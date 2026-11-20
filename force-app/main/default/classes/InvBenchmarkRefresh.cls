public without sharing class InvBenchmarkRefresh implements Queueable, Database.AllowsCallouts {
  private static final String TRI_URL = 'callout:Inv_NSEIndices/BackPage/getTotalReturnIndexString';
  private static final String BSE_TRI_URL = 'callout:Inv_BSEIndices/AsiaIndexAPI/api/GetHistoricalPRTRData_Asia/w';
  private static final Date REQUEST_START_DATE = Date.today().addDays(-14);
  private static final Date REQUEST_END_DATE = Date.today();
  private static final Map<String, String> INDEX_NAMES = new Map<String, String>{
    'NIFTY 500 TRI' => 'Nifty 500',
    'NIFTY MIDCAP 150 TRI' => 'Nifty Midcap 150',
    'NIFTY SMALLCAP 250 TRI' => 'Nifty Smallcap 250',
    'NIFTY LARGEMIDCAP 250 TRI' => 'Nifty LargeMidcap 250'
  };
  private static final List<String> MONTHS = new List<String>{
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  };
  private static final String PROVIDER_KEY = 'ops.providers:27';
  private static final String BSE_PROVIDER_KEY = 'benchmark.provider.bse';

  public void execute(QueueableContext context) {
    Map<Id, String> benchmarks = new Map<Id, String>();
    List<String> errors = new List<String>();
    Map<String, Id> providers = new Map<String, Id>();
    for (Inv_OpsProviders__c p : [
      SELECT Id, MigrationKey__c
      FROM Inv_OpsProviders__c
      WHERE
        MigrationKey__c IN :new Set<String>{ PROVIDER_KEY, BSE_PROVIDER_KEY }
      WITH SYSTEM_MODE
    ])
      providers.put(p.MigrationKey__c, p.Id);
    for (Inv_MarketBenchmarkAssignments__c a : [
      SELECT
        BenchmarkRef__c,
        BenchmarkRef__r.Name__c,
        BenchmarkRef__r.Currency__c,
        BenchmarkRef__r.BenchmarkVariant__c,
        Role__c,
        EffectiveFrom__c,
        EffectiveTo__c
      FROM Inv_MarketBenchmarkAssignments__c
      WHERE
        EffectiveFrom__c <= :REQUEST_END_DATE
        AND (EffectiveTo__c = NULL
        OR EffectiveTo__c > :REQUEST_END_DATE)
      WITH SYSTEM_MODE
    ]) {
      if (a.Role__c != 'primary')
        continue;
      String code = a.BenchmarkRef__r.Name__c;
      if (
        a.BenchmarkRef__r.Currency__c != 'INR' ||
        a.BenchmarkRef__r.BenchmarkVariant__c != 'TRI' ||
        (code != 'BSE 500 TRI' && !INDEX_NAMES.containsKey(code))
      ) {
        errors.add('No supported official TRI feed mapping for ' + code);
        continue;
      }
      benchmarks.put(a.BenchmarkRef__c, code);
    }

    Map<Id, List<Observation>> loaded = new Map<Id, List<Observation>>();
    for (Id benchmarkId : benchmarks.keySet()) {
      String code = benchmarks.get(benchmarkId),
        providerKey = code == 'BSE 500 TRI' ? BSE_PROVIDER_KEY : PROVIDER_KEY;
      if (!providers.containsKey(providerKey)) {
        errors.add('Benchmark source provider is missing for ' + code);
        continue;
      }
      try {
        loaded.put(
          benchmarkId,
          fetch(benchmarkId, code, providers.get(providerKey))
        );
      } catch (Exception e) {
        errors.add(code + ': ' + e.getMessage());
      }
    }

    List<Inv_MarketPriceObservations__c> records = new List<Inv_MarketPriceObservations__c>();
    for (Id benchmarkId : loaded.keySet())
      for (Observation o : loaded.get(benchmarkId))
        records.add(o.row);
    Set<Id> instrumentIds = new Set<Id>();
    Set<Date> observationDates = new Set<Date>();
    for (Inv_MarketPriceObservations__c row : records) {
      instrumentIds.add(row.InstrumentRef__c);
      observationDates.add(row.ObservedOn__c);
    }
    Map<String, List<Inv_MarketPriceObservations__c>> priorByDate = new Map<String, List<Inv_MarketPriceObservations__c>>();
    if (!instrumentIds.isEmpty() && !observationDates.isEmpty())
      for (Inv_MarketPriceObservations__c prior : [
        SELECT
          Id,
          InstrumentRef__c,
          ObservedOn__c,
          Value__c,
          RevisionNo__c,
          ReceivedAt__c,
          PriceKind__c,
          QualityStatus__c
        FROM Inv_MarketPriceObservations__c
        WHERE
          InstrumentRef__c IN :instrumentIds
          AND ObservedOn__c IN :observationDates
        WITH SYSTEM_MODE
        ORDER BY ReceivedAt__c DESC, Id DESC
      ]) {
        if (prior.PriceKind__c != 'TRI' || prior.QualityStatus__c != 'accepted')
          continue;
        String identity = prior.InstrumentRef__c + '|' + prior.ObservedOn__c;
        if (!priorByDate.containsKey(identity))
          priorByDate.put(identity, new List<Inv_MarketPriceObservations__c>());
        priorByDate.get(identity).add(prior);
      }
    List<Inv_MarketPriceObservations__c> newRecords = new List<Inv_MarketPriceObservations__c>();
    for (Inv_MarketPriceObservations__c row : records) {
      List<Inv_MarketPriceObservations__c> prior = priorByDate.get(
        row.InstrumentRef__c + '|' + row.ObservedOn__c
      );
      Boolean identical = false;
      if (prior != null)
        for (Inv_MarketPriceObservations__c candidate : prior)
          if (
            InvMath.exact(candidate.Value__c) == InvMath.exact(row.Value__c)
          ) {
            identical = true;
            break;
          }
      if (identical)
        continue;
      if (prior != null && !prior.isEmpty())
        row.SupersedesRef__c = prior[0].Id;
      newRecords.add(row);
    }
    records = newRecords;
    if (!records.isEmpty()) {
      for (Inv_MarketPriceObservations__c row : records) {
        InvMath.project(row, 'Value__c', row.Value__c);
        InvMath.project(row, 'RevisionNo__c', row.RevisionNo__c);
      }
      insert as system records;
    }
    if (!errors.isEmpty())
      upsert as system new Inv_OpsDataIssues__c(
        MigrationKey__c = 'benchmark-refresh:' + REQUEST_END_DATE,
        IssueKey__c = 'Benchmark refresh ' + REQUEST_END_DATE,
        ObservedOn__c = REQUEST_END_DATE,
        Severity__c = 'warning',
        Status__c = 'open',
        Message__c = String.join(errors, '\n'),
        CreatedAt__c = System.now(),
        SourceJson__c = JSON.serialize(errors)
      )
        MigrationKey__c;
    else {
      List<Inv_OpsDataIssues__c> resolved = new List<Inv_OpsDataIssues__c>();
      for (Inv_OpsDataIssues__c issue : [
        SELECT Id, Status__c
        FROM Inv_OpsDataIssues__c
        WHERE MigrationKey__c LIKE 'benchmark-refresh:%'
        WITH SYSTEM_MODE
      ])
        if (issue.Status__c == 'open') {
          issue.Status__c = 'resolved';
          resolved.add(issue);
        }
      if (!resolved.isEmpty())
        update as system resolved;
    }
    if (!Test.isRunningTest())
      System.enqueueJob(new InvRecalculate(true));
  }

  private class Observation {
    Inv_MarketPriceObservations__c row;
  }
  private static List<Observation> fetch(
    Id instrument,
    String indexName,
    Id providerId
  ) {
    return indexName == 'BSE 500 TRI'
      ? fetchBSE(instrument, providerId)
      : fetchNSE(instrument, INDEX_NAMES.get(indexName), indexName, providerId);
  }
  private static List<Observation> fetchNSE(
    Id instrument,
    String indexName,
    String officialCode,
    Id providerId
  ) {
    String start = formatDate(REQUEST_START_DATE),
      endDate = formatDate(REQUEST_END_DATE);
    String cinfo =
      '{' +
      '\'name\':\'' +
      indexName +
      '\',\'startDate\':\'' +
      start +
      '\',\'endDate\':\'' +
      endDate +
      '\',\'indexName\':\'' +
      indexName +
      '\'}';
    HttpRequest request = new HttpRequest();
    request.setEndpoint(TRI_URL);
    request.setMethod('POST');
    request.setTimeout(30000);
    request.setHeader('Content-Type', 'application/json; charset=UTF-8');
    request.setBody(
      JSON.serialize(new Map<String, String>{ 'cinfo' => cinfo })
    );
    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200)
      throw new InvMath.CalculationException(
        'NSE Indices HTTP ' + response.getStatusCode()
      );
    Object decoded = JSON.deserializeUntyped(response.getBody());
    List<Object> rows;
    if (decoded instanceof List<Object>)
      rows = (List<Object>) decoded;
    else {
      Object body = ((Map<String, Object>) decoded).get('d');
      rows = body instanceof String
        ? (List<Object>) JSON.deserializeUntyped((String) body)
        : (List<Object>) body;
    }
    Map<Date, Map<String, Object>> unique = new Map<Date, Map<String, Object>>();
    for (Object item : rows) {
      Map<String, Object> source = (Map<String, Object>) item;
      if (
        String.valueOf(source.get('Index Name')).trim().toLowerCase() !=
        indexName.toLowerCase()
      )
        throw new InvMath.CalculationException(
          'NSE Indices returned a different index identity'
        );
      Date day = parseDate(String.valueOf(source.get('Date')));
      String value = String.valueOf(source.get('TotalReturnsIndex'));
      if (
        day < REQUEST_START_DATE ||
        day > REQUEST_END_DATE ||
        InvMath.exact(value) <= 0
      )
        throw new InvMath.CalculationException('Invalid NSE TRI date or value');
      if (
        unique.containsKey(day) &&
        InvMath.exact(
          String.valueOf(unique.get(day).get('TotalReturnsIndex'))
        ) != InvMath.exact(value)
      )
        throw new InvMath.CalculationException(
          'Conflicting NSE TRI values for one index date'
        );
      unique.put(day, source);
    }
    if (unique.isEmpty())
      throw new InvMath.CalculationException(
        'NSE Indices returned no TRI observations'
      );
    List<Observation> result = new List<Observation>();
    for (Date day : unique.keySet()) {
      Map<String, Object> source = unique.get(day);
      String value = String.valueOf(source.get('TotalReturnsIndex'));
      result.add(
        makeObservation(
          instrument,
          providerId,
          'nse-tri:',
          indexName,
          day,
          value,
          'https://www.niftyindices.com/BackPage/getTotalReturnIndexString',
          source,
          start,
          endDate
        )
      );
    }
    return result;
  }
  private static List<Observation> fetchBSE(Id instrument, Id providerId) {
    String start = formatBseDate(REQUEST_START_DATE),
      endDate = formatBseDate(REQUEST_END_DATE);
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      BSE_TRI_URL +
        '?code=17&Fromdate=' +
        start +
        '&Todate=' +
        endDate +
        '&flag=1&type=1'
    );
    request.setMethod('GET');
    request.setTimeout(30000);
    request.setHeader('Accept', 'application/json');
    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200)
      throw new InvMath.CalculationException(
        'BSE Indices HTTP ' + response.getStatusCode()
      );
    List<Object> rows = (List<Object>) JSON.deserializeUntyped(
      response.getBody()
    );
    Map<Date, Map<String, Object>> unique = new Map<Date, Map<String, Object>>();
    for (Object item : rows) {
      Map<String, Object> source = (Map<String, Object>) item;
      if (
        String.valueOf(source.get('IndexName')).trim().toLowerCase() !=
        'bse 500'
      )
        throw new InvMath.CalculationException(
          'BSE Indices returned a different index identity'
        );
      Date day = parseBseDate(String.valueOf(source.get('TransDate')));
      String value = String.valueOf(source.get('TRValue'));
      if (
        day < REQUEST_START_DATE ||
        day > REQUEST_END_DATE ||
        InvMath.exact(value) <= 0
      )
        throw new InvMath.CalculationException('Invalid BSE TRI date or value');
      if (
        unique.containsKey(day) &&
        InvMath.exact(String.valueOf(unique.get(day).get('TRValue'))) !=
        InvMath.exact(value)
      )
        throw new InvMath.CalculationException(
          'Conflicting BSE TRI values for one index date'
        );
      unique.put(day, source);
    }
    if (unique.isEmpty())
      throw new InvMath.CalculationException(
        'BSE Indices returned no TRI observations'
      );
    List<Observation> result = new List<Observation>();
    for (Date day : unique.keySet())
      result.add(
        makeObservation(
          instrument,
          providerId,
          'bse-tri:',
          'BSE 500 TRI',
          day,
          String.valueOf(unique.get(day).get('TRValue')),
          'https://www.bseindices.com/AsiaIndexAPI/api/GetHistoricalPRTRData_Asia/w?code=17&type=1',
          unique.get(day),
          start,
          endDate
        )
      );
    return result;
  }
  private static Observation makeObservation(
    Id instrument,
    Id providerId,
    String keyPrefix,
    String indexName,
    Date day,
    String value,
    String endpoint,
    Map<String, Object> source,
    String start,
    String endDate
  ) {
    String identity =
        providerId +
        '|' +
        instrument +
        '|' +
        isoDate(day) +
        '|TRI|' +
        InvMath.valueKey(value),
      raw = JSON.serialize(source),
      key = keyPrefix + InvPortfolioEngine.hash(identity);
    Inv_MarketPriceObservations__c row = new Inv_MarketPriceObservations__c(
      MigrationKey__c = key,
      ObservationKey__c = key,
      InstrumentRef__c = instrument,
      ObservedOn__c = day,
      Value__c = value,
      PriceKind__c = 'TRI',
      KindFilter__c = 'TRI',
      QualityStatus__c = 'accepted',
      QualityFilter__c = 'accepted',
      ProviderRef__c = providerId,
      ReceivedAt__c = System.now(),
      RetrievedAt__c = System.now(),
      RevisionNo__c = String.valueOf(System.now().getTime()),
      SourceHash__c = InvPortfolioEngine.hash(raw),
      SourceJson__c = JSON.serialize(
        new Map<String, Object>{
          'endpoint' => endpoint,
          'indexName' => indexName,
          'startDate' => start,
          'endDate' => endDate,
          'responseRow' => source
        }
      )
    );
    Observation observation = new Observation();
    observation.row = row;
    return observation;
  }
  private static Date parseDate(String input) {
    List<String> parts = input.trim().split(' ');
    if (parts.size() != 3)
      throw new InvMath.CalculationException('Invalid NSE TRI date');
    Integer month = MONTHS.indexOf(parts[1]) + 1;
    if (month < 1)
      throw new InvMath.CalculationException('Invalid NSE TRI month');
    return Date.newInstance(
      Integer.valueOf(parts[2]),
      month,
      Integer.valueOf(parts[0])
    );
  }
  private static String formatDate(Date value) {
    String day = value.day() < 10
      ? '0' + String.valueOf(value.day())
      : String.valueOf(value.day());
    return day +
      '-' +
      MONTHS[value.month() - 1] +
      '-' +
      String.valueOf(value.year());
  }
  private static Date parseBseDate(String input) {
    String datePart = input.trim().substringBefore(' ');
    List<String> parts = datePart.split('/');
    if (parts.size() != 3)
      throw new InvMath.CalculationException('Invalid BSE TRI date');
    return Date.newInstance(
      Integer.valueOf(parts[2]),
      Integer.valueOf(parts[0]),
      Integer.valueOf(parts[1])
    );
  }
  private static String formatBseDate(Date value) {
    String month = value.month() < 10
      ? '0' + String.valueOf(value.month())
      : String.valueOf(value.month());
    String day = value.day() < 10
      ? '0' + String.valueOf(value.day())
      : String.valueOf(value.day());
    return String.valueOf(value.year()) + month + day;
  }
  private static String isoDate(Date value) {
    String month = value.month() < 10
      ? '0' + String.valueOf(value.month())
      : String.valueOf(value.month());
    String day = value.day() < 10
      ? '0' + String.valueOf(value.day())
      : String.valueOf(value.day());
    return String.valueOf(value.year()) + '-' + month + '-' + day;
  }
}
