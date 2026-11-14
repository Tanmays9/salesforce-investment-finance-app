public without sharing class InvPortfolioEngine {
    public static final String VERSION='sf-portfolio-1';
    public static String hash(String value) {return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256',Blob.valueOf(value)));}
    private static String pair(Id account,Id fund) {return String.valueOf(account)+':'+String.valueOf(fund);}
    public static Id calculate(Id portfolioId,Date asOf) {
        // Services are called only by permission-gated actions or the scheduled service identity.
        Inv_PortfolioPortfolios__c portfolio=[SELECT Id,Name__c,PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:portfolioId  WITH SYSTEM_MODE FOR UPDATE];
        Map<Id,Inv_PortfolioAccounts__c> accounts=new Map<Id,Inv_PortfolioAccounts__c>([
            SELECT Id,MaskedReference__c FROM Inv_PortfolioAccounts__c WHERE PortfolioRef__c=:portfolioId WITH SYSTEM_MODE ]);
        Set<Id> accountIds=accounts.keySet();
        Set<Id> reversed=new Set<Id>();
        for(Inv_PortfolioEvents__c e:[SELECT ReversesRef__c FROM Inv_PortfolioEvents__c WHERE PostedAt__c!=null AND ReversesRef__c!=null WITH SYSTEM_MODE ])reversed.add(e.ReversesRef__c);
        List<Inv_PortfolioUnitEntries__c> source=[
            SELECT Id,AccountRef__c,InstrumentRef__c,InstrumentRef__r.Name__c,UnitsDelta__c,AcquisitionCost__c,
                AcquisitionDate__c,ConsiderationAmount__c,ConsiderationBasis__c,EventRef__c,EventRef__r.EventDate__c,
                EventRef__r.SourceSequence__c,EventRef__r.EventType__c,Currency__c
            FROM Inv_PortfolioUnitEntries__c WHERE AccountRef__c IN :accountIds AND EventRef__r.PostedAt__c!=null
                AND EventRef__r.EventDate__c<=:asOf
             WITH SYSTEM_MODE ORDER BY EventRef__r.EventDate__c,EventRef__r.SourceSequenceNumber__c,EventRef__r.Id,Id];
        Map<String,List<InvMath.Entry>> grouped=new Map<String,List<InvMath.Entry>>();
        Map<String,Inv_Holding__c> holdings=new Map<String,Inv_Holding__c>();Set<Id> fundIds=new Set<Id>();
        Map<Id,Decimal> charges=new Map<Id,Decimal>();
        for(Inv_PortfolioEventCharges__c c:[SELECT EventRef__c,Amount__c,IncludedInNetCash__c FROM Inv_PortfolioEventCharges__c
            WHERE EventRef__r.EventDate__c<=:asOf AND IncludedInNetCash__c=true WITH SYSTEM_MODE ])
            charges.put(c.EventRef__c,(charges.containsKey(c.EventRef__c)?charges.get(c.EventRef__c):0)+InvMath.exact(c.Amount__c));
        for(Inv_PortfolioUnitEntries__c u:source) {
            if(reversed.contains(u.EventRef__c) || u.EventRef__r.EventType__c=='reversal')continue;
            if(u.Currency__c!='INR')throw new InvMath.CalculationException('Currency conversion is not configured');
            String key=pair(u.AccountRef__c,u.InstrumentRef__c);fundIds.add(u.InstrumentRef__c);
            if(!grouped.containsKey(key)) {
                grouped.put(key,new List<InvMath.Entry>());
                String title=u.InstrumentRef__r.Name__c+' / '+accounts.get(u.AccountRef__c).MaskedReference__c;
                holdings.put(key,new Inv_Holding__c(Key__c=key,Name=title.left(80),Portfolio__c=portfolioId,
                    Account__c=u.AccountRef__c,Fund__c=u.InstrumentRef__c,SIPAmount__c=0));
            }
            InvMath.Entry e=new InvMath.Entry();e.identity=String.valueOf(u.EventRef__c)+String.valueOf(u.Id);
            e.day=u.EventRef__r.EventDate__c;e.acquired=u.AcquisitionDate__c;e.sequence=InvMath.exact(u.EventRef__r.SourceSequence__c);
            e.units=InvMath.exact(u.UnitsDelta__c);e.cost=InvMath.exact(u.AcquisitionCost__c);
            e.consideration=InvMath.exact(u.ConsiderationAmount__c);e.basis=u.ConsiderationBasis__c;e.kind=u.EventRef__r.EventType__c;
            // Fund cashflows use acquisition cost; gross sale proceeds need charge adjustment below.
            grouped.get(key).add(e);
        }
        Map<Id,Inv_MarketPriceObservations__c> prices=new Map<Id,Inv_MarketPriceObservations__c>();
        for(Id fund:fundIds) {
            List<Inv_MarketPriceObservations__c> rows=[SELECT Id,Value__c,ObservedOn__c,ProviderRef__r.Name__c,RevisionNo__c,PriceKind__c,QualityStatus__c
                FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c=:fund AND ObservedOn__c<=:asOf
                 WITH SYSTEM_MODE ORDER BY ObservedOn__c DESC,RevisionNoNumber__c DESC,ReceivedAt__c DESC LIMIT 200];
            // Bound recent revisions; absence of an accepted NAV is surfaced, never replaced by another price kind.
            for(Inv_MarketPriceObservations__c price:rows)if(price.PriceKind__c=='NAV' && price.QualityStatus__c=='accepted') {
                if(!prices.containsKey(fund))prices.put(fund,price);
                else if(price.ObservedOn__c==prices.get(fund).ObservedOn__c && price.ProviderRef__r.Name__c=='AMFI' && prices.get(fund).ProviderRef__r.Name__c!='AMFI')prices.put(fund,price);
            }
        }
        Map<String,Inv_PortfolioPositionSnapshots__c> snapshots=new Map<String,Inv_PortfolioPositionSnapshots__c>();
        for(Inv_PortfolioPositionSnapshots__c s:[SELECT AccountRef__c,InstrumentRef__c,AsOf__c,ReportedUnits__c FROM Inv_PortfolioPositionSnapshots__c
            WHERE AccountRef__c IN :accountIds AND AsOf__c<=:asOf  WITH SYSTEM_MODE ORDER BY AsOf__c DESC,Id DESC]) {
            String k=pair(s.AccountRef__c,s.InstrumentRef__c);if(!snapshots.containsKey(k))snapshots.put(k,s);
        }
        List<Inv_PortfolioSipVersions__c> sipInputs=[SELECT Id,AccountRef__c,InstrumentRef__r.InstrumentRef__c,Amount__c,Frequency__c,EffectiveFrom__c,EffectiveTo__c,
            VerificationState__c,ReportedStatus__c FROM Inv_PortfolioSipVersions__c WHERE AccountRef__c IN :accountIds
            AND EffectiveFrom__c<=:asOf AND (EffectiveTo__c=null OR EffectiveTo__c>:asOf) WITH SYSTEM_MODE ORDER BY Id];
        for(Inv_PortfolioSipVersions__c sip:sipInputs) {
            String k=pair(sip.AccountRef__c,sip.InstrumentRef__r.InstrumentRef__c);
            if(holdings.containsKey(k) && sip.ReportedStatus__c=='active' && sip.VerificationState__c=='user_confirmed' && sip.Frequency__c=='monthly')
                holdings.get(k).SIPAmount__c+=InvMath.exact(sip.Amount__c);
        }
        Map<Id,Inv_MarketFundShareClasses__c> classes=new Map<Id,Inv_MarketFundShareClasses__c>();
        Set<Id> schemes=new Set<Id>();
        for(Inv_MarketFundShareClasses__c c:[SELECT InstrumentRef__c,SchemeRef__c,SchemeRef__r.AmcRef__r.Name__c FROM Inv_MarketFundShareClasses__c WHERE InstrumentRef__c IN :fundIds WITH SYSTEM_MODE ]) {
            classes.put(c.InstrumentRef__c,c);schemes.add(c.SchemeRef__c);
        }
        Map<Id,String> categories=new Map<Id,String>();
        for(Inv_MarketSchemeVersions__c v:[SELECT SchemeRef__c,Category__c FROM Inv_MarketSchemeVersions__c
            WHERE SchemeRef__c IN :schemes AND EffectiveFrom__c<=:asOf AND (EffectiveTo__c=null OR EffectiveTo__c>:asOf)
             WITH SYSTEM_MODE ORDER BY EffectiveFrom__c DESC])if(!categories.containsKey(v.SchemeRef__c))categories.put(v.SchemeRef__c,v.Category__c);
        String compositionFingerprint=InvExposureEngine.fingerprint(fundIds,asOf);
        String fingerprint=hash(JSON.serialize(source)+JSON.serialize(prices)+JSON.serialize(snapshots)+JSON.serialize(sipInputs)+JSON.serialize(reversed)+
            JSON.serialize(charges)+JSON.serialize(classes)+JSON.serialize(categories)+compositionFingerprint+String.valueOf(asOf)+VERSION);
        Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='operational:'+portfolioId+':'+fingerprint,
            PortfolioRef__c=portfolioId,Kind__c='portfolio_valuation',ValuationAsOf__c=asOf,KnowledgeCutoff__c=System.now(),LedgerCutoff__c=System.now(),
            AlgorithmVersion__c=VERSION,InputFingerprint__c=fingerprint,StartedAt__c=System.now(),Status__c='running',OperationalStatus__c='Running',
            Assumptions__c='INR; latest accepted NAV on/before valuation date; FIFO per account and instrument; portfolio XIRR requires external cashflow confirmation.',
            InputManifest__c=JSON.serialize(new Map<String,Object>{'ledgerRows'=>source.size(),'funds'=>fundIds,'compositionFingerprint'=>compositionFingerprint,'asOf'=>asOf}));
        upsert as system run MigrationKey__c;
        String portfolioTitle=String.isBlank(portfolio.Name__c)?'Portfolio':portfolio.Name__c;
        Inv_PortfolioValuation__c total=new Inv_PortfolioValuation__c(Key__c=String.valueOf(run.Id),Name=portfolioTitle.left(64)+' '+String.valueOf(asOf),
            Portfolio__c=portfolioId,Run__c=run.Id,AsOf__c=asOf,MarketValue__c=0,Cost__c=0,UnrealizedGain__c=0,
            RealizedGain__c=0,MonthlySIP__c=0,HoldingCount__c=0,InputHash__c=fingerprint,Published__c=true,LatestForDate__c=true);
        List<String> issues=new List<String>();Boolean valueKnown=true,costKnown=true,realizedKnown=true;
        for(String k:grouped.keySet()) {
            Inv_Holding__c h=holdings.get(k);InvMath.Position p=InvMath.fifo(grouped.get(k));
            h.Units__c=p.units;h.Status__c=p.units==0?'Closed':'Active';h.Run__c=run.Id;
            h.Cost__c=p.basisKnown?p.cost:null;h.RealizedGain__c=p.realizedKnown?p.realized:null;
            List<String> warnings=new List<String>();
            if(!p.basisKnown){warnings.add('Missing acquisition cost');costKnown=false;}
            if(!p.realizedKnown){warnings.add('Gross proceeds unavailable; realized gain incomplete');realizedKnown=false;}
            if(classes.containsKey(h.Fund__c)) {
                Inv_MarketFundShareClasses__c c=classes.get(h.Fund__c);h.AMC__c=c.SchemeRef__r.AmcRef__r.Name__c;
                h.Category__c=categories.get(c.SchemeRef__c);
            }
            if(snapshots.containsKey(k)) {
                Inv_PortfolioPositionSnapshots__c s=snapshots.get(k);Decimal through=0;
                for(InvMath.Entry e:grouped.get(k))if(e.day<=s.AsOf__c)through+=e.units;
                if(through==InvMath.exact(s.ReportedUnits__c))h.ReconciledThrough__c=s.AsOf__c;
                else warnings.add('Statement units do not reconcile');
            } else warnings.add('No statement reconciliation evidence');
            if(p.units==0)h.MarketValue__c=0;
            else if(prices.containsKey(h.Fund__c)) {
                Inv_MarketPriceObservations__c price=prices.get(h.Fund__c);h.NAV__c=InvMath.exact(price.Value__c);
                if(h.NAV__c<=0)throw new InvMath.CalculationException('Invalid nonpositive NAV');
                h.NAVDate__c=price.ObservedOn__c;h.MarketValue__c=p.units*h.NAV__c;
                if(total.EarliestNAV__c==null || h.NAVDate__c<total.EarliestNAV__c)total.EarliestNAV__c=h.NAVDate__c;
                if(total.LatestNAV__c==null || h.NAVDate__c>total.LatestNAV__c)total.LatestNAV__c=h.NAVDate__c;
                if(h.NAVDate__c.daysBetween(asOf)>4)warnings.add('NAV may be stale; check publication calendar');
            } else {warnings.add('Missing accepted NAV');valueKnown=false;}
            h.UnrealizedGain__c=h.MarketValue__c==null || h.Cost__c==null?null:h.MarketValue__c-h.Cost__c;
            List<InvMath.FlowPoint> flows=new List<InvMath.FlowPoint>();Boolean complete=p.cashflowStatus!='incomplete';
            for(InvMath.Entry e:grouped.get(k)) {
                Decimal flow=e.units>0?e.cost:e.consideration;
                if(e.units<0 && e.basis=='gross') {
                    Id eventId=(Id)e.identity.substring(0,18);flow=flow==null?null:flow-(charges.containsKey(eventId)?charges.get(eventId):0);
                }
                if(flow==null)complete=false;else flows.add(new InvMath.FlowPoint(e.day,e.units>0?-flow:flow));
            }
            if(complete && h.MarketValue__c!=null) {
                flows.add(new InvMath.FlowPoint(asOf,h.MarketValue__c));InvMath.ReturnResult r=InvMath.xirr(flows);
                h.XIRR__c=r.rate;if(r.status!='ok')warnings.add('XIRR: '+r.status);
            } else warnings.add('Personal return requires complete cashflows');
            h.Coverage__c=warnings.isEmpty()?'complete':'needs_review';h.Warnings__c=String.join(warnings,'; ');
            if(!warnings.isEmpty())issues.add(h.Name+': '+h.Warnings__c);
            total.MarketValue__c+=h.MarketValue__c==null?0:h.MarketValue__c;total.Cost__c+=h.Cost__c==null?0:h.Cost__c;
            total.RealizedGain__c+=h.RealizedGain__c==null?0:h.RealizedGain__c;total.MonthlySIP__c+=h.SIPAmount__c;
            if(p.units>0)total.HoldingCount__c++;
        }
        if(!valueKnown)total.MarketValue__c=null;if(!costKnown)total.Cost__c=null;if(!realizedKnown)total.RealizedGain__c=null;
        total.UnrealizedGain__c=total.MarketValue__c==null || total.Cost__c==null?null:total.MarketValue__c-total.Cost__c;
        issues.add('Portfolio XIRR unavailable: external cash history not confirmed. Fund XIRR derives from recorded acquisition costs and redemption cashflows.');
        total.Coverage__c=String.join(issues,'\n').left(32768);
        List<Inv_Holding__c> holdingRows=holdings.values();
        for(Inv_Holding__c h:holdingRows)h.Weight__c=total.MarketValue__c==null || total.MarketValue__c==0 || h.MarketValue__c==null?null:h.MarketValue__c/total.MarketValue__c;
        for(Inv_Holding__c holding:holdingRows)InvMath.capture(holding);
        upsert as system holdingRows Key__c;
        List<Inv_HoldingValuation__c> values=new List<Inv_HoldingValuation__c>();
        for(Inv_Holding__c h:holdingRows) values.add(new Inv_HoldingValuation__c(Key__c=run.Id+':'+h.Key__c,Name=h.Name,
            Holding__c=h.Id,Portfolio__c=portfolioId,Fund__c=h.Fund__c,Run__c=run.Id,AsOf__c=asOf,NAVDate__c=h.NAVDate__c,
            Units__c=h.Units__c,NAV__c=h.NAV__c,Cost__c=h.Cost__c,MarketValue__c=h.MarketValue__c,
            UnrealizedGain__c=h.UnrealizedGain__c,Coverage__c=h.Coverage__c,Published__c=true));
        if(portfolio.PublishedRun__c!=null && portfolio.PublishedRun__c!=run.Id) {
            List<Inv_PortfolioValuation__c> old=[SELECT Id,Published__c,AsOf__c,LatestForDate__c FROM Inv_PortfolioValuation__c WHERE Portfolio__c=:portfolioId AND (Published__c=true OR (AsOf__c=:asOf AND LatestForDate__c=true)) WITH SYSTEM_MODE ];
            for(Inv_PortfolioValuation__c o:old){o.Published__c=false;if(o.AsOf__c==asOf)o.LatestForDate__c=false;}update as system old;
            List<Inv_HoldingValuation__c> prior=[SELECT Id,Published__c FROM Inv_HoldingValuation__c WHERE Portfolio__c=:portfolioId AND Published__c=true WITH SYSTEM_MODE ];
            for(Inv_HoldingValuation__c o:prior)o.Published__c=false;update as system prior;
        }
        for(Inv_HoldingValuation__c value:values)InvMath.capture(value);InvMath.capture(total);
        upsert as system values Key__c;upsert as system total Key__c;
        InvExposureEngine.calculate(portfolioId,run.Id,asOf,holdingRows,total.MarketValue__c);
        portfolio.PublishedRun__c=run.Id;update as system portfolio;
        run.Status__c='complete';run.OperationalStatus__c='Published';run.CompletedAt__c=System.now();update as system run;
        return run.Id;
    }
}
