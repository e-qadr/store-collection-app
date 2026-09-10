"use strict";

// This tool is intentionally bounded and opt-in. Its default mode reads at
// a small number of Purchase invoice/item documents, writes an ignored local backup, and makes
// no Firestore mutations. `--apply` can only create the exact canonical
// product operations saved in that backup; it never changes an invoice, item,
// task, counter, price record, group, or existing product.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const {
  canonicalRequestHash,
  normalizeCatalogText,
  productUniqueKeyId,
} = require("./purchase-invoice-domain");

const COLLECTIONS = Object.freeze({
  brands: "brands",
  invoices: "purchase_invoices",
  groups: "product_groups",
  products: "products",
  uniqueKeys: "product_unique_keys",
  audits: "product_audit_events",
});
const WORKFLOW_IDENTITY = "purchase_invoice_v1";
const MAX_AUDIT_ITEMS = 100;
const BACKUP_VERSION = 1;
const SYSTEM_ACTOR = Object.freeze({
  uid: "system_purchase_catalog_backfill",
  name: "System: Purchase catalog backfill",
  role: "system",
});

function codedError(code) {
  return Object.assign(new Error(code), {code});
}

function optionalString(value) {
  const text = String(value || "").trim();
  return text || "";
}

function hash(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function deterministicId(prefix, ...parts) {
  return `${prefix}-${hash(parts).slice(0, 40)}`;
}

function documentEntry(snapshot) {
  return {id: snapshot.id, path: snapshot.ref.path, data: snapshot.data() || {}};
}

function isCompleteCanonicalItem(data) {
  return [
    data.canonical_product_id,
    data.canonical_group_id,
    data.canonical_unit_id,
  ].every((value) => optionalString(value));
}

function productHasUnit(product, unitText) {
  const normalizedUnit = normalizeCatalogText(unitText);
  return Array.isArray(product.units) && product.units.some((unit) =>
    normalizeCatalogText(unit?.raw_value || unit?.display_value) === normalizedUnit,
  );
}

function safeOperationFrom({candidate, group}) {
  const data = candidate.data;
  const brandId = optionalString(data.receiving_brand_id);
  const name = optionalString(data.original_material_name);
  const unit = optionalString(data.original_unit_text);
  const normalizedName = normalizeCatalogText(name);
  const fingerprint = canonicalRequestHash({
    invoice_item_path: candidate.path,
    brand_id: brandId,
    group_id: group.id,
    name,
    unit,
  });
  const productId = deterministicId("purchase-catalog", brandId, normalizedName);
  return {
    product_id: productId,
    audit_id: deterministicId("purchase-catalog-audit", productId),
    name_unique_key_id: productUniqueKeyId({
      brandId,
      keyType: "name",
      normalizedValue: normalizedName,
    }),
    brand_id: brandId,
    group_id: group.id,
    group_name: optionalString(group.name),
    name,
    normalized_name: normalizedName,
    unit: {unit_id: "primary", display_value: unit, raw_value: unit},
    source_fingerprint: fingerprint,
    source_invoice_item_paths: [candidate.path],
    source_line_number: Number.isSafeInteger(data.line_number) ? data.line_number : 0,
    raw_group_value: optionalString(data.original_group_text),
  };
}

function candidateSourceSnapshot(candidate) {
  const data = candidate.data;
  // This is a deliberately closed, public-only copy of the historical line.
  // The backup must never become a second location for protected price data.
  return {
    document_path: candidate.path,
    id: candidate.id,
    invoice_id: optionalString(data.invoice_id),
    workflow_identity: optionalString(data.workflow_identity),
    receiving_branch_id: optionalString(data.receiving_branch_id),
    receiving_brand_id: optionalString(data.receiving_brand_id),
    line_number: Number.isSafeInteger(data.line_number) ? data.line_number : 0,
    item_id: optionalString(data.item_id),
    source_type: optionalString(data.source_type),
    original_material_name: optionalString(data.original_material_name),
    original_group_text: optionalString(data.original_group_text),
    original_unit_text: optionalString(data.original_unit_text),
    canonical_product_id: optionalString(data.canonical_product_id),
    canonical_group_id: optionalString(data.canonical_group_id),
    canonical_unit_id: optionalString(data.canonical_unit_id),
    review_task_id: optionalString(data.review_task_id),
    review_status: optionalString(data.review_status),
    ordered_quantity: typeof data.ordered_quantity === "number" ? data.ordered_quantity : null,
    line_notes: optionalString(data.line_notes),
  };
}

function recordSkip(candidate, reason) {
  return {
    path: candidate.path,
    item_id: candidate.id,
    source_snapshot: candidateSourceSnapshot(candidate),
    decision: "skipped",
    reason,
  };
}

// Pure planner used by both the bounded read-only audit and unit tests.
function buildBackfillPlan({projectId, scannedCount, scanReachedLimit, candidates, groups, products}) {
  const safe = [];
  const report = [];
  for (const candidate of candidates.sort((left, right) => left.path.localeCompare(right.path))) {
    const data = candidate.data;
    if (data.source_type !== "unmatched") {
      report.push(recordSkip(candidate, "legacy-catalog-line-not-safe-to-repair"));
      continue;
    }
    const brandId = optionalString(data.receiving_brand_id);
    const name = optionalString(data.original_material_name);
    const groupText = optionalString(data.original_group_text);
    const unit = optionalString(data.original_unit_text);
    if (!brandId || !name || !groupText || !unit) {
      report.push(recordSkip(candidate, "missing-unambiguous-brand-name-group-or-unit"));
      continue;
    }
    const matchingGroups = (groups.get(brandId) || []).filter((group) =>
      group.active !== false && normalizeCatalogText(group.normalized_name || group.name) ===
        normalizeCatalogText(groupText),
    );
    if (matchingGroups.length !== 1) {
      report.push(recordSkip(
          candidate,
          matchingGroups.length ? "ambiguous-catalog-group" : "catalog-group-not-found",
      ));
      continue;
    }
    const activeNameMatches = (products.get(brandId) || []).filter((product) =>
      product.active !== false &&
      normalizeCatalogText(product.normalized_name || product.name) === normalizeCatalogText(name),
    );
    if (activeNameMatches.length) {
      const exact = activeNameMatches.filter((product) =>
        product.group_id === matchingGroups[0].id && productHasUnit(product, unit),
      );
      report.push({
        path: candidate.path,
        item_id: candidate.id,
        source_snapshot: candidateSourceSnapshot(candidate),
        decision: exact.length === 1 ? "already_present" : "skipped",
        ...(exact.length === 1
          ? {product_id: exact[0].id}
          : {reason: "existing-product-name-conflict-or-unit-mismatch"}),
      });
      continue;
    }
    const operation = safeOperationFrom({candidate, group: matchingGroups[0]});
    safe.push(operation);
    report.push({
      path: candidate.path,
      item_id: candidate.id,
      source_snapshot: candidateSourceSnapshot(candidate),
      decision: "safe_to_create",
      product_id: operation.product_id,
    });
  }

  const operations = [];
  for (const entries of new Map(safe.map((entry) => [
    `${entry.brand_id}\u001f${entry.normalized_name}`,
    safe.filter((other) => `${other.brand_id}\u001f${other.normalized_name}` ===
      `${entry.brand_id}\u001f${entry.normalized_name}`),
  ])).values()) {
    const first = entries[0];
    const compatible = entries.every((entry) => entry.group_id === first.group_id &&
      normalizeCatalogText(entry.unit.raw_value) === normalizeCatalogText(first.unit.raw_value));
    if (!compatible) {
      for (const entry of entries) {
        const index = report.findIndex((row) => row.path === entry.source_invoice_item_paths[0]);
        if (index >= 0) {
          const {product_id: ignoredProductId, ...prior} = report[index];
          report[index] = {
            ...prior,
            decision: "skipped",
            reason: "conflicting-safe-candidates-share-a-product-name",
          };
        }
      }
      continue;
    }
    operations.push({
      ...first,
      source_invoice_item_paths: entries.flatMap((entry) => entry.source_invoice_item_paths).sort(),
    });
  }
  operations.sort((left, right) => left.product_id.localeCompare(right.product_id));
  const counts = {
    scanned_items: scannedCount,
    candidate_items: candidates.length,
    safe_products: operations.length,
    already_present: report.filter((row) => row.decision === "already_present").length,
    skipped: report.filter((row) => row.decision === "skipped").length,
  };
  const core = {
    backup_version: BACKUP_VERSION,
    project_id: projectId,
    workflow_identity: WORKFLOW_IDENTITY,
    scan_reached_limit: scanReachedLimit,
    counts,
    candidates: report.sort((left, right) => left.path.localeCompare(right.path)),
    operations,
  };
  return {...core, plan_checksum: canonicalRequestHash(core)};
}

async function readAuditInventory({firestore, projectId, limit}) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > MAX_AUDIT_ITEMS) {
    throw codedError("invalid-audit-limit");
  }
  // Use the Purchase-invoice root collection rather than a collection-group
  // query. The production project intentionally has no collection-group
  // single-field index for `items.workflow_identity`; this keeps the audit
  // index-free and avoids any request to alter production indexes.
  const invoiceSnapshot = await firestore.collection(COLLECTIONS.invoices)
      .where("workflow_identity", "==", WORKFLOW_IDENTITY).limit(limit).get();
  const itemDocuments = [];
  for (const invoice of invoiceSnapshot.docs) {
    if (itemDocuments.length >= limit) break;
    const remaining = limit - itemDocuments.length;
    const items = await invoice.ref.collection("items").limit(remaining).get();
    itemDocuments.push(...items.docs.map(documentEntry));
  }
  const candidateDocuments = itemDocuments.filter(({data}) =>
    !isCompleteCanonicalItem(data),
  );
  const brandIds = [...new Set(candidateDocuments.map(({data}) =>
    optionalString(data.receiving_brand_id)).filter(Boolean))].sort();
  const [groupSnapshots, productSnapshots] = await Promise.all([
    Promise.all(brandIds.map((brandId) => firestore.collection(COLLECTIONS.groups)
        .where("brand_id", "==", brandId).get())),
    Promise.all(brandIds.map((brandId) => firestore.collection(COLLECTIONS.products)
        .where("brand_id", "==", brandId).get())),
  ]);
  const groups = new Map(brandIds.map((brandId, index) => [brandId,
    groupSnapshots[index].docs.map((snapshot) => ({id: snapshot.id, ...snapshot.data()}))]));
  const products = new Map(brandIds.map((brandId, index) => [brandId,
    productSnapshots[index].docs.map((snapshot) => ({id: snapshot.id, ...snapshot.data()}))]));
  return buildBackfillPlan({
    projectId,
    scannedCount: itemDocuments.length,
    scanReachedLimit: invoiceSnapshot.size === limit || itemDocuments.length === limit,
    candidates: candidateDocuments,
    groups,
    products,
  });
}

