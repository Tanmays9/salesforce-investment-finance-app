---
title: Technical implementation map
description: Codebase architecture, feature guides, boundaries, and developer entry points.
---

# Technical implementation map

This guide explains the implementation currently checked into this repository. It is intended for developers tracing a user-visible feature from its Salesforce entry point through the Lightning UI, Apex service, records, integrations, and deployment metadata.

## Start with the feature you are changing

| Feature | Read first | Main implementation |
|---|---|---|
| Portfolio overview, holdings and movement | [Portfolio ledger and valuation](./portfolio-ledger-and-valuation.md) | [`InvPortfolioEngine`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvPortfolioEngine.cls), [`InvResearchService`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvResearchService.cls), `invPortfolioResearch` |
| NAV, benchmarks, fund research, exposure | [Market data and fund research](./market-data-and-fund-research.md) | [`InvNAVRefresh`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvNAVRefresh.cls), `InvBenchmarkRefresh`, `InvFundMetrics`, `InvExposureEngine`, `invFundResearch` |
| CAS PDF import and duplicate controls | [CAS import](./cas-import.md) | [`InvCASService`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvCASService.cls), `InvImportActions`, parser under `tools/portfolio/cas/` |
| Draft alternatives and redemption review | [Planning and redemptions](./planning-and-redemptions.md) | `InvPlanScenarioService`, `InvPlanService`, `InvRedemptionService`, `invPlanComparison`, `invRedemptionReview` |
| Lightning app, pages, Flows and permissions | [Lightning experience and access](./lightning-experience-and-access.md) | `force-app/main/default/applications/`, `flexipages/`, `flows/`, `lwc/`, `permissionsets/` |
| A new Salesforce production org | [Deploy to a new org](./deploy-to-new-org.md) | `tools/portfolio/package.py`, `manifest/portfolio-release.xml`, Salesforce CLI, post-deploy scripts |
| Health checks and test locations | [Operations and testing](./operations-and-testing.md) | Data Issues, Apex tests, scheduled jobs, migration and CAS rehearsal tools |

For field definitions and record grain, read [Data model and provenance](./data-model-and-provenance.md).

## System shape

**Main request path:** Lightning app → research/workflow Apex → calculation services → Salesforce investment records.

**Market data path:** MFapi, AMFI and supported index feeds → refresh Queueables → dated observations → analysis run.

**Statement path:** Salesforce Files → optional API Gateway/Lambda `casparser` service → staged import rows → user reconciliation and confirmation → ledger events → recalculation.

Salesforce is the operational store for the deployed application. Apex contains financial calculations and mutating workflow services. Standard Salesforce pages, reports, dashboards and Flows provide most CRUD and navigation. Custom Lightning Web Components provide coordinated research, charts and scenario previews. The CAS parser is an optional, separately deployed AWS service; it stages statement data and does not itself post ledger transactions.

## Implementation conventions

- Treat the source under `force-app/main/default/` as the deployable Salesforce DX implementation. API version is declared in `sfdx-project.json`.
- Treat `tools/portfolio/model.json` and the generators in `tools/portfolio/` as the operational metadata source. Generated Salesforce metadata lives under `force-app/` and scoped manifests under `manifest/`.
- Treat `tools/investment-migration/mapping.json` as the canonical source mapping for preserved legacy records. Migration utilities use protected local exports and an explicit migration run.
- Calculations are dated and versioned. A successful published analysis run points to immutable valuation rows; a failed refresh leaves the last successful run available and exposes failure status.
- Keep original decimals and provenance. Typed numeric projections can be blank when they would silently lose source precision; do not interpret blank as zero.
- User intent is not an automatic trade. Plans are drafts and readiness reviews; the app has no broker execution path.

## Current boundaries

- Mutual funds have the portfolio ledger, valuation, NAV and redemption workflows.
- Stocks and ETFs can be placed on the watchlist, but the investment ledger and valuation pipeline do not yet support them.
- Market prices and scenario outputs are not forecasts. NAV freshness refers to the observation date, which may precede its retrieval date because of weekends or holidays.
- Tax estimates are deliberately incomplete when policy or personal assumptions are missing. The redemption service does not hard-code tax rates.
- Creating the metadata in a new org does not populate the user's investment data. Data migration, source integrations, permissions, scheduled jobs, and optional AWS CAS infrastructure are separate setup steps.

## Repository map

| Path | Responsibility |
|---|---|
| [`force-app/main/default/classes/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/force-app/main/default/classes) | Apex engines, APIs, workflow services and Apex tests |
| [`force-app/main/default/lwc/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/force-app/main/default/lwc) | Portfolio, fund, holding, plan, redemption, import and watchlist UI |
| [`force-app/main/default/objects/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/force-app/main/default/objects) | Custom object, field, validation, layout, list and compact-layout metadata |
| [`force-app/main/default/flows/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/force-app/main/default/flows) | Standard Screen Flows and actions |
| [`force-app/main/default/reports/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/force-app/main/default/reports) and `dashboards/` | Standard Salesforce analytics |
| [`tools/portfolio/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/tools/portfolio) | Operational schema, reporting, page, Flow, package and runtime utilities |
| [`tools/investment-migration/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/tools/investment-migration) | Source mapping, protected export preparation, loading and reconciliation |
| [`manifest/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/manifest) | Generated and scoped Metadata API package manifests |

## Change workflow

1. Trace the current feature through this guide to its source files and the object fields it reads or writes.
2. Update Apex, metadata, tests and generators together when a schema or behavior change requires them. Avoid editing generated metadata alone if a generator will overwrite it.
3. Regenerate the release metadata and inspect the complete Git diff before deploying.
4. Rehearse in a sandbox using representative and incomplete data; then validate and promote a reviewed package.
5. Configure org-specific endpoints, credentials, users, permissions and schedules separately. Never commit credentials, private exports or customer statements.

The exact release path is in [Deploy to a new org](./deploy-to-new-org.md); operational and data validation steps are in [Operations and testing](./operations-and-testing.md).
