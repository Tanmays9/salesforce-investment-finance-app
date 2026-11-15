# Salesforce investment portfolio operations

The Investments Lightning app supports portfolio review, fund research, plan comparison, statement review and data-health follow-up. The financial model keeps source records and calculation results separate: daily valuations are dated snapshots, and missing evidence stays visibly incomplete.

## Environments and deployment

- Production: `LOCAL_SALESFORCE_PRODUCTION_ORG_ALIAS` (`LOCAL_SALESFORCE_PRODUCTION_ORG_ID`), verified as a non-sandbox org.
- Rehearsal sandbox: `LOCAL_SALESFORCE_SANDBOX_ORG_ALIAS` (`LOCAL_SALESFORCE_SANDBOX_ORG_ID`).
- Salesforce API version: 68.0.
- Repository: source metadata and operational tooling live here. Private exports, parser evidence, deployment reports and credentials belong under `LOCAL_PRIVATE_DATA_ROOT`, outside Git and OneDrive.

On 2026-11-14 the operational release was deployed to production after sandbox rehearsal. The latest metadata deployment completed with 26 passing Apex tests and no component errors. It includes operational holdings and dated valuation/metric records, standard report and dashboard metadata, record pages and plan flows, NAV and official Nifty/BSE TRI refresh, and the CAS review pipeline. The parser stack is deployed in AWS `LOCAL_AWS_REGION`; its credentials and private evidence remain outside this repository.

For reproducible metadata changes, run `python tools/portfolio/build.py`, then `reporting.py`, then `pages.py`, and deploy the scoped manifests in that order. The migration schema generator must invoke the operational overlays after regenerating preserved metadata. Operational fields are described in `model.json`; the source mapping remains in `tools/investment-migration/mapping.json`. Never replay the historical cutover loader to deploy operational changes.

## Verified production state (2026-11-14)

- The production app has a published valuation and current position coverage. Exact position names, account scopes, valuation values and raw statement evidence remain in the private Salesforce org and protected run artifacts; they are intentionally omitted from this repository.
- Latest NAV refresh was accepted for all ten tracked funds on 2026-11-14, using NAVs dated 2026-11-13. MFapi observations were fetched and retained; where the same-date values agreed with AMFI, AMFI is the selected official observation. Valuation totals are mutual-fund-only and use the latest available NAV dates.
- Portfolio XIRR remains unavailable until external contribution cash history is confirmed. Realized-gain, redemption-policy and tax coverage remains incomplete where gross proceeds or dated policies are missing.
- Primary benchmark assignments are recorded only where dated official evidence is available. The BSE 500 feed uses the official code 17 history endpoint and its `TRValue` field; `PRValue` is not treated as total return. Identical observations are skipped on repeat imports, and same-date source corrections remain linked revisions. Foreign-currency benchmarks remain unavailable until compatible currency-adjusted total-return history is validated.
- Daily NAV refresh and retry jobs run in `Asia/Kolkata`; retry windows also refresh benchmark data when NAV refresh has succeeded. A refresh date is not itself a NAV date, so screens must display the NAV's actual observation date.
- The production CAS statement import completed with duplicate rows classified as existing ledger events. No transaction was posted twice. Reconciliation snapshots and the source-document link are retained; source-file evidence remains under the protected run artifacts.

## Application use

