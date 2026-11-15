import { LightningElement, api, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';
import getFundResearch from '@salesforce/apex/InvResearchService.getFundResearch';

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', minimumFractionDigits: 2, maximumFractionDigits: 2 });
const money = { type: 'currency', typeAttributes: { currencyCode: 'INR', minimumFractionDigits: 2, maximumFractionDigits: 2 } };
const percent = { type: 'percent', typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 } };

export default class InvFundResearch extends LightningElement {
    @api recordId;
    data;
    errorMessage;
    loading = true;
    chart;
    _chartPromise;

    @wire(getFundResearch, { fundId: '$recordId' })
    wiredFund({ data, error }) {
        this.loading = false;
        if (data) { this.data = data; this.errorMessage = null; this.renderChart(); }
        else if (error) { this.data = null; this.errorMessage = error.body?.message || 'Unable to load fund research.'; }
    }
    get title() { return this.data?.fundName || 'Mutual fund research'; }
    get mappingLabel() { return this.data?.mappingVerified ? 'Verified share class' : 'Mapping review required'; }
    get formattedNav() { return this.data?.latestNav == null ? 'Unavailable' : inr.format(this.data.latestNav); }
    get formattedOwnedValue() { const value = (this.data?.positions || []).reduce((sum, row) => sum + (row.status === 'Active' ? (row.marketValue || 0) : 0), 0); return inr.format(value); }
    get formattedCost() { const rows = (this.data?.positions || []).filter(row => row.status === 'Active'); return rows.some(row => row.cost == null) ? 'Incomplete' : inr.format(rows.reduce((sum, row) => sum + (row.cost || 0), 0)); }
    get formattedGain() { const rows = (this.data?.positions || []).filter(row => row.status === 'Active'); return rows.some(row => row.unrealizedGain == null) ? 'Incomplete' : inr.format(rows.reduce((sum, row) => sum + (row.unrealizedGain || 0), 0)); }
    get formattedAllocation() {
        const groups = new Map();
        for (const row of this.data?.positions || []) if (row.status === 'Active') {
            const key = row.portfolioId || row.portfolioName || 'Portfolio';
            const entry = groups.get(key) || { name: row.portfolioName || 'Portfolio', weight: 0 };
            entry.weight += row.weight || 0; groups.set(key, entry);
        }
        return [...groups.values()].map(entry => `${entry.name}: ${(entry.weight * 100).toFixed(2)}%`).join(' · ') || 'No active allocation';
    }
    get formattedSip() { return inr.format(this.data?.monthlySip || 0); }
    get formattedTer() { return this.data?.ter == null ? 'Unavailable' : `${(Number(this.data.ter) * 100).toFixed(2)}%`; }
    get formattedBer() { return this.data?.ber == null ? 'Unavailable' : `${(Number(this.data.ber) * 100).toFixed(2)}%`; }
    get hasPeers() { return (this.data?.peers || []).length > 0; }
    get metricColumns() { return [{ label: 'Measure', fieldName: 'metric' }, { label: 'Value', fieldName: 'value', ...percent }, { label: 'Period start', fieldName: 'periodStart', type: 'date-local' }, { label: 'Period end', fieldName: 'periodEnd', type: 'date-local' }, { label: 'Coverage', fieldName: 'coverage', wrapText: true }]; }
    get peerColumns() { return [{ label: 'Assigned peer', fieldName: 'peerName' }, { label: 'Metric', fieldName: 'metric' }, { label: 'Common period start', fieldName: 'periodStart', type: 'date-local' }, { label: 'Common period end', fieldName: 'periodEnd', type: 'date-local' }, { label: 'This fund NAV return', fieldName: 'ownValue', ...percent }, { label: 'Peer NAV return', fieldName: 'peerValue', ...percent }, { label: 'Coverage', fieldName: 'coverage', wrapText: true }]; }
    get peerAssignmentColumns() { return [{ label: 'Peer fund', fieldName: 'fundName' }, { label: 'Category', fieldName: 'category' }, { label: 'Share-class rule', fieldName: 'shareClassRule' }, { label: 'Valid from', fieldName: 'effectiveFrom', type: 'date-local' }, { label: 'Valid through', fieldName: 'effectiveTo', type: 'date-local' }, { label: 'Rationale', fieldName: 'rationale', wrapText: true }]; }
    get compositionColumns() { return [{ label: 'Dimension', fieldName: 'dimension' }, { label: 'Member', fieldName: 'member', wrapText: true }, { label: 'Reported weight', fieldName: 'weightDisplay' }, { label: 'Disclosure date', fieldName: 'disclosureDate', type: 'date-local' }, { label: 'Coverage', fieldName: 'coverage' }, { label: 'Source label', fieldName: 'sourceLabels', wrapText: true }]; }
    get positionColumns() { return [{ label: 'Portfolio', fieldName: 'portfolioName' }, { label: 'Account', fieldName: 'accountLabel' }, { label: 'Units', fieldName: 'units', type: 'number', typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 8 } }, { label: 'NAV', fieldName: 'nav', ...money }, { label: 'NAV date', fieldName: 'navDate', type: 'date-local' }, { label: 'Cost', fieldName: 'cost', ...money }, { label: 'Value', fieldName: 'marketValue', ...money }, { label: 'Unrealized gain / loss', fieldName: 'unrealizedGain', ...money }, { label: 'Personal XIRR', fieldName: 'xirr', ...percent }, { label: 'Monthly SIP', fieldName: 'monthlySip', ...money }, { label: 'Reconciled through', fieldName: 'reconciledThrough', type: 'date-local' }, { label: 'Coverage', fieldName: 'coverage', wrapText: true }]; }
    get performanceRows() { return (this.data?.metrics || []).filter(row => row.fundId === this.data?.fundId).map((row, index) => ({ ...row, key: `${row.metric}-${row.periodStart}-${row.periodEnd}-${index}` })); }
    get peerRows() { return (this.data?.peers || []).map(row => ({ ...row })); }
    get hasPeerComparisonRows() { return this.peerComparisonRows.length > 0; }
    get peerComparisonRows() {
        const rows = [];
        const metrics = this.data?.metrics || [];
        for (const peer of this.data?.peers || []) {
            const own = metrics.filter(row => row.fundId === this.data.fundId && /return|CAGR/i.test(row.metric || ''));
            const theirs = metrics.filter(row => row.fundId === peer.fundId && /return|CAGR/i.test(row.metric || ''));
            for (const a of own) {
                const b = theirs.find(row => row.metric === a.metric && row.periodStart === a.periodStart && row.periodEnd === a.periodEnd);
                if (!b) continue;
                rows.push({ key: `${peer.fundId}-${a.metric}-${a.periodStart}-${a.periodEnd}`, peerName: peer.fundName, metric: a.metric, periodStart: a.periodStart, periodEnd: a.periodEnd, ownValue: a.value, peerValue: b.value, coverage: a.coverage === 'ok' && b.coverage === 'ok' ? 'Common period' : `${a.coverage}; peer ${b.coverage}` });
            }
        }
        return rows;
    }
    get compositionRows() {
        return (this.data?.composition || []).map((row, index) => ({ ...row, key: `${row.dimension}-${row.memberKey}-${index}`, weightDisplay: row.value == null ? 'Unavailable' : `${(Number(row.value) * 100).toFixed(2)}%` }));
    }
    get positionRows() { return (this.data?.positions || []).map((row, index) => ({ ...row, rowKey: `${row.holdingId}-${index}` })); }
    renderedCallback() { this.renderChart(); }
    renderChart() {
        if (!this.data || !this.isConnected) return;
        if (!this._chartPromise) this._chartPromise = loadScript(this, `${CHARTJS}/chart.umd.min.js`).catch(() => false);
        this._chartPromise.then(ok => {
            if (ok === false || !window.Chart || this.chart) return;
            const canvas = this.template.querySelector('.navChart');
            if (!canvas || !this.data.navHistory?.length) return;
            this.chart = new window.Chart(canvas, { type: 'line', data: { labels: this.data.navHistory.map(point => point.day), datasets: [{ label: 'NAV (INR per unit)', data: this.data.navHistory.map(point => point.value), borderColor: '#176b87', pointRadius: 0, tension: 0.12 }] }, options: { responsive: true, interaction: { intersect: false, mode: 'index' }, scales: { y: { ticks: { callback: value => inr.format(value) } } }, plugins: { tooltip: { callbacks: { label: context => `NAV: ${inr.format(context.parsed.y)}` } } } } });
        });
    }
    disconnectedCallback() { this.chart?.destroy(); }
}
