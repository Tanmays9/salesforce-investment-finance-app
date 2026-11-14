import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getListRecordsByName } from 'lightning/uiListsApi';

const OBJECT_API_NAME = 'Inv_WatchlistItems__c';
const FIELDS = [
    `${OBJECT_API_NAME}.Name`,
    `${OBJECT_API_NAME}.AssetType__c`,
    `${OBJECT_API_NAME}.Symbol__c`,
    `${OBJECT_API_NAME}.Exchange__c`,
    `${OBJECT_API_NAME}.ISIN__c`,
    `${OBJECT_API_NAME}.AddedOn__c`
];

const COLUMNS = [
    { label: 'Watchlist item', fieldName: 'name', type: 'text' },
    { label: 'Type', fieldName: 'assetType', type: 'text' },
    { label: 'Ticker or symbol', fieldName: 'symbol', type: 'text' },
    { label: 'Exchange', fieldName: 'exchange', type: 'text' },
    { label: 'ISIN', fieldName: 'isin', type: 'text' },
    { label: 'Added on', fieldName: 'addedOn', type: 'date-local' }
];

export default class InvWatchlistCard extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    rows = [];
    loading = true;
    error;

    @wire(getListRecordsByName, {
        objectApiName: OBJECT_API_NAME,
        listViewApiName: 'Active',
        pageSize: 10,
        fields: FIELDS
    })
    wiredRecords(result) {
        if (result.data) {
            this.rows = (result.data.records?.records || []).map(record => ({
                id: record.id,
                name: record.fields.Name?.value,
                assetType: record.fields.AssetType__c?.value,
                symbol: record.fields.Symbol__c?.value,
                exchange: record.fields.Exchange__c?.value,
                isin: record.fields.ISIN__c?.value,
                addedOn: record.fields.AddedOn__c?.value
            }));
            this.error = undefined;
            this.loading = false;
        } else if (result.error) {
            this.error = result.error;
            this.loading = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: OBJECT_API_NAME, actionName: 'new' }
        });
    }

    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: OBJECT_API_NAME, actionName: 'list' },
            state: { filterName: 'Active' }
        });
    }
}
