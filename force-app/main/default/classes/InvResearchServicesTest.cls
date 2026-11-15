@IsTest private class InvResearchServicesTest {
    private static User portfolioManager() {
        User manager=new User(Alias='rsmgr',Email='research-mgr@example.invalid',EmailEncodingKey='UTF-8',LastName='Research manager test',
            LanguageLocaleKey='en_US',LocaleSidKey='en_US',ProfileId=[SELECT Id FROM Profile WHERE Name='Minimum Access - Salesforce' LIMIT 1].Id,
            TimeZoneSidKey='Asia/Kolkata',Username='research-mgr-'+UserInfo.getOrganizationId()+'-'+System.now().getTime()+'@example.invalid');
        insert as system manager;
        for(PermissionSet permission:[SELECT Id FROM PermissionSet WHERE Name IN ('Inv_Viewer','Inv_PortfolioManager')])
            insert as system new PermissionSetAssignment(AssigneeId=manager.Id,PermissionSetId=permission.Id);
        return manager;
    }

    @IsTest static void researchPagesUsePublishedPortfolioAndCurrentFundData() {
        Date asOf=Date.newInstance(2025,1,1);
        Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='research-test:portfolio');insert as system portfolio;
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='research-test:fund',Name__c='Research test fund',
            DisplayName__c='Research test fund',Kind__c='mf_share_class',MappingVerified__c=true,Tracked__c=true,LatestTER__c=0.005,LatestBER__c=0.007,ExpenseDate__c=asOf);
        Inv_MarketInstruments__c peerFund=new Inv_MarketInstruments__c(MigrationKey__c='research-test:peer',Name__c='Peer fund',
            DisplayName__c='Peer fund',Kind__c='mf_share_class',MappingVerified__c=true);
        insert as system new List<Inv_MarketInstruments__c>{fund,peerFund};
        Inv_MarketAmcs__c amc=new Inv_MarketAmcs__c(MigrationKey__c='research-test:amc',Name__c='Research AMC');insert as system amc;
        Inv_MarketSchemes__c scheme=new Inv_MarketSchemes__c(MigrationKey__c='research-test:scheme',Name__c='Research scheme',AmcRef__c=amc.Id);insert as system scheme;
        Inv_MarketSchemeVersions__c schemeVersion=new Inv_MarketSchemeVersions__c(MigrationKey__c='research-test:scheme-version',SchemeRef__c=scheme.Id,
            EffectiveFrom__c=asOf.addYears(-1),Category__c='Flexi Cap');insert as system schemeVersion;
        Inv_MarketFundShareClasses__c share=new Inv_MarketFundShareClasses__c(MigrationKey__c='research-test:share',InstrumentRef__c=fund.Id,
            SchemeRef__c=scheme.Id,Plan__c='Direct',Option__c='Growth');insert as system share;
        Inv_PortfolioAccounts__c account=new Inv_PortfolioAccounts__c(MigrationKey__c='research-test:account',PortfolioRef__c=portfolio.Id,MaskedReference__c='Folio ••12');
        insert as system account;
        insert as system new Inv_PortfolioSipVersions__c(MigrationKey__c='research-test:sip',AccountRef__c=account.Id,InstrumentRef__c=share.Id,
            Amount__c='5000',Frequency__c='monthly',EffectiveFrom__c=asOf.addYears(-1),VerificationState__c='user_confirmed',ReportedStatus__c='active');
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c='research-test:nav',InstrumentRef__c=fund.Id,ObservedOn__c=asOf,
            Value__c='12.34',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        Id runId=InvPortfolioEngine.calculate(portfolio.Id,asOf);
        Inv_Holding__c position=new Inv_Holding__c(Key__c='research-test:holding',Name='Synthetic researched holding',Portfolio__c=portfolio.Id,
            Account__c=account.Id,Fund__c=fund.Id,Units__c=10,MarketValue__c=123.4,NAV__c=12.34,SIPAmount__c=5000);insert as system position;
        insert as system new Inv_HoldingValuation__c(Key__c='research-test:holding-value',Name='Synthetic researched valuation',Holding__c=position.Id,
            Portfolio__c=portfolio.Id,Fund__c=fund.Id,Run__c=runId,AsOf__c=asOf,Units__c=10,NAV__c=12.34,NAVDate__c=asOf,
            Cost__c=100,MarketValue__c=123.4,UnrealizedGain__c=23.4,Weight__c=1,Status__c='Active',Coverage__c='complete',Published__c=true);
        insert as system new Inv_Exposure__c(Key__c='research-test:exposure',Portfolio__c=portfolio.Id,Run__c=runId,Fund__c=fund.Id,
            Dimension__c='Sector',Member__c='Technology',MemberKey__c='Technology',Value__c=50,Weight__c=0.5,DisclosureDate__c=asOf,Coverage__c='complete',Published__c=true);
        insert as system new Inv_FundPeerAssignments__c(Key__c='research-test:peer-assignment',Fund__c=fund.Id,PeerFund__c=peerFund.Id,
            SchemeVersion__c=schemeVersion.Id,Category__c='Flexi Cap',ShareClassRule__c='Direct Growth',Rationale__c='Same category and option',
            EffectiveFrom__c=asOf.addYears(-1),AssignmentStatus__c='active');
        insert as system new Inv_FundMetric__c(Key__c='research-test:metric',Fund__c=fund.Id,Run__c=runId,Metric__c='1 year CAGR',
            Value__c=0.12,PeriodStart__c=asOf.addYears(-1),PeriodEnd__c=asOf,Coverage__c='ok',Published__c=true);
        Inv_MarketFundPortfolioSnapshots__c snapshot=new Inv_MarketFundPortfolioSnapshots__c(MigrationKey__c='research-test:snapshot',
            SchemeRef__c=scheme.Id,HoldingsAsOf__c=asOf,CoverageState__c='partial');insert as system snapshot;
        insert as system new Inv_MarketFundPortfolioPositions__c(MigrationKey__c='research-test:composition',SnapshotRef__c=snapshot.Id,
            RawLabel__c='Synthetic security',WeightRatio__c='0.2',AssetKind__c='equity',Sector__c='Technology',MarketCapBand__c='large');

        InvResearchService.PortfolioData summary=InvResearchService.getPortfolioResearch(portfolio.Id);
        Assert.areEqual(runId,summary.baselineRunId);
        Assert.areEqual(0,summary.marketValue);
        Assert.isNotNull(summary.baselineFingerprint);
        Assert.areEqual(1,summary.sips.size());Assert.areEqual(5000,summary.sips[0].amount);
        Assert.areEqual(1,summary.holdings.size());Assert.areEqual(123.4,summary.holdings[0].marketValue);
        Assert.areEqual(1,summary.exposures.size());

        InvResearchService.FundData fundData=InvResearchService.getFundResearch(fund.Id);
        Assert.areEqual(fund.Id,fundData.fundId);
        Assert.areEqual(12.34,fundData.latestNav);
        Assert.areEqual(asOf,fundData.navDate);
        Assert.isTrue(fundData.mappingVerified);
        Assert.areEqual(5000,fundData.monthlySip);Assert.areEqual('Research AMC',fundData.amc);Assert.areEqual('Flexi Cap',fundData.category);
        Assert.areEqual(0.5,fundData.ter);Assert.areEqual(0.7,fundData.ber);Assert.areEqual(1,fundData.peers.size());Assert.areEqual(peerFund.Id,fundData.peers[0].fundId);
        Assert.areEqual(1,fundData.metrics.size());Assert.isTrue(fundData.composition.size()>=4);Assert.areEqual(1,fundData.positions.size());
        Assert.areEqual(1,fundData.navHistory.size());
    }

    @IsTest static void pipelineWaitsForEveryRequestedStage() {
        Inv_AnalyticsRuns__c pipeline=new Inv_AnalyticsRuns__c(MigrationKey__c='research-test:pipeline',Status__c='running',
            OperationalStatus__c='Running',PortfolioStageStatus__c='Complete',ExposureStageStatus__c='Complete',FundMetricsStageStatus__c='Pending');
        insert as system pipeline;
        InvResearchPipeline.complete(pipeline.Id);
        Assert.areEqual('running',[SELECT Status__c FROM Inv_AnalyticsRuns__c WHERE Id=:pipeline.Id].Status__c);
        pipeline.FundMetricsStageStatus__c='Complete';update as system pipeline;
        InvResearchPipeline.complete(pipeline.Id);
        Inv_AnalyticsRuns__c completed=[SELECT Status__c,OperationalStatus__c,PipelineStage__c FROM Inv_AnalyticsRuns__c WHERE Id=:pipeline.Id];
        Assert.areEqual('complete',completed.Status__c);
        Assert.areEqual('Published',completed.OperationalStatus__c);
        Assert.areEqual('complete',completed.PipelineStage__c);
    }

    @IsTest static void emptyPlanAndRedemptionRequestsFailClearly() {
        Boolean rejected=false;
        try { InvPlanScenarioService.getComparison(new List<Id>()); }
        catch(AuraHandledException expected) { rejected=true; }
        Assert.isTrue(rejected);
        rejected=false;
        try { InvRedemptionService.preview(new InvRedemptionService.Request()); }
        catch(AuraHandledException expected) { rejected=true; }
        Assert.isTrue(rejected);
    }

    @IsTest static void alternativesPreserveBaselineAndFlagMaximumFundCount() {
        User manager=portfolioManager();
        System.runAs(manager) {
            Date asOf=Date.today();
            Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='scenario-test:portfolio');insert as system portfolio;
            Inv_MarketInstruments__c held=new Inv_MarketInstruments__c(MigrationKey__c='scenario-test:held',Name__c='Held synthetic fund',
                DisplayName__c='Held synthetic fund',MappingVerified__c=true,Kind__c='mf_share_class');
            Inv_MarketInstruments__c targetFund=new Inv_MarketInstruments__c(MigrationKey__c='scenario-test:target',Name__c='Target synthetic fund',
                DisplayName__c='Target synthetic fund',MappingVerified__c=true,Kind__c='mf_share_class');
            insert as system new List<Inv_MarketInstruments__c>{held,targetFund};
            Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='scenario-test:run',Kind__c='portfolio',Status__c='complete',
                OperationalStatus__c='Published',AlgorithmVersion__c='test',ValuationAsOf__c=asOf,LedgerCutoff__c=System.now(),
                KnowledgeCutoff__c=System.now(),InputFingerprint__c='synthetic-baseline');insert as system run;
            portfolio.PublishedRun__c=run.Id;update as system portfolio;
            insert as system new Inv_HoldingValuation__c(Key__c='scenario-test:holding',Name='Held synthetic position',Portfolio__c=portfolio.Id,
                Fund__c=held.Id,Run__c=run.Id,AsOf__c=asOf,Units__c=100,NAV__c=10,MarketValue__c=1000,Cost__c=800,
                Status__c='Active',Coverage__c='complete',Published__c=true);

            InvPlanScenarioService.ScenarioInput input=new InvPlanScenarioService.ScenarioInput();input.portfolioId=portfolio.Id;
            input.monthlyBudget=35000;input.cashNeed=0;input.cashHoldDays=10;input.maximumFundCount=1;
            input.exitCandidateFundIds=new List<Id>{held.Id};input.targetAllocations=new List<InvPlanScenarioService.TargetAllocation>();
            InvPlanScenarioService.TargetAllocation exitWeight=new InvPlanScenarioService.TargetAllocation();exitWeight.fundId=held.Id;exitWeight.weightPercent=0;
            InvPlanScenarioService.TargetAllocation newWeight=new InvPlanScenarioService.TargetAllocation();newWeight.fundId=targetFund.Id;newWeight.weightPercent=100;
            input.targetAllocations.add(exitWeight);input.targetAllocations.add(newWeight);

            InvPlanScenarioService.ScenarioResult result=InvPlanScenarioService.createAlternatives(input);
            Assert.areEqual(run.Id,result.baselineRunId);Assert.areEqual(3,result.alternatives.size());
            Assert.isNotNull(result.alternatives[0].versionId);
            Assert.areEqual('Needs review',result.alternatives[2].status,'An unreviewed redemption cannot fund the linked target purchase.');
            InvPlanScenarioService.ComparisonResult comparison=InvPlanScenarioService.getComparison(
                new List<Id>{result.alternatives[0].versionId,result.alternatives[1].versionId});
            Assert.areEqual(run.Id,comparison.baselineRunId);Assert.areEqual(2,comparison.alternatives.size());
            List<InvPlanScenarioService.RedemptionAction> openActions=InvPlanScenarioService.getOpenRedemptionActions(portfolio.Id);
            Assert.areEqual(2,openActions.size());
            input.exitCandidateFundIds=null;input.targetAllocations[0].weightPercent=50;input.targetAllocations[1].weightPercent=50;
            InvPlanScenarioService.ScenarioResult overLimit=InvPlanScenarioService.createAlternatives(input);
            Assert.areEqual('Needs review',overLimit.alternatives[2].status);
            Assert.isTrue(overLimit.alternatives[2].message.contains('maximum of 1'));
        }
    }

    @IsTest static void scenarioRejectsConflictingReviewConstraints() {
        User manager=portfolioManager();
        System.runAs(manager) {
            Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='scenario-test:conflict',MappingVerified__c=true);insert as system fund;
            Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='scenario-test:conflict-portfolio');insert as system portfolio;
            InvPlanScenarioService.ScenarioInput input=new InvPlanScenarioService.ScenarioInput();input.portfolioId=portfolio.Id;
            input.monthlyBudget=35000;input.retainedFundIds=new List<Id>{fund.Id};input.exitCandidateFundIds=new List<Id>{fund.Id};
            InvPlanScenarioService.TargetAllocation target=new InvPlanScenarioService.TargetAllocation();target.fundId=fund.Id;target.weightPercent=100;
            input.targetAllocations=new List<InvPlanScenarioService.TargetAllocation>{target};Boolean rejected=false;
            try{InvPlanScenarioService.createAlternatives(input);}catch(InvPlanScenarioService.ScenarioException expected){rejected=true;}
            Assert.isTrue(rejected,'A fund cannot be both retained and an exit candidate.');
        }
    }

    @IsTest static void redemptionPreviewAndSavedReviewUseFifoAndDatedPolicies() {
        User manager=portfolioManager();
        System.runAs(manager) {
            Date asOf=Date.today(),acquired=Date.today().addDays(-100);
            Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='redemption-test:portfolio');insert as system portfolio;
            Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='redemption-test:fund',Name__c='Redemption test fund',
                DisplayName__c='Redemption test fund',MappingVerified__c=true,Kind__c='mf_share_class');insert as system fund;
            Inv_PortfolioAccounts__c account=new Inv_PortfolioAccounts__c(MigrationKey__c='redemption-test:account',PortfolioRef__c=portfolio.Id,MaskedReference__c='Folio ••34');
            insert as system account;
            Inv_MarketSchemes__c scheme=new Inv_MarketSchemes__c(MigrationKey__c='redemption-test:scheme',Name__c='Redemption scheme');insert as system scheme;
            insert as system new Inv_MarketFundShareClasses__c(MigrationKey__c='redemption-test:share',InstrumentRef__c=fund.Id,SchemeRef__c=scheme.Id,Plan__c='Direct',Option__c='Growth');
            insert as system new List<Inv_MarketEligibilityPolicies__c>{
                new Inv_MarketEligibilityPolicies__c(MigrationKey__c='redemption-test:no-lock',SchemeRef__c=scheme.Id,Kind__c='no_lock',
                    VerificationState__c='verified',EffectiveFrom__c=asOf.addYears(-1)),
                new Inv_MarketEligibilityPolicies__c(MigrationKey__c='redemption-test:load',SchemeRef__c=scheme.Id,Kind__c='exit_load',
                    Parameters__c='{"ratePercent":0}',VerificationState__c='verified',EffectiveFrom__c=asOf.addYears(-1))
            };
            Inv_PortfolioEvents__c eventRow=new Inv_PortfolioEvents__c(MigrationKey__c='redemption-test:event',EventDate__c=acquired,
                PostedAt__c=System.now(),EventType__c='purchase',SourceSequence__c='1');insert as system eventRow;
            insert as system new Inv_PortfolioUnitEntries__c(MigrationKey__c='redemption-test:units',EventRef__c=eventRow.Id,AccountRef__c=account.Id,
                InstrumentRef__c=fund.Id,UnitsDelta__c='100',AcquisitionCost__c='800',AcquisitionDate__c=acquired,
                ConsiderationAmount__c='800',ConsiderationBasis__c='gross',Currency__c='INR');
            Datetime cutoff=System.now().addMinutes(5);
            Inv_AnalyticsRuns__c run=new Inv_AnalyticsRuns__c(MigrationKey__c='redemption-test:run',Kind__c='portfolio',Status__c='complete',
                OperationalStatus__c='Published',AlgorithmVersion__c='test',ValuationAsOf__c=asOf,LedgerCutoff__c=cutoff,
                KnowledgeCutoff__c=cutoff,InputFingerprint__c='redemption-baseline');insert as system run;
            portfolio.PublishedRun__c=run.Id;update as system portfolio;
            Inv_Holding__c holding=new Inv_Holding__c(Key__c='redemption-test:holding',Name='Redemption holding',Portfolio__c=portfolio.Id,
                Account__c=account.Id,Fund__c=fund.Id,Units__c=100,MarketValue__c=1000,NAV__c=10);insert as system holding;
            insert as system new Inv_HoldingValuation__c(Key__c='redemption-test:valuation',Name='Redemption valuation',Holding__c=holding.Id,
                Portfolio__c=portfolio.Id,Fund__c=fund.Id,Run__c=run.Id,AsOf__c=asOf,Units__c=100,NAV__c=10,NAVDate__c=asOf,
                Cost__c=800,MarketValue__c=1000,Status__c='Active',Coverage__c='complete',Published__c=true);
            Inv_PlanningPlans__c plan=new Inv_PlanningPlans__c(MigrationKey__c='redemption-test:plan',PortfolioRef__c=portfolio.Id,
                Name__c='Redemption review',CreatedAt__c=System.now());insert as system plan;
            Inv_PlanningPlanVersions__c version=new Inv_PlanningPlanVersions__c(MigrationKey__c='redemption-test:version',PlanRef__c=plan.Id,
                VersionNo__c='1',Status__c='draft',ValuationAsOf__c=asOf,BaselineRunRef__c=run.Id,
                BaselineInputFingerprint__c=run.InputFingerprint__c,MonthlyBudget__c='35000');insert as system version;
            Inv_PlanningActions__c action=new Inv_PlanningActions__c(MigrationKey__c='action:redemption-test',PlanVersionRef__c=version.Id,
                ActionType__c='redeem',InstrumentRef__c=fund.Id,AccountRef__c=account.Id,RequestedUnits__c='50',AllAvailable__c=false,
                IntendedDate__c=asOf);insert as system action;

            InvRedemptionService.Request request=new InvRedemptionService.Request();request.planVersionId=version.Id;request.actionId=action.Id;
            request.fundId=fund.Id;request.requestedUnits=50;request.settlementDate=asOf.addDays(2);request.acknowledgeUnknownTax=true;
            InvRedemptionService.Preview preview=InvRedemptionService.preview(request);
            Assert.areEqual(100,preview.availableUnits);Assert.areEqual(50,preview.requestedUnits);Assert.areEqual(500,preview.grossProceeds);
            Assert.areEqual(400,preview.costBasis);Assert.areEqual(100,preview.realizedGain);Assert.areEqual(0,preview.exitLoad);
            Assert.areEqual('eligible',preview.eligibilityCoverage);Assert.areEqual('complete',preview.loadCoverage);
            InvRedemptionService.Preview saved=InvRedemptionService.saveReview(request);
            Assert.areEqual('Ready for plan approval',saved.readiness);
            Assert.areEqual(1,[SELECT COUNT() FROM Inv_RedemptionEstimates__c WHERE Action__c=:action.Id AND Published__c=true]);
            Assert.areEqual(1,[SELECT COUNT() FROM Inv_RedemptionLotAllocations__c WHERE Estimate__r.Action__c=:action.Id]);
        }
    }
}
