@IsTest private class InvMathTest {
    private static InvMath.Entry entry(String id,Date d,Decimal units,Decimal amount) {
        InvMath.Entry e=new InvMath.Entry();e.identity=id;e.day=d;e.units=units;e.cost=units>0?amount:null;
        e.consideration=amount;e.basis='gross';e.kind=units>0?'purchase':'redemption';return e;
    }
    @IsTest static void partialFIFOAndUnknownProceeds() {
        Date d=Date.newInstance(2020,1,1);
        InvMath.Position p=InvMath.fifo(new List<InvMath.Entry>{entry('1',d,100,1000),entry('2',d.addDays(1),100,2000),entry('3',d.addDays(2),-150,4500)});
        Assert.areEqual(50,p.units);Assert.areEqual(1000,p.cost);Assert.areEqual(2500,p.realized);
        InvMath.Entry sale=entry('2',d.addDays(1),-20,300);sale.basis='reported_net';
        p=InvMath.fifo(new List<InvMath.Entry>{entry('1',d,100,1000),sale});Assert.isFalse(p.realizedKnown);
    }
    @IsTest static void rejectsMissingOpeningAndPreservesUnknownBasis() {
        Date d=Date.today();Boolean failed=false;
        try {InvMath.fifo(new List<InvMath.Entry>{entry('1',d,-1,10)});}catch(InvMath.CalculationException e){failed=true;}
        Assert.isTrue(failed);
        InvMath.Entry buy=entry('1',d,10,100);buy.cost=null;
        Assert.isFalse(InvMath.fifo(new List<InvMath.Entry>{buy}).basisKnown);
    }
    @IsTest static void annualReturnAndAmbiguity() {
        Date d=Date.newInstance(2021,1,1);
        InvMath.ReturnResult r=InvMath.xirr(new List<InvMath.FlowPoint>{new InvMath.FlowPoint(d,-100),new InvMath.FlowPoint(d.addDays(365),110)});
        Assert.areEqual('ok',r.status);Assert.isTrue((r.rate-0.1).abs()<0.00000001);
        r=InvMath.xirr(new List<InvMath.FlowPoint>{new InvMath.FlowPoint(d,-100),new InvMath.FlowPoint(d.addDays(365),200),new InvMath.FlowPoint(d.addDays(730),-50)});
        Assert.areEqual('nonconventional_cashflows_require_review',r.status);
        Assert.areEqual('insufficient_history',InvMath.xirr(new List<InvMath.FlowPoint>()).status);
    }
    @IsTest static void exactInputsAndReportingProjectionNeverRound() {
        Assert.areEqual(0.001,InvMath.exact('1e-3'));Assert.areEqual(100,InvMath.exact('+100.000'));
        Boolean rejected=false;try{InvMath.exact('0.12345678901234567890123456789');}catch(InvMath.CalculationException e){rejected=true;}Assert.isTrue(rejected);
        Inv_PortfolioUnitEntries__c row=new Inv_PortfolioUnitEntries__c();InvMath.project(row,'UnitsDelta__c','12.3400');Assert.areEqual('12.3400',row.UnitsDelta__c);Assert.areEqual(12.34,row.UnitsDeltaNumber__c);
        Integer scale=Inv_PortfolioUnitEntries__c.UnitsDeltaNumber__c.getDescribe().getScale();String tiny='0.';for(Integer i=0;i<scale;i++)tiny+='0';tiny+='1';
        InvMath.project(row,'UnitsDelta__c',tiny);Assert.areEqual(tiny,row.UnitsDelta__c);Assert.isNull(row.UnitsDeltaNumber__c);
    }
}
