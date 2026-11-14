"""Resumable Salesforce Bulk 2.0 migration. Private state never enters the repository."""
import argparse
import base64
import csv
import decimal
import datetime as dt
import hashlib
import gzip
import io
import json
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from prepare import PRIVATE, ROOT, digest, dump, normalize

PRODUCTION_ID='LOCAL_SALESFORCE_PRODUCTION_ORG_ID'

class Salesforce:
    def __init__(self,alias):
        p=subprocess.run(['sf.cmd','org','display','--target-org',alias,'--json'],capture_output=True,text=True,encoding='utf-8')
        if p.returncode:raise RuntimeError('Salesforce authentication unavailable; reauthenticate the selected alias')
        result=json.loads(p.stdout)['result']
        self.base=result['instanceUrl'];self.token=result['accessToken']
    def request(self,method,path,data=None,content_type='application/json',raw_response=False):
        payload=(json.dumps(data).encode() if content_type=='application/json' else data.encode()) if data is not None else None
        req=urllib.request.Request(self.base+path,payload,{'Authorization':'Bearer '+self.token,'Content-Type':content_type,'Accept-Encoding':'gzip'},method=method)
        try:
            with urllib.request.urlopen(req,timeout=180) as r:
                raw=r.read()
                if r.headers.get('Content-Encoding')=='gzip':raw=gzip.decompress(raw)
                return json.loads(raw,parse_float=str) if not raw_response and 'json' in r.headers.get('Content-Type','') and raw else raw
        except urllib.error.HTTPError as e:
            # Error bodies can contain record values. Keep them in protected evidence, not stdout.
            evidence=PRIVATE/'errors'/('http-'+str(time.time_ns())+'.json')
            dump(evidence,{'status':e.code,'method':method,'path':path.split('?')[0],'response':e.read().decode(errors='replace')})
            raise RuntimeError(f'Salesforce HTTP {e.code}; protected diagnostic: {evidence}') from None
    def query(self,query):
        result=self.request('GET','/services/data/v68.0/query?q='+urllib.parse.quote(query))
        rows=result['records']
        while not result['done']:
            result=self.request('GET',result['nextRecordsUrl']);rows.extend(result['records'])
        return rows

def key(table,ident):return table+':'+str(ident)

def source_envelope(row):
    return {'canonical':row['data'],'originalTwentySource':row['sourceRecord'],'originalTwentyRecord':row.get('originalTwentyRecord'),'neon':row['neon']}

def canonical_digest(canonical):
    return digest({t:sorted((r['key'],digest(source_envelope(r))) for r in rows) for t,rows in canonical.items()})

def preserve_long_text(value):
    if len(value)<=131072:return value
    return json.dumps({'preservedFileSha256':hashlib.sha256(value.encode()).hexdigest()},separators=(',',':'))

def timestamp_projection(value):
    if value is None:return None
    parsed=dt.datetime.fromisoformat(value.replace('Z','+00:00'))
    if parsed.tzinfo is None:parsed=parsed.replace(tzinfo=dt.timezone.utc)
    # Bulk ingest stores these native DateTime projections at whole-second precision.
    # Exact source subsecond values remain in the verified source JSON envelope.
    return parsed.replace(microsecond=0).astimezone(dt.timezone.utc).isoformat(timespec='seconds')

def ensure_freeze_live():
    state=json.loads((PRIVATE/'freeze-state.json').read_text(encoding='utf-8'))
    age=(dt.datetime.now(dt.timezone.utc)-dt.datetime.fromisoformat(state['heartbeatAt'])).total_seconds()
    if not state.get('active') or state.get('lockedTables',0)<38 or age>60 or (PRIVATE/'release-neon-freeze.flag').exists():raise RuntimeError('Source write freeze is no longer active; production writes stopped')

def encode_value(value,spec):
    if value is None:return '#N/A'
    if spec['sourceType']=='boolean':return 'true' if value else 'false'
    if isinstance(value,(dict,list)):return json.dumps(value,ensure_ascii=False,separators=(',',':'))
    return str(value)

def number_projection(value,scale):
    if value is None:return '#N/A'
    # New Twenty entities have namespaced identities rather than Neon bigint IDs.
    if isinstance(value,str) and value.startswith('twenty:'):return '#N/A'
    number=decimal.Decimal(str(value))
    if not number.is_finite():return '#N/A'
    with decimal.localcontext() as ctx:
        ctx.prec=max(100,len(str(value))+scale)
        unit=decimal.Decimal(1).scaleb(-scale)
        rounded=number.quantize(unit)
        return str(number) if rounded==number and abs(number)<decimal.Decimal(10)**(18-scale) else '#N/A'

