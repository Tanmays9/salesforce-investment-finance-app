@RestResource(urlMapping='/investments/imports/*')
global without sharing class InvImportEndpoint {
  @HttpPost
  global static void receive() {
    if (!FeatureManagement.checkPermission('Inv_ParseStatements')) {
      RestContext.response.statusCode = 403;
      return;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.request.requestBody.toString()
    );
    Id runId = (Id) (String) body.get('runId');
    if (body.get('operation') == 'stage') {
      InvCASService.Payload payload = (InvCASService.Payload) JSON.deserialize(
        JSON.serialize(body.get('payload')),
        InvCASService.Payload.class
      );
      InvCASService.stage(runId, payload);
    } else if (body.get('operation') == 'failed') {
      Inv_OpsImportRuns__c run = [
        SELECT Id, MigrationKey__c, OperationalStatus__c
        FROM Inv_OpsImportRuns__c
        WHERE Id = :runId
        WITH SYSTEM_MODE
        FOR UPDATE
      ];
      if (!run.MigrationKey__c.startsWith('cas-import:')) {
        RestContext.response.statusCode = 403;
        return;
      }
      if (
        run.OperationalStatus__c != 'Complete' &&
        run.OperationalStatus__c != 'Duplicate'
      ) {
        run.OperationalStatus__c = 'Parse Failed';
        run.Failure__c = String.valueOf(body.get('errorType')).left(200);
        update as system run;
      }
    } else {
      RestContext.response.statusCode = 400;
      return;
    }
    RestContext.response.statusCode = 200;
    RestContext.response.responseBody = Blob.valueOf('{"accepted":true}');
  }
}
