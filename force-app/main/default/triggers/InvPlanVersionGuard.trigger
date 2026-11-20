// Approved plans are immutable history; users must clone a version to revise it.
trigger InvPlanVersionGuard on Inv_PlanningPlanVersions__c(
  before update,
  before delete
) {
  for (Inv_PlanningPlanVersions__c previous : Trigger.old) {
    if (previous.Status__c == 'approved' || previous.Status__c == 'executed') {
      if (Trigger.isDelete)
        previous.addError(
          'Approved plan versions are preserved. Clone the version to make changes.'
        );
      else
        Trigger.newMap
          .get(previous.Id)
          .addError(
            'Approved plan versions are frozen. Clone the version to make changes.'
          );
    }
  }
}
