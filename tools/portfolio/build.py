"""Reproducible native Salesforce operational metadata; contains no portfolio data."""
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'investment-migration'))
from prepare import ROOT, xml, NS
import xml.etree.ElementTree as ET

DEST=ROOT/'force-app/main/default'

def text(label,length=255): return {'label':label,'length':length,'type':'Text'}
def long(label): return {'label':label,'length':32768,'visibleLines':3,'type':'LongTextArea'}
def number(label,scale=6): return {'label':label,'precision':18,'scale':scale,'type':'Number'}
def date(label): return {'label':label,'type':'Date'}
def lookup(label,target,relation): return {'deleteConstraint':'Restrict','label':label,'referenceTo':target,'relationshipLabel':relation,'relationshipName':relation,'type':'Lookup'}
def check(label): return {'defaultValue':False,'label':label,'type':'Checkbox'}
def percent(label,source):return {'formula':'IF(ISBLANK('+source+'), NULL, '+source+')','formulaTreatBlanksAs':'BlankAsBlank','label':label,'precision':18,'scale':2,'type':'Percent'}
def currency(label,source,text_source=False):
 formula='IF(ISNUMBER('+source+'), ROUND(VALUE('+source+'), 2), NULL)' if text_source else 'IF(ISBLANK('+source+'), NULL, ROUND('+source+', 2))'
 return {'formula':formula,'formulaTreatBlanksAs':'BlankAsBlank','label':label,'precision':18,'scale':2,'type':'Currency'}

