"use strict";

const crypto = require("node:crypto");
const {invoiceItemDigest} = require("./inter-branch-invoice-domain");

const SUPPORTED_CURRENCIES = new Set(["YER", "SAR", "USD"]);
const PUBLIC_PRICE_KEYS = new Set(["unit_price", "total_price"]);
const PRICE_LIKE_KEY =
  /(price|prices|total|cost|amount|currency|suggestion|suggested)/i;
const V2_PUBLIC_ITEM_KEYS = new Set([
  "id", "invoice_id", "schema_version", "workflow_version", "creation_mode",
  "invoice_revision", "branch_ids", "sending_branch_id", "receiving_branch_id",
  "line_number", "item_id", "product_id", "product_version", "product_brand_id",
  "product_name", "group_id", "group_name", "product_legacy_code",
  "group_legacy_code", "unit_id", "unit_value", "unit_raw_value",
  "supplied_quantity", "line_notes", "received_quantity", "damaged_quantity",
  "missing_quantity", "discrepancy_notes",
]);
const V2_PUBLIC_ITEM_REQUIRED_KEYS = new Set([
  "id", "invoice_id", "schema_version", "workflow_version", "creation_mode",
  "invoice_revision", "branch_ids", "sending_branch_id", "receiving_branch_id",
  "line_number", "item_id", "product_id", "product_version", "product_brand_id",
  "product_name", "group_id", "group_name", "unit_id", "unit_value",
  "unit_raw_value", "supplied_quantity",
]);

