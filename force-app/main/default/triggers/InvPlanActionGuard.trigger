trigger InvPlanActionGuard on Inv_PlanningActions__c(
  before insert,
  before update,
  before delete
) {
  // Check old and new parents so moving an action cannot bypass a frozen version.
  Set<Id> versions = new Set<Id>();
  if (Trigger.isInsert || Trigger.isUpdate)
    for (Inv_PlanningActions__c action : Trigger.new)
      versions.add(action.PlanVersionRef__c);
  if (Trigger.isUpdate || Trigger.isDelete)
    for (Inv_PlanningActions__c action : Trigger.old)
      versions.add(action.PlanVersionRef__c);
  Set<Id> frozen = new Set<Id>();
  for (Inv_PlanningPlanVersions__c version : [
    SELECT Id, Status__c
    FROM Inv_PlanningPlanVersions__c
    WHERE Id IN :versions
  ])
    if (version.Status__c == 'approved' || version.Status__c == 'executed')
      frozen.add(version.Id);
  for (
    Inv_PlanningActions__c action : Trigger.isDelete ? Trigger.old : Trigger.new
  )
    if (
      frozen.contains(action.PlanVersionRef__c) ||
      Trigger.isUpdate &&
      frozen.contains(Trigger.oldMap.get(action.Id).PlanVersionRef__c)
    )
      action.addError(
        'Actions on a frozen plan version cannot change. Clone the version first.'
      );
}
