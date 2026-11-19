"""Create a production evidence-only statement review after a unique history match."""
import argparse,base64,collections,hashlib,json,subprocess,sys
from pathlib import Path
import casparser
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'investment-migration'))
from org_config import org_alias_for_stage, org_id_for_stage
from migrate import Salesforce
from prepare import PRIVATE
from normalise import normalise,exact

def main():
    p=argparse.ArgumentParser();p.add_argument('--file',required=True);args=p.parse_args();s=Salesforce(org_alias_for_stage('production'))
    if s.query('SELECT Id,IsSandbox FROM Organization')[0]['Id']!=org_id_for_stage('production'):raise RuntimeError('Production statement staging requires the verified production alias')
    path=Path(args.file);content=path.read_bytes();digest=hashlib.sha256(content).hexdigest()
    payload=normalise(json.loads(casparser.read_cas_pdf(str(path),'',output='json')),digest)
    portfolios=s.query('SELECT Id FROM Inv_PortfolioPortfolios__c')
    if len(portfolios)!=1:raise RuntimeError('A unique destination portfolio is required')
    portfolio=portfolios[0]['Id'];accounts={row['Id']:row for row in s.query("SELECT Id,CASScopeKey__c FROM Inv_PortfolioAccounts__c WHERE PortfolioRef__c='"+portfolio+"'")}
    reversed={row['ReversesRef__c'] for row in s.query('SELECT ReversesRef__c FROM Inv_PortfolioEvents__c WHERE ReversesRef__c!=null AND PostedAt__c!=null')}
    ledger=s.query("SELECT AccountRef__c,InstrumentRef__c,InstrumentRef__r.Isin__c,UnitsDelta__c,ConsiderationAmount__c,EventRef__c,EventRef__r.EventDate__c,EventRef__r.EventType__c FROM Inv_PortfolioUnitEntries__c WHERE AccountRef__r.PortfolioRef__c='"+portfolio+"' AND EventRef__r.PostedAt__c!=null")
    matched={};event_keys={};event_counts=collections.Counter()
    for row in ledger:
        e=row['EventRef__r']
        if row['EventRef__c'] in reversed or e['EventType__c']=='reversal':continue
        token=(e['EventDate__c'],e['EventType__c'],exact(row['UnitsDelta__c']),exact(row['ConsiderationAmount__c']))
        key=(row['AccountRef__c'],row['InstrumentRef__c'],row['InstrumentRef__r']['Isin__c'])
        matched.setdefault(key,collections.Counter())[token]+=1;event_counts[row['EventRef__c']]+=1
        event_keys[row['EventRef__c']]=hashlib.sha256('|'.join([row['AccountRef__c'],row['InstrumentRef__c'],*token]).encode()).hexdigest()
    scopes=[]
    for scope in payload['scopes']:
        incoming=collections.Counter((t['tradeDate'],t['kind'],exact(t['units']),exact(t['amount'])) for t in scope['transactions'])
        candidates=[key for key,values in matched.items() if key[2]==scope['isin'] and values==incoming]
        if len(candidates)!=1 or not incoming:raise RuntimeError('Production CAS history is not a unique, complete existing-only match')
        account,fund,_=candidates[0]
        if account not in accounts or accounts[account]['CASScopeKey__c'] not in [None,scope['scopeKey']]:raise RuntimeError('Production account identity conflicts with the statement')
        scopes.append({'attributes':{'type':'Inv_PortfolioAccounts__c'},'Id':account,'CASScopeKey__c':scope['scopeKey']})
    updates=scopes+[{'attributes':{'type':'Inv_PortfolioEvents__c'},'Id':event,'EconomicKey__c':key} for event,key in event_keys.items() if event_counts[event]==1]
    for start in range(0,len(updates),200):
        results=s.request('PATCH','/services/data/v68.0/composite/sobjects',{'allOrNone':True,'records':updates[start:start+200]})
        if not all(row['success'] for row in results):raise RuntimeError('Identity preparation failed; no transactions were posted')
    directory=PRIVATE/'cas-production-review';directory.mkdir(exist_ok=True)
    existing=[row for row in s.query("SELECT ContentDocumentId,Checksum FROM ContentVersion WHERE IsLatest=true AND FileType='PDF'") if row['Checksum']==hashlib.md5(content).hexdigest()]
    if existing:document=existing[0]['ContentDocumentId']
    else:
        version=s.request('POST','/services/data/v68.0/sobjects/ContentVersion',{'Title':'CAMS statement for reconciliation','PathOnClient':path.name,
            'VersionData':base64.b64encode(content).decode(),'FirstPublishLocationId':portfolio})['id']
        document=s.query("SELECT ContentDocumentId FROM ContentVersion WHERE Id='"+version+"'")[0]['ContentDocumentId']
    result=s.request('POST','/services/data/v68.0/actions/custom/apex/InvImportActions',{'inputs':[{'operation':'create','portfolioId':portfolio,'documentIds':[document]}]})
    if not result[0]['isSuccess']:raise RuntimeError('Could not create production statement review')
    run=result[0]['outputValues']['runId'];(directory/'run.json').write_text(json.dumps({'runId':run,'sha256':digest,'scopes':len(scopes),'matchedEvents':len(event_keys),'baselineLedgerRows':len(ledger)},indent=2))
    apex=directory/'submit.apex';apex.write_text("System.debug(LoggingLevel.INFO, InvImportActions.submit('"+run+"',null));")
    response=subprocess.run(['sf.cmd','apex','run','--file',str(apex),'--target-org',org_alias_for_stage('production'),'--json'],capture_output=True,text=True,encoding='utf-8')
    (directory/'submit.json').write_text(response.stdout)
    if response.returncode:raise RuntimeError('Production parser submission failed; inspect protected report')
    print(json.dumps({'statementStaged':True,'scopesProvenExisting':len(scopes),'candidateExistingEvents':len(event_keys),'transactionsPosted':0,'runId':run}))

if __name__=='__main__':main()