function assertFirestoreEmulatorOnly({
  environment = process.env,
  projectId,
} = {}) {
  const emulatorHost = String(environment.FIRESTORE_EMULATOR_HOST || "").trim();
  const cleanProjectId = String(projectId || environment.GCLOUD_PROJECT || "").trim();
  if (!emulatorHost) {
    throw codedError("emulator-required");
  }
  if (!/^(demo-|local-)/.test(cleanProjectId)) {
    throw codedError("local-project-required");
  }
  if (!/^(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/.test(emulatorHost)) {
    throw codedError("local-emulator-host-required");
  }
  return {emulatorHost, projectId: cleanProjectId};
}

function rehearseLegacyPriceMigration(fixture, {tolerance = 1e-6} = {}) {
  const input = fixture && typeof fixture === "object" ? fixture : {};
  const state = {
    public_invoices: clone(input.public_invoices || {}),
    // Phase-2 line documents are already price-free. A legacy price rehearsal
    // must preserve them byte-for-byte and must never fold them into headers.
    public_invoice_items: clone(input.public_invoice_items || {}),
    restricted_snapshots: clone(input.restricted_snapshots || {}),
    restricted_history: clone(input.restricted_history || {}),
  };
  const beforeState = clone(state);
  const report = {
    mode: "local_fixture_rehearsal",
    scanned: 0,
    containing_prices: 0,
    reconciled: 0,
    migrated: 0,
    already_migrated: 0,
    conflicts: 0,
    missing_currency: 0,
    unknown_price_paths: 0,
    public_price_fields_removed: 0,
    snapshots_created: 0,
    restricted_history_created: 0,
    before_checksum: checksum(beforeState),
    invoices: [],
  };

  const entries = normalizePublicInvoices(state.public_invoices);
  report.scanned = entries.length;
  for (const entry of entries) {
    const result = migrateOne({
      invoiceId: entry.id,
      publicInvoice: entry.data,
      migrationCurrency: entry.migrationCurrency,
      state,
      tolerance,
    });
    report.invoices.push(result.report);
    for (const key of [
      "containing_prices",
      "reconciled",
      "migrated",
      "already_migrated",
      "conflicts",
      "missing_currency",
      "unknown_price_paths",
      "public_price_fields_removed",
      "snapshots_created",
      "restricted_history_created",
    ]) {
      report[key] += result.counts[key] || 0;
    }
  }

  report.invoices.sort((left, right) => left.invoice_id.localeCompare(right.invoice_id));
  report.after_checksum = checksum(state);
  report.public_before_checksum = checksum(beforeState.public_invoices);
  report.public_after_checksum = checksum(state.public_invoices);
  report.restricted_after_checksum = checksum({
    restricted_snapshots: state.restricted_snapshots,
    restricted_history: state.restricted_history,
  });
  return {state, report};
}

function validateV2PublicItemFixture(fixture) {
  const input = fixture && typeof fixture === "object" ? fixture : {};
  const invoices = input.public_invoices || {};
  const itemCollections = input.public_invoice_items || {};
  const report = {invoices: 0, items: 0, invoice_checksums: {}};
  for (const [invoiceId, rawEntry] of Object.entries(invoices)) {
    const header = rawEntry?.data || rawEntry;
    if (!header || header.workflow_version !== 2 || header.schema_version !== 2) {
      continue;
    }
    if (Object.hasOwn(header, "items")) throw codedError("v2-embedded-items-forbidden");
    if (header.id !== invoiceId || !Number.isSafeInteger(header.revision) ||
        header.revision < 1 || !Number.isSafeInteger(header.item_count) ||
        header.item_count < 1 || header.item_count > 50 ||
        !isSha256(header.item_digest)) {
      throw codedError("v2-header-invalid");
    }
    const rawItems = itemCollections[invoiceId];
    const items = Array.isArray(rawItems) ? rawItems :
      rawItems && typeof rawItems === "object" ? Object.values(rawItems) : [];
    if (items.length !== header.item_count) throw codedError("v2-item-count-mismatch");
    const itemIds = new Set();
    const lines = new Set();
    const productUnits = new Set();
    for (const item of items) {
      validateV2FixtureItem({invoiceId, header, item});
      const productUnit = `${item.product_id}\u0000${item.unit_id}`;
      if (itemIds.has(item.item_id) || lines.has(item.line_number) ||
          productUnits.has(productUnit)) {
        throw codedError("v2-item-duplicate");
      }
      itemIds.add(item.item_id);
      lines.add(item.line_number);
      productUnits.add(productUnit);
    }
    for (let line = 1; line <= items.length; line += 1) {
      if (!lines.has(line)) throw codedError("v2-line-sequence-invalid");
    }
    if (invoiceItemDigest(items) !== header.item_digest) {
      throw codedError("v2-item-digest-mismatch");
    }
    report.invoices += 1;
    report.items += items.length;
    report.invoice_checksums[invoiceId] = checksum({header, items});
  }
  if (report.invoices === 0) throw codedError("v2-fixture-empty");
  return report;
}

function validateV2FixtureItem({invoiceId, header, item}) {
  if (!item || typeof item !== "object" || Array.isArray(item)) {
    throw codedError("v2-item-invalid");
  }
  let priceLike = false;
  walk(item, [], (_path, key) => {
    if (PRICE_LIKE_KEY.test(key)) priceLike = true;
  });
  if (priceLike) throw codedError("v2-item-price-field-forbidden");
  const keys = Object.keys(item);
  if (keys.some((key) => !V2_PUBLIC_ITEM_KEYS.has(key)) ||
      [...V2_PUBLIC_ITEM_REQUIRED_KEYS].some((key) => !Object.hasOwn(item, key))) {
    throw codedError("v2-item-schema-invalid");
  }
  if (item.id !== item.item_id || item.invoice_id !== invoiceId ||
      item.schema_version !== 2 || item.workflow_version !== 2 ||
      item.creation_mode !== "direct_supplier_invoice" ||
      item.invoice_revision !== header.revision ||
      checksum(item.branch_ids) !== checksum(header.branch_ids) ||
      item.sending_branch_id !== header.sending_branch_id ||
      item.receiving_branch_id !== header.receiving_branch_id ||
      !Number.isSafeInteger(item.line_number) || item.line_number < 1 ||
      item.line_number > header.item_count ||
      typeof item.product_id !== "string" || !item.product_id ||
      typeof item.unit_id !== "string" || !item.unit_id ||
      typeof item.supplied_quantity !== "number" ||
      !Number.isFinite(item.supplied_quantity) || item.supplied_quantity <= 0) {
    throw codedError("v2-item-identity-invalid");
  }
}

function migrateOne({
  invoiceId,
  publicInvoice,
  migrationCurrency,
  state,
  tolerance,
}) {
  const counts = emptyCounts();
  const original = clone(publicInvoice);
  const existingSnapshot = state.restricted_snapshots[invoiceId];
  const located = locateLegacyPrices(original);
  if (located.priceFieldCount > 0) counts.containing_prices = 1;

  const baseReport = {
    invoice_id: invoiceId,
    outcome: "no_prices",
    located_top_level_fields: located.topLevelCount,
    located_item_fields: located.itemCount,
    located_history_fields: located.historyCount,
    unknown_price_path_count: located.unknownPaths.length,
    before_checksum: checksum(original),
  };

  if (located.unknownPaths.length > 0) {
    counts.conflicts = 1;
    counts.unknown_price_paths = located.unknownPaths.length;
    return finish(baseReport, counts, original, "unknown_price_paths");
  }

  if (located.priceFieldCount === 0) {
    if (existingSnapshot) {
      const conflictCode = validateExistingMigrationState({
        invoiceId,
        publicInvoice: original,
        snapshot: existingSnapshot,
        restrictedHistory: state.restricted_history,
        tolerance,
      });
      if (conflictCode) {
        counts.conflicts = 1;
        return finish(
            {...baseReport, conflict_code: conflictCode},
            counts,
            original,
            "existing_restricted_state_conflict",
        );
      }
      counts.already_migrated = 1;
      return finish(baseReport, counts, original, "already_migrated");
    }
    return finish(baseReport, counts, original, "no_prices");
  }

  const currency = String(migrationCurrency || "").trim().toUpperCase();
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    counts.conflicts = 1;
    counts.missing_currency = 1;
    return finish(baseReport, counts, original, "missing_or_unsupported_currency");
  }

  let protectedData;
  try {
    protectedData = buildProtectedData({
      invoiceId,
      invoice: original,
      currency,
      located,
      tolerance,
    });
  } catch (error) {
    counts.conflicts = 1;
    return finish(
        {...baseReport, conflict_code: error.code || "reconciliation_failed"},
        counts,
        original,
        "reconciliation_conflict",
    );
  }

  counts.reconciled = 1;
  if (existingSnapshot && checksum(existingSnapshot) !== checksum(protectedData.snapshot)) {
    counts.conflicts = 1;
    return finish(baseReport, counts, original, "restricted_snapshot_conflict");
  }
  for (const event of protectedData.historyEvents) {
    const existing = state.restricted_history[event.id];
    if (existing && checksum(existing) !== checksum(event)) {
      counts.conflicts = 1;
      return finish(baseReport, counts, original, "restricted_history_conflict");
    }
  }

  const publicAfter = removeLocatedPriceFields(original, located);
  const nonPriceBefore = stripKnownPublicPrices(original);
  if (checksum(nonPriceBefore) !== checksum(publicAfter)) {
    throw codedError("non-price-data-changed");
  }

  if (!existingSnapshot) {
    state.restricted_snapshots[invoiceId] = protectedData.snapshot;
    counts.snapshots_created = 1;
  }
  for (const event of protectedData.historyEvents) {
    if (!state.restricted_history[event.id]) {
      state.restricted_history[event.id] = event;
      counts.restricted_history_created += 1;
    }
  }
  assignPublicInvoice(state.public_invoices, invoiceId, publicAfter);
  counts.public_price_fields_removed = located.priceFieldCount;
  counts.migrated = 1;
  return finish({
    ...baseReport,
    protected_snapshot_checksum: checksum(protectedData.snapshot),
    non_price_before_checksum: checksum(nonPriceBefore),
  }, counts, publicAfter, "migrated");
}