def records(table,rows,spec,run_id,links=False,id_map=None):
    result=[]
    for row in rows:
        record={'MigrationKey__c':key(table,row['key'])}
        if links:
            for rel in spec['relationships']:
                value=row['data'].get(rel['column'])
                if value is None:record[rel['field']]='#N/A';continue
                target=key(rel['target'],value)
                if target not in id_map:raise ValueError('Unresolved relationship '+target)
                record[rel['field']]=id_map[target]
        else:
            original=source_envelope(row)
            body=json.dumps(original,ensure_ascii=False,separators=(',',':'))
            record.update(MigrationRun__c=run_id,NeonId__c=str(row['key']) if row['neon'] is not None else '#N/A',TwentyId__c=row['twentyId'] or '#N/A',SourceHash__c=digest(original),SourceJson__c=preserve_long_text(body),SnapshotNotice__c='Preserved source data; calculated results are dated snapshots, not live recalculations.')
            for col,fld in spec['fields'].items():
                value=encode_value(row['data'].get(col),fld)
                if fld['sourceType']=='boolean' and value=='#N/A':value='false'
                record[fld['field']]=preserve_long_text(value)
                if fld.get('numberField'):record[fld['numberField']]=number_projection(row['data'].get(col),fld['numberScale'])
                if fld.get('knownField'):record[fld['knownField']]='true' if row['data'].get(col) is not None else 'false'
        result.append(record)
    return result

def bulk(sf,run,table,spec,rows,phase):
    if not rows:return
    if getattr(sf,'production',False):ensure_freeze_live()
    print(phase,table,len(rows),flush=True)
    directory=run/'salesforce'/phase/table;directory.mkdir(parents=True,exist_ok=True)
    stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=list(rows[0]),lineterminator='\n');writer.writeheader();writer.writerows(rows)
    payload=stream.getvalue();fingerprint=hashlib.sha256(payload.encode()).hexdigest();state_file=directory/'job.json'
    state=json.loads(state_file.read_text(encoding='utf-8')) if state_file.exists() else None
    if state and state['fingerprint']!=fingerprint:
        old=sf.request('GET','/services/data/v68.0/jobs/ingest/'+state['id'])
        if old['state'] not in ('JobComplete','Failed','Aborted') or (old['state']=='JobComplete' and not old.get('numberRecordsFailed')):raise ValueError('Checkpoint payload changed; start a new migration run')
        dump(directory/('superseded-job-'+state['id']+'.json'),{'checkpoint':state,'status':old});state=None
    if not state:
        job=sf.request('POST','/services/data/v68.0/jobs/ingest',{'object':spec['object'],'operation':'upsert','externalIdFieldName':'MigrationKey__c','contentType':'CSV','lineEnding':'LF'})
        state={'id':job['id'],'fingerprint':fingerprint,'org':sf.base};dump(state_file,state)
    if state['org']!=sf.base:raise ValueError('Checkpoint belongs to a different org')
    path='/services/data/v68.0/jobs/ingest/'+state['id']
    status=sf.request('GET',path)
    if status['state']=='JobComplete' and not status.get('numberRecordsFailed',0) and status.get('numberRecordsProcessed')==len(rows) and all((directory/(e+'.csv')).exists() for e in ('successfulResults','failedResults','unprocessedrecords')):
        print('Reused completed job',table,len(rows),flush=True)
        return
    if status['state']=='Failed' and status.get('numberRecordsProcessed',0)==0 and status.get('numberRecordsFailed',0)==0:
        dump(directory/('failed-job-'+state['id']+'.json'),{'checkpoint':state,'status':status})
        job=sf.request('POST','/services/data/v68.0/jobs/ingest',{'object':spec['object'],'operation':'upsert','externalIdFieldName':'MigrationKey__c','contentType':'CSV','lineEnding':'LF'})
        state={'id':job['id'],'fingerprint':fingerprint,'org':sf.base};dump(state_file,state)
        path='/services/data/v68.0/jobs/ingest/'+state['id'];status=sf.request('GET',path)
    if status['state']=='Open':
        sf.request('PUT',path+'/batches',payload,'text/csv');sf.request('PATCH',path,{'state':'UploadComplete'})
    deadline=time.monotonic()+900
    while status['state'] not in ('JobComplete','Failed','Aborted'):
        if time.monotonic()>deadline:raise RuntimeError('Job remains active; resume the same command later')
        time.sleep(3);status=sf.request('GET',path)
    dump(directory/'status.json',status)
    job_directory=directory/'jobs'/state['id'];job_directory.mkdir(parents=True,exist_ok=True)
    dump(job_directory/'status.json',status)
    for endpoint in ('successfulResults','failedResults','unprocessedrecords'):
        body=sf.request('GET',path+'/'+endpoint)
        (directory/(endpoint+'.csv')).write_bytes(body)
        (job_directory/(endpoint+'.csv')).write_bytes(body)
    if status['state']!='JobComplete' or status.get('numberRecordsFailed',0):raise RuntimeError('Bulk job has failed rows; inspect protected reports before retrying')
    print('Verified job',table,status.get('numberRecordsProcessed',0),flush=True)

