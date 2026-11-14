public without sharing class InvFundMetricsContinuation implements Schedulable {
    private List<Id> funds;
    public InvFundMetricsContinuation(List<Id> ids){funds=ids;}
    public void execute(SchedulableContext context){System.enqueueJob(new InvFundMetrics(funds));}
}
