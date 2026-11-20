@IsTest
private class InvFundDetailsTest {
  @IsTest
  static void comparisonsRequireEvidenceAndMatchingDates() {
    Date d = Date.newInstance(2024, 1, 1);
    Inv_MarketInstruments__c fund = new Inv_MarketInstruments__c(
      MigrationKey__c = 'details:fund',
      Tracked__c = true
    );
    Inv_MarketInstruments__c other = new Inv_MarketInstruments__c(
      MigrationKey__c = 'details:other',
      Tracked__c = true
    );
    Inv_MarketInstruments__c security = new Inv_MarketInstruments__c(
      MigrationKey__c = 'details:security'
    );
    Inv_MarketInstruments__c benchmark = new Inv_MarketInstruments__c(
      MigrationKey__c = 'details:benchmark',
      BenchmarkVariant__c = 'TRI'
    );
    insert new List<Inv_MarketInstruments__c>{
      fund,
      other,
      security,
      benchmark
    };
    Inv_MarketSchemes__c scheme = new Inv_MarketSchemes__c(
      MigrationKey__c = 'details:scheme'
    );
    Inv_MarketSchemes__c second = new Inv_MarketSchemes__c(
      MigrationKey__c = 'details:second'
    );
    insert new List<Inv_MarketSchemes__c>{ scheme, second };
    Inv_MarketFundShareClasses__c share = new Inv_MarketFundShareClasses__c(
      MigrationKey__c = 'details:share',
      InstrumentRef__c = fund.Id,
      SchemeRef__c = scheme.Id
    );
    insert new List<Inv_MarketFundShareClasses__c>{
      share,
      new Inv_MarketFundShareClasses__c(
        MigrationKey__c = 'details:share2',
        InstrumentRef__c = other.Id,
        SchemeRef__c = second.Id
      )
    };
    insert new Inv_MarketExpenseObservations__c(
      MigrationKey__c = 'details:expense',
      InstrumentRef__c = share.Id,
      ObservedOn__c = d,
      TerRatio__c = '0.005',
      BerRatio__c = '0.004'
    );
    Inv_MarketFundPortfolioSnapshots__c a = new Inv_MarketFundPortfolioSnapshots__c(
      MigrationKey__c = 'details:a',
      SchemeRef__c = scheme.Id,
      HoldingsAsOf__c = d,
      WeightBasis__c = 'net_assets',
      CoverageState__c = 'complete'
    );
    Inv_MarketFundPortfolioSnapshots__c b = new Inv_MarketFundPortfolioSnapshots__c(
      MigrationKey__c = 'details:b',
      SchemeRef__c = second.Id,
      HoldingsAsOf__c = d,
      WeightBasis__c = 'net_assets',
      CoverageState__c = 'partial'
    );
    insert new List<Inv_MarketFundPortfolioSnapshots__c>{ a, b };
    insert new List<Inv_MarketFundPortfolioPositions__c>{
      new Inv_MarketFundPortfolioPositions__c(
        MigrationKey__c = 'details:p1',
        SnapshotRef__c = a.Id,
        SecurityRef__c = security.Id,
        AssetKind__c = 'equity',
        WeightRatio__c = '0.4'
      ),
      new Inv_MarketFundPortfolioPositions__c(
        MigrationKey__c = 'details:p2',
        SnapshotRef__c = b.Id,
        SecurityRef__c = security.Id,
        AssetKind__c = 'equity',
        WeightRatio__c = '0.3'
      ),
      new Inv_MarketFundPortfolioPositions__c(
        MigrationKey__c = 'details:p3',
        SnapshotRef__c = b.Id,
        AssetKind__c = 'equity',
        WeightRatio__c = '0.2'
      ),
      new Inv_MarketFundPortfolioPositions__c(
        MigrationKey__c = 'details:p4',
        SnapshotRef__c = b.Id,
        AssetKind__c = 'cash',
        WeightRatio__c = '-0.01'
      )
    };
    InvFundDetails.Details detail = InvFundDetails.calculate(fund.Id, d);
    Assert.areEqual(0.3, detail.metrics[0].Value__c);
    Assert.areEqual('partial_mapped_equities', detail.metrics[0].Coverage__c);
    Assert.areEqual(
      0.005,
      [SELECT LatestTER__c FROM Inv_MarketInstruments__c WHERE Id = :fund.Id]
      .LatestTER__c
    );
    List<Inv_Exposure__c> exposures = InvExposureEngine.build(
      null,
      null,
      d,
      new List<Inv_Holding__c>{
        new Inv_Holding__c(
          Fund__c = other.Id,
          Units__c = 1,
          MarketValue__c = 1000
        )
      },
      1000
    );
    Boolean negativePreserved = false;
    for (Inv_Exposure__c exposure : exposures)
      if (
        exposure.Dimension__c == 'Asset class' &&
        exposure.Member__c == 'cash'
      ) {
        Assert.areEqual(-10, exposure.Value__c);
        negativePreserved = true;
      }
    Assert.isTrue(negativePreserved);
    List<Inv_PlanImpact__c> impacts = InvPlanExposure.compare(
      null,
      null,
      null,
      d,
      new Map<Id, Decimal>{ other.Id => 1000 },
      new Map<Id, Decimal>{ other.Id => 500 },
      1000,
      500
    );
    Boolean cashPreserved = false;
    for (Inv_PlanImpact__c impact : impacts)
      if (impact.Member__c == 'Scenario cash') {
        Assert.areEqual(500, impact.Proposed__c);
        cashPreserved = true;
      }
    Assert.isTrue(cashPreserved);
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Inv_Exposure__c],
      'Scenario exposure must not publish or mutate actual exposures'
    );
    b.HoldingsAsOf__c = d.addDays(-1);
    update b;
    Assert.areEqual(
      'incompatible_snapshots',
      InvFundDetails.calculate(fund.Id, d).metrics[0].Coverage__c
    );
    Map<Date, Decimal> navs = new Map<Date, Decimal>{
      d => 100,
      d.addMonths(1) => 110
    };
    Assert.areEqual(
      'benchmark_assignment_and_verified_history_required',
      InvBenchmarkEngine.calculate(fund.Id, navs, d.addMonths(1))
        .metrics[0]
        .Coverage__c
    );
    Inv_OpsSourceDocuments__c document = new Inv_OpsSourceDocuments__c(
      MigrationKey__c = 'details:document'
    );
    insert document;
    Inv_MarketBenchmarkAssignments__c assignment = new Inv_MarketBenchmarkAssignments__c(
      MigrationKey__c = 'details:assignment',
      SchemeRef__c = scheme.Id,
      BenchmarkRef__c = benchmark.Id,
      Role__c = 'primary',
      EffectiveFrom__c = d,
      DocumentRef__c = document.Id
    );
    insert assignment;
    insert new List<Inv_MarketPriceObservations__c>{
      new Inv_MarketPriceObservations__c(
        MigrationKey__c = 'details:tri1',
        InstrumentRef__c = benchmark.Id,
        ObservedOn__c = d,
        Value__c = '200',
        PriceKind__c = 'TRI',
        QualityStatus__c = 'accepted'
      ),
      new Inv_MarketPriceObservations__c(
        MigrationKey__c = 'details:tri2',
        InstrumentRef__c = benchmark.Id,
        ObservedOn__c = d.addMonths(1),
        Value__c = '210',
        PriceKind__c = 'TRI',
        QualityStatus__c = 'accepted'
      )
    };
    InvBenchmarkEngine.Comparison compared = InvBenchmarkEngine.calculate(
      fund.Id,
      navs,
      d.addMonths(1)
    );
    Assert.areEqual(0.1, compared.metrics[0].Value__c);
    Assert.areEqual(0.05, compared.metrics[1].Value__c);
    Assert.areEqual(0.05, compared.metrics[2].Value__c);
    benchmark.BenchmarkVariant__c = 'price';
    update benchmark;
    Assert.areEqual(
      'total_return_benchmark_required',
      InvBenchmarkEngine.calculate(fund.Id, navs, d.addMonths(1))
        .metrics[0]
        .Coverage__c
    );
  }
}