function expectedConfirmation({projectId, planChecksum}) {
  return `APPLY_PURCHASE_CATALOG_BACKFILL:${projectId}:${planChecksum}`;
}

function expectedProductionConfirmation(projectId) {
  return `PRODUCTION_PROJECT:${projectId}`;
}

function auditSnapshot(product) {
  return {
    id: product.id,
    brand_id: product.brand_id,
    group_id: product.group_id,
    name: product.name,
    normalized_name: product.normalized_name,
    units: product.units,
    primary_unit_id: product.primary_unit_id,
    active: product.active,
    version: product.version,
    name_unique_key_id: product.name_unique_key_id,
    last_audit_event_id: product.last_audit_event_id,
  };
}

function productForOperation(operation, plan) {
  const sourceMetadata = {
    source_profile: "purchase_invoice_catalog_backfill",
    source_file_sha256: plan.plan_checksum,
    source_sheet: "purchase_invoice_items",
    source_row: operation.source_line_number,
    raw_material_value: operation.name,
    raw_group_value: operation.raw_group_value,
    raw_primary_unit: operation.unit.raw_value,
    raw_unit_2: "",
    raw_unit_3: "",
    source_fingerprint: operation.source_fingerprint,
    import_id: `purchase-catalog-backfill-${plan.plan_checksum.slice(0, 20)}`,
    original_group_missing: false,
    fallback_system_group_assigned: false,
  };
  return {
    id: operation.product_id,
    brand_id: operation.brand_id,
    group_id: operation.group_id,
    name: operation.name,
    normalized_name: operation.normalized_name,
    units: [operation.unit],
    primary_unit_id: "primary",
    active: true,
    version: 1,
    name_unique_key_id: operation.name_unique_key_id,
    source_metadata: sourceMetadata,
    last_audit_event_id: operation.audit_id,
    created_by: SYSTEM_ACTOR.uid,
    created_by_name: SYSTEM_ACTOR.name,
    created_at: undefined,
    updated_by: SYSTEM_ACTOR.uid,
    updated_by_name: SYSTEM_ACTOR.name,
    updated_at: undefined,
  };
}

