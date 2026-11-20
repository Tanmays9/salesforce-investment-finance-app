---
title: Deploy to a new production org
description: Prepare, rehearse, validate, deploy, configure, and verify the Investments app in a new Salesforce org.
---

# Deploy to a new production org

This is a release procedure for deploying the checked-in Salesforce investment application to a **new** production org. It does not move legacy portfolio records and does not configure external services automatically. Rehearse all steps in a sandbox of the target org first.

> **Target safety:** use named CLI aliases, verify the Salesforce Organization ID and `IsSandbox` before every deploy, and keep org authentication local. Never paste access tokens, private keys, passwords or production data into the repository.

## What this deploy includes

The release package contains the model and operational overlays, Apex classes, Lightning components/resources, Flows/actions, Investments app/pages, reports/dashboard, permission sets, public-data Named Credential metadata and generated manifests. `tools/portfolio/package.py` generates a dependency-complete `manifest/portfolio-release.xml` from `build.py`, `reporting.py`, `pages.py`, and `flows.py`.

The release package does **not** include portfolio data, legacy migration exports, source statement PDFs, org-specific credentials, user assignments, refresh schedules, deployed AWS CAS resources or external provider agreements. A blank org can show the UI before it contains any investment records.

## Automated releases through GitHub Actions

The [`Salesforce deployment` workflow](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/.github/workflows/salesforce-deploy.yml) deploys committed release metadata using the dependency-complete `manifest/portfolio-release.xml` and runs `RunLocalTests`.

- A metadata change pushed to `main` deploys to the configured sandbox.
- A manual run from `main` with target `sandbox` deploys only to the sandbox.
- A manual run from `main` with target `production` first deploys and tests that same commit in the sandbox, then validates the manifest in production with `RunLocalTests` and quick-deploys that exact validation. Configure the `salesforce-production` environment with a required reviewer so GitHub pauses before production authentication and deployment.

The GitHub environments `salesforce-sandbox` and `salesforce-production` are already configured for `main`. Their expected organization IDs and sandbox flags are set as non-secret environment variables, and production requires approval from the repository owner. Before the first run, add the following environment secrets:

| Environment | Secret | Value |
|---|---|---|
| `salesforce-sandbox` | `SF_AUTH_URL` | SFDX authorization URL for the sandbox integration user |
| `salesforce-production` | `SF_AUTH_URL` | SFDX authorization URL for the production integration user |

The workflow compares both the authenticated Organization ID and `IsSandbox` value before deployment. Use dedicated, least-privilege integration users for automation and revoke their Salesforce CLI authorization when rotating credentials. Keep auth URLs only in GitHub environment secrets; never add them to source files or workflow logs.

