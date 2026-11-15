public without sharing class InvRecalculate implements Queueable {
    private List<Id> portfolios;
    private Boolean refreshMetrics=false;
    private Integer lockRetries=0;
    private Id pipelineId;
    private Boolean hadFailure=false;
    public InvRecalculate(){portfolios=new List<Id>();for(Inv_PortfolioPortfolios__c p:[SELECT Id FROM Inv_PortfolioPortfolios__c WITH SYSTEM_MODE ])portfolios.add(p.Id);}
    public InvRecalculate(Boolean metrics){this();refreshMetrics=metrics;}
    public InvRecalculate(List<Id> ids){portfolios=ids;}
    private InvRecalculate(List<Id> ids,Boolean metrics,Integer retries,Id pipeline,Boolean failed) {
        portfolios=new List<Id>(ids);refreshMetrics=metrics;lockRetries=retries;pipelineId=pipeline;hadFailure=failed;
    }
    public void execute(QueueableContext context) {
        if(pipelineId==null) {
            Inv_AnalyticsRuns__c pipeline=new Inv_AnalyticsRuns__c(MigrationKey__c='research-pipeline:'+context.getJobId(),
                Kind__c='research_pipeline',AlgorithmVersion__c='sf-research-pipeline-1',Status__c='running',OperationalStatus__c='Running',
                PipelineStage__c='portfolio_valuation',PortfolioStageStatus__c='Running',ExposureStageStatus__c='Pending',
                FundMetricsStageStatus__c=refreshMetrics?'Pending':'Not requested',StartedAt__c=System.now(),
                InputManifest__c=JSON.serialize(new Map<String,Object>{'portfolios'=>portfolios,'refreshFundMetrics'=>refreshMetrics,'valuationDate'=>Date.today()}));
            insert as system pipeline;pipelineId=pipeline.Id;
        }
        if(portfolios.isEmpty()) {finishPortfolioStage();return;}
        Id portfolio=portfolios.remove(0);Savepoint checkpoint=Database.setSavepoint();
        try {InvPortfolioEngine.calculate(portfolio,Date.today(),pipelineId);}
        catch(Exception e) {
            Database.rollback(checkpoint);
            if(lockRetries<2 && (e.getMessage().contains('Record Currently Unavailable') || e.getMessage().contains('UNABLE_TO_LOCK_ROW'))){
                portfolios.add(0,portfolio);System.enqueueJob(new InvRecalculate(portfolios,refreshMetrics,lockRetries+1,pipelineId,hadFailure),1);return;
            }
            hadFailure=true;
            insert as system new Inv_AnalyticsRuns__c(MigrationKey__c='failed:'+context.getJobId(),PortfolioRef__c=portfolio,
                PipelineRef__c=pipelineId,OperationalStatus__c='Failed',Status__c='failed',Failure__c=e.getTypeName()+': '+e.getMessage(),StartedAt__c=System.now());
        }
        if(!portfolios.isEmpty())System.enqueueJob(new InvRecalculate(portfolios,refreshMetrics,0,pipelineId,hadFailure));
        else finishPortfolioStage();
    }
    private void finishPortfolioStage() {
        Inv_AnalyticsRuns__c pipeline=[SELECT Id,PortfolioStageStatus__c,ExposureStageStatus__c,FundMetricsStageStatus__c FROM Inv_AnalyticsRuns__c WHERE Id=:pipelineId WITH SYSTEM_MODE FOR UPDATE];
        pipeline.PortfolioStageStatus__c=hadFailure?'Failed':'Complete';pipeline.ExposureStageStatus__c=hadFailure?'Failed':'Complete';
        pipeline.PipelineStage__c=refreshMetrics?'fund_metrics':'complete';
        if(!refreshMetrics){pipeline.FundMetricsStageStatus__c='Not requested';update as system pipeline;InvResearchPipeline.complete(pipelineId);return;}
        pipeline.FundMetricsStageStatus__c='Running';update as system pipeline;
        List<Id> funds=new List<Id>();for(Inv_MarketInstruments__c fund:[SELECT Id FROM Inv_MarketInstruments__c WHERE Tracked__c=true WITH SYSTEM_MODE])funds.add(fund.Id);
        if(funds.isEmpty()){pipeline.FundMetricsStageStatus__c='Complete';update as system pipeline;InvResearchPipeline.complete(pipelineId);}
        else System.enqueueJob(new InvFundMetrics(funds,pipelineId));
    }
}
