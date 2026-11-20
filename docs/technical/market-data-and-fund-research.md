---
title: Market data and fund research
description: Mutual-fund NAV refresh, benchmark observations, performance metrics, peer comparisons, and exposure.
---

# Market data and fund research

The current market-data pipeline refreshes tracked mutual-fund NAVs and supported benchmark indexes. It does not refresh listed-stock or ETF prices; those instruments are watchlist-only in this release.

## NAV refresh path

`InvDailyRefresh` selects tracked instruments with verified scheme identity. It enqueues `InvNAVRefresh`, which processes funds in bounded batches (up to 10 at a time), fetches:

- MFapi: `callout:Inv_MFapi/mf/{AMFI code}/latest`
- AMFI: `callout:Inv_AMFI/spages/NAVAll.txt`

The code validates the scheme code, mapped ISIN and Direct Growth plan/option identity before accepting MFapi output. AMFI validates its scheme row and share-class identity. Both require a positive NAV dated no later than today. MFapi's `/latest` endpoint is used for daily ingest; this job does not retrieve complete historical series on every run.

Observations are idempotent by provider, instrument, date and normalized value hash. The system retains provider, retrieval time, revision and source payload. If providers disagree for the same mapped fund and date, it creates a Data Issue and selects AMFI as the official value. A provider failure is recorded as an issue; previously accepted observations remain available.

The shared [`InvNAVPolicy`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvNAVPolicy.cls) chooses the latest accepted observation at or before a valuation date, respecting the run's knowledge cutoff. It is shared by valuation, research and plan calculations so they agree about which NAV was selected.

## Scheduled jobs and continuation

[`scripts/apex/portfolio-schedule.apex`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/scripts/apex/portfolio-schedule.apex) installs three schedules named `Investments NAV 09 IST`, `Investments NAV Retry 10 IST` and `Investments NAV Retry 12 IST`. The script requires the running user timezone to be `Asia/Kolkata`; it aborts and replaces only jobs with those exact names. Retry mode targets tracked funds without an accepted attempt today. Benchmark refresh is chained after the NAV work, followed by recalculation.

The schedule is not enabled simply by deploying Apex or the Investments app. See [Deploy to a new org](./deploy-to-new-org.md) for prerequisites and installation. Do not infer that a schedule exists in an org from the presence of the script; check that org's Scheduled Jobs and `CronTrigger` state.

## Benchmarks and fund metrics

- `InvBenchmarkRefresh` fetches supported official index TRI series through the configured BSE/NSE named credentials, preserves date/revision evidence and queues recalculation.
- `InvBenchmarkEngine` compares a fund only with its explicitly assigned, dated benchmark variant. It uses common observation dates; unsupported or missing periods remain unavailable.
- `InvFundMetrics` calculates supported trailing periods, CAGR where the history allows it, monthly-sampled one- and three-year rolling return distributions, annualized monthly volatility, maximum drawdown and recovery, plus common-period benchmark comparisons.
- Each stored metric includes its run/version and period/coverage context. It is a dated analytical result, not a live formula.

## Fund research and peer selection

`InvResearchService.getFundResearch(fundId)` provides the selected fund's identity, latest accepted NAV, expense observations, personal positions, fund metrics, NAV time series, composition, and active peer assignments. `invFundResearch` presents Summary, Performance, Similar Funds, Composition and My Investment views.

Peer assignments are explicit and dated (`Inv_FundPeerAssignments__c`). Comparisons must preserve equivalent share-class rules and common periods. The UI should show sample counts and data coverage. It must not imply a category rank or percentile unless the measured peer universe supports that statistic. NAV return and the investor's cash-flow return are separate measures.

## Composition and underlying exposure

`InvExposureEngine` selects dated fund composition disclosures, resolves verified security identities through canonical security references, then aggregates exposure by security, sector, market capitalization and asset class. It keeps original source labels for audit, preserves cash, negative values and unknown identities, and reports disclosure date and coverage. It does not normalize incomplete composition weights to 100%.

Overlap is meaningful only when fund disclosures are compatible in date and mapping. The UI should label partial mapped coverage and exclude incompatible disclosures from a numeric overlap instead of presenting a spurious precision.

## Data mapping and diagnostics

Before tracking a fund, verify its share class and scheme code/ISIN in the fund record, then enable tracking. Check Data Issues after refresh for failed calls, identity mismatches and same-date provider discrepancies. Do not manually “fix” historical NAV by overwriting a value; corrections should be represented as traceable observations/revisions and selected by the shared policy.

For fund-page wiring, see [Lightning experience and access](./lightning-experience-and-access.md). For generated reports and release manifests, see [Deploy to a new org](./deploy-to-new-org.md).
