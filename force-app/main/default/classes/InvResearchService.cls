/** Read-only, permission-aware facade for the Lightning research pages. */
public with sharing class InvResearchService {
  public class PortfolioData {
    @AuraEnabled
    public Id portfolioId;
    @AuraEnabled
    public String portfolioName;
    @AuraEnabled
    public Id baselineRunId;
    @AuraEnabled
    public String baselineFingerprint;
    @AuraEnabled
    public String calculationVersion;
    @AuraEnabled
    public Date valuationDate;
    @AuraEnabled
    public Date earliestNavDate;
    @AuraEnabled
    public Date latestNavDate;
    @AuraEnabled
    public Datetime ledgerCutoff;
    @AuraEnabled
    public Datetime knowledgeCutoff;
    @AuraEnabled
    public Decimal marketValue;
    @AuraEnabled
    public Decimal remainingCost;
    @AuraEnabled
    public Decimal unrealizedGain;
    @AuraEnabled
    public Decimal realizedGain;
    @AuraEnabled
    public Decimal monthlySip;
    @AuraEnabled
    public Integer activeFundCount;
    @AuraEnabled
    public Date reconciledThrough;
    @AuraEnabled
    public String statusMessage;
    @AuraEnabled
    public String pipelineMessage;
    @AuraEnabled
    public List<HoldingRow> holdings = new List<HoldingRow>();
    @AuraEnabled
    public List<SipRow> sips = new List<SipRow>();
    @AuraEnabled
    public List<ExposureRow> exposures = new List<ExposureRow>();
    @AuraEnabled
    public List<MetricRow> metrics = new List<MetricRow>();
    @AuraEnabled
    public List<ChartPoint> marketValueHistory = new List<ChartPoint>();
  }
  public class HoldingRow {
    @AuraEnabled
    public Id holdingId;
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public Boolean mappingVerified;
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountLabel;
    @AuraEnabled
    public Id portfolioId;
    @AuraEnabled
    public String portfolioName;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String amc;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Decimal units;
    @AuraEnabled
    public Decimal nav;
    @AuraEnabled
    public Date navDate;
    @AuraEnabled
    public String navProvider;
    @AuraEnabled
    public Decimal cost;
    @AuraEnabled
    public Decimal marketValue;
    @AuraEnabled
    public Decimal unrealizedGain;
    @AuraEnabled
    public Decimal realizedGain;
    @AuraEnabled
    public Decimal weight;
    @AuraEnabled
    public Decimal xirr;
    @AuraEnabled
    public Decimal monthlySip;
    @AuraEnabled
    public Date reconciledThrough;
    @AuraEnabled
    public String unitCoverage;
    @AuraEnabled
    public String basisCoverage;
    @AuraEnabled
    public String redemptionCoverage;
    @AuraEnabled
    public String returnCoverage;
    @AuraEnabled
    public String navCoverage;
    @AuraEnabled
    public String compositionCoverage;
    @AuraEnabled
    public String policyCoverage;
    @AuraEnabled
    public String coverage;
    @AuraEnabled
    public String warnings;
  }
  public class SipRow {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public Decimal amount;
    @AuraEnabled
    public Date effectiveFrom;
    @AuraEnabled
    public Date effectiveTo;
    @AuraEnabled
    public String frequency;
    @AuraEnabled
    public String accountLabel;
  }
  public class ExposureRow {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String dimension;
    @AuraEnabled
    public String member;
    @AuraEnabled
    public String memberKey;
    @AuraEnabled
    public String sourceLabels;
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public Decimal weight;
    @AuraEnabled
    public Date disclosureDate;
    @AuraEnabled
    public String coverage;
  }
  public class MetricRow {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String metric;
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public Date periodStart;
    @AuraEnabled
    public Date periodEnd;
    @AuraEnabled
    public String coverage;
    @AuraEnabled
    public Id comparedFundId;
    @AuraEnabled
    public String comparedFundName;
  }
  public class FundData {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String isin;
    @AuraEnabled
    public String amfiCode;
    @AuraEnabled
    public Boolean mappingVerified;
    @AuraEnabled
    public Boolean tracked;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String amc;
    @AuraEnabled
    public Decimal latestNav;
    @AuraEnabled
    public String portfolioRole;
    @AuraEnabled
    public String researchNote;
    @AuraEnabled
    public Decimal monthlySip;
    @AuraEnabled
    public Date navDate;
    @AuraEnabled
    public String navProvider;
    @AuraEnabled
    public Decimal ter;
    @AuraEnabled
    public Decimal ber;
    @AuraEnabled
    public Date expenseDate;
    @AuraEnabled
    public String benchmarkVariant;
    @AuraEnabled
    public List<MetricRow> metrics = new List<MetricRow>();
    @AuraEnabled
    public List<ExposureRow> composition = new List<ExposureRow>();
    @AuraEnabled
    public List<HoldingRow> positions = new List<HoldingRow>();
    @AuraEnabled
    public List<PeerRow> peers = new List<PeerRow>();
    @AuraEnabled
    public List<ChartPoint> navHistory = new List<ChartPoint>();
    @AuraEnabled
    public String statusMessage;
  }
  public class ChartPoint {
    @AuraEnabled
    public Id runId;
    @AuraEnabled
    public Date day;
    @AuraEnabled
    public Decimal value;
    @AuraEnabled
    public Decimal comparison;
  }
  public class PeerRow {
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Date effectiveFrom;
    @AuraEnabled
    public Date effectiveTo;
    @AuraEnabled
    public String shareClassRule;
    @AuraEnabled
    public String rationale;
    @AuraEnabled
    public String coverage;
  }

  @AuraEnabled(cacheable=true)
  public static PortfolioData getPortfolioResearch(Id requestedPortfolioId) {
    PortfolioData out = new PortfolioData();
    Inv_PortfolioPortfolios__c portfolio;
    if (requestedPortfolioId == null) {
      List<Inv_PortfolioPortfolios__c> choices = [
        SELECT Id, Name__c, PublishedRun__c
        FROM Inv_PortfolioPortfolios__c
        WITH USER_MODE
        ORDER BY CreatedDate ASC
        LIMIT 1
      ];
      if (choices.isEmpty()) {
        out.statusMessage = 'No portfolio is available to this user.';
        return out;
      }
      portfolio = choices[0];
    } else {
      List<Inv_PortfolioPortfolios__c> choices = [
        SELECT Id, Name__c, PublishedRun__c
        FROM Inv_PortfolioPortfolios__c
        WHERE Id = :requestedPortfolioId
        WITH USER_MODE
      ];
      if (choices.isEmpty())
        throw new AuraHandledException(
          'The selected portfolio is unavailable.'
        );
      portfolio = choices[0];
    }
    out.portfolioId = portfolio.Id;
    out.portfolioName = portfolio.Name__c;
    if (portfolio.PublishedRun__c == null) {
      out.statusMessage = 'No completed portfolio valuation has been published.';
      return out;
    }
    Inv_AnalyticsRuns__c run = [
      SELECT
        Id,
        Status__c,
        AlgorithmVersion__c,
        InputFingerprint__c,
        LedgerCutoff__c,
        KnowledgeCutoff__c,
        ValuationAsOf__c,
        OperationalStatus__c,
        PipelineRef__c,
        PipelineRef__r.PipelineStage__c,
        PipelineRef__r.OperationalStatus__c,
        PipelineRef__r.PortfolioStageStatus__c,
        PipelineRef__r.ExposureStageStatus__c,
        PipelineRef__r.FundMetricsStageStatus__c,
        PipelineRef__r.CompletedAt__c,
        PipelineRef__r.Failure__c
      FROM Inv_AnalyticsRuns__c
      WHERE Id = :portfolio.PublishedRun__c
      WITH USER_MODE
    ];
    if (run.Status__c != 'complete') {
      out.statusMessage = 'The published calculation is not complete; previous results remain available.';
      return out;
    }
    out.baselineRunId = run.Id;
    out.baselineFingerprint = run.InputFingerprint__c;
    out.calculationVersion = run.AlgorithmVersion__c;
    out.valuationDate = run.ValuationAsOf__c;
    out.ledgerCutoff = run.LedgerCutoff__c;
    out.knowledgeCutoff = run.KnowledgeCutoff__c;
    if (run.PipelineRef__c == null)
      out.pipelineMessage = 'Stage pipeline status is unavailable for this earlier calculation.';
    else {
      Inv_AnalyticsRuns__c pipeline = run.PipelineRef__r;
      out.pipelineMessage =
        'Refresh stages: portfolio ' +
        pipeline.PortfolioStageStatus__c +
        ', exposure ' +
        pipeline.ExposureStageStatus__c +
        ', fund metrics ' +
        pipeline.FundMetricsStageStatus__c +
        '. Last stage update ' +
        String.valueOf(pipeline.CompletedAt__c) +
        '.';
      if (
        pipeline.OperationalStatus__c == 'Failed' ||
        !String.isBlank(pipeline.Failure__c)
      )
        out.pipelineMessage +=
          ' A refresh stage failed; the last successful published portfolio valuation remains available. ' +
          pipeline.Failure__c;
      else if (pipeline.OperationalStatus__c == 'Running')
        out.pipelineMessage += ' Refresh is still running; the prior successful valuation remains published.';
    }
    List<Inv_PortfolioValuation__c> totals = [
      SELECT
        MarketValue__c,
        Cost__c,
        UnrealizedGain__c,
        RealizedGain__c,
        MonthlySIP__c,
        EarliestNAV__c,
        LatestNAV__c,
        Coverage__c
      FROM Inv_PortfolioValuation__c
      WHERE
        Portfolio__c = :portfolio.Id
        AND Run__c = :run.Id
        AND Published__c = TRUE
      WITH USER_MODE
      LIMIT 1
    ];
    if (totals.isEmpty()) {
      out.statusMessage = 'The completed run has no published portfolio summary.';
      return out;
    }
    Inv_PortfolioValuation__c total = totals[0];
    out.marketValue = total.MarketValue__c;
    out.remainingCost = total.Cost__c;
    out.unrealizedGain = total.UnrealizedGain__c;
    out.realizedGain = total.RealizedGain__c;
    out.monthlySip = total.MonthlySIP__c;
    out.earliestNavDate = total.EarliestNAV__c;
    out.latestNavDate = total.LatestNAV__c;
    out.statusMessage = total.Coverage__c;
    List<Inv_PortfolioValuation__c> history = [
      SELECT Run__c, AsOf__c, MarketValue__c, Cost__c
      FROM Inv_PortfolioValuation__c
      WHERE
        Portfolio__c = :portfolio.Id
        AND LatestForDate__c = TRUE
        AND AsOf__c <= :run.ValuationAsOf__c
      WITH USER_MODE
      ORDER BY AsOf__c DESC
      LIMIT 365
    ];
    for (Integer i = history.size() - 1; i >= 0; i--) {
      ChartPoint point = new ChartPoint();
      point.runId = history[i].Run__c;
      point.day = history[i].AsOf__c;
      point.value = history[i].MarketValue__c;
      point.comparison = history[i].Cost__c;
      out.marketValueHistory.add(point);
    }
    Set<Id> funds = new Set<Id>();
    Set<Id> activeFunds = new Set<Id>();
    for (Inv_HoldingValuation__c h : [
      SELECT
        Id,
        Holding__c,
        Holding__r.Account__c,
        Holding__r.Account__r.MaskedReference__c,
        Portfolio__c,
        Portfolio__r.Name__c,
        Fund__c,
        Fund__r.MappingVerified__c,
        Units__c,
        NAV__c,
        NAVDate__c,
        NAVProvider__c,
        ReconciledThrough__c,
        Cost__c,
        MarketValue__c,
        UnrealizedGain__c,
        RealizedGain__c,
        Weight__c,
        XIRR__c,
        SIPAmount__c,
        Category__c,
        AMC__c,
        Status__c,
        UnitCoverage__c,
        BasisCoverage__c,
        RedemptionCoverage__c,
        PersonalReturnCoverage__c,
        NAVCoverage__c,
        CompositionCoverage__c,
        PolicyCoverage__c,
        Coverage__c,
        Warnings__c
      FROM Inv_HoldingValuation__c
      WHERE Portfolio__c = :portfolio.Id AND Run__c = :run.Id
      WITH USER_MODE
      ORDER BY MarketValue__c DESC NULLS LAST
      LIMIT 2000
    ]) {
      HoldingRow row = holding(h);
      if (
        (row.weight == null ||
        row.weight == 0) &&
        row.marketValue != null &&
        row.marketValue > 0 &&
        out.marketValue != null &&
        out.marketValue > 0
      )
        row.weight = row.marketValue / out.marketValue;
      out.holdings.add(row);
      if (row.fundId != null)
        funds.add(row.fundId);
      if (
        row.status == 'Active' &&
        row.units != null &&
        row.units > 0 &&
        row.fundId != null
      )
        activeFunds.add(row.fundId);
      if (
        row.reconciledThrough != null &&
        (out.reconciledThrough == null ||
        row.reconciledThrough > out.reconciledThrough)
      )
        out.reconciledThrough = row.reconciledThrough;
    }
    out.activeFundCount = activeFunds.size();
    Set<Id> accountIds = new Set<Id>();
    for (Inv_PortfolioAccounts__c a : [
      SELECT Id, MaskedReference__c
      FROM Inv_PortfolioAccounts__c
      WHERE PortfolioRef__c = :portfolio.Id
      WITH USER_MODE
    ])
      accountIds.add(a.Id);
    List<Inv_PortfolioSipVersions__c> sipRecords = new List<Inv_PortfolioSipVersions__c>();
    Set<Id> shareClassIds = new Set<Id>();
    if (!accountIds.isEmpty())
      for (Inv_PortfolioSipVersions__c sip : [
        SELECT
          InstrumentRef__c,
          AccountRef__c,
          Amount__c,
          Frequency__c,
          EffectiveFrom__c,
          EffectiveTo__c,
          VerificationState__c,
          ReportedStatus__c
        FROM Inv_PortfolioSipVersions__c
        WHERE
          AccountRef__c IN :accountIds
          AND EffectiveFrom__c <= :run.ValuationAsOf__c
          AND (EffectiveTo__c = NULL
          OR EffectiveTo__c > :run.ValuationAsOf__c)
        WITH USER_MODE
      ]) {
        if (
          sip.VerificationState__c != 'user_confirmed' ||
          sip.ReportedStatus__c != 'active' ||
          sip.Frequency__c != 'monthly'
        )
          continue;
        sipRecords.add(sip);
        if (sip.InstrumentRef__c != null)
          shareClassIds.add(sip.InstrumentRef__c);
      }
    Map<Id, Id> fundByShareClass = new Map<Id, Id>();
    for (Inv_MarketFundShareClasses__c share : [
      SELECT Id, InstrumentRef__c
      FROM Inv_MarketFundShareClasses__c
      WHERE Id IN :shareClassIds
      WITH USER_MODE
    ])
      if (share.InstrumentRef__c != null)
        fundByShareClass.put(share.Id, share.InstrumentRef__c);
    Map<Id, String> accountLabels = new Map<Id, String>();
    for (Inv_PortfolioAccounts__c a : [
      SELECT Id, MaskedReference__c
      FROM Inv_PortfolioAccounts__c
      WHERE Id IN :accountIds
      WITH USER_MODE
    ])
      accountLabels.put(a.Id, a.MaskedReference__c);
    for (Inv_PortfolioSipVersions__c sip : sipRecords) {
      Id fundId = fundByShareClass.get(sip.InstrumentRef__c);
      if (fundId == null)
        continue;
      Decimal amount = InvMath.exact(sip.Amount__c);
      funds.add(fundId);
      SipRow sipRow = new SipRow();
      sipRow.fundId = fundId;
      sipRow.amount = amount;
      sipRow.effectiveFrom = sip.EffectiveFrom__c;
      sipRow.effectiveTo = sip.EffectiveTo__c;
      sipRow.frequency = sip.Frequency__c;
      sipRow.accountLabel = accountLabels.get(sip.AccountRef__c);
      out.sips.add(sipRow);
    }
    Map<Id, String> instrumentNames = loadInstrumentNames(funds);
    for (HoldingRow row : out.holdings)
      row.fundName = instrumentNames.get(row.fundId);
    for (SipRow row : out.sips)
      row.fundName = instrumentNames.get(row.fundId);
    Set<Id> metricFunds = new Set<Id>();
    List<Inv_FundMetric__c> metricRecords = [
      SELECT
        Fund__c,
        Metric__c,
        Value__c,
        PeriodStart__c,
        PeriodEnd__c,
        Coverage__c,
        CounterpartyFund__c
      FROM Inv_FundMetric__c
      WHERE Fund__c IN :funds AND Published__c = TRUE
      WITH USER_MODE
      ORDER BY PeriodEnd__c DESC
      LIMIT 5000
    ];
    for (Inv_FundMetric__c metric : metricRecords) {
      metricFunds.add(metric.Fund__c);
      if (metric.CounterpartyFund__c != null)
        metricFunds.add(metric.CounterpartyFund__c);
    }
    Map<Id, String> metricNames = loadInstrumentNames(metricFunds);
    for (Inv_FundMetric__c metric : metricRecords)
      out.metrics.add(metric(metric, metricNames));
    for (Inv_Exposure__c exposure : [
      SELECT
        Fund__c,
        Dimension__c,
        Member__c,
        MemberKey__c,
        SourceLabels__c,
        Value__c,
        Weight__c,
        DisclosureDate__c,
        Coverage__c
      FROM Inv_Exposure__c
      WHERE
        Portfolio__c = :portfolio.Id
        AND Run__c = :run.Id
        AND Published__c = TRUE
      WITH USER_MODE
      ORDER BY Value__c DESC NULLS LAST
      LIMIT 5000
    ]) {
      ExposureRow row = exposure(exposure);
      row.fundName = instrumentNames.get(row.fundId);
      out.exposures.add(row);
    }
    return out;
  }

  @AuraEnabled(cacheable=true)
  public static FundData getFundResearch(Id fundId) {
    if (fundId == null)
      throw new AuraHandledException('Choose a fund to review.');
    List<Inv_MarketInstruments__c> visible = [
      SELECT
        Id,
        DisplayName__c,
        Name__c,
        Isin__c,
        AMFICode__c,
        MappingVerified__c,
        Tracked__c,
        TERPercent__c,
        BERPercent__c,
        ExpenseDate__c,
        BenchmarkVariant__c,
        PortfolioRole__c,
        ResearchNote__c
      FROM Inv_MarketInstruments__c
      WHERE Id = :fundId
      WITH USER_MODE
    ];
    if (visible.isEmpty())
      throw new AuraHandledException('The selected fund is unavailable.');
    Inv_MarketInstruments__c fund = visible[0];
    FundData out = new FundData();
    out.fundId = fund.Id;
    out.fundName = String.isBlank(fund.DisplayName__c)
      ? fund.Name__c
      : fund.DisplayName__c;
    out.isin = fund.Isin__c;
    out.amfiCode = fund.AMFICode__c;
    out.mappingVerified = fund.MappingVerified__c;
    out.tracked = fund.Tracked__c;
    out.portfolioRole = fund.PortfolioRole__c;
    out.researchNote = fund.ResearchNote__c;
    out.ter = fund.TERPercent__c;
    out.ber = fund.BERPercent__c;
    out.expenseDate = fund.ExpenseDate__c;
    out.benchmarkVariant = fund.BenchmarkVariant__c;
    Date today = Date.today();
    Id schemeId;
    Set<Id> portfolioAccountIds = new Set<Id>();
    for (Inv_PortfolioAccounts__c account : [
      SELECT Id
      FROM Inv_PortfolioAccounts__c
      WITH USER_MODE
    ])
      portfolioAccountIds.add(account.Id);
    if (!portfolioAccountIds.isEmpty())
      for (Inv_PortfolioSipVersions__c sip : [
        SELECT Amount__c, VerificationState__c, ReportedStatus__c, Frequency__c
        FROM Inv_PortfolioSipVersions__c
        WHERE
          AccountRef__c IN :portfolioAccountIds
          AND InstrumentRef__r.InstrumentRef__c = :fund.Id
          AND EffectiveFrom__c <= :today
          AND (EffectiveTo__c = NULL
          OR EffectiveTo__c > :today)
        WITH USER_MODE
      ])
        if (
          sip.VerificationState__c == 'user_confirmed' &&
          sip.ReportedStatus__c == 'active' &&
          sip.Frequency__c == 'monthly'
        )
          out.monthlySip =
            (out.monthlySip == null ? 0 : out.monthlySip) +
            InvMath.exact(sip.Amount__c);
    List<Inv_MarketFundShareClasses__c> shareClasses = [
      SELECT SchemeRef__c
      FROM Inv_MarketFundShareClasses__c
      WHERE InstrumentRef__c = :fund.Id
      WITH USER_MODE
      LIMIT 1
    ];
    if (!shareClasses.isEmpty())
      schemeId = shareClasses[0].SchemeRef__c;
    if (schemeId != null) {
      List<Inv_MarketSchemes__c> schemes = [
        SELECT AmcRef__c
        FROM Inv_MarketSchemes__c
        WHERE Id = :schemeId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!schemes.isEmpty() && schemes[0].AmcRef__c != null) {
        List<Inv_MarketAmcs__c> amcs = [
          SELECT Name__c
          FROM Inv_MarketAmcs__c
          WHERE Id = :schemes[0].AmcRef__c
          WITH USER_MODE
          LIMIT 1
        ];
        if (!amcs.isEmpty())
          out.amc = amcs[0].Name__c;
      }
      List<Inv_MarketSchemeVersions__c> schemeVersions = [
        SELECT Category__c
        FROM Inv_MarketSchemeVersions__c
        WHERE
          SchemeRef__c = :schemeId
          AND EffectiveFrom__c <= :today
          AND (EffectiveTo__c = NULL
          OR EffectiveTo__c > :today)
        WITH USER_MODE
        ORDER BY EffectiveFrom__c DESC
        LIMIT 1
      ];
      if (!schemeVersions.isEmpty())
        out.category = schemeVersions[0].Category__c;
    }
    Map<Id, Inv_MarketPriceObservations__c> latestPrice = InvNAVPolicy.latestByInstrument(
      new Set<Id>{ fund.Id },
      today,
      System.now()
    );
    if (latestPrice.containsKey(fund.Id)) {
      Inv_MarketPriceObservations__c selected = latestPrice.get(fund.Id);
      out.latestNav = InvMath.exact(selected.Value__c);
      out.navDate = selected.ObservedOn__c;
      out.navProvider = selected.ProviderRef__r == null
        ? null
        : selected.ProviderRef__r.Name__c;
    }
    Date startHistory = today.addYears(-20);
    List<Inv_MarketPriceObservations__c> historySource = [
      SELECT
        Id,
        ObservedOn__c,
        Value__c,
        PriceKind__c,
        QualityStatus__c,
        ProviderRef__r.Name__c,
        SelectedNAV__c,
        RevisionNoNumber__c,
        ReceivedAt__c
      FROM Inv_MarketPriceObservations__c
      WHERE
        InstrumentRef__c = :fund.Id
        AND ObservedOn__c >= :startHistory
        AND ObservedOn__c <= :today
        AND KindFilter__c = 'NAV'
        AND QualityFilter__c = 'accepted'
      WITH USER_MODE
      ORDER BY ObservedOn__c ASC
      LIMIT 5000
    ];
    Map<Date, Inv_MarketPriceObservations__c> selectedHistory = InvNAVPolicy.daily(
      historySource
    );
    List<Date> historyDates = new List<Date>(selectedHistory.keySet());
    historyDates.sort();
    Map<String, Date> monthEnds = new Map<String, Date>();
    for (Date d : historyDates)
      monthEnds.put(
        String.valueOf(d.year()) + '-' + String.valueOf(d.month()),
        d
      );
    List<Date> sampled = new List<Date>(monthEnds.values());
    sampled.sort();
    for (Date d : sampled) {
      ChartPoint point = new ChartPoint();
      point.day = d;
      point.value = InvMath.exact(selectedHistory.get(d).Value__c);
      out.navHistory.add(point);
    }
    List<Inv_FundPeerAssignments__c> peerAssignments = [
      SELECT
        PeerFund__c,
        EffectiveFrom__c,
        EffectiveTo__c,
        Category__c,
        ShareClassRule__c,
        Rationale__c
      FROM Inv_FundPeerAssignments__c
      WHERE
        Fund__c = :fund.Id
        AND AssignmentStatus__c = 'active'
        AND EffectiveFrom__c <= :today
        AND (EffectiveTo__c = NULL
        OR EffectiveTo__c >= :today)
      WITH USER_MODE
    ];
    Set<Id> peerFundIds = new Set<Id>();
    for (Inv_FundPeerAssignments__c a : peerAssignments)
      if (a.PeerFund__c != null)
        peerFundIds.add(a.PeerFund__c);
    Map<Id, String> peerNames = loadInstrumentNames(peerFundIds);
    for (Inv_FundPeerAssignments__c assignment : peerAssignments) {
      PeerRow peer = new PeerRow();
      peer.fundId = assignment.PeerFund__c;
      peer.fundName = peerNames.get(assignment.PeerFund__c);
      peer.category = assignment.Category__c;
      peer.effectiveFrom = assignment.EffectiveFrom__c;
      peer.effectiveTo = assignment.EffectiveTo__c;
      peer.shareClassRule = assignment.ShareClassRule__c;
      peer.rationale = assignment.Rationale__c;
      peer.coverage = 'peer_assignment_verified';
      out.peers.add(peer);
    }
    Set<Id> comparisonFunds = new Set<Id>{ fund.Id };
    comparisonFunds.addAll(peerFundIds);
    List<Inv_FundMetric__c> metricRecords = [
      SELECT
        Fund__c,
        Metric__c,
        Value__c,
        PeriodStart__c,
        PeriodEnd__c,
        Coverage__c,
        CounterpartyFund__c
      FROM Inv_FundMetric__c
      WHERE Fund__c IN :comparisonFunds AND Published__c = TRUE
      WITH USER_MODE
      ORDER BY PeriodEnd__c DESC
      LIMIT 5000
    ];
    Map<Id, String> metricNames = loadInstrumentNames(comparisonFunds);
    for (Inv_FundMetric__c m : metricRecords)
      out.metrics.add(metric(m, metricNames));
    if (schemeId != null) {
      List<Inv_MarketFundPortfolioSnapshots__c> snapshots = [
        SELECT Id, HoldingsAsOf__c, CoverageState__c
        FROM Inv_MarketFundPortfolioSnapshots__c
        WHERE SchemeRef__c = :schemeId AND HoldingsAsOf__c <= :today
        WITH USER_MODE
        ORDER BY HoldingsAsOf__c DESC, RevisionNoNumber__c DESC, Id DESC
        LIMIT 1
      ];
      if (!snapshots.isEmpty()) {
        Set<Id> snapshotIds = new Set<Id>{ snapshots[0].Id };
        List<Inv_MarketFundPortfolioPositions__c> sourcePositions = [
          SELECT
            SecurityRef__c,
            RawLabel__c,
            WeightRatio__c,
            AssetKind__c,
            Sector__c,
            MarketCapBand__c
          FROM Inv_MarketFundPortfolioPositions__c
          WHERE SnapshotRef__c IN :snapshotIds
          WITH USER_MODE
          LIMIT 3000
        ];
        Set<Id> securityIds = new Set<Id>();
        for (Inv_MarketFundPortfolioPositions__c p : sourcePositions)
          if (p.SecurityRef__c != null)
            securityIds.add(p.SecurityRef__c);
        Map<Id, String> securityNames = loadInstrumentNames(securityIds);
        for (Inv_MarketFundPortfolioPositions__c position : sourcePositions) {
          ExposureRow row = new ExposureRow();
          row.fundId = fund.Id;
          row.fundName = out.fundName;
          row.dimension = 'Security';
          row.member = securityNames.containsKey(position.SecurityRef__c)
            ? securityNames.get(position.SecurityRef__c)
            : position.RawLabel__c;
          row.memberKey = position.SecurityRef__c == null
            ? 'unmapped:' + position.RawLabel__c
            : 'id:' + position.SecurityRef__c;
          row.sourceLabels = position.RawLabel__c;
          row.value = position.WeightRatio__c == null
            ? null
            : InvMath.exact(position.WeightRatio__c);
          row.disclosureDate = snapshots[0].HoldingsAsOf__c;
          row.coverage = position.SecurityRef__c == null
            ? 'identity_unmapped'
            : snapshots[0].CoverageState__c;
          out.composition.add(row);
          addCompositionBucket(
            out,
            fund.Id,
            out.fundName,
            'Sector',
            position.Sector__c,
            position.WeightRatio__c,
            snapshots[0]
          );
          addCompositionBucket(
            out,
            fund.Id,
            out.fundName,
            'Market cap',
            position.MarketCapBand__c,
            position.WeightRatio__c,
            snapshots[0]
          );
          addCompositionBucket(
            out,
            fund.Id,
            out.fundName,
            'Asset class',
            position.AssetKind__c,
            position.WeightRatio__c,
            snapshots[0]
          );
        }
      }
    }
    Set<Id> currentRunIds = new Set<Id>();
    for (Inv_PortfolioPortfolios__c p : [
      SELECT PublishedRun__c
      FROM Inv_PortfolioPortfolios__c
      WHERE PublishedRun__c != NULL
      WITH USER_MODE
    ])
      currentRunIds.add(p.PublishedRun__c);
    Map<String, Decimal> portfolioTotals = new Map<String, Decimal>();
    for (Inv_PortfolioValuation__c total : [
      SELECT Portfolio__c, Run__c, MarketValue__c
      FROM Inv_PortfolioValuation__c
      WHERE Run__c IN :currentRunIds AND Published__c = TRUE
      WITH USER_MODE
    ])
      portfolioTotals.put(
        String.valueOf(total.Portfolio__c) + ':' + String.valueOf(total.Run__c),
        total.MarketValue__c
      );
    for (Inv_HoldingValuation__c h : [
      SELECT
        Id,
        Holding__c,
        Holding__r.Account__c,
        Holding__r.Account__r.MaskedReference__c,
        Portfolio__c,
        Run__c,
        Portfolio__r.Name__c,
        Fund__c,
        Fund__r.MappingVerified__c,
        Units__c,
        NAV__c,
        NAVDate__c,
        NAVProvider__c,
        ReconciledThrough__c,
        Cost__c,
        MarketValue__c,
        UnrealizedGain__c,
        RealizedGain__c,
        Weight__c,
        XIRR__c,
        SIPAmount__c,
        Category__c,
        AMC__c,
        Status__c,
        UnitCoverage__c,
        BasisCoverage__c,
        RedemptionCoverage__c,
        PersonalReturnCoverage__c,
        NAVCoverage__c,
        CompositionCoverage__c,
        PolicyCoverage__c,
        Coverage__c,
        Warnings__c
      FROM Inv_HoldingValuation__c
      WHERE Run__c IN :currentRunIds AND Fund__c = :fund.Id
      WITH USER_MODE
    ]) {
      HoldingRow position = holding(h);
      Decimal total = portfolioTotals.get(
        String.valueOf(h.Portfolio__c) + ':' + String.valueOf(h.Run__c)
      );
      if (
        (position.weight == null ||
        position.weight == 0) &&
        position.marketValue != null &&
        position.marketValue > 0 &&
        total != null &&
        total > 0
      )
        position.weight = position.marketValue / total;
      out.positions.add(position);
    }
    for (HoldingRow position : out.positions)
      position.fundName = out.fundName;
    out.statusMessage = out.peers.isEmpty()
      ? 'No dated peer assignments yet. Use Peer Assignments in the Investments navigation to add only the comparable funds you want to review.'
      : null;
    return out;
  }

  private static HoldingRow holding(Inv_HoldingValuation__c h) {
    HoldingRow row = new HoldingRow();
    row.holdingId = h.Holding__c;
    row.fundId = h.Fund__c;
    row.mappingVerified = h.Fund__r == null
      ? false
      : h.Fund__r.MappingVerified__c;
    row.portfolioId = h.Portfolio__c;
    row.portfolioName = h.Portfolio__r == null ? null : h.Portfolio__r.Name__c;
    if (h.getSObject('Holding__r') != null) {
      SObject parent = h.getSObject('Holding__r');
      row.accountId = (Id) parent.get('Account__c');
      SObject account = parent.getSObject('Account__r');
      if (account != null)
        row.accountLabel = (String) account.get('MaskedReference__c');
    }
    row.category = h.Category__c;
    row.amc = h.AMC__c;
    row.status = String.isBlank(h.Status__c)
      ? (h.Units__c == null ? 'Unknown' : h.Units__c == 0 ? 'Closed' : 'Active')
      : h.Status__c;
    row.units = h.Units__c;
    row.nav = h.NAV__c;
    row.navDate = h.NAVDate__c;
    row.navProvider = h.NAVProvider__c;
    row.cost = h.Cost__c;
    row.marketValue = h.MarketValue__c;
    row.unrealizedGain = h.UnrealizedGain__c;
    row.realizedGain = h.RealizedGain__c;
    row.weight = h.Weight__c;
    row.xirr = h.XIRR__c;
    row.monthlySip = h.SIPAmount__c;
    row.reconciledThrough = h.ReconciledThrough__c;
    row.unitCoverage = h.UnitCoverage__c;
    row.basisCoverage = h.BasisCoverage__c;
    row.redemptionCoverage = h.RedemptionCoverage__c;
    row.returnCoverage = h.PersonalReturnCoverage__c;
    row.navCoverage = h.NAVCoverage__c;
    row.compositionCoverage = h.CompositionCoverage__c;
    row.policyCoverage = h.PolicyCoverage__c;
    row.coverage = h.Coverage__c;
    row.warnings = h.Warnings__c;
    return row;
  }
  private static MetricRow metric(Inv_FundMetric__c m, Map<Id, String> names) {
    MetricRow row = new MetricRow();
    row.fundId = m.Fund__c;
    row.fundName = names.get(m.Fund__c);
    row.metric = m.Metric__c;
    row.value = m.Value__c;
    row.periodStart = m.PeriodStart__c;
    row.periodEnd = m.PeriodEnd__c;
    row.coverage = m.Coverage__c;
    row.comparedFundId = m.CounterpartyFund__c;
    row.comparedFundName = names.get(m.CounterpartyFund__c);
    return row;
  }
  private static ExposureRow exposure(Inv_Exposure__c e) {
    ExposureRow row = new ExposureRow();
    row.fundId = e.Fund__c;
    row.dimension = e.Dimension__c;
    row.member = e.Member__c;
    row.memberKey = e.MemberKey__c;
    row.sourceLabels = e.SourceLabels__c;
    row.value = e.Value__c;
    row.weight = e.Weight__c;
    row.disclosureDate = e.DisclosureDate__c;
    row.coverage = e.Coverage__c;
    return row;
  }
  private static void addCompositionBucket(
    FundData out,
    Id fund,
    String name,
    String dimension,
    String member,
    String exactWeight,
    Inv_MarketFundPortfolioSnapshots__c snapshot
  ) {
    if (String.isBlank(member))
      return;
    ExposureRow row = new ExposureRow();
    row.fundId = fund;
    row.fundName = name;
    row.dimension = dimension;
    row.member = member;
    row.memberKey = member;
    row.value = exactWeight == null ? null : InvMath.exact(exactWeight);
    row.weight = row.value;
    row.disclosureDate = snapshot.HoldingsAsOf__c;
    row.coverage = snapshot.CoverageState__c;
    out.composition.add(row);
  }
  private static Map<Id, String> loadInstrumentNames(Set<Id> instrumentIds) {
    Map<Id, String> result = new Map<Id, String>();
    if (instrumentIds == null || instrumentIds.isEmpty())
      return result;
    for (Inv_MarketInstruments__c instrument : [
      SELECT Id, DisplayName__c, Name__c
      FROM Inv_MarketInstruments__c
      WHERE Id IN :instrumentIds
      WITH USER_MODE
    ])
      result.put(
        instrument.Id,
        String.isBlank(instrument.DisplayName__c)
          ? instrument.Name__c
          : instrument.DisplayName__c
      );
    return result;
  }
}
