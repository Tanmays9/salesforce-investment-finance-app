public without sharing class InvDailyRefresh implements Schedulable {
  private Boolean retryOnly;
  public InvDailyRefresh() {
    retryOnly = false;
  }
  public InvDailyRefresh(Boolean retry) {
    retryOnly = retry;
  }
  public void execute(SchedulableContext context) {
    List<Id> funds = new List<Id>();
    for (Inv_MarketInstruments__c f : [
      SELECT Id, NAVAttemptAt__c, NAVRefreshStatus__c
      FROM Inv_MarketInstruments__c
      WHERE Tracked__c = TRUE AND MappingVerified__c = TRUE
      WITH SYSTEM_MODE
    ])
      // Retry runs only revisit funds that have not produced an accepted value today.
      if (
        !retryOnly ||
        f.NAVAttemptAt__c == null ||
        f.NAVAttemptAt__c.date() != Date.today() ||
        f.NAVRefreshStatus__c != 'Accepted'
      )
        funds.add(f.Id);
    if (!funds.isEmpty())
      System.enqueueJob(new InvNAVRefresh(funds));
    else if (retryOnly)
      System.enqueueJob(new InvBenchmarkRefresh());
  }
}