Open the [Investments app](https://REDACTED_SALESFORCE_DOMAIN/lightning/app/Investments) in the authenticated production Salesforce session. Main navigation is Overview, Portfolios, Holdings, Watchlist, Funds, SIPs, Plans, Imports, Data Health, Reports and Dashboards. Fund pages reuse standard Salesforce report charts with record-context filters rather than maintaining separate chart definitions for each fund.

On 2026-11-14, the production browser review verified the Overview, holdings list and a fund record page. Monetary display fields use INR locale formatting with two decimal places; source calculation numbers and exact source text remain unchanged. The Overview watchlist uses the existing Active list view and the standard Salesforce New record form; watchlist entries are informational and do not create holdings or trades. Stock and ETF quote refresh is not implemented. The Overview charts group on the reportable `FundDisplayName__c` formula instead of the fund lookup's generated record key, so Allocation by fund, Monthly SIP allocation and unrealized gains show fund names. Holdings reports, list views and the holding layout use the same label. Native Salesforce charts may shorten long labels to fit their axes; the linked report retains the full names.

Use published portfolio/holding valuations for current views. Use Plans to draft and compare versioned scenarios against the published baseline; draft scenarios do not change actual holdings. Imports stage rows for deduplication and reconciliation before any confirmation. Keep parser import status separate from transaction posting status.

## Daily NAV and calculation operations

The scheduled flow fetches NAV observations for held/tracked funds, validates fund identity, date and positive NAV, records provider evidence, then starts calculation work. It refreshes official Nifty and BSE benchmark TRI history during the retry windows when NAV refreshes have succeeded. The BSE 500 backfill and recurring feed use BSE Indices' official [index page and series](https://www.bseindices.com/indices-details/code/17/). AMFI is used to verify or resolve same-date NAV provider disagreements; identical observations are idempotent and corrections remain traceable. If providers fail, the last valid observation stays available with its older NAV date.

To restore the official BSE 500 benchmark history in either authorized org, run `python tools/portfolio/benchmark_bootstrap.py --target-org <alias>` followed by `python tools/portfolio/benchmark_bse_backfill.py --target-org <alias>`. The backfill validates the index identity, exact values, source hashes and Salesforce read-back before reporting success. The importer is idempotent and stores its verification artifacts outside the repository.

For manual recovery, review Data Health and failed refresh records before resubmitting. Retry jobs skip funds already refreshed successfully for the same date. A failed analysis run must not replace the previous published pointer. Never treat a missing value or missing cost basis as zero.

For metadata and migration procedures, use `tools/investment-migration/README.md` and protected run artifacts. Do not print authentication tokens, certificates, source PDFs, parsed account identifiers or secret-bearing CLI output.

## Current follow-up

1. Review the confirmed CAS reconciliation and the 15 closing-position snapshots in the Investments app.
2. Review benchmark coverage and dated evidence for older benchmark-assignment periods. Keep Franklin's USD benchmark unavailable until a suitable currency-adjusted total-return series is validated. Add dated expense, redemption and tax-policy evidence as needed.
3. Import dated expense-ratio and redemption-policy evidence to improve exit-load, tax and realized-gain coverage.
4. Reconcile closed holdings with missing gross proceeds and incomplete realized-gain coverage. Resolve statement-versus-NAV discrepancies against the source evidence, and keep ledger values unchanged until the evidence supports a correction. Complete external cash history before relying on portfolio XIRR.
5. Preserve Twenty, Neon and their backups until migration retirement is separately decided.

## Calculation and data-safety contracts

- Posted ledger movements determine units; closing-balance snapshots reconcile but are not reposted. Reversals invalidate their referenced events. FIFO matching is isolated by account and instrument.
- Valuation uses remaining units and the selected valid NAV on or before the valuation date. Personal fund XIRR uses recorded cost and redemption cash flows; portfolio XIRR requires confirmed external cash flows. Internal switches are not external contributions.
- Each analysis records its valuation date, knowledge and ledger cutoffs, algorithm version, input fingerprint and coverage. Only completed runs are published. Historical migrated analytics remain labeled snapshots.
- Holdings are operational projections; dated valuation, exposure and metric runs are evidence. Repeated calculations for one date do not create duplicate historical points.
- Source decimal text and provenance remain preserved. Unsupported precision is not silently rounded. NAV corrections, cash/negative constituents, unknown identities and incomplete composition coverage remain traceable and are not normalized away.
- CAS matching uses file hashes, stable provider/account-scoped references and occurrence-aware transaction matching. Parser row numbers and page numbers are evidence locators, not economic identities. Existing matches add evidence without creating another ledger event; conflicts require review.
- Draft plans never alter actual holdings. Incomplete eligibility, policy or tax coverage cannot imply that a redemption is executable.

## Local implementation status (2026-11-15)

The current working tree adds reusable portfolio, fund and holding research pages; selectable allocation views and category/AMC filters; dated portfolio movement attribution; draft-plan generation and comparison; FIFO redemption review; a shared NAV selection policy; bounded research refresh stages; and reportable coverage, peer and redemption records. Plan comparisons now use immutable valuation snapshots and require matching baseline fingerprints. Cash from a planned redemption is unavailable to purchases or spending until an eligible redemption estimate records the settlement date and verified exit-load coverage; the configured calendar-day hold is applied after settlement. A full-redemption action remains scoped to its plan and account selection, and realized gain is shown separately from exit load. Movement attribution separates market movement on opening units, recorded unit flows, snapshot/ledger adjustment and any residual; incomplete rows remain labeled.

These changes are local source only. They have not been deployed to the sandbox or production. Local generators, Python syntax, JavaScript syntax, XML parsing and whitespace checks are the available checks; Apex compilation, Apex tests, Lightning runtime checks and end-to-end Salesforce acceptance remain pending in `LOCAL_SALESFORCE_SANDBOX_ORG_ALIAS`. The Salesforce CLI authorizations were left untouched while the sandbox session is unavailable; no Salesforce records, metadata, schedules or AWS resources were changed by this local implementation.