function buildProtectedData({invoiceId, invoice, currency, located, tolerance}) {
  const rawItems = Array.isArray(invoice.items) && invoice.items.length > 0 ?
    invoice.items : [invoice];
  const topUnitPrice = finiteNumber(invoice.unit_price);
  const topTotal = finiteNumber(invoice.total_price);
  const protectedItems = rawItems.map((item, index) => {
    const quantity = firstFiniteNumber(
        item.received_quantity,
        item.approved_quantity,
        item.requested_quantity,
        invoice.received_quantity,
        invoice.approved_quantity,
        invoice.requested_quantity,
    );
    let unitPrice = finiteNumber(item.unit_price);
    if (unitPrice === undefined && rawItems.length === 1) unitPrice = topUnitPrice;
    if (quantity === undefined || quantity < 0) throw codedError("missing_quantity");
    if (unitPrice === undefined || unitPrice < 0) throw codedError("missing_item_price");
    const computedTotal = quantity * unitPrice;
    const itemTotal = finiteNumber(item.total_price);
    if (itemTotal !== undefined && !near(itemTotal, computedTotal, tolerance)) {
      throw codedError("item_total_mismatch");
    }
    return compact({
      item_id: nonEmpty(item.item_id) || deterministicItemId(invoiceId, index),
      product_id: nonEmpty(item.product_id),
      product_brand_id: nonEmpty(item.product_brand_id),
      product_name: nonEmpty(item.product_name) || nonEmpty(item.name) ||
        nonEmpty(item.item_name),
      unit_id: nonEmpty(item.unit_id),
      unit_value: nonEmpty(item.unit_value) || nonEmpty(item.unit),
      confirmed_quantity: quantity,
      unit_price: unitPrice,
      line_total: computedTotal,
    });
  });
  const computedInvoiceTotal = protectedItems.reduce(
      (sum, item) => sum + item.line_total,
      0,
  );
  if (topTotal !== undefined && !near(topTotal, computedInvoiceTotal, tolerance)) {
    throw codedError("invoice_total_mismatch");
  }
  if (topUnitPrice !== undefined && protectedItems.length === 1 &&
      !near(topUnitPrice, protectedItems[0].unit_price, tolerance)) {
    throw codedError("top_level_price_mismatch");
  }

  const sourceChecksum = checksum(invoice);
  const publicAfterChecksum = checksum(removeLocatedPriceFields(invoice, located));
  const legacySourcePriceFields = buildLegacySourcePriceFields({
    invoiceId,
    invoice,
    located,
    protectedItems,
  });
  const historyEvents = located.historyEntries.map((entry) => {
    const id = deterministicHistoryId(invoiceId, entry.index, entry.priceFields);
    const rawHistory = invoice.history[entry.index] || {};
    return compact({
      id,
      invoice_id: invoiceId,
      event_type: "legacy_price_history_migrated",
      source_history_index: entry.index,
      source_action: nonEmpty(rawHistory.action),
      source_actor_id: nonEmpty(rawHistory.actor_id),
      source_actor_role: nonEmpty(rawHistory.actor_role),
      source_timestamp: rawHistory.timestamp,
      price_fields: clone(entry.priceFields),
      source_event_sha256: checksum(rawHistory),
    });
  });
  const snapshot = {
    id: invoiceId,
    invoice_id: invoiceId,
    schema_version: 1,
    workflow_version: Number.isInteger(invoice.workflow_version) ?
      invoice.workflow_version : 1,
    invoice_revision: Number.isInteger(invoice.revision) ? invoice.revision : 1,
    pricing_revision: 1,
    currency,
    items: protectedItems,
    total: computedInvoiceTotal,
    legacy_source_price_fields: legacySourcePriceFields,
    restricted_history_event_ids: historyEvents.map((event) => event.id),
    locked: invoice.status === "postedToAccounting" ||
      invoice.status === "approvedByAccountant",
    source: {
      kind: "legacy_price_migration_rehearsal",
      public_before_sha256: sourceChecksum,
      public_after_sha256: publicAfterChecksum,
    },
  };
  return {snapshot, historyEvents};
}

