# Salesforce investment portfolio operations

This Salesforce DX workspace contains the model, calculations, integrations, and Lightning experience for reviewing mutual-fund holdings, researching funds, comparing plans, and reconciling statement imports.

## Local configuration

Use the repository-root `.env.example` as a template for your local configuration file. On Windows, place it at `%LOCALAPPDATA%\SalesforceInvestmentFinanceApp\.env`, outside synced folders; `SALESFORCE_PORTFOLIO_ENV_FILE` can override the path. The local file holds org IDs and aliases, protected artifact directories, AWS region, and integration secret-name template. Authenticate through Salesforce CLI and AWS profiles separately. Never put passwords, access tokens, certificates, or database URLs in Git.

## Build and deploy

For reproducible metadata changes, run `python tools/portfolio/build.py`, then `python tools/portfolio/reporting.py`, then `python tools/portfolio/pages.py`. Deploy the generated scoped manifests to a sandbox first. The migration schema generator must invoke the operational overlays after regenerating preserved metadata. Operational fields are described in `model.json`; source mappings are in `tools/investment-migration/mapping.json`.

The target-specific scripts load expected org IDs from `.env` and validate the selected org and its sandbox/production status before continuing. Use the matching CLI alias from the local environment configuration.

## Application workflows

- Use the Overview, Holdings, Funds, Plans, Imports, and Data Health views for portfolio review.
- Fund research combines dated NAV, benchmark, expense, and composition information with explicit coverage dates.
- Draft plans compare alternatives against a published valuation baseline and do not change actual holdings.
- Statement imports stage and reconcile rows before confirmation; duplicate evidence does not create a second ledger transaction.
- MFapi and AMFI provide mutual-fund NAV observations. Official index feeds provide supported benchmark history.
- Stocks and ETFs can be tracked on the watchlist; mutual-fund accounting and valuation are the current portfolio-ledger scope.

## Data handling

Use sandbox fixtures for development. Personal statements, source exports, account identifiers, calculation evidence, private run artifacts, and credentials belong in protected local storage and must not be committed. Keep the `.env` file local and commit only `.env.example` with blank values.
