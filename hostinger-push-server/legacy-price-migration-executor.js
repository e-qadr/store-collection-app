"use strict";

const fs = require("node:fs");
const {
  SUPPORTED_CURRENCIES,
  checksum,
  rehearseLegacyPriceMigration,
} = require("./legacy-price-migration");

const COLLECTIONS = Object.freeze({
  invoices: "inter_branch_invoices",
  events: "inter_branch_invoice_events",
  notifications: "notifications",
  restrictedPrices: "inter_branch_invoice_prices",
  restrictedHistory: "inter_branch_invoice_price_history",
  runState: "legacy_price_migration_run_state",
  manifests: "legacy_price_migration_manifests",
  users: "users",
});

const PRICE_LIKE_KEY = /(price|prices|total|cost|amount|currency|suggestion|suggested|سعر)/iu;
const KNOWN_PRICE_KEYS = new Set(["unit_price", "total_price"]);
const MAX_TRANSACTION_WRITES = 450;

function expectedConfirmation({projectId, planChecksum}) {
  return `APPLY_LEGACY_PRICE_MIGRATION:${projectId}:${planChecksum}`;
}

function expectedProductionConfirmation(projectId) {
  return `PRODUCTION_PROJECT:${projectId}`;
}

async function loadLegacyInventory(firestore) {
  const invoiceSnapshot = await firestore.collection(COLLECTIONS.invoices).get();
  const entries = [];
  for (const invoiceDocument of invoiceSnapshot.docs) {
    const header = invoiceDocument.data() || {};
    if (header.workflow_version === 2) continue;
    const [items, events, notifications] = await Promise.all([
      invoiceDocument.ref.collection("items").get(),
      firestore.collection(COLLECTIONS.events)
          .where("invoice_id", "==", invoiceDocument.id).get(),
      firestore.collection(COLLECTIONS.notifications)
          .where("inter_branch_invoice_id", "==", invoiceDocument.id).get(),
    ]);
    entries.push({
      invoice_id: invoiceDocument.id,
      header: documentEntry(invoiceDocument),
      items: items.docs.map(documentEntry),
      history: events.docs.map(documentEntry),
      notifications: notifications.docs.map(documentEntry),
    });
  }
  entries.sort((left, right) => left.invoice_id.localeCompare(right.invoice_id));
  return entries;
}

function documentEntry(snapshot) {
  return {id: snapshot.id, path: snapshot.ref.path, data: clone(snapshot.data())};
}

async function readRestrictedState(firestore, invoiceIds) {
  const snapshots = {};
  const history = {};
  for (const invoiceId of invoiceIds) {
    const snapshot = await firestore.collection(COLLECTIONS.restrictedPrices).doc(invoiceId).get();
    if (snapshot.exists) snapshots[invoiceId] = snapshot.data();
    const events = await firestore.collection(COLLECTIONS.restrictedHistory)
        .where("invoice_id", "==", invoiceId).get();
    for (const event of events.docs) history[event.id] = event.data();
  }
  return {snapshots, history};
}

function buildLegacyMigrationPlan({entries, currencyOverrides = {}, restrictedState = {}}) {
  const snapshots = restrictedState.snapshots || {};
  const restrictedHistory = restrictedState.history || {};
  const operations = new Map();
  const invoicePlans = [];
  for (const entry of [...entries].sort((a, b) =>
    a.invoice_id.localeCompare(b.invoice_id))) {
    const operation = planInvoice({
      entry,
      currencyOverride: currencyOverrides[entry.invoice_id],
      existingSnapshot: snapshots[entry.invoice_id],
      restrictedHistory,
    });
    operations.set(entry.invoice_id, operation);
    invoicePlans.push(operation.report);
  }
  const core = {
    schema_version: 1,
    invoices: invoicePlans,
  };
  const planChecksum = checksum(core);
  return {
    ...core,
    plan_checksum: planChecksum,
    counts: countOutcomes(invoicePlans),
    operations,
  };
}

