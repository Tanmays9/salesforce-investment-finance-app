/** Shared accepted-NAV selection used by portfolio and fund analytics.
 * Same-date provider conflicts prefer the preselected value (normally AMFI),
 * then official AMFI evidence, then the newest revision/retrieval.
 */
public without sharing class InvNAVPolicy {
    public static Map<Id,Inv_MarketPriceObservations__c> latestByInstrument(Set<Id> instruments,Date asOf) {
        return latestByInstrument(instruments,asOf,System.now());
    }
    public static Map<Id,Inv_MarketPriceObservations__c> latestByInstrument(Set<Id> instruments,Date asOf,Datetime knownAt) {
        Map<Id,Inv_MarketPriceObservations__c> result=new Map<Id,Inv_MarketPriceObservations__c>();
        if(instruments==null || instruments.isEmpty())return result;
        Map<Id,Date> lastDay=new Map<Id,Date>();Set<Date> days=new Set<Date>();
        for(AggregateResult a:[SELECT InstrumentRef__c instrument,MAX(ObservedOn__c) latestDay
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c IN :instruments AND ObservedOn__c<=:asOf
                AND CreatedDate<=:knownAt AND KindFilter__c='NAV' AND QualityFilter__c='accepted' WITH SYSTEM_MODE GROUP BY InstrumentRef__c]) {
            Id instrument=(Id)a.get('instrument');Date day=(Date)a.get('latestDay');lastDay.put(instrument,day);days.add(day);
        }
        if(lastDay.isEmpty())return result;
        for(Inv_MarketPriceObservations__c row:[SELECT Id,InstrumentRef__c,ObservedOn__c,Value__c,PriceKind__c,QualityStatus__c,
                ProviderRef__r.Name__c,SelectedNAV__c,RevisionNoNumber__c,ReceivedAt__c
            FROM Inv_MarketPriceObservations__c WHERE InstrumentRef__c IN :lastDay.keySet() AND ObservedOn__c IN :days
                AND CreatedDate<=:knownAt AND KindFilter__c='NAV' AND QualityFilter__c='accepted' WITH SYSTEM_MODE]) {
            if(row.ObservedOn__c!=lastDay.get(row.InstrumentRef__c) || InvMath.exact(row.Value__c)<=0)continue;
            Inv_MarketPriceObservations__c prior=result.get(row.InstrumentRef__c);
            if(prior==null || prefer(row,prior))result.put(row.InstrumentRef__c,row);
        }
        return result;
    }

    public static Map<Date,Inv_MarketPriceObservations__c> daily(List<Inv_MarketPriceObservations__c> source) {
        Map<Date,Inv_MarketPriceObservations__c> result=new Map<Date,Inv_MarketPriceObservations__c>();
        for(Inv_MarketPriceObservations__c row:source) {
            if(row.PriceKind__c!='NAV' || row.QualityStatus__c!='accepted' || InvMath.exact(row.Value__c)<=0)continue;
            Inv_MarketPriceObservations__c prior=result.get(row.ObservedOn__c);
            if(prior==null || prefer(row,prior))result.put(row.ObservedOn__c,row);
        }
        return result;
    }

    private static Boolean prefer(Inv_MarketPriceObservations__c candidate,Inv_MarketPriceObservations__c current) {
        if(candidate.SelectedNAV__c!=current.SelectedNAV__c)return candidate.SelectedNAV__c==true;
        String candidateProvider=candidate.ProviderRef__r==null?null:candidate.ProviderRef__r.Name__c;
        String currentProvider=current.ProviderRef__r==null?null:current.ProviderRef__r.Name__c;
        if((candidateProvider=='AMFI')!=(currentProvider=='AMFI'))return candidateProvider=='AMFI';
        Decimal candidateRevision=candidate.RevisionNoNumber__c,currentRevision=current.RevisionNoNumber__c;
        if(candidateRevision!=currentRevision)return candidateRevision!=null && (currentRevision==null || candidateRevision>currentRevision);
        if(candidate.ReceivedAt__c!=current.ReceivedAt__c)return candidate.ReceivedAt__c!=null && (current.ReceivedAt__c==null || candidate.ReceivedAt__c>current.ReceivedAt__c);
        return String.valueOf(candidate.Id)>String.valueOf(current.Id);
    }
}
