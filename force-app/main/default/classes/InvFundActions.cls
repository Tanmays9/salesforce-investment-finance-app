public with sharing class InvFundActions {
  public class Request {
    @InvocableVariable(required=true)
    public Id fundId;
    @InvocableVariable(required=true)
    public Boolean tracked;
  }
  public class Result {
    @InvocableVariable
    public String message;
  }
  @InvocableMethod(label='Update fund tracking')
  public static List<Result> updateTracking(List<Request> requests) {
    if (!FeatureManagement.checkPermission('Inv_ManagePortfolio'))
      throw new InvMath.CalculationException(
        'Portfolio Manager permission is required'
      );
    Set<Id> ids = new Set<Id>();
    for (Request r : requests)
      ids.add(r.fundId);
    Map<Id, Inv_MarketInstruments__c> visible = new Map<Id, Inv_MarketInstruments__c>(
      [
        SELECT Id, MappingVerified__c
        FROM Inv_MarketInstruments__c
        WHERE Id IN :ids
        WITH USER_MODE
      ]
    );
    Set<Id> held = new Set<Id>();
    for (Inv_Holding__c h : [
      SELECT Fund__c
      FROM Inv_Holding__c
      WHERE Fund__c IN :ids AND Units__c > 0
      WITH SYSTEM_MODE
    ])
      held.add(h.Fund__c);
    Map<Id, Inv_MarketInstruments__c> updates = new Map<Id, Inv_MarketInstruments__c>();
    List<Result> results = new List<Result>();
    for (Request r : requests) {
      if (
        !visible.containsKey(r.fundId) ||
        !visible.get(r.fundId).MappingVerified__c ||
        r.tracked == null
      )
        throw new InvMath.CalculationException(
          'A verified accessible fund and tracking choice are required'
        );
      if (!r.tracked && held.contains(r.fundId))
        throw new InvMath.CalculationException(
          'Held funds must remain tracked for portfolio valuation'
        );
      updates.put(
        r.fundId,
        new Inv_MarketInstruments__c(Id = r.fundId, Tracked__c = r.tracked)
      );
      Result result = new Result();
      result.message = r.tracked
        ? 'Fund included in daily NAV refresh.'
        : 'Unheld fund removed from daily NAV refresh.';
      results.add(result);
    }
    update as system updates.values();
    return results;
  }
}
