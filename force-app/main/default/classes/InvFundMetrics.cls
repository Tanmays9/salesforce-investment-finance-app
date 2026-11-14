public without sharing class InvFundMetrics implements Queueable {
    private List<Id> funds;
    public InvFundMetrics(List<Id> ids){funds=ids;}
    public void execute(QueueableContext context) {
        if(funds.isEmpty())return;Id fund=funds.remove(0);Savepoint checkpoint=Database.setSavepoint();
        try{calculate(fund,Date.today());}
        catch(Exception e) {
            Database.rollback(checkpoint);insert as system new Inv_AnalyticsRuns__c(MigrationKey__c='fund-failed:'+context.getJobId(),Kind__c='fund_metrics',
                OperationalStatus__c='Failed',Status__c='failed',Failure__c=e.getTypeName()+': '+e.getMessage(),StartedAt__c=System.now());
        }
        if(!funds.isEmpty()) {
            Datetime next=System.now().addMinutes(1);
            String cron='0 '+next.minute()+' '+next.hour()+' '+next.day()+' '+next.month()+' ? '+next.year();
            System.schedule('Inv fund metrics continuation '+Crypto.getRandomLong(),cron,new InvFundMetricsContinuation(new List<Id>(funds)));
        }
    }
    public static Id calculate(Id fund,Date asOf) {
        List<Inv_MarketPriceObservations__c> source=[SELECT Id,ObservedOn__c,Value__c,PriceKind__c,QualityStatus__c,ProviderRef__r.Name__c
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c=:fund AND ObservedOn__c<=:asOf
             WITH SYSTEM_MODE ORDER BY ObservedOn__c ASC,ReceivedAt__c DESC LIMIT 45000];
        if(source.size()==45000)throw new InvMath.CalculationException('Fund history exceeds one calculation scope; split history before publishing');
        Map<Date,Decimal> navs=new Map<Date,Decimal>();Map<Date,Boolean> official=new Map<Date,Boolean>();
        for(Inv_MarketPriceObservations__c p:source)if(p.PriceKind__c=='NAV' && p.QualityStatus__c=='accepted' && InvMath.exact(p.Value__c)>0)
            if(!navs.containsKey(p.ObservedOn__c) || p.ProviderRef__r.Name__c=='AMFI' && !official.get(p.ObservedOn__c)) {
                navs.put(p.ObservedOn__c,InvMath.exact(p.Value__c));official.put(p.ObservedOn__c,p.ProviderRef__r.Name__c=='AMFI');
            }
        List<Date> dates=new List<Date>(navs.keySet());dates.sort();if(dates.isEmpty())return null;
        Date endDate=dates[dates.size()-1];Decimal last=navs.get(endDate);InvFundDetails.Details details=InvFundDetails.calculate(fund,endDate);
        InvBenchmarkEngine.Comparison comparison=InvBenchmarkEngine.calculate(fund,navs,endDate);
        String fingerprint=InvPortfolioEngine.hash(JSON.serialize(navs)+details.fingerprint+comparison.fingerprint);
        Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='fund-metrics:'+fund+':'+fingerprint,Kind__c='fund_metrics',
            ValuationAsOf__c=endDate,AlgorithmVersion__c='sf-fund-1',InputFingerprint__c=fingerprint,StartedAt__c=System.now(),Status__c='running',OperationalStatus__c='Running');upsert as system run MigrationKey__c;
        List<Inv_FundMetric__c> rows=new List<Inv_FundMetric__c>();
        for(Integer months:new List<Integer>{1,3,6,12,36,60}) {
            Date requested=endDate.addMonths(-months),start;
            for(Date d:dates)if(d<=requested)start=d;
            Decimal value;String status='insufficient_history';
            if(start!=null) {
                Decimal ratio=last/navs.get(start);value=months<12?ratio-1:
                    Decimal.valueOf(String.valueOf(Math.pow(Double.valueOf(String.valueOf(ratio)),Double.valueOf(String.valueOf(365.0/start.daysBetween(endDate))))-1));status='ok';
            }
            String metric=months+' month '+(months<12?'return':'CAGR');rows.add(row(run.Id,fund,metric,start,endDate,value,status));
        }
        Decimal peak=0,maxDrawdown=0;
        for(Date d:dates){Decimal n=navs.get(d);if(n>peak)peak=n;Decimal dd=n/peak-1;if(dd<maxDrawdown)maxDrawdown=dd;}
        rows.add(row(run.Id,fund,'Historical maximum drawdown',dates[0],endDate,maxDrawdown,'available_history'));
        for(Inv_FundMetric__c metric:comparison.metrics){metric.Run__c=run.Id;metric.Key__c=run.Id+':'+metric.Metric__c;rows.add(metric);}
        for(Inv_FundMetric__c metric:details.metrics){metric.Run__c=run.Id;metric.Key__c=run.Id+':overlap:'+metric.CounterpartyFund__c;rows.add(metric);}
        List<Inv_FundMetric__c> prior=[SELECT Id,Published__c FROM Inv_FundMetric__c WHERE Fund__c=:fund AND Published__c=true AND Run__c!=:run.Id WITH SYSTEM_MODE ];
        for(Inv_FundMetric__c p:prior)p.Published__c=false;update as system prior;
        for(Inv_FundMetric__c metric:rows)InvMath.capture(metric);upsert as system rows Key__c;
        run.Status__c='complete';run.OperationalStatus__c='Published';run.CompletedAt__c=System.now();update as system run;return run.Id;
    }
    private static Inv_FundMetric__c row(Id run,Id fund,String metric,Date start,Date endDate,Decimal value,String coverage) {
        return new Inv_FundMetric__c(Key__c=run+':'+metric,Name=metric,Fund__c=fund,Run__c=run,Metric__c=metric,PeriodStart__c=start,PeriodEnd__c=endDate,
            Value__c=value,Coverage__c=coverage,Published__c=true);
    }
}
