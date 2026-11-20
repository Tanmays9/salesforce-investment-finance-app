---
title: CAS statement import
description: Statement upload, asynchronous parsing, duplicate review, reconciliation, and confirmed ledger posting.
---

# CAS statement import

CAS import has a deliberate two-part boundary: a parser extracts and stages evidence; an authorized user reviews and confirms a reconciled folio/share-class scope before any new movement is posted.

## End-to-end workflow

**Request sequence:** user uploads a PDF in the `Inv_ImportCAS` Flow → Salesforce creates an import run linked to `ContentVersion` → `invParseStatement` submits the run and optional transient password → the authenticated AWS worker retrieves the file, parses and normalizes it → the parser-only Apex endpoint stages rows → the user maps each folio/share-class scope, reviews matches and balances, then confirms a reconciled scope.

## Salesforce-side records and code

- `Inv_ImportCAS` is a Screen Flow using Salesforce Files to create an `Inv_OpsImportRuns__c` record.
- `invParseStatement` sends the run ID, ContentVersion ID and optional password to `InvImportActions.submit()`. The component keeps password input transient; it is not saved on the Salesforce import record.
- `InvImportActions` gates operations with the Portfolio Manager permission and submits the job through the `Inv_CASParser` Named Credential.
- `InvImportEndpoint` is the parser-only REST receiver. It checks the `Inv_ParseStatements` custom permission and delegates only `stage` and `failed` operations to `InvCASService`.
- `InvCASService` creates an import run, stages one summary per folio/share-class scope and its transaction rows, maps scopes to Salesforce investment accounts, classifies possible matches, and confirms one reconciled scope.

Read [`InvCASService.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvCASService.cls), [`InvImportActions.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvImportActions.cls), [`InvImportEndpoint.cls`](https://github.com/Tanmays9/salesforce-investment-finance-app/blob/main/force-app/main/default/classes/InvImportEndpoint.cls), `force-app/main/default/lwc/invParseStatement/` and `force-app/main/default/flows/Inv_ImportCAS.flow-meta.xml` together; the workflow spans all of them.

## Duplicate classification and confirmation

The parser currently accepts rehearsed CAMS and KFintech layouts. Other issuers/layouts fail safely until a mapping is implemented and rehearsed. The system uses multiple independent duplicate and reconciliation checks:

1. The uploaded PDF's SHA-256 identifies the same file and existing source-document evidence.
2. Transaction economic keys scope account, instrument, date, type, signed units and consideration. An occurrence value allows two economically identical purchases to remain distinct when the source really contains both.
3. Reliable transaction/provider references strengthen identity where available. Parser sequence is retained as evidence but is not treated as a universal permanent key.
4. Staged rows are classified as existing, new, possible duplicate, conflict, unmapped or reconciliation failure. Ambiguous matches require human review.
5. During confirmation, the destination account and import run are locked, rows are rechecked, already-existing movements remain linked as evidence, and only resolved `New` rows are posted.
6. Opening units plus accepted movements must equal the statement closing units. The confirmation is guarded by a transaction savepoint; a failure rolls back the account's posting work.
7. Unique posting keys and an idempotent closing position snapshot prevent duplicate posts on retry. Successful posting links source document evidence and queues recalculation.

The normalized scope key is derived from folio plus share-class ISIN. Map and confirm each staged scope only after reviewing it; an import can remain partially confirmed while other scopes need work. A statement with insufficient opening history can reconcile units without establishing complete acquisition basis or personal return.

## Parser service and operations

The optional hosted parser is under [`tools/portfolio/cas/`](https://github.com/Tanmays9/salesforce-investment-finance-app/tree/main/tools/portfolio/cas):

- `worker.py` authenticates with a dedicated certificate-based Salesforce integration identity, retrieves the authorized ContentVersion, checks its identity/status, parses it and stages normalized data.
- `normalise.py` converts provider output to a bounded contract with exact decimal text, account scope keys, transaction occurrences and warnings.
- `requirements.txt` pins `casparser==1.4.1` and its runtime dependencies; `Dockerfile` defines the Lambda image.
- `infrastructure.py` builds an ECR image repository, Lambda worker/dispatcher, restricted API Gateway endpoints, short-lived Secrets Manager password references and an SQS failure queue.
- `auth.py` provisions the restricted parser identity and Salesforce OAuth configuration for a specific stage; `deploy.py` validates the target alias/stage and deploys stage-specific AWS and Salesforce Named Credential configuration.
- `rehearse.py` and parser tests validate the parser workflow; use synthetic or authorized protected statements, never commit statements or generated identity material.

The configured worker uses a 2 GB memory allocation, a five-minute timeout and single concurrent parse worker. Treat these as current defaults, not capacity guarantees; verify statement size and execution time before changing them. The worker rejects statements above its configured size guard. Unsupported/encrypted formats fail without ledger posting.

## Security and failure behavior

- Password submission uses a separate short-lived Secrets Manager secret reference; the worker validates run identity/expiry. It deletes the password secret after a completed parse, while a failed job may retain it briefly for retry; scheduled expiry cleanup removes orphaned secrets. Do not log or persist PDF passwords.
- The parser identity can read authorized import runs/files and stage rows but cannot confirm or post transactions. A user with the Portfolio Manager permission performs scope mapping and confirmation.
- AWS credentials, private keys, OAuth application material, parser passwords, PDFs and reconciliation reports belong in protected local/AWS storage and are excluded from Git.
- API, PDF, parser or validation failures set an import failure state and retain review evidence. Retry from the import record after checking the status; do not create a replacement run as a way to bypass a conflict.

For a new-org deployment, the hosted parser is a separate optional release. Follow the staged procedure in [Deploy to a new org](./deploy-to-new-org.md), and rehearse it in the sandbox before configuring production.
