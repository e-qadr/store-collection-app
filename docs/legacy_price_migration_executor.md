# Legacy inter-branch price remediation

`legacy-price-migration-executor.js` is a guarded local Admin SDK tool for
workflow-v1 inter-branch invoices. It inventories price-like fields in invoice
headers, embedded and subcollection items, embedded and collection history,
and notifications. Reports contain paths/counts and checksums, never the price
values themselves.

Run the committed fixture without Firebase access:

```powershell
node hostinger-push-server/legacy-price-migration-executor.js `
  --fixture hostinger-push-server/test/fixtures/legacy-price-executor-fixture.json
```

For a future production preflight, authenticate with approved Application
Default Credentials and run without `--apply`:

```powershell
node hostinger-push-server/legacy-price-migration-executor.js `
  --project-id <firebase-project-id> `
  --actor-uid <active-admin-or-accountant-uid>
```

If a legacy invoice has no reliable currency, copy
`legacy-price-currency-map.example.json` to the ignored local file
`legacy-price-currency-map.json`, add only reviewed invoice-to-currency entries,
and pass `--currency-map` with that local path. Supported currencies remain
YER, SAR, and USD.

Any unknown price alias, malformed value, total mismatch, mixed embedded and
subcollection item storage, or concurrent public change is a blocking
conflict. Resolve it with the accountant and make a new dry-run. Do not edit
the generated plan.

Apply mode has three independent gates: `--apply`, the exact
`required_confirmation`, and the exact `required_production_confirmation`
printed by the same dry-run:

```powershell
node hostinger-push-server/legacy-price-migration-executor.js `
  --project-id <firebase-project-id> `
  --actor-uid <active-admin-or-accountant-uid> `
  --currency-map hostinger-push-server/legacy-price-currency-map.json `
  --apply `
  --confirm "<required_confirmation>" `
  --production-confirm "<required_production_confirmation>"
```

Each invoice is migrated in one bounded transaction. The executor verifies the
source checksum, creates or validates the restricted snapshot and append-only
history, and only then replaces public documents with price-free copies in the
same atomic commit. It preserves all non-price fields, never deletes a document,
and records private checkpoints plus an immutable final manifest. Repeating an
interrupted or completed plan is idempotent.

Do not run the production command until a backup, conflict review, deployed
price-security rules, and explicit deployment/migration approval are complete.
