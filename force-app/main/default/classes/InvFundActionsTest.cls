@IsTest private class InvFundActionsTest {
    @IsTest static void trackingRequiresManagerAndHeldFundsCannotBeDisabled(){
        User manager=new User(Alias='fundmgr',Email='fundmgr@example.invalid',EmailEncodingKey='UTF-8',LastName='Fund manager test',LanguageLocaleKey='en_US',LocaleSidKey='en_US',
            ProfileId=[SELECT Id FROM Profile WHERE Name='Minimum Access - Salesforce' LIMIT 1].Id,TimeZoneSidKey='Asia/Kolkata',Username='fundmgr-'+UserInfo.getOrganizationId()+'-'+System.now().getTime()+'@example.invalid');insert as system manager;
        for(PermissionSet permission:[SELECT Id FROM PermissionSet WHERE Name IN ('Inv_Viewer','Inv_PortfolioManager')])insert as system new PermissionSetAssignment(AssigneeId=manager.Id,PermissionSetId=permission.Id);
        System.runAs(manager){
            Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='tracking:fund',MappingVerified__c=true);insert as system fund;
            InvFundActions.Request request=new InvFundActions.Request();request.fundId=fund.Id;request.tracked=true;InvFundActions.updateTracking(new List<InvFundActions.Request>{request});
            Assert.isTrue([SELECT Tracked__c FROM Inv_MarketInstruments__c WHERE Id=:fund.Id].Tracked__c);
            request.tracked=false;InvFundActions.updateTracking(new List<InvFundActions.Request>{request});
            Assert.isFalse([SELECT Tracked__c FROM Inv_MarketInstruments__c WHERE Id=:fund.Id].Tracked__c);
            insert as system new Inv_Holding__c(Key__c='tracking:holding',Name='Synthetic holding',Fund__c=fund.Id,Units__c=1);
            Boolean rejected=false;try{InvFundActions.updateTracking(new List<InvFundActions.Request>{request});}catch(InvMath.CalculationException e){rejected=true;}Assert.isTrue(rejected);
            fund.MappingVerified__c=false;update as system fund;request.tracked=true;rejected=false;
            try{InvFundActions.updateTracking(new List<InvFundActions.Request>{request});}catch(InvMath.CalculationException e){rejected=true;}Assert.isTrue(rejected);
        }
    }
}
