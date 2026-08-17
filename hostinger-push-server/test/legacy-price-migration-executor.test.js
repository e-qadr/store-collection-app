"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  applyLegacyMigration,
  buildLegacyMigrationPlan,
  expectedConfirmation,
  expectedProductionConfirmation,
  inventoryPriceFields,
  loadLegacyInventory,
  readRestrictedState,
} = require("../legacy-price-migration-executor");
const {FakeFirestore} = require("./support/fake-firestore");

const PROJECT = "store-collection-production";
const ACTOR = "admin-migration";

function fixture() {
  const file = path.join(__dirname, "fixtures", "legacy-price-executor-fixture.json");
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function seedEntry(entry) {
  const seed = {
    users: {
      [ACTOR]: {role: "admin", isActive: true, mustChangePassword: false},
    },
    inter_branch_invoices: {[entry.header.id]: entry.header.data},
    inter_branch_invoice_events: Object.fromEntries(
        entry.history.map((document) => [document.id, document.data])),
    notifications: Object.fromEntries(
        entry.notifications.map((document) => [document.id, document.data])),
  };
  if (entry.items.length) {
    seed[`inter_branch_invoices/${entry.invoice_id}/items`] = Object.fromEntries(
        entry.items.map((document) => [document.id, document.data]));
  }
  return seed;
}

test("inventory covers headers, subcollection items, history, and notifications", () => {
  const ready = fixture().entries[0];
  const located = inventoryPriceFields(ready);
  assert.equal(located.unknown.length, 0);
  assert.equal(located.known.length, 8);
  const scopes = located.known.map((entry) => entry.scope);
  assert.equal(scopes.filter((scope) => scope === "header").length, 2);
  assert.equal(scopes.filter((scope) => scope === "item").length, 4);
  assert.equal(scopes.filter((scope) => scope === "history").length, 1);
  assert.equal(scopes.filter((scope) => scope === "notification").length, 1);
});

test("deterministic dry-run reports success, missing currency, malformed values, and conflicts", () => {
  const source = fixture();
  const first = buildLegacyMigrationPlan({entries: source.entries});
  const second = buildLegacyMigrationPlan({entries: source.entries});
  assert.equal(first.plan_checksum, second.plan_checksum);
  assert.deepEqual(first.counts, {
    scanned: 4, ready: 1, conflicts: 3,
    already_migrated: 0, no_prices: 0, price_fields: 16,
  });
  assert.equal(first.invoices.find((entry) =>
    entry.invoice_id === "legacy-ready").outcome, "ready");
  assert.equal(first.invoices.find((entry) =>
    entry.invoice_id === "legacy-missing-currency").conflict_code,
  "missing_or_unsupported_currency");
  assert.equal(first.invoices.find((entry) =>
    entry.invoice_id === "legacy-malformed").conflict_code,
  "missing_item_price");
  assert.equal(first.invoices.find((entry) =>
    entry.invoice_id === "legacy-conflict").conflict_code,
  "item_total_mismatch");
  const publicReport = JSON.stringify({counts: first.counts, invoices: first.invoices});
  assert.doesNotMatch(publicReport, /"unit_price"\s*:/);
  assert.doesNotMatch(publicReport, /"total_price"\s*:/);
});

test("unknown aliases fail closed without proposing public removal", () => {
  const ready = structuredClone(fixture().entries[0]);
  ready.notifications[0].data.supplier_cost = 123;
  const plan = buildLegacyMigrationPlan({entries: [ready]});
  assert.equal(plan.counts.conflicts, 1);
  assert.equal(plan.invoices[0].conflict_code, "unknown_price_paths");
  assert.deepEqual(plan.operations.get("legacy-ready").after, ready);
});

test("apply needs both confirmations, migrates atomically, and duplicate retry is idempotent", async () => {
  const ready = fixture().entries[0];
  const firestore = new FakeFirestore(seedEntry(ready));
  const entries = await loadLegacyInventory(firestore);
  const plan = buildLegacyMigrationPlan({entries});
  assert.equal(plan.counts.ready, 1);
  await assert.rejects(() => applyLegacyMigration({
    firestore, plan, projectId: PROJECT, confirmation: "wrong",
    productionConfirmation: expectedProductionConfirmation(PROJECT), actorUid: ACTOR,
  }), (error) => error.code === "apply-confirmation-mismatch");
  assert.equal(firestore.documents("inter_branch_invoice_prices").length, 0);

  const confirmation = expectedConfirmation({
    projectId: PROJECT, planChecksum: plan.plan_checksum,
  });
  await applyLegacyMigration({
    firestore, plan, projectId: PROJECT, confirmation,
    productionConfirmation: expectedProductionConfirmation(PROJECT), actorUid: ACTOR,
    clock: () => new Date("2026-08-06T10:00:00.000Z"),
  });
  const header = firestore.document("inter_branch_invoices", "legacy-ready");
  assert.equal(Object.hasOwn(header, "total_price"), false);
  assert.equal(Object.hasOwn(header, "currency"), false);
  for (const item of firestore.documents("inter_branch_invoices/legacy-ready/items")) {
    assert.equal(Object.hasOwn(item, "unit_price"), false);
    assert.equal(Object.hasOwn(item, "total_price"), false);
  }
  assert.equal(Object.hasOwn(
      firestore.document("notifications", "notification-a"), "unit_price"), false);
  assert.equal(firestore.documents("inter_branch_invoice_prices").length, 1);
  assert.equal(firestore.documents("inter_branch_invoice_price_history").length, 1);

  await applyLegacyMigration({
    firestore, plan, projectId: PROJECT, confirmation,
    productionConfirmation: expectedProductionConfirmation(PROJECT), actorUid: ACTOR,
    clock: () => new Date("2026-08-06T10:00:00.000Z"),
  });
  assert.equal(firestore.documents("inter_branch_invoice_prices").length, 1);
  assert.equal(firestore.documents("legacy_price_migration_manifests").length, 1);

  const rerunEntries = await loadLegacyInventory(firestore);
  const restricted = await readRestrictedState(firestore, ["legacy-ready"]);
  const rerun = buildLegacyMigrationPlan({
    entries: rerunEntries, restrictedState: restricted,
  });
  assert.equal(rerun.counts.already_migrated, 1);
  assert.equal(rerun.counts.ready, 0);
});

test("public drift after planning prevents protected writes and removal", async () => {
  const ready = fixture().entries[0];
  const firestore = new FakeFirestore(seedEntry(ready));
  const plan = buildLegacyMigrationPlan({entries: await loadLegacyInventory(firestore)});
  const header = firestore.document("inter_branch_invoices", "legacy-ready");
  firestore._collection("inter_branch_invoices").set("legacy-ready", {
    ...header, status: "changed-after-plan",
  });
  await assert.rejects(() => applyLegacyMigration({
    firestore, plan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, planChecksum: plan.plan_checksum,
    }),
    productionConfirmation: expectedProductionConfirmation(PROJECT), actorUid: ACTOR,
  }), (error) => error.code === "public-inventory-changed-after-plan");
  assert.equal(firestore.documents("inter_branch_invoice_prices").length, 0);
  assert.equal(Object.hasOwn(
      firestore.document("inter_branch_invoices", "legacy-ready"), "total_price"), true);
});