KEY={**text('Operational key',200),'externalId':True,'unique':True,'required':True}
RUN=lookup('Analysis run','Inv_AnalyticsRuns__c','OperationalResults')
PORT=lookup('Portfolio','Inv_PortfolioPortfolios__c','OperationalHoldings')
FUND=lookup('Fund','Inv_MarketInstruments__c','OperationalHoldings')
COMMON={'Key__c':KEY,'ExactValues__c':long('Exact calculated values')}
OBJECTS={
 'Inv_Holding__c':('Holding','Holdings',{
  'Portfolio__c':PORT,'Account__c':lookup('Investment account','Inv_PortfolioAccounts__c','Holdings'),
  'Fund__c':FUND,'FundDisplayName__c':{'formula':'IF(ISBLANK(Fund__r.DisplayName__c), Fund__r.Name, Fund__r.DisplayName__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Fund name','type':'Text'},
  'Category__c':text('Fund category'),'AMC__c':text('AMC'),
  'Units__c':number('Remaining units',8),'Cost__c':number('Remaining cost INR'),'CostDisplay__c':currency('Remaining cost (INR)','Cost__c'),
  'NAV__c':number('Selected NAV',10),'NAVDisplay__c':currency('Selected NAV (INR per unit)','NAV__c'),'NAVDate__c':date('NAV date'),'NAVProvider__c':text('NAV provider',80),'ReconciledThrough__c':date('Transactions reconciled through'),
  'MarketValue__c':number('Market value INR'),'MarketValueDisplay__c':currency('Market value (INR)','MarketValue__c'),
  'UnrealizedGain__c':number('Unrealized gain INR'),'UnrealizedGainDisplay__c':currency('Unrealized gain (INR)','UnrealizedGain__c'),
  'RealizedGain__c':number('Realized gain INR'),'RealizedGainDisplay__c':currency('Realized gain (INR)','RealizedGain__c'),'XIRR__c':number('Personal XIRR',10),
  'Weight__c':number('Portfolio weight',10),'SIPAmount__c':number('Monthly SIP INR'),'SIPAmountDisplay__c':currency('Monthly SIP (INR)','SIPAmount__c'),
  'XIRRDisplay__c':percent('Personal XIRR percent','XIRR__c'),'WeightDisplay__c':percent('Portfolio weight percent','Weight__c'),
  'Status__c':text('Position status',40),'Coverage__c':text('Calculation coverage'),
  'Warnings__c':long('Review notes'),'Run__c':RUN,
  'ReturnPercent__c':{'formula':'IF(OR(ISBLANK(Cost__c),Cost__c = 0), NULL, UnrealizedGain__c / Cost__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Unrealized return','precision':18,'scale':2,'type':'Percent'},
 }),
 'Inv_HoldingValuation__c':('Holding valuation','Holding Valuations',{
  'Holding__c':lookup('Holding','Inv_Holding__c','Valuations'),'Portfolio__c':PORT,'Fund__c':FUND,'Run__c':RUN,
  'AsOf__c':date('Valuation date'),'NAVDate__c':date('NAV date'),'NAVProvider__c':text('NAV provider',80),'ReconciledThrough__c':date('Transactions reconciled through'),'Units__c':number('Units',8),
  'NAV__c':number('NAV',10),'NAVDisplay__c':currency('NAV (INR per unit)','NAV__c'),'Cost__c':number('Remaining cost INR'),
  'CostDisplay__c':currency('Remaining cost (INR)','Cost__c'),'MarketValue__c':number('Market value INR'),
  'MarketValueDisplay__c':currency('Market value (INR)','MarketValue__c'),'UnrealizedGain__c':number('Unrealized gain INR'),
  'UnrealizedGainDisplay__c':currency('Unrealized gain (INR)','UnrealizedGain__c'),'RealizedGain__c':number('Realized gain INR'),
  'SIPAmount__c':number('Monthly SIP INR'),'SIPAmountDisplay__c':currency('Monthly SIP (INR)','SIPAmount__c'),
  'XIRR__c':number('Personal XIRR',10),'XIRRDisplay__c':percent('Personal XIRR percent','XIRR__c'),
  'Category__c':text('Fund category'),'AMC__c':text('AMC'),'FundDisplayName__c':{'formula':'IF(ISBLANK(Fund__r.DisplayName__c), Fund__r.Name, Fund__r.DisplayName__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Fund name','type':'Text'},
  'Weight__c':number('Portfolio weight',10),'WeightDisplay__c':percent('Portfolio weight percent','Weight__c'),
  'Status__c':text('Position status',40),'Warnings__c':long('Review notes'),
  'UnitCoverage__c':text('Unit reconciliation',40),'BasisCoverage__c':text('Acquisition-basis coverage',40),
  'RedemptionCoverage__c':text('Redemption-proceeds coverage',40),'PersonalReturnCoverage__c':text('Personal-return coverage',40),
  'NAVCoverage__c':text('NAV freshness',40),'CompositionCoverage__c':text('Composition coverage',40),'PolicyCoverage__c':text('Policy coverage',40),
  'Coverage__c':text('Coverage'),'Published__c':check('Published'),
 }),
 'Inv_PortfolioValuation__c':('Portfolio valuation','Portfolio Valuations',{
  'Portfolio__c':PORT,'Run__c':RUN,'AsOf__c':date('Valuation date'),'EarliestNAV__c':date('Earliest NAV date'),
  'LatestNAV__c':date('Latest NAV date'),'MarketValue__c':number('Market value INR'),
  'MarketValueDisplay__c':currency('Market value (INR)','MarketValue__c'),
  'Cost__c':number('Remaining cost INR'),'CostDisplay__c':currency('Remaining cost (INR)','Cost__c'),
  'UnrealizedGain__c':number('Unrealized gain INR'),'UnrealizedGainDisplay__c':currency('Unrealized gain (INR)','UnrealizedGain__c'),
  'RealizedGain__c':number('Realized gain INR'),'RealizedGainDisplay__c':currency('Realized gain (INR)','RealizedGain__c'),'XIRR__c':number('Portfolio XIRR',10),
  'MonthlySIP__c':number('Monthly SIP INR'),'MonthlySIPDisplay__c':currency('Monthly SIP (INR)','MonthlySIP__c'),'HoldingCount__c':number('Active positions',0),
  'XIRRDisplay__c':percent('Portfolio XIRR percent','XIRR__c'),
  'Coverage__c':long('Coverage and review notes'),'Published__c':check('Published'),'LatestForDate__c':check('Latest valuation for date'),'InputHash__c':text('Input fingerprint',64),
 }),
 'Inv_Exposure__c':('Exposure','Exposures',{
  'Portfolio__c':PORT,'Fund__c':FUND,'Run__c':RUN,'Dimension__c':text('Dimension',60),
  'Member__c':text('Exposure member'),'MemberKey__c':text('Canonical member identity',255),'SourceLabels__c':long('Observed source labels'),
  'Value__c':number('Attributed value INR'),'ValueDisplay__c':currency('Attributed value (INR)','Value__c'),
  'Weight__c':number('Portfolio weight',10),'DisclosureDate__c':date('Disclosure date'),
  'Coverage__c':text('Coverage'),'Published__c':check('Published'),
 }),
 'Inv_FundMetric__c':('Fund metric','Fund Metrics',{
  'Fund__c':FUND,'FundDisplayName__c':{'formula':'IF(ISBLANK(Fund__r.DisplayName__c), Fund__r.Name, Fund__r.DisplayName__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Fund name','type':'Text'},
  'Run__c':RUN,'Metric__c':text('Metric',80),'PeriodStart__c':date('Period start'),
  'PeriodEnd__c':date('Period end'),'Value__c':number('Value',10),'Coverage__c':text('Coverage'),
  'Benchmark__c':lookup('Benchmark','Inv_MarketInstruments__c','FundComparisons'),'Published__c':check('Published'),
  'CounterpartyFund__c':lookup('Compared fund','Inv_MarketInstruments__c','OverlapComparisons'),
  'CounterpartyFundDisplayName__c':{'formula':'IF(ISBLANK(CounterpartyFund__r.DisplayName__c), CounterpartyFund__r.Name, CounterpartyFund__r.DisplayName__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Compared fund name','type':'Text'},
  'Disclosure__c':lookup('Fund disclosure','Inv_MarketFundPortfolioSnapshots__c','FundMetricEvidence'),
  'ComparedDisclosure__c':lookup('Compared disclosure','Inv_MarketFundPortfolioSnapshots__c','ComparedMetricEvidence'),
  'ValuePercent__c':percent('Metric percent','Value__c'),'SampleCount__c':number('Observation count',0),
  'Minimum__c':number('Minimum observed value',10),'LowerQuartile__c':number('25th percentile',10),
  'Median__c':number('Median',10),'UpperQuartile__c':number('75th percentile',10),'Maximum__c':number('Maximum observed value',10),
  'AnnualizedVolatility__c':number('Annualized volatility',10),'DrawdownPeak__c':date('Drawdown peak date'),
  'DrawdownTrough__c':date('Drawdown trough date'),'RecoveredOn__c':date('Drawdown recovery date'),
  'RecoveryDays__c':number('Recovery days',0),'Methodology__c':text('Metric methodology',255),
 }),
 'Inv_PlanImpact__c':('Plan impact','Plan Impacts',{
  'PlanVersion__c':lookup('Plan version','Inv_PlanningPlanVersions__c','Impacts'),'Run__c':RUN,'Fund__c':FUND,
  'Scope__c':text('Scope',100),'Metric__c':text('Metric',100),'Baseline__c':number('Current'),
  'BaselineCurrencyDisplay__c':currency('Current amount (INR)','Baseline__c'),
  'Dimension__c':text('Exposure dimension',60),'Member__c':text('Exposure member'),
  'Proposed__c':number('Proposed'),'ProposedCurrencyDisplay__c':currency('Proposed amount (INR)','Proposed__c'),
  'Coverage__c':text('Coverage'),'Notes__c':long('Assumptions and warnings'),'Published__c':check('Published'),
 }),
 'Inv_FundPeerAssignments__c':('Peer assignment','Peer assignments',{
  'Fund__c':lookup('Fund','Inv_MarketInstruments__c','FundPeerAssignments'),'PeerFund__c':lookup('Peer fund','Inv_MarketInstruments__c','PeerAssignments'),
  'SchemeVersion__c':lookup('Category evidence','Inv_MarketSchemeVersions__c','PeerAssignments'),
  'EffectiveFrom__c':date('Effective from'),'EffectiveTo__c':date('Effective to'),
  'AssignmentStatus__c':text('Assignment status',40),'Category__c':text('Peer category'),
  'ShareClassRule__c':text('Share-class comparison rule',80),'Rationale__c':long('Selection rationale'),
 }),
 'Inv_RedemptionEstimates__c':('Redemption estimate','Redemption estimates',{
  'Portfolio__c':PORT,'PlanVersion__c':lookup('Plan version','Inv_PlanningPlanVersions__c','RedemptionEstimates'),
  'AnalysisRun__c':RUN,'Action__c':lookup('Plan action','Inv_PlanningActions__c','RedemptionEstimates'),
  'Account__c':lookup('Investment account','Inv_PortfolioAccounts__c','RedemptionEstimates'),'Fund__c':FUND,
  'ValuationAsOf__c':date('Valuation date'),'RequestedUnits__c':number('Requested units',8),
  'GrossProceeds__c':number('Estimated gross proceeds INR'),'GrossProceedsDisplay__c':currency('Estimated gross proceeds (INR)','GrossProceeds__c'),
  'CostBasis__c':number('Estimated cost basis INR'),'CostBasisDisplay__c':currency('Estimated cost basis (INR)','CostBasis__c'),
  'ExitLoad__c':number('Estimated exit load INR'),'ExitLoadDisplay__c':currency('Estimated exit load (INR)','ExitLoad__c'),
  'RealizedGain__c':number('Estimated realized gain INR'),'RealizedGainDisplay__c':currency('Estimated realized gain (INR)','RealizedGain__c'),
  'EstimatedTax__c':number('Estimated tax INR'),'EstimatedTaxDisplay__c':currency('Estimated tax (INR)','EstimatedTax__c'),
  'NetProceeds__c':number('Estimated net proceeds INR'),'NetProceedsDisplay__c':currency('Estimated net proceeds (INR)','NetProceeds__c'),
  'EligibilityCoverage__c':text('Eligibility coverage',40),'BasisCoverage__c':text('Cost-basis coverage',40),
  'ProceedsCoverage__c':text('Proceeds coverage',40),'LoadCoverage__c':text('Exit-load coverage',40),
  'TaxCoverage__c':text('Tax coverage',40),'SettlementDate__c':date('Assumed settlement date'),
  'Assumptions__c':long('Assumptions and evidence'),'Published__c':check('Published'),
 }),
 'Inv_RedemptionLotAllocations__c':('Redemption lot allocation','Redemption lot allocations',{
  'Estimate__c':lookup('Redemption estimate','Inv_RedemptionEstimates__c','LotAllocations'),
  'Account__c':lookup('Investment account','Inv_PortfolioAccounts__c','RedemptionLotAllocations'),'Fund__c':FUND,
  'AcquiredOn__c':date('Acquisition date'),'EligibleOn__c':date('Eligible date'),'RequestedUnits__c':number('Allocated units',8),
  'UnitCost__c':number('Acquisition cost per unit INR',10),'CostBasis__c':number('Allocated cost basis INR'),
  'GrossProceeds__c':number('Allocated gross proceeds INR'),'ExitLoad__c':number('Allocated exit load INR'),
  'RealizedGain__c':number('Allocated realized gain INR'),'Eligibility__c':text('Eligibility status',40),
  'Coverage__c':text('Coverage',40),'Evidence__c':lookup('Eligibility evidence','Inv_MarketEligibilityPolicies__c','RedemptionLotAllocations'),
 }),
}

