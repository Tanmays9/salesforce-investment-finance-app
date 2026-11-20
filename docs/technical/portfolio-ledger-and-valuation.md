---
title: Portfolio ledger and valuation
description: How posted investment activity becomes holdings, valuations, performance, and movement analysis.
---

# Portfolio ledger and valuation

This guide follows a posted investment ledger through a dated calculation run to the Overview, Holdings and movement analysis UI.

## Entry points and primary code

- `invPortfolioResearch` calls `InvResearchService.getPortfolioResearch()` and `InvMovementService.compare()`.
- `InvPortfolioEngine.calculate(portfolioId, asOf[, pipelineId])` builds the position snapshot and publishes portfolio analysis.
- `InvRecalculate` queues calculation work and tracks portfolio valuation, exposure and fund-metric stages.
- `InvMath` parses exact decimals, applies FIFO lots and calculates supported XIRR results.
- The principal output records are `Inv_AnalyticsRuns__c`, `Inv_HoldingValuation__c`, `Inv_PortfolioValuation__c`, `Inv_Exposure__c` and `Inv_FundMetric__c`.

Open the implementation in [`InvPortfolioEngine.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPortfolioEngine.cls), [`InvRecalculate.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvRecalculate.cls), [`InvMath.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvMath.cls) and [`InvResearchService.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvResearchService.cls).

## Calculation lifecycle

**Run sequence:** a scheduled or controlled refresh starts the Queueable pipeline → `InvPortfolioEngine` reads posted activity, snapshots and SIP evidence at the run cutoffs → `InvNAVPolicy` selects accepted prices → the engine writes run-scoped valuations and coverage → exposure/metrics stages complete → only then is the successful run published → the LWC reads that run's immutable outputs.

The run captures a stable input fingerprint, valuation date, ledger cutoff, knowledge cutoff and calculation version (`sf-portfolio-1`). The engine calculates into a new run; consumers continue to see the prior successful run if a stage fails. A status issue identifies incomplete or failed work.

## Unit and cost calculation

1. Read posted events and unit entries within the run's date and knowledge cutoffs. Apply reversals only when their effective and known times are inside those cutoffs.
2. Group activity by investment account and instrument. Account boundaries are significant; lots from one account are never used to cover a redemption from another.
3. Order acquisition lots chronologically by acquisition/event day, source sequence and stable ID. Apply redemption movements against the oldest available lots.
4. Preserve remaining lot units, cost basis, acquisition dates and basis coverage. If a redemption exceeds available units, or source history is incomplete, mark the affected result for review rather than inventing units or cost.
5. Reconcile computed positions with the latest applicable statement position snapshot. A snapshot is balance evidence, not an additional unit movement.

`InvMath` computes supported XIRR using dated cash flows and terminal market value. It requires conventional inflow/outflow sign changes and a bracketed root. It returns explicit states for invalid inputs, insufficient history, nonconventional cash flows and no bracketed solution. Portfolio XIRR remains unavailable until external cash history is confirmed.

## Valuation and publication

- `InvNAVPolicy` centralizes accepted-price selection. A valid NAV must be positive, accepted, on or before the run's valuation date, and within its knowledge cutoff.
- Units × selected NAV yields market value. Remaining lot cost, realized gain, unrealized gain, SIP amount and XIRR are separate outputs.
- The engine stores per-fund/account valuations and the portfolio aggregate against the same immutable run. History therefore remains reproducible if today's holding record changes later.
- Display currency can be rounded to two decimal places without rounding the calculation inputs. Units and NAV preserve their own precision.
- Mixed NAV dates are shown as latest-available-NAV valuation with the covered date range. A retrieval date does not imply that a fund published a NAV on that date.

## Coverage and interpretation

The API carries coverage separately for unit reconciliation, acquisition basis, redemption, personal return, NAV, composition and policy. Do not collapse these into one “complete” state when building new UI or reports. For example, units can reconcile while acquisition cost or tax-policy evidence remains incomplete.

Portfolio value history answers “what was this portfolio worth on each valuation date?” It is not a performance series. `InvMovementService` compares selected published runs and attributes available changes to purchases, redemptions, other unit movements, comparable-unit market movement, reconciliation changes and an explicit residual. If evidence is incomplete, the result is labeled partial rather than presenting a false complete attribution.

## Development and verification pointers

- Tests: `InvMathTest`, `InvPortfolioEngineTest`, `InvRefreshTest`, `InvResearchServicesTest` and `InvPlanGuardTest`.
- Confirm tests exercise date cutoffs, reversal knowledge, FIFO within account/instrument, partial redemptions, duplicate ingestion and safe null/precision handling before changing calculation contracts.
- Do not update actual holdings from a scenario evaluation. Plan evaluation consumes the selected immutable baseline; it is not a ledger posting operation.
- For generated read-only user experience and permissions, see [Lightning experience and access](./lightning-experience-and-access.md). For scenario calculations, see [Planning and redemptions](./planning-and-redemptions.md).
