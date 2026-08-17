# CODEX HANDOFF — Store Collection App

> This is the continuity record for the next AI assistant or developer. Read it
> before changing code, deploying, importing product data, or changing Firebase
> security.
>
> Last updated: 2026-08-06
> Repository: S:\business\both\projects\collection_flutter\store collection app
>
> Never put actual passwords, tokens, upload credentials, service-account JSON,
> keystores, local environment values, or spreadsheet contents in Git, chat,
> tests, logs, or this file.

---

## 1. Project objective

This is an Arabic RTL Flutter business application for branches, users,
products, invoices, accounting handoff, notifications, and invoice uploads.

The agreed business objective is:

1. Secure user onboarding, password change, forgot-password, and administrator
   password reset.
2. A product catalog for each brand, maintained by the accountant.
3. Direct branch transfers: a supplying manager creates an invoice for a
   receiving branch; the receiving manager confirms receipt; the general
   manager prices it; the accountant posts it.
4. Separate purchase invoices: the general manager creates the invoice for a
   receiving branch; the branch manager confirms it; the general manager
   prices it; the accountant posts it.
5. A new material may be typed in a purchase invoice without blocking invoice
   creation or receipt. The accountant reviews it afterwards.
6. Managers and employees must never see prices, price history, private
   accounting references, or price-bearing PDFs.
7. Production deployment is staged. A GitHub push is not a deployment.

The stored role collector means General Manager. Do not rename the stored role
to change its displayed label.

---

## 2. Current Git and production status

### Last fully committed and pushed implementation

~~~
8dffa3bbbc926858f8530a96e551af2649bc47ff
feat: add secure purchase invoice workflow phase 3
~~~

When this commit was pushed:

- Local main and origin/main were identical.
- Ahead/behind was 0/0.
- Working tree was clean.
- No Hostinger deployment, Firebase production access, rules/index deployment,
  app build/release, Excel import, or production migration occurred.

### Important current-worktree note

When this handoff was written, a later local task for production release
controls was in progress. These uncommitted changes belong to that task and
must be preserved until its agent reports tests and a final commit:

~~~
M  .gitignore
M  android/.gitignore
M  android/app/build.gradle.kts
M  firestore.rules
M  firestore_rules_tests/test/catalog_security.test.mjs
M  hostinger-push-server/package.json
M  hostinger-push-server/test/support/fake-firestore.js
M  lib/models/product_catalog_model.dart
M  lib/services/legacy_catalog_importer.dart
M  lib/services/product_catalog_service.dart
M  test/legacy_catalog_importer_test.dart
?? android/key.properties.example
?? docs/android_release_signing.md
?? docs/catalog_import_executor.md
?? hostinger-push-server/catalog-import-executor.js
?? hostinger-push-server/test/catalog-import-executor.test.js
?? test/android_release_signing_configuration_test.dart
~~~

The Phase 1–3 code is in GitHub, but it is not yet ready for a coordinated
production release. See Section 11.

---

## 3. Completed work

### 3.1 Password management

Commit:

~~~
99180e61dcb5b9991ec8588e8abb17d7c2c249f0
feat: add secure password management workflow
~~~

Implemented:

- Admin creates/resets a user password using the existing admin UI.
- A random temporary password can be delivered by Firebase email when
  configured, or provided to the admin for manual delivery.
- First login with a temporary password forces the user to choose a personal
  password.
- Existing users can change their password.
- Forgot-password flow is available.
- Admin reset forces the next password change.
- Health reports Firebase/password-email readiness.

History: password email was initially believed missing, but it was in Spam.
Delivery worked. Future test mailboxes should check Spam and Promotions.

### 3.2 Node backend dependency hardening

Hostinger is configured for Node 20. Dependencies were upgraded without a
force audit fix.

~~~
express                 5.2.1
firebase-admin          13.10.0
@google-cloud/firestore 7.11.6
uuid                    11.1.1
protobufjs              7.6.5
body-parser             2.3.0
~~~

Technical decisions:

- Firebase Admin 13 plus Firestore 7 was retained because it supports Node 20.
  Firebase Admin 14 needs Node 22.
- A narrow uuid override was used for Node 20 compatibility.
- Global Express JSON limit remains 16 KB:

