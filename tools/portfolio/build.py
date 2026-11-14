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
  'Units__c':number('Remaining units',8),'Cost__c':number('Remaining cost INR'),
  'NAV__c':number('Selected NAV',10),'NAVDate__c':date('NAV date'),'ReconciledThrough__c':date('Transactions reconciled through'),
  'MarketValue__c':number('Market value INR'),'UnrealizedGain__c':number('Unrealized gain INR'),
  'RealizedGain__c':number('Realized gain INR'),'XIRR__c':number('Personal XIRR',10),
  'Weight__c':number('Portfolio weight',10),'SIPAmount__c':number('Monthly SIP INR'),
  'XIRRDisplay__c':percent('Personal XIRR percent','XIRR__c'),'WeightDisplay__c':percent('Portfolio weight percent','Weight__c'),
  'Status__c':text('Position status',40),'Coverage__c':text('Calculation coverage'),
  'Warnings__c':long('Review notes'),'Run__c':RUN,
  'ReturnPercent__c':{'formula':'IF(OR(ISBLANK(Cost__c),Cost__c = 0), NULL, UnrealizedGain__c / Cost__c)','formulaTreatBlanksAs':'BlankAsBlank','label':'Unrealized return','precision':18,'scale':2,'type':'Percent'},
 }),
 'Inv_HoldingValuation__c':('Holding valuation','Holding Valuations',{
  'Holding__c':lookup('Holding','Inv_Holding__c','Valuations'),'Portfolio__c':PORT,'Fund__c':FUND,'Run__c':RUN,
  'AsOf__c':date('Valuation date'),'NAVDate__c':date('NAV date'),'Units__c':number('Units',8),
  'NAV__c':number('NAV',10),'Cost__c':number('Remaining cost INR'),'MarketValue__c':number('Market value INR'),
  'UnrealizedGain__c':number('Unrealized gain INR'),'Coverage__c':text('Coverage'),'Published__c':check('Published'),
 }),
 'Inv_PortfolioValuation__c':('Portfolio valuation','Portfolio Valuations',{
  'Portfolio__c':PORT,'Run__c':RUN,'AsOf__c':date('Valuation date'),'EarliestNAV__c':date('Earliest NAV date'),
  'LatestNAV__c':date('Latest NAV date'),'MarketValue__c':number('Market value INR'),
  'Cost__c':number('Remaining cost INR'),'UnrealizedGain__c':number('Unrealized gain INR'),
  'RealizedGain__c':number('Realized gain INR'),'XIRR__c':number('Portfolio XIRR',10),
  'MonthlySIP__c':number('Monthly SIP INR'),'HoldingCount__c':number('Active positions',0),
  'XIRRDisplay__c':percent('Portfolio XIRR percent','XIRR__c'),
  'Coverage__c':long('Coverage and review notes'),'Published__c':check('Published'),'LatestForDate__c':check('Latest valuation for date'),'InputHash__c':text('Input fingerprint',64),
 }),
 'Inv_Exposure__c':('Exposure','Exposures',{
  'Portfolio__c':PORT,'Fund__c':FUND,'Run__c':RUN,'Dimension__c':text('Dimension',60),
  'Member__c':text('Exposure member'),'Value__c':number('Attributed value INR'),
  'Weight__c':number('Portfolio weight',10),'DisclosureDate__c':date('Disclosure date'),
  'Coverage__c':text('Coverage'),'Published__c':check('Published'),
 }),
 'Inv_FundMetric__c':('Fund metric','Fund Metrics',{
  'Fund__c':FUND,'Run__c':RUN,'Metric__c':text('Metric',80),'PeriodStart__c':date('Period start'),
  'PeriodEnd__c':date('Period end'),'Value__c':number('Value',10),'Coverage__c':text('Coverage'),
  'Benchmark__c':lookup('Benchmark','Inv_MarketInstruments__c','FundComparisons'),'Published__c':check('Published'),
  'CounterpartyFund__c':lookup('Compared fund','Inv_MarketInstruments__c','OverlapComparisons'),
  'Disclosure__c':lookup('Fund disclosure','Inv_MarketFundPortfolioSnapshots__c','FundMetricEvidence'),
  'ComparedDisclosure__c':lookup('Compared disclosure','Inv_MarketFundPortfolioSnapshots__c','ComparedMetricEvidence'),
  'ValuePercent__c':percent('Metric percent','Value__c'),
 }),
 'Inv_PlanImpact__c':('Plan impact','Plan Impacts',{
  'PlanVersion__c':lookup('Plan version','Inv_PlanningPlanVersions__c','Impacts'),'Run__c':RUN,'Fund__c':FUND,
  'Scope__c':text('Scope',100),'Metric__c':text('Metric',100),'Baseline__c':number('Current'),
  'Dimension__c':text('Exposure dimension',60),'Member__c':text('Exposure member'),
  'Proposed__c':number('Proposed'),'Coverage__c':text('Coverage'),'Notes__c':long('Assumptions and warnings'),'Published__c':check('Published'),
 }),
}
EXTENSIONS={
 'Inv_PlanningTargets__c':{'Fund__c':lookup('Target fund','Inv_MarketInstruments__c','AllocationTargets')},
 'Inv_PortfolioAccounts__c':{'CASScopeKey__c':{**text('Verified CAS account scope',64),'externalId':True,'unique':True}},
 'Inv_PortfolioPortfolios__c':{'PublishedRun__c':lookup('Published analysis run','Inv_AnalyticsRuns__c','PublishedPortfolios')},
 'Inv_MarketInstruments__c':{'DisplayName__c':text('Fund or security name'),'Tracked__c':check('Track NAV'),
  'NAVAttemptAt__c':{'label':'NAV refresh attempted at','type':'DateTime'},'NAVRefreshStatus__c':text('NAV refresh status',40),
  'AMFICode__c':text('Verified AMFI scheme code',20),'MappingVerified__c':check('Share-class mapping verified'),
  'LatestTER__c':number('Latest disclosed TER ratio',10),'LatestBER__c':number('Latest disclosed BER ratio',10),
  'ExpenseDate__c':date('Expense disclosure date'),'ExpenseEvidence__c':lookup('Expense evidence','Inv_MarketExpenseObservations__c','FundExpenseSummaries'),
  'TERPercent__c':percent('Latest disclosed TER','LatestTER__c'),'BERPercent__c':percent('Latest disclosed BER','LatestBER__c')},
 'Inv_AnalyticsRuns__c':{'OperationalStatus__c':text('Operational status',40),'Failure__c':long('Failure summary')},
 'Inv_MarketPriceObservations__c':{'ObservationKey__c':{**text('Observation identity',200),'externalId':True,'unique':True},
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
  'MatchStatus__c':text('Match status',40),'MatchedEvent__c':lookup('Existing economic event','Inv_PortfolioEvents__c','ImportEvidence')},
 'Inv_PortfolioEvents__c':{'PostingKey__c':{**text('Posting identity',200),'externalId':True,'unique':True},
  'EconomicKey__c':{**text('Economic matching key',64),'externalId':True}},
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
 def add(kind,name):members.setdefault(kind,[]).append(name)
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
  xml(DEST/'tabs'/(api+'.tab-meta.xml'),'CustomTab',{'customObject':True,'motif':'Custom17: Sack'});add('CustomTab',api)
  xml(DEST/'layouts'/(api+'-Portfolio Analysis.layout-meta.xml'),'Layout',{'layoutSections':[section('Portfolio analysis',['Name',*fields])],
   'relatedLists':{'relatedList':'RelatedFileList'},'showHighlightsPanel':True});add('Layout',api+'-Portfolio Analysis')
  cols=['NAME']+(['FundDisplayName__c'] if api=='Inv_Holding__c' else [])+[f for f in ['Status__c','MarketValue__c','Cost__c','UnrealizedGain__c','NAVDate__c','Coverage__c','AsOf__c','Metric__c'] if f in fields]
  xml(DEST/'objects'/api/'listViews/All.listView-meta.xml','ListView',{'fullName':'All','columns':cols[:8],'filterScope':'Everything','label':'All '+plural.lower()});add('ListView',api+'.All')
 for api,fields in EXTENSIONS.items():
  allfields[api]=fields
  for name,spec in fields.items():
   if spec.get('type')=='Lookup':spec={**spec,'relationshipName':api.removeprefix('Inv_').removesuffix('__c')+name.removesuffix('__c')}
   xml(DEST/'objects'/api/'fields'/(name+'.field-meta.xml'),'CustomField',{'fullName':name,**spec});add('CustomField',api+'.'+name)
 for name,label,filters in [('Current','Current Holdings',[('Status__c','equals','Active')]),('Closed','Closed Positions',[('Status__c','equals','Closed')]),
  ('WithoutSIP','Holdings Without Active SIPs',[('Status__c','equals','Active'),('SIPAmount__c','equals','0')]),('NeedsReview','Needs Review',[('Coverage__c','notEqual','complete')])]:
  xml(DEST/'objects/Inv_Holding__c/listViews'/(name+'.listView-meta.xml'),'ListView',{'fullName':name,'columns':['NAME','FundDisplayName__c','Units__c','Cost__c','MarketValue__c','NAVDate__c','Coverage__c'],
   'filterScope':'Everything','filters':[{'field':f,'operation':o,'value':v} for f,o,v in filters],'label':label});add('ListView','Inv_Holding__c.'+name)
 xml(DEST/'objects/Inv_PortfolioValuation__c/listViews/Current.listView-meta.xml','ListView',{'fullName':'Current',
  'columns':['NAME','MarketValue__c','Cost__c','UnrealizedGain__c','MonthlySIP__c','EarliestNAV__c','LatestNAV__c','XIRRDisplay__c'],
  'filterScope':'Everything','filters':{'field':'Published__c','operation':'equals','value':'1'},'label':'Published portfolio summary'});add('ListView','Inv_PortfolioValuation__c.Current')
 for role in ['Inv_Viewer','Inv_MigrationAdmin']:
  path=DEST/'permissionsets'/(role+'.permissionset-meta.xml');root=ET.parse(path).getroot()
  for api,fields in allfields.items():
   if api in OBJECTS and not any(x.find('{'+NS+'}object').text==api for x in root.findall('{'+NS+'}objectPermissions')):
    obj=ET.SubElement(root,'{'+NS+'}objectPermissions')
    for k,v in {'allowCreate':False,'allowDelete':False,'allowEdit':False,'allowRead':True,'modifyAllRecords':False,'object':api,'viewAllRecords':True}.items(): ET.SubElement(obj,'{'+NS+'}'+k).text=str(v).lower() if isinstance(v,bool) else v
   for field,spec in fields.items():
    if spec.get('required'):continue
    full=api+'.'+field
    if any(x.find('{'+NS+'}field').text==full for x in root.findall('{'+NS+'}fieldPermissions')):continue
    node=ET.SubElement(root,'{'+NS+'}fieldPermissions')
    for k,v in {'editable':'false','field':full,'readable':'true'}.items():ET.SubElement(node,'{'+NS+'}'+k).text=v
  for api in OBJECTS:
   if not any(x.find('{'+NS+'}tab').text==api for x in root.findall('{'+NS+'}tabSettings')):
    node=ET.SubElement(root,'{'+NS+'}tabSettings');ET.SubElement(node,'{'+NS+'}tab').text=api;ET.SubElement(node,'{'+NS+'}visibility').text='Visible'
  # Metadata sequences fields by element name, then preserves entries within each group.
  root[:]=sorted(root,key=lambda x:x.tag)
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('PermissionSet',role)
 for p in (DEST/'classes').glob('Inv*.cls'):
  if p.stem=='InvestmentAccessTest':continue
  xml(p.with_suffix('.cls-meta.xml'),'ApexClass',{'apiVersion':'68.0','status':'Active'});add('ApexClass',p.stem)
 for p in (DEST/'triggers').glob('Inv*.trigger'):
  xml(p.with_suffix('.trigger-meta.xml'),'ApexTrigger',{'apiVersion':'68.0','status':'Active'});add('ApexTrigger',p.stem)
 xml(DEST/'permissionsets/Inv_PortfolioManager.permissionset-meta.xml','PermissionSet',{
  'classAccesses':[{'apexClass':name,'enabled':True} for name in ['InvPlanService','InvImportActions','InvFundActions'] if (DEST/'classes'/(name+'.cls')).exists()],
  'customPermissions':{'enabled':True,'name':'Inv_ManagePortfolio'},
  'description':'Controlled plan actions and reviewed account import confirmation. Assign together with Inv_Viewer.',
  'flowAccesses':[{'enabled':True,'flow':p.stem.removesuffix('.flow-meta')} for p in (DEST/'flows').glob('Inv_*.flow-meta.xml')],
  'label':'Investment Portfolio Manager','userPermissions':{'enabled':True,'name':'RunReports'}});add('PermissionSet','Inv_PortfolioManager')
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
 (ROOT/'tools/portfolio/model.json').write_text(json.dumps({'objects':OBJECTS,'extensions':EXTENSIONS},indent=2),encoding='utf-8')
 print('Generated',len(OBJECTS),'operational objects and',sum(len(v) for v in EXTENSIONS.values()),'extension fields')

if __name__=='__main__':main()
