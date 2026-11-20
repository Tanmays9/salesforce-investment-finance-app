/**
 * Fetches and stores current NAV observations for tracked mutual funds.
 *
 * The scheduled refresh supplies the fund IDs. This queueable processes them in
 * small batches, compares MFapi and AMFI observations, records provider evidence,
 * and starts benchmark refresh after the final batch.
 */
public without sharing class InvNAVRefresh implements Queueable, Database.AllowsCallouts {
  private List<Id> funds;

  public InvNAVRefresh(List<Id> ids) {
    funds = ids;
  }

  /** Parsed provider observation held in memory until the batch is persisted. */
  public class Observation {
    public Id fund;
    public String provider;
    public String code;
    public String isin;
    public String value;
    public String raw;
    public Date day;
  }

  /** Accepts ISO (yyyy-MM-dd) and day-first (dd-MM-yyyy) provider dates. */
  public static Date parseDate(String value) {
    List<String> bits = value.split('-');
    if (bits[0].length() == 4) {
      return Date.valueOf(value);
    }
    return Date.newInstance(
      Integer.valueOf(bits[2]),
      Integer.valueOf(bits[1]),
      Integer.valueOf(bits[0])
    );
  }

  /**
   * Parses MFapi's latest-NAV response and rejects an unexpected scheme or
   * share class before its value can become an accepted observation.
   */
  @TestVisible
  static Observation parseMFAPI(String body, Inv_MarketInstruments__c fund) {
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
      body
    );
    if (root.get('status') != 'SUCCESS') {
      throw new InvMath.CalculationException(
        'MFapi returned unsuccessful status'
      );
    }

    Map<String, Object> meta = (Map<String, Object>) root.get('meta');
    if (
      String.valueOf(meta.get('scheme_code')) != fund.AMFICode__c ||
      meta.get('isin_growth') != fund.Isin__c
    ) {
      throw new InvMath.CalculationException(
        'MFapi share-class identity mismatch'
      );
    }

    String name = String.valueOf(meta.get('scheme_name')).toLowerCase();
    if (!name.contains('direct') || !name.contains('growth')) {
      throw new InvMath.CalculationException(
        'Unsupported plan/option identity'
      );
    }

    List<Object> data = (List<Object>) root.get('data');
    if (data.isEmpty()) {
      throw new InvMath.CalculationException('Missing NAV');
    }

    Map<String, Object> row = (Map<String, Object>) data[0];
    Observation observation = new Observation();
    observation.fund = fund.Id;
    observation.code = fund.AMFICode__c;
    observation.isin = fund.Isin__c;
    observation.provider = 'MFapi';
    observation.day = parseDate((String) row.get('date'));
    observation.value = (String) row.get('nav');
    observation.raw = body;

    if (
      observation.day > Date.today() ||
      InvMath.exact(observation.value) <= 0
    ) {
      throw new InvMath.CalculationException('Invalid NAV date or value');
    }
    return observation;
  }

  /**
   * Finds the fund's row in AMFI's daily NAV file. Returns null when the
   * scheme code is absent; a found row must still match the mapped ISIN.
   */
  @TestVisible
  static Observation parseAMFI(String body, Inv_MarketInstruments__c fund) {
    String prefix = '\n' + fund.AMFICode__c + ';';
    Integer index = body.indexOf(prefix);
    if (index < 0 && body.startsWith(fund.AMFICode__c + ';')) {
      index = -1;
    } else if (index < 0) {
      return null;
    }

    Integer endLine = body.indexOf('\n', index + 1);
    if (endLine < 0) {
      endLine = body.length();
    }

    String line = body.substring(index + 1, endLine).trim();
    List<String> columns = line.split(';');
    if (
      columns.size() < 6 ||
      (columns[1] != fund.Isin__c &&
      columns[2] != fund.Isin__c)
    ) {
      throw new InvMath.CalculationException(
        'AMFI share-class identity mismatch'
      );
    }

    Map<String, Integer> months = new Map<String, Integer>{
      'Jan' => 1,
      'Feb' => 2,
      'Mar' => 3,
      'Apr' => 4,
      'May' => 5,
      'Jun' => 6,
      'Jul' => 7,
      'Aug' => 8,
      'Sep' => 9,
      'Oct' => 10,
      'Nov' => 11,
      'Dec' => 12
    };
    List<String> dateParts = columns[columns.size() - 1].split('-');

    Observation observation = new Observation();
    observation.fund = fund.Id;
    observation.code = fund.AMFICode__c;
    observation.isin = fund.Isin__c;
    observation.provider = 'AMFI';
    observation.day = Date.newInstance(
      Integer.valueOf(dateParts[2]),
      months.get(dateParts[1]),
      Integer.valueOf(dateParts[0])
    );
    observation.value = columns[columns.size() - 2];
    observation.raw = line;

    if (
      observation.day > Date.today() ||
      InvMath.exact(observation.value) <= 0
    ) {
      throw new InvMath.CalculationException('Invalid AMFI NAV');
    }
    return observation;
  }

  /** Performs a GET through a configured Salesforce Named Credential. */
  private static String fetch(String endpoint) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(endpoint);
    request.setMethod('GET');
    request.setTimeout(30000);

    HttpResponse response = new Http().send(request);
    if (response.getStatusCode() != 200) {
      throw new InvMath.CalculationException(
        'Provider HTTP ' + response.getStatusCode()
      );
    }
    return response.getBody();
  }

  public void execute(QueueableContext context) {
    // Keep callouts bounded; the next queueable continues with the remaining funds.
    List<Id> portion = new List<Id>();
    List<Id> remaining = new List<Id>();
    for (Integer i = 0; i < funds.size(); i++) {
      if (i < 10) {
        portion.add(funds[i]);
      } else {
        remaining.add(funds[i]);
      }
    }

    List<Inv_MarketInstruments__c> instruments = [
      SELECT Id, AMFICode__c, Isin__c, MappingVerified__c
      FROM Inv_MarketInstruments__c
      WHERE Id IN :portion
      WITH SYSTEM_MODE
    ];
    List<Observation> observed = new List<Observation>();
    List<String> errors = new List<String>();
    String amfi;

    // AMFI is fetched once for the batch; MFapi is then queried per scheme.
    try {
      amfi = fetch('callout:Inv_AMFI/spages/NAVAll.txt');
    } catch (Exception e) {
      errors.add('AMFI unavailable: ' + e.getMessage());
    }

    for (Inv_MarketInstruments__c fund : instruments) {
      if (!fund.MappingVerified__c || String.isBlank(fund.AMFICode__c)) {
        errors.add('Unverified mapping: ' + fund.Id);
        continue;
      }

      Observation mf;
      Observation official;
      try {
        mf = parseMFAPI(
          fetch('callout:Inv_MFapi/mf/' + fund.AMFICode__c + '/latest'),
          fund
        );
        observed.add(mf);
      } catch (Exception e) {
        errors.add('MFapi ' + fund.Id + ': ' + e.getMessage());
      }

      if (amfi != null) {
        try {
          official = parseAMFI(amfi, fund);
          if (official != null) {
            observed.add(official);
          }
        } catch (Exception e) {
          errors.add('AMFI ' + fund.Id + ': ' + e.getMessage());
        }
      }

      // A same-date mismatch is visible as an issue; AMFI is selected during persistence.
      if (
        mf != null &&
        official != null &&
        mf.day == official.day &&
        InvMath.exact(mf.value) != InvMath.exact(official.value)
      ) {
        errors.add(
          'NAV source discrepancy ' +
            fund.Id +
            ' ' +
            mf.day +
            '; official AMFI selected'
        );
      }
    }

    persist(observed);

    // One valid provider observation is enough to mark this fund's attempt accepted.
    Set<Id> acceptedFunds = new Set<Id>();
    for (Observation observation : observed) {
      acceptedFunds.add(observation.fund);
    }

    List<Inv_MarketInstruments__c> attempts = new List<Inv_MarketInstruments__c>();
    for (Inv_MarketInstruments__c fund : instruments) {
      attempts.add(
        new Inv_MarketInstruments__c(
          Id = fund.Id,
          NAVAttemptAt__c = System.now(),
          NAVRefreshStatus__c = acceptedFunds.contains(fund.Id)
            ? 'Accepted'
            : 'Failed'
        )
      );
    }
    if (!attempts.isEmpty()) {
      update as system attempts;
    }

    if (!errors.isEmpty()) {
      Inv_OpsDataIssues__c issue = new Inv_OpsDataIssues__c(
        MigrationKey__c = 'nav-job:' + context.getJobId(),
        IssueKey__c = 'NAV refresh ' + context.getJobId(),
        ObservedOn__c = Date.today(),
        Severity__c = 'warning',
        Status__c = 'open',
        Message__c = String.join(errors, '\n'),
        CreatedAt__c = System.now(),
        SourceJson__c = JSON.serialize(errors)
      );
      insert as system issue;
    }

    if (!remaining.isEmpty()) {
      System.enqueueJob(new InvNAVRefresh(remaining));
    } else if (!Test.isRunningTest()) {
      // Benchmark refresh starts only after every NAV batch has finished.
      System.enqueueJob(new InvBenchmarkRefresh());
    }
  }

  /**
   * Upserts provider identities and observations, then marks one preferred NAV
   * per instrument/date. The observation key makes repeated values idempotent.
   */
  @TestVisible
  private static void persist(List<Observation> observed) {
    Map<String, Id> providers = new Map<String, Id>();
    for (String name : new List<String>{ 'MFapi', 'AMFI' }) {
      Inv_OpsProviders__c provider = new Inv_OpsProviders__c(
        MigrationKey__c = 'operational:provider:' + name,
        Name__c = name,
        Kind__c = 'nav_feed'
      );
      upsert as system provider MigrationKey__c;
      providers.put(name, provider.Id);
    }

    List<Inv_MarketPriceObservations__c> rows = new List<Inv_MarketPriceObservations__c>();
    for (Observation observation : observed) {
      String key =
        observation.provider +
        ':' +
        observation.fund +
        ':' +
        String.valueOf(observation.day) +
        ':' +
        InvPortfolioEngine.hash(InvMath.valueKey(observation.value));
      rows.add(
        new Inv_MarketPriceObservations__c(
          MigrationKey__c = 'nav:' + InvPortfolioEngine.hash(key),
          ObservationKey__c = key,
          InstrumentRef__c = observation.fund,
          ObservedOn__c = observation.day,
          Value__c = observation.value,
          PriceKind__c = 'NAV',
          QualityStatus__c = 'accepted',
          KindFilter__c = 'NAV',
          QualityFilter__c = 'accepted',
          ProviderRef__c = providers.get(observation.provider),
          ReceivedAt__c = System.now(),
          RetrievedAt__c = System.now(),
          RevisionNo__c = String.valueOf(System.now().getTime()),
          SourceJson__c = JSON.serialize(observation)
        )
      );
    }

    // Keep exact source text; write numeric projections only when representable.
    for (Inv_MarketPriceObservations__c row : rows) {
      InvMath.project(row, 'Value__c', row.Value__c);
      InvMath.project(row, 'RevisionNo__c', row.RevisionNo__c);
    }

    Set<String> keys = new Set<String>();
    for (Inv_MarketPriceObservations__c row : rows) {
      keys.add(row.ObservationKey__c);
    }

    Set<String> existing = new Set<String>();
    for (Inv_MarketPriceObservations__c row : [
      SELECT ObservationKey__c
      FROM Inv_MarketPriceObservations__c
      WHERE ObservationKey__c IN :keys
      WITH SYSTEM_MODE
    ]) {
      existing.add(row.ObservationKey__c);
    }

    List<Inv_MarketPriceObservations__c> fresh = new List<Inv_MarketPriceObservations__c>();
    for (Inv_MarketPriceObservations__c row : rows) {
      if (!existing.contains(row.ObservationKey__c)) {
        fresh.add(row);
      }
    }
    if (!fresh.isEmpty()) {
      upsert as system fresh ObservationKey__c;
    }

    Set<Id> fundIds = new Set<Id>();
    Set<Date> days = new Set<Date>();
    for (Observation observation : observed) {
      fundIds.add(observation.fund);
      days.add(observation.day);
    }

    // Prefer AMFI when provider rows share a date; query ordering picks the newest row per provider.
    Map<String, Inv_MarketPriceObservations__c> chosen = new Map<String, Inv_MarketPriceObservations__c>();
    List<Inv_MarketPriceObservations__c> candidates = [
      SELECT
        Id,
        InstrumentRef__c,
        ObservedOn__c,
        ProviderRef__r.Name__c,
        SelectedNAV__c
      FROM Inv_MarketPriceObservations__c
      WHERE
        InstrumentRef__c IN :fundIds
        AND ObservedOn__c IN :days
        AND KindFilter__c = 'NAV'
        AND QualityFilter__c = 'accepted'
      WITH SYSTEM_MODE
      ORDER BY ReceivedAt__c DESC, RevisionNoNumber__c DESC, Id DESC
    ];
    for (Inv_MarketPriceObservations__c row : candidates) {
      String identity = row.InstrumentRef__c + ':' + row.ObservedOn__c;
      if (
        !chosen.containsKey(identity) ||
        (row.ProviderRef__r.Name__c == 'AMFI' &&
        chosen.get(identity).ProviderRef__r.Name__c != 'AMFI')
      ) {
        chosen.put(identity, row);
      }
    }

    List<Inv_MarketPriceObservations__c> changed = new List<Inv_MarketPriceObservations__c>();
    for (Inv_MarketPriceObservations__c row : candidates) {
      Boolean selected =
        chosen.get(row.InstrumentRef__c + ':' + row.ObservedOn__c).Id == row.Id;
      if (selected != row.SelectedNAV__c) {
        changed.add(
          new Inv_MarketPriceObservations__c(
            Id = row.Id,
            SelectedNAV__c = selected
          )
        );
      }
    }
    if (!changed.isEmpty()) {
      update as system changed;
    }
  }
}