~~~js
express.json({ limit: "16kb" })
~~~

- Larger parser limits are restricted to invoice routes only.
- Production dependency audit excluding development dependencies passed.

### 3.3 Invoice-upload token hardening

The PHP invoice-upload feature is separate from the Node backend.

- The real upload token was removed from source and VS Code launch settings.
- PHP reads the token from ignored local configuration or environment and uses
  constant-time comparison.
- Example configuration contains placeholders only.
- The actual upload configuration remains ignored and must never be committed
  or included in a release archive.
- Flutter Run supplies the token through local dart-define configuration.

Historic error: upload returned Unauthorized when client/server values did not
match. The issue was fixed by synchronizing the ignored PHP config, deployed
PHP endpoint, and local Flutter runtime value. Do not repeat the actual value.

### 3.4 Phase 1 — secure product catalog

Commits:

~~~
03284b04457dfee09ad19b24279445ee64cbe035
feat: add secure product catalog phase 1

271a1b5ccf7b16cca36b38d796bbfaff06b3016a
fix: tighten price writes and support uncategorized products
~~~

Implemented:

- Brand-scoped product groups and products.
- Accountant-only product create, edit, archive, and reactivate workflow.
- Stable products, legacy codes, normalized names, up to three units, and
  immutable non-price audit events.
- Transactional duplicate prevention using unique keys.
- Restricted accounting profiles.
- Restricted current-price memory and append-only price history.
- Arabic RTL accountant catalog UI: search, filters, history, archive, and
  accounting-reference management.
- SpreadsheetML Excel dry-run profiles and local rules/indexes.

Catalog decisions:

- Product belongs to one brand and group.
- Units are independent choices; do not infer conversion ratios.
- Price memory key is brand + product + unit + currency.
- Prices are never stored in public catalog records.
- Missing/unreliable group uses the exact approved group name غير مصنف.
- Preserve the raw group value and reason for fallback. Never guess another
  group.

### 3.5 Phase 2 — direct inter-branch invoice workflow

Commits:

~~~
49a467bc34392197832b0ba76bfda684bee8eab4
feat: add direct inter-branch invoice workflow phase 2

2e942b8a860b59bf3ee33c5b4598dfbe88c75684
fix: support scalable secure inter-branch invoice items
~~~

Workflow:

~~~
Supplying manager creates direct invoice
→ pendingReceiverReview
→ receiving manager confirms receipt
→ pendingPriceEntry
→ collector confirms protected prices
→ pendingAccountingEntry
→ accountant posts
→ postedToAccounting
~~~

Key behavior:

- New transfers no longer use the old request/approval process. Old workflow-v1
  records remain processable only for compatibility.
- Supplying manager selects the receiving branch and products only from the
  supplying branch brand.
- Cross-brand transfer is supported; catalog brand is always sending brand.
- Invoice number comes from inter_branch_invoice_counters/{branchId}.
- Missing counter fails with counter-uninitialized. Never invent, increment, or
  infer a counter during preflight.

Scalability/security:

- Maximum v2 item count is 50.
- Items are stored outside the header:

~~~
inter_branch_invoices/{invoiceId}/items/{itemId}
~~~

- Header contains item_count, item_digest, revision, and workflow identity.
- V2 writes are backend-only, atomic, idempotent, and revision checked.
- Public documents, items, events, notifications, errors, and manager PDFs are
  price-free.
- Restricted price snapshots/history are separate.

A measured 50-item request was 19,983 bytes, larger than global 16 KB. Only
inter-branch routes use a 32 KB parser; global parser remains 16 KB.

### 3.6 Phase 3 — purchase invoices and unmatched-material review

Commit:

~~~
8dffa3bbbc926858f8530a96e551af2649bc47ff
feat: add secure purchase invoice workflow phase 3
~~~

Workflow:

~~~
collector/general manager creates purchase invoice
→ pendingReceiverReview
→ receiving manager confirms receipt
→ pendingPriceEntry
→ collector confirms protected prices
→ pendingAccountingEntry
→ accountant posts
→ postedToAccounting
~~~

Implemented:

- Separate purchase models, services, API, screens, Node commands/domain,
  Firestore collections, events, PDFs, tests, rules, and indexes.
