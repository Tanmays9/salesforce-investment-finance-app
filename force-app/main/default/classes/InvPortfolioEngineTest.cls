@IsTest private class InvPortfolioEngineTest {
    @IsTest static void valuationReconcilesAndRepeatIsIdempotent() {
        Date d=Date.newInstance(2024,1,1);
        Inv_PortfolioPortfolios__c p=new Inv_PortfolioPortfolios__c(MigrationKey__c='test:p');insert p;
        Inv_PortfolioAccounts__c a=new Inv_PortfolioAccounts__c(MigrationKey__c='test:a',PortfolioRef__c=p.Id,MaskedReference__c='synthetic');insert a;
        Inv_MarketInstruments__c f=new Inv_MarketInstruments__c(MigrationKey__c='test:f',Name__c='Synthetic fund',Kind__c='mf_share_class');insert f;
        Inv_PortfolioEvents__c e=new Inv_PortfolioEvents__c(MigrationKey__c='test:e',EventType__c='purchase',EventDate__c=d,PostedAt__c=System.now());insert e;
        insert new Inv_PortfolioUnitEntries__c(MigrationKey__c='test:u',AccountRef__c=a.Id,InstrumentRef__c=f.Id,EventRef__c=e.Id,
            UnitsDelta__c='100',AcquisitionCost__c='1000',ConsiderationAmount__c='1000',ConsiderationBasis__c='gross',Currency__c='INR');
        insert new Inv_MarketPriceObservations__c(MigrationKey__c='test:price',InstrumentRef__c=f.Id,ObservedOn__c=d.addDays(365),Value__c='11',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        insert new Inv_MarketPriceObservations__c(MigrationKey__c='test:price-unselected',InstrumentRef__c=f.Id,ObservedOn__c=d.addDays(365),Value__c='10.8',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted');
        insert new Inv_PortfolioPositionSnapshots__c(MigrationKey__c='test:snapshot',AccountRef__c=a.Id,InstrumentRef__c=f.Id,AsOf__c=d,ReportedUnits__c='100');
        insert new Inv_PortfolioEvents__c(MigrationKey__c='test:future-reversal',EventType__c='reversal',EventDate__c=d.addDays(400),
            PostedAt__c=System.now(),ReversesRef__c=e.Id);
        Id run=InvPortfolioEngine.calculate(p.Id,d.addDays(365));
        Inv_Holding__c h=[SELECT Units__c,Cost__c,MarketValue__c,UnrealizedGain__c,ReconciledThrough__c,XIRR__c,UnitCoverage__c,BasisCoverage__c FROM Inv_Holding__c LIMIT 1];
        Assert.areEqual(100,h.Units__c);Assert.areEqual(1000,h.Cost__c);Assert.areEqual(1100,h.MarketValue__c);
        Assert.areEqual('reconciled',h.UnitCoverage__c);Assert.areEqual('complete',h.BasisCoverage__c);
        Assert.areEqual(100,h.UnrealizedGain__c);Assert.areEqual(d,h.ReconciledThrough__c);Assert.isTrue((h.XIRR__c-0.1).abs()<0.000001);
        Assert.areEqual(run,InvPortfolioEngine.calculate(p.Id,d.addDays(365)));
        Assert.areEqual(1,[SELECT count() FROM Inv_Holding__c]);Assert.areEqual(1,[SELECT count() FROM Inv_PortfolioValuation__c]);
        Assert.areEqual(null,[SELECT XIRR__c FROM Inv_PortfolioValuation__c LIMIT 1].XIRR__c,'External cashflows are not assumed complete');
    }

    @IsTest static void movementExplainsPriceAndPostedUnitChangeSeparately() {
        Date startDate=Date.newInstance(2025,1,1),endDate=startDate.addDays(30);
        Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='movement:p');insert as system portfolio;
        Inv_PortfolioAccounts__c account=new Inv_PortfolioAccounts__c(MigrationKey__c='movement:a',PortfolioRef__c=portfolio.Id,MaskedReference__c='synthetic');insert as system account;
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='movement:f',Name__c='Movement test fund',Kind__c='mf_share_class');insert as system fund;
        Inv_PortfolioEvents__c first=new Inv_PortfolioEvents__c(MigrationKey__c='movement:e1',EventType__c='purchase',EventDate__c=startDate,PostedAt__c=System.now());insert as system first;
        insert as system new Inv_PortfolioUnitEntries__c(MigrationKey__c='movement:u1',AccountRef__c=account.Id,InstrumentRef__c=fund.Id,EventRef__c=first.Id,
            UnitsDelta__c='100',AcquisitionCost__c='1000',ConsiderationAmount__c='1000',ConsiderationBasis__c='gross',Currency__c='INR');
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c='movement:nav1',InstrumentRef__c=fund.Id,ObservedOn__c=startDate,
            Value__c='10',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        Id openingRun=InvPortfolioEngine.calculate(portfolio.Id,startDate);
        Inv_PortfolioEvents__c second=new Inv_PortfolioEvents__c(MigrationKey__c='movement:e2',EventType__c='purchase',EventDate__c=endDate,PostedAt__c=System.now());insert as system second;
        insert as system new Inv_PortfolioUnitEntries__c(MigrationKey__c='movement:u2',AccountRef__c=account.Id,InstrumentRef__c=fund.Id,EventRef__c=second.Id,
            UnitsDelta__c='50',AcquisitionCost__c='600',ConsiderationAmount__c='600',ConsiderationBasis__c='gross',Currency__c='INR');
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c='movement:nav2',InstrumentRef__c=fund.Id,ObservedOn__c=endDate,
            Value__c='12',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        Id closingRun=InvPortfolioEngine.calculate(portfolio.Id,endDate);
        InvMovementService.MovementResult result=InvMovementService.compare(portfolio.Id,openingRun,closingRun);
        Assert.areEqual(800,result.valueChange);Assert.areEqual(200,result.marketMovement);Assert.areEqual(600,result.purchases);
        Assert.areEqual(0,result.redemptions);Assert.areEqual(0,result.reconciliationAdjustment);Assert.areEqual(0,result.residual);
        Assert.areEqual('period_attribution_available',result.coverage);
    }

    @IsTest static void movementIncludesReversalOfAnEarlierHolding() {
        Date startDate=Date.newInstance(2025,1,1),endDate=startDate.addDays(30);
        Inv_PortfolioPortfolios__c portfolio=new Inv_PortfolioPortfolios__c(MigrationKey__c='movement-reversal:p');insert as system portfolio;
        Inv_PortfolioAccounts__c account=new Inv_PortfolioAccounts__c(MigrationKey__c='movement-reversal:a',PortfolioRef__c=portfolio.Id,MaskedReference__c='synthetic');insert as system account;
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='movement-reversal:f',Name__c='Reversal movement test',Kind__c='mf_share_class');insert as system fund;
        Inv_PortfolioEvents__c purchase=new Inv_PortfolioEvents__c(MigrationKey__c='movement-reversal:purchase',EventType__c='purchase',EventDate__c=startDate,PostedAt__c=System.now());insert as system purchase;
        insert as system new Inv_PortfolioUnitEntries__c(MigrationKey__c='movement-reversal:purchase-unit',AccountRef__c=account.Id,InstrumentRef__c=fund.Id,EventRef__c=purchase.Id,
            UnitsDelta__c='100',AcquisitionCost__c='1000',ConsiderationAmount__c='1000',ConsiderationBasis__c='gross',Currency__c='INR');
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c='movement-reversal:nav-open',InstrumentRef__c=fund.Id,ObservedOn__c=startDate,
            Value__c='10',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        Id openingRun=InvPortfolioEngine.calculate(portfolio.Id,startDate);
        Inv_PortfolioEvents__c reversal=new Inv_PortfolioEvents__c(MigrationKey__c='movement-reversal:event',EventType__c='reversal',EventDate__c=endDate,
            PostedAt__c=System.now(),ReversesRef__c=purchase.Id);insert as system reversal;
        insert as system new Inv_PortfolioUnitEntries__c(MigrationKey__c='movement-reversal:reversal-unit',AccountRef__c=account.Id,InstrumentRef__c=fund.Id,EventRef__c=reversal.Id,
            UnitsDelta__c='-100',ConsiderationAmount__c='1000',ConsiderationBasis__c='gross',Currency__c='INR');
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c='movement-reversal:nav-close',InstrumentRef__c=fund.Id,ObservedOn__c=endDate,
            Value__c='12',PriceKind__c='NAV',KindFilter__c='NAV',QualityStatus__c='accepted',QualityFilter__c='accepted',SelectedNAV__c=true);
        Id closingRun=InvPortfolioEngine.calculate(portfolio.Id,endDate);
        InvMovementService.MovementResult result=InvMovementService.compare(portfolio.Id,openingRun,closingRun);
        Assert.areEqual(-1000,result.valueChange);Assert.areEqual(200,result.marketMovement);Assert.areEqual(-1200,result.otherUnitMovements);
        Assert.areEqual(0,result.reconciliationAdjustment);Assert.areEqual(0,result.residual);
        Assert.areEqual('period_attribution_available',result.coverage);
    }
}