AUX_OBJECTS={
 'Inv_WatchlistItems__c':('Watchlist item','Watchlist',{
  'AssetType__c':{'label':'Asset type','type':'Picklist','valueSet':{'restricted':True,'valueSetDefinition':{'sorted':True,'value':[{'fullName':v,'default':False,'label':v} for v in ['Stock','Mutual Fund','ETF']]}}},
  'Symbol__c':text('Ticker or symbol',40),'Exchange__c':{'label':'Exchange','type':'Picklist','valueSet':{'restricted':True,'valueSetDefinition':{'sorted':True,'value':[{'fullName':v,'default':False,'label':v} for v in ['NSE','BSE','Other']]}}},
  'ISIN__c':text('ISIN',20),'SchemeCode__c':text('AMFI scheme code',20),
  'Fund__c':lookup('Linked mutual fund','Inv_MarketInstruments__c','WatchlistItems'),
  'Active__c':{'defaultValue':True,'label':'On watchlist','type':'Checkbox'},
  'AddedOn__c':date('Added on'),'Notes__c':long('Notes'),
 })
}

DISPLAY_FIELDS={
 'Inv_Holding__c':{'Cost__c':'CostDisplay__c','NAV__c':'NAVDisplay__c','MarketValue__c':'MarketValueDisplay__c','UnrealizedGain__c':'UnrealizedGainDisplay__c','RealizedGain__c':'RealizedGainDisplay__c','SIPAmount__c':'SIPAmountDisplay__c'},
 'Inv_HoldingValuation__c':{'NAV__c':'NAVDisplay__c','Cost__c':'CostDisplay__c','MarketValue__c':'MarketValueDisplay__c','UnrealizedGain__c':'UnrealizedGainDisplay__c','SIPAmount__c':'SIPAmountDisplay__c','XIRR__c':'XIRRDisplay__c','Weight__c':'WeightDisplay__c'},
 'Inv_PortfolioValuation__c':{'MarketValue__c':'MarketValueDisplay__c','Cost__c':'CostDisplay__c','UnrealizedGain__c':'UnrealizedGainDisplay__c','RealizedGain__c':'RealizedGainDisplay__c','MonthlySIP__c':'MonthlySIPDisplay__c'},
 'Inv_Exposure__c':{'Value__c':'ValueDisplay__c'},
 'Inv_PortfolioUnitEntries__c':{'AcquisitionCostNumber__c':'AcquisitionCostCurrency__c','ConsiderationAmountNumber__c':'ConsiderationCurrency__c'},
 'Inv_PortfolioSipVersions__c':{'AmountNumber__c':'AmountCurrency__c'},'Inv_PortfolioSipEvidence__c':{'ObservedAmountNumber__c':'ObservedAmountCurrency__c'},
 'Inv_PortfolioPositionSnapshots__c':{'ReportedCostNumber__c':'ReportedCostCurrency__c'},'Inv_PortfolioEventCharges__c':{'AmountNumber__c':'AmountCurrency__c'},
 'Inv_PortfolioCashEntries__c':{'AmountDeltaNumber__c':'AmountDeltaCurrency__c'},'Inv_PlanningReviewItems__c':{'MonthlyOrTransactionAmountNumber__c':'AmountCurrency__c'},
 'Inv_PlanningPlanVersions__c':{'MonthlyBudgetNumber__c':'MonthlyBudgetCurrency__c'},'Inv_PlanningActions__c':{'RequestedAmountNumber__c':'RequestedAmountCurrency__c'},
 'Inv_OpsReconciliations__c':{'CalculatedCashNumber__c':'CalculatedCashCurrency__c','ReportedCashNumber__c':'ReportedCashCurrency__c'},
 'Inv_OpsImportRows__c':{'Amount__c':'AmountCurrency__c','Cost__c':'CostCurrency__c'},
}
HIDDEN_LAYOUT_FIELDS={'Inv_PlanImpact__c':{'BaselineCurrencyDisplay__c','ProposedCurrencyDisplay__c'}}

