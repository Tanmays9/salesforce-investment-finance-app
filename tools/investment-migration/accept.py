"""Read-only technical acceptance and scoped recovery manifest generation."""
import argparse
import csv
import datetime as dt
import hashlib
import json
from pathlib import Path
from migrate import Salesforce,PRODUCTION_ID
from prepare import PRIVATE,ROOT,dump

def main():
    p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);p.add_argument('--run',required=True);args=p.parse_args()
    run=(PRIVATE/args.run).resolve()
    if not run.is_relative_to(PRIVATE.resolve()):raise ValueError('Unsafe run directory')
    read=lambda path:json.loads(path.read_text(encoding='utf-8-sig'))
    manifest=read(run/'manifest.json');proof=read(run/'salesforce/verification.json');files=read(run/'salesforce/files/verification.json')
    assert proof['status']=='STRUCTURED_DATA_VERIFIED'
    assert all(x['expected']==x['matched']==x['existingTotal'] for x in proof['tables'].values())
    assert sum(x['matched'] for x in proof['tables'].values())==sum(manifest['canonicalCounts'].values())
    assert len(files)==manifest['fileCount'] and all(x['verified'] for x in files)
    assert sorted(x['sha256'] for x in files)==sorted(x['sha256'] for x in read(run/'files.json'))
    sf=Salesforce(args.target_org);org=sf.query('SELECT Id,IsSandbox FROM Organization')[0]
    assert org['Id']==PRODUCTION_ID and not org['IsSandbox']
    for name in ['production-investment-deployment.json','production-native-views.json','production-access-test-files.json']:
        assert read(PRIVATE/name)['result']['status']=='Succeeded',name
    layout=sf.request('GET','/services/data/v68.0/sobjects/Inv_MarketInstruments__c/describe/layouts')
    fields=[]
    for item in layout['layouts']:
        for section in item['detailLayoutSections']:
            for row in section['layoutRows']:
                for cell in row['layoutItems']:
                    fields.extend(c['value'] for c in cell['layoutComponents'] if c['type']=='Field')
    assert {'Name__c','SourceJson__c','SourceHash__c','MigrationKey__c'}.issubset(fields),'Native detail fields missing'
    related=sf.request('GET','/services/data/v68.0/ui-api/related-list-info/Inv_WorkspaceDocuments__c')
    assert any(r.get('id')=='AttachedContentDocuments' or r.get('label')=='Files' for r in related['relatedLists']),'Native Files list missing'
    global_schema=sf.request('GET','/services/data/v68.0/sobjects')
    smoke={'globalDescribe':'passed','organizationIdentity':'passed'}
    accessible={r['name'] for r in global_schema['sobjects'] if r['queryable']}
    for obj in ['Invoice__c','InvoiceItem__c','Invoice','InvoiceItem']:
        if obj in accessible:sf.query('SELECT COUNT() FROM '+obj);smoke[obj]='read_query_succeeded'
    app=sf.query("SELECT DurableId FROM AppDefinition WHERE DeveloperName='Investments'")[0]['DurableId']
    tab_sets=sf.request('GET','/services/data/v68.0/tabs')
    visible_tabs={t['name'] for t in tab_sets}
    required_tabs={'Inv_PortfolioPortfolios__c','Inv_MarketInstruments__c','Inv_PortfolioAccounts__c','Inv_PortfolioEvents__c','Inv_PlanningPlans__c','Inv_OpsDataIssues__c'}
    assert required_tabs.issubset(visible_tabs),'Investment navigation tabs are not visible to the current user'
    mapping=read(ROOT/'tools/investment-migration/mapping.json')
    recovery={};total_created=0
    csv.field_size_limit(16*1024*1024)
    for table,spec in mapping.items():
        before=read(run/'salesforce/before-images'/(table+'.json'))
        result=run/'salesforce/records'/table/'successfulResults.csv'
        created=[]
        if result.exists():
            with result.open(encoding='utf-8-sig',newline='') as f:
                for row in csv.DictReader(f):
                    if row['sf__Created'].lower()=='true':created.append(row['sf__Id'])
        recovery[table]={'object':spec['object'],'createdIds':created,'beforeImagePath':str(run/'salesforce/before-images'/(table+'.json')),'existingBefore':len(before)}
        total_created+=len(created)
    assert total_created==sum(manifest['canonicalCounts'].values()),'Created-ID recovery coverage is incomplete'
    dump(run/'recovery-manifest.json',{'organizationId':PRODUCTION_ID,'tables':recovery,'files':[{'contentDocumentId':r['contentDocumentId'],'contentVersionId':r['contentVersionId'],'sha256':r['sha256']} for r in files],'deletionExecuted':False})
    final={'status':'TECHNICALLY_VERIFIED','technicalSignoff':'Codex automated field, relationship, file and access verification','ownerAcceptance':'Pending owner review; no human signature is claimed','verifiedAt':dt.datetime.now(dt.timezone.utc).isoformat(),'organizationId':PRODUCTION_ID,'appUrl':sf.base+'/lightning/app/'+app,'recordsVerified':total_created,'objects':len(mapping),'relationshipDefinitions':sum(len(x['relationships']) for x in mapping.values()),'relationshipFieldChecks':sum(len(mapping[t]['relationships'])*proof['tables'][t]['matched'] for t in mapping),'evidenceFilesVerified':len(files),'evidenceBytes':sum(x['bytes'] for x in files),'duplicateMigratedRecords':0,'originalConflicts':manifest['conflicts'],'sourceSnapshotRun':args.run,'unrelatedSmokeChecks':smoke,'nativeDetailFieldsVerified':len(fields),'nativeFilesListVerified':True,'sourceRetention':'Twenty and Neon retained; no ongoing synchronization','limits':['Native DateTime projections use whole-second bulk precision; exact timestamps and JSON types are retained in source envelopes and raw-source archive.','PostgreSQL posting/calculation procedures are preserved as evidence, not ported to a writable Salesforce accounting engine.']}
    final['navigationTabsVerified']=sorted(required_tabs)
    dump(run/'final-reconciliation.json',final)
    print(json.dumps({k:final[k] for k in ['status','appUrl','recordsVerified','objects','relationshipDefinitions','evidenceFilesVerified']}))

if __name__=='__main__':main()
