/** FIFO lot preview and evidence-backed redemption estimate. Never posts a trade. */
public with sharing class InvRedemptionService {
    public class Request {
        @AuraEnabled public Id portfolioId;
        @AuraEnabled public Id fundId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id planVersionId;
        @AuraEnabled public Id actionId;
        @AuraEnabled public Decimal requestedUnits;
        @AuraEnabled public Date settlementDate;
        @AuraEnabled public Boolean acknowledgeUnknownTax;
    }
    public class LotRow {
        @AuraEnabled public Id accountId; @AuraEnabled public String accountLabel;
        @AuraEnabled public Date acquiredOn; @AuraEnabled public Date eligibleOn;
        @AuraEnabled public Decimal availableUnits; @AuraEnabled public Decimal requestedUnits;
        @AuraEnabled public Decimal unitCost; @AuraEnabled public Decimal costBasis;
        @AuraEnabled public Decimal grossProceeds; @AuraEnabled public Decimal exitLoad;
        @AuraEnabled public Decimal realizedGain; @AuraEnabled public String eligibility;
        @AuraEnabled public String coverage; @AuraEnabled public Id policyId;
    }
    public class Preview {
        @AuraEnabled public Id portfolioId; @AuraEnabled public Id fundId; @AuraEnabled public Id baselineRunId;
        @AuraEnabled public Date valuationDate; @AuraEnabled public Date navDate; @AuraEnabled public Date settlementDate;
        @AuraEnabled public Decimal nav; @AuraEnabled public Decimal requestedUnits; @AuraEnabled public Decimal availableUnits;
        @AuraEnabled public Decimal grossProceeds; @AuraEnabled public Decimal costBasis; @AuraEnabled public Decimal exitLoad;
        @AuraEnabled public Decimal realizedGain; @AuraEnabled public Decimal estimatedTax; @AuraEnabled public Decimal netProceeds;
        @AuraEnabled public Decimal estimatedCashAfterLoad;
        @AuraEnabled public String eligibilityCoverage; @AuraEnabled public String basisCoverage; @AuraEnabled public String loadCoverage;
        @AuraEnabled public String taxCoverage; @AuraEnabled public String readiness; @AuraEnabled public String evidenceSummary;
        @AuraEnabled public List<LotRow> lots=new List<LotRow>();
    }
    private class LotSource {
        Id accountId;String accountLabel;Date acquired;Decimal units;Decimal unitCost;
    }
    private class PolicyInfo {
        Id id;String kind;String parameters;Id documentId;Date startDate;Date endDate;
    }
    public class RedemptionException extends Exception {}

    @AuraEnabled(cacheable=true)
    public static Preview preview(Request request) {
        return calculate(request);
    }
    @AuraEnabled
    public static Preview saveReview(Request request) {
        if(!FeatureManagement.checkPermission('Inv_ManagePortfolio'))throw new AuraHandledException('Portfolio Manager permission is required to save a redemption review.');
        if(request==null || request.planVersionId==null || request.actionId==null)throw new AuraHandledException('Choose the draft redemption action this review supports.');
        Inv_PlanningActions__c action=[SELECT Id,PlanVersionRef__c,ActionType__c,InstrumentRef__c,AccountRef__c,RequestedAmount__c,RequestedUnits__c,AllAvailable__c,IntendedDate__c
            FROM Inv_PlanningActions__c WHERE Id=:request.actionId WITH USER_MODE];
        if(request.settlementDate==null)throw new AuraHandledException('Enter an assumed settlement date before saving this redemption review.');
        if(action.IntendedDate__c!=null && request.settlementDate<action.IntendedDate__c)
            throw new AuraHandledException('The settlement date cannot precede the planned redemption date.');
        if(request.accountId==null && action.AccountRef__c!=null)request.accountId=action.AccountRef__c;
        if(request.requestedUnits==null && action.RequestedUnits__c!=null)request.requestedUnits=InvMath.exact(action.RequestedUnits__c);
        Preview preview=calculate(request);
        Inv_PlanningPlanVersions__c version=[SELECT Id,BaselineRunRef__c,BaselineInputFingerprint__c,TaxAssumptionAcknowledged__c
            FROM Inv_PlanningPlanVersions__c WHERE Id=:request.planVersionId FOR UPDATE];
        if(action.PlanVersionRef__c!=version.Id || action.ActionType__c!='redeem' || action.InstrumentRef__c!=request.fundId)
            throw new AuraHandledException('The selected plan action is not a redemption for this fund.');
        if(version.BaselineRunRef__c!=preview.baselineRunId)throw new AuraHandledException('The selected redemption action uses a different baseline. Rebase the plan before saving its estimate.');
        if(action.AccountRef__c!=null && action.AccountRef__c!=request.accountId)throw new AuraHandledException('The selected account does not match the redemption action.');
        if(action.AllAvailable__c==true && preview.requestedUnits!=preview.availableUnits)throw new AuraHandledException('This action is a full redemption; preview the full available units for the selected account scope.');
        if(action.RequestedUnits__c!=null && (preview.requestedUnits-InvMath.exact(action.RequestedUnits__c)).abs()>0.00000001)
            throw new AuraHandledException('The reviewed units do not match the requested plan action.');
        if(action.RequestedUnits__c==null && !String.isBlank(action.RequestedAmount__c)
            && (preview.grossProceeds-InvMath.exact(action.RequestedAmount__c)).abs()>0.01)
            throw new AuraHandledException('The reviewed proceeds do not match the requested plan amount at the selected baseline NAV.');
        Savepoint point=Database.setSavepoint();
        try {
            String identity=InvPortfolioEngine.hash(action.Id+':'+preview.baselineRunId+':'+String.valueOf(preview.requestedUnits)+':'+String.valueOf(request.settlementDate)+':'+preview.evidenceSummary);
            List<Inv_RedemptionEstimates__c> prior=[SELECT Id,Published__c FROM Inv_RedemptionEstimates__c WHERE Action__c=:action.Id AND Published__c=true FOR UPDATE];
            for(Inv_RedemptionEstimates__c row:prior)row.Published__c=false;if(!prior.isEmpty())update as system prior;
            Inv_RedemptionEstimates__c estimate=new Inv_RedemptionEstimates__c(Key__c='redemption:'+identity,
                Portfolio__c=preview.portfolioId,PlanVersion__c=version.Id,AnalysisRun__c=preview.baselineRunId,Action__c=action.Id,
                Fund__c=preview.fundId,ValuationAsOf__c=preview.valuationDate,RequestedUnits__c=preview.requestedUnits,
                GrossProceeds__c=preview.grossProceeds,CostBasis__c=preview.costBasis,ExitLoad__c=preview.exitLoad,
                RealizedGain__c=preview.realizedGain,EstimatedTax__c=preview.estimatedTax,NetProceeds__c=preview.netProceeds,
                EligibilityCoverage__c=preview.eligibilityCoverage,BasisCoverage__c=preview.basisCoverage,ProceedsCoverage__c='baseline_nav_estimate',
                LoadCoverage__c=preview.loadCoverage,TaxCoverage__c=preview.taxCoverage,SettlementDate__c=request.settlementDate,
                Assumptions__c=preview.evidenceSummary,Published__c=true);
            InvMath.capture(estimate);upsert as system estimate Key__c;
            List<Inv_RedemptionLotAllocations__c> allocations=new List<Inv_RedemptionLotAllocations__c>();Integer index=0;
            for(LotRow lot:preview.lots) {
                index++;Inv_RedemptionLotAllocations__c allocation=new Inv_RedemptionLotAllocations__c(Key__c=identity+':'+String.valueOf(index),
                    Estimate__c=estimate.Id,Account__c=lot.accountId,Fund__c=preview.fundId,
                    AcquiredOn__c=lot.acquiredOn,EligibleOn__c=lot.eligibleOn,RequestedUnits__c=lot.requestedUnits,UnitCost__c=lot.unitCost,
                    CostBasis__c=lot.costBasis,GrossProceeds__c=lot.grossProceeds,ExitLoad__c=lot.exitLoad,RealizedGain__c=lot.realizedGain,
                    Eligibility__c=lot.eligibility,Coverage__c=lot.coverage,Evidence__c=lot.policyId);
                InvMath.capture(allocation);allocations.add(allocation);
            }
            if(!allocations.isEmpty())upsert as system allocations Key__c;
            if(request.acknowledgeUnknownTax==true)version.TaxAssumptionAcknowledged__c=true;
            version.ApprovalReadiness__c=preview.readiness;update as system version;
            return preview;
        } catch(Exception e) {
            Database.rollback(point);throw new AuraHandledException(e.getMessage());
        }
    }

    private static Preview calculate(Request request) {
        if(request==null || (request.portfolioId==null && request.planVersionId==null && request.actionId==null) || request.fundId==null)
            throw new AuraHandledException('Choose a portfolio and fund.');
        Inv_PlanningActions__c linkedAction;
        if(request.actionId!=null) {
            linkedAction=[SELECT Id,PlanVersionRef__c,ActionType__c,InstrumentRef__c,AccountRef__c,RequestedAmount__c,RequestedUnits__c,AllAvailable__c
                FROM Inv_PlanningActions__c WHERE Id=:request.actionId WITH USER_MODE];
            if(linkedAction.ActionType__c!='redeem')throw new AuraHandledException('The selected plan action is not a redemption.');
            if(linkedAction.PlanVersionRef__c==null)throw new AuraHandledException('The selected redemption action is not linked to a plan version.');
            if(linkedAction.InstrumentRef__c!=request.fundId)throw new AuraHandledException('The selected action is for a different fund.');
            if(request.planVersionId!=null && linkedAction.PlanVersionRef__c!=request.planVersionId)
                throw new AuraHandledException('The selected action is in a different plan version.');
            if(request.planVersionId==null)request.planVersionId=linkedAction.PlanVersionRef__c;
            if(linkedAction.AllAvailable__c==true) {
                if(request.accountId!=null && request.accountId!=linkedAction.AccountRef__c)
                    throw new AuraHandledException('The selected action covers its saved account scope. Clear the account selection or use an action for that account.');
                request.accountId=linkedAction.AccountRef__c;
                request.requestedUnits=null;
            } else {
                if(linkedAction.AccountRef__c!=null && request.accountId!=null && linkedAction.AccountRef__c!=request.accountId)
                    throw new AuraHandledException('The selected account does not match the draft redemption action.');
                if(request.accountId==null && linkedAction.AccountRef__c!=null)request.accountId=linkedAction.AccountRef__c;
                if(request.requestedUnits==null && linkedAction.RequestedUnits__c!=null)
                    request.requestedUnits=InvMath.exact(linkedAction.RequestedUnits__c);
            }
            if(request.portfolioId==null && request.planVersionId!=null) {
                Inv_PlanningPlanVersions__c actionVersion=[SELECT PlanRef__r.PortfolioRef__c FROM Inv_PlanningPlanVersions__c
                    WHERE Id=:request.planVersionId WITH USER_MODE];
                request.portfolioId=actionVersion.PlanRef__r.PortfolioRef__c;
            }
        }
        Inv_PortfolioPortfolios__c portfolio;
        Inv_AnalyticsRuns__c run;
        if(request.planVersionId!=null) {
            Inv_PlanningPlanVersions__c version=[SELECT Id,PlanRef__r.PortfolioRef__c,BaselineRunRef__c FROM Inv_PlanningPlanVersions__c WHERE Id=:request.planVersionId WITH USER_MODE];
            if(request.portfolioId==null)request.portfolioId=version.PlanRef__r.PortfolioRef__c;
            else if(version.PlanRef__r.PortfolioRef__c!=request.portfolioId)throw new AuraHandledException('The chosen plan belongs to a different portfolio.');
            run=[SELECT Id,Status__c,ValuationAsOf__c,InputFingerprint__c,LedgerCutoff__c,KnowledgeCutoff__c FROM Inv_AnalyticsRuns__c WHERE Id=:version.BaselineRunRef__c WITH USER_MODE];
        } else {
            portfolio=[SELECT Id,PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:request.portfolioId WITH USER_MODE];
            if(portfolio.PublishedRun__c==null)throw new AuraHandledException('Calculate and publish the portfolio first.');
            run=[SELECT Id,Status__c,ValuationAsOf__c,InputFingerprint__c,LedgerCutoff__c,KnowledgeCutoff__c FROM Inv_AnalyticsRuns__c WHERE Id=:portfolio.PublishedRun__c WITH USER_MODE];
        }
        if(run.Status__c!='complete')throw new AuraHandledException('A completed baseline is required.');
        List<Inv_HoldingValuation__c> values=[SELECT Id,Holding__c,Holding__r.Account__c,Holding__r.Account__r.MaskedReference__c,Units__c,NAV__c,NAVDate__c
            FROM Inv_HoldingValuation__c WHERE Portfolio__c=:request.portfolioId AND Fund__c=:request.fundId AND Run__c=:run.Id
                AND Status__c='Active' WITH USER_MODE];
        if(values.isEmpty())throw new AuraHandledException('This fund has no active holding in the selected baseline.');
        Map<Id,String> accountLabels=new Map<Id,String>();Map<Id,Decimal> snapshotUnits=new Map<Id,Decimal>();Decimal nav;Date navDate;
        for(Inv_HoldingValuation__c row:values) {
            Id account=row.Holding__r==null?null:row.Holding__r.Account__c;if(account==null)continue;
            accountLabels.put(account,row.Holding__r.Account__r==null?null:row.Holding__r.Account__r.MaskedReference__c);
            snapshotUnits.put(account,(snapshotUnits.containsKey(account)?snapshotUnits.get(account):0)+(row.Units__c==null?0:row.Units__c));
            if(row.NAV__c!=null){if(nav!=null && nav!=row.NAV__c)throw new AuraHandledException('Baseline holdings have conflicting NAV values.');nav=row.NAV__c;}
            if(row.NAVDate__c!=null && (navDate==null || row.NAVDate__c>navDate))navDate=row.NAVDate__c;
        }
        if(nav==null || nav<=0)throw new AuraHandledException('The selected baseline has no usable NAV.');
        if(request.accountId!=null && !snapshotUnits.containsKey(request.accountId))throw new AuraHandledException('The selected account does not hold this fund in the baseline.');
        Set<Id> accountIds=request.accountId==null?snapshotUnits.keySet():new Set<Id>{request.accountId};
        List<Inv_PortfolioUnitEntries__c> sourceEntries=[SELECT Id,AccountRef__c,UnitsDelta__c,AcquisitionCost__c,AcquisitionDate__c,ConsiderationAmount__c,
            ConsiderationBasis__c,EventRef__c,EventRef__r.EventDate__c,EventRef__r.SourceSequence__c,EventRef__r.EventType__c
            FROM Inv_PortfolioUnitEntries__c WHERE AccountRef__c IN :accountIds AND InstrumentRef__c=:request.fundId
                AND EventRef__r.PostedAt__c!=null AND EventRef__r.PostedAt__c<=:run.LedgerCutoff__c AND EventRef__r.CreatedDate<=:run.KnowledgeCutoff__c
                AND EventRef__r.EventDate__c<=:run.ValuationAsOf__c WITH USER_MODE ORDER BY EventRef__r.EventDate__c,EventRef__r.SourceSequenceNumber__c,EventRef__r.Id,Id LIMIT 30000];
        if(sourceEntries.size()==30000)throw new AuraHandledException('This account and fund ledger exceeds the redemption preview scope; resolve the historical ledger before previewing.');
        Set<Id> sourceEventIds=new Set<Id>();for(Inv_PortfolioUnitEntries__c source:sourceEntries)sourceEventIds.add(source.EventRef__c);
        Set<Id> reversed=new Set<Id>();
        if(!sourceEventIds.isEmpty())for(Inv_PortfolioEvents__c eventRow:[SELECT ReversesRef__c FROM Inv_PortfolioEvents__c WHERE ReversesRef__c IN :sourceEventIds
            AND PostedAt__c!=null AND PostedAt__c<=:run.LedgerCutoff__c AND CreatedDate<=:run.KnowledgeCutoff__c
            AND EventDate__c<=:run.ValuationAsOf__c WITH USER_MODE])reversed.add(eventRow.ReversesRef__c);
        Map<Id,List<InvMath.Entry>> entriesByAccount=new Map<Id,List<InvMath.Entry>>();
        for(Inv_PortfolioUnitEntries__c source:sourceEntries) {
            if(reversed.contains(source.EventRef__c) || source.EventRef__r.EventType__c=='reversal')continue;
            if(!entriesByAccount.containsKey(source.AccountRef__c))entriesByAccount.put(source.AccountRef__c,new List<InvMath.Entry>());
            InvMath.Entry entry=new InvMath.Entry();entry.identity=String.valueOf(source.EventRef__c)+String.valueOf(source.Id);entry.day=source.EventRef__r.EventDate__c;
            entry.acquired=source.AcquisitionDate__c;entry.sequence=InvMath.exact(source.EventRef__r.SourceSequence__c);entry.units=InvMath.exact(source.UnitsDelta__c);
            entry.cost=InvMath.exact(source.AcquisitionCost__c);entry.consideration=InvMath.exact(source.ConsiderationAmount__c);entry.basis=source.ConsiderationBasis__c;entry.kind=source.EventRef__r.EventType__c;
            entriesByAccount.get(source.AccountRef__c).add(entry);
        }
        Id schemeId;List<Inv_MarketFundShareClasses__c> share=[SELECT SchemeRef__c FROM Inv_MarketFundShareClasses__c WHERE InstrumentRef__c=:request.fundId WITH USER_MODE LIMIT 1];
        if(!share.isEmpty())schemeId=share[0].SchemeRef__c;
        List<PolicyInfo> policies=new List<PolicyInfo>();
        if(schemeId!=null)for(Inv_MarketEligibilityPolicies__c policy:[SELECT Id,Kind__c,Parameters__c,DocumentRef__c,EffectiveFrom__c,EffectiveTo__c,VerificationState__c
            FROM Inv_MarketEligibilityPolicies__c WHERE SchemeRef__c=:schemeId AND EffectiveFrom__c<=:run.ValuationAsOf__c
                AND (EffectiveTo__c=null OR EffectiveTo__c>:run.ValuationAsOf__c) WITH USER_MODE]) {
            if(policy.VerificationState__c!='verified')continue;
            PolicyInfo info=new PolicyInfo();info.id=policy.Id;info.kind=policy.Kind__c;info.parameters=policy.Parameters__c;info.documentId=policy.DocumentRef__c;
            info.startDate=policy.EffectiveFrom__c;info.endDate=policy.EffectiveTo__c;policies.add(info);
        }
        PolicyInfo lockPolicy=findPolicy(policies,'lock'),loadPolicy=findPolicy(policies,'exit_load');Integer lockDays=policyDays(lockPolicy);
        Boolean explicitNoLock=hasPolicy(policies,'no_lock');Boolean hasLockEvidence=lockDays!=null || explicitNoLock;
        Boolean hasLoadEvidence=loadPolicy!=null;Boolean basisComplete=true;Decimal available=0,requested=request.requestedUnits;
        Map<Id,List<LotSource>> availableLots=new Map<Id,List<LotSource>>();
        for(Id accountId:accountIds) {
            List<InvMath.Entry> entries=entriesByAccount.get(accountId);if(entries==null)entries=new List<InvMath.Entry>();
            InvMath.Position position;
            try {position=InvMath.fifo(entries);}catch(Exception ignored) {
                basisComplete=false;Decimal unknownUnits=snapshotUnits.get(accountId)==null?0:snapshotUnits.get(accountId);available+=unknownUnits;
                List<LotSource> unknownLots=new List<LotSource>();if(unknownUnits>0){LotSource unknown=new LotSource();unknown.accountId=accountId;unknown.accountLabel=accountLabels.get(accountId);unknown.units=unknownUnits;unknownLots.add(unknown);}
                availableLots.put(accountId,unknownLots);continue;
            }
            Decimal snapshot=snapshotUnits.get(accountId)==null?0:snapshotUnits.get(accountId);
            if(position.units!=snapshot)basisComplete=false;
            if(!position.basisKnown)basisComplete=false;
            available+=snapshot;Decimal unassigned=snapshot;List<LotSource> lots=new List<LotSource>();
            for(InvMath.Lot lot:position.lots)if(lot.units>0 && unassigned>0) {
                Decimal matched=lot.units<unassigned?lot.units:unassigned;LotSource item=new LotSource();item.accountId=accountId;item.accountLabel=accountLabels.get(accountId);
                item.acquired=lot.acquired;item.units=matched;item.unitCost=lot.unitCost;lots.add(item);unassigned-=matched;
            }
            if(unassigned>0){LotSource unknown=new LotSource();unknown.accountId=accountId;unknown.accountLabel=accountLabels.get(accountId);unknown.units=unassigned;lots.add(unknown);basisComplete=false;}
            availableLots.put(accountId,lots);
        }
        if(requested==null && linkedAction!=null) {
            if(linkedAction.AllAvailable__c!=true && !String.isBlank(linkedAction.RequestedAmount__c))
                requested=InvMath.exact(linkedAction.RequestedAmount__c)/nav;
        }
        if(requested==null)requested=available;
        if(requested<=0 || requested>available)throw new AuraHandledException('Requested units must be positive and no greater than the available baseline units.');
        if(request.accountId==null && requested<available)throw new AuraHandledException('Choose the investment account for a partial redemption. Full redemptions may cover all accounts.');
        Preview out=new Preview();out.portfolioId=request.portfolioId;out.fundId=request.fundId;out.baselineRunId=run.Id;out.valuationDate=run.ValuationAsOf__c;
        out.nav=nav;out.navDate=navDate;out.settlementDate=request.settlementDate;out.availableUnits=available;out.requestedUnits=requested;
        Decimal remaining=requested,totalGross=0,totalCost=0,totalLoad=0;Boolean costKnown=true,allEligible=hasLockEvidence,allLoads=hasLoadEvidence;
        List<Id> orderedAccounts=new List<Id>(accountIds);orderedAccounts.sort();
        for(Id accountId:orderedAccounts)for(LotSource lot:availableLots.get(accountId)) {
            if(remaining<=0)break;Decimal take=remaining<lot.units?remaining:lot.units;remaining-=take;
            LotRow row=new LotRow();row.accountId=accountId;row.accountLabel=lot.accountLabel;row.acquiredOn=lot.acquired;
            row.availableUnits=lot.units;row.requestedUnits=take;row.unitCost=lot.unitCost;row.grossProceeds=take*nav;
            if(lot.unitCost==null){costKnown=false;row.coverage='basis_missing';}
            else {row.costBasis=lot.unitCost*take;row.realizedGain=row.grossProceeds-row.costBasis;totalCost+=row.costBasis;row.coverage='basis_available';}
            row.eligibleOn=lockDays==null || lot.acquired==null?null:lot.acquired.addDays(lockDays);
            row.eligibility=explicitNoLock?'eligible':row.eligibleOn==null?'unknown':row.eligibleOn<=run.ValuationAsOf__c?'eligible':'locked';
            if(row.eligibility!='eligible')allEligible=false;
            row.policyId=lockPolicy==null?null:lockPolicy.id;
            Decimal loadRatio=loadRatio(loadPolicy,lot.acquired,run.ValuationAsOf__c);
            if(loadRatio==null){allLoads=false;row.coverage=row.coverage+'; exit_load_unknown';}
            else {row.exitLoad=row.grossProceeds*loadRatio;totalLoad+=row.exitLoad;}
            totalGross+=row.grossProceeds;out.lots.add(row);
        }
        if(remaining>0)throw new AuraHandledException('Available lots do not cover the requested quantity; review opening-history evidence.');
        out.grossProceeds=totalGross;out.costBasis=costKnown?totalCost:null;out.exitLoad=allLoads?totalLoad:null;
        out.realizedGain=costKnown?totalGross-totalCost:null;out.estimatedTax=null;out.netProceeds=null;
        out.estimatedCashAfterLoad=allLoads?totalGross-totalLoad:null;
        out.eligibilityCoverage=allEligible?'eligible':'evidence_required_or_locked';out.basisCoverage=costKnown?'complete':'incomplete';out.loadCoverage=allLoads?'complete':'evidence_required';
        out.taxCoverage=request.acknowledgeUnknownTax==true?'unknown_acknowledged':'acknowledgement_required';
        out.readiness=out.eligibilityCoverage=='eligible' && out.loadCoverage=='complete'
            && request.settlementDate!=null && request.acknowledgeUnknownTax==true?'Ready for plan approval':'Review required';
        List<String> evidence=new List<String>{'Baseline run '+run.Id,'Valuation date '+String.valueOf(run.ValuationAsOf__c),'NAV date '+String.valueOf(navDate),
            'NAV '+String.valueOf(nav),'Eligibility policy '+(lockPolicy==null?(explicitNoLock?'verified no-lock-in policy':'missing') : lockPolicy.id),
            'Exit-load policy '+(loadPolicy==null?'missing':loadPolicy.id),'Tax amount not estimated; no tax rate was supplied.',
            'Settlement date is a user assumption: '+String.valueOf(request.settlementDate)};
        out.evidenceSummary=String.join(evidence,'\n');return out;
    }
    private static PolicyInfo findPolicy(List<PolicyInfo> policies,String word) {
        for(PolicyInfo policy:policies)if(policy.kind!=null && policy.kind.toLowerCase().contains(word))return policy;return null;
    }
    private static Boolean hasPolicy(List<PolicyInfo> policies,String word) {return findPolicy(policies,word)!=null;}
    private static Integer policyDays(PolicyInfo policy) {
        if(policy==null || String.isBlank(policy.parameters))return null;
        try {Map<String,Object> parsed=(Map<String,Object>)JSON.deserializeUntyped(policy.parameters);
            for(String key:new List<String>{'lockInDays','lock_in_days','durationDays','days'})if(parsed.containsKey(key))return Integer.valueOf(String.valueOf(parsed.get(key)));
        } catch(Exception ignored) {return null;}return null;
    }
    private static Decimal loadRatio(PolicyInfo policy,Date acquired,Date asOf) {
        if(policy==null || String.isBlank(policy.parameters))return null;
        try {
            Map<String,Object> parsed=(Map<String,Object>)JSON.deserializeUntyped(policy.parameters);
            if(parsed.containsKey('tiers')) {
                List<Object> tiers=(List<Object>)parsed.get('tiers');Integer held=acquired.daysBetween(asOf);
                for(Object value:tiers) {
                    Map<String,Object> tier=(Map<String,Object>)value;Integer untilDay=tier.containsKey('throughDays')?Integer.valueOf(String.valueOf(tier.get('throughDays'))):null;
                    if(untilDay!=null && held>untilDay)continue;
                    if(tier.containsKey('rateRatio'))return InvMath.exact(String.valueOf(tier.get('rateRatio')));
                    if(tier.containsKey('ratePercent'))return InvMath.exact(String.valueOf(tier.get('ratePercent')))/100;
                }
            }
            if(parsed.containsKey('rateRatio'))return InvMath.exact(String.valueOf(parsed.get('rateRatio')));
            if(parsed.containsKey('ratePercent'))return InvMath.exact(String.valueOf(parsed.get('ratePercent')))/100;
            if(parsed.containsKey('rate')) {Decimal ratio=InvMath.exact(String.valueOf(parsed.get('rate')));return ratio>=0 && ratio<=1?ratio:null;}
        } catch(Exception ignored) {return null;}return null;
    }
}
