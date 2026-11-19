"""Read-only source export, conservative reconciliation, and Salesforce metadata generation."""
import argparse
import datetime as dt
import decimal
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from org_config import local_path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = local_path("PRIVATE_DATA_ROOT")
OLD = local_path("TWENTY_EXPORT_ROOT")
NS = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', NS)

# Stable object-specific prefixes; never reset the existing auto-number sequence.
NUMBER_PREFIXES = {
    'analytics.results': 'RESULT', 'analytics.runs': 'ANALYSIS',
    'market.amcs': 'AMC', 'market.benchmark_assignments': 'BENCH',
    'market.eligibility_policies': 'ELIG', 'market.exit_load_tiers': 'LOAD',
    'market.expense_observations': 'EXPENSE', 'market.fund_portfolio_positions': 'CONSTIT',
    'market.fund_portfolio_snapshots': 'DISCLOSURE', 'market.fund_share_classes': 'CLASS',
    'market.instruments': 'INST', 'market.price_observations': 'PRICE',
    'market.scheme_versions': 'SCHEMEVER', 'market.schemes': 'SCHEME',
    'ops.change_log': 'CHANGE', 'ops.data_issues': 'ISSUE',
    'ops.import_rows': 'IMPORTROW', 'ops.import_runs': 'IMPORT',
    'ops.providers': 'PROVIDER', 'ops.reconciliations': 'RECON',
    'ops.schema_migrations': 'SCHEMAMIG', 'ops.source_documents': 'SOURCE',
    'planning.action_dependencies': 'DEPEND', 'planning.actions': 'ACTION',
    'planning.execution_records': 'EXEC', 'planning.plan_versions': 'PLANVER',
    'planning.plans': 'PLAN', 'planning.review_items': 'REVIEW',
    'planning.targets': 'TARGET', 'portfolio.accounts': 'ACCT',
    'portfolio.cash_entries': 'CASH', 'portfolio.event_charges': 'CHARGE',
    'portfolio.events': 'EVENT', 'portfolio.portfolios': 'PORT',
    'portfolio.position_snapshots': 'POSITION', 'portfolio.sip_evidence': 'SIPEVID',
    'portfolio.sip_versions': 'SIPVER', 'portfolio.unit_entries': 'UNIT',
    'workspace.documents': 'DOC',
}

def object_presentation(table):
    label = table.replace('.', ' ').replace('_', ' ').title()
    plural = 'Planning Executions' if table == 'planning.execution_records' else label
    presentation = {'portfolio.portfolios': ('Portfolio','Portfolios'), 'market.instruments': ('Instrument','Funds'),
                    'portfolio.sip_versions': ('SIP version','SIPs'), 'planning.plans': ('Investment plan','Plans'),
                    'ops.import_runs': ('Statement import','Imports'), 'ops.data_issues': ('Data issue','Data Health')}
    if table in presentation:label,plural=presentation[table]
    return {'label': label, 'pluralLabel': plural,
            'nameField': {'displayFormat': NUMBER_PREFIXES[table]+'-{0000000000}',
                          'label': 'Investment record', 'type': 'AutoNumber'}}

def apply_operational_overlays():
    directory=ROOT/'tools/portfolio'
    if (directory/'package.py').exists():
        sys.path.insert(0,str(directory))
        from package import main as operational_package
        operational_package()

