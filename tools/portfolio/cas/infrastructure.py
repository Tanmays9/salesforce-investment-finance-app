"""Dedicated AWS resources for async CAS parsing, with IAM-only HTTP admission."""
def template(stage,image,auth_secret):
    prefix='investments-cas-'+stage
    password='investments/cas/'+stage+'/password/'
    arn=lambda service,tail:{'Fn::Sub':'arn:${AWS::Partition}:'+service+':${AWS::Region}:${AWS::AccountId}:'+tail}
    get=lambda resource,attribute:{'Fn::GetAtt':[resource,attribute]}
    ref=lambda resource:{'Ref':resource}
    trust={'Version':'2012-10-17','Statement':[{'Effect':'Allow','Principal':{'Service':'lambda.amazonaws.com'},'Action':'sts:AssumeRole'}]}
    def role(name,statements):return {'Type':'AWS::IAM::Role','Properties':{'RoleName':prefix+'-'+name,'AssumeRolePolicyDocument':trust,'Policies':[{'PolicyName':'ScopedRuntime','PolicyDocument':{'Version':'2012-10-17','Statement':[
        {'Effect':'Allow','Action':['logs:CreateLogStream','logs:PutLogEvents'],'Resource':arn('logs','log-group:/aws/lambda/'+prefix+'-*:log-stream:*')},*statements]}}]}}
    secret_arn=arn('secretsmanager','secret:'+password+'*')
    resources={
      'FailureQueue':{'Type':'AWS::SQS::Queue','Properties':{'QueueName':prefix+'-failed','SqsManagedSseEnabled':True,'MessageRetentionPeriod':1209600}},
      'WorkerRole':role('worker',[
        {'Effect':'Allow','Action':['secretsmanager:GetSecretValue'],'Resource':[auth_secret,secret_arn]},
        {'Effect':'Allow','Action':['secretsmanager:DeleteSecret'],'Resource':secret_arn},
        {'Effect':'Allow','Action':['sqs:SendMessage'],'Resource':get('FailureQueue','Arn')}]),
      'WorkerLog':{'Type':'AWS::Logs::LogGroup','Properties':{'LogGroupName':'/aws/lambda/'+prefix+'-worker','RetentionInDays':14}},
      'DispatchLog':{'Type':'AWS::Logs::LogGroup','Properties':{'LogGroupName':'/aws/lambda/'+prefix+'-dispatcher','RetentionInDays':14}},
      'Worker':{'Type':'AWS::Lambda::Function','DependsOn':['WorkerLog'],'Properties':{'FunctionName':prefix+'-worker','PackageType':'Image',
        'Code':{'ImageUri':image},'Role':get('WorkerRole','Arn'),'MemorySize':2048,'Timeout':300,'ReservedConcurrentExecutions':1,
        'Environment':{'Variables':{'SF_AUTH_SECRET':auth_secret,'PASSWORD_PREFIX':password}}}},
      'WorkerRetry':{'Type':'AWS::Lambda::EventInvokeConfig','Properties':{'FunctionName':ref('Worker'),'Qualifier':'$LATEST','MaximumEventAgeInSeconds':900,
        'MaximumRetryAttempts':2,'DestinationConfig':{'OnFailure':{'Destination':get('FailureQueue','Arn')}}}},
      'DispatchRole':role('dispatcher',[
        {'Effect':'Allow','Action':['secretsmanager:CreateSecret','secretsmanager:DeleteSecret'],'Resource':secret_arn},
        {'Effect':'Allow','Action':['secretsmanager:ListSecrets'],'Resource':'*'},
        {'Effect':'Allow','Action':['lambda:InvokeFunction'],'Resource':get('Worker','Arn')}]),
      'Dispatcher':{'Type':'AWS::Lambda::Function','DependsOn':['DispatchLog'],'Properties':{'FunctionName':prefix+'-dispatcher','Runtime':'python3.13',
        'Role':get('DispatchRole','Arn'),'Handler':'index.handler','MemorySize':128,'Timeout':25,
        'Code':{'ZipFile':'PLACEHOLDER'},'Environment':{'Variables':{'WORKER_NAME':ref('Worker'),'PASSWORD_PREFIX':password}}}},
      'API':{'Type':'AWS::ApiGateway::RestApi','Properties':{'Name':prefix,'EndpointConfiguration':{'Types':['REGIONAL']},'DisableExecuteApiEndpoint':False}},
      'GatewayInvoke':{'Type':'AWS::Lambda::Permission','Properties':{'Action':'lambda:InvokeFunction','FunctionName':ref('Dispatcher'),
        'Principal':'apigateway.amazonaws.com','SourceArn':{'Fn::Sub':'arn:${AWS::Partition}:execute-api:${AWS::Region}:${AWS::AccountId}:${API}/*/POST/*'}}},
      'Cleanup':{'Type':'AWS::Events::Rule','Properties':{'Name':prefix+'-password-expiry','ScheduleExpression':'rate(15 minutes)','State':'ENABLED',
        'Targets':[{'Arn':get('Dispatcher','Arn'),'Id':'ExpirePasswords','Input':'{"cleanup":true}'}]}},
      'CleanupPermission':{'Type':'AWS::Lambda::Permission','Properties':{'Action':'lambda:InvokeFunction','FunctionName':ref('Dispatcher'),
        'Principal':'events.amazonaws.com','SourceArn':get('Cleanup','Arn')}},
      'SalesforceInvoker':{'Type':'AWS::IAM::User','Properties':{'UserName':prefix+'-salesforce','Policies':[{'PolicyName':'OnlyCASAdmission',
        'PolicyDocument':{'Version':'2012-10-17','Statement':[{'Effect':'Allow','Action':'execute-api:Invoke','Resource':[
          {'Fn::Sub':'arn:${AWS::Partition}:execute-api:${AWS::Region}:${AWS::AccountId}:${API}/v1/POST/jobs'},
          {'Fn::Sub':'arn:${AWS::Partition}:execute-api:${AWS::Region}:${AWS::AccountId}:${API}/v1/POST/passwords'}]}]}}]}}
    }
    for name,path in [('Jobs','jobs'),('Passwords','passwords')]:
        resources[name+'Resource']={'Type':'AWS::ApiGateway::Resource','Properties':{'RestApiId':ref('API'),'ParentId':get('API','RootResourceId'),'PathPart':path}}
        resources[name+'Method']={'Type':'AWS::ApiGateway::Method','Properties':{'RestApiId':ref('API'),'ResourceId':ref(name+'Resource'),
            'HttpMethod':'POST','AuthorizationType':'AWS_IAM','Integration':{'Type':'AWS_PROXY','IntegrationHttpMethod':'POST',
            'Uri':{'Fn::Sub':'arn:${AWS::Partition}:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${Dispatcher.Arn}/invocations'}}}}
    resources['Deployment']={'Type':'AWS::ApiGateway::Deployment','DependsOn':['JobsMethod','PasswordsMethod'],'Properties':{'RestApiId':ref('API'),'StageName':'v1',
        'StageDescription':{'MethodSettings':[{'HttpMethod':'*','ResourcePath':'/*','ThrottlingBurstLimit':5,'ThrottlingRateLimit':1,'DataTraceEnabled':False}]}}}
    return {'AWSTemplateFormatVersion':'2010-09-09','Description':'Private IAM-authenticated investment CAS extraction. No trade execution.',
        'Resources':resources,'Outputs':{
        'ApiUrl':{'Value':{'Fn::Sub':'https://${API}.execute-api.${AWS::Region}.amazonaws.com/v1'}},
        'WorkerName':{'Value':ref('Worker')},'DispatcherName':{'Value':ref('Dispatcher')},'InvokerUser':{'Value':ref('SalesforceInvoker')},
        'FailureQueueUrl':{'Value':ref('FailureQueue')}}}
