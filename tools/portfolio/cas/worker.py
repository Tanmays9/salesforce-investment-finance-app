"""Asynchronous, extraction-only CAS worker. Never logs PDFs, passwords or tokens."""
import io,json,os,time,hashlib,urllib.request,urllib.parse
import boto3,jwt,casparser
from normalise import normalise

secrets=boto3.client('secretsmanager')

def parse_pdf(content,password):
    """Handle CAMS statements whose branded header omits CAMSCASWS."""
    import casparser.parsers as dispatch
    from casparser.enums import FileType
    from casparser.parsers.detect import _read_text_sample
    detect=dispatch.detect_file_type
    def detect_with_cams_header(filename,password,*,_doc=None):
        issuer=detect(filename,password,_doc=_doc)
        if issuer!=FileType.UNKNOWN:return issuer
        text=_read_text_sample(filename,password,_doc=_doc).casefold()
        if 'cams' in text and 'consolidated account statement' in text:return FileType.CAMS
        return issuer
    dispatch.detect_file_type=detect_with_cams_header
    try:return json.loads(casparser.read_cas_pdf(io.BytesIO(content),password,output='json'))
    finally:dispatch.detect_file_type=detect

def secret(name):return json.loads(secrets.get_secret_value(SecretId=name)['SecretString'])

def sf_session():
    settings=secret(os.environ['SF_AUTH_SECRET'])
    assertion=jwt.encode({'iss':settings['client_id'],'sub':settings['username'],'aud':settings['audience'],'exp':int(time.time())+120},settings['private_key'],algorithm='RS256')
    request=urllib.request.Request(settings['sf_base_url']+'/services/oauth2/token',urllib.parse.urlencode({'grant_type':'urn:ietf:params:oauth:grant-type:jwt-bearer','assertion':assertion}).encode())
    with urllib.request.urlopen(request,timeout=25) as response:result=json.load(response)
    # The configured domain is trusted configuration, never supplied by a parsing job.
    return settings['sf_base_url'],result['access_token']

def sf(base,token,path,payload=None,binary=False):
    request=urllib.request.Request(base+path,None if payload is None else json.dumps(payload,separators=(',',':')).encode(),
        {'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=40) as response:
        raw=response.read();return raw if binary else json.loads(raw) if raw else None

def handler(event,context):
    run=event['runId'];version=event['contentVersionId'];password_ref=event.get('passwordRef');password=''
    base=token=None;finished=False
    try:
        base,token=sf_session()
        record=sf(base,token,'/services/data/v68.0/sobjects/Inv_OpsImportRuns__c/'+run+'?fields=ContentVersionId__c,OperationalStatus__c')
        if record['ContentVersionId__c']!=version:raise ValueError('SourceVersionMismatch')
        if record['OperationalStatus__c'] in ['Complete','Duplicate','Needs Review','Partially Confirmed']:
            finished=True
            return {'status':'already_processed'}
        if password_ref:
            if not password_ref.startswith(os.environ['PASSWORD_PREFIX']):raise ValueError('InvalidPasswordReference')
            value=secret(password_ref)
            if value['runId']!=run or value['expiresAt']<time.time():raise ValueError('PasswordReferenceExpired')
            password=value['password']
        content=sf(base,token,'/services/data/v68.0/sobjects/ContentVersion/'+version+'/VersionData',binary=True)
        if len(content)>15000000:raise ValueError('StatementTooLarge')
        file_hash=hashlib.sha256(content).hexdigest()
        parsed=parse_pdf(content,password)
        payload=normalise(parsed,file_hash)
        sf(base,token,'/services/apexrest/investments/imports/stage',{'operation':'stage','runId':run,'payload':payload})
        finished=True
        return {'status':'staged','scopes':len(payload['scopes']),'milliseconds':int((300-context.get_remaining_time_in_millis()/1000)*1000)}
    except Exception as error:
        if base and token:
            # Only the exception type is persisted; parser messages can contain personal source text.
            sf(base,token,'/services/apexrest/investments/imports/failed',{'operation':'failed','runId':run,'errorType':type(error).__name__})
        raise RuntimeError('CAS extraction failed: '+type(error).__name__) from None
    finally:
        password=''
        # Keep the short-lived handoff for asynchronous retries after transient failures.
        if finished and password_ref and password_ref.startswith(os.environ['PASSWORD_PREFIX']):
            try:secrets.delete_secret(SecretId=password_ref,ForceDeleteWithoutRecovery=True)
            except Exception:pass # The scheduled expiry cleanup removes orphaned ephemeral secrets.
