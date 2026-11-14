"""Seed CAS identities only after unique full-history matches; submit a sandbox import.

No transaction is posted by this script. A fresh parser job must classify the
historical statement as Existing before confirmation can be rehearsed separately.
"""
import argparse,collections,hashlib,json,sys,subprocess,base64,time
from pathlib import Path
import casparser
from normalise import normalise,exact
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'investment-migration'))
from migrate import Salesforce
from prepare import PRIVATE

def main():
 p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);p.add_argument('--file',required=True);p.add_argument('--submit',action='store_true');args=p.parse_args()
 s=Salesforce(args.target_org);org=s.query('SELECT Id,IsSandbox FROM Organization')[0]
 if not org['IsSandbox'] or org['Id']!='LOCAL_SALESFORCE_SANDBOX_ORG_ID':raise RuntimeError('Rehearsal is restricted to the verified investment sandbox')
 path=Path(args.file);content=path.read_bytes();payload=normalise(json.loads(casparser.read_cas_pdf(str(path),'',output='json')),hashlib.sha256(content).hexdigest())
 portfolios=s.query('SELECT Id FROM Inv_PortfolioPortfolios__c')
 if len(portfolios)!=1:raise RuntimeError('Select a portfolio explicitly before running a multi-portfolio rehearsal')
 portfolio=portfolios[0]['Id'];user=s.request('GET','/services/oauth2/userinfo')['user_id']
 for name in ['Inv_Viewer','Inv_PortfolioManager']:
  permission=s.query("SELECT Id FROM PermissionSet WHERE Name='"+name+"'")[0]['Id']
  if not s.query("SELECT Id FROM PermissionSetAssignment WHERE AssigneeId='"+user+"' AND PermissionSetId='"+permission+"'"):
   s.request('POST','/services/data/v68.0/sobjects/PermissionSetAssignment',{'AssigneeId':user,'PermissionSetId':permission})
 group=s.query("SELECT Id FROM Group WHERE DeveloperName='Investment_Viewers'")[0]['Id']
 if not s.query("SELECT Id FROM GroupMember WHERE GroupId='"+group+"' AND UserOrGroupId='"+user+"'"):
  s.request('POST','/services/data/v68.0/sobjects/GroupMember',{'GroupId':group,'UserOrGroupId':user})
 accounts={r['Id']:r for r in s.query("SELECT Id,CASScopeKey__c FROM Inv_PortfolioAccounts__c WHERE PortfolioRef__c='"+portfolio+"'")}
 reversed={e['ReversesRef__c'] for e in s.query('SELECT ReversesRef__c FROM Inv_PortfolioEvents__c WHERE ReversesRef__c!=null AND PostedAt__c!=null')}
 ledger=s.query("SELECT AccountRef__c,InstrumentRef__c,InstrumentRef__r.Isin__c,UnitsDelta__c,ConsiderationAmount__c,EventRef__c,EventRef__r.EventDate__c,EventRef__r.EventType__c FROM Inv_PortfolioUnitEntries__c WHERE AccountRef__r.PortfolioRef__c='"+portfolio+"' AND EventRef__r.PostedAt__c!=null")
 groups={};event_keys={};event_counts=collections.Counter()
 for row in ledger:
  e=row['EventRef__r']
  if row['EventRef__c'] in reversed or e['EventType__c']=='reversal':continue
  key=(row['AccountRef__c'],row['InstrumentRef__c'],row['InstrumentRef__r']['Isin__c'])
  token=(e['EventDate__c'],e['EventType__c'],exact(row['UnitsDelta__c']),exact(row['ConsiderationAmount__c']))
  groups.setdefault(key,collections.Counter())[token]+=1;event_counts[row['EventRef__c']]+=1
  fingerprint='|'.join([row['AccountRef__c'],row['InstrumentRef__c'],*token]);event_keys[row['EventRef__c']]=hashlib.sha256(fingerprint.encode()).hexdigest()
 mappings=[]
 for scope in payload['scopes']:
  incoming=collections.Counter((r['tradeDate'],r['kind'],exact(r['units']),exact(r['amount'])) for r in scope['transactions'])
  candidates=[key for key,values in groups.items() if key[2]==scope['isin'] and values==incoming]
  if len(candidates)!=1 or not incoming:raise RuntimeError('CAS scope does not have a unique, nonempty full-history match; mapping must be reviewed')
  account,fund,_=candidates[0]
  if accounts[account]['CASScopeKey__c'] not in [None,scope['scopeKey']]:raise RuntimeError('Existing CAS account mapping conflicts')
  mappings.append({'attributes':{'type':'Inv_PortfolioAccounts__c'},'Id':account,'CASScopeKey__c':scope['scopeKey']})
 updates=mappings+[{'attributes':{'type':'Inv_PortfolioEvents__c'},'Id':event,'EconomicKey__c':key} for event,key in event_keys.items() if event_counts[event]==1]
 for start in range(0,len(updates),200):
  result=s.request('PATCH','/services/data/v68.0/composite/sobjects',{'allOrNone':True,'records':updates[start:start+200]})
  if not all(row['success'] for row in result):raise RuntimeError('CAS identity seed failed')
 files=s.query("SELECT Id,ContentDocumentId,Checksum FROM ContentVersion WHERE IsLatest=true AND FileType='PDF'")
 checksum=hashlib.md5(content).hexdigest();matching=[file for file in files if file['Checksum']==checksum]
 if matching:document=matching[0]['ContentDocumentId']
 else:
  version=s.request('POST','/services/data/v68.0/sobjects/ContentVersion',{'Title':'CAS statement rehearsal','PathOnClient':path.name,'VersionData':base64.b64encode(content).decode(),'FirstPublishLocationId':portfolio})['id']
  document=s.query("SELECT ContentDocumentId FROM ContentVersion WHERE Id='"+version+"'")[0]['ContentDocumentId']
 result=s.request('POST','/services/data/v68.0/actions/custom/apex/InvImportActions',{'inputs':[{'operation':'create','portfolioId':portfolio,'documentIds':[document]}]})
 evidence=PRIVATE/'cas-rehearsal';evidence.mkdir(exist_ok=True);(evidence/'create-result.json').write_text(json.dumps(result))
 if not result[0]['isSuccess']:raise RuntimeError('Rehearsal import creation failed; see protected report')
 run=result[0]['outputValues']['runId'];(evidence/'input-manifest.json').write_text(json.dumps({'runId':run,'fileHash':payload['fileHash'],'scopeMappings':mappings,'baselineLedgerCount':len(ledger)},indent=2))
 if args.submit:
  script=evidence/'submit.apex';script.write_text("System.debug(LoggingLevel.INFO, InvImportActions.submit('"+run+"',null));")
  result=subprocess.run(['sf.cmd','apex','run','--file',str(script),'--target-org',args.target_org,'--json'],capture_output=True,text=True,encoding='utf-8')
  (evidence/'submit-result.json').write_text(result.stdout,encoding='utf-8')
  if result.returncode:raise RuntimeError('Salesforce parser submission failed; see protected report')
 print(json.dumps({'scopesVerified':len(mappings),'economicIdentitiesSeeded':len(event_keys),'runId':run,'submitted':args.submit,'transactionsPosted':0}))

if __name__=='__main__':main()