function validateExistingMigrationState({
  invoiceId,
  publicInvoice,
  snapshot,
  restrictedHistory,
  tolerance,
}) {
  if (!snapshot || typeof snapshot !== "object" ||
      snapshot.id !== invoiceId || snapshot.invoice_id !== invoiceId ||
      !SUPPORTED_CURRENCIES.has(snapshot.currency) ||
      !Array.isArray(snapshot.items) || snapshot.items.length === 0 ||
      !Array.isArray(snapshot.legacy_source_price_fields) ||
      snapshot.legacy_source_price_fields.length === 0 ||
      !Array.isArray(snapshot.restricted_history_event_ids) ||
      !snapshot.source ||
      snapshot.source.kind !== "legacy_price_migration_rehearsal" ||
      !isSha256(snapshot.source.public_before_sha256) ||
      !isSha256(snapshot.source.public_after_sha256) ||
      snapshot.source.public_after_sha256 !== checksum(publicInvoice)) {
    return "existing_snapshot_invalid";
  }

  let calculatedTotal = 0;
  for (const item of snapshot.items) {
    if (!item || typeof item !== "object" ||
        !nonEmpty(item.item_id) ||
        finiteNumber(item.confirmed_quantity) === undefined ||
        item.confirmed_quantity < 0 ||
        finiteNumber(item.unit_price) === undefined || item.unit_price < 0 ||
        finiteNumber(item.line_total) === undefined || item.line_total < 0 ||
        !near(item.line_total, item.confirmed_quantity * item.unit_price, tolerance)) {
      return "existing_snapshot_items_invalid";
    }
    calculatedTotal += item.line_total;
  }
  if (finiteNumber(snapshot.total) === undefined ||
      !near(snapshot.total, calculatedTotal, tolerance)) {
    return "existing_snapshot_total_invalid";
  }

  const restored = clone(publicInvoice);
  const historyPriceFields = new Map();
  const archivedPaths = new Set();
  for (const entry of snapshot.legacy_source_price_fields) {
    const sourcePath = nonEmpty(entry?.source_path);
    if (!sourcePath || archivedPaths.has(sourcePath) ||
        !Object.prototype.hasOwnProperty.call(entry, "raw_value")) {
      return "existing_snapshot_archive_invalid";
    }
    archivedPaths.add(sourcePath);
    const parts = sourcePath.split(".").map((part) =>
      /^\d+$/.test(part) ? Number(part) : part);
    if (!setAtPath(restored, parts, clone(entry.raw_value))) {
      return "existing_snapshot_archive_invalid";
    }
    if (entry.source_scope === "history" && Number.isInteger(entry.source_index)) {
      const fields = historyPriceFields.get(entry.source_index) || {};
      fields[parts[parts.length - 1]] = clone(entry.raw_value);
      historyPriceFields.set(entry.source_index, fields);
    }
  }
  if (checksum(restored) !== snapshot.source.public_before_sha256) {
    return "existing_snapshot_source_checksum_mismatch";
  }

  const historyIds = snapshot.restricted_history_event_ids;
  if (new Set(historyIds).size !== historyIds.length ||
      historyIds.length !== historyPriceFields.size) {
    return "existing_restricted_history_invalid";
  }
  for (const id of historyIds) {
    const event = restrictedHistory?.[id];
    const expectedFields = historyPriceFields.get(event?.source_history_index);
    const sourceEvent = restored.history?.[event?.source_history_index];
    if (!nonEmpty(id) || !event || event.id !== id ||
        event.invoice_id !== invoiceId ||
        event.event_type !== "legacy_price_history_migrated" ||
        !expectedFields || !event.price_fields ||
        typeof event.price_fields !== "object" ||
        id !== deterministicHistoryId(
            invoiceId,
            event.source_history_index,
            expectedFields,
        ) ||
        checksum(event.price_fields) !== checksum(expectedFields) ||
        !sourceEvent || event.source_event_sha256 !== checksum(sourceEvent)) {
      return "existing_restricted_history_invalid";
    }
  }
  const unexpectedHistory = Object.values(restrictedHistory || {}).some((event) =>
    event?.invoice_id === invoiceId &&
    event?.event_type === "legacy_price_history_migrated" &&
    !historyIds.includes(event.id));
  return unexpectedHistory ? "existing_restricted_history_invalid" : null;
}

