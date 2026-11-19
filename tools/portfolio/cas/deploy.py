"""Build and deploy the dedicated parser stack, then configure its Salesforce credential."""
import argparse,base64,json,subprocess,sys,time
from pathlib import Path
import boto3
from infrastructure import template
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'investment-migration'))
from org_config import aws_region, org_id_for_stage
from migrate import Salesforce
from prepare import PRIVATE,xml

def run(command,*,cwd=None,input=None,log=None):
    result=subprocess.run(command,cwd=cwd,input=input,capture_output=True,text=True,encoding='utf-8')
    if log:log.write_text(result.stdout+'\n'+result.stderr,encoding='utf-8')
    if result.returncode:raise RuntimeError('Command failed; inspect protected build/deploy log')
    return result.stdout

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--stage',choices=['sandbox','production'],required=True);parser.add_argument('--target-org',required=True);args=parser.parse_args()
    s=Salesforce(args.target_org);org=s.query('SELECT Id FROM Organization')[0]['Id']
    expected=org_id_for_stage(args.stage)
    if org!=expected:raise RuntimeError('Unexpected Salesforce deployment target')
    directory=PRIVATE/'parser-auth'/args.stage
    identity=json.loads((directory/'identity.json').read_text());secret=identity['secretArn']
    if not identity['authenticated']:raise RuntimeError('Salesforce parser identity has not passed authentication')
    region=aws_region();session=boto3.Session(region_name=region);ecr=session.client('ecr');cf=session.client('cloudformation');iam=session.client('iam')
    repository='investments-cas-parser'
    try:repo=ecr.create_repository(repositoryName=repository,imageScanningConfiguration={'scanOnPush':True},imageTagMutability='MUTABLE')['repository']
    except ecr.exceptions.RepositoryAlreadyExistsException:repo=ecr.describe_repositories(repositoryNames=[repository])['repositories'][0]
    auth=ecr.get_authorization_token()['authorizationData'][0];user,password=base64.b64decode(auth['authorizationToken']).decode().split(':',1)
    run(['docker','login','--username',user,'--password-stdin',auth['proxyEndpoint']],input=password,log=directory/'docker-login.log')
    password=None
    image=repo['repositoryUri']+':casparser-1.4.1-'+str(int(time.time()))
    run(['docker','build','--platform','linux/amd64','--provenance=false','-t',image,'.'],cwd=Path(__file__).parent,log=directory/'docker-build.log')
    run(['docker','push',image],log=directory/'docker-push.log')
    configuration=template(args.stage,image,secret)
    configuration['Resources']['Dispatcher']['Properties']['Code']['ZipFile']=Path(__file__).with_name('dispatcher.py').read_text()
    (directory/'cloudformation.json').write_text(json.dumps(configuration,indent=2))
    name='investments-cas-'+args.stage
    parameters={'StackName':name,'TemplateBody':json.dumps(configuration),'Capabilities':['CAPABILITY_NAMED_IAM'],'Tags':[{'Key':'Project','Value':'Investments'}]}
    try:
        cf.describe_stacks(StackName=name);cf.update_stack(**parameters);waiter=cf.get_waiter('stack_update_complete')
    except cf.exceptions.ClientError as error:
        if 'does not exist' not in str(error):raise
        cf.create_stack(**parameters);waiter=cf.get_waiter('stack_create_complete')
    # Polling is performed by the caller; this command can be resumed with --configuration-only in future revisions.
    while True:
        stack=cf.describe_stacks(StackName=name)['Stacks'][0];status=stack['StackStatus']
        if status in ['CREATE_COMPLETE','UPDATE_COMPLETE']:break
        if 'FAILED' in status or 'ROLLBACK' in status:raise RuntimeError('Parser infrastructure deployment failed: '+status)
        print('Parser infrastructure: '+status,flush=True);time.sleep(10)
    outputs={o['OutputKey']:o['OutputValue'] for o in stack['Outputs']}
    credentials_path=directory/'salesforce-invoker-key.json'
    if credentials_path.exists():key=json.loads(credentials_path.read_text())
    else:
        key=iam.create_access_key(UserName=outputs['InvokerUser'])['AccessKey'];credentials_path.write_text(json.dumps(key,default=str))
    source=directory/'credential/force-app/main/default/namedCredentials';source.mkdir(parents=True,exist_ok=True)
    xml(source/'Inv_CASParser.namedCredential-meta.xml','NamedCredential',{'allowMergeFieldsInBody':False,'allowMergeFieldsInHeader':False,
      'awsAccessKey':key['AccessKeyId'],'awsAccessSecret':key['SecretAccessKey'],'awsRegion':region,'awsService':'execute-api',
      'endpoint':outputs['ApiUrl'],'generateAuthorizationHeader':True,'label':'Private CAS parser','principalType':'NamedUser','protocol':'AwsSv4'})
    project=directory/'credential';(project/'sfdx-project.json').write_text(json.dumps({'packageDirectories':[{'path':'force-app','default':True}],'sourceApiVersion':'68.0'}))
    run(['sf.cmd','project','deploy','start','--source-dir','force-app','--target-org',args.target_org,'--wait','10','--json'],cwd=project,log=directory/'credential-deploy.json')
    (directory/'infrastructure.json').write_text(json.dumps({'stack':name,'image':image,'outputs':outputs,'status':status},indent=2))
    print(json.dumps({'stage':args.stage,'stackStatus':status,'api':outputs['ApiUrl']}))

if __name__=='__main__':main()
