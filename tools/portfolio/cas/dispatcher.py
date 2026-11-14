"""IAM-authenticated job admission and short-lived encrypted password handoff."""
import json,os,re,time,uuid,datetime
import boto3
secrets=boto3.client('secretsmanager');functions=boto3.client('lambda')

def response(status,body):return {'statusCode':status,'headers':{'Content-Type':'application/json'},'body':json.dumps(body)}

def handler(event,context):
    prefix=os.environ['PASSWORD_PREFIX']
    if event.get('cleanup') is True:
        removed=0
        for page in secrets.get_paginator('list_secrets').paginate(Filters=[{'Key':'name','Values':[prefix]}]):
            for item in page['SecretList']:
                if item['Name'].startswith(prefix) and item['CreatedDate'].timestamp()<time.time()-900:
                    secrets.delete_secret(SecretId=item['ARN'],ForceDeleteWithoutRecovery=True);removed+=1
        return {'expiredSecretsRemoved':removed}
    try:
        body=json.loads(event.get('body') or '{}');route=event['path'];run=body.get('runId','')
        if not re.fullmatch(r'[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?',run):return response(400,{'error':'Invalid import identifier'})
        if route.endswith('/passwords'):
            if set(body)-{'runId','password'} or not isinstance(body.get('password'),str) or len(body['password'])>256:return response(400,{'error':'Invalid password handoff'})
            name=prefix+str(uuid.uuid4())
            secrets.create_secret(Name=name,SecretString=json.dumps({'runId':run,'password':body['password'],'expiresAt':int(time.time())+900}),
                Tags=[{'Key':'Project','Value':'Investments'},{'Key':'Ephemeral','Value':'CASPassword'}])
            return response(200,{'passwordRef':name})
        if route.endswith('/jobs'):
            if set(body)-{'runId','contentVersionId','passwordRef'}:return response(400,{'error':'Unsupported job field'})
            if not re.fullmatch(r'068[a-zA-Z0-9]{12}(?:[a-zA-Z0-9]{3})?',body.get('contentVersionId','')):return response(400,{'error':'Invalid source version'})
            if body.get('passwordRef') and not body['passwordRef'].startswith(prefix):return response(400,{'error':'Invalid password reference'})
            job=str(uuid.uuid4());functions.invoke(FunctionName=os.environ['WORKER_NAME'],InvocationType='Event',Payload=json.dumps(body).encode())
            return response(202,{'jobId':job,'status':'Queued'})
        return response(404,{'error':'Unknown route'})
    except Exception as error:
        # Do not return raw AWS exception messages; these can include sensitive parameters.
        return response(503,{'error':type(error).__name__})
