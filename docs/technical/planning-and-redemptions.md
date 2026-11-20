---
title: Planning and redemption review
description: Versioned plan alternatives, evaluation against an immutable baseline, FIFO redemption estimates, and execution reconciliation.
---

# Planning and redemption review

Planning records describe proposals. Evaluating or approving a plan does not change holdings, submit a broker order or alter a SIP mandate.

## Draft plan workflow

`InvPlanService` is the Flow-facing service for creating plans and versions, adding/editing/removing draft actions, targets and dependencies, cloning a version, evaluating, and approving. It requires the Portfolio Manager permission for mutations. The Screen Flows in `force-app/main/default/flows/` present these actions through standard Salesforce records.

Plan actions include keep, redeem, buy, SIP changes, pause SIP and cash hold. Draft versions retain:

- A published baseline run reference and input fingerprint.
- User-selected review constraints (retained/exit-candidate/no-new-purchase funds, target weights, maximum fund count, SIP budget, cash need and cash-hold days).
- Versioned action, target, dependency and evaluation records.
- Comparison metrics, calculation rationale and unresolved constraints.

`InvPlanScenarioService.createAlternatives()` creates three deterministic editable versions from explicitly entered constraints: SIP-only changes, minimum turnover and target alignment. It does not infer a core fund or silently relax conflicting constraints. If the baseline is stale or its fingerprint changes, evaluation requires a rebase/review instead of silently using current mutable holdings.

## Evaluation sequence

1. Resolve the selected portfolio's published analysis run and read its immutable holdings/valuation rows.
2. Compare the request fingerprint with the run and version's captured fingerprints.
3. Validate dates, available cash, account/fund mappings, action dependencies and the directed acyclic dependency graph in `InvPlanRules`.
4. Apply proposed buys, redemptions, contribution changes and cash-hold periods to an isolated scenario state at baseline prices.
5. Compare fund count, retained/closed positions, allocation, exposures, SIP budget, estimated proceeds, funding dates, readiness and unmet constraints.
6. Persist version-specific `Inv_PlanImpact__c`/analysis outputs and rationale. The actual ledger and current holdings are not changed.

Evaluation is deterministic for the same input fingerprint and baseline. A comparison must use alternatives on the same baseline; mismatched run/fingerprint inputs are rejected. Baseline market values are scenario assumptions, not a forecast.

## Redemption review

`InvRedemptionService` previews or stores a redemption review from the baseline position and FIFO lots. The reusable `invRedemptionReview` component lets the user select a draft redemption action, fund/account, requested units and settlement date, and explicitly acknowledge an unknown tax estimate where needed.

The service reports separately:

- Eligible, locked and unknown lots with acquisition dates and remaining units.
- Remaining acquisition cost and basis coverage.
- Estimated gross proceeds, applicable dated exit load and realized gain.
- Tax coverage/assumptions and an estimated net amount only where supportable.
- Settlement date as an explicit assumption and readiness blockers.

ELSS lock-in, exit-load and eligibility checks depend on dated evidence. Missing evidence remains unknown. Tax is not calculated using hard-coded rates; missing personal regime/year/assumption data leaves tax unavailable. A proceeds estimate is not the same as settlement cash available for a linked purchase.

Approval rechecks readiness and freezes the plan version. A later change creates a new version. The schema includes planned-execution evidence records, but the repository has no broker order-submission integration or automated SIP mandate control. Reconcile actual activity through reviewed statement imports and retain mismatches for human review; do not treat an approved plan as executed.

## Important code paths

| Concern | Source |
|---|---|
| Plan flow actions and version mutations | [`InvPlanService.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPlanService.cls) |
| Constraint-based alternatives and impact results | [`InvPlanScenarioService.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPlanScenarioService.cls) |
| Action dates, dependencies and validation rules | [`InvPlanRules.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPlanRules.cls) |
| FIFO lots and estimate/review persistence | [`InvRedemptionService.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvRedemptionService.cls) |
| Apex calculations for underlying exposure in alternatives | [`InvPlanExposure.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPlanExposure.cls) |
| Comparison and redemption UI | `force-app/main/default/lwc/invPlanComparison/`, `invRedemptionReview/` |
| Flow entry points | `force-app/main/default/flows/Inv_CreatePlan.flow-meta.xml`, `Inv_EvaluatePlan.flow-meta.xml`, `Inv_ApprovePlan.flow-meta.xml`, `Inv_ImportCAS.flow-meta.xml` |

## Extension guidance

Add a new action type only with an explicit calculation contract, validations, action/dependency UI, baseline impact, readiness evidence and tests. Keep unknown values and coverage explicit. Never let a display-only component calculate final FIFO/tax outputs or mutate ledger records directly. For permissions and the viewer/manager split, see [Lightning experience and access](./lightning-experience-and-access.md).
