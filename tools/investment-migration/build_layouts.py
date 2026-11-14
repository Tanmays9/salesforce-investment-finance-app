"""Standard Salesforce layouts for the preserved model; no custom UI runtime."""
import json
from prepare import ROOT,xml,apply_operational_overlays

def section(label,fields,one_column=False):
    columns=[fields] if one_column else [fields[::2],fields[1::2]]
    return {'customLabel':True,'detailHeading':True,'editHeading':True,'label':label,
        'layoutColumns':[{'layoutItems':[{'behavior':'Required' if f=='MigrationKey__c' else 'Readonly','field':f} for f in column]} for column in columns],
        'style':'OneColumn' if one_column else 'TwoColumnsTopToBottom'}

def main():
    mapping=json.loads((ROOT/'tools/investment-migration/mapping.json').read_text(encoding='utf-8'))
    dest=ROOT/'force-app/main/default';layouts=[];views=[]
    for table,spec in mapping.items():
        api=spec['object'];label=table.replace('.',' ').replace('_',' ').title()+' Layout'
        fields=[]
        for fld in spec['fields'].values():
            fields.append(fld['field'])
            if fld.get('numberField'):fields.append(fld['numberField'])
            if fld.get('knownField'):fields.append(fld['knownField'])
        sections=[section('Investment record',['Name','OwnerId','MigrationKey__c','SnapshotNotice__c']),section('Preserved values',fields)]
        if spec['relationships']:sections.append(section('Relationships',[r['field'] for r in spec['relationships']]))
        sections.extend([section('Provenance',['MigrationRun__c','NeonId__c','TwentyId__c','SourceHash__c','CreatedById','LastModifiedById']),section('Exact original data',['SourceJson__c'],True)])
        full_name=api+'-'+label
        xml(dest/'layouts'/(full_name+'.layout-meta.xml'),'Layout',{'layoutSections':sections,'relatedLists':{'relatedList':'RelatedFileList'},'showEmailCheckbox':False,'showHighlightsPanel':True,'showInteractionLogPanel':False,'showRunAssignmentRulesCheckbox':False,'showSubmitAndAttachButton':False})
        columns=['NAME']
        for col in ['name','event_date','observed_on','amount','units_delta','metric_name','status']:
            if col in spec['fields']:
                fld=spec['fields'][col];columns.append(fld.get('numberField',fld['field']))
        columns.append('MigrationKey__c')
        xml(dest/'objects'/api/'listViews/All.listView-meta.xml','ListView',{'fullName':'All','columns':columns[:6],'filterScope':'Everything','label':'All preserved records'})
        layouts.append(full_name);views.append(api+'.All')
    xml(ROOT/'manifest/investment-views.xml','Package',{'types':[{'members':layouts,'name':'Layout'},{'members':views,'name':'ListView'}],'version':'68.0'})
    print('Prepared',len(layouts),'native layouts and list views')
    apply_operational_overlays()

if __name__=='__main__':main()
