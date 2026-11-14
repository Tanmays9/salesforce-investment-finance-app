import copy
import unittest
from unittest.mock import Mock,patch
from prepare import normalize,reconcile,digest,object_presentation,NUMBER_PREFIXES,ROOT,NS
from migrate import records,key,number_projection,preserve_long_text,timestamp_projection,ensure_freeze_live

class MigrationTests(unittest.TestCase):
    def test_object_presentation_matches_all_mapped_entities(self):
        import json
        import xml.etree.ElementTree as ET
        mapping=json.loads((ROOT/'tools/investment-migration/mapping.json').read_text())
        self.assertEqual(set(mapping),set(NUMBER_PREFIXES))
        self.assertEqual(len(set(NUMBER_PREFIXES.values())),len(mapping))
        for table,spec in mapping.items():
            expected=object_presentation(table)
            self.assertNotIn('Records',expected['pluralLabel'])
            root=ET.parse(ROOT/'force-app/main/default/objects'/spec['object']/(spec['object']+'.object-meta.xml')).getroot()
            self.assertEqual(root.find('{'+NS+'}pluralLabel').text,expected['pluralLabel'])
            self.assertEqual(root.find('{'+NS+'}nameField/{'+NS+'}displayFormat').text,expected['nameField']['displayFormat'])
    def setUp(self):
        self.mapping={'portfolio.events':{'name':'event','fields':[{'sourceColumn':'amount','name':'dataAmount','type':'NUMBER'}],'relations':[]}}
        self.neon={'portfolio.events':[{'id':1,'amount':'12.3400'}]}
        self.twenty={'event':[{'id':'uuid-1','sourceRecord':{'id':1,'amount':12.34},'dataAmount':12.34,'deletedAt':None}]}
    def test_numeric_representation_is_not_a_conflict(self):
        rows,conflicts,_=reconcile(self.neon,self.twenty,self.mapping)
        self.assertEqual(conflicts,[])
        self.assertEqual(rows['portfolio.events'][0]['twentyId'],'uuid-1')
    def test_economic_edit_blocks_acceptance(self):
        self.twenty['event'][0]['dataAmount']=99
        _,conflicts,_=reconcile(self.neon,self.twenty,self.mapping)
        self.assertEqual(conflicts[0]['field'],'amount')
    def test_deletion_and_missing_records_are_not_silently_accepted(self):
        self.twenty['event'][0]['deletedAt']='2026-11-01'
        _,conflicts,_=reconcile(self.neon,self.twenty,self.mapping)
        self.assertEqual(conflicts[0]['kind'],'twenty_deleted')
        _,conflicts,_=reconcile(self.neon,{'event':[]},self.mapping)
        self.assertEqual(conflicts[0]['kind'],'missing_from_twenty')
    def test_decimal_precision_remains_exact(self):
        a={'value':'0.12345678901234567890123456789'}
        self.assertNotEqual(digest(a),digest({'value':'0.12345678901234568'}))
    def test_null_and_zero_differ(self):
        self.assertNotEqual(normalize(None),normalize(0))
    def test_unresolved_link_refuses_load(self):
        spec={'relationships':[{'field':'AccountRef__c','column':'account_id','target':'portfolio.accounts'}]}
        with self.assertRaisesRegex(ValueError,'Unresolved relationship'):
            records('portfolio.events',[{'key':'1','data':{'account_id':2}}],spec,'test',True,{})
    def test_null_links_are_explicitly_cleared(self):
        spec={'relationships':[{'field':'AccountRef__c','column':'account_id','target':'portfolio.accounts'}]}
        row=records('portfolio.events',[{'key':'1','data':{'account_id':None}}],spec,'test',True,{})[0]
        self.assertEqual(row['AccountRef__c'],'#N/A')
    def test_scoped_ids_do_not_collide(self):
        self.assertNotEqual(key('portfolio.accounts',1),key('portfolio.events',1))
    def test_reporting_number_never_rounds_or_overflows(self):
        self.assertEqual(number_projection('12.12345678901',10),'#N/A')
        self.assertEqual(number_projection('100000000',10),'#N/A')
        self.assertEqual(number_projection('12.3400',10),'12.3400')
        self.assertEqual(number_projection('twenty:uuid-1',0),'#N/A')
    def test_oversized_text_retains_content_address(self):
        import hashlib,json
        original='x'*131073
        self.assertEqual(json.loads(preserve_long_text(original))['preservedFileSha256'],hashlib.sha256(original.encode()).hexdigest())
    def test_unknown_boolean_is_distinct_from_false(self):
        spec={'fields':{'flag':{'field':'Flag__c','sourceType':'boolean','knownField':'FlagKnown__c'}},'relationships':[]}
        source={'key':'1','data':{'flag':None},'sourceRecord':{},'neon':None,'twentyId':None}
        unknown=records('test',[source],spec,'test')[0]
        source['data']['flag']=False
        known_false=records('test',[source],spec,'test')[0]
        self.assertEqual(unknown['Flag__c'],known_false['Flag__c'])
        self.assertEqual(unknown['FlagKnown__c'],'false')
        self.assertEqual(known_false['FlagKnown__c'],'true')
    def test_timestamp_projection_matches_bulk_precision(self):
        self.assertEqual(timestamp_projection('2026-11-13T10:20:30.123456+00:00'),timestamp_projection('2026-11-13T10:20:30.000Z'))
    def test_production_freeze_guard_rejects_inactive_stale_or_released_source(self):
        import datetime as dt,json
        from unittest.mock import MagicMock
        state=Mock();release=Mock();release.exists.return_value=False
        root=MagicMock();root.__truediv__.side_effect=lambda name:state if name=='freeze-state.json' else release
        valid={'active':True,'lockedTables':38,'heartbeatAt':dt.datetime.now(dt.timezone.utc).isoformat()}
        with patch('migrate.PRIVATE',root):
            state.read_text.return_value=json.dumps(valid);ensure_freeze_live()
            for change in [{'active':False},{'lockedTables':37},{'heartbeatAt':(dt.datetime.now(dt.timezone.utc)-dt.timedelta(minutes=2)).isoformat()}]:
                state.read_text.return_value=json.dumps({**valid,**change})
                with self.assertRaisesRegex(RuntimeError,'production writes stopped'):ensure_freeze_live()
            state.read_text.return_value=json.dumps(valid);release.exists.return_value=True
            with self.assertRaisesRegex(RuntimeError,'production writes stopped'):ensure_freeze_live()

if __name__=='__main__':unittest.main()