function planInvoice({entry, currencyOverride, existingSnapshot, restrictedHistory}) {
  validateEntry(entry);
  const beforeChecksum = inventoryChecksum(entry);
  const located = inventoryPriceFields(entry);
  const baseReport = {
    invoice_id: entry.invoice_id,
    before_checksum: beforeChecksum,
    price_field_count: located.known.length,
    unknown_price_path_count: located.unknown.length,
    scopes: countScopes(located.known),
  };
  if (located.unknown.length) {
    return conflict(entry, baseReport, "unknown_price_paths");
  }
  const sanitized = sanitizeInventory(entry, located.known);
  const afterChecksum = inventoryChecksum(sanitized);
  if (located.known.length === 0) {
    if (!existingSnapshot) {
      return operation(entry, sanitized, {...baseReport, outcome: "no_prices",
        after_checksum: afterChecksum});
    }
    const source = existingSnapshot.source || {};
    const historyIds = existingSnapshot.restricted_history_event_ids || [];
    const historyComplete = historyIds.every((id) => restrictedHistory[id]);
    if (source.kind === "legacy_price_migration_executor" &&
        source.public_after_sha256 === afterChecksum && historyComplete) {
      return operation(entry, sanitized, {...baseReport, outcome: "already_migrated",
        after_checksum: afterChecksum});
    }
    return conflict(entry, baseReport, "existing_restricted_state_conflict");
  }

  const currency = resolveCurrency(entry.header.data, currencyOverride);
  if (!currency) return conflict(entry, baseReport, "missing_or_unsupported_currency");
  if (entry.header.data.items && entry.items.length) {
    return conflict(entry, baseReport, "duplicate_item_storage");
  }
  const writeCount = 2 + sanitized.items.length + sanitized.history.length +
    sanitized.notifications.length;
  if (writeCount > MAX_TRANSACTION_WRITES) {
    return conflict(entry, baseReport, "invoice_write_set_too_large");
  }

  const envelope = buildRehearsalEnvelope(entry);
  const fixture = {
    public_invoices: {
      [entry.invoice_id]: {migration_currency: currency, data: envelope},
    },
    restricted_snapshots: {},
    restricted_history: {},
  };
  const rehearsal = rehearseLegacyPriceMigration(fixture);
  const rehearsalInvoice = rehearsal.report.invoices[0];
  if (rehearsalInvoice?.outcome !== "migrated") {
    return conflict(entry, baseReport,
        rehearsalInvoice?.conflict_code || rehearsalInvoice?.outcome || "reconciliation_failed");
  }
  const snapshot = clone(rehearsal.state.restricted_snapshots[entry.invoice_id]);
  const history = Object.values(rehearsal.state.restricted_history);
  snapshot.legacy_source_price_fields = located.known.map((field) => ({
    source_scope: field.scope,
    source_document_id: field.document_id,
    source_path: field.path.join("."),
    source_field: field.path[field.path.length - 1],
    raw_value: clone(field.value),
  }));
  snapshot.source = {
    kind: "legacy_price_migration_executor",
    public_before_sha256: beforeChecksum,
    public_after_sha256: afterChecksum,
  };
  snapshot.currency = currency;
  const protectedChecksum = checksum({snapshot, history});
  if (existingSnapshot && checksum(existingSnapshot) !== checksum(snapshot)) {
    return conflict(entry, baseReport, "restricted_snapshot_conflict");
  }
  for (const event of history) {
    if (restrictedHistory[event.id] &&
        checksum(restrictedHistory[event.id]) !== checksum(event)) {
      return conflict(entry, baseReport, "restricted_history_conflict");
    }
  }
  return operation(entry, sanitized, {
    ...baseReport,
    outcome: "ready",
    currency,
    after_checksum: afterChecksum,
    protected_checksum: protectedChecksum,
  }, {snapshot, history});
}

function buildRehearsalEnvelope(entry) {
  const header = clone(entry.header.data);
  delete header.currency;
  if (!Array.isArray(header.items) && entry.items.length) {
    header.items = entry.items.map((item) => clone(item.data));
  }
  const embeddedHistory = Array.isArray(header.history) ? header.history : [];
  const externalHistory = entry.history.map((event) => clone(event.data));
  if (externalHistory.length) header.history = [...embeddedHistory, ...externalHistory];
  return header;
}

function inventoryPriceFields(entry) {
  const known = [];
  const unknown = [];
  for (const descriptor of inventoryDocuments(entry)) {
    walk(descriptor.data, [], (path, key, value) => {
      const fullPath = [...path, key];
      const isHeaderCurrency = descriptor.scope === "header" &&
        fullPath.length === 1 && key === "currency";
      if (KNOWN_PRICE_KEYS.has(key) || isHeaderCurrency) {
        const effectiveScope = descriptor.scope === "header" && fullPath[0] === "items" ?
          "item" : descriptor.scope === "header" && fullPath[0] === "history" ?
            "history" : descriptor.scope;
        known.push({document_id: descriptor.id, document_scope: descriptor.scope,
          scope: effectiveScope, path: fullPath, value: clone(value)});
      } else if (PRICE_LIKE_KEY.test(key)) {
        unknown.push({scope: descriptor.scope, document_id: descriptor.id,
          path: fullPath.join(".")});
      }
    });
  }
  known.sort(compareLocated);
  unknown.sort((a, b) => stableJson(a).localeCompare(stableJson(b)));
  return {known, unknown};
}

