@IsTest private class InvPortfolioEngineTest {
    @IsTest static void valuationReconcilesAndRepeatIsIdempotent() {
        Date d=Date.newInstance(2024,1,1);
        Inv_PortfolioPortfolios__c p=new Inv_PortfolioPortfolios__c(MigrationKey__c='test:p');insert p;
        Inv_PortfolioAccounts__c a=new Inv_PortfolioAccounts__c(MigrationKey__c='test:a',PortfolioRef__c=p.Id,MaskedReference__c='synthetic');insert a;
        Inv_MarketInstruments__c f=new Inv_MarketInstruments__c(MigrationKey__c='test:f',Name__c='Synthetic fund',Kind__c='mf_share_class');insert f;
        Inv_PortfolioEvents__c e=new Inv_PortfolioEvents__c(MigrationKey__c='test:e',EventType__c='purchase',EventDate__c=d,PostedAt__c=System.now());insert e;
        insert new Inv_PortfolioUnitEntries__c(MigrationKey__c='test:u',AccountRef__c=a.Id,InstrumentRef__c=f.Id,EventRef__c=e.Id,
            UnitsDelta__c='100',AcquisitionCost__c='1000',ConsiderationAmount__c='1000',ConsiderationBasis__c='gross',Currency__c='INR');
        insert new Inv_MarketPriceObservations__c(MigrationKey__c='test:price',InstrumentRef__c=f.Id,ObservedOn__c=d.addDays(365),Value__c='11',PriceKind__c='NAV',QualityStatus__c='accepted');
        insert new Inv_PortfolioPositionSnapshots__c(MigrationKey__c='test:snapshot',AccountRef__c=a.Id,InstrumentRef__c=f.Id,AsOf__c=d,ReportedUnits__c='100');
        Id run=InvPortfolioEngine.calculate(p.Id,d.addDays(365));
        Inv_Holding__c h=[SELECT Units__c,Cost__c,MarketValue__c,UnrealizedGain__c,ReconciledThrough__c,XIRR__c FROM Inv_Holding__c LIMIT 1];
        Assert.areEqual(100,h.Units__c);Assert.areEqual(1000,h.Cost__c);Assert.areEqual(1100,h.MarketValue__c);
        Assert.areEqual(100,h.UnrealizedGain__c);Assert.areEqual(d,h.ReconciledThrough__c);Assert.isTrue((h.XIRR__c-0.1).abs()<0.000001);
        Assert.areEqual(run,InvPortfolioEngine.calculate(p.Id,d.addDays(365)));
        Assert.areEqual(1,[SELECT count() FROM Inv_Holding__c]);Assert.areEqual(1,[SELECT count() FROM Inv_PortfolioValuation__c]);
        Assert.areEqual(null,[SELECT XIRR__c FROM Inv_PortfolioValuation__c LIMIT 1].XIRR__c,'External cashflows are not assumed complete');
    }
}