function buildLegacySourcePriceFields({invoiceId, invoice, located, protectedItems}) {
  const paths = [
    ...located.topPaths,
    ...located.itemPaths,
    ...located.historyPaths,
  ];
  return paths.map((path) => {
    const scope = path[0] === "items" ? "item" :
      path[0] === "history" ? "history" : "invoice";
    const sourceIndex = scope === "invoice" ? undefined : path[1];
    const sourceItem = scope === "item" ? invoice.items?.[sourceIndex] : undefined;
    const sourceRow = firstDefined(
        sourceItem?.source_row,
        sourceItem?.source_row_number,
        sourceItem?.row_number,
        sourceItem?.legacy_row_number,
    );
    return compact({
      source_scope: scope,
      source_path: pathKey(path),
      source_field: path[path.length - 1],
      source_index: sourceIndex,
      source_row: sourceRow,
      source_item_id: scope === "item" ?
        protectedItems[sourceIndex]?.item_id || deterministicItemId(invoiceId, sourceIndex) :
        undefined,
      raw_value: clone(valueAtPath(invoice, path)),
    });
  });
}

function locateLegacyPrices(invoice) {
  const topPaths = [];
  const itemPaths = [];
  const historyPaths = [];
  const historyEntries = [];
  for (const key of PUBLIC_PRICE_KEYS) {
    if (Object.prototype.hasOwnProperty.call(invoice, key)) topPaths.push([key]);
  }
  if (Array.isArray(invoice.items)) {
    invoice.items.forEach((item, index) => {
      if (!item || typeof item !== "object") return;
      for (const key of PUBLIC_PRICE_KEYS) {
        if (Object.prototype.hasOwnProperty.call(item, key)) {
          itemPaths.push(["items", index, key]);
        }
      }
    });
  }
  if (Array.isArray(invoice.history)) {
    invoice.history.forEach((entry, index) => {
      const changes = entry && typeof entry === "object" ? entry.changes : undefined;
      if (!changes || typeof changes !== "object") return;
      const priceFields = {};
      for (const key of PUBLIC_PRICE_KEYS) {
        if (Object.prototype.hasOwnProperty.call(changes, key)) {
          historyPaths.push(["history", index, "changes", key]);
          priceFields[key] = changes[key];
        }
      }
      if (Object.keys(priceFields).length > 0) historyEntries.push({index, priceFields});
    });
  }
  const known = new Set([...topPaths, ...itemPaths, ...historyPaths].map(pathKey));
  const unknownPaths = [];
  walk(invoice, [], (path, key) => {
    if (PRICE_LIKE_KEY.test(key) && !known.has(pathKey([...path, key]))) {
      unknownPaths.push([...path, key]);
    }
  });
  return {
    topPaths,
    itemPaths,
    historyPaths,
    historyEntries,
    unknownPaths,
    topLevelCount: topPaths.length,
    itemCount: itemPaths.length,
    historyCount: historyPaths.length,
    priceFieldCount: topPaths.length + itemPaths.length + historyPaths.length,
  };
}