function inventoryDocuments(entry) {
  return [
    {...entry.header, scope: "header"},
    ...entry.items.map((item) => ({...item, scope: "item"})),
    ...entry.history.map((item) => ({...item, scope: "history"})),
    ...entry.notifications.map((item) => ({...item, scope: "notification"})),
  ];
}

function sanitizeInventory(entry, located) {
  const result = clone(entry);
  const documents = new Map(inventoryDocuments(result).map((document) => [
    `${document.scope}:${document.id}`, document.data,
  ]));
  for (const field of located) {
    const data = documents.get(`${field.document_scope}:${field.document_id}`);
    deleteAtPath(data, field.path);
  }
  if (inventoryChecksum(removeKnownPrices(entry)) !== inventoryChecksum(result)) {
    throw codedError("non-price-data-changed");
  }
  return result;
}

function removeKnownPrices(entry) {
  const result = clone(entry);
  const located = inventoryPriceFields(result);
  const documents = new Map(inventoryDocuments(result).map((document) => [
    `${document.scope}:${document.id}`, document.data,
  ]));
  for (const field of located.known) {
    deleteAtPath(documents.get(`${field.document_scope}:${field.document_id}`), field.path);
  }
  return result;
}

function resolveCurrency(header, override) {
  const value = String(override || header.currency || "").trim().toUpperCase();
  return SUPPORTED_CURRENCIES.has(value) ? value : undefined;
}

function conflict(entry, report, code) {
  return operation(entry, entry, {...report, outcome: "conflict", conflict_code: code});
}

function operation(before, after, report, protectedWrites = {}) {
  return {before: clone(before), after: clone(after), report,
    snapshot: protectedWrites.snapshot, history: protectedWrites.history || []};
}

function countOutcomes(reports) {
  const counts = {scanned: reports.length, ready: 0, conflicts: 0,
    already_migrated: 0, no_prices: 0, price_fields: 0};
  for (const report of reports) {
    counts.price_fields += report.price_field_count;
    if (report.outcome === "ready") counts.ready += 1;
    else if (report.outcome === "conflict") counts.conflicts += 1;
    else if (report.outcome === "already_migrated") counts.already_migrated += 1;
    else if (report.outcome === "no_prices") counts.no_prices += 1;
  }
  return counts;
}

function countScopes(fields) {
  const counts = {header: 0, item: 0, history: 0, notification: 0};
  for (const field of fields) counts[field.scope] += 1;
  return counts;
}

function inventoryChecksum(entry) {
  return checksum({
    invoice_id: entry.invoice_id,
    header: {id: entry.header.id, data: entry.header.data},
    items: sortDocuments(entry.items),
    history: sortDocuments(entry.history),
    notifications: sortDocuments(entry.notifications),
  });
}

function sortDocuments(documents) {
  return [...documents].sort((a, b) => a.id.localeCompare(b.id))
      .map((document) => ({id: document.id, data: document.data}));
}

async function applyLegacyMigration({firestore, plan, projectId, confirmation,
  productionConfirmation, actorUid, clock = () => new Date()}) {
  if (confirmation !== expectedConfirmation({
    projectId, planChecksum: plan.plan_checksum,
  })) throw codedError("apply-confirmation-mismatch");
  if (productionConfirmation !== expectedProductionConfirmation(projectId)) {
    throw codedError("production-confirmation-mismatch");
  }
  const actorSnapshot = await firestore.collection(COLLECTIONS.users).doc(actorUid).get();
  const actor = actorSnapshot.data() || {};
  if (!actorSnapshot.exists || !["admin", "accountant"].includes(actor.role) ||
      actor.isActive === false || actor.mustChangePassword === true) {
    throw codedError("active-admin-or-accountant-required");
  }
  if (plan.counts.conflicts) throw codedError("migration-conflicts-block-apply");
  const runId = `legacy-price-migration-${plan.plan_checksum.slice(0, 40)}`;
  const stateRef = firestore.collection(COLLECTIONS.runState).doc(runId);
  await firestore.runTransaction(async (transaction) => {
    const current = await transaction.get(stateRef);
    if (current.exists && current.data()?.plan_checksum !== plan.plan_checksum) {
      throw codedError("migration-run-state-conflict");
    }
    transaction.set(stateRef, {
      schema_version: 1, id: runId, plan_checksum: plan.plan_checksum,
      status: "applying", actor_uid: actorUid,
      started_at: current.data()?.started_at || clock(), updated_at: clock(),
      completed_invoice_ids: current.data()?.completed_invoice_ids || [],
    });
  });
  for (const invoiceReport of plan.invoices) {
    if (invoiceReport.outcome !== "ready") continue;
    const operation = plan.operations.get(invoiceReport.invoice_id);
    await applyInvoiceOperation({firestore, operation, clock});
    await migrationCheckpoint({firestore, stateRef, plan, invoiceId: invoiceReport.invoice_id, clock});
  }
  const manifestRef = firestore.collection(COLLECTIONS.manifests).doc(runId);
  await firestore.runTransaction(async (transaction) => {
    const [manifest, state] = await Promise.all([
      transaction.get(manifestRef), transaction.get(stateRef),
    ]);
    if (manifest.exists && manifest.data()?.plan_checksum !== plan.plan_checksum) {
      throw codedError("migration-manifest-conflict");
    }
    const completedAt = manifest.data()?.completed_at || clock();
    if (!manifest.exists) {
      transaction.set(manifestRef, {
        schema_version: 1, id: runId, plan_checksum: plan.plan_checksum,
        status: "completed", actor_uid: actorUid, counts: plan.counts,
        invoice_reports: plan.invoices, started_at: state.data()?.started_at,
        completed_at: completedAt,
      });
    }
    transaction.set(stateRef, {...state.data(), status: "completed",
      updated_at: clock(), completed_at: completedAt});
  });
  return {run_id: runId, status: "completed", counts: plan.counts};
}