- Purchase logic is not mixed into the transfer service.
- Up to 50 price-free items:

~~~
purchase_invoices/{invoiceId}/items/{itemId}
~~~

- General manager selects catalog products from receiving-branch brand.
- New/unmatched material can be typed into invoice. It creates an accountant
  review task but does not block creation or receipt.
- Accountant can link an existing product, create a corrected one with up to
  three units, request clarification, return task to review, and record
  accounting synchronization.
- Normal accounting post requires resolved tasks.
- Accountant override requires a non-empty immutable audit reason.
- Late reconciliation preserves original entry, quantities, locked prices,
  totals, and financial history.
- General manager receives safe price suggestions but must explicitly confirm.
- Manager PDF is price-free; authorized PDF merges restricted snapshot only
  after authorization.
- Notifications and timeline are price-free.

Payload:

- Largest valid 50-item purchase request: 60,393 bytes.
- Global limit stays 16,384 bytes.
- Purchase routes alone use 65,536 bytes.
- 65,536 bytes reaches schema validation; 65,537 returns safe JSON HTTP 413.

Explicitly deferred:

- Tax, discounts, other costs, and tax-inclusivity.
- Supplier attachments and Firebase Storage rules.
- Purchase cancellation, editing, and archive workflow.
- iOS/Web/desktop production Firebase setup.

---

## 4. Architecture and technologies

### Flutter client

- Flutter/Dart.
- Arabic RTL UI.
- Firebase Authentication and Cloud Firestore client reads.
- VS Code Run uses prompted/ignored dart-define values rather than committed
  secrets.
- Android Firebase project: store-collection-app.
- Android package: com.storecollection.store_collection_app.

### Hostinger Node backend

Directory: hostinger-push-server/

Stack:

- Node.js 20.x
- Express 5
- Firebase Admin
- Google Cloud Firestore

Responsibilities:

- Password management.
- Authenticated commands for transfers and purchases.
- Firebase ID token verification with revocation checking.
- Role, branch, active-state, and forced-password-change revalidation inside
  transactions.
- Atomic writes, idempotency, revision checks, events/notifications, and
  restricted price writes.
- Health endpoint.

### Firebase

- Cloud Firestore: public headers/items/events and restricted price/accounting
  documents.
- Firebase Authentication: identities.
- Firestore rules: client read protection and backend-only v2/purchase writes.
- Admin SDK bypasses rules. Backend validation is the primary write boundary.
- Emulator security tests: firestore_rules_tests/.

### Separate PHP endpoint

Location: server/hostinger/upload_invoice.php

Do not overwrite this endpoint or its local token configuration during a Node
backend deployment.

---

## 5. Authorization and data model

### Stored roles

~~~
admin      Administration
collector  General manager: purchase creation and price confirmation
accountant Catalog maintenance, material review, accounting posting
manager    Branch manager
~~~

Unknown roles must fail closed in Flutter, Node, and Firestore rules.

### Mandatory price-security rule

Price must not be placed in public invoice headers/items/events, notifications,
manager PDFs, logs, or error messages.

Managers/employees must not read:

~~~
product_price_latest
product_price_history
inter_branch_invoice_prices
inter_branch_invoice_price_history
purchase_invoice_prices
~~~

UI hiding alone is insufficient.

### Major collections

Catalog:

~~~
product_groups/{groupId}
products/{productId}
product_unique_keys/{keyId}
products/{productId}/audit_events/{eventId}
product_accounting_profiles/{productId}
product_price_latest/{priceKey}
product_price_history/{eventId}
~~~

Transfers:

~~~
inter_branch_invoices/{invoiceId}
inter_branch_invoices/{invoiceId}/items/{itemId}
inter_branch_invoice_events/{eventId}
inter_branch_invoice_prices/{invoiceId}
inter_branch_invoice_price_history/{eventId}
inter_branch_invoice_counters/{branchId}
~~~

Purchases:

~~~
purchase_invoices/{invoiceId}
purchase_invoices/{invoiceId}/items/{itemId}
purchase_invoice_events/{eventId}
purchase_invoice_prices/{invoiceId}
product_review_tasks/{taskId}
~~~

---

## 6. Important files

Firebase:

