public without sharing class InvNAVRefresh implements Queueable, Database.AllowsCallouts {
    private List<Id> funds;
    public InvNAVRefresh(List<Id> ids) {funds=ids;}
    public class Observation {public Id fund;public String provider,code,isin,value,raw;public Date day;}
    public static Date parseDate(String value) {
        List<String> bits=value.split('-');
        if(bits[0].length()==4)return Date.valueOf(value);
        return Date.newInstance(Integer.valueOf(bits[2]),Integer.valueOf(bits[1]),Integer.valueOf(bits[0]));
    }
    @TestVisible static Observation parseMFAPI(String body,Inv_MarketInstruments__c fund) {
        Map<String,Object> root=(Map<String,Object>)JSON.deserializeUntyped(body);
        if(root.get('status')!='SUCCESS')throw new InvMath.CalculationException('MFapi returned unsuccessful status');
        Map<String,Object> meta=(Map<String,Object>)root.get('meta');
        if(String.valueOf(meta.get('scheme_code'))!=fund.AMFICode__c || meta.get('isin_growth')!=fund.Isin__c)
            throw new InvMath.CalculationException('MFapi share-class identity mismatch');
        String name=String.valueOf(meta.get('scheme_name')).toLowerCase();
        if(!name.contains('direct') || !name.contains('growth'))throw new InvMath.CalculationException('Unsupported plan/option identity');
        List<Object> data=(List<Object>)root.get('data');if(data.isEmpty())throw new InvMath.CalculationException('Missing NAV');
        Map<String,Object> row=(Map<String,Object>)data[0];Observation o=new Observation();
        o.fund=fund.Id;o.code=fund.AMFICode__c;o.isin=fund.Isin__c;o.provider='MFapi';o.day=parseDate((String)row.get('date'));
        o.value=(String)row.get('nav');o.raw=body;
        if(o.day>Date.today() || InvMath.exact(o.value)<=0)throw new InvMath.CalculationException('Invalid NAV date or value');
        return o;
    }
    @TestVisible static Observation parseAMFI(String body,Inv_MarketInstruments__c fund) {
        String prefix='\n'+fund.AMFICode__c+';';Integer index=body.indexOf(prefix);
        if(index<0 && body.startsWith(fund.AMFICode__c+';'))index=-1;
        else if(index<0)return null;
        Integer endLine=body.indexOf('\n',index+1);if(endLine<0)endLine=body.length();
        String line=body.substring(index+1,endLine).trim();List<String> cols=line.split(';');
        if(cols.size()<6 || (cols[1]!=fund.Isin__c && cols[2]!=fund.Isin__c))throw new InvMath.CalculationException('AMFI share-class identity mismatch');
        Map<String,Integer> months=new Map<String,Integer>{'Jan'=>1,'Feb'=>2,'Mar'=>3,'Apr'=>4,'May'=>5,'Jun'=>6,'Jul'=>7,'Aug'=>8,'Sep'=>9,'Oct'=>10,'Nov'=>11,'Dec'=>12};
        List<String> bits=cols[cols.size()-1].split('-');Observation o=new Observation();o.fund=fund.Id;o.code=fund.AMFICode__c;o.isin=fund.Isin__c;
        o.provider='AMFI';o.day=Date.newInstance(Integer.valueOf(bits[2]),months.get(bits[1]),Integer.valueOf(bits[0]));o.value=cols[cols.size()-2];o.raw=line;
        if(o.day>Date.today() || InvMath.exact(o.value)<=0)throw new InvMath.CalculationException('Invalid AMFI NAV');return o;
    }
    private static String fetch(String endpoint) {
        HttpRequest r=new HttpRequest();r.setEndpoint(endpoint);r.setMethod('GET');r.setTimeout(30000);
        HttpResponse response=new Http().send(r);
        if(response.getStatusCode()!=200)throw new InvMath.CalculationException('Provider HTTP '+response.getStatusCode());
        return response.getBody();
    }
    public void execute(QueueableContext context) {
        List<Id> portion=new List<Id>(),remaining=new List<Id>();
        for(Integer i=0;i<funds.size();i++)if(i<10)portion.add(funds[i]);else remaining.add(funds[i]);
        List<Inv_MarketInstruments__c> instruments=[SELECT Id,AMFICode__c,Isin__c,MappingVerified__c FROM Inv_MarketInstruments__c WHERE Id IN :portion WITH SYSTEM_MODE ];
        List<Observation> observed=new List<Observation>();List<String> errors=new List<String>();String amfi;
        try {amfi=fetch('callout:Inv_AMFI/spages/NAVAll.txt');}catch(Exception e){errors.add('AMFI unavailable: '+e.getMessage());}
        for(Inv_MarketInstruments__c fund:instruments) {
            if(!fund.MappingVerified__c || String.isBlank(fund.AMFICode__c)){errors.add('Unverified mapping: '+fund.Id);continue;}
            Observation mf,official;
            try {mf=parseMFAPI(fetch('callout:Inv_MFapi/mf/'+fund.AMFICode__c+'/latest'),fund);observed.add(mf);}
            catch(Exception e){errors.add('MFapi '+fund.Id+': '+e.getMessage());}
            if(amfi!=null)try {official=parseAMFI(amfi,fund);if(official!=null)observed.add(official);}
            catch(Exception e){errors.add('AMFI '+fund.Id+': '+e.getMessage());}
            if(mf!=null && official!=null && mf.day==official.day && InvMath.exact(mf.value)!=InvMath.exact(official.value))errors.add('NAV source discrepancy '+fund.Id+' '+mf.day+'; official AMFI selected');
        }
        persist(observed);
        Set<Id> acceptedFunds=new Set<Id>();for(Observation o:observed)acceptedFunds.add(o.fund);
        List<Inv_MarketInstruments__c> attempts=new List<Inv_MarketInstruments__c>();
        for(Inv_MarketInstruments__c fund:instruments)attempts.add(new Inv_MarketInstruments__c(Id=fund.Id,NAVAttemptAt__c=System.now(),NAVRefreshStatus__c=acceptedFunds.contains(fund.Id)?'Accepted':'Failed'));
        if(!attempts.isEmpty())update as system attempts;
        if(!errors.isEmpty()) {
            Inv_OpsDataIssues__c issue=new Inv_OpsDataIssues__c(MigrationKey__c='nav-job:'+context.getJobId(),IssueKey__c='NAV refresh '+context.getJobId(),
                ObservedOn__c=Date.today(),Severity__c='warning',Status__c='open',Message__c=String.join(errors,'\n'),CreatedAt__c=System.now(),SourceJson__c=JSON.serialize(errors));
            insert as system issue;
        }
        if(!remaining.isEmpty())System.enqueueJob(new InvNAVRefresh(remaining));
        else if(!Test.isRunningTest())System.enqueueJob(new InvBenchmarkRefresh());
    }
    @TestVisible private static void persist(List<Observation> observed) {
        Map<String,Id> providers=new Map<String,Id>();
        for(String name:new List<String>{'MFapi','AMFI'}) {
            Inv_OpsProviders__c provider=new Inv_OpsProviders__c(MigrationKey__c='operational:provider:'+name,Name__c=name,Kind__c='nav_feed');
            upsert as system provider MigrationKey__c;providers.put(name,provider.Id);
        }
        List<Inv_MarketPriceObservations__c> rows=new List<Inv_MarketPriceObservations__c>();
        for(Observation o:observed) {
            String k=o.provider+':'+o.fund+':'+String.valueOf(o.day)+':'+InvPortfolioEngine.hash(InvMath.valueKey(o.value));
            rows.add(new Inv_MarketPriceObservations__c(MigrationKey__c='nav:'+InvPortfolioEngine.hash(k),ObservationKey__c=k,
                InstrumentRef__c=o.fund,ObservedOn__c=o.day,Value__c=o.value,PriceKind__c='NAV',QualityStatus__c='accepted',KindFilter__c='NAV',QualityFilter__c='accepted',
                ProviderRef__c=providers.get(o.provider),ReceivedAt__c=System.now(),RetrievedAt__c=System.now(),
                RevisionNo__c=String.valueOf(System.now().getTime()),SourceJson__c=JSON.serialize(o)));
        }
        for(Inv_MarketPriceObservations__c row:rows){InvMath.project(row,'Value__c',row.Value__c);InvMath.project(row,'RevisionNo__c',row.RevisionNo__c);}
        Set<String> keys=new Set<String>();for(Inv_MarketPriceObservations__c row:rows)keys.add(row.ObservationKey__c);
        Set<String> existing=new Set<String>();
        for(Inv_MarketPriceObservations__c row:[SELECT ObservationKey__c FROM Inv_MarketPriceObservations__c WHERE ObservationKey__c IN :keys WITH SYSTEM_MODE ])existing.add(row.ObservationKey__c);
        List<Inv_MarketPriceObservations__c> fresh=new List<Inv_MarketPriceObservations__c>();
        for(Inv_MarketPriceObservations__c row:rows)if(!existing.contains(row.ObservationKey__c))fresh.add(row);
        if(!fresh.isEmpty())upsert as system fresh ObservationKey__c;
        Set<Id> fundIds=new Set<Id>();Set<Date> days=new Set<Date>();for(Observation o:observed){fundIds.add(o.fund);days.add(o.day);}
        Map<String,Inv_MarketPriceObservations__c> chosen=new Map<String,Inv_MarketPriceObservations__c>();
        List<Inv_MarketPriceObservations__c> candidates=[SELECT Id,InstrumentRef__c,ObservedOn__c,ProviderRef__r.Name__c,SelectedNAV__c
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c IN :fundIds AND ObservedOn__c IN :days AND KindFilter__c='NAV' AND QualityFilter__c='accepted'
            WITH SYSTEM_MODE ORDER BY ReceivedAt__c DESC,RevisionNoNumber__c DESC,Id DESC];
        for(Inv_MarketPriceObservations__c row:candidates) {
            String identity=row.InstrumentRef__c+':'+row.ObservedOn__c;
            if(!chosen.containsKey(identity) || row.ProviderRef__r.Name__c=='AMFI' && chosen.get(identity).ProviderRef__r.Name__c!='AMFI')chosen.put(identity,row);
        }
        List<Inv_MarketPriceObservations__c> changed=new List<Inv_MarketPriceObservations__c>();
        for(Inv_MarketPriceObservations__c row:candidates) {
            Boolean selected=chosen.get(row.InstrumentRef__c+':'+row.ObservedOn__c).Id==row.Id;
            if(selected!=row.SelectedNAV__c)changed.add(new Inv_MarketPriceObservations__c(Id=row.Id,SelectedNAV__c=selected));
        }
        if(!changed.isEmpty())update as system changed;
    }

}