function equivalentCreatedProduct(existing, intended) {
  return existing?.id === intended.id && existing.brand_id === intended.brand_id &&
    existing.group_id === intended.group_id && existing.name === intended.name &&
    existing.normalized_name === intended.normalized_name && existing.active === true &&
    existing.name_unique_key_id === intended.name_unique_key_id &&
    existing.source_metadata?.source_profile === "purchase_invoice_catalog_backfill" &&
    existing.source_metadata?.source_fingerprint === intended.source_metadata.source_fingerprint;
}

async function applyOperation({firestore, operation, plan, FieldValue}) {
  const brandRef = firestore.collection(COLLECTIONS.brands).doc(operation.brand_id);
  const groupRef = firestore.collection(COLLECTIONS.groups).doc(operation.group_id);
  const productRef = firestore.collection(COLLECTIONS.products).doc(operation.product_id);
  const keyRef = firestore.collection(COLLECTIONS.uniqueKeys).doc(operation.name_unique_key_id);
  const auditRef = firestore.collection(COLLECTIONS.audits).doc(operation.audit_id);
  return firestore.runTransaction(async (transaction) => {
    const [brand, group, product, key, audit] = await transaction.getAll(
        brandRef, groupRef, productRef, keyRef, auditRef);
    if (!brand.exists || !group.exists || group.data()?.brand_id !== operation.brand_id ||
        group.data()?.active !== true) throw codedError("backfill-group-not-ready");
    const intended = productForOperation(operation, plan);
    if (product.exists) {
      if (!equivalentCreatedProduct(product.data(), intended) || !audit.exists ||
          !key.exists || key.data()?.product_id !== operation.product_id) {
        throw codedError("backfill-product-changed-after-audit");
      }
      return "unchanged";
    }
    if (audit.exists || key.exists) {
      throw codedError("backfill-unique-key-conflict");
    }
    const now = FieldValue.serverTimestamp();
    const productData = {...intended, created_at: now, updated_at: now};
    transaction.create(productRef, productData);
    transaction.set(keyRef, {
      id: operation.name_unique_key_id,
      brand_id: operation.brand_id,
      key_type: "name",
      normalized_value: operation.normalized_name,
      product_id: operation.product_id,
      active: true,
      created_by: SYSTEM_ACTOR.uid,
      created_at: now,
      updated_by: SYSTEM_ACTOR.uid,
      updated_at: now,
    });
    transaction.create(auditRef, {
      id: operation.audit_id,
      entity_type: "product",
      entity_id: operation.product_id,
      brand_id: operation.brand_id,
      action: "created",
      after: auditSnapshot(productData),
      reason: `purchase_catalog_backfill:${plan.plan_checksum}`,
      actor_uid: SYSTEM_ACTOR.uid,
      actor_name: SYSTEM_ACTOR.name,
      actor_role: SYSTEM_ACTOR.role,
      created_at: now,
    });
    return "created";
  });
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
  return {firestore: admin.firestore(), FieldValue: admin.firestore.FieldValue};
}

