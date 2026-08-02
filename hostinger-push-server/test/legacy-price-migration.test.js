"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  assertFirestoreEmulatorOnly,
  checksum,
  locateLegacyPrices,
  rehearseLegacyPriceMigration,
} = require("../legacy-price-migration");

function fixture() {
  const file = path.join(__dirname, "fixtures", "legacy-inter-branch-price-fixture.json");
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

test("emulator guard refuses production or absent emulator configuration", () => {
  assert.throws(
      () => assertFirestoreEmulatorOnly({environment: {}, projectId: "demo-local"}),
      (error) => error.code === "emulator-required",
  );
  assert.throws(
      () => assertFirestoreEmulatorOnly({
        environment: {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8089"},
        projectId: "store-collection-app",
      }),
      (error) => error.code === "local-project-required",
  );
  assert.throws(
      () => assertFirestoreEmulatorOnly({
        environment: {FIRESTORE_EMULATOR_HOST: "firestore.example.com:8089"},
        projectId: "demo-local",
      }),
      (error) => error.code === "local-emulator-host-required",
  );
  assert.deepEqual(
      assertFirestoreEmulatorOnly({
        environment: {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8089"},
        projectId: "demo-local",
      }),
      {emulatorHost: "127.0.0.1:8089", projectId: "demo-local"},
  );
});

test("rehearsal locates top-level, item, and history prices without reporting values", () => {
  const source = fixture();
  const located = locateLegacyPrices(
      source.public_invoices["legacy-reconciled"].data,
  );
  assert.equal(located.topLevelCount, 2);
  assert.equal(located.itemCount, 4);
  assert.equal(located.historyCount, 1);
  assert.equal(located.unknownPaths.length, 0);

  const {report} = rehearseLegacyPriceMigration(source);
  assert.equal(report.scanned, 3);
  assert.equal(report.containing_prices, 3);
  assert.equal(report.reconciled, 1);
  assert.equal(report.migrated, 1);
  assert.equal(report.conflicts, 2);
  assert.equal(report.missing_currency, 1);
  assert.equal(report.public_price_fields_removed, 7);
  assert.equal(report.snapshots_created, 1);
  assert.equal(report.restricted_history_created, 1);
  assert.doesNotMatch(JSON.stringify(report), /"(unit_price|total_price|price_fields)"\s*:/);
});

test("rehearsal reconciles totals, preserves non-price data, and is idempotent", () => {
  const source = fixture();
  const first = rehearseLegacyPriceMigration(source);
  const migrated = first.state.public_invoices["legacy-reconciled"].data;
  const original = source.public_invoices["legacy-reconciled"].data;

  assert.equal(Object.hasOwn(migrated, "unit_price"), false);
  assert.equal(Object.hasOwn(migrated, "total_price"), false);
  assert.equal(Object.hasOwn(migrated.items[0], "unit_price"), false);
  assert.equal(Object.hasOwn(migrated.items[0], "total_price"), false);
  assert.equal(Object.hasOwn(migrated.history[0].changes, "total_price"), false);
  assert.equal(migrated.accounting_reference, original.accounting_reference);
  assert.equal(migrated.history[0].changes.items_count, 2);

  const located = locateLegacyPrices(original);
  const sourcePaths = [
    ...located.topPaths,
    ...located.itemPaths,
    ...located.historyPaths,
  ];
  const expectedRawFields = Object.fromEntries(sourcePaths.map((sourcePath) => [
    sourcePath.join("."),
    valueAtPath(original, sourcePath),
  ]));
  const snapshot = first.state.restricted_snapshots["legacy-reconciled"];
  const archivedRawFields = Object.fromEntries(
      snapshot.legacy_source_price_fields.map((entry) => [
        entry.source_path,
        entry.raw_value,
      ]),
  );
  assert.equal(snapshot.legacy_source_price_fields.length, 7);
  assert.equal(checksum(archivedRawFields), checksum(expectedRawFields));
  assert.equal(
      snapshot.legacy_source_price_fields.filter(
          (entry) => entry.source_scope === "item" && entry.source_item_id,
      ).length,
      4,
  );
  const invoiceReport = first.report.invoices.find(
      (entry) => entry.invoice_id === "legacy-reconciled",
  );
  assert.equal(
      invoiceReport.non_price_before_checksum,
      invoiceReport.after_checksum,
  );

  const second = rehearseLegacyPriceMigration(first.state);
  assert.equal(second.report.migrated, 0);
  assert.equal(second.report.already_migrated, 1);
  assert.equal(second.report.snapshots_created, 0);
  assert.equal(second.report.restricted_history_created, 0);
  assert.equal(checksum(second.state), checksum(first.state));
});

test("conflicts retain every public price field and create no protected data", () => {
  const source = fixture();
  const beforeMissing = checksum(
      source.public_invoices["legacy-missing-currency"].data,
  );
  const beforeMismatch = checksum(
      source.public_invoices["legacy-total-conflict"].data,
  );
  const {state} = rehearseLegacyPriceMigration(source);

  assert.equal(
      checksum(state.public_invoices["legacy-missing-currency"].data),
      beforeMissing,
  );
  assert.equal(
      checksum(state.public_invoices["legacy-total-conflict"].data),
      beforeMismatch,
  );
  assert.equal(state.restricted_snapshots["legacy-missing-currency"], undefined);
  assert.equal(state.restricted_snapshots["legacy-total-conflict"], undefined);
});

test("unknown nested price-like aliases fail closed", () => {
  for (const key of [
    "supplier_cost",
    "total",
    "amount",
    "currency",
    "suggestion",
    "suggested",
  ]) {
    const source = fixture();
    source.public_invoices["legacy-reconciled"].data.receipt = {[key]: 1};
    const {state, report} = rehearseLegacyPriceMigration(source);
    const invoiceReport = report.invoices.find(
        (entry) => entry.invoice_id === "legacy-reconciled",
    );
    assert.equal(invoiceReport.outcome, "unknown_price_paths");
    assert.equal(report.unknown_price_paths, 1);
    assert.equal(state.restricted_snapshots["legacy-reconciled"], undefined);
  }
});

test("idempotent reruns reject partial or corrupt restricted state", () => {
  const first = rehearseLegacyPriceMigration(fixture());
  const invoiceId = "legacy-reconciled";
  const historyId = first.state.restricted_snapshots[invoiceId]
      .restricted_history_event_ids[0];

  const missingHistory = structuredClone(first.state);
  delete missingHistory.restricted_history[historyId];
  let rerun = rehearseLegacyPriceMigration(missingHistory);
  let invoiceReport = rerun.report.invoices.find(
      (entry) => entry.invoice_id === invoiceId,
  );
  assert.equal(invoiceReport.outcome, "existing_restricted_state_conflict");
  assert.equal(invoiceReport.conflict_code, "existing_restricted_history_invalid");
  assert.equal(rerun.report.conflicts, first.report.conflicts + 1);
  assert.equal(rerun.report.already_migrated, 0);

  const corruptTotal = structuredClone(first.state);
  corruptTotal.restricted_snapshots[invoiceId].total += 1;
  rerun = rehearseLegacyPriceMigration(corruptTotal);
  invoiceReport = rerun.report.invoices.find((entry) => entry.invoice_id === invoiceId);
  assert.equal(invoiceReport.outcome, "existing_restricted_state_conflict");
  assert.equal(invoiceReport.conflict_code, "existing_snapshot_total_invalid");
  assert.equal(rerun.report.conflicts, first.report.conflicts + 1);
  assert.equal(rerun.report.already_migrated, 0);

  const corruptHistory = structuredClone(first.state);
  const priceFields = corruptHistory.restricted_history[historyId].price_fields;
  const firstField = Object.keys(priceFields)[0];
  priceFields[firstField] += 1;
  rerun = rehearseLegacyPriceMigration(corruptHistory);
  invoiceReport = rerun.report.invoices.find((entry) => entry.invoice_id === invoiceId);
  assert.equal(invoiceReport.outcome, "existing_restricted_state_conflict");
  assert.equal(invoiceReport.conflict_code, "existing_restricted_history_invalid");
  assert.equal(rerun.report.conflicts, first.report.conflicts + 1);
  assert.equal(rerun.report.already_migrated, 0);
});

function valueAtPath(value, sourcePath) {
  return sourcePath.reduce((current, part) => current?.[part], value);
}
