@IsTest
private class InvPlanGuardTest {
  @IsTest
  static void approvedHistoryRequiresNewVersions() {
    Inv_PlanningPlans__c plan = new Inv_PlanningPlans__c(
      MigrationKey__c = 'guard:plan'
    );
    insert plan;
    Inv_PlanningPlanVersions__c version = new Inv_PlanningPlanVersions__c(
      MigrationKey__c = 'guard:version',
      PlanRef__c = plan.Id,
      Status__c = 'draft'
    );
    insert version;
    Inv_PlanningActions__c action = new Inv_PlanningActions__c(
      MigrationKey__c = 'guard:action',
      PlanVersionRef__c = version.Id
    );
    insert action;
    version.Status__c = 'approved';
    update version;
    version.Status__c = 'draft';
    Assert.isFalse(Database.update(version, false).isSuccess());
    Assert.isFalse(Database.delete(version, false).isSuccess());
    action.Rationale__c = 'forbidden';
    Assert.isFalse(Database.update(action, false).isSuccess());
    Assert.isFalse(Database.delete(action, false).isSuccess());
    Assert.isFalse(
      Database.insert(
          new Inv_PlanningActions__c(
            MigrationKey__c = 'guard:forbidden',
            PlanVersionRef__c = version.Id
          ),
          false
        )
        .isSuccess()
    );
  }
}
