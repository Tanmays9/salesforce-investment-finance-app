@IsTest private class InvRefreshTest {
    private class Context implements QueueableContext { public Id getJobId(){return '707000000000001';} }
    private class Feed implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse r=new HttpResponse();r.setStatusCode(200);
            if(request.getEndpoint().contains('AMFI'))r.setBody('Scheme Code;ISIN;Other;Name;NAV;Date\n123;TESTISIN;-;Synthetic Direct Growth;11;01-Jan-2024\n');
            else r.setBody('{"status":"SUCCESS","meta":{"scheme_code":123,"isin_growth":"TESTISIN","scheme_name":"Synthetic Direct Growth"},"data":[{"date":"01-01-2024","nav":"11"}]}');
            return r;
        }
    }
    @IsTest static void refreshValidatesIdentityAndDeduplicates() {
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='nav:fund',AMFICode__c='123',Isin__c='TESTISIN',MappingVerified__c=true,Tracked__c=true);insert fund;
        Test.setMock(HttpCalloutMock.class,new Feed());Test.startTest();
        new InvNAVRefresh(new List<Id>{fund.Id}).execute(new Context());
        Assert.areEqual(2,[SELECT COUNT() FROM Inv_MarketPriceObservations__c],JSON.serialize([SELECT SourceJson__c FROM Inv_OpsDataIssues__c]));
        Assert.areEqual('Accepted',[SELECT NAVRefreshStatus__c FROM Inv_MarketInstruments__c WHERE Id=:fund.Id].NAVRefreshStatus__c);
        Integer queued=Limits.getQueueableJobs();new InvDailyRefresh(true).execute(null);Assert.areEqual(queued+1,Limits.getQueueableJobs(),'Retry schedules refresh benchmark data even when NAVs already succeeded');
        InvNAVRefresh.Observation repeated=new InvNAVRefresh.Observation();repeated.fund=fund.Id;repeated.day=Date.newInstance(2024,1,1);repeated.value='11.00';repeated.provider='MFapi';
        InvNAVRefresh.persist(new List<InvNAVRefresh.Observation>{repeated});
        Assert.areEqual(2,[SELECT COUNT() FROM Inv_MarketPriceObservations__c],'A numerically identical provider observation is not inserted again');
        fund.Isin__c='WRONG';Boolean rejected=false;
        try{InvNAVRefresh.parseMFAPI('{"status":"SUCCESS","meta":{"scheme_code":123,"isin_growth":"TESTISIN"}}',fund);}catch(InvMath.CalculationException e){rejected=true;}
        Assert.isTrue(rejected);
        Assert.areEqual(Date.newInstance(2024,1,1),InvNAVRefresh.parseDate('2024-01-01'));
        fund.Tracked__c=false;update fund;new InvDailyRefresh().execute(null);
        new InvRecalculate(new List<Id>()).execute(new Context());
    }
    @IsTest static void fundReturnsAndDrawdownAreReproducible() {
        Inv_MarketInstruments__c f=new Inv_MarketInstruments__c(MigrationKey__c='metric:fund');insert f;
        Date d=Date.newInstance(2020,1,1);List<Inv_MarketPriceObservations__c> prices=new List<Inv_MarketPriceObservations__c>();
        for(Integer i=0;i<3;i++)prices.add(new Inv_MarketPriceObservations__c(MigrationKey__c='metric:'+i,InstrumentRef__c=f.Id,ObservedOn__c=d.addYears(i),
            Value__c=i==0?'100':i==1?'150':'120',PriceKind__c='NAV',QualityStatus__c='accepted'));
        insert prices;Id first=InvFundMetrics.calculate(f.Id,d.addYears(2));Id second=InvFundMetrics.calculate(f.Id,d.addYears(2));Assert.areEqual(first,second);
        Assert.areEqual(8,[SELECT COUNT() FROM Inv_FundMetric__c]);
        Assert.areEqual(-0.2,[SELECT Value__c FROM Inv_FundMetric__c WHERE Metric__c='Historical maximum drawdown'].Value__c);
        new InvFundMetrics(new List<Id>{f.Id}).execute(new Context());
        new InvFundMetrics(new List<Id>()).execute(new Context());
        new InvRecalculate().execute(new Context());
    }
    @IsTest static void fundMetricsContinueThroughScheduledHandoffs() {
        Inv_MarketInstruments__c a=new Inv_MarketInstruments__c(MigrationKey__c='handoff:a');Inv_MarketInstruments__c b=new Inv_MarketInstruments__c(MigrationKey__c='handoff:b');insert new List<Inv_MarketInstruments__c>{a,b};
        Integer beforeCount=[SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Inv fund metrics continuation %'];
        new InvFundMetrics(new List<Id>{a.Id,b.Id}).execute(new Context());
        Assert.areEqual(beforeCount+1,[SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Inv fund metrics continuation %'],'Large metric runs leave the queue depth through a timed scheduled handoff');
    }
    @IsTest static void backgroundPublicationIsAtomic() {
        Inv_PortfolioPortfolios__c p=new Inv_PortfolioPortfolios__c(MigrationKey__c='background:p');insert p;
        new InvRecalculate(new List<Id>{p.Id}).execute(new Context());
        Id published=[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:p.Id].PublishedRun__c;
        Assert.isNotNull(published);
        Inv_PortfolioAccounts__c a=new Inv_PortfolioAccounts__c(MigrationKey__c='background:a',PortfolioRef__c=p.Id);insert a;
        Inv_MarketInstruments__c f=new Inv_MarketInstruments__c(MigrationKey__c='background:f');insert f;
        Inv_PortfolioEvents__c e=new Inv_PortfolioEvents__c(MigrationKey__c='background:e',EventDate__c=Date.today(),PostedAt__c=System.now(),EventType__c='purchase');insert e;
        insert new Inv_PortfolioUnitEntries__c(MigrationKey__c='background:u',EventRef__c=e.Id,AccountRef__c=a.Id,InstrumentRef__c=f.Id,UnitsDelta__c='1',Currency__c='USD');
        new InvRecalculate(new List<Id>{p.Id}).execute(new Context());
        Assert.areEqual(published,[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:p.Id].PublishedRun__c);
        Assert.areEqual(1,[SELECT COUNT() FROM Inv_AnalyticsRuns__c WHERE OperationalStatus__c='Failed']);
    }
}
