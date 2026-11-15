@IsTest private class InvPlanServiceTest {
    @IsTest static void scenariosRemainSeparateAndRejectOverspending() {
        Inv_PortfolioPortfolios__c p=new Inv_PortfolioPortfolios__c(MigrationKey__c='plan-test:p');insert as system p;
        InvPortfolioEngine.calculate(p.Id,Date.today());
        InvPlanService.Request create=new InvPlanService.Request();create.operation='create';create.portfolioId=p.Id;create.title='Synthetic plan';create.budget=35000;
        Id version=InvPlanService.apply(create).versionId;
        Inv_MarketInstruments__c f=new Inv_MarketInstruments__c(MigrationKey__c='plan-test:f');insert as system f;
        InvPlanService.Request add=new InvPlanService.Request();add.operation='add';add.versionId=version;add.fundId=f.Id;add.actionType='set_sip';add.amount=10000;
        InvPlanService.apply(add);
        InvPlanService.Request evaluate=new InvPlanService.Request();evaluate.operation='evaluate';evaluate.versionId=version;
        InvPlanService.apply(evaluate);Assert.areEqual(0,[SELECT COUNT() FROM Inv_PortfolioUnitEntries__c]);
        Assert.areEqual(7,[SELECT COUNT() FROM Inv_PlanImpact__c]);
        InvPlanService.apply(evaluate);Assert.areEqual(7,[SELECT COUNT() FROM Inv_PlanImpact__c]);
        InvPlanService.Request clone=new InvPlanService.Request();clone.operation='clone';clone.versionId=version;
        Assert.areNotEqual(version,InvPlanService.apply(clone).versionId);
        Inv_PlanningPlanVersions__c constrained=[SELECT Id FROM Inv_PlanningPlanVersions__c WHERE Id=:version];
        constrained.ConstraintsJson__c='{"excludedNewPurchaseFundIds":["'+String.valueOf(f.Id)+'"]}';update as system constrained;
        Boolean constrainedRejected=false;try{InvPlanService.apply(evaluate);}catch(InvPlanService.PlanException expected){constrainedRejected=true;}
        Assert.isTrue(constrainedRejected,'A reviewed exclusion blocks future SIP purchases in an edited draft');
        constrained.ConstraintsJson__c=null;update as system constrained;
        add.actionType='buy';add.amount=100;InvPlanService.apply(add);Boolean rejected=false;
        try{InvPlanService.apply(evaluate);}catch(InvPlanService.PlanException e){rejected=true;}Assert.isTrue(rejected);
        Inv_PlanningPlanVersions__c v=[SELECT Status__c FROM Inv_PlanningPlanVersions__c WHERE Id=:version];v.Status__c='approved';update as system v;
        rejected=false;try{InvPlanService.apply(add);}catch(InvPlanService.PlanException e){rejected=true;}Assert.isTrue(rejected);
    }
    @IsTest static void unprivilegedEntryPointIsRejected() {
        User user=new User(Alias='planview',Email='plan-view@example.invalid',EmailEncodingKey='UTF-8',LastName='Plan viewer test',LanguageLocaleKey='en_US',LocaleSidKey='en_US',
            ProfileId=[SELECT Id FROM Profile WHERE Name='Minimum Access - Salesforce' LIMIT 1].Id,TimeZoneSidKey='Asia/Kolkata',Username='plan-view-'+UserInfo.getOrganizationId()+'-'+System.now().getTime()+'@example.invalid');insert as system user;
        System.runAs(user){
            Boolean rejected=false;try{InvPlanService.manage(new List<InvPlanService.Request>{new InvPlanService.Request()});}catch(InvPlanService.PlanException e){rejected=true;}
            Assert.isTrue(rejected);
        }
    }
    @IsTest static void cashBridgeTargetsAndClonePreserveScenarioOnly() {
        Inv_PortfolioPortfolios__c p=new Inv_PortfolioPortfolios__c(MigrationKey__c='bridge:p');insert p;InvPortfolioEngine.calculate(p.Id,Date.today());
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='bridge:f',MappingVerified__c=true);insert fund;
        Inv_Holding__c currentHolding=new Inv_Holding__c(Key__c='bridge:holding',Name='Synthetic holding',Portfolio__c=p.Id,Fund__c=fund.Id,Units__c=100,MarketValue__c=1000,NAV__c=10,SIPAmount__c=0);
        insert currentHolding;
        Id baselineRun=[SELECT PublishedRun__c FROM Inv_PortfolioPortfolios__c WHERE Id=:p.Id].PublishedRun__c;
        Date baselineDate=[SELECT ValuationAsOf__c FROM Inv_AnalyticsRuns__c WHERE Id=:baselineRun].ValuationAsOf__c;
        insert new Inv_HoldingValuation__c(Key__c='bridge:baseline-value',Name='Immutable baseline holding',Holding__c=currentHolding.Id,
            Portfolio__c=p.Id,Fund__c=fund.Id,Run__c=baselineRun,AsOf__c=baselineDate,Units__c=100,NAV__c=10,
            Cost__c=800,MarketValue__c=1000,UnrealizedGain__c=200,Coverage__c='complete',Published__c=true);
        InvPlanService.Request r=new InvPlanService.Request();r.operation='create';r.portfolioId=p.Id;r.title='Bridge';Id version=InvPlanService.apply(r).versionId;
        r=new InvPlanService.Request();r.operation='target';r.versionId=version;r.fundId=fund.Id;r.targetPercent=100;InvPlanService.apply(r);r.targetPercent=80;InvPlanService.apply(r);
        Assert.areEqual(1,[SELECT COUNT() FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:version]);
        r.operation='add';r.actionType='redeem';r.units=50;r.intendedDate=Date.today();InvPlanService.apply(r);
        r=new InvPlanService.Request();r.operation='add';r.versionId=version;r.actionType='cash_hold';r.intendedDate=Date.today();r.cashHoldDays=10;InvPlanService.apply(r);
        r=new InvPlanService.Request();r.operation='add';r.versionId=version;r.actionType='buy';r.fundId=fund.Id;r.amount=500;r.intendedDate=Date.today().addDays(5);InvPlanService.apply(r);
        InvPlanService.Request evaluate=new InvPlanService.Request();evaluate.operation='evaluate';evaluate.versionId=version;
        Boolean rejected=false;try{InvPlanService.apply(evaluate);}catch(InvPlanService.PlanException e){rejected=true;}Assert.isTrue(rejected,'Cash bridge blocks an early purchase');
        Inv_PlanningActions__c purchase=[SELECT Id,IntendedDate__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version AND MigrationKey__c LIKE 'action:%' ORDER BY CreatedDate DESC,Id DESC LIMIT 1];
        // Source action type is a long text field; choose the purchase in memory.
        for(Inv_PlanningActions__c action:[SELECT Id,ActionType__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version])if(action.ActionType__c=='buy')purchase.Id=action.Id;
        // The purchase remains on day five until the settlement-and-hold gate is checked.
        Id redemption;
        for(Inv_PlanningActions__c action:[SELECT Id,ActionType__c FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:version])if(action.ActionType__c=='redeem')redemption=action.Id;
        insert as system new Inv_RedemptionEstimates__c(Name='Synthetic reviewed redemption',Key__c='bridge:estimate',
            Action__c=redemption,AnalysisRun__c=baselineRun,Fund__c=fund.Id,PlanVersion__c=version,Portfolio__c=p.Id,ValuationAsOf__c=baselineDate,
            RequestedUnits__c=50,GrossProceeds__c=500,ExitLoad__c=0,EligibilityCoverage__c='eligible',LoadCoverage__c='complete',
            SettlementDate__c=Date.today().addDays(1),Published__c=true,TaxCoverage__c='unknown_acknowledged');
        rejected=false;try{InvPlanService.apply(evaluate);}catch(InvPlanService.PlanException e){rejected=true;}
        Assert.isTrue(rejected,'Reviewed proceeds cannot fund a purchase before settlement plus the cash hold');
        purchase.IntendedDate__c=Date.today().addDays(11);update purchase;
        InvPlanService.Request dependency=new InvPlanService.Request();dependency.operation='dependency';dependency.versionId=version;dependency.actionId=purchase.Id;dependency.prerequisiteId=redemption;dependency.lagDays=11;InvPlanService.apply(dependency);
        dependency.prerequisiteId=purchase.Id;dependency.lagDays=0;rejected=false;try{InvPlanService.apply(dependency);}catch(InvPlanService.PlanException e){rejected=true;}Assert.isTrue(rejected,'Circular dependencies are rejected');
        currentHolding.Units__c=1;currentHolding.MarketValue__c=9999;update currentHolding;
        InvPlanService.apply(evaluate);
        Assert.areEqual(9999,[SELECT MarketValue__c FROM Inv_Holding__c WHERE Portfolio__c=:p.Id].MarketValue__c,'Scenario calculation must leave the mutable projection untouched');
        Assert.areEqual(1000,[SELECT Baseline__c FROM Inv_PlanImpact__c WHERE PlanVersion__c=:version AND Metric__c='Market value INR'].Baseline__c,
            'Scenario baseline must use the saved valuation row, not current holdings');
        Assert.areEqual(20,[SELECT Proposed__c FROM Inv_PlanImpact__c WHERE PlanVersion__c=:version AND Metric__c='Target deviation percentage points'].Proposed__c);
        InvPlanService.Request clone=new InvPlanService.Request();clone.operation='clone';clone.versionId=version;Id copied=InvPlanService.apply(clone).versionId;
        Assert.areEqual(3,[SELECT COUNT() FROM Inv_PlanningActions__c WHERE PlanVersionRef__c=:copied]);
        Assert.areEqual(1,[SELECT COUNT() FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:copied]);
        Assert.areEqual(1,[SELECT COUNT() FROM Inv_PlanningActionDependencies__c WHERE ActionRef__r.PlanVersionRef__c=:copied]);
        update new Inv_PlanningPlanVersions__c(Id=copied,Status__c='approved');
        Inv_PlanningTargets__c target=[SELECT Id,Ratio__c FROM Inv_PlanningTargets__c WHERE PlanVersionRef__c=:copied];target.Ratio__c='0.9';Assert.isFalse(Database.update(target,false).isSuccess());
        Assert.isFalse(Database.delete(target,false).isSuccess());
        Inv_PlanningActionDependencies__c frozen=[SELECT Id,LagDays__c FROM Inv_PlanningActionDependencies__c WHERE ActionRef__r.PlanVersionRef__c=:copied];frozen.LagDays__c='11';Assert.isFalse(Database.update(frozen,false).isSuccess());Assert.isFalse(Database.delete(frozen,false).isSuccess());
    }
}