- firestore.rules — client authorization; do not deploy it alone.
- firestore.indexes.json — local manifest has 30 composite indexes.
- firebase.json
- firestore_rules_tests/test/catalog_security.test.mjs
- firestore_rules_tests/test/inter_branch_security.test.mjs
- firestore_rules_tests/test/purchase_invoice_security.test.mjs

Node backend:

- hostinger-push-server/server.js — parser ordering, route mounting, health,
  safe error handling.
- hostinger-push-server/password-management.js
- hostinger-push-server/inter-branch-invoice-domain.js
- hostinger-push-server/inter-branch-invoice-commands.js
- hostinger-push-server/purchase-invoice-domain.js
- hostinger-push-server/purchase-invoice-commands.js
- hostinger-push-server/legacy-price-migration.js — rehearsal/planning at
  Phase 3; not an approved production executor then.
- hostinger-push-server/test/

Flutter catalog:

- lib/models/product_catalog_model.dart
- lib/models/product_price_model.dart
- lib/services/product_catalog_service.dart
- lib/services/product_price_service.dart
- lib/services/legacy_catalog_importer.dart
- lib/screens/products/product_catalog_management_screen.dart
- lib/utils/catalog_normalization.dart

Flutter transfer:

- lib/models/inter_branch_invoice_model.dart
- lib/models/inter_branch_invoice_price_model.dart
- lib/services/inter_branch_invoice_api_service.dart
- lib/services/inter_branch_invoice_service.dart
- lib/screens/inter_branch_invoices/
- lib/services/pdf_service.dart
- lib/utils/inter_branch_invoice_policies.dart
- lib/utils/inter_branch_invoice_transitions.dart

Flutter purchase:

- lib/models/purchase_invoice_model.dart
- lib/models/purchase_invoice_price_model.dart
- lib/services/purchase_invoice_api_service.dart
- lib/services/purchase_invoice_service.dart
- lib/services/purchase_invoice_pdf_service.dart
- lib/screens/purchase_invoices/new_purchase_invoice_screen.dart
- lib/screens/purchase_invoices/purchase_catalog_picker.dart
- lib/screens/purchase_invoices/purchase_invoices_dashboard.dart
- lib/screens/purchase_invoices/purchase_invoice_details_screen.dart
- lib/screens/purchase_invoices/product_review_queue_screen.dart

Shared UI:

- lib/screens/systems/system_selection_screen.dart
- lib/screens/dashboards/collector_dashboard.dart
- lib/screens/dashboards/accountant_dashboard.dart
- lib/screens/notifications/notifications_screen.dart
- lib/services/notification_service.dart

Never commit/archive:

~~~
.env
.env.*
android/key.properties
*.jks
*.keystore
upload_invoice.config.php
Firebase service-account JSON
node_modules/
*.zip
*.xls
*.xlsx
emulator logs
~~~

---

## 7. Excel catalog sources

| Brand | Brand ID | Input |
|---|---|---|
| الأصالة | TlOswncJiWX7mwsf3U4e | C:\Users\E_QDR\Downloads\الاصناف مع الوحدات - الاصالة.xls |
| إقليد | WLMnMVT6u1H2VQ0qziJ3 | C:\Users\E_QDR\Downloads\دليل المواد - فرع اقليد جبران.xls |

Dry-run facts:

- Al-Asalah: 91 products and 10 groups; no invalid rows.
- Eqlid: 2,138 parsed products, 22 populated groups, many missing/unreliable
  groups, one missing primary unit, and seven structurally blocked/ambiguous
  rows in the earlier dry-run report.
- No reliable per-product prices exist in these sources. Never create prices
  from the spreadsheet.
- Do not modify the source files.

---

## 8. Verification history

Results reported against exact commits:

Password/dependency baseline:

- Node 20.20.2 npm ci passed.
- npm run check passed.
- npm test: 5/5 passed at that stage.
- npm audit --omit=dev: 0 vulnerabilities.

Phase 1:

- flutter analyze passed.
- Flutter tests: 54/54.
- Importer tests: 11/11.
- Firestore Emulator catalog tests: 13/13.

Phase 2 final:

- flutter analyze passed.
- Flutter tests: 94/94.
- Arabic widget tests: 10/10.
- Node tests: 34/34.
- Firestore Emulator tests: 28/28.
- Production npm audit: 0 vulnerabilities.

