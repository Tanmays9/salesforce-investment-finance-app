public with sharing class InvPlanService {
    public class Request {
        @InvocableVariable(required=true) public String operation;
        @InvocableVariable public Id portfolioId;
        @InvocableVariable public Id versionId;
        @InvocableVariable public Id actionId;
        @InvocableVariable public String title;
        @InvocableVariable public String goal;
        @InvocableVariable public Decimal budget;
        @InvocableVariable public Id fundId;
        @InvocableVariable public Id accountId;
        @InvocableVariable public String actionType;
        @InvocableVariable public Decimal amount;
        @InvocableVariable public Decimal units;
        @InvocableVariable public Date intendedDate;
        @InvocableVariable public Decimal cashHoldDays;
        @InvocableVariable public String rationale;
        @InvocableVariable public Decimal targetPercent;
        @InvocableVariable public Id prerequisiteId;
        @InvocableVariable public Decimal lagDays;
        @InvocableVariable public String expectedFingerprint;
        @InvocableVariable public Boolean allAvailable;
    }
    public class Result { @InvocableVariable public Id versionId; @InvocableVariable public String message; }
    public class PlanException extends Exception {}
    @InvocableMethod(label='Manage investment plan' description='Create a draft, add an action or compare with the published portfolio baseline.')
    public static List<Result> manage(List<Request> requests) {
        if(!FeatureManagement.checkPermission('Inv_ManagePortfolio'))throw new PlanException('Portfolio Manager permission is required');
        List<Result> results=new List<Result>();
        for(Request request:requests)results.add(apply(request));return results;
    }
    @TestVisible private static Result apply(Request r) {
        Result result=new Result();
        if(r.operation=='create') {
            if(String.isBlank(r.title) || r.budget!=null && r.budget<0)throw new PlanException('A plan name and a nonnegative monthly budget are required');
            Inv_PortfolioPortfolios__c p=[SELECT Id,PublishedRun__c,PublishedRun__r.ValuationAsOf__c,PublishedRun__r.InputFingerprint__c,PublishedRun__r.Status__c FROM Inv_PortfolioPortfolios__c WHERE Id=:r.portfolioId];
            if(p.PublishedRun__c==null)throw new PlanException('Calculate the portfolio baseline first');
            if(p.PublishedRun__r.Status__c!='complete' || String.isBlank(p.PublishedRun__r.InputFingerprint__c))throw new PlanException('The published baseline is incomplete');
            String identity=String.valueOf(Crypto.getRandomLong());
            Inv_PlanningPlans__c plan=new Inv_PlanningPlans__c(MigrationKey__c='plan:'+identity,PortfolioRef__c=p.Id,
                Name__c=r.title,Goal__c=r.goal,CreatedAt__c=System.now());insert as system plan;
            Inv_PlanningPlanVersions__c version=new Inv_PlanningPlanVersions__c(MigrationKey__c='plan-version:'+identity,
                PlanRef__c=plan.Id,VersionNo__c='1',Status__c='draft',MonthlyBudget__c=String.valueOf(r.budget==null?35000:r.budget),
                ValuationAsOf__c=p.PublishedRun__r.ValuationAsOf__c,BaselineRunRef__c=p.PublishedRun__c,
                BaselineInputFingerprint__c=p.PublishedRun__r.InputFingerprint__c,CreatedAt__c=System.now(),
                Assumptions__c='Baseline NAV prices; calendar-day cash periods; no forecast returns; policy and tax coverage must be verified before approval.');
            insert as system version;result.versionId=version.Id;result.message='Draft created. Add actions, then evaluate the plan.';return result;
        }
        Inv_PlanningActions__c editing;
        if(r.operation=='edit' || r.operation=='remove') {
            editing=[SELECT Id,PlanVersionRef__c,MigrationKey__c FROM Inv_PlanningActions__c WHERE Id=:r.actionId];r.versionId=editing.PlanVersionRef__c;
            if(!editing.MigrationKey__c.startsWith('action:'))throw new PlanException('Preserve the imported action. Clone its plan version before changing it.');
        }
        Inv_PlanningPlanVersions__c version=[SELECT Id,MigrationKey__c,Status__c,PlanRef__c,PlanRef__r.PortfolioRef__c,BaselineRunRef__c,
            BaselineRunRef__r.ValuationAsOf__c,BaselineRunRef__r.InputFingerprint__c,BaselineRunRef__r.Status__c,
            BaselineInputFingerprint__c,EvaluationFingerprint__c,MonthlyBudget__c,VersionNo__c,Assumptions__c,ConstraintsJson__c,GenerationRationale__c,TaxAssumptionAcknowledged__c
            FROM Inv_PlanningPlanVersions__c WHERE Id=:r.versionId FOR UPDATE];
        result.versionId=version.Id;
        if(r.operation=='clone') {
            List<Inv_PlanningPlanVersions__c> siblings=[SELECT VersionNo__c FROM Inv_PlanningPlanVersions__c WHERE PlanRef__c=:version.PlanRef__c];Decimal maxVersion=0;
            for(Inv_PlanningPlanVersions__c v:siblings){Decimal n=InvMath.exact(v.VersionNo__c);if(n>maxVersion)maxVersion=n;}
            Inv_PlanningPlanVersions__c copy=new Inv_PlanningPlanVersions__c(MigrationKey__c='version:'+String.valueOf(Crypto.getRandomLong()),PlanRef__c=version.PlanRef__c,
                MonthlyBudget__c=version.MonthlyBudget__c,ValuationAsOf__c=Date.today(),KnowledgeCutoff__c=System.now(),
                Assumptions__c=JSON.serialize(new Map<String,Object>{'priorAssumptions'=>version.Assumptions__c,'rebased'=>true}),
                ConstraintsJson__c=version.ConstraintsJson__c,GenerationRationale__c=version.GenerationRationale__c,
                TaxAssumptionAcknowledged__c=version.TaxAssumptionAcknowledged__c);
            copy.VersionNo__c=String.valueOf(maxVersion+1);copy.Status__c='draft';copy.SupersedesRef__c=version.Id;
            if(r.budget!=null){if(r.budget<0)throw new PlanException('Monthly budget must be nonnegative');copy.MonthlyBudget__c=String.valueOf(r.budget);}
            Inv_PortfolioPortfolios__c currentPortfolio=[SELECT PublishedRun__c,PublishedRun__r.ValuationAsOf__c,PublishedRun__r.InputFingerprint__c,PublishedRun__r.Status__c
                FROM Inv_PortfolioPortfolios__c WHERE Id=:version.PlanRef__r.PortfolioRef__c];
            if(currentPortfolio.PublishedRun__c==null || currentPortfolio.PublishedRun__r.Status__c!='complete')throw new PlanException('Calculate a complete baseline before rebasing');
            copy.BaselineRunRef__c=currentPortfolio.PublishedRun__c;copy.BaselineInputFingerprint__c=currentPortfolio.PublishedRun__r.InputFingerprint__c;
            copy.ValuationAsOf__c=currentPortfolio.PublishedRun__r.ValuationAsOf__c;
            Integer dateShift=version.BaselineRunRef__r.ValuationAsOf__c==null?0:version.BaselineRunRef__r.ValuationAsOf__c.daysBetween(copy.ValuationAsOf__c);
            copy.CreatedAt__c=System.now();insert as system copy;
            List<Inv_PlanningActions__c> actions=[SELECT Id,ActionType__c,AccountRef__c,InstrumentRef__c,RequestedUnits__c,RequestedAmount__c,AllAvailable__c,IntendedDate__c,CashHoldDays__c,Rationale__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id];
            Map<Id,Inv_PlanningActions__c> copies=new Map<Id,Inv_PlanningActions__c>();List<Inv_PlanningActions__c> newActions=new List<Inv_PlanningActions__c>();
            for(Inv_PlanningActions__c action:actions){Inv_PlanningActions__c cloned=action.clone(false,false,false,false);cloned.PlanVersionRef__c=copy.Id;cloned.MigrationKey__c='action:'+String.valueOf(Crypto.getRandomLong());
                if(cloned.IntendedDate__c!=null)cloned.IntendedDate__c=cloned.IntendedDate__c.addDays(dateShift);copies.put(action.Id,cloned);newActions.add(cloned);}
            if(!newActions.isEmpty())insert as system newActions;
            List<Inv_PlanningActionDependencies__c> dependencies=[SELECT ActionRef__c,PrerequisiteRef__c,Kind__c,LagDays__c,DayBasis__c FROM Inv_PlanningActionDependencies__c WHERE ActionRef__c IN :copies.keySet()];
            for(Inv_PlanningActionDependencies__c dependency:dependencies){
                if(!copies.containsKey(dependency.PrerequisiteRef__c))throw new PlanException('A dependency crosses plan versions; resolve it before cloning');
                dependency.Id=null;dependency.ActionRef__c=copies.get(dependency.ActionRef__c).Id;dependency.PrerequisiteRef__c=copies.get(dependency.PrerequisiteRef__c).Id;dependency.MigrationKey__c='dependency:'+String.valueOf(Crypto.getRandomLong());
            }
            if(!dependencies.isEmpty())insert as system dependencies;
            List<Inv_PlanningTargets__c> targets=[SELECT Axis__c,TargetKey__c,Ratio__c,Fund__c FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:version.Id];
            for(Inv_PlanningTargets__c target:targets){target.Id=null;target.PlanVersionRef__c=copy.Id;target.MigrationKey__c='target:'+String.valueOf(Crypto.getRandomLong());}
            if(!targets.isEmpty())insert as system targets;
            result.versionId=copy.Id;result.message='Draft version, actions, targets and dependencies cloned against the latest published baseline.';return result;
        }
        if(version.Status__c!='draft')throw new PlanException('This version is frozen; clone it to make changes');
        if(!version.MigrationKey__c.startsWith('plan-version:') && !version.MigrationKey__c.startsWith('version:'))throw new PlanException('Clone the imported version before changing it.');
        if(r.operation=='dependency') {
            List<Inv_PlanningActions__c> actions=[SELECT Id,ActionType__c,IntendedDate__c,CashHoldDays__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id];
            Set<Id> ids=new Map<Id,Inv_PlanningActions__c>(actions).keySet();
            if(r.actionId==null || r.prerequisiteId==null || !ids.contains(r.actionId) || !ids.contains(r.prerequisiteId))throw new PlanException('Select two actions in this plan version');
            Inv_PlanningActionDependencies__c dependency=new Inv_PlanningActionDependencies__c(MigrationKey__c='dependency:'+version.Id+':'+r.actionId+':'+r.prerequisiteId,
                ActionRef__c=r.actionId,PrerequisiteRef__c=r.prerequisiteId,Kind__c='after',DayBasis__c='calendar',LagDays__c=String.valueOf(r.lagDays==null?0:r.lagDays));
            List<Inv_PlanningActionDependencies__c> existing=[SELECT Id,MigrationKey__c,ActionRef__c,PrerequisiteRef__c,Kind__c,DayBasis__c,LagDays__c FROM Inv_PlanningActionDependencies__c WHERE ActionRef__c IN :ids];
            List<Inv_PlanningActionDependencies__c> reviewed=new List<Inv_PlanningActionDependencies__c>();
            for(Inv_PlanningActionDependencies__c row:existing)if(row.ActionRef__c==r.actionId && row.PrerequisiteRef__c==r.prerequisiteId){dependency.Id=row.Id;dependency.MigrationKey__c=row.MigrationKey__c;}else reviewed.add(row);
            reviewed.add(dependency);InvPlanRules.validate(actions,reviewed);InvMath.project(dependency,'LagDays__c',dependency.LagDays__c);upsert as system dependency MigrationKey__c;
            result.message='Calendar-day dependency saved and validated.';return result;
        }
        if(r.operation=='target') {
            if(r.fundId==null || r.targetPercent==null || r.targetPercent<0 || r.targetPercent>100)throw new PlanException('Select a fund and an allocation target from 0 to 100 percent');
            List<Inv_MarketInstruments__c> verified=[SELECT Id FROM Inv_MarketInstruments__c WHERE Id=:r.fundId AND MappingVerified__c=true];
            if(verified.isEmpty())throw new PlanException('Use a verified fund share class');
            Inv_PlanningTargets__c target=new Inv_PlanningTargets__c(MigrationKey__c='target:'+version.Id+':'+r.fundId,PlanVersionRef__c=version.Id,Axis__c='fund',TargetKey__c=String.valueOf(r.fundId),Fund__c=r.fundId,Ratio__c=String.valueOf(r.targetPercent/100));
            List<Inv_PlanningTargets__c> existing=[SELECT Id,MigrationKey__c FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:version.Id AND Fund__c=:r.fundId];
            if(existing.size()>1)throw new PlanException('Resolve duplicate fund targets first');
            if(!existing.isEmpty()){target.Id=existing[0].Id;target.MigrationKey__c=existing[0].MigrationKey__c;}
            InvMath.project(target,'Ratio__c',target.Ratio__c);upsert as system target MigrationKey__c;
            result.message='Fund allocation target saved. Evaluate the plan to review deviations.';return result;
        }
        if(r.operation=='remove') {
            if([SELECT COUNT() FROM Inv_PlanningActionDependencies__c WHERE ActionRef__c=:editing.Id OR PrerequisiteRef__c=:editing.Id]>0)throw new PlanException('Remove or revise linked dependencies before removing this action');
            insert as system new Inv_OpsChangeLog__c(MigrationKey__c='draft-action-removal:'+String.valueOf(Crypto.getRandomLong()),SourceJson__c=JSON.serialize(editing));
            delete as system editing;result.message='Draft action removed; the removal is recorded in audit history.';return result;
        }
        if(r.operation=='acknowledge_tax') {
            version.TaxAssumptionAcknowledged__c=true;version.ApprovalReadiness__c='Tax uncertainty acknowledged';update as system version;
            result.message='Unknown tax amount explicitly acknowledged; no tax rate or liability was estimated.';return result;
        }
        if(r.operation=='add' || r.operation=='edit') {
            if(!new Set<String>{'keep','redeem','buy','set_sip','pause_sip','cash_hold','cash_need'}.contains(r.actionType))throw new PlanException('Unsupported action. Model a switch with separate linked redemption and purchase actions.');
            if((r.amount!=null && r.amount<0) || (r.units!=null && r.units<0) || (r.cashHoldDays!=null && r.cashHoldDays<0))throw new PlanException('Amounts, units and calendar-day periods must be nonnegative');
            Inv_PlanningActions__c action=new Inv_PlanningActions__c(Id=editing==null?null:editing.Id,MigrationKey__c=editing==null?'action:'+String.valueOf(Crypto.getRandomLong()):editing.MigrationKey__c,PlanVersionRef__c=version.Id,
                AccountRef__c=r.accountId,InstrumentRef__c=r.fundId,ActionType__c=r.actionType,RequestedUnits__c=r.units==null?null:String.valueOf(r.units),
                RequestedAmount__c=r.amount==null?null:String.valueOf(r.amount),AllAvailable__c=r.allAvailable==true,IntendedDate__c=r.intendedDate,
                CashHoldDays__c=r.cashHoldDays==null?null:String.valueOf(r.cashHoldDays),Rationale__c=r.rationale);
            upsert as system action;result.message='Draft action saved. Evaluate again to refresh the comparison.';return result;
        }
        if(r.operation=='approve') {
            Request evaluation=new Request();evaluation.operation='evaluate';evaluation.versionId=version.Id;apply(evaluation);
            List<Inv_PlanningActions__c> redemptions=new List<Inv_PlanningActions__c>();Set<Id> redemptionIds=new Set<Id>();
            for(Inv_PlanningActions__c action:[SELECT Id,InstrumentRef__c,ActionType__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id WITH SYSTEM_MODE])
                if(action.ActionType__c=='redeem'){redemptions.add(action);redemptionIds.add(action.Id);}
            Map<Id,Inv_RedemptionEstimates__c> estimateByAction=new Map<Id,Inv_RedemptionEstimates__c>();
            if(!redemptionIds.isEmpty())for(Inv_RedemptionEstimates__c estimate:[SELECT Id,Action__c,Fund__c,EligibilityCoverage__c,LoadCoverage__c,TaxCoverage__c,SettlementDate__c
                FROM Inv_RedemptionEstimates__c WHERE Action__c IN :redemptionIds AND Published__c=true WITH SYSTEM_MODE ORDER BY CreatedDate DESC])
                if(!estimateByAction.containsKey(estimate.Action__c))estimateByAction.put(estimate.Action__c,estimate);
            for(Inv_PlanningActions__c action:redemptions) {
                Inv_RedemptionEstimates__c estimate=estimateByAction.get(action.Id);
                if(estimate==null || estimate.Fund__c!=action.InstrumentRef__c)throw new PlanException('Save an evidence-backed redemption review for each redemption action before approval.');
                if(estimate.EligibilityCoverage__c!='eligible')throw new PlanException('Resolve lock-in and eligibility evidence for every requested redemption lot before approval.');
                if(estimate.LoadCoverage__c!='complete')throw new PlanException('Resolve exit-load evidence for every requested redemption lot before approval.');
                if(estimate.SettlementDate__c==null)throw new PlanException('Record the assumed settlement date for each redemption before approval.');
                if(estimate.TaxCoverage__c!='complete' && version.TaxAssumptionAcknowledged__c!=true)
                    throw new PlanException('Acknowledge the unknown tax estimate or add reviewed tax evidence before approval.');
            }
            update as system new Inv_PlanningPlanVersions__c(Id=version.Id,Status__c='approved',ApprovalReadiness__c='Ready',ApprovedAt__c=System.now(),ApprovedBy__c=UserInfo.getUserId());
            result.message='Plan version approved and frozen. No broker transaction or SIP change was executed.';return result;
        }
        if(r.operation!='evaluate')throw new PlanException('Unknown plan operation');
        Id portfolio=version.PlanRef__r.PortfolioRef__c;
        Inv_PortfolioPortfolios__c p=[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:portfolio];
        if(p.PublishedRun__c!=version.BaselineRunRef__c)throw new PlanException('Baseline is stale. Clone the plan to rebase it before comparison.');
        if(version.BaselineRunRef__r.Status__c!='complete' || String.isBlank(version.BaselineInputFingerprint__c)
            || version.BaselineInputFingerprint__c!=version.BaselineRunRef__r.InputFingerprint__c)
            throw new PlanException('The plan baseline fingerprint is missing or inconsistent. Rebase the plan before comparison.');
        if(r.expectedFingerprint!=null && r.expectedFingerprint!=version.BaselineInputFingerprint__c)
            throw new PlanException('The portfolio baseline changed while this review was open. Rebase and compare changes.');
        Map<Id,Decimal> original=new Map<Id,Decimal>(),proposed=new Map<Id,Decimal>(),sips=new Map<Id,Decimal>(),originalSips=new Map<Id,Decimal>();
        Map<Id,Decimal> available=new Map<Id,Decimal>(),navs=new Map<Id,Decimal>();
        List<Inv_HoldingValuation__c> baselineValues=[SELECT Fund__c,Units__c,MarketValue__c,NAV__c,Coverage__c
            FROM Inv_HoldingValuation__c WHERE Portfolio__c=:portfolio AND Run__c=:version.BaselineRunRef__c WITH SYSTEM_MODE];
        for(Inv_HoldingValuation__c h:baselineValues) {
            if(h.Units__c>0 && (h.MarketValue__c==null || h.NAV__c==null))throw new PlanException('A baseline holding has no valid valuation');
            if(h.Fund__c==null)throw new PlanException('A baseline holding is missing its fund mapping');
            if(h.MarketValue__c!=null)original.put(h.Fund__c,(original.containsKey(h.Fund__c)?original.get(h.Fund__c):0)+h.MarketValue__c);
            available.put(h.Fund__c,(available.containsKey(h.Fund__c)?available.get(h.Fund__c):0)+(h.Units__c==null?0:h.Units__c));
            if(h.NAV__c!=null){if(navs.containsKey(h.Fund__c) && navs.get(h.Fund__c)!=h.NAV__c)throw new PlanException('Baseline has inconsistent NAVs between accounts for one share class');navs.put(h.Fund__c,h.NAV__c);}
        }
        Set<Id> accounts=new Set<Id>();for(Inv_PortfolioAccounts__c account:[SELECT Id FROM Inv_PortfolioAccounts__c WHERE PortfolioRef__c=:portfolio WITH SYSTEM_MODE])accounts.add(account.Id);
        List<Inv_PortfolioSipVersions__c> baselineSips=[SELECT Id,InstrumentRef__r.InstrumentRef__c,Amount__c,Frequency__c,VerificationState__c,ReportedStatus__c
            FROM Inv_PortfolioSipVersions__c WHERE AccountRef__c IN :accounts AND EffectiveFrom__c<=:version.BaselineRunRef__r.ValuationAsOf__c
                AND (EffectiveTo__c=null OR EffectiveTo__c>:version.BaselineRunRef__r.ValuationAsOf__c) WITH SYSTEM_MODE];
        for(Inv_PortfolioSipVersions__c sip:baselineSips)if(sip.VerificationState__c=='user_confirmed' && sip.ReportedStatus__c=='active'
            && sip.Frequency__c=='monthly' && sip.InstrumentRef__r!=null && sip.InstrumentRef__r.InstrumentRef__c!=null) {
            Id fund=sip.InstrumentRef__r.InstrumentRef__c;Decimal amount=InvMath.exact(sip.Amount__c);
            originalSips.put(fund,(originalSips.containsKey(fund)?originalSips.get(fund):0)+amount);
        }
        sips.putAll(originalSips);
        proposed.putAll(original);sips.putAll(originalSips);Decimal cash=0,spendingCash=0;Boolean redemption=false;
        Decimal portfolioValue=0;for(Decimal value:original.values())portfolioValue+=value;
        List<Inv_PlanningActions__c> actions=[SELECT Id,ActionType__c,InstrumentRef__c,AccountRef__c,RequestedUnits__c,RequestedAmount__c,AllAvailable__c,IntendedDate__c,CashHoldDays__c
            FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id ORDER BY IntendedDate__c ASC NULLS LAST,CreatedDate ASC,Id ASC];
        Set<Id> actionIds=new Map<Id,Inv_PlanningActions__c>(actions).keySet();
        Set<Id> redemptionActionIds=new Set<Id>();Integer cashHoldDays=0;
        for(Inv_PlanningActions__c action:actions) {
            if(action.ActionType__c=='redeem')redemptionActionIds.add(action.Id);
            if(action.ActionType__c=='cash_hold') {
                Decimal days=InvMath.exact(action.CashHoldDays__c);
                if(days!=null && days>cashHoldDays)cashHoldDays=days.intValue();
            }
        }
        Map<Id,Inv_RedemptionEstimates__c> redemptionEstimates=new Map<Id,Inv_RedemptionEstimates__c>();
        if(!redemptionActionIds.isEmpty())for(Inv_RedemptionEstimates__c estimate:[SELECT Id,Action__c,AnalysisRun__c,Fund__c,RequestedUnits__c,
            GrossProceeds__c,ExitLoad__c,EligibilityCoverage__c,LoadCoverage__c,SettlementDate__c
            FROM Inv_RedemptionEstimates__c WHERE Action__c IN :redemptionActionIds AND Published__c=true WITH SYSTEM_MODE ORDER BY CreatedDate DESC])
            if(!redemptionEstimates.containsKey(estimate.Action__c))redemptionEstimates.put(estimate.Action__c,estimate);
        Map<Date,Decimal> pendingCash=new Map<Date,Decimal>();
        List<Inv_PlanningActionDependencies__c> dependencies=[SELECT ActionRef__c,PrerequisiteRef__c,Kind__c,LagDays__c,DayBasis__c FROM Inv_PlanningActionDependencies__c WHERE ActionRef__c IN :actionIds];
        InvPlanRules.validate(actions,dependencies);
        Map<String,Object> reviewConstraints=String.isBlank(version.ConstraintsJson__c)?new Map<String,Object>()
            :(Map<String,Object>)JSON.deserializeUntyped(version.ConstraintsJson__c);
        Set<Id> excludedNewPurchases=new Set<Id>();
        if(reviewConstraints.containsKey('excludedNewPurchaseFundIds') && reviewConstraints.get('excludedNewPurchaseFundIds')!=null)
            for(Object rawId:(List<Object>)reviewConstraints.get('excludedNewPurchaseFundIds'))excludedNewPurchases.add((Id)String.valueOf(rawId));
        for(Inv_PlanningActions__c action:actions)if(action.InstrumentRef__c!=null && excludedNewPurchases.contains(action.InstrumentRef__c)) {
            Decimal requestedAmount=InvMath.exact(action.RequestedAmount__c);
            if(action.ActionType__c=='buy' || (action.ActionType__c=='set_sip' && requestedAmount!=null && requestedAmount>0))
                throw new PlanException('A draft purchase or SIP conflicts with the selected excluded-from-new-purchases constraint.');
        }
        for(Inv_PlanningActions__c action:actions)if(action.IntendedDate__c!=null && action.IntendedDate__c<version.BaselineRunRef__r.ValuationAsOf__c)
            throw new PlanException('Scenario actions cannot predate the valuation baseline');
        List<Inv_PlanningTargets__c> targets=[SELECT Fund__c,Axis__c,TargetKey__c,Ratio__c FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:version.Id];
        Map<Id,Decimal> targetWeights=new Map<Id,Decimal>();Decimal targetTotal=0;
        for(Inv_PlanningTargets__c target:targets){
            if(target.Axis__c!='fund' || target.Fund__c==null)throw new PlanException('An imported target requires explicit fund mapping before comparison');
            Decimal ratio=InvMath.exact(target.Ratio__c);if(ratio==null || ratio<0 || ratio>1 || targetWeights.containsKey(target.Fund__c))throw new PlanException('Allocation targets must be unique and between zero and one');
            targetWeights.put(target.Fund__c,ratio);targetTotal+=ratio;
        }
        if(targetTotal>1)throw new PlanException('Allocation targets exceed 100 percent');
        List<String> notes=new List<String>();
        for(Inv_PlanningActions__c a:actions) {
            if(a.IntendedDate__c!=null)for(Date releaseDate:new List<Date>(pendingCash.keySet()))if(releaseDate<=a.IntendedDate__c) {
                cash+=pendingCash.get(releaseDate);pendingCash.remove(releaseDate);
            }
            Id fund=a.InstrumentRef__c;String kind=a.ActionType__c;Decimal amount=InvMath.exact(a.RequestedAmount__c),units=InvMath.exact(a.RequestedUnits__c);
            if(kind=='keep')continue;
            if(kind=='set_sip' || kind=='pause_sip') {
                if(fund==null || (kind=='set_sip' && amount==null))throw new PlanException('SIP action requires a fund and amount');
                sips.put(fund,kind=='pause_sip'?0:amount);continue;
            }
            if(kind=='cash_hold'){notes.add('Cash bridge: up to '+a.CashHoldDays__c+' calendar days after verified redemption settlement.');continue;}
            if(kind=='cash_need') {
                if(amount==null || amount<=0 || amount>cash)throw new PlanException('Requested spending cash exceeds proceeds available by that date');
                cash-=amount;spendingCash+=amount;notes.add('Spending cash requested: INR '+String.valueOf(amount)+' on '+String.valueOf(a.IntendedDate__c));continue;
            }
            if(kind=='redeem') {
                if(fund==null || !navs.containsKey(fund))throw new PlanException('Redemption requires a valued holding');
                if(a.AccountRef__c!=null)throw new PlanException('Account-specific redemption requires lot allocation review; use a portfolio-level draft action');
                if(a.AllAvailable__c)units=available.get(fund);
                if(units==null && amount!=null)units=amount/navs.get(fund);
                Decimal availableUnits=available.containsKey(fund)?available.get(fund):0;
                if(units==null || units<=0 || units>availableUnits)throw new PlanException('Requested redemption exceeds baseline units or has no positive quantity');
                amount=units*navs.get(fund);available.put(fund,availableUnits-units);proposed.put(fund,(proposed.containsKey(fund)?proposed.get(fund):0)-amount);redemption=true;
                Inv_RedemptionEstimates__c estimate=redemptionEstimates.get(a.Id);
                if(estimate!=null && estimate.AnalysisRun__c==version.BaselineRunRef__c && estimate.Fund__c==fund
                    && estimate.RequestedUnits__c!=null && (estimate.RequestedUnits__c-units).abs()<=0.00000001
                    && estimate.EligibilityCoverage__c=='eligible' && estimate.LoadCoverage__c=='complete'
                    && estimate.SettlementDate__c!=null && estimate.ExitLoad__c!=null && estimate.GrossProceeds__c!=null) {
                    Decimal settledAmount=estimate.GrossProceeds__c-estimate.ExitLoad__c;
                    if(settledAmount<0)throw new PlanException('The reviewed redemption estimate has a negative settlement amount.');
                    Date releaseDate=estimate.SettlementDate__c.addDays(cashHoldDays);
                    if(a.IntendedDate__c!=null && releaseDate<a.IntendedDate__c)releaseDate=a.IntendedDate__c;
                    pendingCash.put(releaseDate,(pendingCash.containsKey(releaseDate)?pendingCash.get(releaseDate):0)+settledAmount);
                    notes.add('Net of verified exit load, INR '+String.valueOf(settledAmount)+' is available on '+String.valueOf(releaseDate)+' after settlement and the selected cash hold; tax remains separately unestimated.');
                } else notes.add('Redemption proceeds are unavailable to purchases and spending until a matching eligible-lot, exit-load and settlement review is saved.');
            } else if(kind=='buy') {
                if(fund==null || amount==null || amount<=0)throw new PlanException('Purchase requires a fund and positive amount');
                if(cashHoldDays>0 && a.IntendedDate__c==null)throw new PlanException('A dated purchase is required when a cash-hold period is selected.');
                if(amount>cash)throw new PlanException('Purchase exceeds scenario cash; add an earlier redemption or reduce the amount');
                proposed.put(fund,(proposed.containsKey(fund)?proposed.get(fund):0)+amount);cash-=amount;
            } else throw new PlanException('Existing action type needs explicit review: '+kind);
        }
        Decimal monthly=0,originalMonthly=0;for(Decimal amount:sips.values())monthly+=amount;for(Decimal amount:originalSips.values())originalMonthly+=amount;
        if(monthly>InvMath.exact(version.MonthlyBudget__c))throw new PlanException('Proposed SIP total exceeds the plan monthly budget');
        Decimal pendingTotal=0;for(Decimal value:pendingCash.values())pendingTotal+=value;
        Decimal proposedTotal=cash+pendingTotal;for(Decimal value:proposed.values())proposedTotal+=value;
        String fingerprint=InvPortfolioEngine.hash(JSON.serialize(actions)+JSON.serialize(targets)+JSON.serialize(dependencies)+JSON.serialize(proposed)+
            JSON.serialize(originalSips)+JSON.serialize(pendingCash)+String.valueOf(cash)+version.BaselineRunRef__c+
            version.BaselineInputFingerprint__c+version.MonthlyBudget__c);
        Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='plan-impact:'+version.Id+':'+fingerprint,PortfolioRef__c=portfolio,
            PlanVersionRef__c=version.Id,Kind__c='plan_comparison',Status__c='complete',OperationalStatus__c='Published',AlgorithmVersion__c='sf-plan-1',
            ValuationAsOf__c=version.BaselineRunRef__r.ValuationAsOf__c,InputFingerprint__c=fingerprint,StartedAt__c=System.now(),CompletedAt__c=System.now(),
            InputManifest__c=JSON.serialize(new Map<String,Object>{'baselineRunId'=>version.BaselineRunRef__c,'baselineFingerprint'=>version.BaselineInputFingerprint__c,
                'baselineDate'=>version.BaselineRunRef__r.ValuationAsOf__c,'holdingValuations'=>baselineValues.size(),'confirmedMonthlySIPs'=>baselineSips.size()}));upsert as system run MigrationKey__c;
        List<Inv_PlanImpact__c> results=new List<Inv_PlanImpact__c>();Set<Id> funds=new Set<Id>();funds.addAll(original.keySet());funds.addAll(proposed.keySet());funds.addAll(sips.keySet());
        funds.addAll(targetWeights.keySet());
        for(Id fund:funds) {
            results.add(impact(version.Id,run.Id,fund,'Market value INR',original.containsKey(fund)?original.get(fund):0,proposed.containsKey(fund)?proposed.get(fund):0,redemption,notes));
            results.add(impact(version.Id,run.Id,fund,'Monthly SIP INR',originalSips.containsKey(fund)?originalSips.get(fund):0,sips.containsKey(fund)?sips.get(fund):0,false,notes));
            if(portfolioValue>0)results.add(impact(version.Id,run.Id,fund,'Allocation percent',100*(original.containsKey(fund)?original.get(fund):0)/portfolioValue,
                proposedTotal>0?100*(proposed.containsKey(fund)?proposed.get(fund):0)/proposedTotal:null,redemption,notes));
            if(portfolioValue>0 && targetWeights.containsKey(fund))results.add(impact(version.Id,run.Id,fund,'Target deviation percentage points',
                100*((original.containsKey(fund)?original.get(fund):0)/portfolioValue-targetWeights.get(fund)),
                proposedTotal>0?100*((proposed.containsKey(fund)?proposed.get(fund):0)/proposedTotal-targetWeights.get(fund)):null,redemption,notes));
        }
        results.add(impact(version.Id,run.Id,null,'Cash remaining INR',0,cash,redemption,notes));
        results.add(impact(version.Id,run.Id,null,'Pending settlement cash INR',0,pendingTotal,redemption,notes));
        results.add(impact(version.Id,run.Id,null,'Cash used for spending INR',0,spendingCash,redemption,notes));
        Decimal originalCount=0,proposedCount=0,largestBefore=0,largestAfter=0;
        for(Decimal value:original.values())if(value>0){originalCount++;if(value>largestBefore)largestBefore=value;}
        for(Decimal value:proposed.values())if(value>0){proposedCount++;if(value>largestAfter)largestAfter=value;}
        if(!reviewConstraints.isEmpty()) {
            if(reviewConstraints.containsKey('maximumFundCount') && reviewConstraints.get('maximumFundCount')!=null) {
                Integer maximum=InvMath.exact(String.valueOf(reviewConstraints.get('maximumFundCount'))).intValue();
                if(maximum<1 || proposedCount>maximum)throw new PlanException('The proposed actions exceed the selected maximum fund count. The constraint was not relaxed.');
            }
            if(reviewConstraints.containsKey('retainedFundIds') && reviewConstraints.get('retainedFundIds')!=null)for(Object rawId:(List<Object>)reviewConstraints.get('retainedFundIds')) {
                Id retainedId=(Id)String.valueOf(rawId);
                Decimal remainingValue=proposed.containsKey(retainedId)?proposed.get(retainedId):0;
                Decimal futureSip=sips.containsKey(retainedId)?sips.get(retainedId):0;
                if(remainingValue<=0 && futureSip<=0)throw new PlanException('A fund selected to retain is fully redeemed and has no continuing SIP.');
            }
        }
        results.add(impact(version.Id,run.Id,null,'Fund count',originalCount,proposedCount,false,notes));
        if(portfolioValue>0)results.add(impact(version.Id,run.Id,null,'Largest fund allocation percent',100*largestBefore/portfolioValue,
            proposedTotal>0?100*largestAfter/proposedTotal:null,redemption,notes));
        Decimal budget=InvMath.exact(version.MonthlyBudget__c);
        results.add(impact(version.Id,run.Id,null,'Unallocated monthly SIP budget INR',budget-originalMonthly,budget-monthly,false,notes));
        if(portfolioValue>0)results.addAll(InvPlanExposure.compare(version.Id,run.Id,portfolio,version.BaselineRunRef__r.ValuationAsOf__c,
            original,proposed,portfolioValue,cash+pendingTotal));
        for(Inv_PlanImpact__c row:results)InvMath.capture(row);
        List<Inv_PlanImpact__c> old=[SELECT Id,Published__c FROM Inv_PlanImpact__c WHERE PlanVersion__c=:version.Id AND Published__c=true AND Run__c!=:run.Id];
        for(Inv_PlanImpact__c row:old)row.Published__c=false;update as system old;
        upsert as system results Key__c;version.EvaluationFingerprint__c=fingerprint;update as system version;
        result.message='Comparison calculated from immutable baseline '+String.valueOf(version.BaselineRunRef__r.ValuationAsOf__c)+'. '+
            (redemption?'Redemption policy and tax checks require review.':'No trade has been executed.');return result;
    }
    private static Inv_PlanImpact__c impact(Id version,Id run,Id fund,String metric,Decimal before,Decimal after,Boolean review,List<String> notes) {
        return new Inv_PlanImpact__c(Key__c=run+':'+fund+':'+metric,Name=metric,PlanVersion__c=version,Run__c=run,Fund__c=fund,Published__c=true,
            Scope__c=fund==null?'Portfolio':'Fund',Metric__c=metric,Baseline__c=before,Proposed__c=after,
            Coverage__c=review?'policy_review_required':'baseline_prices',Notes__c=String.join(notes,'\n').left(32768));
    }
}
