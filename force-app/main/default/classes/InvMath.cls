public class InvMath {
    public class CalculationException extends Exception {}
    public class FlowPoint {
        public Date day; public Decimal amount;
        public FlowPoint(Date d, Decimal a) { day=d; amount=a; }
    }
    public class ReturnResult { public Decimal rate; public String status; }
    public class Entry implements Comparable {
        public String identity; public Date day; public Date acquired;
        public Decimal sequence; public Decimal units; public Decimal cost; public Decimal consideration;
        public String basis; public String kind;
        public Integer compareTo(Object other) {
            Entry e=(Entry)other;
            if(day!=e.day) return day<e.day ? -1 : 1;
            Decimal a=sequence==null?0:sequence, b=e.sequence==null?0:e.sequence;
            if(a!=b)return a<b?-1:1;
            return identity.compareTo(e.identity);
        }
    }
    public class Lot { public Date acquired; public Decimal units; public Decimal unitCost; }
    public class Position {
        public Decimal units=0,cost=0,realized=0;
        public Boolean basisKnown=true,realizedKnown=true;
        public List<Lot> lots=new List<Lot>();
        public List<FlowPoint> cashflows=new List<FlowPoint>();
        public String cashflowStatus='derived_from_reported_consideration';
    }
    public static Decimal exact(String value) {
        if(String.isBlank(value))return null;
        String expected=decimalSignature(value);
        Decimal d=Decimal.valueOf(value);
        if(d.precision()>28 || decimalSignature(String.valueOf(d))!=expected)throw new CalculationException('Source decimal exceeds supported precision');
        return d;
    }
    private static String decimalSignature(String value) {
        String raw=value.trim().toLowerCase();
        if(!Pattern.matches('[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:e[+-]?[0-9]+)?',raw))throw new CalculationException('Invalid decimal input');
        List<String> parts=raw.split('e');String mantissa=parts[0];Integer exponent=parts.size()>1?Integer.valueOf(parts[1]):0;
        Boolean negative=mantissa.startsWith('-');mantissa=mantissa.replaceFirst('^[+-]','');
        Integer dot=mantissa.indexOf('.');if(dot>=0)exponent-=mantissa.length()-dot-1;
        String digits=mantissa.replace('.','').replaceFirst('^0+','');
        if(digits=='')return '0';
        while(digits.endsWith('0')){digits=digits.left(digits.length()-1);exponent++;}
        if(digits.length()>28)throw new CalculationException('Source decimal exceeds supported precision');
        return (negative?'-':'')+digits+'e'+exponent;
    }
    public static String valueKey(String value) {exact(value);return decimalSignature(value);}
    public static void capture(SObject row) {
        Map<String,String> values=new Map<String,String>();
        for(String field:row.getPopulatedFieldsAsMap().keySet()){
            Object value=row.get(field);if(value instanceof Decimal)values.put(field,String.valueOf(value));
        }
        row.put('ExactValues__c',JSON.serialize(values));
    }
    public static void project(SObject target,String field,String value) {
        target.put(field,value);String numeric=field.replace('__c','Number__c');
        Map<String,Schema.SObjectField> fields=target.getSObjectType().getDescribe().fields.getMap();
        if(!fields.containsKey(numeric))return;
        if(value==null){target.put(numeric,null);return;}
        Decimal parsed=exact(value);Schema.DescribeFieldResult description=fields.get(numeric).getDescribe();
        Decimal bound=1;for(Integer i=0;i<description.getPrecision()-description.getScale();i++)bound*=10;
        target.put(numeric,parsed==parsed.setScale(description.getScale()) && parsed.abs()<bound?parsed:null);
    }
    public static Position fifo(List<Entry> entries) {
        entries.sort();Position p=new Position();Integer head=0;
        for(Entry e:entries) {
            if(e.units==null || e.units==0)continue;
            p.units+=e.units;
            if(e.units>0) {
                Lot l=new Lot();l.acquired=e.acquired==null?e.day:e.acquired;l.units=e.units;
                l.unitCost=e.cost==null?null:e.cost/e.units;p.lots.add(l);
            } else {
                Decimal sell=-e.units, allocated=0;Boolean known=true;
                while(sell>0 && head<p.lots.size()) {
                    Lot l=p.lots[head];Decimal take=sell<l.units?sell:l.units;
                    if(l.unitCost==null)known=false;else allocated+=take*l.unitCost;
                    l.units-=take;sell-=take;if(l.units==0)head++;
                }
                if(sell>0)throw new CalculationException('Redemption exceeds available FIFO units; opening history required');
                if(!known || e.consideration==null || e.basis!='gross')p.realizedKnown=false;
                else p.realized+=e.consideration-allocated;
            }
            if(e.consideration==null || (e.kind!='purchase' && e.kind!='redemption'))p.cashflowStatus='incomplete';
            else p.cashflows.add(new FlowPoint(e.day,e.units>0?-e.consideration:e.consideration));
        }
        for(Lot l:p.lots) if(l.units>0) {if(l.unitCost==null)p.basisKnown=false;else p.cost+=l.units*l.unitCost;}
        return p;
    }
    public static ReturnResult xirr(List<FlowPoint> points) {
        ReturnResult result=new ReturnResult();Map<Date,Decimal> amounts=new Map<Date,Decimal>();
        for(FlowPoint p:points) {
            if(p.day==null || p.amount==null){result.status='invalid_inputs';return result;}
            amounts.put(p.day,(amounts.containsKey(p.day)?amounts.get(p.day):0)+p.amount);
        }
        List<Date> dates=new List<Date>(amounts.keySet());dates.sort();Integer prev=0,changes=0,nonzero=0;
        for(Date d:dates) {Decimal a=amounts.get(d);if(a==0)continue;nonzero++;Integer sign=a>0?1:-1;if(prev!=0 && sign!=prev)changes++;prev=sign;}
        if(nonzero<2 || dates[0]==dates[dates.size()-1]){result.status='insufficient_history';return result;}
        if(changes!=1){result.status='nonconventional_cashflows_require_review';return result;}
        Double lo=-20,hi=20,flo=npv(lo,dates,amounts),fhi=npv(hi,dates,amounts);
        if((flo>0)==(fhi>0)){result.status='no_bracketed_root';return result;}
        for(Integer i=0;i<100;i++) {
            Double mid=(lo+hi)/2,f=npv(mid,dates,amounts);
            if((f>=0)==(flo>=0)){lo=mid;flo=f;}else hi=mid;
        }
        result.rate=Decimal.valueOf(String.valueOf(Math.exp((lo+hi)/2)-1));result.status='ok';return result;
    }
    private static Double npv(Double logRate,List<Date> dates,Map<Date,Decimal> amounts) {
        Double value=0;
        for(Date d:dates) {
            Double exponent=-logRate*dates[0].daysBetween(d)/365.0;
            exponent=Math.max(-700.0,Math.min(700.0,exponent));
            value+=Double.valueOf(String.valueOf(amounts.get(d)))*Math.exp(exponent);
        }
        return value;
    }
}
