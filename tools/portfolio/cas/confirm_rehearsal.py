"""Sandbox-only confirmation of a proven existing-only statement; resumable by account."""
import argparse,hashlib,json,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'investment-migration'))
from migrate import Salesforce
from prepare import PRIVATE

def ledger(s):
    result={}
    for name,fields in {
        'Inv_PortfolioUnitEntries__c':'Id,MigrationKey__c,AccountRef__c,InstrumentRef__c,EventRef__c,UnitsDelta__c,AcquisitionCost__c,ConsiderationAmount__c,SourceNav__c,AcquisitionDate__c,Currency__c',
        'Inv_PortfolioEvents__c':'Id,MigrationKey__c,EventDate__c,EventType__c,SourceSequence__c,PostedAt__c,ReversesRef__c'
    }.items():
        rows=s.query('SELECT '+fields+' FROM '+name+' ORDER BY Id')
        for row in rows:row.pop('attributes',None)
        result[name]={'count':len(rows),'sha256':hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);p.add_argument('--run',required=True);args=p.parse_args();s=Salesforce(args.target_org)
    if s.query('SELECT Id FROM Organization')[0]['Id']!='LOCAL_SALESFORCE_SANDBOX_ORG_ID':raise RuntimeError('This acceptance rehearsal is sandbox-only')
    rows=s.query("SELECT Id,RowKind__c,MatchStatus__c FROM Inv_OpsImportRows__c WHERE RunRef__c='"+args.run+"'")
    summaries=[row for row in rows if row['RowKind__c']=='Account']
    if not summaries or any(row['MatchStatus__c'] not in ['Mapped','Confirmed'] if row['RowKind__c']=='Account' else row['MatchStatus__c']!='Existing' for row in rows):raise RuntimeError('Only fully reconciled, existing-only statements can use this rehearsal')
    directory=PRIVATE/'cas-rehearsal';path=directory/'confirmation.json'
    report=json.loads(path.read_text()) if path.exists() else {'runId':args.run,'before':ledger(s),'confirmed':[]}
    if report['runId']!=args.run:raise RuntimeError('Use a separate rehearsal evidence directory for another run')
    for row in summaries:
        if row['MatchStatus__c']!='Confirmed':
            result=s.request('POST','/services/data/v68.0/actions/custom/apex/InvImportActions',{'inputs':[{'operation':'confirm','summaryId':row['Id']}]})
            if not result[0]['isSuccess']:
                (directory/'confirm-failure.json').write_text(json.dumps(result));raise RuntimeError('Confirmation failed; inspect protected report')
        if row['Id'] not in report['confirmed']:report['confirmed'].append(row['Id'])
        path.write_text(json.dumps(report,indent=2));print('Verified account '+str(len(report['confirmed']))+'/'+str(len(summaries)),flush=True)
    result=s.request('POST','/services/data/v68.0/actions/custom/apex/InvImportActions',{'inputs':[{'operation':'confirm','summaryId':summaries[0]['Id']}]})
    if not result[0]['isSuccess']:raise RuntimeError('Repeat confirmation was not idempotent')
    report['after']=ledger(s);report['ledgerUnchanged']=report['before']==report['after'];report['repeatConfirmationSucceeded']=True
    report['status']=s.query("SELECT OperationalStatus__c FROM Inv_OpsImportRuns__c WHERE Id='"+args.run+"'")[0]['OperationalStatus__c']
    path.write_text(json.dumps(report,indent=2))
    if not report['ledgerUnchanged'] or report['status']!='Complete':raise RuntimeError('Rehearsal reconciliation failed')
    print(json.dumps({'accountsConfirmed':len(summaries),'ledgerUnchanged':True,'repeatConfirmationSucceeded':True,'status':report['status']}))

if __name__=='__main__':main()
