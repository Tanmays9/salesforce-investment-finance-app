import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { loadScript } from "lightning/platformResourceLoader";
import CHARTJS from "@salesforce/resourceUrl/chartjs";
import getPortfolioResearch from "@salesforce/apex/InvResearchService.getPortfolioResearch";
import compareMovement from "@salesforce/apex/InvMovementService.compare";

const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});
const currencyColumn = {
  type: "currency",
  typeAttributes: {
    currencyCode: "INR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }
};

export default class InvPortfolioResearch extends NavigationMixin(
  LightningElement
) {
  // App pages do not receive a recordId. Passing null selects the portfolio's published baseline.
  @api recordId = null;
  data;
  errorMessage;
  loading = true;
  searchTerm = "";
  statusFilter = "Active";
  reviewFilter = "All";
  categoryFilter = "All";
  amcFilter = "All";
  withoutSip = false;
  exposureDimension = "Security";
  allocationDimension = "Fund";
  allocationFilter;
  allocationFilterLabel;
  allocationFilterDimension;
  movementStartRunId;
  movementEndRunId;
  movementResult;
  movementError;
  movementLoading = false;
  chartReady = false;
  historyChart;
  allocationChart;
  _chartPromise;

  connectedCallback() {
    this.loadPortfolio();
  }
  async loadPortfolio() {
    if (this._portfolioRequestInFlight) return;
    this._portfolioRequestInFlight = true;
    this.loading = true;
    this.errorMessage = null;
    try {
      const data = await getPortfolioResearch({
        requestedPortfolioId: this.recordId || null
      });
      this.data = data;
      const points = data?.marketValueHistory || [];
      if (points.length > 1 && !this.movementStartRunId) {
        this.movementStartRunId = points[points.length - 2].runId;
        this.movementEndRunId = points[points.length - 1].runId;
        this.loadMovement();
      }
    } catch (error) {
      this.data = null;
      this.errorMessage =
        error.body?.message ||
        error.message ||
        "Unable to load the published portfolio analysis.";
    } finally {
      this.loading = false;
      this._portfolioRequestInFlight = false;
      this.renderCharts();
    }
  }

  get summaryCards() {
    if (!this.data) return [];
    return [
      {
        label: "Market value",
        value:
          this.data.marketValue == null
            ? "Incomplete"
            : inr.format(this.data.marketValue)
      },
      {
        label: "Remaining cost",
        value:
          this.data.remainingCost == null
            ? "Incomplete"
            : inr.format(this.data.remainingCost)
      },
      {
        label: "Unrealized gain",
        value:
          this.data.unrealizedGain == null
            ? "Incomplete"
            : inr.format(this.data.unrealizedGain)
      },
      {
        label: "Realized gain",
        value:
          this.data.realizedGain == null
            ? "Incomplete"
            : inr.format(this.data.realizedGain)
      },
      { label: "Active funds", value: String(this.data.activeFundCount ?? 0) },
      {
        label: "Monthly SIP",
        value:
          this.data.monthlySip == null
            ? "Incomplete"
            : inr.format(this.data.monthlySip)
      }
    ];
  }
  get overviewHoldingColumns() {
    return [
      {
        label: "Fund",
        fieldName: "fundUrl",
        type: "url",
        typeAttributes: { label: { fieldName: "fundName" }, target: "_self" }
      },
      { label: "Category", fieldName: "category" },
      { label: "Market value", fieldName: "marketValue", ...currencyColumn },
      {
        label: "Allocation",
        fieldName: "weight",
        type: "percent",
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      },
      { label: "Gain / loss", fieldName: "unrealizedGain", ...currencyColumn },
      {
        label: "Personal XIRR",
        fieldName: "xirr",
        type: "percent",
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      }
    ];
  }
  get allocationColumns() {
    return [
      { label: this.allocationDimension, fieldName: "label" },
      {
        label: "Value represented (INR)",
        fieldName: "value",
        ...currencyColumn
      }
    ];
  }
  get reviewColumns() {
    return [
      {
        label: "Fund",
        fieldName: "fundUrl",
        type: "url",
        typeAttributes: { label: { fieldName: "fundName" }, target: "_self" }
      },
      { label: "Position", fieldName: "status" },
      { label: "Coverage", fieldName: "coverage" },
      { label: "Review note", fieldName: "reviewReason", wrapText: true }
    ];
  }
  get overviewHoldings() {
    return (this.data?.holdings || [])
      .filter((row) => row.status === "Active" && row.marketValue > 0)
      .slice(0, 6)
      .map((row, index) => ({
        ...row,
        holdingId: row.holdingId || `${row.fundId}-${index}`,
        fundUrl: row.fundId
          ? `/lightning/r/Inv_MarketInstruments__c/${row.fundId}/view`
          : null
      }));
  }
  get reviewHoldings() {
    return (this.data?.holdings || [])
      .filter((row) => row.coverage !== "complete" || row.warnings)
      .map((row, index) => ({
        ...row,
        holdingId: row.holdingId || `${row.fundId}-review-${index}`,
        fundUrl: row.fundId
          ? `/lightning/r/Inv_MarketInstruments__c/${row.fundId}/view`
          : null,
        reviewReason: row.warnings || `Coverage: ${row.coverage || "unknown"}`
      }));
  }
  get hasReviewHoldings() {
    return this.reviewHoldings.length > 0;
  }
  get reviewCount() {
    return this.reviewHoldings.length;
  }
  get hasSips() {
    return this.sipRows.length > 0;
  }
  get holdingColumns() {
    return [
      {
        label: "Fund",
        fieldName: "fundUrl",
        type: "url",
        typeAttributes: { label: { fieldName: "fundName" }, target: "_self" }
      },
      {
        label: "Identity verified",
        fieldName: "mappingVerified",
        type: "boolean"
      },
      { label: "Category", fieldName: "category" },
      { label: "AMC", fieldName: "amc" },
      { label: "Status", fieldName: "status" },
      {
        label: "Units",
        fieldName: "units",
        type: "number",
        typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 8 }
      },
      { label: "NAV date", fieldName: "navDate", type: "date-local" },
      { label: "Market value", fieldName: "marketValue", ...currencyColumn },
      {
        label: "Allocation",
        fieldName: "weight",
        type: "percent",
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      },
      { label: "Gain / loss", fieldName: "unrealizedGain", ...currencyColumn },
      {
        label: "Personal XIRR",
        fieldName: "xirr",
        type: "percent",
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      },
      { label: "Monthly SIP", fieldName: "monthlySip", ...currencyColumn },
      { label: "Data coverage", fieldName: "coverage" }
    ];
  }
  get historyColumns() {
    return [
      { label: "Valuation date", fieldName: "day", type: "date-local" },
      { label: "Market value (INR)", fieldName: "value", ...currencyColumn },
      {
        label: "Remaining cost (INR)",
        fieldName: "comparison",
        ...currencyColumn
      }
    ];
  }
  get valuationOptions() {
    return (this.data?.marketValueHistory || []).map((point) => ({
      label: `${point.day} · ${point.value == null ? "Incomplete value" : inr.format(point.value)}`,
      value: point.runId
    }));
  }
  get movementColumns() {
    return [
      { label: "Fund", fieldName: "fundName" },
      { label: "Account", fieldName: "accountLabel" },
      {
        label: "Opening units",
        fieldName: "openingUnits",
        type: "number",
        typeAttributes: { maximumFractionDigits: 8 }
      },
      {
        label: "Closing units",
        fieldName: "closingUnits",
        type: "number",
        typeAttributes: { maximumFractionDigits: 8 }
      },
      { label: "Value change", fieldName: "valueChange", ...currencyColumn },
      {
        label: "Market movement",
        fieldName: "marketMovement",
        ...currencyColumn
      },
      { label: "Purchases", fieldName: "purchases", ...currencyColumn },
      { label: "Redemptions", fieldName: "redemptions", ...currencyColumn },
      {
        label: "Other unit movements",
        fieldName: "otherUnitMovements",
        ...currencyColumn
      },
      {
        label: "Reconciliation adjustment",
        fieldName: "reconciliationAdjustment",
        ...currencyColumn
      },
      { label: "Residual", fieldName: "residual", ...currencyColumn },
      { label: "Coverage", fieldName: "coverage" }
    ];
  }
  get movementSummary() {
    if (!this.movementResult) return [];
    const result = this.movementResult;
    return [
      {
        label: "Portfolio value change",
        value:
          result.valueChange == null
            ? "Incomplete"
            : inr.format(result.valueChange)
      },
      {
        label: "Market movement",
        value:
          result.marketMovement == null
            ? "Incomplete"
            : inr.format(result.marketMovement)
      },
      {
        label: "Purchases",
        value:
          result.purchases == null ? "Incomplete" : inr.format(result.purchases)
      },
      {
        label: "Redemptions",
        value:
          result.redemptions == null
            ? "Incomplete"
            : inr.format(result.redemptions)
      },
      {
        label: "Other unit movements",
        value:
          result.otherUnitMovements == null
            ? "Incomplete"
            : inr.format(result.otherUnitMovements)
      },
      {
        label: "Reconciliation adjustment",
        value:
          result.reconciliationAdjustment == null
            ? "Incomplete"
            : inr.format(result.reconciliationAdjustment)
      },
      {
        label: "Unattributed residual",
        value:
          result.residual == null ? "Incomplete" : inr.format(result.residual)
      }
    ];
  }
  get exposureColumns() {
    return [
      { label: "Member", fieldName: "member" },
      { label: "Fund", fieldName: "fundName" },
      {
        label: "Disclosure date",
        fieldName: "disclosureDate",
        type: "date-local"
      },
      {
        label: "Attributed value (INR)",
        fieldName: "value",
        ...currencyColumn
      },
      {
        label: "Portfolio weight",
        fieldName: "weight",
        type: "percent",
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
      },
      { label: "Coverage", fieldName: "coverage" },
      { label: "Source labels", fieldName: "sourceLabels", wrapText: true }
    ];
  }
  get sipColumns() {
    return [
      { label: "Fund", fieldName: "fundName" },
      { label: "Monthly amount", fieldName: "amount", ...currencyColumn },
      { label: "Account", fieldName: "accountLabel" },
      {
        label: "Effective from",
        fieldName: "effectiveFrom",
        type: "date-local"
      },
      { label: "Effective to", fieldName: "effectiveTo", type: "date-local" }
    ];
  }
  get statusOptions() {
    return [
      { label: "Active", value: "Active" },
      { label: "Closed", value: "Closed" },
      { label: "All", value: "All" }
    ];
  }
  get reviewOptions() {
    return [
      { label: "All", value: "All" },
      { label: "Needs review", value: "Review" },
      { label: "No review flags", value: "Clear" }
    ];
  }
  get dimensionOptions() {
    return ["Security", "Sector", "Market cap", "Asset class"].map((value) => ({
      label: value,
      value
    }));
  }
  get allocationOptions() {
    return [
      "Fund",
      "Category",
      "AMC",
      "Security",
      "Sector",
      "Market cap",
      "Asset class"
    ].map((value) => ({ label: value, value }));
  }
  get allocationTitle() {
    return `Allocation by ${this.allocationDimension}`;
  }
  get categoryOptions() {
    return [
      { label: "All categories", value: "All" },
      ...[
        ...new Set(
          (this.data?.holdings || []).map((row) => row.category).filter(Boolean)
        )
      ]
        .sort()
        .map((value) => ({ label: value, value }))
    ];
  }
  get amcOptions() {
    return [
      { label: "All AMCs", value: "All" },
      ...[
        ...new Set(
          (this.data?.holdings || []).map((row) => row.amc).filter(Boolean)
        )
      ]
        .sort()
        .map((value) => ({ label: value, value }))
    ];
  }
  get allocationGroups() {
    const groups = new Map();
    const add = (label, value, key) => {
      const safeLabel = label || "Unknown / unclassified";
      if (value == null || value <= 0) return;
      const group = groups.get(key) || { key, label: safeLabel, value: 0 };
      group.value += value;
      groups.set(key, group);
    };
    if (["Fund", "Category", "AMC"].includes(this.allocationDimension)) {
      for (const row of this.data?.holdings || []) {
        if (row.status !== "Active" || !(row.marketValue > 0)) continue;
        const label =
          this.allocationDimension === "Fund"
            ? row.fundName
            : row[this.allocationDimension.toLowerCase()];
        const key =
          this.allocationDimension === "Fund" ? row.fundId : label || "unknown";
        add(label, row.marketValue, key);
      }
    } else {
      for (const row of this.data?.exposures || [])
        if (row.dimension === this.allocationDimension)
          add(row.member, row.value, row.memberKey || row.member || "unknown");
    }
    return [...groups.values()].sort((left, right) => right.value - left.value);
  }
  get allocationRows() {
    return this.allocationGroups.map((row, index) => ({
      key: `${row.key}-${index}`,
      label: row.label,
      value: row.value
    }));
  }
  get visibleHoldings() {
    const rows = (this.data?.holdings || []).map((row, index) => ({
      ...row,
      holdingId: row.holdingId || `${row.fundId}-${index}`,
      fundUrl: row.fundId
        ? `/lightning/r/Inv_MarketInstruments__c/${row.fundId}/view`
        : null
    }));
    const term = this.searchTerm.trim().toLowerCase();
    const sipFunds = new Set((this.data?.sips || []).map((row) => row.fundId));
    return rows.filter(
      (row) =>
        (this.statusFilter === "All" || row.status === this.statusFilter) &&
        (!term ||
          `${row.fundName || ""} ${row.category || ""} ${row.amc || ""}`
            .toLowerCase()
            .includes(term)) &&
        (!this.categoryFilter ||
          this.categoryFilter === "All" ||
          row.category === this.categoryFilter) &&
        (!this.amcFilter ||
          this.amcFilter === "All" ||
          row.amc === this.amcFilter) &&
        (!this.withoutSip || !sipFunds.has(row.fundId)) &&
        (this.reviewFilter === "All" ||
          (this.reviewFilter === "Review"
            ? row.coverage !== "complete"
            : row.coverage === "complete")) &&
        (!this.allocationFilter ||
          !["Fund", "Category", "AMC"].includes(
            this.allocationFilterDimension
          ) ||
          (this.allocationFilterDimension === "Fund" &&
            row.fundId === this.allocationFilter) ||
          (this.allocationFilterDimension === "Category" &&
            row.category === this.allocationFilter) ||
          (this.allocationFilterDimension === "AMC" &&
            row.amc === this.allocationFilter))
    );
  }
  get historyRows() {
    return (this.data?.marketValueHistory || []).map((row, index) => ({
      ...row,
      day: row.day || String(index)
    }));
  }
  get visibleExposures() {
    return (this.data?.exposures || [])
      .filter(
        (row) =>
          row.dimension === this.exposureDimension &&
          (!this.allocationFilter ||
            this.allocationFilterDimension !== this.exposureDimension ||
            row.memberKey === this.allocationFilter ||
            row.member === this.allocationFilter)
      )
      .map((row, index) => ({
        ...row,
        key: `${row.fundId}-${row.dimension}-${row.memberKey}-${index}`
      }));
  }
  get sipRows() {
    return (this.data?.sips || []).map((row, index) => ({
      ...row,
      id: `${row.fundId}-${row.accountLabel}-${row.effectiveFrom}-${index}`
    }));
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }
  handleStatus(event) {
    this.statusFilter = event.detail.value;
  }
  handleReview(event) {
    this.reviewFilter = event.detail.value;
  }
  handleCategory(event) {
    this.categoryFilter = event.detail.value;
  }
  handleAmc(event) {
    this.amcFilter = event.detail.value;
  }
  handleWithoutSip(event) {
    this.withoutSip = event.target.checked;
  }
  handleDimension(event) {
    this.exposureDimension = event.detail.value;
  }
  handleAllocationDimension(event) {
    this.allocationDimension = event.detail.value;
    this.allocationFilter = null;
    this.allocationFilterDimension = null;
    this.allocationChart?.destroy();
    this.allocationChart = null;
    this.renderCharts();
  }
  clearAllocationFilter() {
    this.allocationFilter = null;
    this.allocationFilterLabel = null;
    this.allocationFilterDimension = null;
  }
  handleMovementStart(event) {
    this.movementStartRunId = event.detail.value;
    this.movementResult = null;
  }
  handleMovementEnd(event) {
    this.movementEndRunId = event.detail.value;
    this.movementResult = null;
  }
  get movementDisabled() {
    return (
      this.movementLoading ||
      !this.data?.portfolioId ||
      !this.movementStartRunId ||
      !this.movementEndRunId ||
      this.movementStartRunId === this.movementEndRunId
    );
  }
  async loadMovement() {
    if (this.movementDisabled) return;
    this.movementLoading = true;
    this.movementError = null;
    try {
      this.movementResult = await compareMovement({
        portfolioId: this.data.portfolioId,
        openingRunId: this.movementStartRunId,
        closingRunId: this.movementEndRunId
      });
    } catch (error) {
      this.movementResult = null;
      this.movementError =
        error.body?.message ||
        error.message ||
        "Unable to attribute this portfolio movement.";
    } finally {
      this.movementLoading = false;
    }
  }
  openPlanComparison() {
    this.openNavItem("Inv_PlanComparison");
  }
  openRedemptionReview() {
    this.openNavItem("Inv_RedemptionReview");
  }
  openDataHealth() {
    this.openObject("Inv_OpsDataIssues__c");
  }
  openHoldings() {
    this.openObject("Inv_Holding__c");
  }
  openNavItem(apiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: { apiName }
    });
  }
  openObject(objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName, actionName: "list" }
    });
  }
  handleRowAction(event) {
    const row = event.detail.row;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: row.fundId,
        objectApiName: "Inv_MarketInstruments__c",
        actionName: "view"
      }
    });
  }
  renderedCallback() {
    this.renderCharts();
  }
  renderCharts() {
    if (!this.data || !this.isConnected) return;
    // renderedCallback can repeat after state updates, so guard library loading and chart creation.
    if (!this._chartPromise)
      this._chartPromise = loadScript(this, `${CHARTJS}/chart.umd.min.js`)
        .then(() => {
          this.chartReady = true;
        })
        .catch(() => {
          this.chartReady = false;
        });
    this._chartPromise.then(() => {
      if (!this.chartReady || !window.Chart) return;
      const historyCanvas = this.template.querySelector(".historyChart");
      if (
        historyCanvas &&
        this.data.marketValueHistory?.length &&
        !this.historyChart
      )
        this.historyChart = new window.Chart(historyCanvas, {
          type: "line",
          data: {
            labels: this.data.marketValueHistory.map((row) => row.day),
            datasets: [
              {
                label: "Market value",
                data: this.data.marketValueHistory.map((row) => row.value),
                borderColor: "#176b87",
                pointRadius: 0,
                tension: 0.15
              },
              {
                label: "Remaining cost",
                data: this.data.marketValueHistory.map((row) => row.comparison),
                borderColor: "#d17b27",
                pointRadius: 0,
                tension: 0.1
              }
            ]
          },
          options: {
            responsive: true,
            interaction: { intersect: false, mode: "index" },
            scales: {
              y: { ticks: { callback: (value) => inr.format(value) } }
            },
            plugins: {
              tooltip: {
                callbacks: {
                  label: (context) =>
                    `${context.dataset.label}: ${inr.format(context.parsed.y)}`
                }
              }
            }
          }
        });
      const allocationCanvas = this.template.querySelector(".allocationChart");
      const groups = this.allocationGroups;
      if (allocationCanvas && groups.length && !this.allocationChart)
        this.allocationChart = new window.Chart(allocationCanvas, {
          type: "doughnut",
          data: {
            labels: groups.map((row) => row.label),
            datasets: [
              {
                data: groups.map((row) => row.value),
                backgroundColor: [
                  "#176b87",
                  "#4e9a84",
                  "#d17b27",
                  "#7b6ea8",
                  "#dc7771",
                  "#74a5cc",
                  "#ad8d5c",
                  "#63816b"
                ]
              }
            ]
          },
          options: {
            responsive: true,
            onClick: (_event, elements) => {
              if (elements.length) {
                const selected = groups[elements[0].index];
                this.allocationFilter = selected.key;
                this.allocationFilterLabel = selected.label;
                this.allocationFilterDimension = this.allocationDimension;
                if (
                  !["Fund", "Category", "AMC"].includes(
                    this.allocationDimension
                  )
                )
                  this.exposureDimension = this.allocationDimension;
              }
            },
            plugins: {
              tooltip: {
                callbacks: {
                  label: (context) =>
                    `${context.label}: ${inr.format(context.parsed)}`
                }
              }
            }
          }
        });
    });
  }
  disconnectedCallback() {
    this.historyChart?.destroy();
    this.allocationChart?.destroy();
  }
}