def verify(sf,run,mapping,canonical):
    report={};id_map={}
    for table,spec in mapping.items():
        fields=['Id','MigrationKey__c','SourceHash__c','SourceJson__c']+[f['field'] for f in spec['fields'].values()]+[f['numberField'] for f in spec['fields'].values() if f.get('numberField')]+[f['knownField'] for f in spec['fields'].values() if f.get('knownField')]+[r['field'] for r in spec['relationships']]
        actual=sf.query('SELECT '+','.join(fields)+' FROM '+spec['object'])
        by_key={r['MigrationKey__c']:r for r in actual}
        for row in canonical[table]:
            ident=key(table,row['key']);target=by_key.get(ident)
            if not target:raise ValueError('Missing migrated identity '+ident)
            original=source_envelope(row)
            expected_source=preserve_long_text(json.dumps(original,ensure_ascii=False,separators=(',',':')))
            if target['SourceHash__c']!=digest(original) or target['SourceJson__c']!=expected_source:raise ValueError('Source JSON mismatch '+ident)
            for col,fld in spec['fields'].items():
                want=preserve_long_text(encode_value(row['data'].get(col),fld));want=None if want=='#N/A' else want
                value=target.get(fld['field'])
                # Native long text trims trailing whitespace; the exact original is in SourceJson.
                if isinstance(want,str) and isinstance(value,str):want=want.rstrip();value=value.rstrip()
                if fld['sourceType']=='boolean':value='true' if value else 'false';want=want or 'false'
                if want is not None and fld['sourceType'].startswith('timestamp'):
                    if timestamp_projection(value)!=timestamp_projection(want):raise ValueError('Timestamp mismatch '+ident+':'+col)
                elif value!=want:raise ValueError('Typed field mismatch '+ident+':'+col)
                if fld.get('numberField'):
                    projected=number_projection(row['data'].get(col),fld['numberScale'])
                    if normalize(target.get(fld['numberField']))!=normalize(None if projected=='#N/A' else projected):raise ValueError('Numeric projection mismatch '+ident+':'+col)
                if fld.get('knownField') and target.get(fld['knownField'])!=(row['data'].get(col) is not None):raise ValueError('Boolean known-state mismatch '+ident+':'+col)
            id_map[ident]=target['Id']
        report[table]={'expected':len(canonical[table]),'matched':len(canonical[table]),'existingTotal':len(actual)}
        print('Read-back verified',table,len(canonical[table]),flush=True)
    for table,spec in mapping.items():
        if not spec['relationships']:continue
        actual={r['MigrationKey__c']:r for r in sf.query('SELECT MigrationKey__c,'+','.join(r['field'] for r in spec['relationships'])+' FROM '+spec['object'])}
        for row in canonical[table]:
            for rel in spec['relationships']:
                value=row['data'].get(rel['column']);want=id_map[key(rel['target'],value)] if value is not None else None
                if actual[key(table,row['key'])].get(rel['field'])!=want:raise ValueError('Relationship mismatch')
    dump(run/'salesforce/verification.json',{'tables':report,'status':'STRUCTURED_DATA_VERIFIED','filesVerified':False})

