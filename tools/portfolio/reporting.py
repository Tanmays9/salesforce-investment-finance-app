"""Generate standard reports, dashboards and Lightning pages for portfolio review."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'investment-migration'))
from prepare import ROOT,xml
from build import DEST,OBJECTS,AUX_OBJECTS,section,text,number,date,lookup

MODELS={**OBJECTS,**AUX_OBJECTS,'Inv_MarketPriceObservations__c':('Price observation','NAV history',{
 'InstrumentRef__c':lookup('Fund','Inv_MarketInstruments__c','Prices'),'ObservedOn__c':date('NAV date'),
 'ValueNumber__c':number('NAV',10),'KindFilter__c':text('Price type',30),'QualityFilter__c':text('Quality',40),
 'ProviderRef__c':lookup('Provider','Inv_OpsProviders__c','Prices'),'SelectedNAV__c':{'label':'Selected NAV','type':'Checkbox'},'RecentChartDate__c':{'label':'Within five year chart window','type':'Checkbox'}})}

def main():
 members={}
 def add(kind,name):members.setdefault(kind,[]).append(name)
 for api,(singular,plural,fields) in MODELS.items():
  name=api.removesuffix('__c')+'_Analysis'
  columns=[{'checkedByDefault':True,'field':f,'table':api} for f in ['Id','Name','CreatedDate',*fields] if fields.get(f,{}).get('type')!='LongTextArea']
  columns += [{'checkedByDefault':False,'field':f+'.Id','table':api} for f,spec in fields.items() if spec.get('type')=='Lookup']
  xml(DEST/'reportTypes'/(name+'.reportType-meta.xml'),'ReportType',{'baseObject':api,'category':'other','deployed':True,
   'description':'Operational investment analysis with portfolio and fund context.','label':plural+' Analysis',
   'sections':{'columns':columns,
               'masterLabel':plural}});add('ReportType',name)
 for folder,kind in [('reports','ReportFolder'),('dashboards','DashboardFolder')]:
  xml(DEST/folder/('Investments.'+('reportFolder' if folder=='reports' else 'dashboardFolder')+'-meta.xml'),kind,
   {'accessType':'Shared','folderShares':{'accessLevel':'View','sharedTo':'Investment_Viewers','sharedToType':'Group'},'name':'Investments','publicFolderAccess':'ReadOnly'})
  add(kind,'Investments')
 specs=[
  ('Holdings','Current holdings','Inv_Holding__c',None,['Name','FundDisplayName__c','Account__c','Units__c','CostDisplay__c','MarketValueDisplay__c','UnrealizedGainDisplay__c','NAVDate__c','ReconciledThrough__c','Coverage__c'],[('Status__c','equals','Active')],None),
  ('FundAllocation','Allocation by fund','Inv_Holding__c','FundDisplayName__c',['FundDisplayName__c','MarketValueDisplay__c','Weight__c'],[('Status__c','equals','Active')],'MarketValueDisplay__c'),
  ('CategoryAllocation','Allocation by category','Inv_Holding__c','Category__c',['Name','MarketValueDisplay__c'],[('Status__c','equals','Active')],'MarketValueDisplay__c'),
  ('AMCAllocation','Allocation by AMC','Inv_Holding__c','AMC__c',['Name','MarketValueDisplay__c'],[('Status__c','equals','Active')],'MarketValueDisplay__c'),
  ('SIPAllocation','Monthly SIP allocation','Inv_Holding__c','FundDisplayName__c',['FundDisplayName__c','SIPAmountDisplay__c'],[('SIPAmount__c','greaterThan','0')],'SIPAmountDisplay__c'),
  ('HoldingGains','Unrealized gains by fund','Inv_Holding__c','FundDisplayName__c',['FundDisplayName__c','UnrealizedGainDisplay__c'],[('Status__c','equals','Active')],'UnrealizedGainDisplay__c'),
  ('Review','Holdings requiring review','Inv_Holding__c',None,['Name','Coverage__c','NAVDate__c','ReconciledThrough__c'],[('Coverage__c','notEqual','complete')],None),
  ('Exposure','Sector exposure','Inv_Exposure__c','Member__c',['Dimension__c','Member__c','ValueDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Sector')],'ValueDisplay__c'),
  ('AssetExposure','Asset-class exposure','Inv_Exposure__c','Member__c',['Member__c','ValueDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Asset class')],'ValueDisplay__c'),
  ('CapExposure','Market-cap exposure','Inv_Exposure__c','Member__c',['Member__c','ValueDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Market cap')],'ValueDisplay__c'),
  ('SecurityExposure','Underlying securities','Inv_Exposure__c','Member__c',['Member__c','ValueDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Security')],'ValueDisplay__c'),
  ('FundMetrics','Fund performance and coverage','Inv_FundMetric__c',None,['Fund__c','Metric__c','CounterpartyFund__c','ValuePercent__c','PeriodStart__c','PeriodEnd__c','Coverage__c'],[('Published__c','equals','true')],None),
  ('NAVHistory','Fund NAV history (last five years)','Inv_MarketPriceObservations__c','ObservedOn__c',['ValueNumber__c'],[('KindFilter__c','equals','NAV'),('QualityFilter__c','equals','accepted'),('SelectedNAV__c','equals','true'),('RecentChartDate__c','equals','true')],'ValueNumber__c'),
  ('ValuationHistory','Portfolio value history','Inv_PortfolioValuation__c','AsOf__c',['Name','MarketValueDisplay__c','CostDisplay__c','EarliestNAV__c','LatestNAV__c'],[('LatestForDate__c','equals','true')],'MarketValueDisplay__c'),
  ('PlanComparison','Current versus proposed fund values','Inv_PlanImpact__c','Fund__c',['Name','BaselineCurrencyDisplay__c','ProposedCurrencyDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Metric__c','equals','Market value INR')],'ProposedCurrencyDisplay__c'),
  ('PlanSIPs','Current versus proposed SIPs','Inv_PlanImpact__c','Fund__c',['Name','BaselineCurrencyDisplay__c','ProposedCurrencyDisplay__c','Coverage__c'],[('Published__c','equals','true'),('Metric__c','equals','Monthly SIP INR')],'ProposedCurrencyDisplay__c'),
  ('PlanWeights','Current versus proposed allocation','Inv_PlanImpact__c','Fund__c',['Name','Baseline__c','Proposed__c','Coverage__c'],[('Published__c','equals','true'),('Metric__c','equals','Allocation percent')],'Proposed__c'),
  ('PlanSectors','Current versus proposed sector exposure','Inv_PlanImpact__c','Member__c',['Name','Baseline__c','Proposed__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Sector')],'Proposed__c'),
  ('PlanAssets','Current versus proposed asset exposure','Inv_PlanImpact__c','Member__c',['Name','Baseline__c','Proposed__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Asset class')],'Proposed__c'),
  ('PlanCaps','Current versus proposed market-cap exposure','Inv_PlanImpact__c','Member__c',['Name','Baseline__c','Proposed__c','Coverage__c'],[('Published__c','equals','true'),('Dimension__c','equals','Market cap')],'Proposed__c'),
  ('PlanTargets','Allocation target deviations','Inv_PlanImpact__c','Fund__c',['Name','Baseline__c','Proposed__c','Coverage__c'],[('Published__c','equals','true'),('Metric__c','equals','Target deviation percentage points')],'Proposed__c'),
  ('Watchlist','Watchlist items','Inv_WatchlistItems__c',None,['Name','AssetType__c','Symbol__c','Exchange__c','ISIN__c','SchemeCode__c','Fund__c','Active__c','AddedOn__c'],[('Active__c','equals','true')],None),
 ]
 for name,label,api,group,cols,filters,measure in specs:
  def col(f):return api+'$'+f
  values={
   'columns':[{'aggregateTypes':'Average' if name=='NAVHistory' else 'Sum','field':col(f)} if f==measure else {'field':col(f)} for f in cols if f!=group]+
             [{'field':col(f+'.Id')} for f in ['Portfolio__c','Fund__c','InstrumentRef__c','PlanVersion__c'] if f in MODELS[api][2]],
   'format':'Summary' if group else 'Tabular','name':label[:40],'reportType':api.removesuffix('__c')+'_Analysis__c',
   'scope':'organization','showDetails':True,'showGrandTotal':True,'showSubTotals':True,
   'timeFrameFilter':{'dateColumn':api+'$CreatedDate','interval':'INTERVAL_CUSTOM'}}
  if filters:values['filter']={'criteriaItems':[{'column':col(f),'operator':op,'value':v} for f,op,v in filters]}
  if group:
   values['groupingsDown']={'dateGranularity':'Day','field':col(group),'sortOrder':'Asc'}
   values['chart']={'chartSummaries':{'aggregate':'Average' if name=='NAVHistory' else 'Sum','column':col(measure),'axisBinding':'y'},
    'chartType':'Line' if name in ['ValuationHistory','NAVHistory'] else 'VerticalColumn','enableHoverLabels':True,
    'expandOthers':True,'groupingColumn':col(group),'location':'CHART_TOP',
    'showAxisLabels':True,'showPercentage':False,'showValues':True,'size':'Large',
    'summaryAxisRange':'Auto','textSize':12,'title':label[:40],'titleSize':14}
  if name.startswith('Plan'):
   money=name in ['PlanComparison','PlanSIPs']
   baseline='BaselineCurrencyDisplay__c' if money else 'Baseline__c'
   proposed='ProposedCurrencyDisplay__c' if money else 'Proposed__c'
   for column in values['columns']:
    if column['field']==col(baseline):column['aggregateTypes']='Sum'
   values['chart']['chartSummaries']=[{'aggregate':'Sum','column':col(f),'axisBinding':'y'} for f in [baseline,proposed]]
  # Metadata elements use alphabetical schema order.
  xml(DEST/'reports/Investments'/(name+'.report-meta.xml'),'Report',dict(sorted(values.items())));add('Report','Investments/'+name)
 dashboard={'backgroundEndColor':'#FFFFFF','backgroundStartColor':'#FFFFFF','backgroundFadeDirection':'TopToBottom','dashboardType':'LoggedInUser',
  'description':'Published holdings and NAV dates. Missing cash history and stale sources are shown on records and the review report.',
  'isGridLayout':True,'title':'Portfolio Overview','titleColor':'#16325C','titleSize':12,'textColor':'#16325C',
  'dashboardGridLayout':{'dashboardGridComponents':[{'colSpan':6,'columnIndex':(i%2)*6,
   'dashboardComponent':{'componentType':'Bar','header':label,'chartAxisRange':'auto','report':'Investments/'+name,
    'showValues':True,'sortBy':'RowLabelAscending','useReportChart':True},'rowIndex':(i//2)*5,'rowSpan':5}
   for i,(name,label) in enumerate([('FundAllocation','Allocation by fund'),('CategoryAllocation','Allocation by category'),('AMCAllocation','Allocation by AMC'),('SIPAllocation','Monthly SIP allocation'),('HoldingGains','Unrealized gains'),('ValuationHistory','Portfolio value history')])],
   'numberOfColumns':12,'rowHeight':36}}
 xml(DEST/'dashboards/Investments/PortfolioOverview.dashboard-meta.xml','Dashboard',dict(sorted(dashboard.items())));add('Dashboard','Investments/PortfolioOverview')
 xml(ROOT/'manifest/portfolio-reporting.xml','Package',{'types':[{'members':v,'name':k} for k,v in members.items()],'version':'68.0'})
 print('Generated',len(specs),'standard reports and portfolio dashboard')

if __name__=='__main__':main()
