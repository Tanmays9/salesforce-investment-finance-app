public without sharing class InvExposureEngine {
    public static String fingerprint(Set<Id> funds,Date asOf) {
        Set<Id> schemes=new Set<Id>();for(Inv_MarketFundShareClasses__c c:[SELECT SchemeRef__c FROM Inv_MarketFundShareClasses__c WHERE InstrumentRef__c IN :funds WITH SYSTEM_MODE])schemes.add(c.SchemeRef__c);
        Set<Id> snapshotIds=new Set<Id>();Set<Id> seen=new Set<Id>();
        List<Inv_MarketFundPortfolioSnapshots__c> snapshots=[SELECT Id,SchemeRef__c,HoldingsAsOf__c,CoverageState__c,WeightBasis__c FROM Inv_MarketFundPortfolioSnapshots__c
            WHERE SchemeRef__c IN :schemes AND HoldingsAsOf__c<=:asOf WITH SYSTEM_MODE ORDER BY HoldingsAsOf__c DESC,RevisionNoNumber__c DESC,Id DESC];
        List<Inv_MarketFundPortfolioSnapshots__c> chosen=new List<Inv_MarketFundPortfolioSnapshots__c>();
        for(Inv_MarketFundPortfolioSnapshots__c snapshot:snapshots)if(!seen.contains(snapshot.SchemeRef__c)){chosen.add(snapshot);snapshotIds.add(snapshot.Id);seen.add(snapshot.SchemeRef__c);}
        List<Inv_MarketFundPortfolioPositions__c> positions=[SELECT Id,SnapshotRef__c,SecurityRef__c,RawLabel__c,WeightRatio__c,AssetKind__c,Sector__c,MarketCapBand__c,ClassificationAsOf__c
            FROM Inv_MarketFundPortfolioPositions__c WHERE SnapshotRef__c IN :snapshotIds WITH SYSTEM_MODE ORDER BY Id];
        return InvPortfolioEngine.hash(JSON.serialize(chosen)+JSON.serialize(positions));
    }
    public static List<Inv_Exposure__c> build(Id portfolio,Id run,Date asOf,List<Inv_Holding__c> holdings,Decimal total) {
        Map<Id,Decimal> fundValues=new Map<Id,Decimal>();
        for(Inv_Holding__c h:holdings)if(h.Units__c>0 && h.MarketValue__c!=null)
            fundValues.put(h.Fund__c,(fundValues.containsKey(h.Fund__c)?fundValues.get(h.Fund__c):0)+h.MarketValue__c);
        Map<Id,Id> fundSchemes=new Map<Id,Id>();
        for(Inv_MarketFundShareClasses__c c:[SELECT InstrumentRef__c,SchemeRef__c FROM Inv_MarketFundShareClasses__c WHERE InstrumentRef__c IN :fundValues.keySet() WITH SYSTEM_MODE ])fundSchemes.put(c.InstrumentRef__c,c.SchemeRef__c);
        Map<Id,Inv_MarketFundPortfolioSnapshots__c> snapshots=new Map<Id,Inv_MarketFundPortfolioSnapshots__c>();
        Set<Id> schemes=new Set<Id>(fundSchemes.values());
        for(Inv_MarketFundPortfolioSnapshots__c s:[SELECT Id,SchemeRef__c,HoldingsAsOf__c,CoverageState__c,WeightBasis__c FROM Inv_MarketFundPortfolioSnapshots__c
            WHERE SchemeRef__c IN :schemes AND HoldingsAsOf__c<=:asOf  WITH SYSTEM_MODE ORDER BY HoldingsAsOf__c DESC,RevisionNoNumber__c DESC,Id DESC])if(!snapshots.containsKey(s.SchemeRef__c))snapshots.put(s.SchemeRef__c,s);
        Set<Id> snapIds=new Set<Id>();for(Inv_MarketFundPortfolioSnapshots__c s:snapshots.values())snapIds.add(s.Id);
        Map<Id,List<Inv_MarketFundPortfolioPositions__c>> positions=new Map<Id,List<Inv_MarketFundPortfolioPositions__c>>();
        for(Inv_MarketFundPortfolioPositions__c p:[SELECT SnapshotRef__c,SecurityRef__c,RawLabel__c,WeightRatio__c,AssetKind__c,Sector__c,MarketCapBand__c
            FROM Inv_MarketFundPortfolioPositions__c WHERE SnapshotRef__c IN :snapIds WITH SYSTEM_MODE ]) {
            if(!positions.containsKey(p.SnapshotRef__c))positions.put(p.SnapshotRef__c,new List<Inv_MarketFundPortfolioPositions__c>());positions.get(p.SnapshotRef__c).add(p);
        }
        Map<String,Inv_Exposure__c> rows=new Map<String,Inv_Exposure__c>();
        for(Id fund:fundValues.keySet()) {
            Inv_MarketFundPortfolioSnapshots__c snapshot=snapshots.get(fundSchemes.get(fund));
            if(snapshot==null || !positions.containsKey(snapshot.Id)) {
                add(rows,portfolio,run,fund,'Coverage','Missing composition',fundValues.get(fund),null,'unavailable');continue;
            }
            for(Inv_MarketFundPortfolioPositions__c p:positions.get(snapshot.Id)) {
                Decimal weight=InvMath.exact(p.WeightRatio__c);if(weight==null){add(rows,portfolio,run,fund,'Coverage','Missing weight',null,snapshot.HoldingsAsOf__c,'partial');continue;}
                Decimal value=fundValues.get(fund)*weight;
                add(rows,portfolio,run,fund,'Asset class',p.AssetKind__c,value,snapshot.HoldingsAsOf__c,snapshot.CoverageState__c);
                add(rows,portfolio,run,fund,'Sector',p.Sector__c,value,snapshot.HoldingsAsOf__c,snapshot.CoverageState__c);
                add(rows,portfolio,run,fund,'Market cap',p.MarketCapBand__c,value,snapshot.HoldingsAsOf__c,snapshot.CoverageState__c);
                add(rows,portfolio,run,fund,'Security',p.RawLabel__c,value,snapshot.HoldingsAsOf__c,p.SecurityRef__c==null?'identity_unmapped':snapshot.CoverageState__c);
            }
        }
        for(Inv_Exposure__c e:rows.values())e.Weight__c=total==null || total==0 || e.Value__c==null?null:e.Value__c/total;
        return rows.values();
    }
    public static void calculate(Id portfolio,Id run,Date asOf,List<Inv_Holding__c> holdings,Decimal total) {
        List<Inv_Exposure__c> values=build(portfolio,run,asOf,holdings,total);
        for(Inv_Exposure__c row:values)InvMath.capture(row);
        List<Inv_Exposure__c> prior=[SELECT Id,Published__c FROM Inv_Exposure__c WHERE Portfolio__c=:portfolio AND Published__c=true AND Run__c!=:run WITH SYSTEM_MODE];
        for(Inv_Exposure__c e:prior)e.Published__c=false;update as system prior;
        if(!values.isEmpty())upsert as system values Key__c;
    }
    private static void add(Map<String,Inv_Exposure__c> rows,Id portfolio,Id run,Id fund,String dimension,String member,Decimal value,Date day,String coverage) {
        member=String.isBlank(member)?'Unclassified':member;String k=InvPortfolioEngine.hash(run+':'+fund+':'+dimension+':'+member);
        if(!rows.containsKey(k))rows.put(k,new Inv_Exposure__c(Key__c=k,Name=(dimension+': '+member).left(80),Portfolio__c=portfolio,
            Fund__c=fund,Run__c=run,Dimension__c=dimension,Member__c=member.left(255),Value__c=value,DisclosureDate__c=day,Coverage__c=coverage.left(255),Published__c=true));
        else if(value!=null)rows.get(k).Value__c=(rows.get(k).Value__c==null?0:rows.get(k).Value__c)+value;
    }
}
