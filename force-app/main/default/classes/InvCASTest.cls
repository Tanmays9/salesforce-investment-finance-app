@IsTest
private class InvCASTest {
  @TestSetup
  static void manager() {
    User user = new User(
      Alias = 'castest',
      Email = 'cas-test@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'CAS manager test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = 'Minimum Access - Salesforce'
        LIMIT 1
      ]
      .Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'cas-manager-' +
        UserInfo.getOrganizationId() +
        '-' +
        System.now().getTime() +
        '@example.invalid'
    );
    insert as system user;
    insert as system new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Inv_PortfolioManager'
      ]
      .Id
    );
    insert as system new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Inv_Parser']
      .Id
    );
    insert as system new PermissionSetAssignment(
      AssigneeId = user.Id,
      PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Inv_Viewer']
      .Id
    );
    insert as system new User(
      Alias = 'casnone',
      Email = 'cas-none@example.invalid',
      EmailEncodingKey = 'UTF-8',
      LastName = 'CAS access test',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = user.ProfileId,
      TimeZoneSidKey = 'Asia/Kolkata',
      Username = 'cas-none-' +
        UserInfo.getOrganizationId() +
        '-' +
        System.now().getTime() +
        '@example.invalid'
    );
  }
  private static User managerUser() {
    return [
      SELECT Id
      FROM User
      WHERE Alias = 'castest' AND LastName = 'CAS manager test'
      LIMIT 1
    ];
  }
  private static User unprivilegedUser() {
    return [
      SELECT Id
      FROM User
      WHERE Alias = 'casnone' AND LastName = 'CAS access test'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  private class Fixture {
    public Id portfolio, account, fund, version, run;
  }
  private static Fixture fixture(Boolean mapped) {
    Fixture f = new Fixture();
    Inv_PortfolioPortfolios__c p = new Inv_PortfolioPortfolios__c(
      MigrationKey__c = 'cas-test:p'
    );
    insert as system p;
    f.portfolio = p.Id;
    Inv_PortfolioAccounts__c a = new Inv_PortfolioAccounts__c(
      MigrationKey__c = 'cas-test:a',
      PortfolioRef__c = p.Id,
      CASScopeKey__c = mapped ? InvPortfolioEngine.hash('scope') : null
    );
    insert as system a;
    f.account = a.Id;
    Inv_MarketInstruments__c fund = new Inv_MarketInstruments__c(
      MigrationKey__c = 'cas-test:f',
      Isin__c = 'SYNTHETIC',
      Name__c = 'Synthetic fund'
    );
    insert as system fund;
    f.fund = fund.Id;
    insert as system new Inv_MarketFundShareClasses__c(
      MigrationKey__c = 'cas-test:class',
      InstrumentRef__c = fund.Id
    );
    ContentVersion version = new ContentVersion(
      Title = 'Synthetic statement',
      PathOnClient = 'synthetic.pdf',
      VersionData = Blob.valueOf('%PDF-1.4 synthetic financial test')
    );
    insert as system version;
    f.version = version.Id;
    f.run = InvCASService.createRun(p.Id, version.Id);
    return f;
  }
  private static InvCASService.Payload payload(
    Integer purchases,
    String identity
  ) {
    InvCASService.Payload p = new InvCASService.Payload();
    p.contractVersion = 'cas-staging-1';
    p.fileHash = InvPortfolioEngine.hash(identity);
    p.parserVersion = 'casparser-1.4.1';
    p.issuer = 'CAMS';
    p.statementType = 'DETAILED';
    p.warnings = new List<String>();
    InvCASService.Scope s = new InvCASService.Scope();
    s.scopeKey = InvPortfolioEngine.hash('scope');
    s.isin = 'SYNTHETIC';
    s.periodStart = '2024-01-01';
    s.periodEnd = '2024-01-31';
    s.opening = '0';
    s.closing = String.valueOf(purchases * 10);
    s.warnings = new List<String>();
    s.transactions = new List<InvCASService.Trade>();
    for (Integer i = 1; i <= purchases; i++) {
      InvCASService.Trade t = new InvCASService.Trade();
      t.sequence = i;
      t.occurrence = i;
      t.tradeDate = '2024-01-02';
      t.kind = 'purchase';
      t.units = '10';
      t.amount = '100';
      t.cost = '100';
      t.nav = '10';
      t.balance = String.valueOf(i * 10);
      t.charges = new List<InvCASService.Charge>();
      s.transactions.add(t);
    }
    p.scopes = new List<InvCASService.Scope>{ s };
    return p;
  }
  private static Id summary(Id run) {
    return [
      SELECT Id
      FROM Inv_OpsImportRows__c
      WHERE RunRef__c = :run AND RowKind__c = 'Account'
    ]
    .Id;
  }
  private static Id another(Fixture f) {
    Inv_OpsImportRuns__c run = new Inv_OpsImportRuns__c(
      MigrationKey__c = 'cas-import:other',
      Portfolio__c = f.portfolio,
      ContentVersionId__c = String.valueOf(f.version),
      OperationalStatus__c = 'Uploaded'
    );
    insert as system run;
    return run.Id;
  }
  @IsTest
  static void identicalPurchasesPostOnceAndEvidenceDoesNotDuplicateLedger() {
    System.runAs(managerUser()) {
      Fixture f = fixture(true);
      InvCASService.Payload p = payload(2, 'first');
      InvCASService.stage(f.run, p);
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM Inv_OpsImportRows__c WHERE MatchStatus__c = 'New']
      );
      InvCASService.confirmAccount(summary(f.run));
      Assert.areEqual(2, [SELECT COUNT() FROM Inv_PortfolioEvents__c]);
      InvCASService.confirmAccount(summary(f.run));
      InvCASService.stage(f.run, p);
      Assert.areEqual(2, [SELECT COUNT() FROM Inv_PortfolioEvents__c]);
      Id other = another(f);
      p.fileHash = InvPortfolioEngine.hash('regenerated-statement');
      InvCASService.stage(other, p);
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Inv_OpsImportRows__c
          WHERE RunRef__c = :other AND MatchStatus__c = 'Existing'
        ]
      );
      InvCASService.confirmAccount(summary(other));
      Assert.areEqual(2, [SELECT COUNT() FROM Inv_PortfolioUnitEntries__c]);
      Assert.areEqual(
        'Complete',
        [
          SELECT OperationalStatus__c
          FROM Inv_OpsImportRuns__c
          WHERE Id = :other
        ]
        .OperationalStatus__c
      );
    }
  }
  @IsTest
  static void overlappingOccurrenceMismatchIsBlocked() {
    System.runAs(managerUser()) {
      Fixture f = fixture(true);
      InvCASService.stage(f.run, payload(1, 'first'));
      InvCASService.confirmAccount(summary(f.run));
      Id other = another(f);
      InvCASService.stage(other, payload(2, 'overlap'));
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Inv_OpsImportRows__c
          WHERE RunRef__c = :other AND MatchStatus__c = 'Possible Duplicate'
        ]
      );
      Boolean blocked = false;
      try {
        InvCASService.confirmAccount(summary(other));
      } catch (InvCASService.ImportException e) {
        blocked = true;
      }
      Assert.isTrue(blocked);
      Assert.areEqual(1, [SELECT COUNT() FROM Inv_PortfolioUnitEntries__c]);
    }
  }
  @IsTest
  static void changesAndBadOpeningBalancesAreNotOverwritten() {
    System.runAs(managerUser()) {
      Fixture f = fixture(true);
      InvCASService.stage(f.run, payload(1, 'first'));
      InvCASService.confirmAccount(summary(f.run));
      Id other = another(f);
      InvCASService.Payload p = payload(1, 'changed');
      p.scopes[0].transactions[0].amount = '101';
      p.scopes[0].transactions[0].cost = '101';
      InvCASService.stage(other, p);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Inv_OpsImportRows__c
          WHERE RunRef__c = :other AND MatchStatus__c = 'Conflict'
        ]
      );
      p.scopes[0].opening = '1';
      p.scopes[0].closing = '11';
      p.scopes[0].transactions[0].balance = '11';
      InvCASService.stage(other, p);
      Assert.areEqual(
        'Reconciliation Failure',
        [
          SELECT MatchStatus__c
          FROM Inv_OpsImportRows__c
          WHERE Id = :summary(other)
        ]
        .MatchStatus__c
      );
      Assert.areEqual(
        '100',
        [SELECT ConsiderationAmount__c FROM Inv_PortfolioUnitEntries__c LIMIT 1]
        .ConsiderationAmount__c
      );
    }
  }
  @IsTest
  static void mapScopeAndSameFileDetection() {
    System.runAs(managerUser()) {
      Fixture f = fixture(false);
      InvCASService.Payload p = payload(1, 'same-file');
      InvCASService.stage(f.run, p);
      Assert.areEqual(
        2,
        [
          SELECT COUNT()
          FROM Inv_OpsImportRows__c
          WHERE MatchStatus__c = 'Unmapped'
        ]
      );
      InvCASService.mapScope(summary(f.run), f.account);
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Inv_OpsImportRows__c WHERE MatchStatus__c = 'New']
      );
      Assert.areEqual(f.run, InvCASService.createRun(f.portfolio, f.version));
      Id other = another(f);
      InvCASService.stage(other, p);
      Assert.areEqual(
        'Duplicate',
        [
          SELECT OperationalStatus__c
          FROM Inv_OpsImportRuns__c
          WHERE Id = :other
        ]
        .OperationalStatus__c
      );
    }
  }
  @IsTest
  static void failedChargeRollsBackEntireAccount() {
    System.runAs(managerUser()) {
      Fixture f = fixture(true);
      InvCASService.Payload p = payload(1, 'bad-charge');
      InvCASService.Charge charge = new InvCASService.Charge();
      charge.kind = 'unsupported';
      charge.amount = '1';
      charge.sequence = 2;
      p.scopes[0].transactions[0].charges.add(charge);
      InvCASService.stage(f.run, p);
      Boolean blocked = false;
      try {
        InvCASService.confirmAccount(summary(f.run));
      } catch (InvCASService.ImportException e) {
        blocked = true;
      }
      Assert.isTrue(blocked);
      Assert.areEqual(0, [SELECT COUNT() FROM Inv_PortfolioEvents__c]);
      Assert.areEqual(0, [SELECT COUNT() FROM Inv_OpsSourceDocuments__c]);
    }
  }
  private class Admission implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      if (request.getEndpoint().endsWith('/passwords')) {
        Assert.isTrue(request.getBody().contains('ephemeral-secret'));
        response.setBody('{"passwordRef":"reference-only"}');
      } else {
        Assert.isFalse(request.getBody().contains('ephemeral-secret'));
        response.setBody('{"jobId":"synthetic-job"}');
      }
      return response;
    }
  }
  @IsTest
  static void controlledUploadAndPasswordAdmission() {
    System.runAs(managerUser()) {
      Fixture f = fixture(true);
      Id doc = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :f.version
      ]
      .ContentDocumentId;
      InvImportActions.Request input = new InvImportActions.Request();
      input.operation = 'create';
      input.portfolioId = f.portfolio;
      input.documentIds = new List<String>{ String.valueOf(doc) };
      Assert.areEqual(
        f.run,
        InvImportActions.manage(new List<InvImportActions.Request>{ input })[0]
          .runId
      );
      Test.setMock(HttpCalloutMock.class, new Admission());
      Test.startTest();
      Assert.areEqual(
        'Queued',
        InvImportActions.submit(f.run, 'ephemeral-secret')
      );
      Assert.areEqual('Queued', InvImportActions.submit(f.run, null));
      Test.stopTest();
      RestContext.request = new RestRequest();
      RestContext.response = new RestResponse();
      RestContext.request.requestBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{
            'operation' => 'failed',
            'runId' => f.run,
            'errorType' => 'SyntheticFailure'
          }
        )
      );
      InvImportEndpoint.receive();
      Assert.areEqual(200, RestContext.response.statusCode);
      RestContext.request.requestBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{
            'operation' => 'stage',
            'runId' => f.run,
            'payload' => payload(1, 'endpoint')
          }
        )
      );
      InvImportEndpoint.receive();
      Assert.areEqual(200, RestContext.response.statusCode);
      RestContext.request.requestBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{ 'operation' => 'unknown', 'runId' => f.run }
        )
      );
      InvImportEndpoint.receive();
      Assert.areEqual(400, RestContext.response.statusCode);
      System.runAs(unprivilegedUser()) {
        InvImportEndpoint.receive();
        Assert.areEqual(403, RestContext.response.statusCode);
      }
    }
  }
}
