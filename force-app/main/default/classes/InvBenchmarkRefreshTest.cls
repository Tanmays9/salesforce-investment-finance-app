@IsTest private class InvBenchmarkRefreshTest {
    private class Context implements QueueableContext {public Id getJobId(){return '707000000000002';}}
    private class OfficialFeed implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response=new HttpResponse();response.setStatusCode(200);
            if(request.getEndpoint().contains('GetHistoricalPRTRData_Asia')) {
                Assert.isTrue(request.getEndpoint().contains('code=17'));
                Date first=Date.today().addDays(-2),second=Date.today().addDays(-1);
                response.setBody(JSON.serialize(new List<Object>{
                    new Map<String,Object>{'IndexName'=>'BSE 500','TransDate'=>bseDisplay(first),'TRValue'=>'200.50','PRValue'=>'150.00'},
                    new Map<String,Object>{'IndexName'=>'BSE 500','TransDate'=>bseDisplay(second),'TRValue'=>'202.00','PRValue'=>'151.00'}
                }));return response;
            }
            Assert.isTrue(request.getEndpoint().contains('/BackPage/getTotalReturnIndexString'));
            Assert.isTrue(request.getBody().contains('Nifty 500'));
            Date first=Date.today().addDays(-2),second=Date.today().addDays(-1);
            response.setBody(JSON.serialize(new List<Object>{
                new Map<String,Object>{'Index Name'=>'Nifty 500','Date'=>display(first),'TotalReturnsIndex'=>'100.25','NTR_Value'=>'90.00'},
                new Map<String,Object>{'Index Name'=>'Nifty 500','Date'=>display(second),'TotalReturnsIndex'=>'101.50','NTR_Value'=>'91.00'}
            }));return response;
        }
    }
    private static String display(Date day) {
        List<String> months=new List<String>{'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
        return String.valueOf(day.day())+' '+months[day.month()-1]+' '+String.valueOf(day.year());
    }
    private static String bseDisplay(Date day) {
        String month=day.month()<10?'0'+String.valueOf(day.month()):String.valueOf(day.month());
        String dateText=day.day()<10?'0'+String.valueOf(day.day()):String.valueOf(day.day());
        return month+'/'+dateText+'/'+String.valueOf(day.year())+' 12:00:00 AM';
    }
    private static String isoDate(Date value) {
        String month=value.month()<10?'0'+String.valueOf(value.month()):String.valueOf(value.month());
        String day=value.day()<10?'0'+String.valueOf(value.day()):String.valueOf(value.day());
        return String.valueOf(value.year())+'-'+month+'-'+day;
    }

    @TestSetup static void data() {
        Inv_OpsProviders__c provider=new Inv_OpsProviders__c(MigrationKey__c='ops.providers:27',Name__c='NSE Indices official TRI',Kind__c='official_benchmark');insert as system provider;
        Inv_MarketInstruments__c benchmark=new Inv_MarketInstruments__c(MigrationKey__c='benchmark-refresh:test',Name__c='NIFTY 500 TRI',
            Kind__c='benchmark',BenchmarkVariant__c='TRI',Currency__c='INR',ProviderCode__c='NIFTY 500 TRI');insert as system benchmark;
        Inv_MarketSchemes__c scheme=new Inv_MarketSchemes__c(MigrationKey__c='benchmark-refresh:scheme',Name__c='Test Scheme');insert as system scheme;
        Inv_MarketInstruments__c fund=new Inv_MarketInstruments__c(MigrationKey__c='benchmark-refresh:fund',Name__c='Test Fund');insert as system fund;
        insert as system new Inv_MarketFundShareClasses__c(MigrationKey__c='benchmark-refresh:share',InstrumentRef__c=fund.Id,SchemeRef__c=scheme.Id,Plan__c='Direct',Option__c='Growth');
        Inv_OpsSourceDocuments__c evidence=new Inv_OpsSourceDocuments__c(MigrationKey__c='benchmark-refresh:evidence',ProviderRef__c=provider.Id,
            Sha256__c='evidence-hash',MediaType__c='application/pdf',SourceUrl__c='https://example.invalid/factsheet.pdf',
            RetrievedAt__c=System.now(),ParserVersion__c='test');insert as system evidence;
        insert as system new Inv_MarketBenchmarkAssignments__c(MigrationKey__c='benchmark-refresh:assignment',SchemeRef__c=scheme.Id,
            BenchmarkRef__c=benchmark.Id,Role__c='primary',EffectiveFrom__c=Date.today().addYears(-1),DocumentRef__c=evidence.Id);
        Inv_OpsProviders__c bseProvider=new Inv_OpsProviders__c(MigrationKey__c='benchmark.provider.bse',Name__c='BSE Indices official TRI',Kind__c='official_benchmark');insert as system bseProvider;
        Inv_MarketInstruments__c bse=new Inv_MarketInstruments__c(MigrationKey__c='benchmark-refresh:bse',Name__c='BSE 500 TRI',
            Kind__c='benchmark',BenchmarkVariant__c='TRI',Currency__c='INR',ProviderCode__c='17');insert as system bse;
        Inv_MarketSchemes__c bseScheme=new Inv_MarketSchemes__c(MigrationKey__c='benchmark-refresh:bse-scheme',Name__c='BSE Test Scheme');insert as system bseScheme;
        Inv_MarketInstruments__c bseFund=new Inv_MarketInstruments__c(MigrationKey__c='benchmark-refresh:bse-fund',Name__c='BSE Test Fund');insert as system bseFund;
        insert as system new Inv_MarketFundShareClasses__c(MigrationKey__c='benchmark-refresh:bse-share',InstrumentRef__c=bseFund.Id,SchemeRef__c=bseScheme.Id,Plan__c='Direct',Option__c='Growth');
        insert as system new Inv_MarketBenchmarkAssignments__c(MigrationKey__c='benchmark-refresh:bse-assignment',SchemeRef__c=bseScheme.Id,
            BenchmarkRef__c=bse.Id,Role__c='primary',EffectiveFrom__c=Date.today().addYears(-1),DocumentRef__c=evidence.Id);
        String identity=provider.Id+'|'+benchmark.Id+'|'+Date.today().addDays(-2)+'|TRI|'+InvMath.valueKey('100.25');
        String key='nse-tri:'+InvPortfolioEngine.hash(identity);
        insert as system new Inv_MarketPriceObservations__c(MigrationKey__c=key,ObservationKey__c=key,InstrumentRef__c=benchmark.Id,
            ObservedOn__c=Date.today().addDays(-2),Value__c='100.25',PriceKind__c='TRI',KindFilter__c='TRI',QualityStatus__c='accepted',
            QualityFilter__c='accepted',ProviderRef__c=provider.Id,ReceivedAt__c=Datetime.newInstance(2020,1,1),RevisionNo__c='1');
    }

    @IsTest static void importsOfficialTri() {
        Inv_MarketInstruments__c benchmark=[SELECT Id FROM Inv_MarketInstruments__c WHERE MigrationKey__c='benchmark-refresh:test' WITH SYSTEM_MODE];
        Assert.areEqual(2,[SELECT COUNT() FROM Inv_MarketBenchmarkAssignments__c]);
        Test.setMock(HttpCalloutMock.class,new OfficialFeed());Test.startTest();System.enqueueJob(new InvBenchmarkRefresh());Test.stopTest();
        List<Inv_OpsDataIssues__c> issues=[SELECT Message__c FROM Inv_OpsDataIssues__c];
        Assert.areEqual(0,issues.size(),issues.isEmpty()?'':issues[0].Message__c);
        List<Inv_MarketPriceObservations__c> first=[SELECT PriceKind__c,QualityStatus__c,ObservedOn__c,ReceivedAt__c FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c=:benchmark.Id];
        Assert.areEqual(2,first.size());Assert.areEqual('TRI',first[0].PriceKind__c);Assert.areEqual('accepted',first[0].QualityStatus__c);
        Inv_MarketPriceObservations__c existing;
        for(Inv_MarketPriceObservations__c row:first)if(row.ObservedOn__c==Date.today().addDays(-2))existing=row;
        Assert.areEqual(Datetime.newInstance(2020,1,1),existing.ReceivedAt__c,'An identical official observation must remain unchanged on refresh.');
        Inv_MarketInstruments__c bse=[SELECT Id FROM Inv_MarketInstruments__c WHERE MigrationKey__c='benchmark-refresh:bse' WITH SYSTEM_MODE];
        List<Inv_MarketPriceObservations__c> bseRows=[SELECT MigrationKey__c,ProviderRef__c,Value__c,ObservedOn__c,PriceKind__c,QualityStatus__c,ProviderRef__r.MigrationKey__c
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c=:bse.Id WITH SYSTEM_MODE ORDER BY ObservedOn__c];
        Assert.areEqual(2,bseRows.size());Assert.areEqual('202.00',bseRows[1].Value__c);
        Assert.areEqual('TRI',bseRows[0].PriceKind__c);Assert.areEqual('accepted',bseRows[0].QualityStatus__c);
        Assert.areEqual('benchmark.provider.bse',bseRows[0].ProviderRef__r.MigrationKey__c);
        String expectedKey='bse-tri:'+InvPortfolioEngine.hash(bseRows[1].ProviderRef__c+'|'+bse.Id+'|'+isoDate(Date.today().addDays(-1))+'|TRI|'+InvMath.valueKey('202.00'));
        Assert.areEqual(expectedKey,bseRows[1].MigrationKey__c,'Observation identity must use the canonical ISO date shared with the history importer.');
    }
}
