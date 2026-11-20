/** Explains a selected portfolio value change using dated snapshots and posted unit movements. */
public with sharing class InvMovementService {
  public class MovementRow {
    @AuraEnabled
    public String rowKey;
    @AuraEnabled
    public Id fundId;
    @AuraEnabled
    public String fundName;
    @AuraEnabled
    public String accountLabel;
    @AuraEnabled
    public Decimal openingUnits;
    @AuraEnabled
    public Decimal closingUnits;
    @AuraEnabled
    public Decimal valueChange;
    @AuraEnabled
    public Decimal marketMovement;
    @AuraEnabled
    public Decimal purchases;
    @AuraEnabled
    public Decimal redemptions;
    @AuraEnabled
    public Decimal otherUnitMovements;
    @AuraEnabled
    public Decimal reconciliationAdjustment;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String coverage;
  }
  public class MovementResult {
    @AuraEnabled
    public Id portfolioId;
    @AuraEnabled
    public Id openingRunId;
    @AuraEnabled
    public Id closingRunId;
    @AuraEnabled
    public Date openingDate;
    @AuraEnabled
    public Date closingDate;
    @AuraEnabled
    public Decimal openingValue;
    @AuraEnabled
    public Decimal closingValue;
    @AuraEnabled
    public Decimal valueChange;
    @AuraEnabled
    public Decimal marketMovement;
    @AuraEnabled
    public Decimal purchases;
    @AuraEnabled
    public Decimal redemptions;
    @AuraEnabled
    public Decimal otherUnitMovements;
    @AuraEnabled
    public Decimal reconciliationAdjustment;
    @AuraEnabled
    public Decimal residual;
    @AuraEnabled
    public String coverage;
    @AuraEnabled
    public List<MovementRow> rows = new List<MovementRow>();
  }
  private class State {
    Id accountId;
    Id fundId;
    String accountLabel;
    Decimal units = 0;
    Decimal value;
    Decimal nav;
    Boolean conflict = false;
    Boolean valueMissing = false;
    Boolean unitsMissing = false;
  }
  public class MovementException extends Exception {
  }

  @AuraEnabled(cacheable=true)
  public static MovementResult compare(
    Id portfolioId,
    Id openingRunId,
    Id closingRunId
  ) {
    if (
      portfolioId == null ||
      openingRunId == null ||
      closingRunId == null ||
      openingRunId == closingRunId
    )
      throw new AuraHandledException(
        'Choose two different dated portfolio valuations.'
      );
    Set<Id> runIds = new Set<Id>{ openingRunId, closingRunId };
    List<Inv_PortfolioValuation__c> valuations = [
      SELECT
        Id,
        Portfolio__c,
        Run__c,
        AsOf__c,
        MarketValue__c,
        LatestForDate__c,
        Run__r.Status__c,
        Run__r.LedgerCutoff__c,
        Run__r.KnowledgeCutoff__c
      FROM Inv_PortfolioValuation__c
      WHERE
        Portfolio__c = :portfolioId
        AND Run__c IN :runIds
        AND LatestForDate__c = TRUE
      WITH USER_MODE
    ];
    Map<Id, Inv_PortfolioValuation__c> byRun = new Map<Id, Inv_PortfolioValuation__c>();
    for (Inv_PortfolioValuation__c value : valuations)
      byRun.put(value.Run__c, value);
    Inv_PortfolioValuation__c opening = byRun.get(openingRunId),
      closing = byRun.get(closingRunId);
    if (
      opening == null ||
      closing == null ||
      opening.Run__r.Status__c != 'complete' ||
      closing.Run__r.Status__c != 'complete'
    )
      throw new AuraHandledException(
        'Both selected records must be complete dated portfolio valuations.'
      );
    if (opening.AsOf__c >= closing.AsOf__c)
      throw new AuraHandledException(
        'The opening valuation must precede the closing valuation.'
      );
    if (opening.MarketValue__c == null || closing.MarketValue__c == null)
      throw new AuraHandledException(
        'Both selected valuations need known portfolio values before movement attribution.'
      );
    if (
      closing.Run__r.LedgerCutoff__c == null ||
      closing.Run__r.KnowledgeCutoff__c == null
    )
      throw new AuraHandledException(
        'The closing historical run has no source cutoffs, so ledger movement cannot be safely attributed.'
      );

    MovementResult result = new MovementResult();
    result.portfolioId = portfolioId;
    result.openingRunId = openingRunId;
    result.closingRunId = closingRunId;
    result.openingDate = opening.AsOf__c;
    result.closingDate = closing.AsOf__c;
    result.openingValue = opening.MarketValue__c;
    result.closingValue = closing.MarketValue__c;
    result.valueChange = opening.MarketValue__c == null ||
      closing.MarketValue__c == null
      ? null
      : closing.MarketValue__c - opening.MarketValue__c;
    Map<String, State> begins = loadStates(portfolioId, openingRunId),
      ends = loadStates(portfolioId, closingRunId);
    Set<String> keys = new Set<String>();
    keys.addAll(begins.keySet());
    keys.addAll(ends.keySet());
    Set<Id> accounts = new Set<Id>(), funds = new Set<Id>();
    for (State state : begins.values()) {
      if (state.accountId != null)
        accounts.add(state.accountId);
      if (state.fundId != null)
        funds.add(state.fundId);
    }
    for (State state : ends.values()) {
      if (state.accountId != null)
        accounts.add(state.accountId);
      if (state.fundId != null)
        funds.add(state.fundId);
    }
    Map<String, Decimal> ledgerUnits = new Map<String, Decimal>(),
      buyUnits = new Map<String, Decimal>(),
      sellUnits = new Map<String, Decimal>(),
      otherUnits = new Map<String, Decimal>();
    if (!accounts.isEmpty() && !funds.isEmpty()) {
      List<Inv_PortfolioUnitEntries__c> entries = [
        SELECT
          Id,
          AccountRef__c,
          InstrumentRef__c,
          UnitsDelta__c,
          EventRef__c,
          EventRef__r.EventType__c,
          EventRef__r.EventDate__c,
          EventRef__r.PostedAt__c,
          EventRef__r.CreatedDate,
          EventRef__r.SourceSequenceNumber__c
        FROM Inv_PortfolioUnitEntries__c
        WHERE
          AccountRef__c IN :accounts
          AND InstrumentRef__c IN :funds
          AND EventRef__r.EventDate__c > :opening.AsOf__c
          AND EventRef__r.EventDate__c <= :closing.AsOf__c
          AND EventRef__r.PostedAt__c != NULL
          AND EventRef__r.PostedAt__c <= :closing.Run__r.LedgerCutoff__c
          AND EventRef__r.CreatedDate <= :closing.Run__r.KnowledgeCutoff__c
        WITH USER_MODE
        ORDER BY
          EventRef__r.EventDate__c,
          EventRef__r.SourceSequenceNumber__c,
          Id
        LIMIT 30000
      ];
      if (entries.size() == 30000)
        throw new AuraHandledException(
          'The selected period has more ledger rows than this analysis can safely reconcile. Shorten the date range.'
        );
      Set<Id> eventIds = new Set<Id>();
      for (Inv_PortfolioUnitEntries__c entry : entries)
        eventIds.add(entry.EventRef__c);
      Set<Id> reversed = new Set<Id>();
      if (!eventIds.isEmpty())
        for (Inv_PortfolioEvents__c reversal : [
          SELECT ReversesRef__c
          FROM Inv_PortfolioEvents__c
          WHERE
            ReversesRef__c IN :eventIds
            AND PostedAt__c != NULL
            AND PostedAt__c <= :closing.Run__r.LedgerCutoff__c
            AND CreatedDate <= :closing.Run__r.KnowledgeCutoff__c
            AND EventDate__c > :opening.AsOf__c
            AND EventDate__c <= :closing.AsOf__c
          WITH USER_MODE
        ])
          reversed.add(reversal.ReversesRef__c);
      for (Inv_PortfolioUnitEntries__c entry : entries) {
        if (reversed.contains(entry.EventRef__c))
          continue;
        String key = pair(entry.AccountRef__c, entry.InstrumentRef__c);
        Decimal delta = InvMath.exact(entry.UnitsDelta__c);
        if (delta == null)
          continue;
        ledgerUnits.put(
          key,
          (ledgerUnits.containsKey(key) ? ledgerUnits.get(key) : 0) + delta
        );
        String kind = entry.EventRef__r.EventType__c == null
          ? ''
          : entry.EventRef__r.EventType__c.toLowerCase();
        if (
          (kind.contains('purchase') ||
          kind == 'buy' ||
          kind == 'subscription') && delta > 0
        )
          buyUnits.put(
            key,
            (buyUnits.containsKey(key) ? buyUnits.get(key) : 0) + delta
          );
        else if ((kind.contains('redemption') || kind == 'sell') && delta < 0)
          sellUnits.put(
            key,
            (sellUnits.containsKey(key) ? sellUnits.get(key) : 0) + delta
          );
        else
          otherUnits.put(
            key,
            (otherUnits.containsKey(key) ? otherUnits.get(key) : 0) + delta
          );
      }
    }
    Map<Id, Inv_MarketPriceObservations__c> openingPrices = InvNAVPolicy.latestByInstrument(
      funds,
      opening.AsOf__c,
      opening.Run__r.KnowledgeCutoff__c
    );
    Map<Id, Inv_MarketPriceObservations__c> closingPrices = InvNAVPolicy.latestByInstrument(
      funds,
      closing.AsOf__c,
      closing.Run__r.KnowledgeCutoff__c
    );
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
    Decimal market = 0,
      buyValue = 0,
      sellValue = 0,
      otherValue = 0,
      adjustment = 0;
    Boolean complete = true,
      marketKnown = true,
      buyKnown = true,
      sellKnown = true,
      otherKnown = true,
      adjustmentKnown = true;
    for (String key : keys) {
      State start = begins.get(key), finish = ends.get(key);
      Id fundId = finish == null ? start.fundId : finish.fundId;
      State exemplar = finish == null ? start : finish;
      Decimal startUnits = start == null ? 0 : start.units,
        endUnits = finish == null ? 0 : finish.units;
      Decimal startValue = start == null ? 0 : start.value,
        endValue = finish == null ? 0 : finish.value;
      Decimal startNav = start == null ? null : start.nav,
        endNav = finish == null ? null : finish.nav;
      if (
        fundId != null &&
        startNav == null &&
        openingPrices.containsKey(fundId)
      )
        startNav = InvMath.exact(openingPrices.get(fundId).Value__c);
      if (fundId != null && endNav == null && closingPrices.containsKey(fundId))
        endNav = InvMath.exact(closingPrices.get(fundId).Value__c);
      Boolean stateConflict =
        (start != null && start.conflict) ||
        (finish != null && finish.conflict);
      Boolean stateValueMissing =
        (start != null && start.valueMissing) ||
        (finish != null && finish.valueMissing);
      Boolean stateUnitsMissing =
        (start != null && start.unitsMissing) ||
        (finish != null && finish.unitsMissing);
      MovementRow row = new MovementRow();
      row.fundId = fundId;
      row.fundName = fundNames.get(fundId);
      row.accountLabel = exemplar.accountLabel;
      row.rowKey = key;
      row.openingUnits = startUnits;
      row.closingUnits = endUnits;
      row.valueChange = stateValueMissing
        ? null
        : (startValue == null ||
            endValue == null
            ? null
            : endValue - startValue);
      Decimal observedUnits = endUnits - startUnits,
        periodUnits = ledgerUnits.containsKey(key) ? ledgerUnits.get(key) : 0;
      if (endNav != null) {
        row.purchases =
          (buyUnits.containsKey(key) ? buyUnits.get(key) : 0) * endNav;
        row.redemptions =
          -(sellUnits.containsKey(key) ? sellUnits.get(key) : 0) * endNav;
        row.otherUnitMovements =
          (otherUnits.containsKey(key) ? otherUnits.get(key) : 0) * endNav;
        row.reconciliationAdjustment = (observedUnits - periodUnits) * endNav;
        if (startUnits == 0)
          row.marketMovement = 0;
        else if (startNav != null)
          row.marketMovement = startUnits * (endNav - startNav);
      }
      if (row.valueChange != null)
        row.residual =
          row.valueChange -
          (row.marketMovement == null ? 0 : row.marketMovement) -
          (row.purchases == null ? 0 : row.purchases) +
          (row.redemptions == null ? 0 : row.redemptions) -
          (row.otherUnitMovements == null ? 0 : row.otherUnitMovements) -
          (row.reconciliationAdjustment == null
            ? 0
            : row.reconciliationAdjustment);
      Boolean partial =
        row.valueChange == null ||
        row.marketMovement == null ||
        endNav == null ||
        stateConflict ||
        stateValueMissing ||
        stateUnitsMissing;
      if (partial) {
        row.coverage = 'partial_with_residual';
        complete = false;
      } else if (row.reconciliationAdjustment != 0)
        row.coverage = 'attributed_with_reconciliation_adjustment';
      else
        row.coverage = 'complete_period_attribution';
      result.rows.add(row);
      if (row.marketMovement != null)
        market += row.marketMovement;
      else
        marketKnown = false;
      if (row.purchases != null)
        buyValue += row.purchases;
      else
        buyKnown = false;
      if (row.redemptions != null)
        sellValue += row.redemptions;
      else
        sellKnown = false;
      if (row.otherUnitMovements != null)
        otherValue += row.otherUnitMovements;
      else
        otherKnown = false;
      if (row.reconciliationAdjustment != null)
        adjustment += row.reconciliationAdjustment;
      else
        adjustmentKnown = false;
    }
    result.marketMovement = marketKnown ? market : null;
    result.purchases = buyKnown ? buyValue : null;
    result.redemptions = sellKnown ? sellValue : null;
    result.otherUnitMovements = otherKnown ? otherValue : null;
    result.reconciliationAdjustment = adjustmentKnown ? adjustment : null;
    result.residual = result.valueChange == null
      ? null
      : result.valueChange -
        market -
        buyValue +
        sellValue -
        otherValue -
        adjustment;
    if (keys.isEmpty() && result.valueChange != 0)
      complete = false;
    result.coverage = complete
      ? (result.residual != null &&
          result.residual.abs() > 0.01
          ? 'period_attribution_available_with_residual'
          : 'period_attribution_available')
      : 'partial_period_attribution_residual_includes_unvalued_movements';
    return result;
  }
  private static Map<String, State> loadStates(Id portfolioId, Id runId) {
    Map<String, State> states = new Map<String, State>();
    List<Inv_HoldingValuation__c> source = [
      SELECT
        Id,
        Holding__r.Account__c,
        Holding__r.Account__r.MaskedReference__c,
        Fund__c,
        Units__c,
        NAV__c,
        MarketValue__c
      FROM Inv_HoldingValuation__c
      WHERE Portfolio__c = :portfolioId AND Run__c = :runId
      WITH USER_MODE
      LIMIT 20000
    ];
    if (source.size() == 20000)
      throw new AuraHandledException(
        'The selected valuation has too many positions for a safe movement comparison.'
      );
    for (Inv_HoldingValuation__c row : source) {
      Id accountId = row.Holding__r == null ? null : row.Holding__r.Account__c;
      String key = accountId == null ||
        row.Fund__c == null
        ? 'unknown:' + row.Id
        : pair(accountId, row.Fund__c);
      State state = states.get(key);
      if (state == null) {
        state = new State();
        state.accountId = accountId;
        state.fundId = row.Fund__c;
        state.accountLabel = row.Holding__r == null ||
          row.Holding__r.Account__r == null
          ? null
          : row.Holding__r.Account__r.MaskedReference__c;
        states.put(key, state);
      }
      if (row.Units__c == null)
        state.unitsMissing = true;
      else
        state.units += row.Units__c;
      if (row.MarketValue__c == null)
        state.valueMissing = true;
      state.value =
        (state.value == null ? 0 : state.value) +
        (row.MarketValue__c == null ? 0 : row.MarketValue__c);
      if (row.NAV__c != null) {
        if (state.nav != null && state.nav != row.NAV__c)
          state.conflict = true;
        state.nav = row.NAV__c;
      }
    }
    return states;
  }
  private static String pair(Id accountId, Id fundId) {
    return String.valueOf(accountId) + ':' + String.valueOf(fundId);
  }
}
