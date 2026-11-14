"""Finish a successful source export without re-reading mutable source records."""
import argparse
import hashlib
import json
import subprocess
import re
import zipfile
from pathlib import Path
import prepare as p

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--run',required=True);args=parser.parse_args()
    run=(p.PRIVATE/args.run).resolve()
    if not run.is_relative_to(p.PRIVATE.resolve()):raise SystemExit('Unsafe path')
    def read(name):return json.loads((run/name).read_text(encoding='utf-8'))
    neon,twenty,mapping,columns=read('neon.json'),read('twenty.json'),read('object-map.json'),read('columns.json')
    raw_twenty=run/'twenty-raw.ndjson'
    if not raw_twenty.exists():
        statements=['BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;']
        for name in [o['name'] for o in mapping.values()]+['investmentDocument']:
            if not re.fullmatch('[A-Za-z0-9]+',name):raise ValueError('Unsafe table name')
            statements.append(f'''SELECT jsonb_build_object('table','{name}','rows',coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb))::text FROM "workspace_4487a7uwg9t6pxbxwx015tcnp"."_{name}" t;''')
        statements.append('COMMIT;')
        output=subprocess.run(['docker','exec','-i','twenty-local-db-1','psql','-X','-q','-v','ON_ERROR_STOP=1','-U','twenty','-d','twenty','-At'],input='\n'.join(statements),capture_output=True,text=True,encoding='utf-8',check=True).stdout
        parsed={r['table']:r['rows'] for r in (json.loads(line,parse_float=str) for line in output.splitlines() if line.startswith('{'))}
        if any(p.digest(parsed[t])!=p.digest(twenty[t]) for t in parsed):raise ValueError('Twenty changed between the source and raw-evidence snapshots')
        raw_twenty.write_text(output,encoding='utf-8')
    canonical,conflicts,provenance=p.reconcile(neon,twenty,mapping)
    docs=[r for r in twenty['investmentDocument'] if not r.get('deletedAt')]
    doccols={'id':'text','name':'text','body':'text','sourceId':'text','sourceUrl':'text','originalEditedAt':'text','createdAt':'timestamp with time zone','updatedAt':'timestamp with time zone','sourceFiles':'jsonb'}
    mapping['workspace.documents']={'name':'investmentDocument','relations':[],'fields':[]}
    for col,typ in doccols.items():columns.append(['workspace','documents',col,typ,'YES',None,None,None])
    canonical['workspace.documents']=[{'key':r['id'],'data':{k:r.get(k) for k in doccols},'sourceRecord':{k:r.get(k) for k in doccols},'neon':None,'twentyId':r['id'],'originalTwentyRecord':r} for r in docs]
    evidence=[]
    server_state=json.loads(subprocess.check_output(['docker','inspect','twenty-local-server-1'],text=True,encoding='utf-8'))[0]
    server_running=server_state['State']['Running']
    helper=['docker','run','--rm','--network','none','--read-only','--user','0','--mount','type=volume,source=twenty-local-uploads,target=/app/packages/twenty-server/.local-storage,readonly','--entrypoint','sh',server_state['Image']]
    for doc in docs:
        for f in doc.get('sourceFiles') or []:
            ident=f['fileId']
            if not re.fullmatch(r'[a-fA-F0-9-]{36}',ident):raise ValueError('Invalid file identity')
            query="SELECT to_jsonb(f)::text FROM core.file f WHERE id='"+ident+"' AND \"deletedAt\" IS NULL"
            out=subprocess.run(['docker','exec','twenty-local-db-1','psql','-X','-q','-v','ON_ERROR_STOP=1','-U','twenty','-d','twenty','-At','-c',query],capture_output=True,text=True,encoding='utf-8',check=True).stdout.strip()
            if not out:raise ValueError('Missing file '+ident)
            info=json.loads(out);relative=Path(info['path'])
            if relative.is_absolute() or '..' in relative.parts:raise ValueError('Unsafe file path')
            dest=run/'files'/ident;dest.parent.mkdir(exist_ok=True)
            storage='/app/packages/twenty-server/.local-storage/'+info['workspaceId']
            command=['find',storage,'-type','f','-name',relative.name]
            if server_running:find_command=['docker','exec','twenty-local-server-1']+command
            else:find_command=helper+['-c','find "$1" -type f -name "$2"','find-files',storage,relative.name]
            found=subprocess.run(find_command,capture_output=True,text=True,check=True).stdout.splitlines()
            found=[x for x in found if x.endswith('/'+relative.as_posix())]
            if len(found)!=1:raise ValueError('File location is missing or ambiguous')
            source=found[0]
            if server_running:subprocess.run(['docker','cp','twenty-local-server-1:'+source,str(dest)],capture_output=True,check=True)
            else:dest.write_bytes(subprocess.run(helper+['-c','cat "$1"','read-file',source],capture_output=True,check=True).stdout)
            body=dest.read_bytes();sha=hashlib.sha256(body).hexdigest()
            if info.get('contentSha256') and sha!=info['contentSha256']:raise ValueError('Source file checksum mismatch')
            if len(body)!=info['size']:raise ValueError('Source file size mismatch')
            evidence.append({'sourceFileId':ident,'documentKey':doc['id'],'name':f['label'],'path':str(dest),'bytes':len(body),'sha256':sha})
    manifest=p.generate(mapping,columns)
    # Oversized JSON/fields become linked Files, never truncated or silently omitted.
    from migrate import encode_value,source_envelope
    for table,rows in canonical.items():
        for row in rows:
            envelope=source_envelope(row)
            values={'SourceJson':json.dumps(envelope,ensure_ascii=False,separators=(',',':'))}
            values.update({col:encode_value(row['data'].get(col),fld) for col,fld in manifest[table]['fields'].items()})
            for field,body in values.items():
                if len(body)<=131072:continue
                sha=hashlib.sha256(body.encode()).hexdigest();dest=run/'files'/sha;dest.write_text(body,encoding='utf-8')
                evidence.append({'targetTable':table,'targetKey':row['key'],'field':field,'name':field+'.json','path':str(dest),'bytes':len(body.encode()),'sha256':sha})
    if (run/'neon-raw').exists():
        archive=run/'files/exact-neon-source.zip'
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
            for f in sorted((run/'neon-raw').glob('*.json')):z.write(f,'tables/'+f.name)
            for name in ['columns.json','constraints.json','routines.json']:z.write(run/name,name)
            z.write(raw_twenty,'twenty-raw.ndjson')
        body=archive.read_bytes()
        evidence.append({'targetTable':'workspace.documents','targetKey':'REDACTED_SOURCE_IDENTIFIER','name':'exact-neon-source.zip','path':str(archive),'bytes':len(body),'sha256':hashlib.sha256(body).hexdigest()})
    p.dump(run/'canonical-provisional.json',canonical);p.dump(run/'conflicts.json',conflicts);p.dump(run/'provenance.json',provenance);p.dump(run/'files.json',evidence)
    evidence_names={'neon.json','twenty.json','columns.json','constraints.json','routines.json','object-map.json','canonical-provisional.json','conflicts.json','provenance.json','files.json'}
    inventory={'run':args.run,'status':'BLOCKED_CONFLICTS' if conflicts else 'READY_FOR_REHEARSAL','conflicts':len(conflicts),'sourceCounts':{t:len(r) for t,r in neon.items()},'canonicalCounts':{t:len(r) for t,r in canonical.items()},'twentyCounts':{t:len(r) for t,r in twenty.items()},'fileBytes':sum(e['bytes'] for e in evidence),'fileCount':len(evidence),'files':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in run.glob('*.json') if f.name in evidence_names}}
    p.dump(run/'manifest.json',inventory)
    print(json.dumps({'objects':len(manifest),'rows':sum(map(len,canonical.values())),'conflicts':len(conflicts),'files':len(evidence),'fileBytes':inventory['fileBytes']}))

if __name__=='__main__':main()