def files(sf,run):
    mapping=json.loads((ROOT/'tools/investment-migration/mapping.json').read_text(encoding='utf-8'))
    document_ids={}
    evidence=[]
    for item in json.loads((run/'files.json').read_text(encoding='utf-8')):
        if getattr(sf,'production',False):ensure_freeze_live()
        body=Path(item['path']).read_bytes()
        if hashlib.sha256(body).hexdigest()!=item['sha256']:raise ValueError('Local file changed')
        title='InvEvidence_'+item['sha256']
        readable_title=item['name'][:150]+' ['+item['sha256']+']'
        versions=sf.query("SELECT Id,ContentDocumentId,Title FROM ContentVersion WHERE IsLatest=true AND (Title='"+title+"' OR Title LIKE '% ["+item['sha256']+"]')")
        if len(versions)>1:raise ValueError('Duplicate content hash files require review')
        if not versions:
            receipt=sf.request('POST','/services/data/v68.0/sobjects/ContentVersion',{'Title':readable_title,'PathOnClient':item['name'],'Description':'Investment evidence SHA256 '+item['sha256'],'VersionData':base64.b64encode(body).decode()})
            dump(run/'salesforce/files'/('created-'+receipt['id']+'.json'),{'id':receipt['id'],'sha256':item['sha256']})
            versions=sf.query("SELECT Id,ContentDocumentId,Title FROM ContentVersion WHERE Id='"+receipt['id']+"'")
        if versions[0]['Title']!=readable_title:sf.request('PATCH','/services/data/v68.0/sobjects/ContentVersion/'+versions[0]['Id'],{'Title':readable_title})
        table=item.get('targetTable','workspace.documents');target_key=item.get('targetKey',item.get('documentKey'))
        if table not in document_ids:document_ids[table]={r['MigrationKey__c']:r['Id'] for r in sf.query('SELECT Id,MigrationKey__c FROM '+mapping[table]['object'])}
        version=versions[0];doc_id=document_ids[table][key(table,target_key)]
        links=sf.query("SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId='"+version['ContentDocumentId']+"' AND LinkedEntityId='"+doc_id+"'")
        if not links:
            # Custom-record links use the record's sharing; this creates no public file URL.
            receipt=sf.request('POST','/services/data/v68.0/sobjects/ContentDocumentLink',{'ContentDocumentId':version['ContentDocumentId'],'LinkedEntityId':doc_id,'ShareType':'V'})
            dump(run/'salesforce/files'/('link-'+receipt['id']+'.json'),receipt)
        downloaded=sf.request('GET','/services/data/v68.0/sobjects/ContentVersion/'+version['Id']+'/VersionData',raw_response=True)
        if hashlib.sha256(downloaded).hexdigest()!=item['sha256']:raise ValueError('Uploaded file checksum mismatch')
        evidence.append({**item,'contentVersionId':version['Id'],'contentDocumentId':version['ContentDocumentId'],'linkedEntityId':doc_id,'verified':True})
    dump(run/'salesforce/files/verification.json',evidence)