Phase 3:

- Node 20.19.5 verification passed.
- Backend npm ci and npm run check passed.
- Backend tests: 47/47.
- Backend npm audit --omit=dev: 0 vulnerabilities.
- Firestore Emulator suite: 32/32.
- flutter analyze passed.
- Full Flutter suite: 107/107.
- Arabic Phase 3 widget tests: 5/5.
- git diff --check, JSON validation, and secret scan passed.

Known development-only concern: Firestore Emulator tooling reported seven
moderate audit warnings in development dependencies. Production backend audit
was clean.

---

## 9. Commands used and future release gates

Flutter:

~~~powershell
flutter pub get
flutter analyze
flutter test
~~~

Node backend:

~~~powershell
Set-Location hostinger-push-server
npm ci
npm run check
npm test
npm audit --omit=dev
npm ls uuid protobufjs body-parser
~~~

Firestore emulator:

~~~powershell
Set-Location firestore_rules_tests
npm ci
npm test
~~~

The emulator project is demo-store-collection-catalog. Never redirect it to
production.

Read-only Excel previews:

~~~powershell
dart run tool/legacy_catalog_dry_run.dart --profile al_asalah_legacy_catalog --file "C:\Users\E_QDR\Downloads\الاصناف مع الوحدات - الاصالة.xls" --brand-id TlOswncJiWX7mwsf3U4e --brand-name "الأصالة" --details
dart run tool/legacy_catalog_dry_run.dart --profile eqlid_legacy_catalog --file "C:\Users\E_QDR\Downloads\دليل المواد - فرع اقليد جبران.xls" --brand-id WLMnMVT6u1H2VQ0qziJ3 --brand-name "إقليد" --details
~~~

Conditional Firebase deployment — not authorized until all blockers pass:

~~~powershell
firebase deploy --only firestore:indexes --project store-collection-app
firebase deploy --only firestore:rules --project store-collection-app
~~~

Deploy indexes first. Wait until every required index is Enabled in Firebase
Console. Then deploy rules. Do not release Flutter while any index is Building.

Conditional signed Android bundle:

~~~powershell
flutter build appbundle --release --build-name=<approved-version> --build-number=<new-unique-build-number> --dart-define-from-file=.env.release.json
~~~

The ignored release environment file must not be committed. AUTH_API_BASE_URL
must have no trailing slash.

---

## 10. Problems seen and resolutions

### Hostinger dependency vulnerabilities

Dependencies were upgraded safely for Node 20. No force audit fix was used;
production audit became clean.

### Invoice upload Unauthorized

Client and PHP token/configuration did not match. Synchronizing the ignored
server config and local Flutter runtime value fixed it.

### Password email apparently missing

It was delivered to Spam. No code defect was found.

### Invoice capacity

Early invoice design could not safely carry enough items. Phase 2 moved items to
subcollections and added route-only parser size. It supports 50 items.

### Purchase payload

50 purchase items cannot fit global 16 KB. Phase 3 uses route-only 64 KB parser
and boundary tests, without weakening the global parser.

### Eqlid source quality

Rows have missing/unreliable groups and invalid data. No production import has
run. Use غير مصنف only for group uncertainty; keep missing-primary-unit rows
review-required.

### Production readiness

Three controls were missing in Phase 1–3: Android release signing, a guarded
live catalog importer, and legacy inline-price remediation. The follow-up task
is the current uncommitted work listed in Section 2.

---

## 11. Unfinished work and release blockers

Do not deploy Phase 1–3 until the following controls are resolved or explicitly
waived by the owner with documented risk.

### Android signing

The committed Android release used debug signing.

Required:

- Ignored local keystore and android/key.properties.
- Release build fails if signing configuration is missing.
- No debug fallback in release.
- A new unique build number; do not reuse 1.0.0+4.
- Never share the signing key/password.

### Production catalog import

Existing importer is dry-run only. It cannot validate live brands, compare
existing products/keys, apply safely, record manifests, or rollback.

Required:

- Guarded production-capable executor, dry-run default.
- Exact brand ID/name validation.
- Read live products/unique keys before plan.
- Idempotent apply/resume.
- Immutable manifest/source hash.
- Safe handling for غير مصنف, invalid rows, manual corrections, rollback.
- Explicit approval before production apply.