The pipeline does not pause scheduled jobs or change Salesforce deployment-bypass settings. If active Apex jobs block a release, follow the [deployment safety procedure](./operations-and-testing.md#deployment-operational-safety), then rerun the workflow.

The CLI version and GitHub Actions are pinned in the workflow. A successful pipeline records Salesforce validation and deployment IDs in the GitHub Actions run summary. This automated release covers Salesforce metadata; it does not load investment records, install schedules, configure provider credentials, deploy the optional CAS parser, or replace the new-org acceptance checklist below.

## 1. Prepare the new org and local environment

1. Confirm the target org edition, API access, metadata deployment permissions, Apex test readiness, custom-object/field limits, storage, integration constraints, and any existing metadata conflicts. Record its Organization ID and whether it is production.
   The repo targets Metadata API `68.0` in `sfdx-project.json`; confirm that the target org supports the package's API version before deploying.
2. Create a sandbox belonging to the target production org. Use it for deployment rehearsal and data/integration tests.
3. Install Salesforce CLI and authenticate each target using explicit aliases. Production login:

   ```bash
   sf org login web --alias investment-production --instance-url https://login.salesforce.com
   ```

   Sandbox login:

   ```bash
   sf org login web --alias investment-sandbox --instance-url https://test.salesforce.com
   ```

   Authenticate through the browser, then inspect the org with `sf org display --target-org <alias>` and query `SELECT Id, Name, IsSandbox FROM Organization`. Do not rely on the CLI's default org.
4. Copy `.env.example` to the local protected path `%LOCALAPPDATA%\SalesforceInvestmentFinanceApp\.env` or set `SALESFORCE_PORTFOLIO_ENV_FILE`. Fill the new production/sandbox org IDs and aliases and the required private artifact root. Keep it outside Git and synced folders. `tools/investment-migration/org_config.py` reads this configuration for stage-specific tools; the ordinary Salesforce CLI deploy itself uses the explicit `--target-org`.
5. Review whether the target is truly the intended **new** org. If it already has metadata, retrieve/back up overlapping components and resolve name/ownership conflicts before deploying; a source deploy overwrites matching components.

## 2. Generate a clean release package

Run from the repository root with a supported Python environment:

```bash
python tools/portfolio/package.py
git status --short
git diff --stat
git diff -- manifest force-app tools/portfolio/model.json
```

The package generator calls the model, reporting, page and Flow generators, then rebuilds the release manifest. Generators write deterministic metadata under `force-app/`, `manifest/` and `tools/portfolio/model.json`; inspect and commit the intended output before deployment. Do not run only one generator for a new-org release if the model/report/page/Flow dependencies have changed.

Important manifests:

- `manifest/portfolio-release.xml`: dependency-complete generated release package for the portfolio app.
- `manifest/portfolio-implementation.xml`: a deliberately narrower current implementation/rehearsal package; scheduled continuation classes are excluded because replacing them while their jobs are active is unsafe. It is not the full new-org package.
- `manifest/portfolio.xml`, `portfolio-pages.xml`, `portfolio-reporting.xml`, `portfolio-flows.xml`: generated package slices for diagnostics or narrower releases.

## 3. Rehearse in the new org's sandbox

Deploy the generated package to the sandbox and run local Apex tests:

```bash
sf project deploy start --manifest manifest/portfolio-release.xml --target-org investment-sandbox --test-level RunLocalTests --wait 60
sf apex run test --target-org investment-sandbox --test-level RunLocalTests --wait 60 --code-coverage
```

Then complete the manual release checklist:

- Open the Investments app; verify navigation, Overview empty state, list views, fund/holding pages and related lists.
- Create representative synthetic fund/instrument/reference records and check fund identity, mapping, verified tracking and permission behavior.
- Exercise read-only viewer versus manager access; verify the parser permission cannot confirm or post transactions.
- Run a controlled portfolio recalculation. Check the published run, holdings, reconciliation dates, currency formatting and coverage flags.
- Verify MFapi/AMFI and index credentials/endpoints only after configuring them in this sandbox. Confirm provider discrepancies surface in Data Issues.
- Test a draft plan, baseline fingerprint rejection/rebase, plan comparison, redemption preview with locked/unknown lots and approval readiness.
- Test CAS parsing and duplicate review with representative authorized statements under protected storage. Confirm no posting occurs before a reviewed account confirmation.
- Check mobile/desktop layout, charts and table equivalents; verify all failures/loading/empty states.

Resolve validation and manual failures before production. Preserve the sandbox deployment/test run IDs and review signed-off component scope.

## 4. Validate and deploy production

After the sandbox rehearsal and code review, authenticate the production alias, re-check its ID and `IsSandbox=false`, and perform a validate-only deployment with Apex local tests:

```bash
sf project deploy validate --manifest manifest/portfolio-release.xml --target-org investment-production --test-level RunLocalTests --wait 60
```

Record the successful validation job ID. Then use Salesforce's quick-deploy path for that exact successful validation:

```bash
sf project deploy quick --job-id <validation-job-id> --target-org investment-production --wait 60
```

Do not run `deploy quick` from an unrelated or expired validation. If validation fails, fix the source, regenerate the package, repeat the sandbox rehearsal as required, and validate again. A Metadata API source deployment overwrites corresponding component definitions; it does not merge administrator changes automatically. See Salesforce CLI references for [`sf project deploy validate`](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_validate.html), [`sf project deploy quick`](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_project_deploy_quick.html) and [production test levels](https://developer.salesforce.com/docs/platform/salesforce-cli-reference/guide/cli_reference_apex_run_test.html).

## 5. Configure org-specific services and access

Do these only after successful deployment and with an org administrator:

1. Review generated Named Credentials. Configure and exercise the MFapi and AMFI endpoints and the supported BSE/NSE TRI endpoints. This repo's public feeds do not require credentials, but the Salesforce Named Credential setup and allowed endpoints still must be verified in the new org.
2. Seed/verify market identity: AMC/scheme/share-class records, direct-growth code/ISIN mappings, benchmarks and benchmark return variants, category/peer assignments, expense, composition and dated policy evidence. Do not enable tracking on an ambiguous share class.
3. Assign `Inv_Viewer` to intended read-only users. Assign `Inv_PortfolioManager` only to operators who should draft/approve plans, maintain selected tracking/peer records and confirm reviewed imports. `Inv_Parser` and `Inv_MigrationAdmin` are restricted integration/migration access; do not assign them broadly.
4. Load or migrate records through the separate approved data migration. Run import preflight and reconciliation before using the application for decisions. Metadata deployment alone creates no holdings.
5. Confirm that tracked funds and price-history coverage are ready, then install the daily refresh schedules. Run [`scripts/apex/portfolio-schedule.apex`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/scripts/apex/portfolio-schedule.apex) as an org user whose timezone is `Asia/Kolkata`:

   ```bash
   sf apex run --file scripts/apex/portfolio-schedule.apex --target-org investment-production
   ```

   This creates 9:00 AM NAV refresh plus 10:00 AM and 12:00 PM retry schedules in that user's timezone. It aborts/replaces jobs with these exact app schedule names; inspect scheduled jobs first. Deployment alone does not install them.
6. Run an initial controlled refresh/recalculation, verify NAV date separately from retrieval time, confirm the new run publishes successfully, and review any Data Issues before trusting the dashboard.

## 6. Optional CAS parser deployment

CAS parsing is a separate AWS release and requires AWS account/region access, Docker, ECR/Lambda/API Gateway/Secrets Manager/SQS permissions, and a protected stage configuration. Follow [CAS import](./cas-import.md) and inspect `tools/portfolio/cas/auth.py`, `deploy.py` and `infrastructure.py` before provisioning. These scripts can create an integration user/OAuth configuration, AWS resources and short-lived secrets. Rehearse with the sandbox target and isolated AWS stage first; never use production files/passwords as test fixtures.

The parser deployment script requires explicit `--stage sandbox|production` and `--target-org <alias>` and checks that the org ID matches the protected local stage configuration. Keep generated certificates, OAuth identity artifacts, secret material, parser PDFs and job reports outside Git. Do not deploy parser infrastructure as an automatic side effect of the Salesforce package release.

## 7. Data migration is a separate release

For a new org with existing investment history, run [`tools/investment-migration/README.md`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/tools/investment-migration/README.md). That process exports and fingerprints sources, maps and resolves conflicts, rehearses a resumable load, links files, and reconciles records/relationships/hashes. Use a fresh approved dataset and target identity. Keep source systems and backups until separately approved retirement; do not use metadata deployment as a shortcut for historical record loading.

## 8. Production acceptance and rollback evidence

Accept the release only when the deployment and tests passed, app navigation/records are accessible to intended users, production integrations and schedules are verified, a successful dated valuation is published, data-health issues are understood, and migration reconciliation is separately signed off if applicable. Save the validation/job IDs, package commit, test reports, stage checks and recovery plan in the protected release record.

For a metadata rollback, prepare a reviewed inverse package or restore the prior component versions from source control/retrieval. For data rollback, use the migration run's explicit created/updated manifest and before-images; never bulk-delete all investment records. Preserve scheduled jobs and prior published valuation while diagnosing refresh failures.
