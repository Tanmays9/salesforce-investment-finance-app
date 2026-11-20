public class InvPlanRules {
  public static void validate(
    List<Inv_PlanningActions__c> actions,
    List<Inv_PlanningActionDependencies__c> dependencies
  ) {
    Map<Id, Inv_PlanningActions__c> byId = new Map<Id, Inv_PlanningActions__c>(
      actions
    );
    Map<Id, Set<Id>> needs = new Map<Id, Set<Id>>();
    Date bridgeEnd;
    for (Inv_PlanningActions__c action : actions) {
      if (
        new Set<String>{ 'buy', 'redeem', 'cash_hold' }
          .contains(action.ActionType__c) && action.IntendedDate__c == null
      )
        throw new InvPlanService.PlanException(
          'Trades and cash-hold periods require an intended date'
        );
      if (action.ActionType__c == 'cash_hold') {
        Decimal days = InvMath.exact(action.CashHoldDays__c);
        if (
          days == null ||
          days < 0 ||
          days != days.setScale(0) ||
          days > 36500
        )
          throw new InvPlanService.PlanException(
            'Cash-hold duration must be whole calendar days from zero to 36500'
          );
        Date endDate = action.IntendedDate__c.addDays(days.intValue());
        if (bridgeEnd == null || endDate > bridgeEnd)
          bridgeEnd = endDate;
      }
    }
    for (Inv_PlanningActions__c action : actions)
      if (
        action.ActionType__c == 'buy' &&
        bridgeEnd != null &&
        action.IntendedDate__c < bridgeEnd
      )
        throw new InvPlanService.PlanException(
          'A purchase occurs before the cash-hold period ends on ' + bridgeEnd
        );
    for (Inv_PlanningActionDependencies__c dependency : dependencies) {
      if (
        !byId.containsKey(dependency.ActionRef__c) ||
        !byId.containsKey(dependency.PrerequisiteRef__c)
      )
        throw new InvPlanService.PlanException(
          'Dependencies must stay within one plan version'
        );
      if (dependency.DayBasis__c != 'calendar' || dependency.Kind__c != 'after')
        throw new InvPlanService.PlanException(
          'Dependency requires a reviewed calendar-day after rule'
        );
      Decimal lag = InvMath.exact(dependency.LagDays__c);
      if (lag == null || lag < 0 || lag != lag.setScale(0) || lag > 36500)
        throw new InvPlanService.PlanException(
          'Dependency lag must be nonnegative whole calendar days'
        );
      Date first = byId.get(dependency.PrerequisiteRef__c).IntendedDate__c,
        second = byId.get(dependency.ActionRef__c).IntendedDate__c;
      if (
        first == null ||
        second == null ||
        second < first.addDays(lag.intValue())
      )
        throw new InvPlanService.PlanException(
          'Action date violates its dependency lag'
        );
      if (!needs.containsKey(dependency.ActionRef__c))
        needs.put(dependency.ActionRef__c, new Set<Id>());
      needs.get(dependency.ActionRef__c).add(dependency.PrerequisiteRef__c);
    }
    Set<Id> resolved = new Set<Id>();
    Boolean progressed = true;
    while (progressed) {
      progressed = false;
      for (Id action : byId.keySet())
        if (!resolved.contains(action)) {
          Set<Id> outstanding = needs.containsKey(action)
            ? needs.get(action).clone()
            : new Set<Id>();
          outstanding.removeAll(resolved);
          if (outstanding.isEmpty()) {
            resolved.add(action);
            progressed = true;
          }
        }
    }
    if (resolved.size() != byId.size())
      throw new InvPlanService.PlanException(
        'Plan dependencies contain a cycle'
      );
  }
}