function readBackup(backupPath) {
  const parsed = JSON.parse(fs.readFileSync(backupPath, "utf8"));
  const core = {...parsed};
  delete core.plan_checksum;
  if (parsed.backup_version !== BACKUP_VERSION ||
      parsed.plan_checksum !== canonicalRequestHash(core)) {
    throw codedError("backup-checksum-mismatch");
  }
  return parsed;
}

async function main(arguments_ = process.argv.slice(2)) {
  const options = parseArguments(arguments_);
  const projectId = optionalString(options["project-id"]);
  if (!projectId) throw codedError("missing-project-id");
  if (options.apply) {
    const backupPath = optionalString(options["backup-path"]);
    if (!backupPath) throw codedError("missing-backup-path");
    const plan = readBackup(backupPath);
    if (plan.project_id !== projectId || plan.scan_reached_limit === true) {
      throw codedError("unsafe-backup-plan");
    }
    if (options.confirm !== expectedConfirmation({projectId, planChecksum: plan.plan_checksum}) ||
        options["production-confirm"] !== expectedProductionConfirmation(projectId)) {
      throw codedError("apply-confirmation-mismatch");
    }
    const {firestore, FieldValue} = await createAdminFirestore(projectId);
    const outcomes = [];
    for (const operation of plan.operations) {
      outcomes.push(await applyOperation({firestore, operation, plan, FieldValue}));
    }
    const result = {mode: "apply", project_id: projectId, plan_checksum: plan.plan_checksum,
      created: outcomes.filter((outcome) => outcome === "created").length,
      unchanged: outcomes.filter((outcome) => outcome === "unchanged").length,
      invoice_or_item_writes: 0, counter_writes: 0};
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return result;
  }
  const limit = options.limit === undefined ? MAX_AUDIT_ITEMS : Number(options.limit);
  const backupPath = path.resolve(options["backup-path"] ||
      `purchase-catalog-backfill-${new Date().toISOString().slice(0, 10)}.backfill.local.json`);
  if (!backupPath.endsWith(".backfill.local.json")) throw codedError("backup-path-must-be-ignored-local-json");
  if (fs.existsSync(backupPath)) throw codedError("backup-already-exists");
  const {firestore} = await createAdminFirestore(projectId);
  const plan = await readAuditInventory({firestore, projectId, limit});
  fs.writeFileSync(backupPath, `${JSON.stringify(plan, null, 2)}\n`, {encoding: "utf8", flag: "wx"});
  const result = {
    mode: "read_only_audit",
    project_id: projectId,
    plan_checksum: plan.plan_checksum,
    counts: plan.counts,
    scan_reached_limit: plan.scan_reached_limit,
    backup_path: backupPath,
    required_confirmation: expectedConfirmation({projectId, planChecksum: plan.plan_checksum}),
  };
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return result;
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.code || "purchase-catalog-backfill-failed"}\n`);
    process.exitCode = 2;
  });
}

module.exports = {
  buildBackfillPlan,
  candidateSourceSnapshot,
  expectedConfirmation,
  expectedProductionConfirmation,
  isCompleteCanonicalItem,
  productForOperation,
};
