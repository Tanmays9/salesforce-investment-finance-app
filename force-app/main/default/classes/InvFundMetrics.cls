public without sharing class InvFundMetrics implements Queueable {
    private static final Integer BATCH_SIZE=1;
    private List<Id> funds;
    private Id pipelineId;
    public InvFundMetrics(List<Id> ids){this(ids,null);}
    public InvFundMetrics(List<Id> ids,Id parentPipeline){funds=ids==null?new List<Id>():new List<Id>(ids);pipelineId=parentPipeline;}
    public void execute(QueueableContext context) {
        Boolean failed=false;Integer processed=0;
        while(!funds.isEmpty() && processed<BATCH_SIZE) {
            Id fund=funds.remove(0);processed++;Savepoint checkpoint=Database.setSavepoint();
            try{calculate(fund,Date.today(),pipelineId);}
            catch(Exception e) {
                Database.rollback(checkpoint);failed=true;insert as system new Inv_AnalyticsRuns__c(MigrationKey__c='fund-failed:'+context.getJobId()+':'+fund,Kind__c='fund_metrics',
                    PipelineRef__c=pipelineId,OperationalStatus__c='Failed',Status__c='failed',Failure__c='Fund '+fund+': '+e.getTypeName()+': '+e.getMessage(),StartedAt__c=System.now());
            }
        }
        if(pipelineId!=null) {
            Inv_AnalyticsRuns__c pipeline=[SELECT Id,FundMetricsStageStatus__c FROM Inv_AnalyticsRuns__c WHERE Id=:pipelineId WITH SYSTEM_MODE FOR UPDATE];
            if(failed)pipeline.FundMetricsStageStatus__c='Failed';
            else if(funds.isEmpty() && pipeline.FundMetricsStageStatus__c!='Failed')pipeline.FundMetricsStageStatus__c='Complete';
            update as system pipeline;
        }
        if(!funds.isEmpty())System.enqueueJob(new InvFundMetrics(funds,pipelineId));
        else if(pipelineId!=null)InvResearchPipeline.complete(pipelineId);
    }
    public static Id calculate(Id fund,Date asOf) {
        return calculate(fund,asOf,null);
    }
    public static Id calculate(Id fund,Date asOf,Id pipelineId) {
        List<Inv_MarketPriceObservations__c> source=[SELECT Id,ObservedOn__c,Value__c,PriceKind__c,QualityStatus__c,ProviderRef__r.Name__c,
                SelectedNAV__c,RevisionNoNumber__c,ReceivedAt__c
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c=:fund AND ObservedOn__c<=:asOf
             WITH SYSTEM_MODE ORDER BY ObservedOn__c ASC,ReceivedAt__c DESC LIMIT 30000];
        if(source.size()==30000)throw new InvMath.CalculationException('Fund history exceeds one calculation scope; split history before publishing');
        Map<Date,Inv_MarketPriceObservations__c> selected=InvNAVPolicy.daily(source);Map<Date,Decimal> navs=new Map<Date,Decimal>();
        for(Date observationDate:selected.keySet())navs.put(observationDate,InvMath.exact(selected.get(observationDate).Value__c));
        List<Date> dates=new List<Date>(navs.keySet());dates.sort();if(dates.isEmpty())return null;
        Date endDate=dates[dates.size()-1];Decimal last=navs.get(endDate);InvFundDetails.Details details=InvFundDetails.calculate(fund,endDate);
        InvBenchmarkEngine.Comparison comparison=InvBenchmarkEngine.calculate(fund,navs,endDate);
        String fingerprint=InvPortfolioEngine.hash(JSON.serialize(navs)+details.fingerprint+comparison.fingerprint);
        Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='fund-metrics:'+fund+':'+fingerprint,Kind__c='fund_metrics',PipelineRef__c=pipelineId,
            ValuationAsOf__c=endDate,AlgorithmVersion__c='sf-fund-1',InputFingerprint__c=fingerprint,StartedAt__c=System.now(),Status__c='running',OperationalStatus__c='Running');upsert as system run MigrationKey__c;
        List<Inv_FundMetric__c> rows=new List<Inv_FundMetric__c>();
        for(Integer months:new List<Integer>{1,3,6,12,36,60}) {
            Date requested=endDate.addMonths(-months),start;
            for(Date d:dates)if(d<=requested)start=d;
            Decimal value;String status='insufficient_history';
            if(start!=null) {
                Decimal ratio=last/navs.get(start);value=months<12?ratio-1:annualized(ratio,start.daysBetween(endDate));status='ok';
            }
            String metric=months+' month '+(months<12?'return':'CAGR');rows.add(row(run.Id,fund,metric,start,endDate,value,status));
        }
        Map<String,Date> latestInMonth=new Map<String,Date>();for(Date d:dates)latestInMonth.put(String.valueOf(d.year())+'-'+String.valueOf(d.month()),d);
        List<Date> monthDates=new List<Date>(latestInMonth.values());monthDates.sort();List<Decimal> monthlyReturns=new List<Decimal>();
        for(Integer i=1;i<monthDates.size();i++)monthlyReturns.add(navs.get(monthDates[i])/navs.get(monthDates[i-1])-1);
        List<Decimal> oneYearRolling=new List<Decimal>(),threeYearRolling=new List<Decimal>();
        for(Integer i=0;i<monthDates.size();i++)for(Integer months:new List<Integer>{12,36}) {
            Date startDay=monthDates[i],targetDay=startDay.addMonths(months),endDay;
            for(Integer j=i+1;j<monthDates.size();j++)if(monthDates[j]<=targetDay)endDay=monthDates[j];
            if(endDay==null)continue;Integer elapsed=startDay.daysBetween(endDay);
            if(months==12 && elapsed>=330 && elapsed<=400)oneYearRolling.add(navs.get(endDay)/navs.get(startDay)-1);
            if(months==36 && elapsed>=1050 && elapsed<=1130) {
                Decimal ratio=navs.get(endDay)/navs.get(startDay);
                threeYearRolling.add(annualized(ratio,elapsed));
            }
        }
        rows.add(distribution(run.Id,fund,'1 year rolling return distribution',monthDates.isEmpty()?null:monthDates[0],endDate,oneYearRolling,'Rolling monthly samples; approximately 12 months; nearest-rank quartiles.'));
        rows.add(distribution(run.Id,fund,'3 year rolling annualized return distribution',monthDates.isEmpty()?null:monthDates[0],endDate,threeYearRolling,'Rolling monthly samples; annualized by 365.25 / elapsed days; nearest-rank quartiles.'));
        Decimal annualizedVolatility;String volatilityCoverage='insufficient_history';
        if(monthlyReturns.size()>1) {
            Decimal average=0;for(Decimal value:monthlyReturns)average+=value;average/=monthlyReturns.size();Decimal squared=0;
            for(Decimal value:monthlyReturns)squared+=(value-average)*(value-average);
            annualizedVolatility=Decimal.valueOf(String.valueOf(Math.sqrt(Double.valueOf(String.valueOf((squared/(monthlyReturns.size()-1))*12)))));volatilityCoverage='available_monthly_samples';
        }
        Inv_FundMetric__c volatility=row(run.Id,fund,'Annualized volatility (monthly NAV, available history)',monthDates.isEmpty()?null:monthDates[0],endDate,annualizedVolatility,volatilityCoverage);
        volatility.SampleCount__c=monthlyReturns.size();volatility.Methodology__c='Sample standard deviation of monthly NAV returns multiplied by square root of 12.';rows.add(volatility);
        Decimal peak=0,maxDrawdown=0,peakForMax=0;Date peakDate,maxPeakDate,troughDate,recoveredOn;
        for(Date d:dates) {
            Decimal n=navs.get(d);
            if(n>=peak){peak=n;peakDate=d;}
            Decimal dd=n/peak-1;
            if(dd<maxDrawdown){maxDrawdown=dd;peakForMax=peak;maxPeakDate=peakDate;troughDate=d;recoveredOn=null;}
            else if(troughDate!=null && recoveredOn==null && d>troughDate && n>=peakForMax)recoveredOn=d;
        }
        Inv_FundMetric__c drawdown=row(run.Id,fund,'Historical maximum drawdown',dates[0],endDate,maxDrawdown,'available_history');
        drawdown.DrawdownPeak__c=maxPeakDate;drawdown.DrawdownTrough__c=troughDate;drawdown.RecoveredOn__c=recoveredOn;
        if(recoveredOn!=null)drawdown.RecoveryDays__c=troughDate.daysBetween(recoveredOn);
        drawdown.Methodology__c='Peak-to-trough decline in selected accepted daily NAV history; recovery is the first later NAV at or above that peak.';rows.add(drawdown);
        for(Inv_FundMetric__c metric:comparison.metrics){metric.Run__c=run.Id;metric.Key__c=run.Id+':'+metric.Metric__c;rows.add(metric);}
        for(Inv_FundMetric__c metric:details.metrics){metric.Run__c=run.Id;metric.Key__c=run.Id+':overlap:'+metric.CounterpartyFund__c;rows.add(metric);}
        List<Inv_FundMetric__c> prior=[SELECT Id,Published__c FROM Inv_FundMetric__c WHERE Fund__c=:fund AND Published__c=true AND Run__c!=:run.Id WITH SYSTEM_MODE ];
        for(Inv_FundMetric__c p:prior)p.Published__c=false;update as system prior;
        for(Inv_FundMetric__c metric:rows)InvMath.capture(metric);upsert as system rows Key__c;
        run.Status__c='complete';run.OperationalStatus__c='Published';run.CompletedAt__c=System.now();update as system run;return run.Id;
    }
    private static Inv_FundMetric__c row(Id run,Id fund,String metric,Date start,Date endDate,Decimal value,String coverage) {
        return new Inv_FundMetric__c(Key__c=run+':'+metric,Name=metric,Fund__c=fund,Run__c=run,Metric__c=metric,PeriodStart__c=start,PeriodEnd__c=endDate,
            Value__c=value,Coverage__c=coverage,Published__c=true,Methodology__c='Selected accepted NAVs; fund NAV return excludes investor cash flows.');
    }
    private static Inv_FundMetric__c distribution(Id run,Id fund,String metric,Date start,Date endDate,List<Decimal> samples,String methodology) {
        Inv_FundMetric__c result=row(run,fund,metric,start,endDate,null,samples.isEmpty()?'insufficient_history':'available_monthly_samples');
        result.SampleCount__c=samples.size();result.Methodology__c=methodology;if(samples.isEmpty())return result;
        samples.sort();result.Minimum__c=samples[0];result.LowerQuartile__c=nearestRank(samples,0.25);result.Median__c=nearestRank(samples,0.5);
        result.UpperQuartile__c=nearestRank(samples,0.75);result.Maximum__c=samples[samples.size()-1];result.Value__c=result.Median__c;return result;
    }
    private static Decimal nearestRank(List<Decimal> sorted,Decimal quantile) {
        Integer index=(Integer)Math.ceil(Double.valueOf(String.valueOf(quantile))*sorted.size())-1;
        index=Math.max(0,Math.min(sorted.size()-1,index));return sorted[index];
    }
    private static Decimal annualized(Decimal totalReturnRatio,Integer days) {
        if(totalReturnRatio==null || totalReturnRatio<=0 || days==null || days<=0)return null;
        Double exponent=Double.valueOf('365.25')/Double.valueOf(String.valueOf(days));
        return Decimal.valueOf(String.valueOf(Math.pow(Double.valueOf(String.valueOf(totalReturnRatio)),exponent)-1));
    }
}
