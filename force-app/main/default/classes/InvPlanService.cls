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
            Inv_PortfolioPortfolios__c p=[SELECT Id,PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:r.portfolioId];
            if(p.PublishedRun__c==null)throw new PlanException('Calculate the portfolio baseline first');
            String identity=String.valueOf(Crypto.getRandomLong());
            Inv_PlanningPlans__c plan=new Inv_PlanningPlans__c(MigrationKey__c='plan:'+identity,PortfolioRef__c=p.Id,
                Name__c=r.title,Goal__c=r.goal,CreatedAt__c=System.now());insert as system plan;
            Inv_PlanningPlanVersions__c version=new Inv_PlanningPlanVersions__c(MigrationKey__c='plan-version:'+identity,
                PlanRef__c=plan.Id,VersionNo__c='1',Status__c='draft',MonthlyBudget__c=String.valueOf(r.budget==null?35000:r.budget),
                ValuationAsOf__c=Date.today(),BaselineRunRef__c=p.PublishedRun__c,CreatedAt__c=System.now(),
                Assumptions__c='Baseline NAV prices; calendar-day cash periods; no forecast returns; policy and tax coverage must be verified before approval.');
            insert as system version;result.versionId=version.Id;result.message='Draft created. Add actions, then evaluate the plan.';return result;
        }
        Inv_PlanningActions__c editing;
        if(r.operation=='edit' || r.operation=='remove') {
            editing=[SELECT Id,PlanVersionRef__c,MigrationKey__c FROM Inv_PlanningActions__c WHERE Id=:r.actionId];r.versionId=editing.PlanVersionRef__c;
            if(!editing.MigrationKey__c.startsWith('action:'))throw new PlanException('Preserve the imported action. Clone its plan version before changing it.');
        }
        Inv_PlanningPlanVersions__c version=[SELECT Id,MigrationKey__c,Status__c,PlanRef__c,PlanRef__r.PortfolioRef__c,BaselineRunRef__c,BaselineRunRef__r.ValuationAsOf__c,MonthlyBudget__c,VersionNo__c,Assumptions__c
            FROM Inv_PlanningPlanVersions__c WHERE Id=:r.versionId FOR UPDATE];
        result.versionId=version.Id;
        if(r.operation=='clone') {
            List<Inv_PlanningPlanVersions__c> siblings=[SELECT VersionNo__c FROM Inv_PlanningPlanVersions__c WHERE PlanRef__c=:version.PlanRef__c];Decimal maxVersion=0;
            for(Inv_PlanningPlanVersions__c v:siblings){Decimal n=InvMath.exact(v.VersionNo__c);if(n>maxVersion)maxVersion=n;}
            Inv_PlanningPlanVersions__c copy=new Inv_PlanningPlanVersions__c(MigrationKey__c='version:'+String.valueOf(Crypto.getRandomLong()),PlanRef__c=version.PlanRef__c,
                MonthlyBudget__c=version.MonthlyBudget__c,ValuationAsOf__c=Date.today(),KnowledgeCutoff__c=System.now(),
                Assumptions__c=JSON.serialize(new Map<String,Object>{'priorAssumptions'=>version.Assumptions__c,'rebased'=>true}));
            copy.VersionNo__c=String.valueOf(maxVersion+1);copy.Status__c='draft';copy.SupersedesRef__c=version.Id;
            if(r.budget!=null){if(r.budget<0)throw new PlanException('Monthly budget must be nonnegative');copy.MonthlyBudget__c=String.valueOf(r.budget);}
            copy.BaselineRunRef__c=[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:version.PlanRef__r.PortfolioRef__c].PublishedRun__c;
            copy.CreatedAt__c=System.now();insert as system copy;
            List<Inv_PlanningActions__c> actions=[SELECT Id,ActionType__c,AccountRef__c,InstrumentRef__c,RequestedUnits__c,RequestedAmount__c,AllAvailable__c,IntendedDate__c,CashHoldDays__c,Rationale__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id];
            Map<Id,Inv_PlanningActions__c> copies=new Map<Id,Inv_PlanningActions__c>();List<Inv_PlanningActions__c> newActions=new List<Inv_PlanningActions__c>();
            for(Inv_PlanningActions__c action:actions){Inv_PlanningActions__c cloned=action.clone(false,false,false,false);cloned.PlanVersionRef__c=copy.Id;cloned.MigrationKey__c='action:'+String.valueOf(Crypto.getRandomLong());copies.put(action.Id,cloned);newActions.add(cloned);}
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
        if(r.operation=='add' || r.operation=='edit') {
            if(!new Set<String>{'keep','redeem','buy','set_sip','pause_sip','cash_hold'}.contains(r.actionType))throw new PlanException('Unsupported action. Model a switch with separate linked redemption and purchase actions.');
            if((r.amount!=null && r.amount<0) || (r.units!=null && r.units<0) || (r.cashHoldDays!=null && r.cashHoldDays<0))throw new PlanException('Amounts, units and calendar-day periods must be nonnegative');
            Inv_PlanningActions__c action=new Inv_PlanningActions__c(Id=editing==null?null:editing.Id,MigrationKey__c=editing==null?'action:'+String.valueOf(Crypto.getRandomLong()):editing.MigrationKey__c,PlanVersionRef__c=version.Id,
                AccountRef__c=r.accountId,InstrumentRef__c=r.fundId,ActionType__c=r.actionType,RequestedUnits__c=r.units==null?null:String.valueOf(r.units),
                RequestedAmount__c=r.amount==null?null:String.valueOf(r.amount),IntendedDate__c=r.intendedDate,CashHoldDays__c=r.cashHoldDays==null?null:String.valueOf(r.cashHoldDays),Rationale__c=r.rationale);
            upsert as system action;result.message='Draft action saved. Evaluate again to refresh the comparison.';return result;
        }
        if(r.operation=='approve') {
            Request evaluation=new Request();evaluation.operation='evaluate';evaluation.versionId=version.Id;apply(evaluation);
            if([SELECT COUNT() FROM Inv_PlanImpact__c WHERE PlanVersion__c=:version.Id AND Published__c=true AND Coverage__c='policy_review_required']>0)
                throw new PlanException('Redemption policy and tax review must be completed before approval');
            update as system new Inv_PlanningPlanVersions__c(Id=version.Id,Status__c='approved',ApprovedAt__c=System.now(),ApprovedBy__c=UserInfo.getUserId());
            result.message='Plan version approved and frozen. No broker transaction or SIP change was executed.';return result;
        }
        if(r.operation!='evaluate')throw new PlanException('Unknown plan operation');
        Id portfolio=version.PlanRef__r.PortfolioRef__c;
        Inv_PortfolioPortfolios__c p=[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:portfolio];
        if(p.PublishedRun__c!=version.BaselineRunRef__c)throw new PlanException('Baseline is stale. Clone the plan to rebase it before comparison.');
        Map<Id,Decimal> original=new Map<Id,Decimal>(),proposed=new Map<Id,Decimal>(),sips=new Map<Id,Decimal>(),originalSips=new Map<Id,Decimal>();
        Map<Id,Decimal> available=new Map<Id,Decimal>(),navs=new Map<Id,Decimal>();
        for(Inv_Holding__c h:[SELECT Fund__c,Account__c,Units__c,MarketValue__c,NAV__c,SIPAmount__c FROM Inv_Holding__c WHERE Portfolio__c=:portfolio]) {
            if(h.Units__c>0 && (h.MarketValue__c==null || h.NAV__c==null))throw new PlanException('A held fund has no valid valuation');
            original.put(h.Fund__c,(original.containsKey(h.Fund__c)?original.get(h.Fund__c):0)+(h.MarketValue__c==null?0:h.MarketValue__c));
            originalSips.put(h.Fund__c,(originalSips.containsKey(h.Fund__c)?originalSips.get(h.Fund__c):0)+h.SIPAmount__c);
            available.put(h.Fund__c,(available.containsKey(h.Fund__c)?available.get(h.Fund__c):0)+h.Units__c);
            if(h.NAV__c!=null)navs.put(h.Fund__c,h.NAV__c);
        }
        proposed.putAll(original);sips.putAll(originalSips);Decimal cash=0;Boolean redemption=false;
        Decimal portfolioValue=0;for(Decimal value:original.values())portfolioValue+=value;
        List<Inv_PlanningActions__c> actions=[SELECT Id,ActionType__c,InstrumentRef__c,AccountRef__c,RequestedUnits__c,RequestedAmount__c,AllAvailable__c,IntendedDate__c,CashHoldDays__c
            FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version.Id ORDER BY IntendedDate__c ASC NULLS LAST,CreatedDate ASC,Id ASC];
        Set<Id> actionIds=new Map<Id,Inv_PlanningActions__c>(actions).keySet();
        List<Inv_PlanningActionDependencies__c> dependencies=[SELECT ActionRef__c,PrerequisiteRef__c,Kind__c,LagDays__c,DayBasis__c FROM Inv_PlanningActionDependencies__c WHERE ActionRef__c IN :actionIds];
        InvPlanRules.validate(actions,dependencies);
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
            Id fund=a.InstrumentRef__c;String kind=a.ActionType__c;Decimal amount=InvMath.exact(a.RequestedAmount__c),units=InvMath.exact(a.RequestedUnits__c);
            if(kind=='keep')continue;
            if(kind=='set_sip' || kind=='pause_sip') {
                if(fund==null || (kind=='set_sip' && amount==null))throw new PlanException('SIP action requires a fund and amount');
                sips.put(fund,kind=='pause_sip'?0:amount);continue;
            }
            if(kind=='cash_hold'){notes.add('Cash bridge: '+a.CashHoldDays__c+' calendar days from '+a.IntendedDate__c);continue;}
            if(kind=='redeem') {
                if(fund==null || !navs.containsKey(fund))throw new PlanException('Redemption requires a valued holding');
                if(a.AccountRef__c!=null)throw new PlanException('Account-specific redemption requires lot allocation review; use a portfolio-level draft action');
                if(a.AllAvailable__c)units=available.get(fund);
                if(units==null && amount!=null)units=amount/navs.get(fund);
                if(units==null || units<=0 || units>available.get(fund))throw new PlanException('Requested redemption exceeds available units or has no positive quantity');
                amount=units*navs.get(fund);available.put(fund,available.get(fund)-units);proposed.put(fund,proposed.get(fund)-amount);cash+=amount;redemption=true;
                notes.add('Redemption is a gross estimate. Lot eligibility, exit loads and tax policy are not verified.');
            } else if(kind=='buy') {
                if(fund==null || amount==null || amount<=0)throw new PlanException('Purchase requires a fund and positive amount');
                if(amount>cash)throw new PlanException('Purchase exceeds scenario cash; add an earlier redemption or reduce the amount');
                proposed.put(fund,(proposed.containsKey(fund)?proposed.get(fund):0)+amount);cash-=amount;
            } else throw new PlanException('Existing action type needs explicit review: '+kind);
        }
        Decimal monthly=0;for(Decimal amount:sips.values())monthly+=amount;
        if(monthly>InvMath.exact(version.MonthlyBudget__c))throw new PlanException('Proposed SIP total exceeds the plan monthly budget');
        String fingerprint=InvPortfolioEngine.hash(JSON.serialize(actions)+JSON.serialize(targets)+JSON.serialize(dependencies)+JSON.serialize(proposed)+version.BaselineRunRef__c+version.MonthlyBudget__c);
        Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='plan-impact:'+version.Id+':'+fingerprint,PortfolioRef__c=portfolio,
            PlanVersionRef__c=version.Id,Kind__c='plan_comparison',Status__c='complete',OperationalStatus__c='Published',AlgorithmVersion__c='sf-plan-1',
            ValuationAsOf__c=Date.today(),InputFingerprint__c=fingerprint,StartedAt__c=System.now(),CompletedAt__c=System.now());upsert as system run MigrationKey__c;
        List<Inv_PlanImpact__c> results=new List<Inv_PlanImpact__c>();Set<Id> funds=new Set<Id>();funds.addAll(original.keySet());funds.addAll(proposed.keySet());funds.addAll(sips.keySet());
        funds.addAll(targetWeights.keySet());
        for(Id fund:funds) {
            results.add(impact(version.Id,run.Id,fund,'Market value INR',original.containsKey(fund)?original.get(fund):0,proposed.containsKey(fund)?proposed.get(fund):0,redemption,notes));
            results.add(impact(version.Id,run.Id,fund,'Monthly SIP INR',originalSips.containsKey(fund)?originalSips.get(fund):0,sips.containsKey(fund)?sips.get(fund):0,false,notes));
            if(portfolioValue>0)results.add(impact(version.Id,run.Id,fund,'Allocation percent',100*(original.containsKey(fund)?original.get(fund):0)/portfolioValue,
                100*(proposed.containsKey(fund)?proposed.get(fund):0)/portfolioValue,redemption,notes));
            if(portfolioValue>0 && targetWeights.containsKey(fund))results.add(impact(version.Id,run.Id,fund,'Target deviation percentage points',
                100*((original.containsKey(fund)?original.get(fund):0)/portfolioValue-targetWeights.get(fund)),
                100*((proposed.containsKey(fund)?proposed.get(fund):0)/portfolioValue-targetWeights.get(fund)),redemption,notes));
        }
        results.add(impact(version.Id,run.Id,null,'Cash generated INR',0,cash,redemption,notes));
        Decimal originalCount=0,proposedCount=0,largestBefore=0,largestAfter=0;
        for(Decimal value:original.values())if(value>0){originalCount++;if(value>largestBefore)largestBefore=value;}
        for(Decimal value:proposed.values())if(value>0){proposedCount++;if(value>largestAfter)largestAfter=value;}
        results.add(impact(version.Id,run.Id,null,'Fund count',originalCount,proposedCount,false,notes));
        if(portfolioValue>0)results.add(impact(version.Id,run.Id,null,'Largest fund allocation percent',100*largestBefore/portfolioValue,100*largestAfter/portfolioValue,redemption,notes));
        if(portfolioValue>0)results.addAll(InvPlanExposure.compare(version.Id,run.Id,portfolio,version.BaselineRunRef__r.ValuationAsOf__c,original,proposed,portfolioValue,cash));
        for(Inv_PlanImpact__c row:results)InvMath.capture(row);
        List<Inv_PlanImpact__c> old=[SELECT Id,Published__c FROM Inv_PlanImpact__c WHERE PlanVersion__c=:version.Id AND Published__c=true AND Run__c!=:run.Id];
        for(Inv_PlanImpact__c row:old)row.Published__c=false;update as system old;
        upsert as system results Key__c;result.message='Comparison calculated. '+(redemption?'Redemption policy and tax checks require review.':'No trade has been executed.');return result;
    }
    private static Inv_PlanImpact__c impact(Id version,Id run,Id fund,String metric,Decimal before,Decimal after,Boolean review,List<String> notes) {
        return new Inv_PlanImpact__c(Key__c=run+':'+fund+':'+metric,Name=metric,PlanVersion__c=version,Run__c=run,Fund__c=fund,Published__c=true,
            Scope__c=fund==null?'Portfolio':'Fund',Metric__c=metric,Baseline__c=before,Proposed__c=after,
            Coverage__c=review?'policy_review_required':'baseline_prices',Notes__c=String.join(notes,'\n').left(32768));
    }
}
