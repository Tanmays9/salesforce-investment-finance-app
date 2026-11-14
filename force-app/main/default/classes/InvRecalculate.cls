public without sharing class InvRecalculate implements Queueable {
    private List<Id> portfolios;
    private Boolean refreshMetrics=false;
    private Integer lockRetries=0;
    public InvRecalculate(){portfolios=new List<Id>();for(Inv_PortfolioPortfolios__c p:[SELECT Id FROM Inv_PortfolioPortfolios__c WITH SYSTEM_MODE ])portfolios.add(p.Id);}
    public InvRecalculate(Boolean metrics){this();refreshMetrics=metrics;}
    public InvRecalculate(List<Id> ids){portfolios=ids;}
    public void execute(QueueableContext context) {
        if(portfolios.isEmpty())return;Id portfolio=portfolios.remove(0);Savepoint checkpoint=Database.setSavepoint();
        try {InvPortfolioEngine.calculate(portfolio,Date.today());}
        catch(Exception e) {
            Database.rollback(checkpoint);
            if(lockRetries<2 && (e.getMessage().contains('Record Currently Unavailable') || e.getMessage().contains('UNABLE_TO_LOCK_ROW'))){
                portfolios.add(0,portfolio);InvRecalculate retry=new InvRecalculate(portfolios);retry.refreshMetrics=refreshMetrics;retry.lockRetries=lockRetries+1;System.enqueueJob(retry,1);return;
            }
            insert as system new Inv_AnalyticsRuns__c(MigrationKey__c='failed:'+context.getJobId(),PortfolioRef__c=portfolio,
                OperationalStatus__c='Failed',Status__c='failed',Failure__c=e.getTypeName()+': '+e.getMessage(),StartedAt__c=System.now());
        }
        if(!portfolios.isEmpty()){InvRecalculate next=new InvRecalculate(portfolios);next.refreshMetrics=refreshMetrics;System.enqueueJob(next);}
        else if(refreshMetrics) {
            List<Id> funds=new List<Id>();for(Inv_MarketInstruments__c fund:[SELECT Id FROM Inv_MarketInstruments__c WHERE Tracked__c=true WITH SYSTEM_MODE])funds.add(fund.Id);
            if(!funds.isEmpty())System.enqueueJob(new InvFundMetrics(funds));
        }
    }
}
