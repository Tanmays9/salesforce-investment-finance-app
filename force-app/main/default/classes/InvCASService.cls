public without sharing class InvCASService {
  public class ImportException extends Exception {
  }
  public class Payload {
    public String contractVersion,
      fileHash,
      parserVersion,
      issuer,
      statementType;
    public List<String> warnings;
    public List<Scope> scopes;
  }
  public class Scope {
    public String scopeKey,
      isin,
      schemeName,
      periodStart,
      periodEnd,
      opening,
      closing;
    public List<String> warnings;
    public List<Trade> transactions;
  }
  public class Trade {
    public Integer sequence, occurrence;
    public String tradeDate, kind, units, amount, cost, nav, balance;
    public List<Charge> charges;
  }
  public class Charge {
    public String kind, amount;
    public Integer sequence;
  }
  public static void requireManager() {
    if (!FeatureManagement.checkPermission('Inv_ManagePortfolio'))
      throw new ImportException('Portfolio Manager permission required');
  }
  public static String canonical(String value) {
    if (value == null)
      return '';
    String numericText = String.valueOf(InvMath.exact(value));
    if (numericText.contains('.'))
      numericText = numericText.replaceAll('0+$', '').replaceAll('\\.$', '');
    return numericText == '-0' ? '0' : numericText;
  }
  public static String economicKey(
    Id account,
    Id fund,
    Date day,
    String kind,
    String units,
    String amount
  ) {
    // Parser row numbers are excluded so overlapping statements identify the same ledger movement.
    return InvPortfolioEngine.hash(
      account +
        '|' +
        fund +
        '|' +
        String.valueOf(day) +
        '|' +
        kind +
        '|' +
        canonical(units) +
        '|' +
        canonical(amount)
    );
  }
  public static Id createRun(Id portfolio, Id fileVersion) {
    requireManager();
    List<Inv_PortfolioPortfolios__c> visible = [
      SELECT Id
      FROM Inv_PortfolioPortfolios__c
      WHERE Id = :portfolio
      WITH USER_MODE
    ];
    if (visible.isEmpty())
      throw new ImportException('Portfolio is not accessible');
    ContentVersion file = [
      SELECT Id, ContentDocumentId, FileType, ContentSize
      FROM ContentVersion
      WHERE Id = :fileVersion
      WITH USER_MODE
    ];
    if (file.FileType != 'PDF' || file.ContentSize > 15000000)
      throw new ImportException('Upload a CAS PDF of at most 15 MB');
    String key = 'cas-import:' + fileVersion;
    List<Inv_OpsImportRuns__c> prior = [
      SELECT Id
      FROM Inv_OpsImportRuns__c
      WHERE MigrationKey__c = :key
      WITH SYSTEM_MODE
    ];
    if (!prior.isEmpty())
      return prior[0].Id;
    Inv_OpsImportRuns__c run = new Inv_OpsImportRuns__c(
      MigrationKey__c = key,
      Portfolio__c = portfolio,
      ContentVersionId__c = String.valueOf(fileVersion),
      OperationalStatus__c = 'Uploaded',
      Status__c = 'staged',
      ParserVersion__c = 'casparser-1.4.1',
      CASParserVersion__c = 'casparser-1.4.1'
    );
    insert as system run;
    insert as system new ContentDocumentLink(
      ContentDocumentId = file.ContentDocumentId,
      LinkedEntityId = run.Id,
      ShareType = 'V'
    );
    return run.Id;
  }
  public static void stage(Id runId, Payload payload) {
    if (!FeatureManagement.checkPermission('Inv_ParseStatements'))
      throw new ImportException('Dedicated parser permission required');
    if (
      payload.contractVersion != 'cas-staging-1' ||
      payload.fileHash == null ||
      !Pattern.matches('[a-f0-9]{64}', payload.fileHash) ||
      !new Set<String>{ 'CAMS', 'KFINTECH' }.contains(payload.issuer)
    )
      throw new ImportException('Invalid staging contract, issuer or SHA-256');
    Inv_OpsImportRuns__c run = [
      SELECT
        Id,
        MigrationKey__c,
        Portfolio__c,
        OperationalStatus__c,
        FileHash__c
      FROM Inv_OpsImportRuns__c
      WHERE Id = :runId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (!run.MigrationKey__c.startsWith('cas-import:'))
      throw new ImportException(
        'Historical migration evidence cannot be restaged'
      );
    if (run.OperationalStatus__c == 'Complete')
      return;
    // A byte-identical statement is the same import even if a retry created another run.
    List<Inv_OpsImportRuns__c> duplicates = [
      SELECT Id, OperationalStatus__c
      FROM Inv_OpsImportRuns__c
      WHERE FileHash__c = :payload.fileHash AND Id != :runId
      WITH SYSTEM_MODE
    ];
    if (!duplicates.isEmpty()) {
      run.OperationalStatus__c = 'Duplicate';
      run.DuplicateOf__c = duplicates[0].Id;
      update as system run;
      return;
    }
    Inv_OpsProviders__c provider = new Inv_OpsProviders__c(
      MigrationKey__c = 'cas-provider:' + payload.issuer,
      Name__c = payload.issuer + ' CAS',
      Kind__c = 'issuer_statement'
    );
    upsert as system provider MigrationKey__c;
    run.ProviderRef__c = provider.Id;
    run.FileHash__c = payload.fileHash;
    run.ParserVersion__c = payload.parserVersion;
    run.CASParserVersion__c = payload.parserVersion;
    run.SourceJson__c = JSON.serialize(
      new Map<String, Object>{
        'issuer' => payload.issuer,
        'statementType' => payload.statementType,
        'contractVersion' => payload.contractVersion,
        'sha256' => payload.fileHash
      }
    );
    Map<String, Id> fundByISIN = new Map<String, Id>();
    Set<String> ambiguous = new Set<String>();
    for (Inv_MarketFundShareClasses__c c : [
      SELECT InstrumentRef__c, InstrumentRef__r.Isin__c
      FROM Inv_MarketFundShareClasses__c
      WITH SYSTEM_MODE
    ]) {
      String isin = c.InstrumentRef__r.Isin__c;
      if (String.isBlank(isin))
        continue;
      if (
        fundByISIN.containsKey(isin) &&
        fundByISIN.get(isin) != c.InstrumentRef__c
      )
        ambiguous.add(isin);
      else
        fundByISIN.put(isin, c.InstrumentRef__c);
    }
    Map<String, Id> accountByScope = new Map<String, Id>();
    for (Inv_PortfolioAccounts__c a : [
      SELECT Id, CASScopeKey__c
      FROM Inv_PortfolioAccounts__c
      WHERE PortfolioRef__c = :run.Portfolio__c AND CASScopeKey__c != NULL
      WITH SYSTEM_MODE
    ])
      accountByScope.put(a.CASScopeKey__c, a.Id);
    List<Inv_OpsImportRows__c> rows = new List<Inv_OpsImportRows__c>();
    Integer count = 0;
    if (payload.scopes == null || payload.scopes.isEmpty())
      throw new ImportException('No account scopes');
    for (Scope scope : payload.scopes) {
      if (!Pattern.matches('[a-f0-9]{64}', scope.scopeKey))
        throw new ImportException('Invalid account-scope identity');
      Date start = Date.valueOf(scope.periodStart),
        endDate = Date.valueOf(scope.periodEnd);
      if (start > endDate || endDate > Date.today())
        throw new ImportException('Invalid statement date range');
      Id account = accountByScope.get(scope.scopeKey),
        fund = ambiguous.contains(scope.isin)
          ? null
          : fundByISIN.get(scope.isin);
      Boolean bad =
        scope.warnings != null && !scope.warnings.isEmpty() ||
        payload.warnings != null && !payload.warnings.isEmpty();
      Decimal running = InvMath.exact(scope.opening);
      Inv_OpsImportRows__c summary = new Inv_OpsImportRows__c(
        MigrationKey__c = 'cas:' + runId + ':' + scope.scopeKey + ':account',
        RowIdentity__c = runId + ':' + scope.scopeKey + ':account',
        RunRef__c = runId,
        ScopeKey__c = scope.scopeKey,
        RowKind__c = 'Account',
        Account__c = account,
        Fund__c = fund,
        ISIN__c = scope.isin,
        PeriodStart__c = start,
        PeriodEnd__c = endDate,
        OpeningUnits__c = scope.opening,
        ClosingUnits__c = scope.closing,
        RawPayload__c = JSON.serialize(
          new Map<String, Object>{
            'warnings' => scope.warnings,
            'schemeName' => scope.schemeName
          }
        ),
        MatchStatus__c = account == null || fund == null ? 'Unmapped' : 'Mapped'
      );
      rows.add(summary);
      if (scope.transactions == null)
        throw new ImportException('Missing transaction array');
      for (Trade trade : scope.transactions) {
        if (++count > 1000)
          throw new ImportException(
            'Statement exceeds 1000 unit movements; split issuer statements into smaller periods'
          );
        Date day = Date.valueOf(trade.tradeDate);
        Decimal units = InvMath.exact(trade.units),
          amount = InvMath.exact(trade.amount);
        if (
          day < start ||
          day > endDate ||
          units == null ||
          amount == null ||
          amount < 0 ||
          !new Set<String>{ 'purchase', 'redemption' }.contains(trade.kind) ||
          (trade.kind == 'purchase') != (units > 0)
        )
          throw new ImportException(
            'Invalid transaction identity or financial values'
          );
        if (running != null) {
          running += units;
          if (trade.balance != null && running != InvMath.exact(trade.balance))
            bad = true;
        }
        rows.add(
          new Inv_OpsImportRows__c(
            MigrationKey__c = 'cas:' +
              InvPortfolioEngine.hash(
                runId + ':' + scope.scopeKey + ':' + trade.sequence
              ),
            RowIdentity__c = runId +
              ':' +
              scope.scopeKey +
              ':' +
              trade.sequence,
            RunRef__c = runId,
            ScopeKey__c = scope.scopeKey,
            RowKind__c = 'Transaction',
            Account__c = account,
            Fund__c = fund,
            ISIN__c = scope.isin,
            TradeDate__c = day,
            TransactionType__c = trade.kind,
            Units__c = trade.units,
            Amount__c = trade.amount,
            Cost__c = trade.cost,
            NAV__c = trade.nav,
            Occurrence__c = trade.occurrence,
            RawPayload__c = JSON.serialize(trade),
            MatchStatus__c = account == null ||
              fund == null
              ? 'Unmapped'
              : 'Pending'
          )
        );
      }
      if (
        running == null ||
        scope.closing == null ||
        running != InvMath.exact(scope.closing)
      )
        bad = true;
      if (bad)
        summary.MatchStatus__c = 'Reconciliation Failure';
    }
    upsert as system rows RowIdentity__c;
    classify(runId, null);
    run.OperationalStatus__c = 'Needs Review';
    run.RowsSeen__c = String.valueOf(count);
    update as system run;
  }
  public static void mapScope(Id summaryId, Id accountId) {
    requireManager();
    Inv_OpsImportRows__c summary = [
      SELECT Id, RunRef__c, ScopeKey__c, Fund__c, MatchStatus__c
      FROM Inv_OpsImportRows__c
      WHERE Id = :summaryId AND RowKind__c = 'Account'
      WITH SYSTEM_MODE
    ];
    Inv_OpsImportRuns__c run = [
      SELECT Portfolio__c, OperationalStatus__c
      FROM Inv_OpsImportRuns__c
      WHERE Id = :summary.RunRef__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    List<Inv_PortfolioPortfolios__c> visible = [
      SELECT Id
      FROM Inv_PortfolioPortfolios__c
      WHERE Id = :run.Portfolio__c
      WITH USER_MODE
    ];
    if (visible.isEmpty())
      throw new ImportException('Portfolio is not accessible');
    if (
      run.OperationalStatus__c == 'Complete' ||
      summary.MatchStatus__c == 'Confirmed'
    )
      throw new ImportException('Confirmed imports cannot be remapped');
    Inv_PortfolioAccounts__c account = [
      SELECT Id, PortfolioRef__c, CASScopeKey__c
      FROM Inv_PortfolioAccounts__c
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (account.PortfolioRef__c != run.Portfolio__c || summary.Fund__c == null)
      throw new ImportException(
        'Account must belong to the destination portfolio and share class must be known'
      );
    if (
      account.CASScopeKey__c != null &&
      account.CASScopeKey__c != summary.ScopeKey__c
    )
      throw new ImportException(
        'Account already has a different verified CAS scope'
      );
    if (summary.MatchStatus__c == 'Reconciliation Failure')
      throw new ImportException(
        'Resolve source reconciliation errors before mapping'
      );
    account.CASScopeKey__c = summary.ScopeKey__c;
    update as system account;
    List<Inv_OpsImportRows__c> rows = [
      SELECT Id, Account__c, MatchStatus__c, RowKind__c
      FROM Inv_OpsImportRows__c
      WHERE
        RunRef__c = :summary.RunRef__c
        AND ScopeKey__c = :summary.ScopeKey__c
      WITH SYSTEM_MODE
    ];
    for (Inv_OpsImportRows__c row : rows) {
      row.Account__c = accountId;
      row.MatchStatus__c = row.RowKind__c == 'Account' ? 'Mapped' : 'Pending';
    }
    update as system rows;
    classify(summary.RunRef__c, summary.ScopeKey__c);
  }
  @TestVisible
  private static void classify(Id runId, String onlyScope) {
    List<Inv_OpsImportRows__c> rows = [
      SELECT
        Id,
        RowKind__c,
        Account__c,
        Fund__c,
        ScopeKey__c,
        MatchStatus__c,
        TradeDate__c,
        TransactionType__c,
        Units__c,
        Amount__c,
        MatchKey__c,
        MatchedEvent__c,
        Occurrence__c,
        OpeningUnits__c,
        PeriodStart__c,
        Cost__c,
        NAV__c
      FROM Inv_OpsImportRows__c
      WHERE RunRef__c = :runId
      WITH SYSTEM_MODE
      ORDER BY RowIdentity__c
    ];
    Set<Id> accounts = new Set<Id>();
    for (Inv_OpsImportRows__c row : rows)
      if (row.Account__c != null)
        accounts.add(row.Account__c);
    Map<String, List<Id>> existing = new Map<String, List<Id>>();
    Map<String, Set<String>> rough = new Map<String, Set<String>>();
    Map<Id, Inv_PortfolioUnitEntries__c> details = new Map<Id, Inv_PortfolioUnitEntries__c>();
    Set<Id> reversed = new Set<Id>();
    for (Inv_PortfolioEvents__c e : [
      SELECT ReversesRef__c
      FROM Inv_PortfolioEvents__c
      WHERE ReversesRef__c != NULL AND PostedAt__c != NULL
      WITH SYSTEM_MODE
    ])
      reversed.add(e.ReversesRef__c);
    List<Inv_PortfolioUnitEntries__c> ledger = [
      SELECT
        AccountRef__c,
        InstrumentRef__c,
        EventRef__c,
        EventRef__r.EventDate__c,
        EventRef__r.EventType__c,
        UnitsDelta__c,
        ConsiderationAmount__c,
        AcquisitionCost__c,
        SourceNav__c
      FROM Inv_PortfolioUnitEntries__c
      WHERE AccountRef__c IN :accounts AND EventRef__r.PostedAt__c != NULL
      WITH SYSTEM_MODE
      ORDER BY
        EventRef__r.EventDate__c,
        EventRef__r.SourceSequenceNumber__c,
        EventRef__c,
        Id
    ];
    List<Inv_PortfolioUnitEntries__c> valid = new List<Inv_PortfolioUnitEntries__c>();
    for (Inv_PortfolioUnitEntries__c entry : ledger) {
      if (
        reversed.contains(entry.EventRef__c) ||
        entry.EventRef__r.EventType__c == 'reversal'
      )
        continue;
      valid.add(entry);
      details.put(entry.EventRef__c, entry);
      String key = economicKey(
        entry.AccountRef__c,
        entry.InstrumentRef__c,
        entry.EventRef__r.EventDate__c,
        entry.EventRef__r.EventType__c,
        entry.UnitsDelta__c,
        entry.ConsiderationAmount__c
      );
      if (!existing.containsKey(key))
        existing.put(key, new List<Id>());
      existing.get(key).add(entry.EventRef__c);
      String prefix =
        entry.AccountRef__c +
        '|' +
        entry.InstrumentRef__c +
        '|' +
        entry.EventRef__r.EventDate__c +
        '|' +
        entry.EventRef__r.EventType__c +
        '|' +
        canonical(entry.UnitsDelta__c);
      if (!rough.containsKey(prefix))
        rough.put(prefix, new Set<String>());
      rough.get(prefix).add(key);
    }
    Map<String, Integer> incoming = new Map<String, Integer>();
    for (Inv_OpsImportRows__c row : rows)
      if (
        row.RowKind__c == 'Transaction' &&
        row.Account__c != null &&
        row.Fund__c != null
      ) {
        row.MatchKey__c = economicKey(
          row.Account__c,
          row.Fund__c,
          row.TradeDate__c,
          row.TransactionType__c,
          row.Units__c,
          row.Amount__c
        );
        incoming.put(
          row.MatchKey__c,
          (incoming.containsKey(row.MatchKey__c)
            ? incoming.get(row.MatchKey__c)
            : 0) + 1
        );
      }
    List<Inv_OpsImportRows__c> changed = new List<Inv_OpsImportRows__c>();
    Map<String, Integer> used = new Map<String, Integer>();
    for (Inv_OpsImportRows__c row : rows) {
      if (
        onlyScope != null && row.ScopeKey__c != onlyScope ||
        row.MatchStatus__c == 'Confirmed'
      )
        continue;
      if (
        row.RowKind__c == 'Account' &&
        row.MatchStatus__c == 'Reconciliation Failure'
      )
        continue;
      if (row.Account__c == null || row.Fund__c == null) {
        row.MatchStatus__c = 'Unmapped';
        changed.add(row);
        continue;
      }
      if (row.RowKind__c == 'Account') {
        if (row.MatchStatus__c != 'Reconciliation Failure') {
          Decimal opening = 0;
          for (Inv_PortfolioUnitEntries__c entry : valid)
            if (
              entry.AccountRef__c == row.Account__c &&
              entry.InstrumentRef__c == row.Fund__c &&
              entry.EventRef__r.EventDate__c < row.PeriodStart__c
            )
              opening += InvMath.exact(entry.UnitsDelta__c);
          row.MatchStatus__c = row.OpeningUnits__c != null &&
            opening == InvMath.exact(row.OpeningUnits__c)
            ? 'Mapped'
            : 'Reconciliation Failure';
        }
      } else {
        row.MatchedEvent__c = null;
        String key = row.MatchKey__c;
        Integer n = existing.containsKey(key) ? existing.get(key).size() : 0;
        if (n > 0 && n != incoming.get(key))
          row.MatchStatus__c = 'Possible Duplicate';
        else if (n > 0) {
          Integer index = used.containsKey(key) ? used.get(key) : 0;
          row.MatchedEvent__c = existing.get(key)[index];
          used.put(key, index + 1);
          row.MatchStatus__c = 'Existing';
          Inv_PortfolioUnitEntries__c old = details.get(row.MatchedEvent__c);
          if (
            canonical(old.AcquisitionCost__c) != canonical(row.Cost__c) ||
            old.SourceNav__c != null && row.NAV__c != null &&
            canonical(old.SourceNav__c) != canonical(row.NAV__c)
          )
            row.MatchStatus__c = 'Conflict';
        } else {
          String prefix =
            row.Account__c +
            '|' +
            row.Fund__c +
            '|' +
            row.TradeDate__c +
            '|' +
            row.TransactionType__c +
            '|' +
            canonical(row.Units__c);
          row.MatchStatus__c = rough.containsKey(prefix) ? 'Conflict' : 'New';
        }
      }
      changed.add(row);
    }
    if (!changed.isEmpty())
      update as system changed;
  }
  public static void confirmAccount(Id summaryId) {
    requireManager();
    Inv_OpsImportRows__c summary = [
      SELECT
        Id,
        RunRef__c,
        ScopeKey__c,
        Account__c,
        Fund__c,
        MatchStatus__c,
        PeriodEnd__c,
        ClosingUnits__c
      FROM Inv_OpsImportRows__c
      WHERE Id = :summaryId AND RowKind__c = 'Account'
      WITH SYSTEM_MODE
    ];
    // Row locks serialize overlapping confirmations for this import and destination account.
    Inv_OpsImportRuns__c run = [
      SELECT
        Id,
        MigrationKey__c,
        FileHash__c,
        ContentVersionId__c,
        Portfolio__c,
        OperationalStatus__c,
        ProviderRef__c
      FROM Inv_OpsImportRuns__c
      WHERE Id = :summary.RunRef__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (!run.MigrationKey__c.startsWith('cas-import:'))
      throw new ImportException(
        'Historical migration evidence cannot be posted'
      );
    if (summary.MatchStatus__c == 'Confirmed')
      return;
    if (run.OperationalStatus__c == 'Duplicate' || summary.Account__c == null)
      throw new ImportException(
        'Map and reconcile this account before confirmation'
      );
    Inv_PortfolioAccounts__c account = [
      SELECT Id, PortfolioRef__c
      FROM Inv_PortfolioAccounts__c
      WHERE Id = :summary.Account__c
      WITH SYSTEM_MODE
      FOR UPDATE
    ];
    if (account.PortfolioRef__c != run.Portfolio__c)
      throw new ImportException('Destination portfolio mismatch');
    List<Inv_PortfolioPortfolios__c> visible = [
      SELECT Id
      FROM Inv_PortfolioPortfolios__c
      WHERE Id = :run.Portfolio__c
      WITH USER_MODE
    ];
    if (visible.isEmpty())
      throw new ImportException('Portfolio is not accessible');
    // Keep each account atomic: a failed check must not leave a partially posted ledger.
    Savepoint checkpoint = Database.setSavepoint();
    try {
      classify(run.Id, summary.ScopeKey__c);
      summary = [
        SELECT
          Id,
          ScopeKey__c,
          Fund__c,
          MatchStatus__c,
          PeriodEnd__c,
          ClosingUnits__c
        FROM Inv_OpsImportRows__c
        WHERE Id = :summaryId
        WITH SYSTEM_MODE
      ];
      if (summary.MatchStatus__c != 'Mapped')
        throw new ImportException(
          'Account opening units or source movements do not reconcile'
        );
      List<Inv_OpsImportRows__c> rows = [
        SELECT
          Id,
          Account__c,
          Fund__c,
          TradeDate__c,
          TransactionType__c,
          Units__c,
          Amount__c,
          Cost__c,
          NAV__c,
          Occurrence__c,
          MatchStatus__c,
          MatchKey__c,
          RawPayload__c,
          MatchedEvent__c,
          PostingKey__c
        FROM Inv_OpsImportRows__c
        WHERE
          RunRef__c = :run.Id
          AND ScopeKey__c = :summary.ScopeKey__c
          AND RowKind__c = 'Transaction'
        WITH SYSTEM_MODE
        ORDER BY TradeDate__c, Occurrence__c, RowIdentity__c
      ];
      Decimal expected = 0;
      Set<Id> reversed = new Set<Id>();
      for (Inv_PortfolioEvents__c e : [
        SELECT ReversesRef__c
        FROM Inv_PortfolioEvents__c
        WHERE ReversesRef__c != NULL AND PostedAt__c != NULL
        WITH SYSTEM_MODE
      ])
        reversed.add(e.ReversesRef__c);
      for (Inv_PortfolioUnitEntries__c u : [
        SELECT UnitsDelta__c, EventRef__c, EventRef__r.EventType__c
        FROM Inv_PortfolioUnitEntries__c
        WHERE
          AccountRef__c = :account.Id
          AND InstrumentRef__c = :summary.Fund__c
          AND EventRef__r.EventDate__c <= :summary.PeriodEnd__c
          AND EventRef__r.PostedAt__c != NULL
        WITH SYSTEM_MODE
      ])
        if (
          !reversed.contains(u.EventRef__c) &&
          u.EventRef__r.EventType__c != 'reversal'
        )
          expected += InvMath.exact(u.UnitsDelta__c);
      for (Inv_OpsImportRows__c row : rows) {
        if (row.MatchStatus__c != 'New' && row.MatchStatus__c != 'Existing')
          throw new ImportException(
            'Resolve possible duplicates, conflicts and mappings before posting'
          );
        if (row.MatchStatus__c == 'New')
          expected += InvMath.exact(row.Units__c);
      }
      if (expected != InvMath.exact(summary.ClosingUnits__c))
        throw new ImportException(
          'Projected ledger units do not equal statement closing units'
        );
      Inv_OpsSourceDocuments__c document;
      for (Inv_OpsSourceDocuments__c existing : [
        SELECT Id, Sha256__c
        FROM Inv_OpsSourceDocuments__c
        WITH SYSTEM_MODE
      ])
        if (existing.Sha256__c == run.FileHash__c) {
          document = existing;
          break;
        }
      if (document == null) {
        document = new Inv_OpsSourceDocuments__c(
          MigrationKey__c = 'cas-document:' + run.FileHash__c,
          Sha256__c = run.FileHash__c,
          ProviderRef__c = run.ProviderRef__c,
          MediaType__c = 'application/pdf',
          SourceJson__c = JSON.serialize(
            new Map<String, Object>{
              'contentVersionId' => run.ContentVersionId__c,
              'sha256' => run.FileHash__c
            }
          )
        );
        insert as system document;
      }
      ContentVersion file = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :run.ContentVersionId__c
        WITH SYSTEM_MODE
      ];
      if (
        [
          SELECT COUNT()
          FROM ContentDocumentLink
          WHERE
            ContentDocumentId = :file.ContentDocumentId
            AND LinkedEntityId = :document.Id
          WITH SYSTEM_MODE
        ] == 0
      )
        insert as system new ContentDocumentLink(
          ContentDocumentId = file.ContentDocumentId,
          LinkedEntityId = document.Id,
          ShareType = 'V'
        );
      List<Inv_PortfolioEvents__c> events = new List<Inv_PortfolioEvents__c>();
      List<Inv_OpsImportRows__c> fresh = new List<Inv_OpsImportRows__c>();
      for (Inv_OpsImportRows__c row : rows)
        if (row.MatchStatus__c == 'New') {
          String posting =
            row.MatchKey__c +
            ':' +
            String.valueOf(row.Occurrence__c);
          Trade trade = (Trade) JSON.deserialize(
            row.RawPayload__c,
            Trade.class
          );
          events.add(
            new Inv_PortfolioEvents__c(
              MigrationKey__c = 'cas-event:' + InvPortfolioEngine.hash(posting),
              PostingKey__c = posting,
              EconomicKey__c = row.MatchKey__c,
              EventDate__c = row.TradeDate__c,
              EventType__c = row.TransactionType__c,
              SourceSequence__c = String.valueOf(trade.sequence),
              SourceSequenceNumber__c = trade.sequence,
              DocumentRef__c = document.Id,
              ProviderRef__c = run.ProviderRef__c,
              SubjectInstrumentRef__c = row.Fund__c,
              ProviderEventId__c = run.FileHash__c + ':' + trade.sequence
            )
          );
          fresh.add(row);
        }
      if (!events.isEmpty())
        insert as system events;
      List<Inv_PortfolioUnitEntries__c> entries = new List<Inv_PortfolioUnitEntries__c>();
      List<Inv_PortfolioEventCharges__c> charges = new List<Inv_PortfolioEventCharges__c>();
      for (Integer i = 0; i < fresh.size(); i++) {
        Inv_OpsImportRows__c row = fresh[i];
        Inv_PortfolioEvents__c event = events[i];
        Trade trade = (Trade) JSON.deserialize(row.RawPayload__c, Trade.class);
        entries.add(
          new Inv_PortfolioUnitEntries__c(
            MigrationKey__c = 'cas-unit:' +
              InvPortfolioEngine.hash(event.PostingKey__c),
            EventRef__c = event.Id,
            AccountRef__c = account.Id,
            InstrumentRef__c = row.Fund__c,
            UnitsDelta__c = row.Units__c,
            ConsiderationAmount__c = row.Amount__c,
            AcquisitionCost__c = row.Cost__c,
            AcquisitionDate__c = row.TransactionType__c == 'purchase'
              ? row.TradeDate__c
              : null,
            SourceNav__c = row.NAV__c,
            Currency__c = 'INR',
            ConsiderationBasis__c = row.TransactionType__c == 'purchase'
              ? 'gross'
              : 'reported_net'
          )
        );
        if (trade.charges != null)
          for (Charge charge : trade.charges) {
            if (
              !new Set<String>{ 'stamp_duty', 'stt' }.contains(charge.kind) ||
              InvMath.exact(charge.amount) < 0
            )
              throw new ImportException('Unsupported charge');
            charges.add(
              new Inv_PortfolioEventCharges__c(
                MigrationKey__c = 'cas-charge:' +
                  InvPortfolioEngine.hash(
                    event.PostingKey__c + ':' + charge.sequence
                  ),
                EventRef__c = event.Id,
                ChargeKind__c = charge.kind,
                Amount__c = charge.amount,
                Currency__c = 'INR',
                IncludedInBasis__c = charge.kind == 'stamp_duty',
                IncludedInNetCash__c = charge.kind == 'stt'
              )
            );
          }
        row.MatchedEvent__c = event.Id;
        row.MatchStatus__c = 'Existing';
        row.PostingKey__c = event.PostingKey__c;
        event.PostedAt__c = System.now();
      }
      for (Inv_PortfolioUnitEntries__c entry : entries) {
        InvMath.project(entry, 'UnitsDelta__c', entry.UnitsDelta__c);
        InvMath.project(
          entry,
          'ConsiderationAmount__c',
          entry.ConsiderationAmount__c
        );
        InvMath.project(entry, 'AcquisitionCost__c', entry.AcquisitionCost__c);
        InvMath.project(entry, 'SourceNav__c', entry.SourceNav__c);
      }
      for (Inv_PortfolioEventCharges__c charge : charges)
        InvMath.project(charge, 'Amount__c', charge.Amount__c);
      if (!entries.isEmpty())
        insert as system entries;
      if (!charges.isEmpty())
        insert as system charges;
      if (!events.isEmpty())
        update as system events;
      if (!fresh.isEmpty())
        update as system fresh;
      Inv_PortfolioPositionSnapshots__c closing = new Inv_PortfolioPositionSnapshots__c(
        MigrationKey__c = 'cas-closing:' + run.FileHash__c + ':' + account.Id,
        AccountRef__c = account.Id,
        InstrumentRef__c = summary.Fund__c,
        AsOf__c = summary.PeriodEnd__c,
        ReportedUnits__c = summary.ClosingUnits__c,
        DocumentRef__c = document.Id
      );
      upsert as system closing MigrationKey__c;
      summary.MatchStatus__c = 'Confirmed';
      update as system summary;
      Integer pending = [
        SELECT COUNT()
        FROM Inv_OpsImportRows__c
        WHERE
          RunRef__c = :run.Id
          AND RowKind__c = 'Account'
          AND MatchStatus__c != 'Confirmed'
        WITH SYSTEM_MODE
      ];
      run.OperationalStatus__c = pending == 0
        ? 'Complete'
        : 'Partially Confirmed';
      if (pending == 0) {
        run.Status__c = 'complete';
        run.CompletedAt__c = System.now();
      }
      update as system run;
      if (pending == 0 || !events.isEmpty())
        System.enqueueJob(new InvRecalculate(new List<Id>{ run.Portfolio__c }));
    } catch (Exception e) {
      Database.rollback(checkpoint);
      throw new ImportException(e.getMessage());
    }
  }
}
