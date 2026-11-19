"""Create a restricted CAS integration identity and certificate-based OAuth app.

All generated credentials and metadata containing consumer credentials stay in the
protected runtime directory. No human Salesforce CLI token is used by Lambda.
"""
import argparse,datetime,json,sys,subprocess,urllib.request,urllib.parse,urllib.error,xml.etree.ElementTree as ET
from pathlib import Path
import boto3,jwt
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'investment-migration'))
from org_config import aws_region, cas_auth_secret_name, org_id_for_stage
from migrate import Salesforce
from prepare import PRIVATE,xml,NS

def main():
 p=argparse.ArgumentParser();p.add_argument('--target-org',required=True);p.add_argument('--stage',choices=['sandbox','production'],required=True);args=p.parse_args()
 s=Salesforce(args.target_org);org=s.query('SELECT Id,IsSandbox FROM Organization')[0]
 expected=org_id_for_stage(args.stage)
 if org['Id']!=expected:raise RuntimeError('Wrong investment org for parser stage')
 directory=PRIVATE/'parser-auth'/args.stage;directory.mkdir(parents=True,exist_ok=True)
 key_path=directory/'signing-key.pem';cert_path=directory/'signing-certificate.pem'
 if not key_path.exists():
  key=rsa.generate_private_key(public_exponent=65537,key_size=3072)
  now=datetime.datetime.now(datetime.timezone.utc)
  subject=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Investment CAS Parser '+args.stage)])
  cert=x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(key.public_key()).serial_number(x509.random_serial_number()).not_valid_before(now-datetime.timedelta(minutes=5)).not_valid_after(now+datetime.timedelta(days=365)).sign(key,hashes.SHA256())
  key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
  cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
 username='cas-parser.'+org['Id'].lower()+'@integration.invalid'
 users=s.query("SELECT Id FROM User WHERE Username='"+username+"'")
 if users:user_id=users[0]['Id']
 else:
  profile=s.query("SELECT Id FROM Profile WHERE Name='Minimum Access - API Only Integrations'")[0]['Id']
  user_id=s.request('POST','/services/data/v68.0/sobjects/User',{'Username':username,'Email':'cas-parser@example.invalid','LastName':'Investment CAS Parser',
   'Alias':'casparse','ProfileId':profile,'TimeZoneSidKey':'Asia/Kolkata','LocaleSidKey':'en_IN','EmailEncodingKey':'UTF-8','LanguageLocaleKey':'en_US'})['id']
 licenses=s.query("SELECT Id,DeveloperName,MasterLabel FROM PermissionSetLicense WHERE MasterLabel LIKE '%Integration%'")
 for license in licenses:
  if 'Salesforce API Integration' not in license['MasterLabel']:continue
  if not s.query("SELECT Id FROM PermissionSetLicenseAssign WHERE AssigneeId='"+user_id+"' AND PermissionSetLicenseId='"+license['Id']+"'"):
   s.request('POST','/services/data/v68.0/sobjects/PermissionSetLicenseAssign',{'AssigneeId':user_id,'PermissionSetLicenseId':license['Id']})
 permission=s.query("SELECT Id FROM PermissionSet WHERE Name='Inv_Parser'")[0]['Id']
 if not s.query("SELECT Id FROM PermissionSetAssignment WHERE AssigneeId='"+user_id+"' AND PermissionSetId='"+permission+"'"):
  s.request('POST','/services/data/v68.0/sobjects/PermissionSetAssignment',{'AssigneeId':user_id,'PermissionSetId':permission})
 source=directory/'force-app/main/default';app='InvCASParser'
 xml(source/'externalClientApps'/(app+'.eca-meta.xml'),'ExternalClientApplication',{'contactEmail':'cas-parser@example.invalid','description':'Restricted statement extraction worker; cannot confirm or post transactions.','distributionState':'Local','isProtected':False,'label':'Investment CAS Parser'})
 # Salesforce requires RefreshToken scope for preauthorized JWT grants; the worker obtains short-lived tokens with its certificate.
 xml(source/'extlClntAppOauthSettings'/(app+'.ecaOauth-meta.xml'),'ExtlClntAppOauthSettings',{'commaSeparatedOauthScopes':'Api,RefreshToken','externalClientApplication':app,'label':'Investment CAS Parser API'})
 xml(source/'extlClntAppGlobalOauthSets'/(app+'.ecaGlblOauth-meta.xml'),'ExtlClntAppGlobalOauthSettings',{
  'callbackUrl':s.base+'/services/oauth2/success','certificate':cert_path.read_text(),'externalClientApplication':app,
  'isConsumerSecretOptional':False,'isPkceRequired':True,'isSecretRequiredForRefreshToken':True,'label':'Investment CAS Parser certificate'})
 xml(source/'extlClntAppOauthPolicies'/(app+'.ecaOauthPlcy-meta.xml'),'ExtlClntAppOauthConfigurablePolicies',{
  'commaSeparatedPermissionSet':'Inv_Parser','externalClientApplication':app,'label':'Investment CAS Parser restricted policy','permittedUsersPolicyType':'AdminApprovedPreAuthorized',
  'refreshTokenPolicyType':'Zero'})
 (directory/'sfdx-project.json').write_text(json.dumps({'packageDirectories':[{'path':'force-app','default':True}],'sourceApiVersion':'68.0'}))
 command=['sf.cmd','project','deploy','start','--source-dir','force-app','--target-org',args.target_org,'--wait','10','--json']
 result=subprocess.run(command,cwd=directory,capture_output=True,text=True,encoding='utf-8')
 (directory/'deploy.json').write_text(result.stdout,encoding='utf-8')
 if result.returncode:raise RuntimeError('Parser OAuth deployment failed; protected deployment report: '+str(directory/'deploy.json'))
 result=subprocess.run(['sf.cmd','project','retrieve','start','--metadata','ExtlClntAppGlobalOauthSettings:'+app,'--target-org',args.target_org,'--wait','10','--json'],cwd=directory,capture_output=True,text=True,encoding='utf-8')
 (directory/'retrieve.json').write_text(result.stdout,encoding='utf-8')
 if result.returncode:raise RuntimeError('Cannot read parser OAuth consumer key; see protected retrieval report')
 root=ET.parse(source/'extlClntAppGlobalOauthSets'/(app+'.ecaGlblOauth-meta.xml')).getroot()
 client=root.find('{'+NS+'}consumerKey')
 if client is None:raise RuntimeError('OAuth consumer key was not returned; verify org OAuth metadata access')
 now=int(datetime.datetime.now(datetime.timezone.utc).timestamp())
 assertion=jwt.encode({'iss':client.text,'sub':username,'aud':s.base,'exp':now+120},key_path.read_bytes(),algorithm='RS256')
 request=urllib.request.Request(s.base+'/services/oauth2/token',urllib.parse.urlencode({'grant_type':'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion':assertion}).encode())
 try:
  with urllib.request.urlopen(request,timeout=30) as response:token=json.load(response)
 except urllib.error.HTTPError as error:
  failure=json.loads(error.read());safe={k:failure.get(k) for k in ['error','error_description']}
  (directory/'oauth-error.json').write_text(json.dumps(safe));raise RuntimeError('Parser OAuth JWT test failed: '+str(safe)) from None
 if 'access_token' not in token:raise RuntimeError('OAuth response did not contain an access token')
 secret={'sf_base_url':s.base,'client_id':client.text,'username':username,'private_key':key_path.read_text(),'audience':s.base}
 secrets=boto3.client('secretsmanager',region_name=aws_region());name=cas_auth_secret_name(args.stage)
 try:arn=secrets.create_secret(Name=name,Description='Certificate-based Salesforce CAS parser identity',SecretString=json.dumps(secret),Tags=[{'Key':'Project','Value':'Investments'}])['ARN']
 except secrets.exceptions.ResourceExistsException:arn=secrets.put_secret_value(SecretId=name,SecretString=json.dumps(secret))['ARN']
 (directory/'identity.json').write_text(json.dumps({'orgId':org['Id'],'username':username,'userId':user_id,'secretArn':arn,'authenticated':True},indent=2))
 print(json.dumps({'stage':args.stage,'authenticated':True,'secretArn':arn}))

if __name__=='__main__':main()
