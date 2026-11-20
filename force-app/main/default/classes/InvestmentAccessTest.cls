@IsTest
private class InvestmentAccessTest {
  @IsTest
  static void viewerCanReadButCannotChangePreservedRecords() {
    Profile baseline = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User viewer = new User(
      Alias = 'invtest',
      Email = 'investment-access@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'Investment access test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = baseline.Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'investment-access-' +
        UserInfo.getOrganizationId() +
        '-' +
        DateTime.now().getTime() +
        '@example.invalid'
    );
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert viewer;
      insert new PermissionSetAssignment(
        AssigneeId = viewer.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'Inv_Viewer'
          LIMIT 1
        ]
        .Id
      );
    }
    Inv_PortfolioEvents__c preserved = new Inv_PortfolioEvents__c(
      MigrationKey__c = 'access-test:preserved'
    );
    insert preserved;
    ContentVersion evidence = new ContentVersion(
      Title = 'Investment access fixture',
      PathOnClient = 'access-fixture.txt',
      VersionData = Blob.valueOf('Synthetic investment evidence')
    );
    insert evidence;
    Id documentId = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :evidence.Id
    ]
    .ContentDocumentId;
    insert new ContentDocumentLink(
      ContentDocumentId = documentId,
      LinkedEntityId = preserved.Id,
      ShareType = 'V'
    );
    System.runAs(viewer) {
      List<Inv_PortfolioEvents__c> visible = [
        SELECT Id, MigrationKey__c
        FROM Inv_PortfolioEvents__c
        WHERE Id = :preserved.Id
        WITH USER_MODE
      ];
      Assert.areEqual(
        1,
        visible.size(),
        'The viewer must be able to read investment records.'
      );
      ContentVersion readableEvidence = [
        SELECT VersionData
        FROM ContentVersion
        WHERE ContentDocumentId = :documentId AND IsLatest = TRUE
        WITH USER_MODE
      ];
      Assert.areEqual(
        'Synthetic investment evidence',
        readableEvidence.VersionData.toString(),
        'Record viewers must be able to read linked evidence.'
      );
      Boolean rejected = false;
      try {
        Database.insert(
          new Inv_PortfolioEvents__c(MigrationKey__c = 'access-test:forbidden'),
          AccessLevel.USER_MODE
        );
      } catch (DmlException e) {
        rejected = true;
      } catch (TypeException e) {
        rejected = e.getMessage().contains('not allowed');
      }
      Assert.isTrue(
        rejected,
        'The viewer must not be able to create ledger records.'
      );
      rejected = false;
      try {
        Database.update(
          new Inv_PortfolioEvents__c(
            Id = preserved.Id,
            SnapshotNotice__c = 'forbidden'
          ),
          AccessLevel.USER_MODE
        );
      } catch (DmlException e) {
        rejected = true;
      } catch (TypeException e) {
        rejected = e.getMessage().contains('not allowed');
      }
      Assert.isTrue(
        rejected,
        'The viewer must not be able to edit ledger records.'
      );
      rejected = false;
      try {
        Database.delete(
          new Inv_PortfolioEvents__c(Id = preserved.Id),
          AccessLevel.USER_MODE
        );
      } catch (DmlException e) {
        rejected = true;
      } catch (TypeException e) {
        rejected = e.getMessage().contains('not allowed');
      }
      Assert.isTrue(
        rejected,
        'The viewer must not be able to delete ledger records.'
      );
    }
  }
}
