import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import PORTFOLIO from "@salesforce/schema/Inv_Holding__c.Portfolio__c";
import FUND from "@salesforce/schema/Inv_Holding__c.Fund__c";
import getPortfolioResearch from "@salesforce/apex/InvResearchService.getPortfolioResearch";
import getOpenRedemptionActions from "@salesforce/apex/InvPlanScenarioService.getOpenRedemptionActions";
import preview from "@salesforce/apex/InvRedemptionService.preview";
import saveReview from "@salesforce/apex/InvRedemptionService.saveReview";

const FIELDS = [PORTFOLIO, FUND];
const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});
const money = {
  type: "currency",
  typeAttributes: {
    currencyCode: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }
};

export default class InvRedemptionReview extends LightningElement {
  @api recordId;
  record;
  portfolioData;
  actions = [];
  previewData;
  loading = true;
  saving = false;
  errorMessage;
  selectedFundId;
  selectedActionId;
  selectedAccountId;
  requestedUnits;
  settlementDate;
  taxAcknowledged = false;
  @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
  wiredRecord({ data }) {
    if (data) {
      this.record = data;
      this.selectedFundId = getFieldValue(data, FUND);
    }
  }
  get portfolioId() {
    return this.record ? getFieldValue(this.record, PORTFOLIO) : null;
  }
  @wire(getPortfolioResearch, { requestedPortfolioId: "$portfolioId" })
  wiredPortfolio({ data, error }) {
    if (data) {
      this.portfolioData = data;
      this.loading = false;
      if (!this.selectedFundId)
        this.selectedFundId = data.holdings?.find(
          (row) => row.status === "Active"
        )?.fundId;
      this.errorMessage = null;
    } else if (error) {
      this.loading = false;
      this.errorMessage =
        error.body?.message || "Unable to load portfolio valuation data.";
    }
  }
  get researchPortfolioId() {
    return this.portfolioData?.portfolioId || null;
  }
  @wire(getOpenRedemptionActions, { portfolioId: "$researchPortfolioId" })
  wiredActions({ data }) {
    if (data) this.actions = data;
  }
  get fundOptions() {
    const byId = new Map();
    for (const row of this.portfolioData?.holdings || [])
      if (row.fundId && row.status === "Active")
        byId.set(row.fundId, row.fundName);
    return [...byId.entries()].map(([value, label]) => ({ value, label }));
  }
  get actionOptions() {
    return [
      { label: "Preview without linking a plan action", value: "" },
      ...this.actions.map((row) => ({ label: row.label, value: row.actionId }))
    ];
  }
  get actionLocked() {
    return !!this.selectedActionId;
  }
  get selectedAction() {
    return this.actions.find((row) => row.actionId === this.selectedActionId);
  }
  get fullScopeAction() {
    return this.selectedAction?.allAvailable === true;
  }
  get accountOptions() {
    const accounts = new Map();
    for (const row of this.portfolioData?.holdings || [])
      if (
        row.fundId === this.selectedFundId &&
        row.status === "Active" &&
        row.accountId
      )
        accounts.set(row.accountId, row.accountLabel || "Investment account");
    return [
      { label: "All accounts (full redemption only)", value: "" },
      ...[...accounts.entries()].map(([value, label]) => ({ value, label }))
    ];
  }
  get previewDisabled() {
    return (
      this.saving || !this.portfolioData?.portfolioId || !this.selectedFundId
    );
  }
  get saveDisabled() {
    return (
      this.saving ||
      !this.previewData ||
      !this.selectedActionId ||
      !this.settlementDate
    );
  }
  get formattedNav() {
    return this.previewData?.nav == null
      ? "Unavailable"
      : inr.format(this.previewData.nav);
  }
  get formattedGross() {
    return this.previewData?.grossProceeds == null
      ? "Incomplete"
      : inr.format(this.previewData.grossProceeds);
  }
  get formattedBasis() {
    return this.previewData?.costBasis == null
      ? "Incomplete"
      : inr.format(this.previewData.costBasis);
  }
  get formattedLoad() {
    return this.previewData?.exitLoad == null
      ? "Unknown"
      : inr.format(this.previewData.exitLoad);
  }
  get formattedGain() {
    return this.previewData?.realizedGain == null
      ? "Incomplete"
      : inr.format(this.previewData.realizedGain);
  }
  get formattedCashAfterLoad() {
    return this.previewData?.estimatedCashAfterLoad == null
      ? "Unknown"
      : inr.format(this.previewData.estimatedCashAfterLoad);
  }
  get formattedTax() {
    return this.previewData?.estimatedTax == null
      ? "Unavailable"
      : inr.format(this.previewData.estimatedTax);
  }
  get formattedNet() {
    return this.previewData?.netProceeds == null
      ? "Unknown"
      : inr.format(this.previewData.netProceeds);
  }
  get lotColumns() {
    return [
      { label: "Account", fieldName: "accountLabel" },
      { label: "Acquired", fieldName: "acquiredOn", type: "date-local" },
      { label: "Eligible on", fieldName: "eligibleOn", type: "date-local" },
      {
        label: "Available units",
        fieldName: "availableUnits",
        type: "number",
        typeAttributes: { maximumFractionDigits: 8 }
      },
      {
        label: "Requested units",
        fieldName: "requestedUnits",
        type: "number",
        typeAttributes: { maximumFractionDigits: 8 }
      },
      { label: "Unit cost", fieldName: "unitCost", ...money },
      { label: "Cost basis", fieldName: "costBasis", ...money },
      { label: "Gross proceeds", fieldName: "grossProceeds", ...money },
      { label: "Exit load", fieldName: "exitLoad", ...money },
      { label: "Realized gain", fieldName: "realizedGain", ...money },
      { label: "Eligibility", fieldName: "eligibility" },
      { label: "Coverage", fieldName: "coverage" }
    ];
  }
  get lotRows() {
    return (this.previewData?.lots || []).map((row, index) => ({
      ...row,
      key: `${row.accountId}-${row.acquiredOn}-${index}`
    }));
  }
  handleFund(event) {
    this.selectedFundId = event.detail.value;
    this.selectedActionId = null;
    this.previewData = null;
    this.selectedAccountId = null;
  }
  handleAccount(event) {
    this.selectedAccountId = event.detail.value || null;
    this.previewData = null;
  }
  handleUnits(event) {
    this.requestedUnits =
      event.target.value === "" ? null : Number(event.target.value);
    this.previewData = null;
  }
  handleSettlement(event) {
    this.settlementDate = event.target.value;
  }
  handleTaxAck(event) {
    this.taxAcknowledged = event.target.checked;
    this.previewData = null;
  }
  handleAction(event) {
    this.selectedActionId = event.detail.value || null;
    this.previewData = null;
    const action = this.selectedAction;
    if (action) {
      this.selectedFundId = action.fundId;
      this.selectedAccountId = action.accountId || null;
      this.requestedUnits = action.units ?? null;
    }
  }
  get request() {
    return {
      portfolioId: this.portfolioData?.portfolioId,
      fundId: this.selectedFundId,
      accountId: this.selectedAccountId,
      planVersionId: this.selectedAction?.versionId,
      actionId: this.selectedActionId,
      requestedUnits: this.requestedUnits,
      settlementDate: this.settlementDate,
      acknowledgeUnknownTax: this.taxAcknowledged
    };
  }
  async previewRedemption() {
    this.saving = true;
    this.errorMessage = null;
    try {
      this.previewData = await preview({ request: this.request });
    } catch (error) {
      this.previewData = null;
      this.errorMessage =
        error.body?.message ||
        error.message ||
        "Unable to calculate FIFO redemption lots.";
    } finally {
      this.saving = false;
    }
  }
  async saveReview() {
    this.saving = true;
    this.errorMessage = null;
    try {
      this.previewData = await saveReview({ request: this.request });
    } catch (error) {
      this.errorMessage =
        error.body?.message ||
        error.message ||
        "Unable to save the redemption review.";
    } finally {
      this.saving = false;
    }
  }
}
