trigger InvPlanDependencyGuard on Inv_PlanningActionDependencies__c (before insert,before update,before delete) {
    Set<Id> actionIds=new Set<Id>();
    if(!Trigger.isDelete)for(Inv_PlanningActionDependencies__c row:Trigger.new){actionIds.add(row.ActionRef__c);actionIds.add(row.PrerequisiteRef__c);}
    if(!Trigger.isInsert)for(Inv_PlanningActionDependencies__c row:Trigger.old){actionIds.add(row.ActionRef__c);actionIds.add(row.PrerequisiteRef__c);}
    Set<Id> frozen=new Set<Id>();
    for(Inv_PlanningActions__c action:[SELECT Id,PlanVersionRef__r.Status__c FROM Inv_PlanningActions__c WHERE Id IN :actionIds WITH SYSTEM_MODE])
        if(action.PlanVersionRef__r.Status__c=='approved' || action.PlanVersionRef__r.Status__c=='executed')frozen.add(action.Id);
    for(Inv_PlanningActionDependencies__c row:Trigger.isDelete?Trigger.old:Trigger.new){
        Boolean blocked=frozen.contains(row.ActionRef__c) || frozen.contains(row.PrerequisiteRef__c);
        if(Trigger.isUpdate){Inv_PlanningActionDependencies__c old=Trigger.oldMap.get(row.Id);blocked=blocked || frozen.contains(old.ActionRef__c) || frozen.contains(old.PrerequisiteRef__c);}
        if(blocked)row.addError('Dependencies on frozen plan versions cannot change. Clone the version first.');
    }
}
