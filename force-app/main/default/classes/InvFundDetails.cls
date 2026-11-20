public without sharing class InvFundDetails {
  public class Details {
    public List<Inv_FundMetric__c> metrics = new List<Inv_FundMetric__c>();
    public String fingerprint;
  }
  public static Details calculate(Id fund, Date asOf) {
    Details result = new Details();
    Set<Id> funds = new Set<Id>{ fund };
    for (Inv_MarketInstruments__c instrument : [
      SELECT Id
      FROM Inv_MarketInstruments__c
      WHERE Tracked__c = TRUE
      WITH SYSTEM_MODE
    ])
      funds.add(instrument.Id);
    Map<Id, Id> schemes = new Map<Id, Id>();
    Id shareClass;
    for (Inv_MarketFundShareClasses__c c : [
      SELECT Id, InstrumentRef__c, SchemeRef__c
      FROM Inv_MarketFundShareClasses__c
      WHERE InstrumentRef__c IN :funds
      WITH SYSTEM_MODE
    ]) {
      if (c.SchemeRef__c != null)
        schemes.put(c.InstrumentRef__c, c.SchemeRef__c);
      if (c.InstrumentRef__c == fund)
        shareClass = c.Id;
    }
    List<Inv_MarketExpenseObservations__c> expenses = shareClass == null
      ? new List<Inv_MarketExpenseObservations__c>()
      : [
          SELECT Id, ObservedOn__c, TerRatio__c, BerRatio__c, DocumentRef__c
          FROM Inv_MarketExpenseObservations__c
          WHERE
            InstrumentRef__c = :shareClass
            AND ObservedOn__c <= :asOf
            AND (EffectiveTo__c = NULL
            OR EffectiveTo__c > :asOf)
          WITH SYSTEM_MODE
          ORDER BY ObservedOn__c DESC, ReceivedAt__c DESC, Id DESC
          LIMIT 1
        ];
    Inv_MarketInstruments__c summary = new Inv_MarketInstruments__c(Id = fund);
    summary.LatestTER__c = null;
    summary.LatestBER__c = null;
    summary.ExpenseDate__c = null;
    summary.ExpenseEvidence__c = null;
    if (!expenses.isEmpty()) {
      Inv_MarketExpenseObservations__c e = expenses[0];
      summary.LatestTER__c = InvMath.exact(e.TerRatio__c);
      summary.LatestBER__c = InvMath.exact(e.BerRatio__c);
      summary.ExpenseDate__c = e.ObservedOn__c;
      summary.ExpenseEvidence__c = e.Id;
    }
    update as system summary;
    Set<Id> schemeIds = new Set<Id>(schemes.values());
    Map<Id, Inv_MarketFundPortfolioSnapshots__c> snapshots = new Map<Id, Inv_MarketFundPortfolioSnapshots__c>();
    for (Inv_MarketFundPortfolioSnapshots__c snapshot : [
      SELECT Id, SchemeRef__c, HoldingsAsOf__c, WeightBasis__c, CoverageState__c
      FROM Inv_MarketFundPortfolioSnapshots__c
      WHERE SchemeRef__c IN :schemeIds AND HoldingsAsOf__c <= :asOf
      WITH SYSTEM_MODE
      ORDER BY HoldingsAsOf__c DESC, RevisionNoNumber__c DESC, Id DESC
    ])
      if (!snapshots.containsKey(snapshot.SchemeRef__c))
        snapshots.put(snapshot.SchemeRef__c, snapshot);
    Set<Id> snapshotIds = new Set<Id>();
    for (Inv_MarketFundPortfolioSnapshots__c s : snapshots.values())
      snapshotIds.add(s.Id);
    Map<Id, Map<Id, Decimal>> weights = new Map<Id, Map<Id, Decimal>>();
    Set<Id> unmapped = new Set<Id>();
    for (Inv_MarketFundPortfolioPositions__c p : [
      SELECT SnapshotRef__c, SecurityRef__c, WeightRatio__c, AssetKind__c
      FROM Inv_MarketFundPortfolioPositions__c
      WHERE SnapshotRef__c IN :snapshotIds
      WITH SYSTEM_MODE
    ]) {
      if (p.AssetKind__c != 'equity')
        continue;
      if (p.SecurityRef__c == null || p.WeightRatio__c == null) {
        unmapped.add(p.SnapshotRef__c);
        continue;
      }
      if (!weights.containsKey(p.SnapshotRef__c))
        weights.put(p.SnapshotRef__c, new Map<Id, Decimal>());
      Map<Id, Decimal> basket = weights.get(p.SnapshotRef__c);
      basket.put(
        p.SecurityRef__c,
        (basket.containsKey(p.SecurityRef__c)
          ? basket.get(p.SecurityRef__c)
          : 0) + InvMath.exact(p.WeightRatio__c)
      );
    }
    Inv_MarketFundPortfolioSnapshots__c own = snapshots.get(schemes.get(fund));
    for (Id other : funds)
      if (other != fund) {
        Inv_MarketFundPortfolioSnapshots__c compared = snapshots.get(
          schemes.get(other)
        );
        Decimal overlap;
        String coverage = 'missing_composition';
        if (own != null && compared != null) {
          if (
            own.HoldingsAsOf__c != compared.HoldingsAsOf__c ||
            own.WeightBasis__c != compared.WeightBasis__c ||
            own.WeightBasis__c == null ||
            own.WeightBasis__c.toLowerCase().contains('gross')
          )
            coverage = 'incompatible_snapshots';
          else if (
            !weights.containsKey(own.Id) || !weights.containsKey(compared.Id)
          )
            coverage = 'insufficient_security_mapping';
          else {
            overlap = 0;
            Map<Id, Decimal> a = weights.get(own.Id),
              b = weights.get(compared.Id);
            for (Id security : a.keySet())
              if (b.containsKey(security))
                overlap += a.get(security) < b.get(security)
                  ? a.get(security)
                  : b.get(security);
            coverage = unmapped.contains(own.Id) ||
              unmapped.contains(compared.Id)
              ? 'partial_mapped_equities'
              : 'mapped_equities_reported_nav_weights';
          }
        }
        result.metrics.add(
          new Inv_FundMetric__c(
            Name = 'Mapped equity overlap',
            Metric__c = 'Mapped equity overlap',
            Fund__c = fund,
            CounterpartyFund__c = other,
            Disclosure__c = own == null ? null : own.Id,
            ComparedDisclosure__c = compared == null ? null : compared.Id,
            PeriodStart__c = own == null ? null : own.HoldingsAsOf__c,
            PeriodEnd__c = compared == null ? null : compared.HoldingsAsOf__c,
            Value__c = overlap,
            Coverage__c = coverage,
            Published__c = true
          )
        );
      }
    result.fingerprint = InvPortfolioEngine.hash(
      JSON.serialize(expenses) +
        InvExposureEngine.fingerprint(funds, asOf) +
        JSON.serialize(funds)
    );
    return result;
  }
}
