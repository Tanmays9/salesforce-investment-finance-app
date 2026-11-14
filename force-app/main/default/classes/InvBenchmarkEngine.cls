public without sharing class InvBenchmarkEngine {
    public class Comparison {public List<Inv_FundMetric__c> metrics=new List<Inv_FundMetric__c>();public String fingerprint;}
    public static Comparison calculate(Id fund,Map<Date,Decimal> navs,Date endDate) {
        Comparison result=new Comparison();Id scheme;
        for(Inv_MarketFundShareClasses__c c:[SELECT SchemeRef__c FROM Inv_MarketFundShareClasses__c WHERE InstrumentRef__c=:fund WITH SYSTEM_MODE])scheme=c.SchemeRef__c;
        List<Inv_MarketBenchmarkAssignments__c> assignments=scheme==null?new List<Inv_MarketBenchmarkAssignments__c>():[
            SELECT Id,BenchmarkRef__c,BenchmarkRef__r.BenchmarkVariant__c,Role__c,EffectiveFrom__c,EffectiveTo__c,DocumentRef__c
            FROM Inv_MarketBenchmarkAssignments__c WHERE SchemeRef__c=:scheme AND EffectiveFrom__c<=:endDate AND (EffectiveTo__c=null OR EffectiveTo__c>:endDate)
            WITH SYSTEM_MODE ORDER BY EffectiveFrom__c DESC];
        Inv_MarketBenchmarkAssignments__c assignment;Integer primary=0;
        for(Inv_MarketBenchmarkAssignments__c a:assignments)if(a.Role__c=='primary'){assignment=a;primary++;}
        String status=primary==0?'benchmark_assignment_and_verified_history_required':primary>1?'ambiguous_primary_benchmark':
            assignment.DocumentRef__c==null?'benchmark_assignment_evidence_required':assignment.BenchmarkRef__r.BenchmarkVariant__c!='TRI'?'total_return_benchmark_required':null;
        if(status!=null) {
            result.metrics.add(metric(fund,null,'Benchmark comparison',null,endDate,null,status));result.fingerprint=InvPortfolioEngine.hash(JSON.serialize(assignments));return result;
        }
        Id benchmark=assignment.BenchmarkRef__c;
        List<Inv_MarketPriceObservations__c> prices=[SELECT Id,ObservedOn__c,Value__c,QualityStatus__c,PriceKind__c FROM Inv_MarketPriceObservations__c
            WHERE InstrumentRef__c=:benchmark AND ObservedOn__c<=:endDate WITH SYSTEM_MODE ORDER BY ObservedOn__c,ReceivedAt__c DESC,Id DESC LIMIT 45000];
        if(prices.size()==45000)throw new InvMath.CalculationException('Benchmark history exceeds one calculation scope');
        Map<Date,Decimal> tri=new Map<Date,Decimal>();
        for(Inv_MarketPriceObservations__c p:prices)if(p.PriceKind__c=='TRI' && p.QualityStatus__c=='accepted' && !tri.containsKey(p.ObservedOn__c) && InvMath.exact(p.Value__c)>0)tri.put(p.ObservedOn__c,InvMath.exact(p.Value__c));
        List<Date> common=new List<Date>();for(Date d:tri.keySet())if(navs.containsKey(d) && d>=assignment.EffectiveFrom__c)common.add(d);common.sort();
        if(common.isEmpty())result.metrics.add(metric(fund,benchmark,'Benchmark comparison',null,endDate,null,'no_common_verified_price_dates'));
        else {
            Date last=common[common.size()-1];
            for(Integer months:new List<Integer>{1,3,6,12,36,60}) {
                Date target=last.addMonths(-months),start;for(Date d:common)if(d<=target)start=d;
                String coverage=start==null?'assignment_or_history_does_not_cover_period':last.daysBetween(endDate)>4?'benchmark_series_ends_before_latest_fund_nav':'matched_dates';
                Decimal fundReturn,benchmarkReturn;
                if(start!=null) {
                    fundReturn=navs.get(last)/navs.get(start)-1;benchmarkReturn=tri.get(last)/tri.get(start)-1;
                    if(months>=12) {
                        Double exponent=Double.valueOf(String.valueOf(365.0/start.daysBetween(last)));
                        fundReturn=Decimal.valueOf(String.valueOf(Math.pow(Double.valueOf(String.valueOf(fundReturn+1)),exponent)-1));
                        benchmarkReturn=Decimal.valueOf(String.valueOf(Math.pow(Double.valueOf(String.valueOf(benchmarkReturn+1)),exponent)-1));
                    }
                }
                result.metrics.add(metric(fund,benchmark,'Fund matched '+months+' month return',start,last,fundReturn,coverage));
                result.metrics.add(metric(fund,benchmark,'Benchmark '+months+' month return',start,last,benchmarkReturn,coverage));
                result.metrics.add(metric(fund,benchmark,'Excess '+months+' month return',start,last,fundReturn==null?null:fundReturn-benchmarkReturn,coverage));
            }
        }
        result.fingerprint=InvPortfolioEngine.hash(JSON.serialize(assignments)+JSON.serialize(prices));return result;
    }
    private static Inv_FundMetric__c metric(Id fund,Id benchmark,String name,Date start,Date endDate,Decimal value,String coverage) {
        return new Inv_FundMetric__c(Name=name,Fund__c=fund,Benchmark__c=benchmark,Metric__c=name,PeriodStart__c=start,PeriodEnd__c=endDate,Value__c=value,Coverage__c=coverage,Published__c=true);
    }
}
