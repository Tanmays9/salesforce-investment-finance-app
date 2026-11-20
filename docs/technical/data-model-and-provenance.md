---
title: Data model and provenance
description: Investment record grains, relationships, identifiers, exact values, and source evidence.
---

# Data model and provenance

The investment model separates market reference data, account activity, observed prices, analytical outputs, plans, and import evidence. The canonical object and field definitions are generated from [`tools/portfolio/model.json`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/tools/portfolio/model.json), the preserved-schema mapping in [`tools/investment-migration/mapping.json`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/tools/investment-migration/mapping.json), and object metadata under `force-app/main/default/objects/`.

## Relationship map

**Core links:** Portfolio → accounts → unit entries → events and instruments. Instruments link to scheme/share-class references, price observations and composition disclosures. An analysis run publishes portfolio and holding valuations, exposure and fund metrics. A plan contains versions, which contain actions, targets, dependencies and impacts. An import run contains staged rows; confirmed events link to source-document evidence.

Names in the diagram are conceptual groupings; actual API names use the `Inv_` prefix and `__c` suffix.

## Main record groups

| Domain | Representative Salesforce records | Grain and purpose |
|---|---|---|
| Portfolio reference | `Inv_PortfolioPortfolios__c`, `Inv_PortfolioAccounts__c` | Investor-owned portfolio and account boundaries. Accounts distinguish holding/cost basis and verified CAS scope. |
| Market identity | `Inv_MarketInstruments__c`, `Inv_MarketFundShareClasses__c`, scheme versions, AMCs and benchmark assignments | Instrument identity, scheme/plan/option mapping, effective category and benchmark evidence. NAV mappings must be explicitly verified. |
| Market observations | `Inv_MarketPriceObservations__c`, composition snapshots and constituent records | Provider-specific, dated prices and fund disclosures. Preserve observed date, retrieval date, revision, provider and source evidence. |
| Ledger | `Inv_PortfolioEvents__c`, `Inv_PortfolioUnitEntries__c`, event charges and position snapshots | Posted source events and their account/instrument unit or cash movements. A statement snapshot reconciles a balance; it is not an extra transaction. |
| Contributions | SIP versions and evidence | Account/fund contribution amount with effective dates and verification. Current SIPs are independent of whether the fund currently has units. |
| Analysis | `Inv_AnalyticsRuns__c`, `Inv_AnalyticsResults__c`, `Inv_Holding__c`, `Inv_HoldingValuation__c`, `Inv_PortfolioValuation__c`, `Inv_Exposure__c`, `Inv_FundMetric__c` | Versioned run metadata, compatibility results, current holding projections and immutable dated valuations/metrics/exposure. |
| Planning | Plans, plan versions, actions, targets, action dependencies, `Inv_PlanImpact__c` | User-entered alternative actions, evaluation outputs, rationale and comparison against one published baseline. |
| Redemption | `Inv_RedemptionEstimates__c`, `Inv_RedemptionLotAllocations__c` and policy records | Evidence-backed eligibility/load inputs and estimated proceeds/lots; outputs remain estimates with explicit missing coverage. |
| Import and provenance | `Inv_OpsImportRuns__c`, `Inv_OpsImportRows__c`, `Inv_OpsSourceDocuments__c`, providers, data issues and change/audit records | File identity, parser status, staged rows, source hashes, evidence links and data-quality exceptions. |
| Watchlist | `Inv_WatchlistItems__c` | Tracked investment ideas. It is deliberately separate from the portfolio ledger. |

For the full current inventory, inspect the object directories rather than relying on a hard-coded count in this guide. The source data model has evolved; a fresh count should be generated from the checked-in object metadata for a release.

## Stable keys and relationships

- Operationally generated records use `MigrationKey__c` or the model's `Key__c` external-ID field. Generator definitions mark keys unique where supported.
- Legacy records retain original source identities and migration run evidence. Do not replace stable source keys with Salesforce record IDs.
- Relationship fields are lookups with restricted deletion behavior for financial history. Preserve the source relationship and keep records even when a reference is unavailable; report the mapping issue rather than fabricating a link.
- CAS events use canonical economic identity plus an occurrence counter to distinguish legitimate identical purchases. Statement row positions are locators, not permanent transaction identity.
- Source files are linked as Salesforce Files through `ContentDocumentLink`; file hashes prevent duplicate document evidence.

## Exact amounts and display projections

Source financial values are preserved as decimal text in JSON/exact-value fields where necessary. `InvMath` parses exact values and only writes a numeric Salesforce projection when the value fits the field's precision without loss. This makes Salesforce reports convenient while preserving original numeric evidence. A blank typed projection can mean “cannot represent safely,” not zero.

Currency display fields format the INR numeric projection to two decimal places; calculation precision and unit/NAV precision remain separate. Never use a rounded display formula as an input to ledger calculations.

## Analysis run contract

An analysis run identifies its portfolio, valuation date, ledger and knowledge cutoffs, calculation version, input fingerprint, stage statuses, coverage and failures. The portfolio's published-run pointer changes only after the valuation pipeline completes successfully. Consumers should read the immutable valuation rows linked to that run instead of joining live current holdings to an older run.

Run-scoped outputs include:

- Per-account/instrument holding valuations and portfolio totals.
- NAV and transaction reconciliation dates.
- Unit, acquisition-basis, redemption, personal-return, NAV, composition and policy coverage.
- Fund performance and compatible benchmark comparisons.
- Underlying exposure and its disclosure dates/coverage.
- Fingerprints for deterministic plan evaluation and rebase checks.

## Adding a field or entity

1. Identify source identity, record grain, parent relationship, deletion behavior and whether the value is raw evidence or a derived snapshot.
2. Update `model.json`, source mapping or relevant generator rather than only editing a generated object file.
3. Add permission fields, layouts, list views, reports and tests as needed; update the release manifest by running the package generator.
4. Preserve precision, nulls, source, original date and explicit coverage. Do not backfill missing values with zero.
5. Document migration/backfill behavior separately from deploying metadata. The org data is not stored in Git.
