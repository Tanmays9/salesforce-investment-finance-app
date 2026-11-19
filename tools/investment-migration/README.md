# Investment migration utilities

This directory contains Salesforce DX source-mapping, schema-generation, and migration tools for the investment data model. Migration is a controlled operational process and requires current source exports, reconciliation, and an approved target plan.

## Local configuration

Use the repository-root `.env.example` as a template for your local configuration file. On Windows, place it at `%LOCALAPPDATA%\SalesforceInvestmentFinanceApp\.env`, outside synced folders; `SALESFORCE_PORTFOLIO_ENV_FILE` can override the path. Set local org IDs and aliases, protected artifact directories, and selected integration configuration. Authenticate through Salesforce CLI; keep database URLs, certificates, access tokens, statement files, and generated reports outside Git.

## Controlled migration workflow

1. Export source schemas and records into protected local storage; record source counts, hashes, and export dates.
2. Map entities by stable identity and resolve conflicts before loading.
3. Generate and deploy metadata in an isolated sandbox.
4. Load parent records, dependent records, and files in resumable stages, then reconcile counts, relationships, and hashes.
5. Run production cutover only under a separately reviewed runbook with an approved source freeze and recovery plan.

Use only explicitly supplied run identifiers and target aliases. The loader validates the configured target org before production-specific operations. Do not run a historical cutover against current data as a deployment shortcut.

## Source files

- `mapping.json` — source-to-Salesforce field and relationship mapping
- `prepare.py` — snapshot preparation and metadata generation
- `migrate.py` — resumable load, relationship, file, and verification operations
- `finish.py` — final reconciliation and evidence manifest generation

Generated exports, before-images, source archives, recovery manifests, credentials, and acceptance evidence remain local and are never committed.