function removeLocatedPriceFields(invoice, located) {
  const result = clone(invoice);
  for (const path of [...located.topPaths, ...located.itemPaths, ...located.historyPaths]) {
    deleteAtPath(result, path);
  }
  return result;
}

function stripKnownPublicPrices(invoice) {
  const located = locateLegacyPrices(invoice);
  return removeLocatedPriceFields(invoice, located);
}

function normalizePublicInvoices(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => ({
      id: String(entry.id || ""),
      data: clone(entry.data || {}),
      migrationCurrency: entry.migration_currency,
    })).filter((entry) => entry.id);
  }
  return Object.entries(value).map(([id, entry]) => {
    const wrapped = entry && typeof entry === "object" && entry.data ? entry : null;
    return {
      id,
      data: clone(wrapped ? wrapped.data : entry),
      migrationCurrency: wrapped ? wrapped.migration_currency : undefined,
    };
  });
}

function assignPublicInvoice(container, invoiceId, value) {
  if (Array.isArray(container)) {
    const entry = container.find((candidate) => String(candidate.id) === invoiceId);
    if (entry) entry.data = value;
    return;
  }
  const existing = container[invoiceId];
  if (existing && typeof existing === "object" && existing.data) {
    existing.data = value;
  } else {
    container[invoiceId] = value;
  }
}

