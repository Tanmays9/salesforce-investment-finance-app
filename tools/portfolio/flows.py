"""Standard Screen Flows and record actions; passwords never enter Flow variables."""
from build import DEST
from prepare import ROOT,xml,NS
from pages import component
import xml.etree.ElementTree as ET

def ref(value):return {'elementReference':value}
def literal(value):return {'stringValue':value}
def field(name,label,kind='String',required=True,choice=None,default=None):
 result={'name':name,'dataType':kind,'fieldText':label,'fieldType':'DropdownBox' if choice else 'InputField','isRequired':required}
 if choice:result['choiceReferences']=choice
 if kind=='Number':result['scale']=8 if name=='Units' else 2
 if default is not None:result['defaultValue']={'numberValue':default} if isinstance(default,int) else ref(default)
 return result
def screen(name,label,fields,next_node=None):
 value={'name':name,'label':label,'locationX':100,'locationY':100,'allowBack':True,'allowFinish':next_node is None,'allowPause':False,
  'fields':fields,'showFooter':True,'showHeader':True}
 if next_node:value['connector']={'targetReference':next_node}
 return value
def action(apex,operation,inputs):
 return {'name':'Apply','label':'Apply reviewed action','locationX':100,'locationY':200,'actionName':apex,'actionType':'apex',
  'connector':{'targetReference':'Result'},'faultConnector':{'targetReference':'Fault'},
  'inputParameters':[{'name':'operation','value':literal(operation)}]+[{'name':key,'value':value} for key,value in inputs.items()],
  'storeOutputAutomatically':True}
def choice(name,label,value):return {'name':name,'choiceText':label,'dataType':'String','value':literal(value)}
def dynamic(name,obj,display='Name',filters=None):
 result={'name':name,'dataType':'String','displayField':display,'object':obj,'valueField':'Id','sortField':'Name','sortOrder':'Asc'}
 if filters:result['filters']=filters
 return result

