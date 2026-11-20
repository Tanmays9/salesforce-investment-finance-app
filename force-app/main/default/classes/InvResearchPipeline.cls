/** Publishes a refresh pipeline only after each requested stage has completed. */
public without sharing class InvResearchPipeline {
  public static void complete(Id pipelineId) {
    if (pipelineId == null)
      return;
    Inv_AnalyticsRuns__c pipeline = [
      SELECT
        Id,
        Status__c,
        PortfolioStageStatus__c,
        ExposureStageStatus__c,
        FundMetricsStageStatus__c,
        PipelineStage__c
      FROM Inv_AnalyticsRuns__c
      WHERE Id = :pipelineId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    Boolean failed =
      pipeline.PortfolioStageStatus__c == 'Failed' ||
      pipeline.ExposureStageStatus__c == 'Failed' ||
      pipeline.FundMetricsStageStatus__c == 'Failed';
    Boolean waiting =
      pipeline.PortfolioStageStatus__c == 'Running' ||
      pipeline.ExposureStageStatus__c == 'Running' ||
      pipeline.FundMetricsStageStatus__c == 'Running' ||
      pipeline.FundMetricsStageStatus__c == 'Pending';
    if (waiting)
      return;
    pipeline.Status__c = failed ? 'failed' : 'complete';
    pipeline.OperationalStatus__c = failed ? 'Failed' : 'Published';
    pipeline.PipelineStage__c = failed ? 'failed' : 'complete';
    pipeline.CompletedAt__c = System.now();
    update as system pipeline;
  }
}