async function applyInvoiceOperation({firestore, operation, clock}) {
  const invoiceId = operation.before.invoice_id;
  await firestore.runTransaction(async (transaction) => {
    const refs = operationReferences(firestore, operation.before);
    const currentSnapshots = await Promise.all(refs.map((entry) =>
      transaction.get(entry.reference)));
    const currentEntry = rebuildEntry(operation.before, currentSnapshots);
    const currentChecksum = inventoryChecksum(currentEntry);
    const beforeChecksum = inventoryChecksum(operation.before);
    const afterChecksum = inventoryChecksum(operation.after);
    if (currentChecksum !== beforeChecksum && currentChecksum !== afterChecksum) {
      throw codedError("public-inventory-changed-after-plan");
    }
    const snapshotRef = firestore.collection(COLLECTIONS.restrictedPrices).doc(invoiceId);
    const existingSnapshot = await transaction.get(snapshotRef);
    if (existingSnapshot.exists &&
        checksum(existingSnapshot.data()) !== checksum(operation.snapshot)) {
      throw codedError("restricted-snapshot-changed-after-plan");
    }
    if (!existingSnapshot.exists) transaction.set(snapshotRef, operation.snapshot);
    for (const event of operation.history) {
      const reference = firestore.collection(COLLECTIONS.restrictedHistory).doc(event.id);
      const existing = await transaction.get(reference);
      if (existing.exists && checksum(existing.data()) !== checksum(event)) {
        throw codedError("restricted-history-changed-after-plan");
      }
      if (!existing.exists) transaction.set(reference, event);
    }
    if (currentChecksum === afterChecksum) return;
    for (const write of operationReferences(firestore, operation.after)) {
      transaction.set(write.reference, write.data);
    }
    const afterRecheck = clone(operation.after);
    if (inventoryChecksum(afterRecheck) !== operation.report.after_checksum) {
      throw codedError("public-after-integrity-failed");
    }
  });
}

function operationReferences(firestore, entry) {
  return [
    {kind: "header", id: entry.header.id,
      reference: firestore.collection(COLLECTIONS.invoices).doc(entry.header.id),
      data: entry.header.data},
    ...entry.items.map((item) => ({kind: "item", id: item.id,
      reference: firestore.collection(COLLECTIONS.invoices).doc(entry.invoice_id)
          .collection("items").doc(item.id), data: item.data})),
    ...entry.history.map((event) => ({kind: "history", id: event.id,
      reference: firestore.collection(COLLECTIONS.events).doc(event.id), data: event.data})),
    ...entry.notifications.map((notification) => ({kind: "notification", id: notification.id,
      reference: firestore.collection(COLLECTIONS.notifications).doc(notification.id),
      data: notification.data})),
  ];
}

function rebuildEntry(template, snapshots) {
  let index = 0;
  const take = () => {
    const snapshot = snapshots[index++];
    if (!snapshot.exists) throw codedError("public-document-missing-after-plan");
    return {id: snapshot.id, path: snapshot.ref.path, data: snapshot.data()};
  };
  return {
    invoice_id: template.invoice_id,
    header: take(),
    items: template.items.map(take),
    history: template.history.map(take),
    notifications: template.notifications.map(take),
  };
}

