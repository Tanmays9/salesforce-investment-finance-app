public without sharing class InvPlanExposure {
    public static List<Inv_PlanImpact__c> compare(Id version,Id run,Id portfolio,Date asOf,Map<Id,Decimal> before,Map<Id,Decimal> after,Decimal total,Decimal cash) {
        Map<String,Inv_PlanImpact__c> impacts=new Map<String,Inv_PlanImpact__c>();
        for(Integer side=0;side<2;side++){
            Map<Id,Decimal> amounts=side==0?before:after;List<Inv_Holding__c> holdings=new List<Inv_Holding__c>();
            for(Id fund:amounts.keySet())if(amounts.get(fund)>0)holdings.add(new Inv_Holding__c(Fund__c=fund,Units__c=1,MarketValue__c=amounts.get(fund)));
            List<Inv_Exposure__c> exposure=InvExposureEngine.build(portfolio,run,asOf,holdings,total);
            if(side==1 && cash>0)exposure.add(new Inv_Exposure__c(Dimension__c='Asset class',Member__c='Scenario cash',Value__c=cash,Coverage__c='gross_cash_before_loads_and_taxes'));
            for(Inv_Exposure__c row:exposure){
                String identity=row.Dimension__c+':'+row.Member__c;
                if(!impacts.containsKey(identity))impacts.put(identity,new Inv_PlanImpact__c(Key__c=InvPortfolioEngine.hash(run+':exposure:'+identity),Name=(row.Dimension__c+': '+row.Member__c).left(80),
                    PlanVersion__c=version,Run__c=run,Scope__c='Exposure',Metric__c=row.Dimension__c+' exposure INR',Dimension__c=row.Dimension__c,Member__c=row.Member__c,
                    Baseline__c=0,Proposed__c=0,Published__c=true,Coverage__c='reported_weights_partial_coverage',Notes__c='Baseline composition dated on or before '+asOf+'. Cash, negative items and missing classifications are retained. Gross scenario prices; no forecast or normalization.'));
                Inv_PlanImpact__c impact=impacts.get(identity);
                if(row.Value__c==null){impact.Coverage__c='missing_weights';if(side==0)impact.Baseline__c=null;else impact.Proposed__c=null;continue;}
                if(side==0)impact.Baseline__c+=row.Value__c;else impact.Proposed__c+=row.Value__c;
            }
        }
        return impacts.values();
    }
}
