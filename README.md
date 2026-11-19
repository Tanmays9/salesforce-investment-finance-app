# Salesforce Investment Portfolio Manager

A Salesforce Lightning application for reviewing a mutual-fund portfolio, researching individual funds, and comparing consolidation and redemption scenarios. The project is built as a Salesforce DX source repository with Apex services, Lightning Web Components, custom objects, reports, and Screen Flows.

## Capabilities

- **Portfolio overview:** holdings, allocation, valuations, contribution activity, SIPs, freshness, and data-quality signals in one research workspace.
- **Holding and fund research:** fund performance and NAV history, benchmark context, peer comparisons, expenses, disclosed composition, exposure, and account-level position details.
- **Portfolio calculations:** position valuations, ledger reconciliation, cost basis and FIFO lots, cash-flow returns, benchmark metrics, and exposure analysis with dated analysis runs.
- **NAV ingestion:** MFapi and AMFI integrations with verified scheme mapping, observation provenance, and AMFI preference when same-scheme, same-date values disagree.
- **Statement import:** CAS import staging, file fingerprinting, duplicate review, account reconciliation, and explicit confirmation before ledger updates.
- **Planning and redemptions:** versioned plans, scenario comparison, SIP changes, redemption previews, eligibility and exit-load checks, and evidence-linked readiness.
- **Watchlist:** a home-page watchlist for funds, stocks, and ETFs.

## Technical design

- **Apex** implements financial calculations, ingestion, reconciliation, access checks, and plan workflows.
- **Lightning Web Components** provide the portfolio research, fund research, holding detail, plan comparison, redemption review, statement import, and watchlist interfaces.
- **Screen Flows** guide plan creation and approval, statement import and confirmation, and fund tracking.
- **Salesforce records and reports** hold the investment model, dated observations, analysis snapshots, plans, import evidence, and operational issues.

The calculation and research views preserve valuation dates, source coverage, and provenance. Scenario values use a chosen baseline and are estimates; they are not forecasts or broker instructions.

## Integrations and configuration

The source includes Named Credential metadata for MFapi, AMFI, BSE indices, and NSE indices. Configure and verify these connections in the target Salesforce org before enabling refresh jobs. Integration credentials and org-specific settings belong in Salesforce Setup or the deployment environment, not in Git.

Portfolio-changing operations are permission-gated. Assign the portfolio manager permissions only to intended users and validate access in a sandbox before production use.

## Current scope

The investment ledger and valuation workflows focus on mutual funds. Stocks and ETFs can be added to the watchlist; their full portfolio accounting and valuation are outside the current scope. The application supports research and planning, not trade execution.

## Repository layout

- `force-app/main/default/classes/` — Apex calculation, integration, and workflow services with their tests
- `force-app/main/default/lwc/` — Lightning Web Components
- `force-app/main/default/flows/` — guided investment workflows
- `force-app/main/default/objects/` — investment data model and field metadata
- `force-app/main/default/reports/` and `dashboards/` — standard Salesforce reporting assets
- `sfdx-project.json` — Salesforce DX project configuration (API version 68.0)

## Develop and deploy

### Prerequisites

- Salesforce CLI
- Access to a Salesforce sandbox with permissions to deploy the project metadata

### Local org configuration

Use `.env.example` as the template for your local configuration file. On Windows, place it at `%LOCALAPPDATA%\SalesforceInvestmentFinanceApp\.env`, outside synced folders; the loader also accepts `SALESFORCE_PORTFOLIO_ENV_FILE` to select another local path. Set the production and sandbox org IDs and CLI aliases there. Only the blank template is committed; Salesforce CLI authentication remains separate.

### Deploy to a sandbox

```bash
sf org login web --alias investment-sandbox --instance-url https://test.salesforce.com
sf project deploy start --source-dir force-app --target-org investment-sandbox
```

After deployment, configure the Named Credentials, review scheduled jobs and permission assignments, and use representative sandbox data to validate calculations and import workflows. The repository contains Apex unit tests alongside the implementation; run the relevant tests in a sandbox before promoting changes.

## Project status

This is an actively developed portfolio-management application. Production readiness depends on the target org's integration configuration, data quality, permissions, and successful sandbox validation.