EXTENSIONS={
 'Inv_PlanningTargets__c':{'Fund__c':lookup('Target fund','Inv_MarketInstruments__c','AllocationTargets')},
 'Inv_PortfolioAccounts__c':{'CASScopeKey__c':{**text('Verified CAS account scope',64),'externalId':True,'unique':True}},
 'Inv_PortfolioPortfolios__c':{'PublishedRun__c':lookup('Published analysis run','Inv_AnalyticsRuns__c','PublishedPortfolios')},
 'Inv_MarketInstruments__c':{'DisplayName__c':text('Fund or security name'),'Tracked__c':check('Track NAV'),
  'PortfolioRole__c':text('Portfolio role',120),'ResearchNote__c':long('Portfolio research note'),
  'NAVAttemptAt__c':{'label':'NAV refresh attempted at','type':'DateTime'},'NAVRefreshStatus__c':text('NAV refresh status',40),
  'AMFICode__c':text('Verified AMFI scheme code',20),'MappingVerified__c':check('Share-class mapping verified'),
  'LatestTER__c':number('Latest disclosed TER ratio',10),'LatestBER__c':number('Latest disclosed BER ratio',10),
  'ExpenseDate__c':date('Expense disclosure date'),'ExpenseEvidence__c':lookup('Expense evidence','Inv_MarketExpenseObservations__c','FundExpenseSummaries'),
  'TERPercent__c':percent('Latest disclosed TER','LatestTER__c'),'BERPercent__c':percent('Latest disclosed BER','LatestBER__c')},
 'Inv_AnalyticsRuns__c':{'OperationalStatus__c':text('Operational status',40),'Failure__c':long('Failure summary'),
  'PortfolioStageStatus__c':text('Portfolio stage',40),'FundMetricsStageStatus__c':text('Fund metrics stage',40),
  'ExposureStageStatus__c':text('Exposure stage',40),'PipelineStage__c':text('Pipeline stage',40),
  'PipelineRef__c':{**lookup('Parent refresh pipeline','Inv_AnalyticsRuns__c','CalculationStages'),'deleteConstraint':'SetNull'}},
 'Inv_MarketPriceObservations__c':{'ObservationKey__c':{**text('Observation identity',200),'externalId':True,'unique':True},
  'InstrumentDisplayName__c':{'formula':'IF(ISBLANK(InstrumentRef__r.DisplayName__c), InstrumentRef__r.Name, InstrumentRef__r.DisplayName__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Fund / instrument','type':'Text'},
  'ProviderDisplayName__c':{'formula':'CASE(ProviderRef__r.MigrationKey__c, "operational:provider:MFapi", "MFapi", "operational:provider:AMFI", "AMFI", "ops.providers:13", "AMFI", "ops.providers:15", "MFapi", "Other")','formulaTreatBlanksAs':'BlankAsBlank','label':'Data source','type':'Text'},
  'ValueDisplay__c':{'formula':'IF(ISBLANK(ValueNumber__c), NULL, ROUND(ValueNumber__c, 2))','formulaTreatBlanksAs':'BlankAsBlank','label':'NAV (₹, 2 d.p.)','precision':18,'scale':2,'type':'Number'},
  'RecentChartDate__c':{'formula':'AND(NOT(ISBLANK(ObservedOn__c)), ObservedOn__c >= ADDMONTHS(TODAY(), -60))','label':'Within five year chart window','type':'Checkbox'},
  'RetrievedAt__c':{'label':'Retrieved at','type':'DateTime'},'KindFilter__c':text('Price type',30),'QualityFilter__c':text('Observation quality',40),'SelectedNAV__c':check('Selected NAV for this date')},
 'Inv_OpsImportRuns__c':{'FileHash__c':{**text('Source file SHA-256',64),'externalId':True,'unique':True},
  'Portfolio__c':lookup('Destination portfolio','Inv_PortfolioPortfolios__c','StatementImports'),
  'DuplicateOf__c':{**lookup('Existing import','Inv_OpsImportRuns__c','DuplicateUploads'),'deleteConstraint':'SetNull'},
  'CASParserVersion__c':text('CAS parser version',60),
  'ContentVersionId__c':text('Source file version',18),'OperationalStatus__c':text('Import status',40),
  'ParserJobId__c':text('Parser job identity',100),'Failure__c':long('Failure summary')},
 'Inv_OpsImportRows__c':{'PostingKey__c':{**text('Posting identity',200),'externalId':True,'unique':True},
  'RowIdentity__c':{**text('Staged row identity',200),'externalId':True,'unique':True},
  'ScopeKey__c':text('CAS account scope',64),'RowKind__c':text('Statement row kind',30),'MatchKey__c':{**text('Economic matching key',64),'externalId':True},
  'Account__c':lookup('Mapped account','Inv_PortfolioAccounts__c','StatementRows'),'Fund__c':lookup('Mapped share class','Inv_MarketInstruments__c','StatementRows'),
  'ISIN__c':text('ISIN',20),'TradeDate__c':date('Transaction date'),'TransactionType__c':text('Transaction type',40),
  'Units__c':text('Exact signed units',80),'Amount__c':text('Exact consideration INR',80),'Cost__c':text('Exact acquisition cost INR',80),
  'NAV__c':text('Exact source NAV',80),'OpeningUnits__c':text('Statement opening units',80),'ClosingUnits__c':text('Statement closing units',80),
  'PeriodStart__c':date('Statement start'),'PeriodEnd__c':date('Statement end'),'Occurrence__c':number('Matching occurrence',0),
  'MatchStatus__c':text('Match status',40),'MatchedEvent__c':lookup('Existing economic event','Inv_PortfolioEvents__c','ImportEvidence'),
  'AmountCurrency__c':currency('Consideration (INR)','Amount__c',True),'CostCurrency__c':currency('Acquisition cost (INR)','Cost__c',True)},
 'Inv_PortfolioEvents__c':{'PostingKey__c':{**text('Posting identity',200),'externalId':True,'unique':True},
  'EconomicKey__c':{**text('Economic matching key',64),'externalId':True}},
 'Inv_PortfolioUnitEntries__c':{'AcquisitionCostCurrency__c':currency('Acquisition cost (INR)','AcquisitionCostNumber__c'),
  'ConsiderationCurrency__c':currency('Consideration (INR)','ConsiderationAmountNumber__c')},
 'Inv_PortfolioSipVersions__c':{'AmountCurrency__c':currency('Monthly SIP amount (INR)','AmountNumber__c')},
 'Inv_PortfolioSipEvidence__c':{'ObservedAmountCurrency__c':currency('Observed SIP amount (INR)','ObservedAmountNumber__c')},
 'Inv_PortfolioPositionSnapshots__c':{'ReportedCostCurrency__c':currency('Reported cost (INR)','ReportedCostNumber__c')},
 'Inv_PortfolioEventCharges__c':{'AmountCurrency__c':currency('Charge amount (INR)','AmountNumber__c')},
 'Inv_PortfolioCashEntries__c':{'AmountDeltaCurrency__c':currency('Cash movement (INR)','AmountDeltaNumber__c')},
 'Inv_PlanningReviewItems__c':{'AmountCurrency__c':currency('Monthly or transaction amount (INR)','MonthlyOrTransactionAmountNumber__c')},
 'Inv_Holding__c':{'UnitCoverage__c':text('Unit reconciliation',40),'BasisCoverage__c':text('Acquisition-basis coverage',40),
  'RedemptionCoverage__c':text('Redemption-proceeds coverage',40),'PersonalReturnCoverage__c':text('Personal-return coverage',40),
  'NAVCoverage__c':text('NAV freshness',40),'CompositionCoverage__c':text('Composition coverage',40),'PolicyCoverage__c':text('Policy coverage',40)},
 'Inv_PlanningPlanVersions__c':{'MonthlyBudgetCurrency__c':currency('Monthly budget (INR)','MonthlyBudgetNumber__c'),
  'BaselineInputFingerprint__c':text('Baseline input fingerprint',64),'EvaluationFingerprint__c':text('Last evaluation fingerprint',64),
  'ConstraintsJson__c':long('Review constraints'),'GenerationRationale__c':long('Alternative generation rationale'),
  'ApprovalReadiness__c':text('Approval readiness',40),'TaxAssumptionAcknowledged__c':check('Tax estimate acknowledged')},
 'Inv_PlanningActions__c':{'RequestedAmountCurrency__c':currency('Requested amount (INR)','RequestedAmountNumber__c'),
  'ExecutionStatus__c':text('Execution status',40),'ExecutionDifference__c':long('Execution difference and review')},
 'Inv_PlanningExecutionRecords__c':{'ActionRef__c':lookup('Plan action','Inv_PlanningActions__c','ExecutionEvidence'),
  'ExecutionStatus__c':text('Execution status',40),'MatchedImportRowRef__c':{**lookup('Matched statement row','Inv_OpsImportRows__c','ExecutionEvidence'),'relationshipName':'ExecutionImportRows'},
  'DifferenceSummary__c':long('Difference summary')},
 'Inv_OpsReconciliations__c':{'CalculatedCashCurrency__c':currency('Calculated cash (INR)','CalculatedCashNumber__c'),
  'ReportedCashCurrency__c':currency('Reported cash (INR)','ReportedCashNumber__c')},
}