async function migrationCheckpoint({firestore, stateRef, plan, invoiceId, clock}) {
  await firestore.runTransaction(async (transaction) => {
    const state = await transaction.get(stateRef);
    if (!state.exists || state.data()?.plan_checksum !== plan.plan_checksum) {
      throw codedError("migration-run-state-missing");
    }
    const completed = new Set(state.data().completed_invoice_ids || []);
    completed.add(invoiceId);
    transaction.set(stateRef, {...state.data(),
      completed_invoice_ids: [...completed].sort(), updated_at: clock()});
  });
}

function validateEntry(entry) {
  if (!entry?.invoice_id || !entry.header?.data || entry.header.id !== entry.invoice_id) {
    throw codedError("invalid-inventory-entry");
  }
}

function compareLocated(left, right) {
  return `${left.scope}:${left.document_id}:${left.path.join(".")}`.localeCompare(
      `${right.scope}:${right.document_id}:${right.path.join(".")}`,
  );
}

function walk(value, path, visitor) {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    value.forEach((child, index) => walk(child, [...path, index], visitor));
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    visitor(path, key, child);
    walk(child, [...path, key], visitor);
  }
}

function deleteAtPath(value, path) {
  let current = value;
  for (let index = 0; index < path.length - 1; index += 1) {
    current = current?.[path[index]];
  }
  if (current && typeof current === "object") delete current[path[path.length - 1]];
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

function codedError(code) {
  return Object.assign(new Error(code), {code});
}

function parseArguments(arguments_) {
  const options = {};
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--apply") {
      options.apply = true;
      continue;
    }
    if (!argument.startsWith("--") || index + 1 >= arguments_.length) {
      throw codedError("invalid-command-line");
    }
    options[argument.slice(2)] = arguments_[++index];
  }
  return options;
}

async function createAdminFirestore(projectId) {
  const admin = require("firebase-admin");
  if (admin.apps.length === 0) {
    admin.initializeApp({credential: admin.credential.applicationDefault(), projectId});
  }
  return admin.firestore();
}

async function main(arguments_ = process.argv.slice(2)) {
  const options = parseArguments(arguments_);
  if (options.fixture) {
    if (options.apply) throw codedError("fixture-apply-forbidden");
    const fixture = JSON.parse(fs.readFileSync(options.fixture, "utf8"));
    const plan = buildLegacyMigrationPlan({
      entries: fixture.entries || [],
      currencyOverrides: fixture.currency_overrides || {},
      restrictedState: fixture.restricted_state || {},
    });
    const report = {
      mode: "local_fixture_dry_run",
      writes_performed: false,
      plan_checksum: plan.plan_checksum,
      counts: plan.counts,
      invoices: plan.invoices,
    };
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return report;
  }
  for (const required of ["project-id", "actor-uid"]) {
    if (!String(options[required] || "").trim()) throw codedError(`missing-${required}`);
  }
  const firestore = await createAdminFirestore(options["project-id"]);
  const entries = await loadLegacyInventory(firestore);
  const restrictedState = await readRestrictedState(
      firestore, entries.map((entry) => entry.invoice_id),
  );
  const currencyOverrides = options["currency-map"] ?
    JSON.parse(fs.readFileSync(options["currency-map"], "utf8")) : {};
  const plan = buildLegacyMigrationPlan({entries, currencyOverrides, restrictedState});
  const publicPlan = {
    mode: options.apply ? "apply" : "dry_run",
    plan_checksum: plan.plan_checksum,
    counts: plan.counts,
    invoices: plan.invoices,
    required_confirmation: expectedConfirmation({
      projectId: options["project-id"], planChecksum: plan.plan_checksum,
    }),
    required_production_confirmation:
      expectedProductionConfirmation(options["project-id"]),
  };
  if (!options.apply) {
    process.stdout.write(`${JSON.stringify(publicPlan, null, 2)}\n`);
    return publicPlan;
  }
  const result = await applyLegacyMigration({
    firestore, plan, projectId: options["project-id"],
    confirmation: options.confirm,
    productionConfirmation: options["production-confirm"],
    actorUid: options["actor-uid"],
  });
  process.stdout.write(`${JSON.stringify({...publicPlan, ...result}, null, 2)}\n`);
  return result;
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.code || "legacy-price-migration-failed"}\n`);
    process.exitCode = 2;
  });
}

module.exports = {
  COLLECTIONS,
  applyLegacyMigration,
  buildLegacyMigrationPlan,
  expectedConfirmation,
  expectedProductionConfirmation,
  inventoryPriceFields,
  loadLegacyInventory,
  readRestrictedState,
};