def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=['preflight','load','verify','files']);p.add_argument('--target-org',required=True);p.add_argument('--run',required=True);args=p.parse_args()
    run=(PRIVATE/args.run).resolve()
    if not run.is_relative_to(PRIVATE.resolve()):raise SystemExit('Unsafe run path')
    sf=Salesforce(args.target_org);org=sf.query('SELECT Id,Name,OrganizationType,IsSandbox FROM Organization')[0]
    sf.production=not org['IsSandbox']
    if sf.production and org['Id']!=PRODUCTION_ID:raise SystemExit('Unexpected production org')
    mapping=json.loads((ROOT/'tools/investment-migration/mapping.json').read_text(encoding='utf-8'));manifest=json.loads((run/'manifest.json').read_text(encoding='utf-8'))
    for name,expected in manifest['files'].items():
        source=(run/name).resolve()
        if not source.is_relative_to(run) or hashlib.sha256(source.read_bytes()).hexdigest()!=expected:raise SystemExit('Source evidence changed; prepare a new reviewed run')
    limits=sf.request('GET','/services/data/v68.0/limits')
    total=sum(manifest['canonicalCounts'].values());required_mb=total*2048/1024/1024*1.25
    completed=0
    for table,count in manifest['canonicalCounts'].items():
        status_file=run/'salesforce/records'/table/'status.json'
        if status_file.exists():
            state=json.loads(status_file.read_text(encoding='utf-8'))
            if state.get('state')=='JobComplete' and not state.get('numberRecordsFailed'):completed+=min(count,state.get('numberRecordsProcessed',0))
    additional_mb=max(0,total-completed)*2048/1024/1024*1.25
    required_files_mb=manifest.get('fileBytes',0)/1024/1024*1.25
    preflight={'orgId':org['Id'],'edition':org['OrganizationType'],'sandbox':org['IsSandbox'],'structuredDataEstimateMB':required_mb,'fileStorageEstimateMB':required_files_mb,'availableDataMB':limits['DataStorageMB']['Remaining'],'availableFileMB':limits['FileStorageMB']['Remaining'],'conflicts':manifest['conflicts']}
    dump(run/('preflight-'+args.target_org+'.json'),preflight)
    if args.command=='preflight':print(json.dumps(preflight));return
    if manifest['conflicts']:raise SystemExit('Unresolved source conflicts: loading is blocked')
    if args.command=='load' and additional_mb>limits['DataStorageMB']['Remaining']:raise SystemExit('Insufficient data storage headroom')
    if args.command=='files' and required_files_mb>limits['FileStorageMB']['Remaining']:raise SystemExit('Insufficient file storage headroom')
    if not org['IsSandbox'] and args.command!='verify':
        if org['Id']!=PRODUCTION_ID:raise SystemExit('Unexpected production org')
        approval=run/'production-approval.json'
        if not approval.exists():raise SystemExit('Production requires a verified sandbox rehearsal, approved source freeze, verified files, and explicit production approval evidence')
        gate=json.loads(approval.read_text(encoding='utf-8'))
        if gate['organizationId']!=PRODUCTION_ID or not gate.get('userAuthorizedImplementation'):raise SystemExit('Production authorization does not match target')
        if dt.datetime.now(dt.timezone.utc)>dt.datetime.fromisoformat(gate['expiresAt']):raise SystemExit('Cutover window expired; recheck sources and rehearsal evidence')
        candidate=json.loads((run/'canonical-provisional.json').read_text(encoding='utf-8'))
        if canonical_digest(candidate)!=gate['canonicalDigest']:raise SystemExit('Production dataset differs from the rehearsed dataset')
        proof_path=Path(gate['sandboxVerification']);file_path=Path(gate['sandboxFilesVerification'])
        if hashlib.sha256(proof_path.read_bytes()).hexdigest()!=gate['sandboxVerificationSha256'] or hashlib.sha256(file_path.read_bytes()).hexdigest()!=gate['sandboxFilesSha256']:raise SystemExit('Rehearsal evidence changed')
        proof=json.loads(proof_path.read_text(encoding='utf-8'));proof_files=json.loads(file_path.read_text(encoding='utf-8'))
        if proof['status']!='STRUCTURED_DATA_VERIFIED' or any(r['expected']!=r['matched'] or r['existingTotal']!=r['expected'] for r in proof['tables'].values()):raise SystemExit('Sandbox reconciliation incomplete')
        if not all(f['verified'] for f in proof_files):raise SystemExit('Sandbox file verification incomplete')
        expected_files=json.loads((run/'files.json').read_text(encoding='utf-8'))
        if sorted(f['sha256'] for f in expected_files)!=sorted(f['sha256'] for f in proof_files):raise SystemExit('Final files differ from rehearsed files')
        if args.command in ('load','files'):
            ensure_freeze_live()
            frozen=json.loads(subprocess.check_output(['docker','inspect','twenty-local-server-1','twenty-local-worker-1'],text=True,encoding='utf-8'))
            if any(c['State']['Running'] for c in frozen) or (PRIVATE/'release-neon-freeze.flag').exists():raise SystemExit('Source freeze is no longer in effect')
    canonical=json.loads((run/'canonical-provisional.json').read_text(encoding='utf-8'))
    if args.command=='verify':verify(sf,run,mapping,canonical);print('Structured record and relationship verification passed; file acceptance is separate');return
    if args.command=='files':files(sf,run);print('Files uploaded, linked and hash-verified');return
    # Before-images and exact IDs are the recovery boundary; no broad delete exists here.
    for table,spec in mapping.items():
        before=run/'salesforce/before-images'/(table+'.json')
        if not before.exists():
            description=sf.request('GET','/services/data/v68.0/sobjects/'+spec['object']+'/describe')
            fields=[f['name'] for f in description['fields'] if f['type'] not in ('address','location')]
            dump(before,sf.query('SELECT '+','.join(fields)+' FROM '+spec['object']))
        bulk(sf,run,table,spec,records(table,canonical[table],spec,args.run),'records')
    id_map={}
    for spec in mapping.values():
        for row in sf.query('SELECT Id,MigrationKey__c FROM '+spec['object']):id_map[row['MigrationKey__c']]=row['Id']
    dump(run/'salesforce/id-map.json',id_map)
    for table,spec in mapping.items():
        if spec['relationships']:bulk(sf,run,table,spec,records(table,canonical[table],spec,args.run,True,id_map),'relationships')
    verify(sf,run,mapping,canonical)
    print('Structured migration verified for',org['Id'],'; document/file and owner acceptance are recorded separately')

if __name__=='__main__':main()