def section(label,fields):
 return {'customLabel':True,'detailHeading':True,'editHeading':True,'label':label,
  'layoutColumns':[{'layoutItems':[{'behavior':'Required' if f in ['Name','Key__c'] else 'Readonly','field':f} for f in fields[::2]]},
                   {'layoutItems':[{'behavior':'Readonly','field':f} for f in fields[1::2]]}],
  'style':'TwoColumnsTopToBottom'}

def main():
 members={};allfields={}
 source_mapping=json.loads((ROOT/'tools/investment-migration/mapping.json').read_text(encoding='utf-8'))
 for source in source_mapping.values():
  original={f['field'] for f in source['fields'].values()}
  collision=original.intersection(EXTENSIONS.get(source['object'],{}))
  if collision:raise ValueError('Operational fields collide with preserved source fields: '+str(collision))
 def add(kind,name):
  values=members.setdefault(kind,[])
  if name not in values:values.append(name)
 for name,label in [('Inv_ManagePortfolio','Manage investment plans and confirm statement imports'),('Inv_ParseStatements','Submit extracted CAS data to staging')]:
  xml(DEST/'customPermissions'/(name+'.customPermission-meta.xml'),'CustomPermission',{'isLicensed':False,'label':label});add('CustomPermission',name)
 for api,(singular,plural,fields) in OBJECTS.items():
  fields={**COMMON,**fields};allfields[api]=fields
  xml(DEST/'objects'/api/(api+'.object-meta.xml'),'CustomObject',{
   'deploymentStatus':'Deployed','description':'Operational portfolio analysis; source history remains separately preserved.',
   'enableReports':True,'label':singular,'nameField':{'label':singular+' name','type':'Text'},'pluralLabel':plural,'sharingModel':'Private'})
  add('CustomObject',api)
  for name,spec in fields.items():
   if spec.get('type')=='Lookup':spec={**spec,'relationshipName':api.removeprefix('Inv_').removesuffix('__c')+name.removesuffix('__c')}
   xml(DEST/'objects'/api/'fields'/(name+'.field-meta.xml'),'CustomField',{'fullName':name,**spec})
  xml(DEST/'tabs'/(api+'.tab-meta.xml'),'CustomTab',{'customObject':True,'label':plural,'motif':'Custom17: Sack'});add('CustomTab',api)
  visible=DISPLAY_FIELDS.get(api,{})
  display_values=set(visible.values())
  hidden=HIDDEN_LAYOUT_FIELDS.get(api,set())
  layout_fields=['Name',*[visible.get(f,f) for f in fields if f not in display_values and f not in hidden]]
  xml(DEST/'layouts'/(api+'-Portfolio Analysis.layout-meta.xml'),'Layout',{'layoutSections':[section('Portfolio analysis',layout_fields)],
   'relatedLists':{'relatedList':'RelatedFileList'},'showHighlightsPanel':True});add('Layout',api+'-Portfolio Analysis')
  cols=['NAME']+(['FundDisplayName__c'] if api=='Inv_Holding__c' else [])+[visible.get(f,f) for f in ['Status__c','MarketValue__c','Cost__c','UnrealizedGain__c','NAVDate__c','Coverage__c','AsOf__c','Metric__c'] if f in fields]
  xml(DEST/'objects'/api/'listViews/All.listView-meta.xml','ListView',{'fullName':'All','columns':cols[:8],'filterScope':'Everything','label':'All '+plural.lower()});add('ListView',api+'.All')
 for api,fields in EXTENSIONS.items():
  allfields[api]=fields
  for name,spec in fields.items():
   if spec.get('type')=='Lookup' and not spec.get('relationshipName'):
    spec={**spec,'relationshipName':api.removeprefix('Inv_').removesuffix('__c')+name.removesuffix('__c')}
   xml(DEST/'objects'/api/'fields'/(name+'.field-meta.xml'),'CustomField',{'fullName':name,**spec});add('CustomField',api+'.'+name)
 for api,(singular,plural,fields) in AUX_OBJECTS.items():
  allfields[api]=fields
  xml(DEST/'objects'/api/(api+'.object-meta.xml'),'CustomObject',{
   'deploymentStatus':'Deployed','description':'Items the portfolio owner wants to monitor; watchlist entries do not create holdings or trades.',
   'enableReports':True,'label':singular,'nameField':{'label':'Watchlist item','type':'Text'},'pluralLabel':plural,'sharingModel':'Private'})
  add('CustomObject',api)
  for name,spec in fields.items():
   if spec.get('type')=='Lookup':spec={**spec,'relationshipName':'WatchlistItems'+name.removesuffix('__c')}
   xml(DEST/'objects'/api/'fields'/(name+'.field-meta.xml'),'CustomField',{'fullName':name,**spec})
  xml(DEST/'tabs'/(api+'.tab-meta.xml'),'CustomTab',{'customObject':True,'label':'Watchlist','motif':'Custom18: Form'});add('CustomTab',api)
  xml(DEST/'layouts'/(api+'-Watchlist.layout-meta.xml'),'Layout',{'layoutSections':[section('Watchlist item',['Name',*fields])],
   'relatedLists':{'relatedList':'RelatedFileList'},'showHighlightsPanel':True});add('Layout',api+'-Watchlist')
  xml(DEST/'objects'/api/'listViews/All.listView-meta.xml','ListView',{'fullName':'All',
   'columns':['NAME','AssetType__c','Symbol__c','Exchange__c','ISIN__c','SchemeCode__c','Fund__c','Active__c','AddedOn__c'],
   'filterScope':'Everything','label':'All watchlist items'});add('ListView',api+'.All')
  xml(DEST/'objects'/api/'listViews/Active.listView-meta.xml','ListView',{'fullName':'Active',
   'columns':['NAME','AssetType__c','Symbol__c','Exchange__c','ISIN__c','Fund__c','AddedOn__c'],
   'filterScope':'Everything','filters':{'field':'Active__c','operation':'equals','value':'1'},'label':'On watchlist'});add('ListView',api+'.Active')
 for name,label,filters in [('Current','Current Holdings',[('Status__c','equals','Active')]),('Closed','Closed Positions',[('Status__c','equals','Closed')]),
  ('WithoutSIP','Holdings Without Active SIPs',[('Status__c','equals','Active'),('SIPAmount__c','equals','0')]),('NeedsReview','Needs Review',[('Coverage__c','notEqual','complete')])]:
  xml(DEST/'objects/Inv_Holding__c/listViews'/(name+'.listView-meta.xml'),'ListView',{'fullName':name,'columns':['NAME','FundDisplayName__c','Units__c','CostDisplay__c','MarketValueDisplay__c','NAVDate__c','Coverage__c'],
   'filterScope':'Everything','filters':[{'field':f,'operation':o,'value':v} for f,o,v in filters],'label':label});add('ListView','Inv_Holding__c.'+name)
 xml(DEST/'objects/Inv_PortfolioValuation__c/listViews/Current.listView-meta.xml','ListView',{'fullName':'Current',
  'columns':['NAME','MarketValueDisplay__c','CostDisplay__c','UnrealizedGainDisplay__c','MonthlySIPDisplay__c','EarliestNAV__c','LatestNAV__c','XIRRDisplay__c'],
  'filterScope':'Everything','filters':{'field':'Published__c','operation':'equals','value':'1'},'label':'Published portfolio summary'});add('ListView','Inv_PortfolioValuation__c.Current')
 for role in ['Inv_Viewer','Inv_MigrationAdmin']:
  path=DEST/'permissionsets'/(role+'.permissionset-meta.xml');root=ET.parse(path).getroot()
  for api,fields in allfields.items():
   if (api in OBJECTS or api in AUX_OBJECTS) and not any(x.find('{'+NS+'}object').text==api for x in root.findall('{'+NS+'}objectPermissions')):
    obj=ET.SubElement(root,'{'+NS+'}objectPermissions')
    for k,v in {'allowCreate':False,'allowDelete':False,'allowEdit':False,'allowRead':True,'modifyAllRecords':False,'object':api,'viewAllRecords':False}.items(): ET.SubElement(obj,'{'+NS+'}'+k).text=str(v).lower() if isinstance(v,bool) else v
   for field,spec in fields.items():
    if spec.get('required'):continue
    full=api+'.'+field
    if any(x.find('{'+NS+'}field').text==full for x in root.findall('{'+NS+'}fieldPermissions')):continue
    node=ET.SubElement(root,'{'+NS+'}fieldPermissions')
    for k,v in {'editable':'false','field':full,'readable':'true'}.items():ET.SubElement(node,'{'+NS+'}'+k).text=v
  for api in [*OBJECTS,*AUX_OBJECTS]:
   if not any(x.find('{'+NS+'}tab').text==api for x in root.findall('{'+NS+'}tabSettings')):
    node=ET.SubElement(root,'{'+NS+'}tabSettings');ET.SubElement(node,'{'+NS+'}tab').text=api;ET.SubElement(node,'{'+NS+'}visibility').text='Visible'
  if role=='Inv_Viewer':
   class_names=['InvResearchService','InvMovementService','InvPlanScenarioService','InvRedemptionService']
   existing={x.find('{'+NS+'}apexClass').text for x in root.findall('{'+NS+'}classAccesses')}
   for class_name in class_names:
    if (DEST/'classes'/(class_name+'.cls')).exists() and class_name not in existing:
     node=ET.SubElement(root,'{'+NS+'}classAccesses');ET.SubElement(node,'{'+NS+'}apexClass').text=class_name;ET.SubElement(node,'{'+NS+'}enabled').text='true'
  # Metadata sequences fields by element name, then preserves entries within each group.
  root[:]=sorted(root,key=lambda x:x.tag)
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('PermissionSet',role)
 for p in (DEST/'classes').glob('Inv*.cls'):
  if p.stem=='InvestmentAccessTest':continue
  xml(p.with_suffix('.cls-meta.xml'),'ApexClass',{'apiVersion':'68.0','status':'Active'});add('ApexClass',p.stem)
 for p in (DEST/'triggers').glob('Inv*.trigger'):
  xml(p.with_suffix('.trigger-meta.xml'),'ApexTrigger',{'apiVersion':'68.0','status':'Active'});add('ApexTrigger',p.stem)
 xml(DEST/'permissionsets/Inv_PortfolioManager.permissionset-meta.xml','PermissionSet',{
  'classAccesses':[{'apexClass':name,'enabled':True} for name in ['InvPlanService','InvPlanScenarioService','InvRedemptionService','InvImportActions','InvFundActions'] if (DEST/'classes'/(name+'.cls')).exists()],
  'customPermissions':{'enabled':True,'name':'Inv_ManagePortfolio'},
  'description':'Controlled plan actions and reviewed account import confirmation. Assign together with Inv_Viewer.',
  'flowAccesses':[{'enabled':True,'flow':p.stem.removesuffix('.flow-meta')} for p in (DEST/'flows').glob('Inv_*.flow-meta.xml')],
  'label':'Investment Portfolio Manager','userPermissions':{'enabled':True,'name':'RunReports'},
  'objectPermissions':[{'allowCreate':True,'allowDelete':True,'allowEdit':True,'allowRead':True,'modifyAllRecords':False,'object':'Inv_WatchlistItems__c','viewAllRecords':False},
   {'allowCreate':True,'allowDelete':False,'allowEdit':True,'allowRead':True,'modifyAllRecords':False,'object':'Inv_FundPeerAssignments__c','viewAllRecords':False}],
  'fieldPermissions':[{'editable':field in ['AssetType__c','Symbol__c','Exchange__c','ISIN__c','SchemeCode__c','Fund__c','Active__c','AddedOn__c','Notes__c'],
    'field':'Inv_WatchlistItems__c.'+field,'readable':True} for field in AUX_OBJECTS['Inv_WatchlistItems__c'][2]]+
   [{'editable':field in ['Key__c','Fund__c','PeerFund__c','SchemeVersion__c','EffectiveFrom__c','EffectiveTo__c','AssignmentStatus__c','Category__c','ShareClassRule__c','Rationale__c'],
    'field':'Inv_FundPeerAssignments__c.'+field,'readable':True} for field in OBJECTS['Inv_FundPeerAssignments__c'][2]]});add('PermissionSet','Inv_PortfolioManager')
 if (DEST/'lwc/invParseStatement').exists():add('LightningComponentBundle','invParseStatement')
 xml(DEST/'permissionsets/Inv_Parser.permissionset-meta.xml','PermissionSet',{
  'classAccesses':{'apexClass':'InvImportEndpoint','enabled':True},'customPermissions':{'enabled':True,'name':'Inv_ParseStatements'},
  'description':'Dedicated CAS parser identity: read import jobs and stage extracted data; cannot confirm or post transactions.',
  'fieldPermissions':[{'editable':False,'field':'Inv_OpsImportRuns__c.'+field,'readable':True} for field in ['ContentVersionId__c','OperationalStatus__c']],
  'label':'Investment CAS Parser','objectPermissions':{'allowCreate':False,'allowDelete':False,'allowEdit':False,'allowRead':True,'modifyAllRecords':False,'object':'Inv_OpsImportRuns__c','viewAllRecords':True}});add('PermissionSet','Inv_Parser')
 for name,url in [('Inv_MFapi','https://api.mfapi.in'),('Inv_AMFI','https://portal.amfiindia.com')]:
  xml(DEST/'namedCredentials'/(name+'.namedCredential-meta.xml'),'NamedCredential',{
   'allowMergeFieldsInBody':False,'allowMergeFieldsInHeader':False,'endpoint':url,'generateAuthorizationHeader':False,
   'label':name.replace('_',' '),'principalType':'Anonymous','protocol':'NoAuthentication'})
  add('NamedCredential',name)
 xml(ROOT/'manifest/portfolio.xml','Package',{'types':[{'members':v,'name':k} for k,v in members.items()],'version':'68.0'})
 (ROOT/'tools/portfolio/model.json').write_text(json.dumps({'objects':OBJECTS,'extensions':EXTENSIONS,'auxiliary':AUX_OBJECTS},indent=2),encoding='utf-8')
 print('Generated',len(OBJECTS),'operational objects and',sum(len(v) for v in EXTENSIONS.values()),'extension fields')

if __name__=='__main__':main()
