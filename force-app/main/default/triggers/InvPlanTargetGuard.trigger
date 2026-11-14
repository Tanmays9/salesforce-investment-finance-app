trigger InvPlanTargetGuard on Inv_PlanningTargets__c (before insert,before update,before delete) {
    Set<Id> versions=new Set<Id>();
    if(!Trigger.isDelete)for(Inv_PlanningTargets__c target:Trigger.new)versions.add(target.PlanVersionRef__c);
    if(!Trigger.isInsert)for(Inv_PlanningTargets__c target:Trigger.old)versions.add(target.PlanVersionRef__c);
    Set<Id> frozen=new Set<Id>();
    for(Inv_PlanningPlanVersions__c version:[SELECT Id,Status__c FROM Inv_PlanningPlanVersions__c WHERE Id IN :versions WITH SYSTEM_MODE])
        if(version.Status__c=='approved' || version.Status__c=='executed')frozen.add(version.Id);
    for(Inv_PlanningTargets__c target:Trigger.isDelete?Trigger.old:Trigger.new)
        if(frozen.contains(target.PlanVersionRef__c) || Trigger.isUpdate && frozen.contains(Trigger.oldMap.get(target.Id).PlanVersionRef__c))target.addError('Allocation targets on frozen versions cannot change. Clone the version first.');
}
