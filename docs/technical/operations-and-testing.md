---
title: Operations and testing
description: Test suites, async pipeline status, troubleshooting, safe releases, and post-deployment checks.
---

# Operations and testing

This page describes how to verify behavior after code changes and how to diagnose a stale or incomplete portfolio view. Run checks in a sandbox before any production promotion.

## Test areas in source

| Area | Representative test classes/tools |
|---|---|
| Exact decimal handling, FIFO and XIRR | `InvMathTest` |
| Portfolio units, snapshots, reversal cutoffs and valuation | `InvPortfolioEngineTest` |
| NAV/benchmark parsing, identity checks, retries and refresh stages | `InvRefreshTest`, `InvBenchmarkRefreshTest` |
| Research facade, run scoping, permissions and movement | `InvResearchServicesTest`, `InvestmentAccessTest` |
| Plan guards, baseline evaluation and plan service | `InvPlanGuardTest`, `InvPlanServiceTest` |
| Redemption preview and eligibility | `InvRedemptionService` currently has no dedicated Apex test class in the repository; add one before changing the service contract or relying on coverage for production acceptance. |
| CAS staging and duplicate/confirmation behavior | `InvCASTest`; Python checks in `tools/portfolio/cas/test_normalise.py` and `test_worker.py` |
| Migration preparation and integrity | `tools/investment-migration/test_migration.py` |

Run Salesforce Apex tests against a sandbox and keep reports with the release evidence. For example:

```bash
sf apex run test --target-org investment-sandbox --test-level RunLocalTests --wait 60 --code-coverage
```

For parser changes, run Python tests from the repo root after installing `tools/portfolio/cas/requirements.txt` in an isolated environment. Never use a personal CAS PDF in a test checked into Git. Test live integrations only with explicit org authorization and target mappings; mocks are preferred in Apex tests.

## Async pipeline stages

The refresh sequence runs independently observable work for NAV, benchmark, fund metrics, portfolio valuation and exposure. The `Inv_AnalyticsRuns__c` pipeline state and the instrument NAV attempt status distinguish success, failure and not-yet-completed stages. A stage finishing does not imply that other stages are fresh.

If a refresh fails:

1. Open Data Issues and inspect the issue message, provider, affected instruments and observed dates.
2. Compare the last successful run and the current pipeline's stage status. Keep using the last published successful valuation while the new run is incomplete.
3. Verify the fund identity mapping, `Tracked__c`, Named Credential availability, provider response/status and Salesforce async job state.
4. Retry transient provider failures through the scheduled retry or supported controlled refresh path; do not delete accepted historical observations.
5. Reconcile counts, source dates and report output after a successful recalculation.

For stale NAV, compare the NAV's observation date with retrieval date and the fund's market calendar. Weekends and holidays can make a successful retrieval return an earlier observation.

## Deployment operational safety

- Check scheduled jobs and in-flight Queueable/Apex jobs before deploying changes to active scheduled classes. Replacing Apex while the same class has pending jobs may require waiting, draining or a reviewed temporary deployment procedure.
- `scripts/apex/portfolio-unschedule.apex` cancels the named NAV schedules and queued fund-metrics continuations. It is intentionally not a generic deploy hook; review current job IDs and operational impact before running it.
- `scripts/apex/portfolio-schedule.apex` replaces only the three known NAV schedule names and requires an `Asia/Kolkata` user timezone. Confirm one schedule owner and verify all three CronTrigger entries after installation.
- Never run migration, parser production staging, bulk posting or owner-activation utilities as an incidental deployment step. Those scripts can create or modify real org records, users, external applications or AWS resources.

## Evidence to keep for a release

- Git commit hash and generator output / manifest component count.
- Deployment validation/job IDs and test results.
- Sandbox manual scenarios and unresolved limitations.
- Named Credential, permission-set and schedule verification (record names/status only; no secrets).
- First-run data health issues and reconciled counts, stored in protected operational records rather than the public repository.

## Red flags

- A successful NAV call is not proof that the portfolio run published successfully.
- A published valuation is not proof that XIRR, tax, FIFO basis or fund composition is complete; inspect coverage per category.
- The Portfolio Overview market value series is not an investment performance return series.
- Approval freezes a plan version; it does not execute a redemption, buy or SIP change.
- A new Salesforce org starts without the legacy records. Run the separate approved migration and reconcile the resulting data before treating the portfolio as complete.
