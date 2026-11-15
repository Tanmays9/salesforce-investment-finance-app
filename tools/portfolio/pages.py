"""Native Lightning navigation and contextual standard report charts."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'investment-migration'))
from prepare import ROOT,xml,NS,object_presentation
from build import DEST,section,AUX_OBJECTS,DISPLAY_FIELDS
import xml.etree.ElementTree as ET

def component(name,identity,properties):
 return {'componentInstance':{'componentInstanceProperties':[{'name':k,'value':v} for k,v in properties.items()],
  'componentName':name,'identifier':identity}}

def component_element(name,identity,properties):
 item=ET.Element('{'+NS+'}itemInstances');instance=ET.SubElement(item,'{'+NS+'}componentInstance')
 for key,value in properties.items():
  prop=ET.SubElement(instance,'{'+NS+'}componentInstanceProperties');ET.SubElement(prop,'{'+NS+'}name').text=key;ET.SubElement(prop,'{'+NS+'}value').text=value
 ET.SubElement(instance,'{'+NS+'}componentName').text=name;ET.SubElement(instance,'{'+NS+'}identifier').text=identity
 return item

def main():
 members={}
 def add(kind,name):
  values=members.setdefault(kind,[])
  if name not in values:values.append(name)
 charts=[component('flexipage:filterListCard','summary',{'entityName':'Inv_PortfolioValuation__c','filterName':'Current','pageSize':'5'}),
         component('c:invPortfolioResearch','portfolioResearch',{}),
         component('c:invWatchlistCard','watchlist',{}),
         component('flexipage:reportChart','allocation',{'reportName':'FundAllocation','showRefreshButton':'true'}),
         component('flexipage:reportChart','category',{'reportName':'CategoryAllocation','showRefreshButton':'true'}),
         component('flexipage:reportChart','sip',{'reportName':'SIPAllocation','showRefreshButton':'true'})]
 xml(DEST/'flexipages/Inv_Overview.flexipage-meta.xml','FlexiPage',{'description':'Portfolio snapshot, current holdings, watchlist, allocation and SIP review.',
  'flexiPageRegions':{'itemInstances':charts,'name':'main','type':'Region'},'masterLabel':'Portfolio Overview',
  'template':{'name':'flexipage:defaultAppHomeTemplate'},'type':'AppPage'});add('FlexiPage','Inv_Overview')
 xml(DEST/'tabs/Inv_Overview.tab-meta.xml','CustomTab',{'flexiPage':'Inv_Overview','label':'Overview','motif':'Custom18: Form'});add('CustomTab','Inv_Overview')
 for page,bundle,label in [('Inv_PlanComparison','c:invPlanComparison','Plan Comparison'),('Inv_RedemptionReview','c:invRedemptionReview','Redemption Review')]:
  page_path=DEST/'flexipages'/(page+'.flexipage-meta.xml')
  if not page_path.exists():
   xml(page_path,'FlexiPage',{'description':label+' workflow using saved investment analysis and versioned plan records.',
    'flexiPageRegions':{'itemInstances':[component(bundle,'main',{})],'name':'main','type':'Region'},'masterLabel':label,
    'template':{'name':'flexipage:defaultAppHomeTemplate'},'type':'AppPage'})
  xml(DEST/'tabs'/(page+'.tab-meta.xml'),'CustomTab',{'flexiPage':page,'label':label,'motif':'Custom18: Form'});add('FlexiPage',page);add('CustomTab',page)
 # Preserve and expose the curated Funds page instead of adding the raw object tab whose label ends in "Records".
 add('FlexiPage','Inv_MutualFunds');add('CustomTab','Inv_MutualFunds')
 for api,original,label in [('Inv_MarketInstruments__c','Market Instruments Layout','Fund analysis'),('Inv_PortfolioPortfolios__c','Portfolio Portfolios Layout','Portfolio review'),('Inv_PlanningPlanVersions__c','Planning Plan Versions Layout','Plan comparison')]:
  fund=api=='Inv_MarketInstruments__c'
  report_specs=[('NAVHistory','Inv_MarketPriceObservations__c$InstrumentRef__c.Id'),('Exposure','Inv_Exposure__c$Fund__c.Id')] if fund else [('PlanComparison','Inv_PlanImpact__c$PlanVersion__c.Id'),('PlanSIPs','Inv_PlanImpact__c$PlanVersion__c.Id')] if api=='Inv_PlanningPlanVersions__c' else [('FundAllocation','Inv_Holding__c$Portfolio__c.Id'),('CategoryAllocation','Inv_Holding__c$Portfolio__c.Id')]
  path=DEST/'layouts'/(api+'-'+original+'.layout-meta.xml');root=ET.parse(path).getroot()
  for node in list(root.findall('{'+NS+'}layoutSections')):
   if node.find('{'+NS+'}label').text in ['Analysis charts','Fund identity']:root.remove(node)
  chartsection=ET.Element('{'+NS+'}layoutSections')
  for k,v in [('customLabel','true'),('detailHeading','true'),('editHeading','false'),('label','Analysis charts')]:ET.SubElement(chartsection,'{'+NS+'}'+k).text=v
  column=ET.SubElement(chartsection,'{'+NS+'}layoutColumns')
  for report,context in report_specs[:2]:
   item=ET.SubElement(column,'{'+NS+'}layoutItems');chart=ET.SubElement(item,'{'+NS+'}reportChartComponent')
   for k,v in {'cacheData':'true','contextFilterableField':context.replace('$','.'),'hideOnError':'false','includeContext':'true','reportName':report,'showTitle':'true','size':'LARGE'}.items():ET.SubElement(chart,'{'+NS+'}'+k).text=v
  ET.SubElement(chartsection,'{'+NS+'}style').text='OneColumn';root.insert(0,chartsection)
  if fund:
   for col in root.findall('.//{'+NS+'}layoutColumns'):
    for item in list(col):
     field=item.find('{'+NS+'}field')
     if field is not None and field.text in ['DisplayName__c','Isin__c','AMFICode__c','MappingVerified__c','Tracked__c']:col.remove(item)
   # A standard field section exposes readable scheme identity without renaming imported IDs.
   value=section('Fund identity',['DisplayName__c','Isin__c','AMFICode__c','MappingVerified__c','Tracked__c','TERPercent__c','BERPercent__c','ExpenseDate__c','ExpenseEvidence__c'])
   temp=DEST/'layouts/_temporary.layout-meta.xml';xml(temp,'Layout',{'layoutSections':value});root.insert(0,ET.parse(temp).getroot()[0]);temp.unlink()
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('Layout',api+'-'+original)
  if fund:
   for child,field,columns in [('Inv_Holding__c','Fund__c',['NAME','Units__c','CostDisplay__c','MarketValueDisplay__c','XIRRDisplay__c','NAVDate__c']),('Inv_FundMetric__c','Fund__c',['NAME','CounterpartyFund__c','ValuePercent__c','PeriodEnd__c','Coverage__c']),('Inv_FundPeerAssignments__c','Fund__c',['PeerFund__c','Category__c','ShareClassRule__c','EffectiveFrom__c','EffectiveTo__c','AssignmentStatus__c','Rationale__c'])]:
    name=child+'.'+field
    if not any(n.find('{'+NS+'}relatedList').text==name for n in root.findall('{'+NS+'}relatedLists')):
     node=ET.SubElement(root,'{'+NS+'}relatedLists')
     for column in columns:ET.SubElement(node,'{'+NS+'}fields').text=column
     ET.SubElement(node,'{'+NS+'}relatedList').text=name
   root[:]=sorted(root,key=lambda n:n.tag);ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True)
 tabs=['Inv_Overview','Inv_PortfolioPortfolios__c','Inv_Holding__c','Inv_MutualFunds','Inv_PortfolioSipVersions__c','Inv_PlanningPlans__c','Inv_PlanComparison','Inv_RedemptionReview','Inv_WatchlistItems__c','Inv_FundPeerAssignments__c','Inv_OpsImportRuns__c','Inv_OpsDataIssues__c','standard-report','standard-Dashboard']
 labels={'Inv_MutualFunds':'Funds','Inv_PortfolioPortfolios__c':'Portfolios','Inv_Holding__c':'Holdings','Inv_WatchlistItems__c':'Watchlist','Inv_FundPeerAssignments__c':'Peer Assignments',
  'Inv_PortfolioSipVersions__c':'SIPs','Inv_PlanningPlans__c':'Plans','Inv_OpsImportRuns__c':'Imports','Inv_OpsDataIssues__c':'Data Health'}
 for tab,label in labels.items():
  path=DEST/'tabs'/(tab+'.tab-meta.xml')
  if path.exists():
   root=ET.parse(path).getroot();node=root.find('{'+NS+'}label')
   if node is None:node=ET.SubElement(root,'{'+NS+'}label')
   node.text=label;root[:]=sorted(root,key=lambda n:n.tag);ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True)
   add('CustomTab',tab)
 xml(DEST/'applications/Investments.app-meta.xml','CustomApplication',{'description':'Portfolio review, fund analysis and versioned investment plans.',
  'actionOverrides':[{'actionName':'View','content':'Inv_MutualFundRecord','formFactor':'Large','pageOrSobjectType':'Inv_MarketInstruments__c','type':'Flexipage'},
   {'actionName':'View','content':'Inv_HoldingRecord','formFactor':'Large','pageOrSobjectType':'Inv_Holding__c','type':'Flexipage'}],
  'formFactors':['Large','Small'],'isNavAutoTempTabsDisabled':False,'isNavPersonalizationDisabled':False,
  'label':'Investments','navType':'Standard','tabs':tabs,'uiType':'Lightning'});add('CustomApplication','Investments')
 for role in ['Inv_Viewer','Inv_MigrationAdmin','Inv_PortfolioManager']:
  path=DEST/'permissionsets'/(role+'.permissionset-meta.xml');root=ET.parse(path).getroot()
  for tab in tabs:
   if tab.startswith('standard-'):continue
   if not any(n.find('{'+NS+'}tab').text==tab for n in root.findall('{'+NS+'}tabSettings')):
    n=ET.SubElement(root,'{'+NS+'}tabSettings');ET.SubElement(n,'{'+NS+'}tab').text=tab;ET.SubElement(n,'{'+NS+'}visibility').text='Visible'
  root[:]=sorted(root,key=lambda n:n.tag);ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('PermissionSet',role)
 for table,api in [('portfolio.portfolios','Inv_PortfolioPortfolios__c'),('market.instruments','Inv_MarketInstruments__c'),('portfolio.sip_versions','Inv_PortfolioSipVersions__c'),('planning.plans','Inv_PlanningPlans__c'),('ops.import_runs','Inv_OpsImportRuns__c'),('ops.data_issues','Inv_OpsDataIssues__c')]:
  path=DEST/'objects'/api/(api+'.object-meta.xml');root=ET.parse(path).getroot();presentation=object_presentation(table)
  root.find('{'+NS+'}label').text=presentation['label'];root.find('{'+NS+'}pluralLabel').text=presentation['pluralLabel']
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('CustomObject',api)
 for api,fields in {
  'Inv_OpsImportRuns__c':['OperationalStatus__c','Portfolio__c','CASParserVersion__c','DuplicateOf__c','Failure__c'],
  'Inv_OpsImportRows__c':['RowKind__c','MatchStatus__c','Account__c','Fund__c','TradeDate__c','TransactionType__c','Units__c','AmountCurrency__c','CostCurrency__c','NAV__c','PeriodStart__c','PeriodEnd__c','OpeningUnits__c','ClosingUnits__c','MatchedEvent__c']}.items():
  path=next((DEST/'layouts').glob(api+'-*.layout-meta.xml'));root=ET.parse(path).getroot()
  for node in list(root.findall('{'+NS+'}layoutSections')):
   if node.find('{'+NS+'}label').text=='Statement review':root.remove(node)
  temp=DEST/'layouts/_review.layout-meta.xml';xml(temp,'Layout',{'layoutSections':section('Statement review',fields)});root.insert(0,ET.parse(temp).getroot()[0]);temp.unlink()
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('Layout',path.name.removesuffix('.layout-meta.xml'))
 for name,label,kind in [('Accounts','Account reconciliation','Account'),('Transactions','Transaction matches','Transaction')]:
  api='Inv_OpsImportRows__c'
  xml(DEST/'objects'/api/'listViews'/(name+'.listView-meta.xml'),'ListView',{'fullName':name,
    'columns':['NAME','MatchStatus__c','Account__c','Fund__c','PeriodEnd__c','ClosingUnits__c'] if kind=='Account' else ['NAME','MatchStatus__c','Account__c','Fund__c','TradeDate__c','Units__c','AmountCurrency__c'],
   'filterScope':'Everything','filters':{'field':'RowKind__c','operation':'equals','value':kind},'label':label});add('ListView',api+'.'+name)
 xml(DEST/'objects/Inv_MarketInstruments__c/listViews/Funds.listView-meta.xml','ListView',{'fullName':'Funds','columns':['NAME','DisplayName__c','AMFICode__c','MappingVerified__c','Tracked__c'],
  'filterScope':'Everything','filters':{'field':'MappingVerified__c','operation':'equals','value':'1'},'label':'Verified mutual funds'});add('ListView','Inv_MarketInstruments__c.Funds')
 api='Inv_MarketInstruments__c'
 xml(DEST/'objects'/api/'compactLayouts/Inv_Summary.compactLayout-meta.xml','CompactLayout',{'fullName':'Inv_Summary','fields':['DisplayName__c','AMFICode__c','Tracked__c','TERPercent__c','ExpenseDate__c'],'label':'Fund summary'});add('CompactLayout',api+'.Inv_Summary')
 path=DEST/'objects'/api/(api+'.object-meta.xml');root=ET.parse(path).getroot()
 for tag in ['compactLayoutAssignment','searchLayouts']:
  for node in root.findall('{'+NS+'}'+tag):root.remove(node)
 ET.SubElement(root,'{'+NS+'}compactLayoutAssignment').text='Inv_Summary'
 search=ET.SubElement(root,'{'+NS+'}searchLayouts')
 for tag in ['lookupDialogsAdditionalFields','searchResultsAdditionalFields']:
  for field in ['DisplayName__c','Isin__c','AMFICode__c']:ET.SubElement(search,'{'+NS+'}'+tag).text=field
 root[:]=sorted(root,key=lambda n:n.tag);ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True)
 for api,replacements in DISPLAY_FIELDS.items():
  for path in (DEST/'layouts').glob(api+'-*.layout-meta.xml'):
   root=ET.parse(path).getroot();changed=False
   for field in root.findall('.//{'+NS+'}field'):
    if field.text in replacements:field.text=replacements[field.text];changed=True
   if changed:
    ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('Layout',path.name.removesuffix('.layout-meta.xml'))
  for path in (DEST/'objects'/api/'listViews').glob('*.listView-meta.xml'):
   root=ET.parse(path).getroot();changed=False
   for column in root.findall('{'+NS+'}columns'):
    if column.text in replacements:column.text=replacements[column.text];changed=True
   if changed:
    ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('ListView',api+'.'+path.stem)
 if (DEST/'lwc/invWatchlistCard').exists():
  add('LightningComponentBundle','invWatchlistCard')
 for bundle in ['invPortfolioResearch','invFundResearch','invHoldingSummary','invPlanComparison','invRedemptionReview']:
  if (DEST/'lwc'/bundle).exists():add('LightningComponentBundle',bundle)
 # The existing fund record page remains a single reusable layout with live data from the selected fund record.
 for page,bundle,identifier in [('Inv_MutualFundRecord','c:invFundResearch','fundResearch')]:
  path=DEST/'flexipages'/(page+'.flexipage-meta.xml')
  if path.exists():
   root=ET.parse(path).getroot();main=next((r for r in root.findall('{'+NS+'}flexiPageRegions') if r.find('{'+NS+'}name').text=='main'),None)
   if main is not None:
    existing=next((i for i in main.findall('{'+NS+'}itemInstances')
     if i.find('.//{'+NS+'}componentName') is not None and i.find('.//{'+NS+'}componentName').text==bundle),None)
    if existing is None:existing=component_element(bundle,identifier,{})
    else:main.remove(existing)
    name_node=main.find('{'+NS+'}name')
    main.insert(list(main).index(name_node),existing)
    ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True)
   add('FlexiPage',page)
 # Reusable holding detail page: native highlights and details plus the account-centric analysis component.
 holding=DEST/'flexipages/Inv_HoldingRecord.flexipage-meta.xml'
 if not holding.exists():
  xml(holding,'FlexiPage',{'description':'Reusable holding page with account-specific position, reconciliation and redemption-lot context.',
   'flexiPageRegions':[{'itemInstances':[component('force:highlightsPanel','holdingHighlights',{'collapsed':'false','numVisibleActions':'5'})],'name':'header','type':'Region'},
    {'itemInstances':[component('force:detailPanel','holdingDetails',{}),component('c:invHoldingSummary','holdingSummary',{})],'name':'main','type':'Region'},
    {'itemInstances':[component('force:relatedListContainer','holdingRelatedLists',{})],'name':'sidebar','type':'Region'}],
   'masterLabel':'Investment Holding','sobjectType':'Inv_Holding__c','template':{'name':'flexipage:recordHomeTemplateDesktop'},'type':'RecordPage'})
 add('FlexiPage','Inv_HoldingRecord')
 # Add curated page bundles to the deployment manifest.
 add('StaticResource','chartjs')
 xml(ROOT/'manifest/portfolio-pages.xml','Package',{'types':[{'members':v,'name':k} for k,v in members.items()],'version':'68.0'})
 print('Generated native overview and context-filtered record charts')

if __name__=='__main__':main()
