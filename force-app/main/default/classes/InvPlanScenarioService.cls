/** Generates editable plan drafts from explicit review constraints. */
public with sharing class InvPlanScenarioService {
  public class TargetAllocation {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public Decimal weightPercent;
  }
  public class ScenarioInput {
    @AuraEnabled
    public Id portfolioId;
    @AuraEnabled
    public Decimal monthlyBudget;
    @AuraEnabled
    public Decimal cashNeed;
    @AuraEnabled
    public Integer cashHoldDays;
    @AuraEnabled
    public Integer maximumFundCount;
    @AuraEnabled
    public List<Id> retainedFundIds;
    @AuraEnabled
    public List<Id> exitCandidateFundIds;
    @AuraEnabled
    public List<Id> excludedNewPurchaseFundIds;
    @AuraEnabled
    public List<TargetAllocation> targetAllocations;
    @AuraEnabled
    public String objective;
  }
  public class Alternative {
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
  }
  public class ScenarioResult {
    @AuraEnabled
    public Id planId;
    @AuraEnabled
    public Id baselineRunId;
    @AuraEnabled
    public Date baselineDate;
    @AuraEnabled
    public String baselineFingerprint;
    @AuraEnabled
    public List<Alternative> alternatives = new List<Alternative>();
  }
  public class ImpactRow {
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String metric;
    @AuraEnabled
    public String dimension;
    @AuraEnabled
    public String member;
    @AuraEnabled
    public Decimal baseline;
    @AuraEnabled
    public Decimal proposed;
    @AuraEnabled
    public String coverage;
    @AuraEnabled
    public String notes;
  }
  public class ComparisonResult {
    @AuraEnabled
    public Id baselineRunId;
    @AuraEnabled
    public Date baselineDate;
    @AuraEnabled
    public String baselineFingerprint;
    @AuraEnabled
    public List<Alternative> alternatives = new List<Alternative>();
    @AuraEnabled
    public List<ImpactRow> impacts = new List<ImpactRow>();
  }
  public class RedemptionAction {
    @AuraEnabled
    public Id actionId;
    @AuraEnabled
    public Id versionId;
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Decimal units;
    @AuraEnabled
    public Boolean allAvailable;
  }
  private class Baseline {
    Id portfolioId;
    Id runId;
    Date valuationDate;
    String fingerprint;
    Boolean complete = true;
    Decimal value = 0;
    Map<Id, Decimal> values = new Map<Id, Decimal>();
    Map<Id, Decimal> units = new Map<Id, Decimal>();
    Map<Id, Decimal> navs = new Map<Id, Decimal>();
    Map<Id, Decimal> sips = new Map<Id, Decimal>();
  }
  private class DraftSpec {
    String label;
    String rationale;
    String unmetConstraints;
    List<Inv_PlanningActions__c> actions = new List<Inv_PlanningActions__c>();
    List<Inv_PlanningTargets__c> targets = new List<Inv_PlanningTargets__c>();
    String constraints;
  }
  public class ScenarioException extends Exception {
  }

  @AuraEnabled
  public static ScenarioResult createAlternatives(ScenarioInput input) {
    requireManager();
    validateInput(input);
    Savepoint point = Database.setSavepoint();
    try {
      Baseline baseline = loadBaseline(input.portfolioId);
      if (
        baseline.runId == null ||
        baseline.value == null ||
        baseline.value <= 0 ||
        !baseline.complete ||
        String.isBlank(baseline.fingerprint)
      )
        throw new ScenarioException(
          'A complete, valued portfolio baseline is required before planning.'
        );
      List<DraftSpec> specs = buildSpecs(input, baseline);
      String identity = InvPortfolioEngine.hash(
        String.valueOf(input.portfolioId) +
          baseline.fingerprint +
          String.valueOf(System.now()) +
          String.valueOf(Crypto.getRandomLong())
      );
      Inv_PlanningPlans__c parent = new Inv_PlanningPlans__c(
        MigrationKey__c = 'scenario-plan:' + identity,
        PortfolioRef__c = input.portfolioId,
        Name__c = 'Portfolio review ' + String.valueOf(Date.today()),
        Goal__c = String.isBlank(input.objective)
          ? 'Compare consolidation and redemption alternatives'
          : input.objective,
        CreatedAt__c = System.now()
      );
      insert as system parent;
      List<Inv_PlanningPlanVersions__c> versions = new List<Inv_PlanningPlanVersions__c>();
      for (Integer i = 0; i < specs.size(); i++) {
        DraftSpec spec = specs[i];
        Inv_PlanningPlanVersions__c version = new Inv_PlanningPlanVersions__c(
          MigrationKey__c = 'scenario-version:' +
            identity +
            ':' +
            String.valueOf(i + 1),
          PlanRef__c = parent.Id,
          VersionNo__c = String.valueOf(i + 1),
          Status__c = 'draft',
          ValuationAsOf__c = baseline.valuationDate,
          BaselineRunRef__c = baseline.runId,
          BaselineInputFingerprint__c = baseline.fingerprint,
          CreatedAt__c = System.now(),
          KnowledgeCutoff__c = System.now(),
          ConstraintsJson__c = spec.constraints,
          GenerationRationale__c = spec.rationale,
          ApprovalReadiness__c = 'Draft',
          TaxAssumptionAcknowledged__c = false,
          Assumptions__c = 'Baseline-price scenario only. No forecast return, tax amount, exit load, lock-in or broker execution is inferred.'
        );
        InvMath.project(
          version,
          'MonthlyBudget__c',
          String.valueOf(input.monthlyBudget)
        );
        versions.add(version);
      }
      insert as system versions;
      List<Inv_PlanningActions__c> actions = new List<Inv_PlanningActions__c>();
      List<Inv_PlanningTargets__c> targets = new List<Inv_PlanningTargets__c>();
      for (Integer i = 0; i < versions.size(); i++) {
        for (Inv_PlanningActions__c action : specs[i].actions) {
          action.PlanVersionRef__c = versions[i].Id;
          actions.add(action);
        }
        for (Inv_PlanningTargets__c target : specs[i].targets) {
          target.PlanVersionRef__c = versions[i].Id;
          targets.add(target);
        }
      }
      for (Inv_PlanningActions__c action : actions) {
        if (action.RequestedAmount__c != null)
          InvMath.project(
            action,
            'RequestedAmount__c',
            action.RequestedAmount__c
          );
        if (action.RequestedUnits__c != null)
          InvMath.project(
            action,
            'RequestedUnits__c',
            action.RequestedUnits__c
          );
        if (action.CashHoldDays__c != null)
          InvMath.project(action, 'CashHoldDays__c', action.CashHoldDays__c);
      }
      for (Inv_PlanningTargets__c target : targets)
        InvMath.project(target, 'Ratio__c', target.Ratio__c);
      if (!actions.isEmpty())
        insert as system actions;
      if (!targets.isEmpty())
        insert as system targets;
      ScenarioResult result = new ScenarioResult();
      result.planId = parent.Id;
      result.baselineRunId = baseline.runId;
      result.baselineDate = baseline.valuationDate;
      result.baselineFingerprint = baseline.fingerprint;
      for (Integer i = 0; i < versions.size(); i++) {
        Inv_PlanningPlanVersions__c version = versions[i];
        Alternative alternative = new Alternative();
        alternative.versionId = version.Id;
        alternative.title = specs[i].label;
        alternative.status = 'Draft';
        alternative.message = specs[i].rationale;
        Savepoint evaluationPoint = Database.setSavepoint();
        try {
          InvPlanService.Request request = new InvPlanService.Request();
          request.operation = 'evaluate';
          request.versionId = version.Id;
          request.expectedFingerprint = baseline.fingerprint;
          InvPlanService.manage(new List<InvPlanService.Request>{ request });
          if (String.isBlank(specs[i].unmetConstraints)) {
            alternative.status = 'Compared';
            alternative.message = 'Draft evaluated against the selected immutable baseline.';
            version.ApprovalReadiness__c = 'Review required';
          } else {
            alternative.status = 'Needs review';
            alternative.message = specs[i].unmetConstraints;
            version.ApprovalReadiness__c = 'Needs review';
            version.GenerationRationale__c = (version.GenerationRationale__c +
              '\nUnmet constraint: ' +
              specs[i].unmetConstraints)
              .left(32768);
          }
        } catch (Exception evaluationError) {
          Database.rollback(evaluationPoint);
          alternative.status = 'Needs review';
          alternative.message = String.isBlank(specs[i].unmetConstraints)
            ? evaluationError.getMessage()
            : specs[i].unmetConstraints +
              ' Evaluation needs review: ' +
              evaluationError.getMessage();
          version.ApprovalReadiness__c = 'Needs review';
          version.GenerationRationale__c = (version.GenerationRationale__c +
            '\nEvaluation needs review: ' +
            evaluationError.getMessage())
            .left(32768);
        }
        result.alternatives.add(alternative);
      }
      update as system versions;
      return result;
    } catch (Exception e) {
      Database.rollback(point);
      if (e instanceof ScenarioException)
        throw (ScenarioException) e;
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static ComparisonResult getComparison(List<Id> versionIds) {
    if (versionIds == null || versionIds.isEmpty() || versionIds.size() > 3)
      throw new AuraHandledException('Select one to three plan alternatives.');
    List<Inv_PlanningPlanVersions__c> versions = [
      SELECT
        Id,
        PlanRef__c,
        PlanRef__r.Name__c,
        PlanRef__r.PortfolioRef__c,
        VersionNo__c,
        Status__c,
        BaselineRunRef__c,
        BaselineRunRef__r.ValuationAsOf__c,
        BaselineInputFingerprint__c,
        ApprovalReadiness__c,
        GenerationRationale__c
      FROM Inv_PlanningPlanVersions__c
      WHERE Id IN :versionIds
      WITH USER_MODE
    ];
    if (versions.size() != new Set<Id>(versionIds).size())
      throw new AuraHandledException(
        'One or more selected plan versions are unavailable.'
      );
    ComparisonResult result = new ComparisonResult();
    Set<Id> versionSet = new Set<Id>();
    Id baselineId;
    String fingerprint;
    for (Inv_PlanningPlanVersions__c version : versions) {
      if (baselineId == null) {
        baselineId = version.BaselineRunRef__c;
        fingerprint = version.BaselineInputFingerprint__c;
        result.baselineDate = version.BaselineRunRef__r.ValuationAsOf__c;
      } else if (
        baselineId != version.BaselineRunRef__c ||
        fingerprint != version.BaselineInputFingerprint__c
      )
        throw new AuraHandledException(
          'These plan versions use different baselines. Rebase and compare them before proceeding.'
        );
      versionSet.add(version.Id);
      Alternative item = new Alternative();
      item.versionId = version.Id;
      item.title = version.PlanRef__r.Name__c + ' · v' + version.VersionNo__c;
      item.status = version.ApprovalReadiness__c;
      item.message = version.GenerationRationale__c;
      result.alternatives.add(item);
    }
    result.baselineRunId = baselineId;
    result.baselineFingerprint = fingerprint;
    Map<Id, String> names = new Map<Id, String>();
    Set<Id> fundIds = new Set<Id>();
    List<Inv_PlanImpact__c> source = [
      SELECT
        Id,
        PlanVersion__c,
        Fund__c,
        Fund__r.DisplayName__c,
        Fund__r.Name__c,
        Metric__c,
        Dimension__c,
        Member__c,
        Baseline__c,
        Proposed__c,
        Coverage__c,
        Notes__c
      FROM Inv_PlanImpact__c
      WHERE PlanVersion__c IN :versionSet AND Published__c = TRUE
      WITH USER_MODE
    ];
    for (Inv_PlanImpact__c row : source)
      if (row.Fund__c != null)
        fundIds.add(row.Fund__c);
    for (Inv_MarketInstruments__c fund : [
      SELECT Id, DisplayName__c, Name__c
      FROM Inv_MarketInstruments__c
      WHERE Id IN :fundIds
      WITH USER_MODE
    ])
      names.put(
        fund.Id,
        String.isBlank(fund.DisplayName__c) ? fund.Name__c : fund.DisplayName__c
      );
    for (Inv_PlanImpact__c record : source) {
      ImpactRow row = new ImpactRow();
      row.versionId = record.PlanVersion__c;
      row.fundId = record.Fund__c;
      row.fundName = names.get(record.Fund__c);
      row.metric = record.Metric__c;
      row.dimension = record.Dimension__c;
      row.member = record.Member__c;
      row.baseline = record.Baseline__c;
      row.proposed = record.Proposed__c;
      row.coverage = record.Coverage__c;
      row.notes = record.Notes__c;
      result.impacts.add(row);
    }
    return result;
  }

  @AuraEnabled(cacheable=true)
  public static List<RedemptionAction> getOpenRedemptionActions(
    Id portfolioId
  ) {
    if (portfolioId == null)
      return new List<RedemptionAction>();
    List<Inv_PortfolioPortfolios__c> portfolios = [
      SELECT Id, PublishedRun__c
      FROM Inv_PortfolioPortfolios__c
      WHERE Id = :portfolioId
      WITH USER_MODE
    ];
    if (portfolios.isEmpty() || portfolios[0].PublishedRun__c == null)
      return new List<RedemptionAction>();
    Set<Id> versions = new Set<Id>();
    for (Inv_PlanningPlanVersions__c version : [
      SELECT Id, Status__c
      FROM Inv_PlanningPlanVersions__c
      WHERE
        PlanRef__r.PortfolioRef__c = :portfolioId
        AND BaselineRunRef__c = :portfolios[0].PublishedRun__c
      WITH USER_MODE
    ])
      if (version.Status__c == 'draft')
        versions.add(version.Id);
    if (versions.isEmpty())
      return new List<RedemptionAction>();
    List<Inv_PlanningActions__c> source = [
      SELECT
        Id,
        ActionType__c,
        PlanVersionRef__c,
        PlanVersionRef__r.VersionNo__c,
        PlanVersionRef__r.PlanRef__r.Name__c,
        InstrumentRef__c,
        AccountRef__c,
        RequestedAmount__c,
        RequestedUnits__c,
        AllAvailable__c
      FROM Inv_PlanningActions__c
      WHERE PlanVersionRef__c IN :versions
      WITH USER_MODE
      ORDER BY CreatedDate DESC
    ];
    Set<Id> funds = new Set<Id>();
    for (Inv_PlanningActions__c action : source)
      if (action.InstrumentRef__c != null)
        funds.add(action.InstrumentRef__c);
    Map<Id, String> fundNames = new Map<Id, String>();
    for (Inv_MarketInstruments__c fund : [
      SELECT Id, DisplayName__c, Name__c
      FROM Inv_MarketInstruments__c
      WHERE Id IN :funds
      WITH USER_MODE
    ])
      fundNames.put(
        fund.Id,
        String.isBlank(fund.DisplayName__c) ? fund.Name__c : fund.DisplayName__c
      );
    List<RedemptionAction> results = new List<RedemptionAction>();
    for (Inv_PlanningActions__c action : source) {
      if (action.ActionType__c != 'redeem')
        continue;
      RedemptionAction item = new RedemptionAction();
      item.actionId = action.Id;
      item.versionId = action.PlanVersionRef__c;
      item.fundId = action.InstrumentRef__c;
      item.accountId = action.AccountRef__c;
      item.amount = InvMath.exact(action.RequestedAmount__c);
      item.units = InvMath.exact(action.RequestedUnits__c);
      item.allAvailable = action.AllAvailable__c;
      item.label =
        action.PlanVersionRef__r.PlanRef__r.Name__c +
        ' v' +
        action.PlanVersionRef__r.VersionNo__c +
        ' · ' +
        fundNames.get(action.InstrumentRef__c);
      results.add(item);
    }
    return results;
  }

  private static void requireManager() {
    if (!FeatureManagement.checkPermission('Inv_ManagePortfolio'))
      throw new AuraHandledException(
        'Portfolio Manager permission is required to create scenario drafts.'
      );
  }
  private static void validateInput(ScenarioInput input) {
    if (input == null || input.portfolioId == null)
      throw new ScenarioException('Choose a portfolio.');
    if (input.monthlyBudget == null || input.monthlyBudget < 0)
      throw new ScenarioException('Enter a nonnegative monthly SIP budget.');
    if (input.cashNeed != null && input.cashNeed < 0)
      throw new ScenarioException(
        'Cash needed for spending must be nonnegative.'
      );
    if (input.cashHoldDays != null && input.cashHoldDays < 0)
      throw new ScenarioException(
        'Cash-hold duration must be nonnegative calendar days.'
      );
    if (input.maximumFundCount != null && input.maximumFundCount < 1)
      throw new ScenarioException('Maximum fund count must be at least one.');
    Set<Id> retain = new Set<Id>();
    if (input.retainedFundIds != null)
      retain.addAll(input.retainedFundIds);
    Set<Id> exits = new Set<Id>();
    if (input.exitCandidateFundIds != null)
      exits.addAll(input.exitCandidateFundIds);
    Set<Id> excludedNew = new Set<Id>();
    if (input.excludedNewPurchaseFundIds != null)
      excludedNew.addAll(input.excludedNewPurchaseFundIds);
    for (Id id : retain)
      if (exits.contains(id))
        throw new ScenarioException(
          'A fund cannot be marked both retain and consider-exit.'
        );
    Decimal total = 0;
    Set<Id> uniqueTargets = new Set<Id>();
    if (input.targetAllocations != null)
      for (TargetAllocation target : input.targetAllocations) {
        if (
          target == null ||
          target.fundId == null ||
          target.weightPercent == null ||
          target.weightPercent < 0 ||
          target.weightPercent > 100
        )
          throw new ScenarioException(
            'Every target allocation needs a fund and a weight from zero to 100 percent.'
          );
        if (uniqueTargets.contains(target.fundId))
          throw new ScenarioException(
            'Target allocations must contain each fund once.'
          );
        uniqueTargets.add(target.fundId);
        total += target.weightPercent;
      }
    if (total > 100)
      throw new ScenarioException('Target allocations exceed 100 percent.');
    if (input.targetAllocations == null || input.targetAllocations.isEmpty())
      throw new ScenarioException(
        'Enter target allocations to build the target-alignment alternative.'
      );
    Set<Id> selectedFunds = new Set<Id>();
    selectedFunds.addAll(retain);
    selectedFunds.addAll(exits);
    selectedFunds.addAll(excludedNew);
    for (TargetAllocation target : input.targetAllocations)
      if (target != null && target.fundId != null)
        selectedFunds.add(target.fundId);
    if (!selectedFunds.isEmpty()) {
      Set<Id> valid = new Set<Id>();
      for (Inv_MarketInstruments__c fund : [
        SELECT Id
        FROM Inv_MarketInstruments__c
        WHERE Id IN :selectedFunds AND MappingVerified__c = TRUE
        WITH USER_MODE
      ])
        valid.add(fund.Id);
      if (valid.size() != selectedFunds.size())
        throw new ScenarioException(
          'Selected funds must be verified mutual-fund share classes.'
        );
    }
  }
  private static Baseline loadBaseline(Id portfolioId) {
    Inv_PortfolioPortfolios__c portfolio = [
      SELECT
        Id,
        PublishedRun__c,
        PublishedRun__r.Status__c,
        PublishedRun__r.ValuationAsOf__c,
        PublishedRun__r.InputFingerprint__c
      FROM Inv_PortfolioPortfolios__c
      WHERE Id = :portfolioId
      WITH USER_MODE
    ];
    Baseline b = new Baseline();
    b.portfolioId = portfolioId;
    b.runId = portfolio.PublishedRun__c;
    if (b.runId == null || portfolio.PublishedRun__r.Status__c != 'complete')
      return b;
    b.valuationDate = portfolio.PublishedRun__r.ValuationAsOf__c;
    b.fingerprint = portfolio.PublishedRun__r.InputFingerprint__c;
    for (Inv_HoldingValuation__c h : [
      SELECT Fund__c, Units__c, MarketValue__c, NAV__c
      FROM Inv_HoldingValuation__c
      WHERE Portfolio__c = :portfolioId AND Run__c = :b.runId
      WITH USER_MODE
    ]) {
      if (h.Fund__c == null) {
        b.complete = false;
        continue;
      }
      if (h.Units__c > 0 && (h.MarketValue__c == null || h.NAV__c == null))
        b.complete = false;
      Decimal value = h.MarketValue__c == null ? 0 : h.MarketValue__c;
      b.values.put(
        h.Fund__c,
        (b.values.containsKey(h.Fund__c) ? b.values.get(h.Fund__c) : 0) + value
      );
      b.units.put(
        h.Fund__c,
        (b.units.containsKey(h.Fund__c) ? b.units.get(h.Fund__c) : 0) +
        (h.Units__c == null ? 0 : h.Units__c)
      );
      if (h.NAV__c != null)
        b.navs.put(h.Fund__c, h.NAV__c);
      b.value += value;
    }
    Set<Id> accounts = new Set<Id>();
    for (Inv_PortfolioAccounts__c account : [
      SELECT Id
      FROM Inv_PortfolioAccounts__c
      WHERE PortfolioRef__c = :portfolioId
      WITH USER_MODE
    ])
      accounts.add(account.Id);
    if (!accounts.isEmpty())
      for (Inv_PortfolioSipVersions__c sip : [
        SELECT
          InstrumentRef__r.InstrumentRef__c,
          Amount__c,
          VerificationState__c,
          ReportedStatus__c,
          Frequency__c
        FROM Inv_PortfolioSipVersions__c
        WHERE
          AccountRef__c IN :accounts
          AND EffectiveFrom__c <= :b.valuationDate
          AND (EffectiveTo__c = NULL
          OR EffectiveTo__c > :b.valuationDate)
        WITH USER_MODE
      ]) {
        if (
          sip.VerificationState__c != 'user_confirmed' ||
          sip.ReportedStatus__c != 'active' ||
          sip.Frequency__c != 'monthly'
        )
          continue;
        if (
          sip.InstrumentRef__r == null ||
          sip.InstrumentRef__r.InstrumentRef__c == null
        )
          continue;
        Id fund = sip.InstrumentRef__r.InstrumentRef__c;
        b.sips.put(
          fund,
          (b.sips.containsKey(fund) ? b.sips.get(fund) : 0) +
          InvMath.exact(sip.Amount__c)
        );
      }
    return b;
  }
  private static List<DraftSpec> buildSpecs(ScenarioInput input, Baseline b) {
    Date firstDate = b.valuationDate.addDays(1);
    Integer holdDays = input.cashHoldDays == null ? 0 : input.cashHoldDays;
    Set<Id> retain = new Set<Id>();
    if (input.retainedFundIds != null)
      retain.addAll(input.retainedFundIds);
    Set<Id> exits = new Set<Id>();
    if (input.exitCandidateFundIds != null)
      exits.addAll(input.exitCandidateFundIds);
    Set<Id> excludeNew = new Set<Id>();
    if (input.excludedNewPurchaseFundIds != null)
      excludeNew.addAll(input.excludedNewPurchaseFundIds);
    DraftSpec sipOnly = new DraftSpec();
    sipOnly.label = 'SIP changes only';
    sipOnly.rationale = 'Holdings are left unchanged. Future monthly SIPs are distributed in proportion to currently confirmed monthly SIPs; if no active SIP evidence exists, budget remains unallocated.';
    Set<Id> sipOnlyRecipients = new Set<Id>(b.sips.keySet());
    sipOnlyRecipients.removeAll(excludeNew);
    sipOnly.constraints = constraints(input, 'SIP changes only');
    addSipActions(
      sipOnly,
      b.sips,
      input.monthlyBudget,
      sipOnlyRecipients,
      firstDate,
      'Preserve the existing SIP distribution except for funds excluded from new purchases.'
    );
    DraftSpec minimum = new DraftSpec();
    minimum.label = 'Minimum turnover';
    minimum.rationale = 'Only funds you marked as consider-exit are fully redeemed. SIP budget is directed to retained funds by current SIP weights, falling back to current holding weights; no unselected fund is exited.';
    minimum.constraints = constraints(input, 'Minimum turnover');
    for (Id fund : exits)
      if ((b.units.containsKey(fund) ? b.units.get(fund) : 0) > 0)
        minimum.actions.add(
          action(
            'redeem',
            fund,
            null,
            null,
            firstDate,
            true,
            'Explicit user-selected exit candidate; lot eligibility, exit load and tax remain for review.'
          )
        );
    Set<Id> sipTargets = new Set<Id>();
    if (!retain.isEmpty())
      sipTargets.addAll(retain);
    else {
      sipTargets.addAll(b.sips.keySet());
      sipTargets.removeAll(exits);
    }
    sipTargets.removeAll(excludeNew);
    for (Id fund : b.sips.keySet())
      if (!sipTargets.contains(fund))
        minimum.actions.add(
          action(
            'pause_sip',
            fund,
            0,
            null,
            firstDate,
            false,
            'Stop future SIP for a fund outside the selected retained set or excluded from new purchases.'
          )
        );
    Map<Id, Decimal> weights = new Map<Id, Decimal>();
    for (Id fund : sipTargets)
      weights.put(
        fund,
        b.sips.containsKey(fund)
          ? b.sips.get(fund)
          : (b.values.containsKey(fund) ? b.values.get(fund) : 0)
      );
    addSipActions(
      minimum,
      weights,
      input.monthlyBudget,
      sipTargets,
      firstDate,
      'Redirect future contributions within the explicit retained set.'
    );
    if (input.cashNeed != null && input.cashNeed > 0)
      minimum.actions.add(
        action(
          'cash_need',
          null,
          input.cashNeed,
          null,
          firstDate,
          false,
          'User-entered spending cash requirement.'
        )
      );
    if (holdDays > 0)
      minimum.actions.add(
        action(
          'cash_hold',
          null,
          null,
          holdDays,
          firstDate,
          false,
          'User-entered calendar-day cash hold.'
        )
      );
    DraftSpec target = new DraftSpec();
    target.label = 'Target alignment';
    target.rationale = 'Applies only the target allocation percentages you entered. Blank or omitted funds are treated as zero; review the table carefully before saving. Values use baseline prices.';
    target.constraints = constraints(input, 'Target alignment');
    Map<Id, Decimal> weightsByFund = new Map<Id, Decimal>();
    if (input.targetAllocations != null)
      for (TargetAllocation row : input.targetAllocations)
        weightsByFund.put(row.fundId, row.weightPercent);
    Set<Id> allFunds = new Set<Id>();
    allFunds.addAll(b.values.keySet());
    allFunds.addAll(weightsByFund.keySet());
    for (Id currentFund : b.values.keySet())
      if (!weightsByFund.containsKey(currentFund))
        throw new ScenarioException(
          'Enter a target allocation, including zero for exits, for every fund in the current baseline.'
        );
    validateTargetFunds(weightsByFund, retain, exits);
    for (Id fund : weightsByFund.keySet()) {
      Inv_PlanningTargets__c row = new Inv_PlanningTargets__c(
        MigrationKey__c = 'target:scenario:' +
          String.valueOf(Crypto.getRandomLong()),
        Axis__c = 'fund',
        TargetKey__c = String.valueOf(fund),
        Fund__c = fund
      );
      row.Ratio__c = String.valueOf(weightsByFund.get(fund) / 100);
      target.targets.add(row);
    }
    Decimal cashNeed = input.cashNeed == null ? 0 : input.cashNeed;
    if (cashNeed > b.value)
      throw new ScenarioException(
        'Spending cash exceeds the baseline portfolio value.'
      );
    Decimal investable = b.value - cashNeed;
    if (holdDays > 0)
      target.actions.add(
        action(
          'cash_hold',
          null,
          null,
          holdDays,
          firstDate,
          false,
          'User-entered calendar-day cash hold; linked purchases are dated after the hold period.'
        )
      );
    for (Id fund : allFunds) {
      Decimal current = b.values.containsKey(fund) ? b.values.get(fund) : 0,
        weight = weightsByFund.containsKey(fund) ? weightsByFund.get(fund) : 0;
      Decimal desired = investable * weight / 100, delta = desired - current;
      if (delta < -0.005)
        target.actions.add(
          action(
            'redeem',
            fund,
            -delta,
            null,
            firstDate,
            false,
            'Target-weight reduction calculated from the selected baseline NAV.'
          )
        );
    }
    for (Id fund : allFunds) {
      Decimal current = b.values.containsKey(fund) ? b.values.get(fund) : 0,
        weight = weightsByFund.containsKey(fund) ? weightsByFund.get(fund) : 0;
      Decimal desired = investable * weight / 100, delta = desired - current;
      if (delta > 0.005 && excludeNew.contains(fund)) {
        target.unmetConstraints =
          (String.isBlank(target.unmetConstraints)
            ? ''
            : target.unmetConstraints + '; ') +
          'Target for ' +
          String.valueOf(fund) +
          ' requires a purchase, but this fund is excluded from new purchases.';
      } else if (delta > 0.005)
        target.actions.add(
          action(
            'buy',
            fund,
            delta,
            null,
            firstDate.addDays(holdDays),
            false,
            'Target-weight increase calculated from baseline portfolio value.'
          )
        );
    }
    if (cashNeed > 0)
      target.actions.add(
        action(
          'cash_need',
          null,
          cashNeed,
          null,
          firstDate,
          false,
          'User-entered spending cash requirement.'
        )
      );
    Set<Id> sipTargets2 = new Set<Id>();
    for (Id fund : b.sips.keySet())
      sipTargets2.add(fund);
    if (!retain.isEmpty())
      sipTargets2.retainAll(retain);
    sipTargets2.removeAll(exits);
    sipTargets2.removeAll(excludeNew);
    addSipActions(
      target,
      b.sips,
      input.monthlyBudget,
      sipTargets2,
      firstDate,
      'Maintain confirmed SIP distribution in target-alignment alternative.'
    );
    if (input.maximumFundCount != null) {
      Integer currentCount = 0, minimumCount = 0, targetCount = 0;
      for (Id fund : b.values.keySet())
        if (b.values.get(fund) > 0) {
          currentCount++;
          if (!exits.contains(fund))
            minimumCount++;
        }
      for (Inv_PlanningTargets__c allocation : target.targets)
        if (InvMath.exact(allocation.Ratio__c) > 0)
          targetCount++;
      flagFundLimit(sipOnly, currentCount, input.maximumFundCount);
      flagFundLimit(minimum, minimumCount, input.maximumFundCount);
      flagFundLimit(target, targetCount, input.maximumFundCount);
    }
    return new List<DraftSpec>{ sipOnly, minimum, target };
  }
  private static void flagFundLimit(
    DraftSpec spec,
    Integer count,
    Integer maximum
  ) {
    if (count <= maximum)
      return;
    String reason =
      'Projected fund count ' +
      String.valueOf(count) +
      ' exceeds your selected maximum of ' +
      String.valueOf(maximum) +
      '.';
    spec.unmetConstraints = String.isBlank(spec.unmetConstraints)
      ? reason
      : spec.unmetConstraints + '; ' + reason;
  }
  private static String constraints(ScenarioInput input, String variant) {
    return JSON.serialize(
      new Map<String, Object>{
        'objective' => input.objective,
        'variant' => variant,
        'maximumFundCount' => input.maximumFundCount,
        'retainedFundIds' => input.retainedFundIds == null
          ? new List<Id>()
          : input.retainedFundIds,
        'exitCandidateFundIds' => input.exitCandidateFundIds == null
          ? new List<Id>()
          : input.exitCandidateFundIds,
        'excludedNewPurchaseFundIds' => input.excludedNewPurchaseFundIds == null
          ? new List<Id>()
          : input.excludedNewPurchaseFundIds,
        'cashNeed' => input.cashNeed == null ? 0 : input.cashNeed,
        'cashHoldDays' => input.cashHoldDays == null ? 0 : input.cashHoldDays,
        'targetAllocations' => input.targetAllocations == null
          ? new List<TargetAllocation>()
          : input.targetAllocations
      }
    );
  }
  private static Inv_PlanningActions__c action(
    String kind,
    Id fund,
    Decimal amount,
    Decimal holdDays,
    Date day,
    Boolean all,
    String rationale
  ) {
    Inv_PlanningActions__c row = new Inv_PlanningActions__c(
      MigrationKey__c = 'scenario-action:' +
        String.valueOf(Crypto.getRandomLong()),
      ActionType__c = kind,
      InstrumentRef__c = fund,
      AllAvailable__c = all,
      IntendedDate__c = day,
      Rationale__c = rationale
    );
    if (amount != null)
      row.RequestedAmount__c = String.valueOf(amount);
    if (holdDays != null)
      row.CashHoldDays__c = String.valueOf(holdDays);
    return row;
  }
  private static void addSipActions(
    DraftSpec spec,
    Map<Id, Decimal> weights,
    Decimal budget,
    Set<Id> recipients,
    Date actionDate,
    String rationale
  ) {
    Map<Id, Decimal> allocated = allocate(budget, weights, recipients);
    Set<Id> all = new Set<Id>();
    all.addAll(weights.keySet());
    all.addAll(recipients);
    for (Id fund : all) {
      Decimal amount = allocated.containsKey(fund) ? allocated.get(fund) : 0;
      if (amount > 0)
        spec.actions.add(
          action('set_sip', fund, amount, null, actionDate, false, rationale)
        );
      else if (weights.containsKey(fund))
        spec.actions.add(
          action('pause_sip', fund, 0, null, actionDate, false, rationale)
        );
    }
  }
  private static Map<Id, Decimal> allocate(
    Decimal budget,
    Map<Id, Decimal> weights,
    Set<Id> recipients
  ) {
    Map<Id, Decimal> result = new Map<Id, Decimal>();
    List<Id> ordered = new List<Id>();
    for (Id fund : recipients)
      if ((weights.containsKey(fund) ? weights.get(fund) : 0) > 0)
        ordered.add(fund);
    ordered.sort();
    Decimal total = 0;
    for (Id fund : ordered)
      total += weights.get(fund);
    if (total <= 0 || budget <= 0)
      return result;
    Decimal remaining = budget;
    for (Integer i = 0; i < ordered.size(); i++) {
      Id fund = ordered[i];
      Decimal value = i == ordered.size() - 1
        ? remaining
        : (budget *
            weights.get(fund) /
            total)
            .setScale(2, RoundingMode.HALF_UP);
      result.put(fund, value);
      remaining -= value;
    }
    return result;
  }
  private static void validateTargetFunds(
    Map<Id, Decimal> targets,
    Set<Id> retained,
    Set<Id> exits
  ) {
    Set<Id> targetIds = targets.keySet();
    Set<Id> valid = new Set<Id>();
    for (Inv_MarketInstruments__c fund : [
      SELECT Id
      FROM Inv_MarketInstruments__c
      WHERE Id IN :targetIds AND MappingVerified__c = TRUE
      WITH USER_MODE
    ])
      valid.add(fund.Id);
    if (valid.size() != targetIds.size())
      throw new ScenarioException(
        'Every new target must be a verified mutual-fund share class.'
      );
    for (Id id : retained)
      if (!targets.containsKey(id) || targets.get(id) <= 0)
        throw new ScenarioException(
          'Add a positive target allocation for every fund marked to retain.'
        );
    for (Id id : exits)
      if (targets.containsKey(id) && targets.get(id) > 0)
        throw new ScenarioException(
          'A fund marked to exit cannot also have a positive target allocation.'
        );
  }
}
