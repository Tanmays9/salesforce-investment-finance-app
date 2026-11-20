public with sharing class InvImportActions {
  public class Request {
    @InvocableVariable(required=true)
    public String operation;
    @InvocableVariable
    public Id portfolioId;
    @InvocableVariable
    public List<String> documentIds;
    @InvocableVariable
    public Id summaryId;
    @InvocableVariable
    public Id accountId;
  }
  public class Result {
    @InvocableVariable
    public Id runId;
    @InvocableVariable
    public String message;
  }
  @InvocableMethod(label='Review investment statement import')
  public static List<Result> manage(List<Request> requests) {
    InvCASService.requireManager();
    List<Result> results = new List<Result>();
    for (Request request : requests) {
      Result result = new Result();
      if (request.operation == 'create') {
        if (request.documentIds == null || request.documentIds.size() != 1)
          throw new InvCASService.ImportException('Upload exactly one PDF');
        ContentDocument document = [
          SELECT LatestPublishedVersionId
          FROM ContentDocument
          WHERE Id = :request.documentIds[0]
          WITH USER_MODE
        ];
        result.runId = InvCASService.createRun(
          request.portfolioId,
          document.LatestPublishedVersionId
        );
        result.message = 'Statement uploaded. Start parsing on the next screen.';
      } else if (request.operation == 'map') {
        InvCASService.mapScope(request.summaryId, request.accountId);
        result.message = 'Account mapped. Review transaction matches before confirming.';
      } else if (request.operation == 'confirm') {
        InvCASService.confirmAccount(request.summaryId);
        result.message = 'Account confirmed. Existing transactions were retained; only reconciled new movements were posted.';
      } else
        throw new InvCASService.ImportException('Unknown import action');
      results.add(result);
    }
    return results;
  }
  @AuraEnabled
  public static String submit(Id runId, String password) {
    InvCASService.requireManager();
    Inv_OpsImportRuns__c run = [
      SELECT Id, OperationalStatus__c, ContentVersionId__c, ParserJobId__c
      FROM Inv_OpsImportRuns__c
      WHERE Id = :runId
      WITH USER_MODE
    ];
    if (
      new Set<String>{
          'Complete',
          'Duplicate',
          'Queued',
          'Needs Review',
          'Partially Confirmed'
        }
        .contains(run.OperationalStatus__c)
    )
      return run.OperationalStatus__c;
    String passwordRef;
    if (!String.isBlank(password)) {
      Map<String, Object> reply = call(
        '/passwords',
        new Map<String, Object>{ 'password' => password, 'runId' => run.Id }
      );
      passwordRef = (String) reply.get('passwordRef');
    }
    password = null;
    Map<String, Object> reply = call(
      '/jobs',
      new Map<String, Object>{
        'runId' => run.Id,
        'contentVersionId' => run.ContentVersionId__c,
        'passwordRef' => passwordRef
      }
    );
    // A fast worker can stage while the enqueue call returns; never overwrite that later state.
    run = [
      SELECT Id, OperationalStatus__c
      FROM Inv_OpsImportRuns__c
      WHERE Id = :runId
      FOR UPDATE
    ];
    if (
      run.OperationalStatus__c == 'Uploaded' ||
      run.OperationalStatus__c == 'Parse Failed'
    ) {
      run.OperationalStatus__c = 'Queued';
      run.ParserJobId__c = (String) reply.get('jobId');
      run.Failure__c = null;
      update as system run;
    }
    return run.OperationalStatus__c;
  }
  private static Map<String, Object> call(
    String path,
    Map<String, Object> body
  ) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint('callout:Inv_CASParser' + path);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/json');
    request.setTimeout(25000);
    request.setBody(JSON.serialize(body));
    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200 && response.getStatusCode() != 202)
      throw new AuraHandledException(
        'Parser service could not accept this request. Retry from the import record.'
      );
    return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
  }
}