Manual creation is possible but not practical for all Eqlid products. Do not
enable new transfer/purchase creation until needed catalog products exist.

### Legacy v1 price confidentiality

New v2/purchase data is safe. Legacy v1 documents may contain manager-readable
inline prices.

Required:

- Read-only inventory of legacy headers, items, history, and notifications for
  price-like fields.
- Reviewed migration strategy: restricted write and integrity verification first,
  then public inline field removal.
- Idempotent/resumable conflict handling for malformed values and currency.

Do not deploy rules if production inspection finds manager-readable legacy
prices without approved remediation.

### Production preflight

Requires explicit approval:

- Firestore backup/export and capture of deployed rules/index state.
- Validate branches, brands, counters, branch codes, manager IDs, and user
  roles/branch assignments.
- Confirm intended admin, collector, accountant, and test managers.
- Verify Firebase Admin/email configuration without logging values.
- Check existing public data for forbidden prices.

### Deferred features

Not current agreed release blockers:

- Purchase tax, discount, other costs, tax inclusivity.
- Supplier attachments/Firebase Storage policy.
- Purchase cancel/edit/archive.
- iOS/Web/desktop production Firebase configuration.
- Custom email-domain/template branding.
- Staging flavor and feature flags.

---

## 12. Recommended next step

### Immediate task

Finish and review the existing release-control task only:

1. Safe Android release-signing configuration/documentation.
2. Local guarded catalog import executor: dry-run default, explicit apply,
   manifests, no prices, safe resume/rollback.
3. Local guarded legacy price preflight/migration executor: dry-run default,
   explicit apply, no production execution.

The agent must preserve Phase 1–3 behavior, run complete Flutter/Node/Firestore
tests, run both catalog dry-runs and migration fixture dry-run, scan secrets,
and create one local commit only. It must not push, deploy, import production
data, or access production Firebase.

Suggested commit message:

~~~
feat: prepare secure production release controls
~~~

### After review and normal push

1. Create/secure the Android signing key locally; fill ignored
   android/key.properties. Never give key/password to AI.
2. Obtain explicit approval for backup and production read-only preflight.
3. Stop on counter, role, brand, legacy-price, or Firebase-config mismatch.
4. Configure Hostinger environment variables without logging values.
5. Build a fresh Node backend archive from reviewed Git outside repository.
   Exclude secrets, node_modules, tests, ZIPs, Excel, logs, PHP config, and
   service-account files.
6. Deploy Node backend using Node 20, npm ci --omit=dev, npm start; verify
   health endpoint.
7. Deploy Firestore indexes; wait for all Enabled.
8. Run approved legacy price remediation only if required by preflight and
   accountant conflict decisions.
9. Deploy Firestore rules.
10. Dry-run catalog import, review it, then apply only with explicit approval.
    Never import prices.
11. Build a newly signed Android AAB with a new build number/runtime endpoints.
12. Run smoke tests with dedicated labelled test accounts.

Smoke tests must cover health, password flow, catalog rights, purchase invoice
with catalog item, unmatched material review, direct transfer/counter retry, and
manager price denial in UI/PDF/notifications/Firestore. Keep labelled audit
records; do not delete history.

---

## 13. Instructions for the next assistant

1. Read this document fully.
2. First run git status --short --branch and git log --oneline --decorate -8.
3. Preserve uncommitted work belonging to another agent.
4. Never confuse GitHub push with deployment.
5. Do not deploy rules before indexes are Enabled, legacy price exposure is
   addressed, and production preflight passes.
6. Do not use force push, destructive reset, npm audit fix force, or an
   unreviewed production migration.
7. Admin SDK bypasses Firestore rules: retain complete server validation.
8. Public documents, PDFs, events, notifications, errors, and logs must remain
   price-free.
9. If a secret was exposed, do not repeat it. Rotate it and remove it safely.
10. Model guidance:
    - GPT-5.6 Sol with XHigh reasoning: architecture, security, Firebase,
      migration, or multi-layer implementation.
    - GPT-5.6 Terra with High reasoning: scoped Git checks and normal pushes.

This document is not authority to deploy or write production data.
