import { LightningElement, wire } from "lwc";
import getPortfolioResearch from "@salesforce/apex/InvResearchService.getPortfolioResearch";
import createAlternatives from "@salesforce/apex/InvPlanScenarioService.createAlternatives";
import getComparison from "@salesforce/apex/InvPlanScenarioService.getComparison";

const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});
export default class InvPlanComparison extends LightningElement {
  research;
  comparison;
  loading = true;
  generating = false;
  errorMessage;
  monthlyBudget = 35000;
  cashNeed = 0;
  cashHoldDays = 0;
  maximumFundCount;
  objective = "Review portfolio consolidation and redemption options";
  retainedFundIds = [];
  exitCandidateFundIds = [];
  excludedNewPurchaseFundIds = [];
  targetWeights = {};
  @wire(getPortfolioResearch, { requestedPortfolioId: null })
  wiredPortfolio({ data, error }) {
    this.loading = false;
    if (data) {
      this.research = data;
      this.errorMessage = null;
      if (data.monthlySip > 0) this.monthlyBudget = data.monthlySip;
    } else if (error) {
      this.errorMessage =
        error.body?.message ||
        "Unable to load the published portfolio baseline.";
    }
  }
  get fundRows() {
    const byFund = new Map();
    for (const row of this.research?.holdings || []) {
      const current = byFund.get(row.fundId) || {
        fundId: row.fundId,
        fundName: row.fundName || "Fund",
        currentValueNumber: 0,
        currentSipNumber: 0
      };
      current.currentValueNumber += row.marketValue || 0;
      byFund.set(row.fundId, current);
    }
    // Keep SIP-only funds in scenarios even when the portfolio has no current holding for them.
    for (const row of this.research?.sips || []) {
      const current = byFund.get(row.fundId) || {
        fundId: row.fundId,
        fundName: row.fundName || "Fund",
        currentValueNumber: 0,
        currentSipNumber: 0
      };
      current.currentSipNumber += row.amount || 0;
      byFund.set(row.fundId, current);
    }
    const rows = [...byFund.values()];
    const total = rows.reduce((sum, row) => sum + row.currentValueNumber, 0);
    return rows.map((row) => ({
      ...row,
      currentValue: inr.format(row.currentValueNumber),
      currentSip: inr.format(row.currentSipNumber),
      targetPercent:
        this.targetWeights[row.fundId] ??
        (total > 0
          ? Number(((row.currentValueNumber * 100) / total).toFixed(2))
          : 0)
    }));
  }
  get fundOptions() {
    return this.fundRows
      .filter((row) => row.currentValueNumber > 0 || row.currentSipNumber > 0)
      .map((row) => ({ label: row.fundName, value: row.fundId }));
  }
  get hasImpacts() {
    return (this.comparison?.impacts || []).length > 0;
  }
  get hasIncompleteValuation() {
    return (this.research?.holdings || []).some(
      (row) =>
        row.status === "Active" &&
        row.units > 0 &&
        (row.marketValue == null ||
          row.fundId == null ||
          row.mappingVerified !== true)
    );
  }
  get generateDisabled() {
    return (
      this.generating ||
      !this.research?.baselineRunId ||
      this.hasIncompleteValuation
    );
  }
  get targetReadinessMessage() {
    return this.hasIncompleteValuation
      ? "At least one active holding has a missing value or unverified share-class identity. Resolve it before generating trade comparisons; uncertain positions must stay unresolved."
      : null;
  }
  get comparisonColumns() {
    const variants = this.comparison?.alternatives || [];
    return [
      { label: "Measure", fieldName: "metric" },
      { label: "Fund / scope", fieldName: "subject" },
      { label: "Baseline", fieldName: "baselineDisplay" },
      ...variants.map((variant, index) => ({
        label: variant.title,
        fieldName: `alternative${index + 1}`
      })),
      { label: "Coverage", fieldName: "coverage", wrapText: true },
      { label: "Assumptions", fieldName: "notes", wrapText: true }
    ];
  }
  get comparisonRows() {
    const alternatives = this.comparison?.alternatives || [];
    const indexByVersion = new Map(
      alternatives.map((row, index) => [row.versionId, index])
    );
    const keyed = new Map();
    for (const impact of this.comparison?.impacts || []) {
      const key = `${impact.metric}|${impact.fundId || "portfolio"}|${impact.dimension || ""}|${impact.member || ""}`;
      const row = keyed.get(key) || {
        key,
        metric: impact.metric,
        subject: impact.fundName || impact.member || "Portfolio",
        baselineDisplay: this.formatMetric(impact.metric, impact.baseline),
        coverage: impact.coverage,
        notes: impact.notes
      };
      const index = indexByVersion.get(impact.versionId);
      if (index !== undefined)
        row[`alternative${index + 1}`] = this.formatMetric(
          impact.metric,
          impact.proposed
        );
      if (impact.coverage === "policy_review_required")
        row.coverage = "Redemption policy review required";
      keyed.set(key, row);
    }
    return [...keyed.values()];
  }
  handleBudget(e) {
    this.monthlyBudget = Number(e.target.value);
  }
  handleCashNeed(e) {
    this.cashNeed = Number(e.target.value);
  }
  handleCashHold(e) {
    this.cashHoldDays = Number(e.target.value);
  }
  handleMaximumFunds(e) {
    this.maximumFundCount = e.target.value ? Number(e.target.value) : null;
  }
  handleObjective(e) {
    this.objective = e.target.value;
  }
  handleRetain(e) {
    this.retainedFundIds = e.detail.value;
  }
  handleExit(e) {
    this.exitCandidateFundIds = e.detail.value;
  }
  handleExcludedNewPurchase(e) {
    this.excludedNewPurchaseFundIds = e.detail.value;
  }
  handleTarget(e) {
    this.targetWeights = {
      ...this.targetWeights,
      [e.target.dataset.fundId]: Number(e.target.value || 0)
    };
  }
  formatMetric(metric, value) {
    if (value == null) return "Unavailable";
    if (metric.toLowerCase().includes("inr")) return inr.format(value);
    return Number(value).toLocaleString("en-IN", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    });
  }
  async generate() {
    if (!this.research?.portfolioId) {
      this.errorMessage = "No accessible portfolio baseline is available.";
      return;
    }
    this.generating = true;
    this.comparison = null;
    this.errorMessage = null;
    try {
      const targetAllocations = this.fundRows.map((row) => ({
        fundId: row.fundId,
        weightPercent: this.targetWeights[row.fundId] ?? 0
      }));
      const created = await createAlternatives({
        input: {
          portfolioId: this.research.portfolioId,
          monthlyBudget: this.monthlyBudget,
          cashNeed: this.cashNeed,
          cashHoldDays: this.cashHoldDays,
          maximumFundCount: this.maximumFundCount,
          retainedFundIds: this.retainedFundIds,
          exitCandidateFundIds: this.exitCandidateFundIds,
          excludedNewPurchaseFundIds: this.excludedNewPurchaseFundIds,
          targetAllocations,
          objective: this.objective
        }
      });
      this.comparison = await getComparison({
        versionIds: created.alternatives.map((row) => row.versionId)
      });
      this.comparison.baselineDate = created.baselineDate;
    } catch (error) {
      this.errorMessage =
        error.body?.message ||
        error.message ||
        "Unable to create and compare the draft alternatives.";
    } finally {
      this.generating = false;
    }
  }
}