def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary=path.with_name(path.name+'.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str), encoding='utf-8')
    temporary.replace(path)

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'), default=str).encode()).hexdigest()

def sfname(value):
    return ''.join(x.title() for x in value.split('_'))

def xml(path, kind, values):
    node = ET.Element('{'+NS+'}'+kind)
    def add(parent, k, v):
        for item in v if isinstance(v, list) else [v]:
            child = ET.SubElement(parent, '{'+NS+'}'+k)
            if isinstance(item, dict):
                for a,b in item.items(): add(child,a,b)
            else: child.text = str(item).lower() if isinstance(item,bool) else str(item)
    for k,v in values.items(): add(node,k,v)
    ET.indent(node)
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(node).write(path, encoding='UTF-8', xml_declaration=True)

def normalize(v):
    if isinstance(v, (decimal.Decimal,float,int)) and not isinstance(v,bool):
        with decimal.localcontext() as ctx:
            ctx.prec=max(100,len(str(v)))
            return str(decimal.Decimal(str(v)).normalize())
    if isinstance(v, dict): return {k:normalize(x) for k,x in v.items()}
    if isinstance(v,list): return [normalize(x) for x in v]
    if isinstance(v,str):
        try:
            if re.fullmatch(r'-?\d+(\.\d+)?([eE][+-]?\d+)?',v):
                with decimal.localcontext() as ctx:
                    ctx.prec=max(100,len(v))
                    return str(decimal.Decimal(v).normalize())
        except decimal.InvalidOperation: pass
        if re.match(r'^\d{4}-\d\d-\d\dT',v):
            try: return dt.datetime.fromisoformat(v.replace('Z','+00:00')).isoformat()
            except ValueError: pass
    return v

def export(run):
    import psycopg
    from psycopg import sql
    url_path=PRIVATE/'neon-url.tmp'
    with psycopg.connect(url_path.read_text(encoding='utf-8').strip()) as conn:
        conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
        tables=conn.execute("SELECT table_schema,table_name FROM information_schema.tables WHERE table_schema IN ('market','portfolio','planning','analytics','ops') AND table_type='BASE TABLE' ORDER BY 1,2").fetchall()
        rows={}
        for s,t in tables:
            # PostgreSQL serializes numeric values directly, without a float round trip.
            raw=conn.execute(sql.SQL("SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)::text FROM {}.{} t").format(sql.Identifier(s),sql.Identifier(t))).fetchone()[0]
            raw_dir=run/'neon-raw';raw_dir.mkdir(exist_ok=True)
            (raw_dir/(s+'.'+t+'.json')).write_text(raw,encoding='utf-8')
            rows[s+'.'+t]=json.loads(raw,parse_float=str)
        columns=conn.execute("SELECT table_schema,table_name,column_name,data_type,is_nullable,numeric_precision,numeric_scale,character_maximum_length FROM information_schema.columns WHERE table_schema IN ('market','portfolio','planning','analytics','ops') ORDER BY table_schema,table_name,ordinal_position").fetchall()
        constraints=conn.execute("SELECT n.nspname,c.relname,k.conname,k.contype,pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('market','portfolio','planning','analytics','ops') ORDER BY 1,2,3").fetchall()
        routines=conn.execute("SELECT n.nspname,p.proname,pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('market','portfolio','planning','analytics','ops') AND p.prokind='f'").fetchall()
    dump(run/'neon.json',rows); dump(run/'columns.json',columns)
    dump(run/'constraints.json',constraints); dump(run/'routines.json',routines)
    mapping=json.loads((OLD/'object-map.json').read_text(encoding='utf-8'))
    schema='workspace_4487a7uwg9t6pxbxwx015tcnp'
    names=[o['name'] for o in mapping.values()]+['investmentDocument','attachment']
    statements=['BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;']
    for name in names:
        if not re.fullmatch('[A-Za-z0-9]+',name): raise ValueError('Unsafe table name')
        db_name=name if name=='attachment' else '_'+name
        statements.append(f'''SELECT jsonb_build_object('table','{name}','rows',coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb))::text FROM "{schema}"."{db_name}" t;''')
    statements.append('COMMIT;')
    result=subprocess.run(['docker','exec','-i','twenty-local-db-1','psql','-X','-q','-v','ON_ERROR_STOP=1','-U','twenty','-d','twenty','-At'],input='\n'.join(statements),capture_output=True,text=True,encoding='utf-8')
    if result.returncode: raise RuntimeError('Twenty read-only export failed: '+result.stderr[:500])
    twenty={}
    for line in result.stdout.splitlines():
        if line.startswith('{'):
            item=json.loads(line,parse_float=str);twenty[item['table']]=item['rows']
    dump(run/'twenty.json',twenty)
    dump(run/'object-map.json',mapping)
    return rows,twenty,mapping,columns

def reconcile(neon,twenty,mapping):
    canonical={}; conflicts=[]; provenance={}
    identities={}
    def source_key(table,row,record=None):
        if 'id' in row:return str(row['id'])
        if table=='planning.action_dependencies' and 'action_id' in row:return str(row['action_id'])+':'+str(row['prerequisite_id'])
        if 'instrument_id' in row:return str(row['instrument_id'])
        if 'version' in row:return str(row['version'])
        if record:return 'twenty:'+record['id']
        raise ValueError('Unknown primary key: '+table)
    for table,o in mapping.items():
        for record in twenty[o['name']]:
            identities[(table,record['id'])]=source_key(table,record.get('sourceRecord') or {},record)
    for table, records in neon.items():
        o=mapping[table]
        has_source_name=any('name' in row for row in records)
        def key(row):return source_key(table,row)
        by_key={key(r):r for r in records}; seen=set(); canonical[table]=[];provenance[table]={}
        for record in twenty[o['name']]:
            original=record.get('sourceRecord') or {}
            ident=identities[(table,record['id'])]
            if record.get('deletedAt'):
                if ident in by_key: conflicts.append({'table':table,'key':ident,'kind':'twenty_deleted','twentyId':record['id']})
                seen.add(ident);continue
            if ident in seen: raise ValueError('Duplicate identity '+table+':'+ident)
            seen.add(ident)
            effective=dict(original) if ident in by_key else {}
            for field in o['fields']:
                col=field.get('sourceColumn')
                if col:
                    value=record.get(field['name'])
                    if field['type']=='TEXT' and isinstance(original.get(col),(dict,list)) and isinstance(value,str):
                        try:value=json.loads(value)
                        except ValueError:pass
                    effective[col]=value
            # Imported display name is generated for nameless rows, never an economic key.
            if 'name' in original or has_source_name: effective['name']=record.get('name')
            for rel in o['relations']:
                fk=original.get(rel['column']);target=record.get(rel['name']+'Id')
                import uuid
                expected=str(uuid.uuid5(uuid.UUID('b048e32a-6ff4-40d0-a311-81a5ed4bf433'),rel['target']+':'+str(fk))) if fk is not None else None
                if ident in by_key:
                    if target!=expected: conflicts.append({'table':table,'key':ident,'field':rel['column'],'kind':'relationship_changed','twentyTarget':target,'expectedTarget':expected})
                elif target:
                    target_key=identities.get((rel['target'],target))
                    if target_key is None: conflicts.append({'table':table,'key':ident,'field':rel['column'],'kind':'unresolved_twenty_relationship'})
                    effective[rel['column']]=target_key
            baseline=by_key.get(ident)
            if baseline is not None:
                for col in set(baseline)|set(effective):
                    if normalize(baseline.get(col))!=normalize(effective.get(col)):
                        conflicts.append({'table':table,'key':ident,'field':col,'kind':'value_difference','neon':baseline.get(col),'twenty':effective.get(col)})
            elif not original:
                conflicts.append({'table':table,'key':ident,'kind':'missing_source_identity'})
            canonical[table].append({'key':ident,'data':effective,'neon':baseline,'twentyId':record['id'],'sourceRecord':original,'originalTwentyRecord':record})
            provenance[table][ident]={'twentyId':record['id'],'neonPresent':baseline is not None}
        for ident,row in by_key.items():
            if ident not in seen:
                conflicts.append({'table':table,'key':ident,'kind':'missing_from_twenty'})
                canonical[table].append({'key':ident,'data':row,'neon':row,'twentyId':None,'sourceRecord':row})
    return canonical,conflicts,provenance

def generate(mapping,columns):
    dest=ROOT/'force-app/main/default'; manifest={}
    for table,o in mapping.items():
        api='Inv_'+sfname(table.replace('.','_'))+'__c';manifest[table]={'object':api,'fields':{},'relationships':[]}
        if table=='market.price_observations':
            manifest[table]['derivedFields']=[{'field':'KindFilter__c','sourceColumn':'price_kind'},
                {'field':'QualityFilter__c','sourceColumn':'quality_status'}]
        folder=dest/'objects'/api
        xml(folder/(api+'.object-meta.xml'),'CustomObject',{'deploymentStatus':'Deployed','description':'Preserved investment data. Historical calculations are dated snapshots.','enableActivities':False,'enableReports':True,**object_presentation(table),'sharingModel':'Private'})
        fields={
          'MigrationKey__c':{'label':'Migration key','length':100,'externalId':True,'unique':True,'required':True,'type':'Text'},
          'MigrationRun__c':{'label':'Migration run','length':80,'type':'Text'},
          'SourceHash__c':{'label':'Source SHA-256','length':64,'type':'Text'},
          'NeonId__c':{'label':'Original Neon identity','length':255,'type':'Text'},
          'TwentyId__c':{'label':'Original Twenty identity','length':36,'type':'Text'},
          'SourceJson__c':{'label':'Exact source and provenance JSON','length':131072,'visibleLines':3,'type':'LongTextArea'},
          'SnapshotNotice__c':{'label':'Calculation scope','length':255,'type':'Text'}}
        for s,t,col,typ,nullable,precision,scale,length in columns:
            if s+'.'+t!=table:continue
            name=sfname(col)+'__c';spec={'label':col.replace('_',' ').title()}
            if typ=='boolean':spec.update(type='Checkbox',defaultValue='false')
            elif typ=='date':spec.update(type='Date')
            elif typ.startswith('timestamp'):spec.update(type='DateTime')
            elif typ in ('numeric','integer','bigint','smallint','double precision','real'):
                # Exact text is authoritative for financial values; no silent float/scale conversion.
                spec.update(type='Text',length=255)
            elif typ in ('json','jsonb','text','ARRAY') or length is None or length>255:spec.update(type='LongTextArea',length=131072,visibleLines=3)
            else:spec.update(type='Text',length=min(255,length))
            fields[name]=spec;manifest[table]['fields'][col]={'field':name,'sourceType':typ,'nullable':nullable=='YES','exactText':typ in ('numeric','integer','bigint','smallint','double precision','real')}
            if typ=='boolean' and nullable=='YES':
                known=sfname(col)+'Known__c'
                fields[known]={'label':col.replace('_',' ').title()+' Known','type':'Checkbox','defaultValue':'false'}
                manifest[table]['fields'][col]['knownField']=known
            if typ in ('numeric','integer','bigint','smallint','double precision','real'):
                number_name=sfname(col)+'Number__c'
                number_scale=min(16,scale if scale is not None else (0 if typ in ('integer','bigint','smallint') else 10))
                fields[number_name]={'label':col.replace('_',' ').title()+' Numeric','description':'Reporting projection only. Exact source text remains authoritative; values that cannot fit without rounding remain blank.','type':'Number','precision':18,'scale':number_scale}
                manifest[table]['fields'][col].update(numberField=number_name,numberScale=number_scale)
        for rel in o['relations']:
            name=sfname(rel['column'].removesuffix('_id'))+'Ref__c'
            fields[name]={'deleteConstraint':'SetNull' if rel['target']==table else 'Restrict','label':rel['column'].replace('_',' ').title()+' Link','referenceTo':'Inv_'+sfname(rel['target'].replace('.','_'))+'__c','relationshipLabel':sfname(table.replace('.','_'))+' '+sfname(rel['column']),'relationshipName':sfname(table.replace('.','_'))+sfname(rel['column']),'required':False,'type':'Lookup'}
            manifest[table]['relationships'].append({'field':name,'column':rel['column'],'target':rel['target'],'targetColumn':rel['targetColumn']})
        for name,spec in fields.items():xml(folder/'fields'/(name+'.field-meta.xml'),'CustomField',{'fullName':name,**spec})
        xml(folder/'listViews'/'All.listView-meta.xml','ListView',{'fullName':'All','columns':['NAME','MigrationKey__c'],'filterScope':'Everything','label':'All preserved records'})
        xml(dest/'tabs'/(api+'.tab-meta.xml'),'CustomTab',{'customObject':True,'motif':'Custom57: Building Block'})
    for role,editable in [('Inv_Viewer',False),('Inv_MigrationAdmin',True)]:
        values={'applicationVisibilities':{'application':'Investments','visible':True},'label':role.replace('_',' '),'description':'Investment migration phase: read-only preserved records' if not editable else 'Dedicated migration operations; assign only to migration administrators'}
        values['objectPermissions']=[]; values['fieldPermissions']=[]
        navigation=['portfolio.portfolios','market.instruments','portfolio.accounts','portfolio.events','planning.plans','ops.data_issues']
        values['tabSettings']=[{'tab':manifest[t]['object'],'visibility':'Visible'} for t in navigation]
        for obj in manifest.values():
            values['objectPermissions'].append({'allowCreate':editable,'allowDelete':False,'allowEdit':editable,'allowRead':True,'modifyAllRecords':False,'object':obj['object'],'viewAllRecords':True})
            folder=dest/'objects'/obj['object']/'fields'
            for f in sorted(folder.glob('*.field-meta.xml')):
                tree=ET.parse(f).getroot()
                if tree.find('{'+NS+'}required') is not None and tree.find('{'+NS+'}required').text=='true':continue
                values['fieldPermissions'].append({'editable':editable,'field':obj['object']+'.'+f.name.removesuffix('.field-meta.xml'),'readable':True})
        xml(dest/'permissionsets'/(role+'.permissionset-meta.xml'),'PermissionSet',values)
    tabs=[manifest[t]['object'] for t in ['portfolio.portfolios','market.instruments','portfolio.accounts','portfolio.events','planning.plans','ops.data_issues']]
    xml(dest/'applications'/'Investments.app-meta.xml','CustomApplication',{'description':'Core investment records and dated evidence','formFactors':['Large','Small'],'isNavAutoTempTabsDisabled':False,'isNavPersonalizationDisabled':False,'label':'Investments','navType':'Standard','tabs':tabs,'uiType':'Lightning'})
    dump(ROOT/'tools/investment-migration/mapping.json',manifest)
    apply_operational_overlays()
    return manifest

def main():
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);args=p.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-]+',args.run):raise SystemExit('Invalid run name')
    run=PRIVATE/args.run
    if run.exists():raise SystemExit('Run exists; use a new immutable export run')
    run.mkdir(parents=True)
    neon,twenty,mapping,columns=export(run)
    canonical,conflicts,provenance=reconcile(neon,twenty,mapping)
    dump(run/'canonical-provisional.json',canonical);dump(run/'conflicts.json',conflicts);dump(run/'provenance.json',provenance)
    manifest=generate(mapping,columns)
    inventory={'run':args.run,'exportedAt':dt.datetime.now(dt.timezone.utc).isoformat(),'status':'BLOCKED_CONFLICTS' if conflicts else 'READY_FOR_REHEARSAL','sourceCounts':{t:len(r) for t,r in neon.items()},'canonicalCounts':{t:len(r) for t,r in canonical.items()},'twentyCounts':{t:len(r) for t,r in twenty.items()},'conflicts':len(conflicts),'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in run.glob('*.json')}}
    dump(run/'manifest.json',inventory)
    print(json.dumps({'run':args.run,'objects':len(manifest),'neonRows':sum(map(len,neon.values())),'canonicalRows':sum(map(len,canonical.values())),'conflicts':len(conflicts),'status':inventory['status']}))

if __name__=='__main__':main()
