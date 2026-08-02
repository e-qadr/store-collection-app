# Phase 2 inter-branch invoice deployment preflight

This checklist is deliberately local and undeployed. Do not run its production
steps until deployment is explicitly approved.

## Required counter inspection

Before enabling version-2 creation, perform a read-only inventory of every
active branch and `inter_branch_invoice_counters/{branchId}` document. Record
the result outside application logs and verify all of the following:

- every active supplying branch has exactly one existing counter document;
- the counter document ID and stored `branch_id` equal the branch document ID;
- the stored branch code matches the existing branch code used by historical
  invoice numbers;
- `next_number` is a positive safe integer and agrees with the last legitimately
  allocated invoice number for that branch;
- duplicate, missing, malformed, or unexpectedly reset counters are escalated
  for an accountant-approved sequence decision.

Do not create a missing counter automatically, infer a sequence from incomplete
data, rewrite an explicit value, or consume a number during this inspection.
The application must continue returning `counter-uninitialized` until the
counter is explicitly and correctly initialized.

## Release gates

- Re-run Flutter, Node 20, payload-boundary, migration-rehearsal, and complete
  Firestore emulator tests against the exact release commit.
- Confirm new v2 headers have no embedded `items` array and all public item
  documents are price-free, branch-scoped, and backend-only.
- Confirm the required local indexes are reviewed and built before clients issue
  the corresponding queries.
- Review the deployment order for backend commands, rules/indexes, and client
  builds so no client can depend on an unavailable schema.
- Take the approved backups/exports and prepare a rollback plan without changing
  historical version-1 invoices.
- Run the secret scan again and verify no local environment, credential, token,
  catalog source, archive, or ignored configuration is in the release diff.

No production Firebase read, write, migration, rules/index deployment, or
application deployment was performed while creating this checklist.
