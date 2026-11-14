import copy,unittest
from normalise import normalise,exact

class NormaliseTests(unittest.TestCase):
    def setUp(self):
        self.source={'file_type':'CAMS','cas_type':'DETAILED','statement_period':{'from':'01-Jan-2024','to':'31-Jan-2024'},
         'folios':[{'folio':'123 / 4','PAN':'do-not-copy','schemes':[{'isin':'SYNTHETIC','scheme':'Synthetic fund','open':'0','close':'20','close_calculated':'20',
          'transactions':[{'type':'PURCHASE','date':'2024-01-01','amount':'100.00','units':'10','nav':'10','balance':'10'},
           {'type':'STAMP_DUTY_TAX','date':'2024-01-01','amount':'0.01'},
           {'type':'PURCHASE','date':'2024-01-01','amount':'100.00','units':'10','nav':'10','balance':'20'}]}]}]}
    def test_identical_legitimate_purchases_remain_distinct(self):
        rows=normalise(self.source,'a'*64)['scopes'][0]['transactions']
        self.assertEqual([r['occurrence'] for r in rows],[1,2]);self.assertEqual(rows[0]['cost'],'100.01')
    def test_financial_precision_and_personal_data(self):
        result=normalise(self.source,'a'*64)
        self.assertNotIn('123 / 4',str(result));self.assertNotIn('PAN',str(result))
        self.assertEqual(exact('0.1234567890123456789012345678'),'0.1234567890123456789012345678')
    def test_unrecognized_movements_and_bad_balances_require_review(self):
        self.source['folios'][0]['schemes'][0]['transactions'][0]['type']='UNKNOWN'
        self.assertTrue(normalise(self.source,'a'*64)['scopes'][0]['warnings'])
    def test_summary_is_evidence_without_synthetic_purchases(self):
        scheme=self.source['folios'][0]['schemes'][0];scheme.update(open='20',transactions=[])
        result=normalise(self.source,'a'*64)['scopes'][0];self.assertEqual(result['transactions'],[]);self.assertEqual(result['warnings'],[])

if __name__=='__main__':unittest.main()
