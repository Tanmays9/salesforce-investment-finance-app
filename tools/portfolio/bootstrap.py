"""Verify held-share-class mappings against AMFI and populate operational display fields."""
import argparse,json,sys,urllib.request,datetime,decimal
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'investment-migration'))
from migrate import Salesforce
from prepare import PRIVATE

def main():
 p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);args=p.parse_args();s=Salesforce(args.target_org)
 org=s.query('SELECT Id,IsSandbox FROM Organization')[0]
 if org['Id'] not in ['LOCAL_SALESFORCE_SANDBOX_ORG_ID','LOCAL_SALESFORCE_PRODUCTION_ORG_ID']:raise RuntimeError('Unexpected investment org')
 with urllib.request.urlopen('https://portal.amfiindia.com/spages/NAVAll.txt',timeout=60) as response:raw=response.read()
 source={}
 for line in raw.decode('utf-8-sig').splitlines():
  cols=line.split(';')
  if len(cols)>=6 and cols[0].isdigit():source[cols[0]]=cols
 reversed={x['ReversesRef__c'] for x in s.query('SELECT ReversesRef__c FROM Inv_PortfolioEvents__c WHERE PostedAt__c!=null AND ReversesRef__c!=null')}
 positions={}
 for row in s.query('SELECT AccountRef__c,InstrumentRef__c,UnitsDelta__c,EventRef__c,EventRef__r.EventType__c FROM Inv_PortfolioUnitEntries__c WHERE EventRef__r.PostedAt__c!=null'):
  if row['EventRef__c'] in reversed or row['EventRef__r']['EventType__c']=='reversal':continue
  key=(row['AccountRef__c'],row['InstrumentRef__c']);positions[key]=positions.get(key,decimal.Decimal(0))+decimal.Decimal(row['UnitsDelta__c'] or 0)
 active={fund for (_,fund),units in positions.items() if units>0}
 rows=s.query('SELECT Id,Name__c,Isin__c FROM Inv_MarketInstruments__c')
 classes={x['InstrumentRef__c']:x for x in s.query('SELECT InstrumentRef__c,AmfiCode__c,Plan__c,Option__c FROM Inv_MarketFundShareClasses__c')}
 updates=[];verified=[];failures=[]
 for row in rows:
  update={'attributes':{'type':'Inv_MarketInstruments__c'},'Id':row['Id'],'DisplayName__c':(row['Name__c'] or '')[:255]}
  if row['Id'] in classes:
   spec=classes.get(row['Id']);cols=source.get(spec['AmfiCode__c']) if spec else None
   if spec and cols and row['Isin__c'] in cols[1:3] and spec['Plan__c']=='Direct' and spec['Option__c']=='Growth' and 'direct' in ';'.join(cols[3:-2]).lower() and 'growth' in ';'.join(cols[3:-2]).lower():
    update.update(AMFICode__c=spec['AmfiCode__c'],MappingVerified__c=True)
    if row['Id'] in active:update['Tracked__c']=True
    verified.append({'instrument':row['Id'],'schemeCode':spec['AmfiCode__c'],'isin':row['Isin__c']})
   elif row['Id'] in active:failures.append(row['Id'])
  updates.append(update)
 for start in range(0,len(updates),200):
  results=s.request('PATCH','/services/data/v68.0/composite/sobjects',{'allOrNone':True,'records':updates[start:start+200]})
  if not all(r['success'] for r in results):raise RuntimeError('Operational display/mapping update failed')
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')
 path=PRIVATE/('bootstrap-'+args.target_org+'-'+stamp);path.mkdir()
 (path/'amfi.txt').write_bytes(raw);(path/'verification.json').write_text(json.dumps({'org':org,'verified':verified,'unverified':failures},indent=2))
 print(json.dumps({'displayNamesUpdated':len(updates),'shareClassMappingsVerified':len(verified),'unverifiedHeldFunds':len(failures),'evidence':str(path)}))

if __name__=='__main__':main()
