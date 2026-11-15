import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import PORTFOLIO from '@salesforce/schema/Inv_Holding__c.Portfolio__c';
import FUND from '@salesforce/schema/Inv_Holding__c.Fund__c';
import getPortfolioResearch from '@salesforce/apex/InvResearchService.getPortfolioResearch';

const FIELDS = [PORTFOLIO, FUND];
const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', minimumFractionDigits: 2, maximumFractionDigits: 2 });

export default class InvHoldingSummary extends NavigationMixin(LightningElement) {
    @api recordId;
    holdingRecord;
    portfolio;
    loading = true;
    errorMessage;
    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) { this.holdingRecord = data; this.errorMessage = null; this.portfolio = undefined; this.loading = true; }
        else if (error) { this.loading = false; this.errorMessage = error.body?.message || 'Unable to load the holding record.'; }
    }
    get portfolioId() { return this.holdingRecord ? getFieldValue(this.holdingRecord, PORTFOLIO) : undefined; }
    get fundId() { return this.holdingRecord ? getFieldValue(this.holdingRecord, FUND) : undefined; }
    @wire(getPortfolioResearch, { requestedPortfolioId: '$portfolioId' })
    wiredPortfolio({ data, error }) {
        if (data) {
            this.portfolio = data; this.loading = false; this.errorMessage = data.statusMessage && !data.baselineRunId ? data.statusMessage : null;
        } else if (error) { this.loading = false; this.errorMessage = error.body?.message || 'Unable to load the published valuation.'; }
    }
    get holding() { return this.portfolio?.holdings?.find(row => row.holdingId === this.recordId); }
    get valuationDate() { return this.portfolio?.valuationDate; }
    get fundUrl() { return this.fundId ? `/lightning/r/Inv_MarketInstruments__c/${this.fundId}/view` : '#'; }
    get formattedNav() { return this.holding?.nav == null ? 'Unavailable' : inr.format(this.holding.nav); }
    get formattedCost() { return this.holding?.cost == null ? 'Incomplete' : inr.format(this.holding.cost); }
    get formattedValue() { return this.holding?.marketValue == null ? 'Incomplete' : inr.format(this.holding.marketValue); }
    get formattedGain() { return this.holding?.unrealizedGain == null ? 'Incomplete' : inr.format(this.holding.unrealizedGain); }
    get formattedXirr() { return this.holding?.xirr == null ? 'Unavailable' : `${(Number(this.holding.xirr) * 100).toFixed(2)}%`; }
    get formattedWeight() { return this.holding?.weight == null ? 'Unavailable' : `${(Number(this.holding.weight) * 100).toFixed(2)}%`; }
    get formattedSip() { return inr.format(this.holding?.monthlySip || 0); }
    openFund(event) {
        event?.preventDefault();
        if (!this.fundId) return;
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: this.fundId, objectApiName: 'Inv_MarketInstruments__c', actionName: 'view' } });
    }
}