def main():
 members={}
 def add(kind,name):members.setdefault(kind,[]).append(name)
 portfolio=dynamic('Portfolios','Inv_PortfolioPortfolios__c','Name__c')
 funds=dynamic('Funds','Inv_MarketInstruments__c','DisplayName__c',[{'field':'MappingVerified__c','operator':'EqualTo','value':{'booleanValue':True}}])
 flows=[
  ('Inv_TrackFund','Set fund NAV tracking','InvFundActions',None,[field('Tracked','Include in daily NAV refresh','Boolean',True)],
   {'fundId':ref('recordId'),'tracked':ref('Tracked')},[],[]),
  ('Inv_CreatePlan','Create investment plan','InvPlanService','create',[
   field('Portfolio','Portfolio','String',True,['Portfolios']),field('Title','Plan name'),field('Goal','Objective','String',False),field('Budget','Monthly SIP budget INR','Number',True,default=35000)],
   {'portfolioId':ref('Portfolio'),'title':ref('Title'),'goal':ref('Goal'),'budget':ref('Budget')},[portfolio],[]),
  ('Inv_AddPlanAction','Add draft plan action','InvPlanService','add',[
   field('Fund','Fund (for fund-specific actions)','String',False,['Funds']),field('ActionType','Action','String',True,['Keep','Redeem','Buy','SetSIP','PauseSIP','CashHold']),
   field('Amount','Amount INR','Number',False),field('Units','Units to redeem (leave blank for amount)','Number',False),
   field('IntendedDate','Intended date','Date',True),field('Days','Cash-hold calendar days','Number',False),field('Reason','Rationale','String',False)],
   {'versionId':ref('recordId'),'fundId':ref('Fund'),'actionType':ref('ActionType'),'amount':ref('Amount'),'units':ref('Units'),'intendedDate':ref('IntendedDate'),'cashHoldDays':ref('Days'),'rationale':ref('Reason')},[funds],
   [choice('Keep','Keep','keep'),choice('Redeem','Redeem','redeem'),choice('Buy','Buy / reinvest','buy'),choice('SetSIP','Set monthly SIP','set_sip'),choice('PauseSIP','Pause SIP','pause_sip'),choice('CashHold','Hold cash','cash_hold')]),
  ('Inv_EvaluatePlan','Evaluate draft investment plan','InvPlanService','evaluate',[
   {'name':'Review','fieldType':'DisplayText','fieldText':'<p>Compare this draft with its published baseline. This action does not execute trades or change your actual holdings.</p>'}],{'versionId':ref('recordId')},[],[]),
  ('Inv_SetPlanTarget','Set fund allocation target','InvPlanService','target',[
   field('Fund','Verified fund','String',True,['Funds']),field('Target','Target portfolio allocation percent','Number',True)],
   {'versionId':ref('recordId'),'fundId':ref('Fund'),'targetPercent':ref('Target')},[funds],[]),
  ('Inv_SetDependency','Link plan actions','InvPlanService','dependency',[
   field('Action','Dependent action','String',True,['Actions']),field('Preceding','Prerequisite action','String',True,['Actions']),field('Lag','Minimum lag in calendar days','Number',True,default=0)],
   {'versionId':ref('recordId'),'actionId':ref('Action'),'prerequisiteId':ref('Preceding'),'lagDays':ref('Lag')},
   [dynamic('Actions','Inv_PlanningActions__c','Name',[{'field':'PlanVersionRef__c','operator':'EqualTo','value':ref('recordId')}])],[]),
  ('Inv_ClonePlan','Clone investment plan version','InvPlanService','clone',[
   {'name':'Review','fieldType':'DisplayText','fieldText':'<p>Create a new draft against the latest published portfolio baseline. The previous version remains preserved.</p>'},field('Budget','New monthly SIP budget INR (blank retains existing budget)','Number',False)],{'versionId':ref('recordId'),'budget':ref('Budget')},[],[]),
  ('Inv_ApprovePlan','Approve investment plan version','InvPlanService','approve',[
   {'name':'Review','fieldType':'DisplayText','fieldText':'<p>Re-evaluate and freeze this plan version. Missing redemption policy or tax coverage blocks approval. Approval does not execute broker transactions or change SIP mandates.</p>'}],{'versionId':ref('recordId')},[],[]),
  ('Inv_MapCASAccount','Map CAS account','InvImportActions','map',[
   field('Account','Existing investment account','String',True,['Accounts'])],{'summaryId':ref('recordId'),'accountId':ref('Account')},[dynamic('Accounts','Inv_PortfolioAccounts__c','MaskedReference__c')],[]),
  ('Inv_ConfirmCASAccount','Confirm reconciled CAS account','InvImportActions','confirm',[
   {'name':'Review','fieldType':'DisplayText','fieldText':'<p>Confirm only after reviewing this account and its transaction matches. Possible duplicates, conflicts or unit discrepancies block posting. Existing transactions are retained.</p>'}],{'summaryId':ref('recordId')},[],[]),
 ]
 add_spec=next(spec for spec in flows if spec[0]=='Inv_AddPlanAction')
 edit_inputs=dict(add_spec[5]);edit_inputs.pop('versionId');edit_inputs['actionId']=ref('recordId')
 flows.append(('Inv_EditPlanAction','Edit draft plan action','InvPlanService','edit',add_spec[4],edit_inputs,add_spec[6],add_spec[7]))
 flows.append(('Inv_RemovePlanAction','Remove draft plan action','InvPlanService','remove',[
  {'name':'Review','fieldType':'DisplayText','fieldText':'<p>Remove this user-created draft action. Imported history and frozen plan versions cannot be changed. The removal is recorded in audit history.</p>'}],{'actionId':ref('recordId')},[],[]))
 for name,label,apex,operation,fields,inputs,dynamics,choices in flows:
  call=action(apex,operation,inputs)
  if operation is None:call['inputParameters']=[item for item in call['inputParameters'] if item['name']!='operation']
  values={'apiVersion':'68.0','actionCalls':call,'choices':choices,'dynamicChoiceSets':dynamics,
   'environments':'Default','interviewLabel':label+' {!$Flow.CurrentDateTime}','label':label,'processType':'Flow',
   'screens':[screen('Input',label,fields,'Apply'),screen('Result','Result',[
    {'name':'Message','fieldType':'DisplayText','fieldText':'<p>{!Apply.message}</p>'}]),
    screen('Fault','Review required',[{'name':'Error','fieldType':'DisplayText','fieldText':'<p>{!$Flow.FaultMessage}</p>'}])],
   'start':{'locationX':0,'locationY':0,'connector':{'targetReference':'Input'}},'status':'Active',
   'variables':{'name':'recordId','dataType':'String','isCollection':False,'isInput':True,'isOutput':False}}
  xml(DEST/'flows'/(name+'.flow-meta.xml'),'Flow',dict(sorted((k,v) for k,v in values.items() if v)));add('Flow',name)
 # Standard Files upload handles the document. The only custom screen component holds the transient PDF password.
 values={'apiVersion':'68.0','actionCalls':action('InvImportActions','create',{'portfolioId':ref('Portfolio'),'documentIds':ref('Upload.contentDocIds')}),
  'dynamicChoiceSets':[portfolio],'environments':'Default','interviewLabel':'Import CAS {!$Flow.CurrentDateTime}','label':'Import CAS statement','processType':'Flow',
  'screens':[screen('Input','Upload CAS statement',[
   field('Portfolio','Destination portfolio','String',True,['Portfolios']),
   {'name':'Upload','extensionName':'forceContent:fileUpload','fieldType':'ComponentInstance','inputParameters':[
    {'name':'label','value':literal('Original issuer CAS PDF')},{'name':'multiple','value':{'booleanValue':False}},{'name':'accept','value':literal('.pdf')}],
    'isRequired':True,'storeOutputAutomatically':True}],'Apply'),
   screen('Result','Parse statement',[{'name':'Parser','extensionName':'c:invParseStatement','fieldType':'ComponentInstance',
    'inputParameters':[{'name':'runId','value':ref('Apply.runId')}],'storeOutputAutomatically':True},
    {'name':'Link','fieldType':'DisplayText','fieldText':'<p><a href="/{!Apply.runId}" target="_blank">Open import and staged rows</a></p>'}]),
   screen('Fault','Review required',[{'name':'Error','fieldType':'DisplayText','fieldText':'<p>{!$Flow.FaultMessage}</p>'}])],
  'start':{'locationX':0,'locationY':0,'connector':{'targetReference':'Input'}},'status':'Active'}
 xml(DEST/'flows/Inv_ImportCAS.flow-meta.xml','Flow',dict(sorted(values.items())));add('Flow','Inv_ImportCAS')
 actions={
  'Inv_MarketInstruments__c':[('TrackFund','Set NAV tracking','Inv_TrackFund')],
  'Inv_PortfolioPortfolios__c':[('CreatePlan','Create plan','Inv_CreatePlan'),('ImportCAS','Import CAS','Inv_ImportCAS')],
  'Inv_PlanningPlanVersions__c':[('AddAction','Add action','Inv_AddPlanAction'),('SetTarget','Set allocation target','Inv_SetPlanTarget'),('Dependency','Link actions','Inv_SetDependency'),('Evaluate','Evaluate plan','Inv_EvaluatePlan'),('CloneVersion','Clone version','Inv_ClonePlan'),('Approve','Approve version','Inv_ApprovePlan')],
  'Inv_PlanningActions__c':[('EditDraft','Edit draft action','Inv_EditPlanAction'),('RemoveDraft','Remove draft action','Inv_RemovePlanAction')],
  'Inv_OpsImportRows__c':[('MapAccount','Map account','Inv_MapCASAccount'),('ConfirmAccount','Confirm account','Inv_ConfirmCASAccount')],
 }
 for api,entries in actions.items():
  for name,label,flow in entries:
   full=api+'.'+name;xml(DEST/'quickActions'/(full+'.quickAction-meta.xml'),'QuickAction',{'flowDefinition':flow,'label':label,'optionsCreateFeedItem':False,'type':'Flow'});add('QuickAction',full)
  path=next((DEST/'layouts').glob(api+'-*.layout-meta.xml'));root=ET.parse(path).getroot()
  for node in list(root.findall('{'+NS+'}platformActionList')):root.remove(node)
  # Reuse the XML writer to keep the platform-action sequence valid.
  temp=DEST/'layouts/_actions.layout-meta.xml'
  xml(temp,'Layout',{'platformActionList':{'actionListContext':'Record','platformActionListItems':[
   {'actionName':api+'.'+name,'actionType':'QuickAction','sortOrder':i} for i,(name,_,_) in enumerate(entries)]}})
  root.append(ET.parse(temp).getroot()[0]);temp.unlink();root[:]=sorted(root,key=lambda n:n.tag)
  ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('Layout',path.name.removesuffix('.layout-meta.xml'))
 for api,relation_field in [('Inv_PlanningPlans__c','PlanRef__c'),('Inv_PlanningPlanVersions__c','PlanVersionRef__c'),('Inv_OpsImportRuns__c','RunRef__c')]:
  children=['Inv_PlanningPlanVersions__c'] if api=='Inv_PlanningPlans__c' else ['Inv_PlanningActions__c','Inv_PlanningTargets__c','Inv_PlanImpact__c'] if api=='Inv_PlanningPlanVersions__c' else ['Inv_OpsImportRows__c']
  for child in children:
   actual='PlanVersion__c' if child=='Inv_PlanImpact__c' else relation_field
   path=next((DEST/'layouts').glob(api+'-*.layout-meta.xml'));root=ET.parse(path).getroot();name=child+'.'+actual
   if not any(n.find('{'+NS+'}relatedList').text==name for n in root.findall('{'+NS+'}relatedLists')):
    node=ET.SubElement(root,'{'+NS+'}relatedLists');ET.SubElement(node,'{'+NS+'}fields').text='NAME';ET.SubElement(node,'{'+NS+'}relatedList').text=name
   root[:]=sorted(root,key=lambda n:n.tag);ET.indent(root,space='  ');ET.ElementTree(root).write(path,encoding='UTF-8',xml_declaration=True);add('Layout',path.name.removesuffix('.layout-meta.xml'))
 xml(ROOT/'manifest/portfolio-flows.xml','Package',{'types':[{'members':sorted(set(v)),'name':k} for k,v in members.items()],'version':'68.0'})
 print('Generated standard plan/import Screen Flows and record actions')

if __name__=='__main__':main()