function finish(report, counts, invoiceAfter, outcome) {
  return {
    counts,
    report: {
      ...report,
      outcome,
      after_checksum: checksum(invoiceAfter),
      removed_field_count: counts.public_price_fields_removed,
      restricted_history_event_count: counts.restricted_history_created,
    },
  };
}

function emptyCounts() {
  return {
    containing_prices: 0,
    reconciled: 0,
    migrated: 0,
    already_migrated: 0,
    conflicts: 0,
    missing_currency: 0,
    unknown_price_paths: 0,
    public_price_fields_removed: 0,
    snapshots_created: 0,
    restricted_history_created: 0,
  };
}

function deterministicItemId(invoiceId, index) {
  return `legacy-item-${hash(`${invoiceId}\u001f${index}`).slice(0, 20)}`;
}

function deterministicHistoryId(invoiceId, index, fields) {
  return `legacy-price-${hash(`${invoiceId}\u001f${index}\u001f${canonical(fields)}`).slice(0, 24)}`;
}

function checksum(value) {
  return hash(canonical(value));
}

function hash(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function isSha256(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

function canonical(value) {
  return JSON.stringify(sortValue(value));
}

function sortValue(value) {
  if (Array.isArray(value)) return value.map(sortValue);
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = sortValue(value[key]);
      return result;
    }, {});
  }
  return value;
}

function walk(value, path, visitor) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => walk(item, [...path, index], visitor));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    visitor(path, key);
    walk(child, [...path, key], visitor);
  }
}

function deleteAtPath(value, path) {
  let current = value;
  for (let index = 0; index < path.length - 1; index += 1) {
    current = current?.[path[index]];
    if (current === undefined || current === null) return;
  }
  delete current[path[path.length - 1]];
}

function setAtPath(value, path, replacement) {
  let current = value;
  for (let index = 0; index < path.length - 1; index += 1) {
    const part = path[index];
    if (current === null || current === undefined ||
        (typeof current !== "object" && !Array.isArray(current)) ||
        !Object.prototype.hasOwnProperty.call(current, part)) {
      return false;
    }
    current = current[part];
  }
  if (current === null || current === undefined ||
      (typeof current !== "object" && !Array.isArray(current))) {
    return false;
  }
  current[path[path.length - 1]] = replacement;
  return true;
}

function valueAtPath(value, path) {
  let current = value;
  for (const part of path) {
    current = current?.[part];
  }
  return current;
}

function pathKey(path) {
  return path.map(String).join(".");
}

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function compact(value) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function nonEmpty(value) {
  const result = value === undefined || value === null ? "" : String(value).trim();
  return result || undefined;
}

function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function firstFiniteNumber(...values) {
  for (const value of values) {
    const result = finiteNumber(value);
    if (result !== undefined) return result;
  }
  return undefined;
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null);
}

function near(left, right, tolerance) {
  return Math.abs(left - right) <= tolerance;
}

function codedError(code) {
  return Object.assign(new Error(code), {code});
}

module.exports = {
  SUPPORTED_CURRENCIES,
  assertFirestoreEmulatorOnly,
  checksum,
  locateLegacyPrices,
  rehearseLegacyPriceMigration,
  validateV2PublicItemFixture,
};
