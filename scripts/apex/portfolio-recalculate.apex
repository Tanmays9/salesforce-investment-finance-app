for (Inv_PortfolioPortfolios__c portfolio : [SELECT Id FROM Inv_PortfolioPortfolios__c]) {
    Id runId = InvPortfolioEngine.calculate(portfolio.Id, Date.today());
    System.debug(LoggingLevel.INFO, 'Published portfolio analysis run: ' + runId);
}
