"""No network or secrets: exercise ephemeral-password retry retention."""
import importlib.util,json,os,sys,types,unittest
from pathlib import Path
from unittest.mock import Mock,patch

class WorkerTests(unittest.TestCase):
    def load(self):
        path=Path(__file__).with_name('worker.py')
        spec=importlib.util.spec_from_file_location('cas_worker_test',path);module=importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules,{'boto3':types.SimpleNamespace(client=lambda _:Mock()),'jwt':Mock(),'casparser':Mock()}):spec.loader.exec_module(module)
        module.sf_session=Mock(return_value=('https://example.invalid','test-only'))
        module.secret=Mock(return_value={'runId':'run','expiresAt':9999999999,'password':'test-only'})
        module.normalise=Mock(return_value={'scopes':[]});module.casparser.read_cas_pdf.return_value='{}'
        return module
    def test_transient_error_retains_password_for_retry(self):
        module=self.load();module.sf=Mock(side_effect=[{'ContentVersionId__c':'version','OperationalStatus__c':'Queued'},TimeoutError(),None])
        with patch.dict(os.environ,{'PASSWORD_PREFIX':'private/'}):
            with self.assertRaises(RuntimeError):module.handler({'runId':'run','contentVersionId':'version','passwordRef':'private/ref'},Mock())
        module.secrets.delete_secret.assert_not_called()
    def test_success_removes_password(self):
        module=self.load();module.sf=Mock(side_effect=[{'ContentVersionId__c':'version','OperationalStatus__c':'Queued'},b'pdf',None])
        context=Mock();context.get_remaining_time_in_millis.return_value=299000
        with patch.dict(os.environ,{'PASSWORD_PREFIX':'private/'}):
            result=module.handler({'runId':'run','contentVersionId':'version','passwordRef':'private/ref'},context)
        self.assertEqual('staged',result['status']);module.secrets.delete_secret.assert_called_once()

if __name__=='__main__':unittest.main()
