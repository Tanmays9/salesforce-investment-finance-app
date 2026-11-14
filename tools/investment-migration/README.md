# Investment migration

Target production org: `LOCAL_SALESFORCE_PRODUCTION_ORG_ALIAS`, organization ID `LOCAL_SALESFORCE_PRODUCTION_ORG_ID`, Enterprise Edition. The checked-in metadata is API 68.0. The model/data migration completed on 2026-11-13 after a verified rehearsal in the production org's `LOCAL_SALESFORCE_SANDBOX_ORG_ALIAS` Developer sandbox (`LOCAL_SALESFORCE_SANDBOX_ORG_ID`). Technical reconciliation passed; owner review is pending.

Open [Investments](https://REDACTED_SALESFORCE_DOMAIN/lightning/app/REDACTED_SALESFORCE_APP_ID). The separately requested `Investment_Viewers` public group exists in production, empty and with hierarchy access disabled. No sharing rule was added for it.

## Verified state

The rehearsal export is in `LOCAL_PRIVATE_DATA_ROOT/20261113-second`. The final cutover export and acceptance artifacts are in the ACL-restricted `LOCAL_PRIVATE_DATA_ROOT/20261113-cutover2`, outside Git and OneDrive. Twenty web/worker services were stopped and Neon investment tables held under bounded share locks for the final recheck and load. The frozen source data matched the rehearsed dataset. Source locks are released and all four Twenty services are running again. Temporary Neon URL files were removed.

Production contains 50,079 core records plus 20 investment documents. Neon contributed 48,405 records; Twenty adds 1,031 portfolio positions, 12 portfolio snapshots, 619 instruments, one provider and 11 evidence records. No value or relationship conflicts were found. All 50,099 record envelopes/typed projections and 193,905 relationship-field checks reconciled. Repeat import left the same count with no duplicate migrated records.

Eight evidence files totaling 18,248,776 bytes were uploaded, linked, downloaded and SHA-256 verified: four original attachments, three oversized JSON payloads and an exact raw-source archive. `exact-neon-source.zip` also contains the raw Twenty export and preserves original JSON numeric types, schema columns, source constraints and SQL functions. Ordinary viewers can read records and linked evidence but cannot create, edit or delete ledger records; the Apex test passed in both sandbox and production. Thirteen local tests passed. Platform identity/global-schema smoke checks passed; this is not an unrelated business-app UI regression suite.

The generated schema contains 39 custom objects and 74 lookup relationships, the Investments app, standard detail layouts/list views/file lists, tabs, and `Inv_Viewer` / `Inv_MigrationAdmin` permission sets. `mapping.json` is the exact object/field dictionary. `manifest/investment-package.xml` scopes the model deployment; `manifest/investment-views.xml` scopes native layouts/views. Source payloads, record identifiers, document contents, credentials and checkpoints must never be committed.

Navigation correction: both permission sets explicitly mark the six configured app tabs Visible. Application visibility and object access alone did not expose the navigation. Acceptance now checks the live flat REST `/tabs` response as well as the app/layout metadata. Chrome verification confirmed the configured tabs and a portfolio row. Use the **All preserved records** list view for imported data; Recently Viewed starts empty until records have been opened.

## Commands

Use Python 3.11+ with the existing `psycopg` installation and authenticated Salesforce CLI. Run commands from this Salesforce project. Reauthenticate aliases through the normal CLI browser flow when needed; never print `sf org display --json` because it includes credentials.

```powershell
python -m unittest discover -s tools/investment-migration -p test_migration.py -v
python tools/investment-migration/migrate.py verify --target-org LOCAL_SALESFORCE_PRODUCTION_ORG_ALIAS --run 20261113-cutover2
python tools/investment-migration/accept.py --target-org LOCAL_SALESFORCE_PRODUCTION_ORG_ALIAS --run 20261113-cutover2
```

To take a **new** snapshot, securely supply a temporary Neon direct URL in `LOCAL_PRIVATE_DATA_ROOT/neon-url.tmp`, then run:

```powershell
python tools/investment-migration/prepare.py --run NEW_RUN_NAME
python tools/investment-migration/finish.py --run NEW_RUN_NAME
```

Remove the temporary URL file after export. Run directories must be new; retain prior snapshots for evidence. `finish.py` can finish a partial preparation from its existing Neon/Twenty exports without re-reading financial records. It retrieves the referenced attachment bytes and verifies them. After `finish.py`, do not rerun `prepare.py` on that same directory.

For a future rehearsal, authenticate an explicit sandbox alias, confirm its ancestry and `Organization.IsSandbox`, and then:

```powershell
sf project deploy start --manifest manifest/investment-package.xml --target-org SANDBOX_ALIAS --test-level RunSpecifiedTests --tests InvestmentAccessTest --wait 30
python tools/investment-migration/build_layouts.py
sf project deploy start --manifest manifest/investment-views.xml --target-org SANDBOX_ALIAS --wait 30
python tools/investment-migration/migrate.py load --target-org SANDBOX_ALIAS --run 20261113-second
python tools/investment-migration/migrate.py files --target-org SANDBOX_ALIAS --run 20261113-second
python tools/investment-migration/migrate.py verify --target-org SANDBOX_ALIAS --run 20261113-second
```

The loader blocks on source conflicts, insufficient additional storage, unexpected production orgs and missing/expired cutover evidence. Production writes require a matching canonical fingerprint, immutable sandbox record/file proofs, the authorized implementation record, stopped Twenty web/worker services and a live 38-table Neon freeze heartbeat. The completed cutover window is now closed; do not replay production writes against this historical run. Read-only verification remains available. Sandbox ancestry must be confirmed against production before any future rehearsal.

## Identity, precision and recovery

- Migration keys include source entity and canonical identity. Twenty-only additions retain namespaced Twenty IDs; their actual native relationships determine target keys.
- Numeric source fields are stored as exact text. Companion Number fields are populated only when the value fits Salesforce precision and scale without rounding; otherwise they remain blank. Original JSON is authoritative, and no money calculations use Python floats.
- Nullable source booleans have companion Known flags so unknown is distinct from false. Bulk native DateTime projections are stored at whole-second precision, and native long text can trim trailing whitespace; exact source timestamps/text/types remain in verified envelopes and the raw archive.
- Ordinary viewers have read-only access. No permission set grants delete. Four self-lookups use `SetNull` because Salesforce rejects `Restrict` on self-lookups; all other lookups restrict parent deletion. This is not equivalent to database-wide immutability against system administrators.
- Original source constraints and SQL functions are exported in private `constraints.json` and `routines.json`. PostgreSQL posting routines, transaction rules, composite uniqueness, numerical domain checks and approved-plan immutability have not all been ported to native Salesforce automation. Phase one preserves data and snapshots; it does not provide a writable ledger application.
- Every Bulk job and source fingerprint is checkpointed. Failed/unprocessed rows and successful IDs are retained privately. Completed identical jobs are reused, and uncertain upload/job outcomes must be inspected before retrying. Existing before-images are exported in full with pagination before a table is loaded.
- Files deduplicate by content hash, link to the relevant record, and are downloaded for hash verification. Readable titles include the full hash; original file names are retained. Creation/link receipts are retained for recovery. Oversized JSON/fields are linked Files with hash pointers rather than truncated text. Custom-record file links inherit access from the private record; no public distribution URL is created.
- No automatic rollback deletion command is provided. Review the exact successful-ID manifests and before-images before a scoped rollback. Never run a broad delete or overwrite unrelated production records.

## Handoff and boundaries

- Object tab labels omit `Records` (the execution-history tab is `Planning Executions`). Each of the 39 objects has a distinct name-based auto-number prefix, defined in `prepare.NUMBER_PREFIXES`, retaining ten numeric digits. `manifest/investment-presentation.xml` scopes deployment to these objects. Existing auto-number values retain their original `INV-` names; this metadata change does not renumber imported records or reset sequences. Sandbox and production deployment/read-back evidence is retained privately as `presentation-*` reports.

- `final-reconciliation.json` records technical verification and pending owner review; it does not claim a human signature or independent audit of the broker statement.
- `recovery-manifest.json` contains all 50,099 created record IDs, before-image paths and native file IDs. It is scoped evidence, not an automatic deletion command. Metadata creation/deployment evidence is in the protected migration root.
- Preserve Twenty, Neon and existing backups until separately authorized retirement. No ongoing synchronization is installed; do not assume changes in one copy propagate to another.
- This completes model/data preservation. Live NAV ingestion, the SQL posting/calculation engine, writable-ledger invariants and new investment decision dashboards require a subsequent implementation.
