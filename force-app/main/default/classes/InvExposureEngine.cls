public without sharing class InvExposureEngine {
  public static String fingerprint(Set<Id> funds, Date asOf) {
    Set<Id> schemes = new Set<Id>();
    for (Inv_MarketFundShareClasses__c c : [
      SELECT SchemeRef__c
      FROM Inv_MarketFundShareClasses__c
      WHERE InstrumentRef__c IN :funds
      WITH SYSTEM_MODE
    ])
      schemes.add(c.SchemeRef__c);
    Set<Id> snapshotIds = new Set<Id>();
    Set<Id> seen = new Set<Id>();
    List<Inv_MarketFundPortfolioSnapshots__c> snapshots = [
      SELECT Id, SchemeRef__c, HoldingsAsOf__c, CoverageState__c, WeightBasis__c
      FROM Inv_MarketFundPortfolioSnapshots__c
      WHERE SchemeRef__c IN :schemes AND HoldingsAsOf__c <= :asOf
      WITH SYSTEM_MODE
      ORDER BY HoldingsAsOf__c DESC, RevisionNoNumber__c DESC, Id DESC
      LIMIT 5000
    ];
    if (snapshots.size() == 5000)
      throw new InvMath.CalculationException(
        'Fund-disclosure history exceeds the calculation scope.'
      );
    List<Inv_MarketFundPortfolioSnapshots__c> chosen = new List<Inv_MarketFundPortfolioSnapshots__c>();
    for (Inv_MarketFundPortfolioSnapshots__c snapshot : snapshots)
      if (!seen.contains(snapshot.SchemeRef__c)) {
        chosen.add(snapshot);
        snapshotIds.add(snapshot.Id);
        seen.add(snapshot.SchemeRef__c);
      }
    List<Inv_MarketFundPortfolioPositions__c> positions = [
      SELECT
        Id,
        SnapshotRef__c,
        SecurityRef__c,
        RawLabel__c,
        WeightRatio__c,
        AssetKind__c,
        Sector__c,
        MarketCapBand__c,
        ClassificationAsOf__c
      FROM Inv_MarketFundPortfolioPositions__c
      WHERE SnapshotRef__c IN :snapshotIds
      WITH SYSTEM_MODE
      ORDER BY Id
      LIMIT 20000
    ];
    if (positions.size() == 20000)
      throw new InvMath.CalculationException(
        'Fund-disclosure positions exceed the calculation scope.'
      );
    return InvPortfolioEngine.hash(
      JSON.serialize(chosen) + JSON.serialize(positions)
    );
  }
  public static List<Inv_Exposure__c> build(
    Id portfolio,
    Id run,
    Date asOf,
    List<Inv_Holding__c> holdings,
    Decimal total
  ) {
    Map<Id, Decimal> fundValues = new Map<Id, Decimal>();
    for (Inv_Holding__c h : holdings)
      if (h.Units__c > 0 && h.MarketValue__c != null)
        fundValues.put(
          h.Fund__c,
          (fundValues.containsKey(h.Fund__c) ? fundValues.get(h.Fund__c) : 0) +
          h.MarketValue__c
        );
    Map<Id, Id> fundSchemes = new Map<Id, Id>();
    for (Inv_MarketFundShareClasses__c c : [
      SELECT InstrumentRef__c, SchemeRef__c
      FROM Inv_MarketFundShareClasses__c
      WHERE InstrumentRef__c IN :fundValues.keySet()
      WITH SYSTEM_MODE
    ])
      fundSchemes.put(c.InstrumentRef__c, c.SchemeRef__c);
    Map<Id, Inv_MarketFundPortfolioSnapshots__c> snapshots = new Map<Id, Inv_MarketFundPortfolioSnapshots__c>();
    Set<Id> schemes = new Set<Id>(fundSchemes.values());
    List<Inv_MarketFundPortfolioSnapshots__c> snapshotRows = [
      SELECT Id, SchemeRef__c, HoldingsAsOf__c, CoverageState__c, WeightBasis__c
      FROM Inv_MarketFundPortfolioSnapshots__c
      WHERE SchemeRef__c IN :schemes AND HoldingsAsOf__c <= :asOf
      WITH SYSTEM_MODE
      ORDER BY HoldingsAsOf__c DESC, RevisionNoNumber__c DESC, Id DESC
      LIMIT 5000
    ];
    if (snapshotRows.size() == 5000)
      throw new InvMath.CalculationException(
        'Fund-disclosure history exceeds the calculation scope.'
      );
    for (Inv_MarketFundPortfolioSnapshots__c s : snapshotRows)
      if (!snapshots.containsKey(s.SchemeRef__c))
        snapshots.put(s.SchemeRef__c, s);
    Set<Id> snapIds = new Set<Id>();
    for (Inv_MarketFundPortfolioSnapshots__c s : snapshots.values())
      snapIds.add(s.Id);
    Map<Id, List<Inv_MarketFundPortfolioPositions__c>> positions = new Map<Id, List<Inv_MarketFundPortfolioPositions__c>>();
    List<Inv_MarketFundPortfolioPositions__c> positionRows = [
      SELECT
        SnapshotRef__c,
        SecurityRef__c,
        RawLabel__c,
        WeightRatio__c,
        AssetKind__c,
        Sector__c,
        MarketCapBand__c
      FROM Inv_MarketFundPortfolioPositions__c
      WHERE SnapshotRef__c IN :snapIds
      WITH SYSTEM_MODE
      LIMIT 20000
    ];
    if (positionRows.size() == 20000)
      throw new InvMath.CalculationException(
        'Fund-disclosure positions exceed the calculation scope.'
      );
    for (Inv_MarketFundPortfolioPositions__c p : positionRows) {
      if (!positions.containsKey(p.SnapshotRef__c))
        positions.put(
          p.SnapshotRef__c,
          new List<Inv_MarketFundPortfolioPositions__c>()
        );
      positions.get(p.SnapshotRef__c).add(p);
    }
    Set<Id> securityIds = new Set<Id>();
    for (
      List<Inv_MarketFundPortfolioPositions__c> positionGroup : positions.values()
    )
      for (Inv_MarketFundPortfolioPositions__c position : positionGroup)
        if (position.SecurityRef__c != null)
          securityIds.add(position.SecurityRef__c);
    Map<Id, String> securityNames = new Map<Id, String>();
    for (Inv_MarketInstruments__c security : [
      SELECT Id, DisplayName__c, Name__c
      FROM Inv_MarketInstruments__c
      WHERE Id IN :securityIds
      WITH SYSTEM_MODE
    ])
      securityNames.put(
        security.Id,
        String.isBlank(security.DisplayName__c)
          ? security.Name__c
          : security.DisplayName__c
      );
    Map<String, Inv_Exposure__c> rows = new Map<String, Inv_Exposure__c>();
    for (Id fund : fundValues.keySet()) {
      Inv_MarketFundPortfolioSnapshots__c snapshot = snapshots.get(
        fundSchemes.get(fund)
      );
      if (snapshot == null || !positions.containsKey(snapshot.Id)) {
        for (Inv_Holding__c holding : holdings)
          if (holding.Fund__c == fund)
            holding.CompositionCoverage__c = 'missing_disclosure';
        add(
          rows,
          portfolio,
          run,
          fund,
          'Coverage',
          'Missing composition',
          fundValues.get(fund),
          null,
          'unavailable'
        );
        continue;
      }
      Boolean unmapped = false;
      for (Inv_MarketFundPortfolioPositions__c p : positions.get(snapshot.Id)) {
        Decimal weight = InvMath.exact(p.WeightRatio__c);
        if (weight == null) {
          add(
            rows,
            portfolio,
            run,
            fund,
            'Coverage',
            'Missing weight',
            null,
            snapshot.HoldingsAsOf__c,
            'partial'
          );
          continue;
        }
        Decimal value = fundValues.get(fund) * weight;
        add(
          rows,
          portfolio,
          run,
          fund,
          'Asset class',
          p.AssetKind__c,
          value,
          snapshot.HoldingsAsOf__c,
          snapshot.CoverageState__c
        );
        add(
          rows,
          portfolio,
          run,
          fund,
          'Sector',
          p.Sector__c,
          value,
          snapshot.HoldingsAsOf__c,
          snapshot.CoverageState__c
        );
        add(
          rows,
          portfolio,
          run,
          fund,
          'Market cap',
          p.MarketCapBand__c,
          value,
          snapshot.HoldingsAsOf__c,
          snapshot.CoverageState__c
        );
        // Verified identities combine aliases; unmapped source labels stay separate to avoid false merges.
        String identity = p.SecurityRef__c == null
          ? 'unmapped:' + String.valueOf(p.RawLabel__c)
          : 'security:' + String.valueOf(p.SecurityRef__c);
        String label = p.SecurityRef__c == null
          ? p.RawLabel__c
          : securityNames.get(p.SecurityRef__c);
        if (p.SecurityRef__c == null)
          unmapped = true;
        add(
          rows,
          portfolio,
          run,
          fund,
          'Security',
          label,
          value,
          snapshot.HoldingsAsOf__c,
          p.SecurityRef__c == null
            ? 'identity_unmapped'
            : snapshot.CoverageState__c,
          identity,
          p.RawLabel__c
        );
      }
      for (Inv_Holding__c holding : holdings)
        if (holding.Fund__c == fund)
          holding.CompositionCoverage__c = unmapped
            ? 'partially_mapped'
            : snapshot.CoverageState__c;
    }
    for (Inv_Exposure__c e : rows.values())
      e.Weight__c = total == null ||
        total == 0 ||
        e.Value__c == null
        ? null
        : e.Value__c / total;
    return rows.values();
  }
  public static void calculate(
    Id portfolio,
    Id run,
    Date asOf,
    List<Inv_Holding__c> holdings,
    Decimal total
  ) {
    List<Inv_Exposure__c> values = build(portfolio, run, asOf, holdings, total);
    for (Inv_Exposure__c row : values)
      InvMath.capture(row);
    List<Inv_Exposure__c> prior = [
      SELECT Id, Published__c
      FROM Inv_Exposure__c
      WHERE Portfolio__c = :portfolio AND Published__c = TRUE AND Run__c != :run
      WITH SYSTEM_MODE
    ];
    for (Inv_Exposure__c e : prior)
      e.Published__c = false;
    update as system prior;
    if (!values.isEmpty())
      upsert as system values Key__c;
  }
  private static void add(
    Map<String, Inv_Exposure__c> rows,
    Id portfolio,
    Id run,
    Id fund,
    String dimension,
    String member,
    Decimal value,
    Date day,
    String coverage
  ) {
    add(
      rows,
      portfolio,
      run,
      fund,
      dimension,
      member,
      value,
      day,
      coverage,
      'label:' + String.valueOf(member),
      member
    );
  }
  private static void add(
    Map<String, Inv_Exposure__c> rows,
    Id portfolio,
    Id run,
    Id fund,
    String dimension,
    String member,
    Decimal value,
    Date day,
    String coverage,
    String identity,
    String sourceLabel
  ) {
    member = String.isBlank(member) ? 'Unclassified' : member;
    String k = InvPortfolioEngine.hash(
      run + ':' + fund + ':' + dimension + ':' + identity
    );
    if (!rows.containsKey(k))
      rows.put(
        k,
        new Inv_Exposure__c(
          Key__c = k,
          Name = (dimension + ': ' + member).left(80),
          Portfolio__c = portfolio,
          Fund__c = fund,
          Run__c = run,
          Dimension__c = dimension,
          Member__c = member.left(255),
          MemberKey__c = identity.left(255),
          SourceLabels__c = sourceLabel,
          Value__c = value,
          DisclosureDate__c = day,
          Coverage__c = coverage.left(255),
          Published__c = true
        )
      );
    else {
      Inv_Exposure__c existing = rows.get(k);
      if (value != null)
        existing.Value__c =
          (existing.Value__c == null ? 0 : existing.Value__c) + value;
      if (
        !String.isBlank(sourceLabel) &&
        !String.valueOf(existing.SourceLabels__c)
          .split(';')
          .contains(sourceLabel)
      )
        existing.SourceLabels__c = (String.isBlank(existing.SourceLabels__c)
            ? sourceLabel
            : (existing.SourceLabels__c + '; ' + sourceLabel))
          .left(32768);
    }
  }
}
