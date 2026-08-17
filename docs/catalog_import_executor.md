# Guarded catalog import executor

The existing `tool/legacy_catalog_dry_run.dart` remains the authoritative,
read-only parser. The local Node executor runs that parser, validates the live
brand and an active accountant, and compares the preview with current groups,
products, unique keys, and prior manifests before it can write.

Use Application Default Credentials from an approved local administrator
workstation. Never copy a service-account file into this repository. First run
without `--apply`:

```powershell
node hostinger-push-server/catalog-import-executor.js `
  --project-id <firebase-project-id> `
  --profile al_asalah_legacy_catalog `
  --file "C:\path\to\al-asalah.xls" `
  --brand-id TlOswncJiWX7mwsf3U4e `
  --brand-name "الأصالة" `
  --actor-uid <active-accountant-uid>
```

For Eqlid use profile `eqlid_legacy_catalog`, brand document
`WLMnMVT6u1H2VQ0qziJ3`, and exact name `اقليد`. Review every conflict and
skipped/review row. Invalid rows, including missing primary units, are never
created. A missing source group uses only the deterministic existing contract
named exactly `غير مصنف`; its missing raw value and fallback reason remain in
immutable source metadata.

Write mode requires both `--apply` and the complete
`required_confirmation` emitted by that exact dry-run:

```powershell
node hostinger-push-server/catalog-import-executor.js <same arguments> `
  --apply --confirm "<required_confirmation>"
```

The executor creates only missing records in small transactions. It never
updates a manually changed product and never writes a price. A mutable private
checkpoint supports resume; a completed manifest is immutable.

Rollback is also dry-run by default. It archives, never deletes, and selects
only unchanged records created by the named run that have no invoice/review
references. The system `غير مصنف` group is retained.

```powershell
node hostinger-push-server/catalog-import-executor.js `
  --project-id <firebase-project-id> `
  --actor-uid <active-accountant-uid> `
  --rollback-run-id <catalog-import-run-id>
```

Only after reviewing the plan, repeat with `--apply --confirm` and the exact
rollback confirmation. Do not run either apply command until rules/indexes,
backup, production preflight, and explicit deployment approval are complete.
