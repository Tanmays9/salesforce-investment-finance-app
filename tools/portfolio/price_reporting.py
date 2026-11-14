"""Backfill only report-selection fields; never modifies source dates or prices."""
import argparse,csv,hashlib,io,json,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'investment-migration'))
from migrate import Salesforce
from prepare import PRIVATE

def main():
 p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);args=p.parse_args();s=Salesforce(args.target_org)
 org=s.query('SELECT Id FROM Organization')[0]['Id']
 if org not in ['LOCAL_SALESFORCE_SANDBOX_ORG_ID','LOCAL_SALESFORCE_PRODUCTION_ORG_ID']:raise RuntimeError('Unexpected investment org')
 source=s.query('SELECT Id,InstrumentRef__c,ObservedOn__c,PriceKind__c,QualityStatus__c,ProviderRef__r.Name__c FROM Inv_MarketPriceObservations__c ORDER BY InstrumentRef__c,ObservedOn__c,ReceivedAt__c DESC,RevisionNoNumber__c DESC,Id DESC')
 selected={}
 for row in source:
  if row['PriceKind__c']!='NAV' or row['QualityStatus__c']!='accepted':continue
  key=(row['InstrumentRef__c'],row['ObservedOn__c'])
  provider=(row.get('ProviderRef__r') or {}).get('Name__c')
  prior=selected.get(key)
  if prior is None or provider=='AMFI' and (prior.get('ProviderRef__r') or {}).get('Name__c')!='AMFI':selected[key]=row
 ids={row['Id'] for row in selected.values()};stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=['Id','KindFilter__c','QualityFilter__c','SelectedNAV__c'],lineterminator='\n');writer.writeheader()
 for row in source:writer.writerow({'Id':row['Id'],'KindFilter__c':row['PriceKind__c'] or '#N/A','QualityFilter__c':row['QualityStatus__c'] or '#N/A','SelectedNAV__c':'true' if row['Id'] in ids else 'false'})
 body=stream.getvalue();fingerprint=hashlib.sha256(body.encode()).hexdigest();directory=PRIVATE/('price-reporting-'+args.target_org+'-'+fingerprint[:12]);directory.mkdir(exist_ok=True)
 (directory/'updates.csv').write_text(body,encoding='utf-8');receipt=directory/'job.json'
 job=json.loads(receipt.read_text()) if receipt.exists() else None
 if job:
  state=s.request('GET','/services/data/v68.0/jobs/ingest/'+job['id'])['state']
  if state=='Open':
   # An open job has not processed records; an interrupted upload may be incomplete.
   s.request('PATCH','/services/data/v68.0/jobs/ingest/'+job['id'],{'state':'Aborted'});job=None
  elif state in ['Failed','Aborted']:job=None
 if not job:
  job=s.request('POST','/services/data/v68.0/jobs/ingest',{'object':'Inv_MarketPriceObservations__c','operation':'update','contentType':'CSV','lineEnding':'LF'})
  receipt.write_text(json.dumps(job))
  s.request('PUT','/services/data/v68.0/jobs/ingest/'+job['id']+'/batches',body,'text/csv')
  s.request('PATCH','/services/data/v68.0/jobs/ingest/'+job['id'],{'state':'UploadComplete'})
 while True:
  result=s.request('GET','/services/data/v68.0/jobs/ingest/'+job['id']);(directory/'status.json').write_text(json.dumps(result))
  if result['state'] in ['JobComplete','Failed','Aborted']:break
  time.sleep(10)
 if result['state']!='JobComplete' or result.get('numberRecordsFailed',0):
  failed=s.request('GET','/services/data/v68.0/jobs/ingest/'+job['id']+'/failedResults',raw_response=True);(directory/'failed.csv').write_bytes(failed)
  raise RuntimeError('Reporting backfill failed; inspect protected per-row results')
 report={'sourceObservations':len(source),'selectedNAVDates':len(ids),'jobId':job['id'],'state':result['state'],'fieldsChanged':['KindFilter__c','QualityFilter__c','SelectedNAV__c'],'sourcePricesChanged':False}
 (directory/'verification.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))

if __name__=='__main__':main()
