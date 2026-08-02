# Firestore rules tests

These tests always use the local Firestore emulator and the synthetic
`demo-store-collection-catalog` project ID. They do not read or write a real
Firebase project.

Requirements: Node.js 20 or later and a Java runtime supported by the Firebase
emulator.

From this directory:

```text
npm ci
npm test
```

The suite proves branch-scoped catalog reads, accountant-only catalog writes,
non-destructive archival rules, immutable audit/history records, and data-layer
denial of all product-price reads by branch users.
