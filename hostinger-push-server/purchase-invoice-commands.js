const crypto = require("node:crypto");
const express = require("express");

const {
  PurchaseCommandError,
  SUPPORTED_CURRENCIES,
  canonicalRequestHash,
  compact,
  deterministicDocumentId,
  documentId,
  normalizeCatalogText,
  normalizeLegacyCode,
  productPriceLatestKey,
  productUniqueKeyId,
  publicError,
  purchaseItemDigest,
  uncategorizedGroupId,
  validateCreatePayload,
  validateIdempotencyKey,
  validatePostingPayload,
  validatePricingPayload,
  validateReceiptPayload,
  validateReviewPayload,
} = require("./purchase-invoice-domain");

const COLLECTIONS = Object.freeze({
  users: "users",
  branches: "branches",
  brands: "brands",
  products: "products",
  groups: "product_groups",
  uniqueProductKeys: "product_unique_keys",
  productAudits: "product_audit_events",
  accountingProfiles: "product_accounting_profiles",
  invoices: "purchase_invoices",
  events: "purchase_invoice_events",
  prices: "purchase_invoice_prices",
  reviewTasks: "product_review_tasks",
  commands: "purchase_invoice_commands",
  supplierKeys: "purchase_invoice_unique_keys",
  priceLatest: "product_price_latest",
  priceHistory: "product_price_history",
  notifications: "notifications",
});

const STATUS = Object.freeze({
  pendingReceiverReview: "pendingReceiverReview",
  pendingPriceEntry: "pendingPriceEntry",
  pendingAccountingEntry: "pendingAccountingEntry",
  postedToAccounting: "postedToAccounting",
});

const REVIEW_STATUS = Object.freeze({
  notRequired: "not_required",
  pending: "pending_review",
  clarification: "clarification_requested",
  linked: "linked_material",
  created: "newly_created_material",
  synchronized: "synchronized",
});

const PURCHASE_JSON_LIMIT = "64kb";
const ITEMS_SUBCOLLECTION = "items";
const OPERATIONAL_ROLES = new Set(["manager", "collector", "accountant", "admin"]);

const HEADER_KEYS = new Set([
  "id", "schema_version", "workflow_version", "workflow_identity", "status", "revision",
  "purchase_number", "receiving_branch_id", "receiving_branch_name", "receiving_brand_id",
  "branch_ids", "item_count", "item_digest", "currency", "supplier_name",
  "supplier_invoice_number", "supplier_invoice_date", "general_manager_notes", "receiver_notes",
  "created_by", "created_by_name", "created_by_role", "created_at", "receipt_confirmed_by",
  "receipt_confirmed_by_name", "receipt_confirmed_at", "posted_by", "posted_by_name",
  "posted_at", "posted_with_unresolved_override", "last_updated", "history",
]);

const ITEM_KEYS = new Set([
  "id", "invoice_id", "schema_version", "workflow_version", "workflow_identity",
  "invoice_revision", "branch_ids", "receiving_branch_id", "receiving_brand_id", "line_number",
  "item_id", "source_type", "original_material_name", "original_group_text", "original_unit_text",
  "canonical_product_id", "canonical_product_version", "canonical_product_name",
  "canonical_product_legacy_code", "canonical_group_id", "canonical_group_name",
  "canonical_group_legacy_code", "canonical_unit_id", "canonical_unit_value",
  "canonical_unit_raw_value", "review_task_id", "review_status", "ordered_quantity", "line_notes",
  "received_quantity", "damaged_quantity", "missing_quantity", "discrepancy_notes",
]);

const HISTORY_KEYS = new Set([
  "action", "message", "actor_id", "actor_name", "actor_role", "timestamp",
]);

const PROTECTED_PRICE_KEYS = new Set([
  "id", "invoice_id", "invoice_revision", "pricing_revision", "pricing_state", "item_count",
  "item_digest", "currency", "provisional_items", "items", "invoice_total", "pricing_notes",
  "confirmed_by", "confirmed_by_name", "confirmed_by_role", "confirmed_at", "locked",
  "locked_by", "locked_by_name", "locked_at", "locked_invoice_revision",
  "accounting_reference", "accountant_notes", "posting_override",
]);

function bearerToken(request) {
  return (request.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1];
}

function isOperationalProfile(profile) {
  return profile && profile.isActive !== false && profile.mustChangePassword !== true &&
    OPERATIONAL_ROLES.has(String(profile.role || ""));
}

function actorFromProfile(uid, profile) {
  return {
    uid,
    name: bounded(profile.name, uid, 200),
    role: String(profile.role || ""),
    branchId: String(profile.branchId || "").trim(),
  };
}

function bounded(value, fallback, maximumCharacters) {
  const clean = String(value || "").trim();
  return (clean || String(fallback)).slice(0, maximumCharacters);
}

function timestampFor(admin, now) {
  return admin.firestore.Timestamp.fromDate(now());
}

function hasOnlyKeys(value, keys) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).every((key) => keys.has(key));
}

function eventData(action, message, actor, timestamp) {
  return {
    action,
    message,
    actor_id: actor.uid,
    actor_name: actor.name,
    actor_role: actor.role,
    timestamp,
  };
}

function historyWithEvent(invoice, event) {
  if (!Array.isArray(invoice.history) ||
      invoice.history.some((entry) => !hasOnlyKeys(entry, HISTORY_KEYS))) {
    throw new PurchaseCommandError("invoice-malformed", 409, "Invoice history is invalid.");
  }
  return [...invoice.history, event];
}

function activeDocument(data) {
  return data && data.active !== false && data.isActive !== false && data.is_active !== false;
}

function cleanBranch(snapshot, branchId) {
  if (!snapshot.exists || !activeDocument(snapshot.data())) {
    throw new PurchaseCommandError("branch-not-found", 404, "The receiving branch is unavailable.");
  }
  const data = snapshot.data();
  const brandId = String(data.brand_id || "").trim();
  if (!brandId) {
    throw new PurchaseCommandError("branch-brand-missing", 409, "The branch brand is missing.");
  }
  return {id: branchId, name: bounded(data.name, branchId, 200), brandId, data};
}

function requireBrand(snapshot, brandId) {
  if (!snapshot.exists || !activeDocument(snapshot.data()) ||
      (snapshot.data()?.id !== undefined && snapshot.data().id !== brandId)) {
    throw new PurchaseCommandError("branch-brand-invalid", 409, "The branch brand is invalid.");
  }
}

function catalogUnit(product, unitId) {
  if (!Array.isArray(product?.units)) return null;
  return product.units.find((unit) => unit && String(unit.unit_id || "") === unitId) || null;
}

function catalogSnapshot(product, group, unit, brandId) {
  if (!product || product.active !== true || product.brand_id !== brandId ||
      !Number.isSafeInteger(product.version) || product.version < 1 ||
      !group || group.active !== true || group.brand_id !== brandId ||
      !unit || unit.active === false) {
    throw new PurchaseCommandError("catalog-snapshot-invalid", 409, "A catalog selection is invalid.");
  }
  const required = [product.name, group.name, unit.display_value, unit.raw_value || unit.display_value];
  if (required.some((value) => typeof value !== "string" || !value.trim())) {
    throw new PurchaseCommandError("catalog-snapshot-invalid", 409, "A catalog selection is incomplete.");
  }
  return compact({
    canonical_product_id: product.id,
    canonical_product_version: product.version,
    canonical_product_name: product.name.trim(),
    canonical_product_legacy_code: optionalStored(product.legacy_code),
    canonical_group_id: group.id,
    canonical_group_name: group.name.trim(),
    canonical_group_legacy_code: optionalStored(group.legacy_code),
    canonical_unit_id: unit.unit_id,
    canonical_unit_value: unit.display_value.trim(),
    canonical_unit_raw_value: String(unit.raw_value || unit.display_value).trim(),
  });
}

function optionalStored(value) {
  const clean = String(value || "").trim();
  return clean || undefined;
}

function assertPublicHeader(invoice, expectedId) {
  if (!hasOnlyKeys(invoice, HEADER_KEYS) || invoice.id !== expectedId ||
      invoice.schema_version !== 1 || invoice.workflow_version !== 1 ||
      invoice.workflow_identity !== "purchase_invoice_v1" ||
      !Object.values(STATUS).includes(invoice.status) ||
      !Number.isSafeInteger(invoice.revision) || invoice.revision < 1 ||
      !Number.isSafeInteger(invoice.item_count) || invoice.item_count < 1 || invoice.item_count > 50 ||
      typeof invoice.item_digest !== "string" || !/^[a-f0-9]{64}$/.test(invoice.item_digest) ||
      !SUPPORTED_CURRENCIES.has(invoice.currency) ||
      !Array.isArray(invoice.branch_ids) || invoice.branch_ids.length !== 1 ||
      invoice.branch_ids[0] !== invoice.receiving_branch_id ||
      invoice.created_by_role !== "collector" ||
      !Array.isArray(invoice.history) ||
      invoice.history.some((entry) => !hasOnlyKeys(entry, HISTORY_KEYS))) {
    throw new PurchaseCommandError("invoice-malformed", 409, "The purchase invoice is invalid.");
  }
  const serialized = JSON.stringify(invoice).toLowerCase();
  if (/unit_price|invoice_total|accounting_reference|accountant_notes|override_reason/.test(serialized)) {
    throw new PurchaseCommandError("public-price-field-forbidden", 409, "Protected data is public.");
  }
}

function assertPublicItem(invoice, item, expectedId) {
  if (!hasOnlyKeys(item, ITEM_KEYS) || item.id !== expectedId || item.item_id !== expectedId ||
      item.invoice_id !== invoice.id || item.schema_version !== 1 || item.workflow_version !== 1 ||
      item.workflow_identity !== "purchase_invoice_v1" ||
      !Number.isSafeInteger(item.invoice_revision) || item.invoice_revision < 1 ||
      item.invoice_revision > invoice.revision ||
      !Array.isArray(item.branch_ids) || item.branch_ids.length !== 1 ||
      item.branch_ids[0] !== invoice.receiving_branch_id ||
      item.receiving_branch_id !== invoice.receiving_branch_id ||
      item.receiving_brand_id !== invoice.receiving_brand_id ||
      !Number.isSafeInteger(item.line_number) || item.line_number < 1 ||
      (item.source_type !== "catalog" && item.source_type !== "unmatched") ||
      typeof item.original_material_name !== "string" || !item.original_material_name ||
      typeof item.original_group_text !== "string" ||
      typeof item.original_unit_text !== "string" || !item.original_unit_text ||
      typeof item.ordered_quantity !== "number" || !Number.isFinite(item.ordered_quantity) ||
      item.ordered_quantity <= 0 || typeof item.review_status !== "string") {
    throw new PurchaseCommandError("invoice-item-malformed", 409, "A purchase item is invalid.");
  }
  const serialized = JSON.stringify(item).toLowerCase();
  if (/unit_price|line_total|invoice_total|accounting_reference|accountant_notes/.test(serialized)) {
    throw new PurchaseCommandError("public-price-field-forbidden", 409, "Protected data is public.");
  }
  if (item.source_type === "catalog" &&
      (!item.canonical_product_id || !item.canonical_unit_id ||
       item.review_status !== REVIEW_STATUS.notRequired || item.review_task_id !== undefined)) {
    throw new PurchaseCommandError("invoice-item-malformed", 409, "A catalog item is invalid.");
  }
  if (item.source_type === "unmatched" && !item.review_task_id) {
    throw new PurchaseCommandError("invoice-item-malformed", 409, "An unmatched item is invalid.");
  }
}

function requireInvoice(snapshot, invoiceId) {
  if (!snapshot.exists) {
    throw new PurchaseCommandError("invoice-not-found", 404, "The purchase invoice was not found.");
  }
  const invoice = snapshot.data();
  assertPublicHeader(invoice, invoiceId);
  return invoice;
}

function requireState(invoice, status, expectedRevision) {
  if (invoice.status !== status) {
    throw new PurchaseCommandError("invalid-state", 409, "The invoice is not in the required state.");
  }
  if (invoice.revision !== expectedRevision) {
    throw new PurchaseCommandError("stale-revision", 409, "The invoice revision has changed.");
  }
}

function itemsCollection(invoiceRef) {
  return invoiceRef.collection(ITEMS_SUBCOLLECTION);
}

async function readItems(transaction, invoiceRef, invoice) {
  const snapshot = await transaction.get(itemsCollection(invoiceRef).orderBy("line_number", "asc"));
  if (snapshot.size !== invoice.item_count) {
    throw new PurchaseCommandError("items-mismatch", 409, "The item count is inconsistent.");
  }
  const items = snapshot.docs.map((document) => {
    const item = document.data();
    assertPublicItem(invoice, item, document.id);
    return item;
  });
  if (new Set(items.map((item) => item.item_id)).size !== items.length ||
      new Set(items.map((item) => item.line_number)).size !== items.length ||
      purchaseItemDigest(items) !== invoice.item_digest) {
    throw new PurchaseCommandError("item-digest-mismatch", 409, "The item snapshot changed.");
  }
  return items;
}

async function readActor(transaction, firestore, uid, expectedRole) {
  const snapshot = await transaction.get(firestore.collection(COLLECTIONS.users).doc(uid));
  const profile = snapshot.data();
  if (!snapshot.exists || !isOperationalProfile(profile)) {
    throw new PurchaseCommandError("forbidden", 403, "The account cannot perform this operation.");
  }
  const actor = actorFromProfile(uid, profile);
  if (actor.role !== expectedRole) {
    throw new PurchaseCommandError("forbidden", 403, "The role cannot perform this operation.");
  }
  return actor;
}

function commandRef(firestore, command, uid, idempotencyKey) {
  const id = deterministicDocumentId("purchase-invoice-v1", command, uid, idempotencyKey);
  return firestore.collection(COLLECTIONS.commands).doc(id);
}

function replayOf(snapshot, command, uid, requestHash) {
  if (!snapshot.exists) return null;
  const data = snapshot.data();
  if (data.command !== command || data.actor_uid !== uid || data.request_hash !== requestHash) {
    throw new PurchaseCommandError("idempotency-conflict", 409, "The key was used for another request.");
  }
  if (!data.response_data || typeof data.response_data !== "object") {
    throw new PurchaseCommandError("idempotency-record-invalid", 409, "The command receipt is invalid.");
  }
  return {statusCode: data.status_code || 200, responseData: data.response_data, replay: true};
}

async function runIdempotent({
  firestore, command, actorUid, expectedRole, idempotencyKey, requestHash, timestamp, execute,
}) {
  const reference = commandRef(firestore, command, actorUid, idempotencyKey);
  return firestore.runTransaction(async (transaction) => {
    const actor = await readActor(transaction, firestore, actorUid, expectedRole);
    const receipt = await transaction.get(reference);
    const replay = replayOf(receipt, command, actorUid, requestHash);
    if (replay) return replay;
    const result = await execute(transaction, actor);
    transaction.set(reference, {
      id: reference.id,
      command,
      actor_uid: actorUid,
      request_hash: requestHash,
      invoice_id: result.responseData.invoice_id,
      status_code: result.statusCode,
      response_data: result.responseData,
      created_at: timestamp,
    });
    return {...result, replay: false};
  });
}

async function activeUsersByRole(transaction, firestore, role) {
  const snapshot = await transaction.get(
      firestore.collection(COLLECTIONS.users).where("role", "==", role),
  );
  return snapshot.docs.filter((doc) => isOperationalProfile(doc.data()) && doc.data().role === role)
      .map((doc) => actorFromProfile(doc.id, doc.data()));
}

async function activeBranchManagers(transaction, firestore, branchId, branch) {
  const assigned = String(branch?.branch_manager_id || "").trim();
  if (assigned) {
    const snapshot = await transaction.get(firestore.collection(COLLECTIONS.users).doc(assigned));
    const data = snapshot.data();
    return snapshot.exists && isOperationalProfile(data) && data.role === "manager" &&
      String(data.branchId || "") === branchId ? [actorFromProfile(assigned, data)] : [];
  }
  const snapshot = await transaction.get(
      firestore.collection(COLLECTIONS.users).where("branchId", "==", branchId),
  );
  return snapshot.docs.filter((doc) => isOperationalProfile(doc.data()) && doc.data().role === "manager")
      .map((doc) => actorFromProfile(doc.id, doc.data()));
}

function assertManager(actor, branchId, branch) {
  if (actor.role !== "manager" || actor.branchId !== branchId) {
    throw new PurchaseCommandError("forbidden", 403, "You cannot act for this branch.");
  }
  const assigned = String(branch.branch_manager_id || "").trim();
  if (assigned && assigned !== actor.uid) {
    throw new PurchaseCommandError("forbidden", 403, "You cannot act for this branch.");
  }
}

function notificationRef(firestore, invoiceId, type, revision, recipientId) {
  return firestore.collection(COLLECTIONS.notifications).doc(deterministicDocumentId(
      "purchase-invoice-v1-notification", invoiceId, type, String(revision), recipientId,
  ));
}

function writeNotifications(transaction, firestore, {
  recipients, invoice, type, title, message, revision, timestamp, excludeUid,
}) {
  const seen = new Set();
  for (const recipient of recipients) {
    const uid = typeof recipient === "string" ? recipient : recipient.uid;
    if (!uid || uid === excludeUid || seen.has(uid)) continue;
    seen.add(uid);
    const reference = notificationRef(firestore, invoice.id, type, revision, uid);
    transaction.set(reference, {
      id: reference.id,
      recipient_id: uid,
      title,
      message,
      is_read: false,
      push_status: "pending",
      module: COLLECTIONS.invoices,
      entity_collection: COLLECTIONS.invoices,
      entity_id: invoice.id,
      branch_id: invoice.receiving_branch_id,
      branch_ids: [invoice.receiving_branch_id],
      reference_number: invoice.purchase_number,
      notification_type: type,
      purchase_invoice_id: invoice.id,
      created_at: timestamp,
    });
  }
}

function writeEvent(transaction, firestore, {invoice, event, revision, suffix = ""}) {
  const id = deterministicDocumentId(
      "purchase-invoice-v1-event", invoice.id, String(revision), event.action, suffix,
  );
  transaction.set(firestore.collection(COLLECTIONS.events).doc(id), {
    id,
    invoice_id: invoice.id,
    workflow_version: 1,
    workflow_identity: "purchase_invoice_v1",
    receiving_branch_id: invoice.receiving_branch_id,
    branch_ids: [invoice.receiving_branch_id],
    revision,
    action: event.action,
    message: event.message,
    actor_id: event.actor_id,
    actor_name: event.actor_name,
    actor_role: event.actor_role,
    created_at: event.timestamp,
  });
}

function responseFor(invoiceId, status, revision, purchaseNumber) {
  return compact({invoice_id: invoiceId, purchase_number: purchaseNumber, status, revision});
}

function supplierUniqueKey(payload) {
  if (!payload.supplier_name || !payload.supplier_invoice_number) return null;
  return deterministicDocumentId(
      "purchase-supplier-reference",
      normalizeCatalogText(payload.supplier_name),
      normalizeCatalogText(payload.supplier_invoice_number),
  );
}

async function createPurchaseInvoice({
  firestore, actorUid, payload, idempotencyKey, timestamp, randomUUID,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc();
  const itemIds = payload.items.map(() => randomUUID());
  const taskIds = payload.items.map((item, index) => item.source_type === "unmatched" ?
    deterministicDocumentId("purchase-product-review", invoiceRef.id, itemIds[index]) : null);
  const requestHash = canonicalRequestHash(payload);
  return runIdempotent({
    firestore,
    command: "create_purchase_invoice",
    actorUid,
    expectedRole: "collector",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const branchRef = firestore.collection(COLLECTIONS.branches).doc(payload.receiving_branch_id);
      const branchSnapshot = await transaction.get(branchRef);
      const branch = cleanBranch(branchSnapshot, payload.receiving_branch_id);
      const brandSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.brands).doc(branch.brandId),
      );
      requireBrand(brandSnapshot, branch.brandId);
      const managers = await activeBranchManagers(transaction, firestore, branch.id, branch.data);
      if (managers.length === 0) {
        throw new PurchaseCommandError(
            "receiving-manager-not-configured", 409, "The receiving branch has no active manager.",
        );
      }
      const accountants = payload.items.some((item) => item.source_type === "unmatched") ?
        await activeUsersByRole(transaction, firestore, "accountant") : [];
      if (payload.items.some((item) => item.source_type === "unmatched") && accountants.length === 0) {
        throw new PurchaseCommandError("accountant-not-configured", 409, "No active accountant exists.");
      }

      const catalogInputs = payload.items.map((item, index) => ({item, index}))
          .filter((entry) => entry.item.source_type === "catalog");
      const productSnapshots = await Promise.all(catalogInputs.map((entry) => transaction.get(
          firestore.collection(COLLECTIONS.products).doc(entry.item.product_id),
      )));
      const productEntries = productSnapshots.map((snapshot, index) => {
        const input = catalogInputs[index];
        const product = snapshot.data();
        if (!snapshot.exists || product?.id !== input.item.product_id ||
            product.brand_id !== branch.brandId || product.active !== true) {
          throw new PurchaseCommandError(
              "product-brand-mismatch", 403, "A product does not belong to the receiving brand.",
          );
        }
        return {...input, product, groupId: String(product.group_id || "")};
      });
      const groupIds = [...new Set(productEntries.map((entry) => entry.groupId))];
      const groupSnapshots = await Promise.all(groupIds.map((id) => transaction.get(
          firestore.collection(COLLECTIONS.groups).doc(id),
      )));
      const groups = new Map(groupSnapshots.map((snapshot, index) => [groupIds[index], snapshot.data()]));

      const duplicateKeyId = supplierUniqueKey(payload);
      const duplicateRef = duplicateKeyId ? firestore.collection(COLLECTIONS.supplierKeys).doc(duplicateKeyId) : null;
      const duplicateSnapshot = duplicateRef ? await transaction.get(duplicateRef) : null;
      if (duplicateSnapshot?.exists) {
        throw new PurchaseCommandError(
            "duplicate-supplier-invoice", 409, "A matching supplier invoice already exists.",
        );
      }

      const catalogByIndex = new Map(productEntries.map((entry) => [entry.index, entry]));
      const items = payload.items.map((input, index) => {
        const base = {
          id: itemIds[index],
          invoice_id: invoiceRef.id,
          schema_version: 1,
          workflow_version: 1,
          workflow_identity: "purchase_invoice_v1",
          invoice_revision: 1,
          branch_ids: [branch.id],
          receiving_branch_id: branch.id,
          receiving_brand_id: branch.brandId,
          line_number: index + 1,
          item_id: itemIds[index],
          source_type: input.source_type,
          ordered_quantity: input.ordered_quantity,
          ...(input.line_notes ? {line_notes: input.line_notes} : {}),
        };
        if (input.source_type === "catalog") {
          const entry = catalogByIndex.get(index);
          const unit = catalogUnit(entry.product, input.unit_id);
          const canonical = catalogSnapshot(
              entry.product, groups.get(entry.groupId), unit, branch.brandId,
          );
          return {
            ...base,
            original_material_name: canonical.canonical_product_name,
            original_group_text: canonical.canonical_group_name,
            original_unit_text: canonical.canonical_unit_raw_value,
            ...canonical,
            review_status: REVIEW_STATUS.notRequired,
          };
        }
        return {
          ...base,
          original_material_name: input.material_name,
          original_group_text: input.group_text,
          original_unit_text: input.unit_text,
          review_task_id: taskIds[index],
          review_status: REVIEW_STATUS.pending,
        };
      });
      const itemDigest = purchaseItemDigest(items);
      const purchaseNumber = `PUR-${invoiceRef.id.slice(0, 8).toUpperCase()}`;
      const createdEvent = eventData(
          "purchase_invoice_created",
          "تم إنشاء فاتورة المشتريات وإرسالها إلى الفرع المستلم.",
          actor,
          timestamp,
      );
      const invoice = compact({
        id: invoiceRef.id,
        schema_version: 1,
        workflow_version: 1,
        workflow_identity: "purchase_invoice_v1",
        status: STATUS.pendingReceiverReview,
        revision: 1,
        purchase_number: purchaseNumber,
        receiving_branch_id: branch.id,
        receiving_branch_name: branch.name,
        receiving_brand_id: branch.brandId,
        branch_ids: [branch.id],
        item_count: items.length,
        item_digest: itemDigest,
        currency: payload.currency,
        supplier_name: payload.supplier_name,
        supplier_invoice_number: payload.supplier_invoice_number,
        supplier_invoice_date: payload.supplier_invoice_date,
        general_manager_notes: payload.general_manager_notes,
        created_by: actor.uid,
        created_by_name: actor.name,
        created_by_role: actor.role,
        created_at: timestamp,
        last_updated: timestamp,
        history: [createdEvent],
      });
      assertPublicHeader(invoice, invoiceRef.id);
      items.forEach((item) => assertPublicItem(invoice, item, item.item_id));

      const provisionalItems = payload.items.map((input, index) =>
        input.provisional_unit_price === undefined ? null : {
          item_id: itemIds[index], unit_price: input.provisional_unit_price,
        }).filter(Boolean);
      transaction.set(invoiceRef, invoice);
      items.forEach((item) => transaction.set(itemsCollection(invoiceRef).doc(item.item_id), item));
      transaction.set(firestore.collection(COLLECTIONS.prices).doc(invoiceRef.id), {
        id: invoiceRef.id,
        invoice_id: invoiceRef.id,
        invoice_revision: 1,
        pricing_revision: 0,
        pricing_state: "provisional",
        item_count: items.length,
        item_digest: itemDigest,
        currency: payload.currency,
        provisional_items: provisionalItems,
        locked: false,
        confirmed_by: actor.uid,
        confirmed_by_name: actor.name,
        confirmed_by_role: actor.role,
        confirmed_at: timestamp,
      });
      payload.items.forEach((input, index) => {
        if (input.source_type !== "unmatched") return;
        const taskId = taskIds[index];
        transaction.set(firestore.collection(COLLECTIONS.reviewTasks).doc(taskId), {
          id: taskId,
          invoice_id: invoiceRef.id,
          item_id: itemIds[index],
          brand_id: branch.brandId,
          receiving_branch_id: branch.id,
          status: REVIEW_STATUS.pending,
          revision: 1,
          original_material_name: input.material_name,
          original_group_text: input.group_text,
          original_unit_text: input.unit_text,
          original_snapshot_locked: true,
          created_by: actor.uid,
          created_by_name: actor.name,
          created_at: timestamp,
          updated_at: timestamp,
          history: [{
            action: "review_task_created",
            actor_id: actor.uid,
            actor_name: actor.name,
            actor_role: actor.role,
            created_at: timestamp,
          }],
        });
      });
      if (duplicateRef) {
        transaction.set(duplicateRef, {
          id: duplicateKeyId,
          invoice_id: invoiceRef.id,
          supplier_name_normalized: normalizeCatalogText(payload.supplier_name),
          supplier_invoice_number_normalized: normalizeCatalogText(payload.supplier_invoice_number),
          created_at: timestamp,
        });
      }
      writeEvent(transaction, firestore, {invoice, event: createdEvent, revision: 1});
      writeNotifications(transaction, firestore, {
        recipients: managers,
        invoice,
        type: "purchase_invoice_created",
        title: "فاتورة مشتريات بانتظار الاستلام",
        message: `فاتورة المشتريات ${purchaseNumber} بانتظار مراجعة الكميات.`,
        revision: 1,
        timestamp,
        excludeUid: actor.uid,
      });
      if (accountants.length > 0) {
        writeNotifications(transaction, firestore, {
          recipients: accountants,
          invoice,
          type: "purchase_product_review_required",
          title: "مواد مشتريات تحتاج مراجعة",
          message: `توجد مواد غير مطابقة للكتالوج في الفاتورة ${purchaseNumber}.`,
          revision: 1,
          timestamp,
          excludeUid: actor.uid,
        });
      }
      return {
        statusCode: 201,
        responseData: responseFor(invoiceRef.id, STATUS.pendingReceiverReview, 1, purchaseNumber),
      };
    },
  });
}

function receiptItems(storedItems, receivedItems, revision) {
  if (storedItems.length !== receivedItems.length) {
    throw new PurchaseCommandError("items-mismatch", 409, "Every item must be confirmed once.");
  }
  const byId = new Map(receivedItems.map((item) => [item.item_id, item]));
  return storedItems.map((stored) => {
    const received = byId.get(stored.item_id);
    if (!received) {
      throw new PurchaseCommandError("items-mismatch", 409, "Receipt items do not match.");
    }
    const maximumMissing = Math.max(stored.ordered_quantity - received.received_quantity, 0);
    if (received.missing_quantity > maximumMissing) {
      throw new PurchaseCommandError("quantity-inconsistent", 400, "Missing quantity is invalid.");
    }
    return compact({
      ...stored,
      invoice_revision: revision,
      received_quantity: received.received_quantity,
      damaged_quantity: received.damaged_quantity,
      missing_quantity: received.missing_quantity,
      discrepancy_notes: received.discrepancy_notes,
    });
  });
}

async function confirmReceipt({firestore, actorUid, invoiceId, payload, idempotencyKey, timestamp}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotent({
    firestore,
    command: "confirm_purchase_receipt",
    actorUid,
    expectedRole: "manager",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const rawSnapshot = await transaction.get(invoiceRef);
      const raw = rawSnapshot.data();
      const branchId = String(raw?.receiving_branch_id || "");
      if (!rawSnapshot.exists || actor.branchId !== branchId) {
        throw new PurchaseCommandError("forbidden", 403, "You cannot act for this branch.");
      }
      const branchSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.branches).doc(branchId),
      );
      const branch = cleanBranch(branchSnapshot, branchId);
      assertManager(actor, branchId, branch.data);
      const invoice = requireInvoice(rawSnapshot, invoiceId);
      requireState(invoice, STATUS.pendingReceiverReview, payload.expected_revision);
      const stored = await readItems(transaction, invoiceRef, invoice);
      const collectors = await activeUsersByRole(transaction, firestore, "collector");
      if (collectors.length === 0) {
        throw new PurchaseCommandError("general-manager-not-configured", 409, "No general manager exists.");
      }
      const revision = invoice.revision + 1;
      const items = receiptItems(stored, payload.items, revision);
      const digest = purchaseItemDigest(items);
      const event = eventData(
          "purchase_receipt_confirmed",
          "أكد مدير الفرع المستلم الكميات المستلمة.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, compact({
        status: STATUS.pendingPriceEntry,
        revision,
        item_digest: digest,
        receiver_notes: payload.receiver_notes,
        receipt_confirmed_by: actor.uid,
        receipt_confirmed_by_name: actor.name,
        receipt_confirmed_at: timestamp,
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      }));
      items.forEach((item) => transaction.set(itemsCollection(invoiceRef).doc(item.item_id), item));
      transaction.update(firestore.collection(COLLECTIONS.prices).doc(invoiceId), {
        invoice_revision: revision,
        item_digest: digest,
      });
      writeEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: collectors,
        invoice,
        type: "purchase_receipt_confirmed",
        title: "فاتورة مشتريات بانتظار التسعير",
        message: `تم استلام فاتورة المشتريات ${invoice.purchase_number}.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, STATUS.pendingPriceEntry, revision),
      };
    },
  });
}

function finalPriceItems(storedItems, inputs) {
  if (storedItems.length !== inputs.length) {
    throw new PurchaseCommandError("items-mismatch", 409, "Every item must be priced once.");
  }
  const byId = new Map(inputs.map((item) => [item.item_id, item.unit_price]));
  return storedItems.map((item) => {
    if (!byId.has(item.item_id) || !Number.isFinite(item.received_quantity)) {
      throw new PurchaseCommandError("items-mismatch", 409, "Pricing items do not match.");
    }
    const price = byId.get(item.item_id);
    const total = price * item.received_quantity;
    if (!Number.isFinite(total)) {
      throw new PurchaseCommandError("invalid-argument", 400, "A line total is invalid.");
    }
    return compact({
      item_id: item.item_id,
      source_type: item.source_type,
      original_material_name: item.original_material_name,
      original_unit_text: item.original_unit_text,
      canonical_product_id: item.canonical_product_id,
      canonical_product_version: item.canonical_product_version,
      canonical_unit_id: item.canonical_unit_id,
      canonical_unit_value: item.canonical_unit_value,
      receiving_brand_id: item.receiving_brand_id,
      ordered_quantity: item.ordered_quantity,
      received_quantity: item.received_quantity,
      unit_price: price,
      line_total: total,
    });
  });
}

function validateLatest(snapshot, entry, currency) {
  if (!snapshot.exists) return;
  const data = snapshot.data();
  if (data.id !== entry.latestKey || data.latest_key !== entry.latestKey ||
      data.brand_id !== entry.item.receiving_brand_id ||
      data.product_id !== entry.item.canonical_product_id ||
      data.unit_id !== entry.item.canonical_unit_id || data.currency !== currency ||
      typeof data.price !== "number" || !Number.isFinite(data.price) || data.price < 0 ||
      !Number.isSafeInteger(data.version) || data.version < 1) {
    throw new PurchaseCommandError("price-memory-conflict", 409, "Price memory is inconsistent.");
  }
}

function priceMemoryEntries(firestore, invoiceId, items, currency) {
  return items.filter((item) => item.canonical_product_id && item.canonical_unit_id)
      .map((item) => {
        const latestKey = productPriceLatestKey({
          brandId: item.receiving_brand_id,
          productId: item.canonical_product_id,
          unitId: item.canonical_unit_id,
          currency,
        });
        const historyId = deterministicDocumentId(
            "purchase-invoice-v1-price-history", invoiceId, item.item_id,
        );
        return {
          item,
          latestKey,
          latestRef: firestore.collection(COLLECTIONS.priceLatest).doc(latestKey),
          historyRef: firestore.collection(COLLECTIONS.priceHistory).doc(historyId),
        };
      });
}

function writePriceMemory(transaction, entries, latestSnapshots, currency, invoiceId, actor, timestamp) {
  entries.forEach((entry, index) => {
    const previous = latestSnapshots[index].data();
    const version = (Number.isSafeInteger(previous?.version) ? previous.version : 0) + 1;
    const common = {
      brand_id: entry.item.receiving_brand_id,
      product_id: entry.item.canonical_product_id,
      unit_id: entry.item.canonical_unit_id,
      unit_value: entry.item.canonical_unit_value,
      currency,
      price: entry.item.unit_price,
      source_invoice_id: invoiceId,
      changed_by: actor.uid,
      changed_by_name: actor.name,
      changed_by_role: actor.role,
      changed_at: timestamp,
      version,
    };
    transaction.set(entry.latestRef, {
      id: entry.latestKey,
      latest_key: entry.latestKey,
      history_event_id: entry.historyRef.id,
      ...common,
    });
    transaction.set(entry.historyRef, compact({
      id: entry.historyRef.id,
      latest_key: entry.latestKey,
      ...common,
      previous_price: typeof previous?.price === "number" ? previous.price : undefined,
      previous_source_invoice_id: optionalStored(previous?.source_invoice_id),
    }));
  });
}

async function confirmPrices({firestore, actorUid, invoiceId, payload, idempotencyKey, timestamp}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const priceRef = firestore.collection(COLLECTIONS.prices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotent({
    firestore,
    command: "confirm_purchase_prices",
    actorUid,
    expectedRole: "collector",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const [invoiceSnapshot, priceSnapshot] = await Promise.all([
        transaction.get(invoiceRef), transaction.get(priceRef),
      ]);
      const invoice = requireInvoice(invoiceSnapshot, invoiceId);
      requireState(invoice, STATUS.pendingPriceEntry, payload.expected_revision);
      const storedItems = await readItems(transaction, invoiceRef, invoice);
      const currentPrice = priceSnapshot.data();
      if (!priceSnapshot.exists || currentPrice?.locked !== false ||
          currentPrice?.pricing_state !== "provisional" ||
          currentPrice?.item_digest !== invoice.item_digest ||
          currentPrice?.invoice_revision !== invoice.revision ||
          currentPrice?.currency !== invoice.currency) {
        throw new PurchaseCommandError("price-snapshot-invalid", 409, "The protected price draft is invalid.");
      }
      const items = finalPriceItems(storedItems, payload.items);
      const memory = priceMemoryEntries(firestore, invoiceId, items, invoice.currency);
      const latestSnapshots = await Promise.all(memory.map((entry) => transaction.get(entry.latestRef)));
      latestSnapshots.forEach((snapshot, index) => validateLatest(snapshot, memory[index], invoice.currency));
      const historySnapshots = await Promise.all(memory.map((entry) => transaction.get(entry.historyRef)));
      if (historySnapshots.some((snapshot) => snapshot.exists)) {
        throw new PurchaseCommandError("price-history-conflict", 409, "A price history event exists.");
      }
      const accountants = await activeUsersByRole(transaction, firestore, "accountant");
      if (accountants.length === 0) {
        throw new PurchaseCommandError("accountant-not-configured", 409, "No active accountant exists.");
      }
      const revision = invoice.revision + 1;
      const total = items.reduce((sum, item) => sum + item.line_total, 0);
      if (!Number.isFinite(total)) {
        throw new PurchaseCommandError("invalid-argument", 400, "The invoice total is invalid.");
      }
      const protectedDocument = compact({
        id: invoiceId,
        invoice_id: invoiceId,
        invoice_revision: revision,
        pricing_revision: 1,
        pricing_state: "confirmed",
        item_count: invoice.item_count,
        item_digest: invoice.item_digest,
        currency: invoice.currency,
        provisional_items: Array.isArray(currentPrice.provisional_items) ?
          currentPrice.provisional_items : [],
        items,
        invoice_total: total,
        pricing_notes: payload.pricing_notes,
        confirmed_by: actor.uid,
        confirmed_by_name: actor.name,
        confirmed_by_role: actor.role,
        confirmed_at: timestamp,
        locked: false,
      });
      if (!hasOnlyKeys(protectedDocument, PROTECTED_PRICE_KEYS)) {
        throw new PurchaseCommandError("internal", 500, "The protected price schema is invalid.");
      }
      transaction.set(priceRef, protectedDocument);
      writePriceMemory(transaction, memory, latestSnapshots, invoice.currency, invoiceId, actor, timestamp);
      const event = eventData(
          "purchase_prices_confirmed",
          "أكد المدير العام أسعار فاتورة المشتريات.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, {
        status: STATUS.pendingAccountingEntry,
        revision,
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      });
      writeEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: accountants,
        invoice,
        type: "purchase_prices_confirmed",
        title: "فاتورة مشتريات جاهزة للمحاسبة",
        message: `فاتورة المشتريات ${invoice.purchase_number} جاهزة للترحيل.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, STATUS.pendingAccountingEntry, revision),
      };
    },
  });
}

function taskHistory(task, action, actor, timestamp, note, extra = {}) {
  const history = Array.isArray(task.history) ? task.history : [];
  return [...history, compact({
    action,
    actor_id: actor.uid,
    actor_name: actor.name,
    actor_role: actor.role,
    created_at: timestamp,
    note,
    ...extra,
  })];
}

function assertReviewTask(task, taskId, invoice, item, expectedRevision) {
  if (!task || task.id !== taskId || task.invoice_id !== invoice.id ||
      task.item_id !== item.item_id || task.brand_id !== invoice.receiving_brand_id ||
      task.receiving_branch_id !== invoice.receiving_branch_id ||
      task.original_snapshot_locked !== true ||
      task.original_material_name !== item.original_material_name ||
      task.original_group_text !== item.original_group_text ||
      task.original_unit_text !== item.original_unit_text ||
      !Number.isSafeInteger(task.revision) || task.revision !== expectedRevision) {
    throw new PurchaseCommandError("review-task-invalid", 409, "The review task is invalid.");
  }
}

function productAuditSnapshot(data) {
  const fields = [
    "id", "brand_id", "group_id", "name", "normalized_name", "legacy_code", "units",
    "primary_unit_id", "active", "version", "name_unique_key_id",
    "legacy_code_unique_key_id", "last_audit_event_id",
  ];
  return Object.fromEntries(fields.filter((field) => data[field] !== undefined)
      .map((field) => [field, data[field]]));
}

function groupAuditSnapshot(data) {
  const fields = [
    "id", "brand_id", "name", "normalized_name", "active", "last_audit_event_id",
    "is_system_group", "system_key",
  ];
  return Object.fromEntries(fields.filter((field) => data[field] !== undefined)
      .map((field) => [field, data[field]]));
}

function auditData({id, entityType, entityId, brandId, action, actor, timestamp, after}) {
  return {
    id,
    entity_type: entityType,
    entity_id: entityId,
    brand_id: brandId,
    action,
    after,
    actor_uid: actor.uid,
    actor_name: actor.name,
    actor_role: actor.role,
    created_at: timestamp,
  };
}

function uniqueKeyData({id, brandId, keyType, normalizedValue, productId, actor, timestamp}) {
  return {
    id,
    brand_id: brandId,
    key_type: keyType,
    normalized_value: normalizedValue,
    product_id: productId,
    active: true,
    created_by: actor.uid,
    created_at: timestamp,
    updated_by: actor.uid,
    updated_at: timestamp,
  };
}

function accountingProfileData({productId, brandId, reference, syncState, actor, timestamp, auditId}) {
  return compact({
    id: productId,
    product_id: productId,
    brand_id: brandId,
    accounting_reference: reference,
    sync_state: syncState || "not_synced",
    created_by: actor.uid,
    created_at: timestamp,
    updated_by: actor.uid,
    updated_at: timestamp,
    last_audit_event_id: auditId,
  });
}

async function reviewProductTask({
  firestore, actorUid, taskId, payload, idempotencyKey, timestamp, randomUUID,
}) {
  const productRef = firestore.collection(COLLECTIONS.products).doc();
  const requestHash = canonicalRequestHash({task_id: taskId, ...payload});
  return runIdempotent({
    firestore,
    command: `review_product_${payload.action}`,
    actorUid,
    expectedRole: "accountant",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const taskRef = firestore.collection(COLLECTIONS.reviewTasks).doc(taskId);
      const taskSnapshot = await transaction.get(taskRef);
      if (!taskSnapshot.exists) {
        throw new PurchaseCommandError("review-task-not-found", 404, "The review task was not found.");
      }
      const task = taskSnapshot.data();
      const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(String(task.invoice_id || ""));
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const invoice = requireInvoice(invoiceSnapshot, invoiceRef.id);
      if (invoice.revision !== payload.expected_invoice_revision) {
        throw new PurchaseCommandError("stale-revision", 409, "The invoice revision has changed.");
      }
      const itemRef = itemsCollection(invoiceRef).doc(String(task.item_id || ""));
      const itemSnapshot = await transaction.get(itemRef);
      if (!itemSnapshot.exists) {
        throw new PurchaseCommandError("review-task-invalid", 409, "The linked item is unavailable.");
      }
      const item = itemSnapshot.data();
      assertPublicItem(invoice, item, itemRef.id);
      assertReviewTask(task, taskId, invoice, item, payload.expected_revision);
      const priceRef = firestore.collection(COLLECTIONS.prices).doc(invoice.id);
      const priceSnapshot = await transaction.get(priceRef);
      const price = priceSnapshot.data();

      const pendingActions = new Set(["link_existing", "create_product", "request_clarification"]);
      if (pendingActions.has(payload.action) && task.status !== REVIEW_STATUS.pending) {
        throw new PurchaseCommandError("invalid-state", 409, "The task is not pending review.");
      }
      if (payload.action === "return_to_pending" && task.status !== REVIEW_STATUS.clarification) {
        throw new PurchaseCommandError("invalid-state", 409, "The task is not awaiting clarification.");
      }
      if (payload.action === "mark_synchronized" &&
          ![REVIEW_STATUS.linked, REVIEW_STATUS.created].includes(task.status)) {
        throw new PurchaseCommandError("invalid-state", 409, "The task has not been resolved.");
      }

      let selectedProduct;
      let selectedGroup;
      let selectedUnit;
      let selectedProductRef;
      let groupRef;
      let createGroup = false;
      let groupAuditRef;
      let nameKeyRef;
      let codeKeyRef;
      let nameKeySnapshot;
      let codeKeySnapshot;
      let productAuditRef;
      let accountingAuditRef;
      let accountingProfileRef;
      let accountingProfileSnapshot;

      if (payload.action === "link_existing") {
        selectedProductRef = firestore.collection(COLLECTIONS.products).doc(payload.product_id);
        const selectedProductSnapshot = await transaction.get(selectedProductRef);
        selectedProduct = selectedProductSnapshot.data();
        if (!selectedProductSnapshot.exists || selectedProduct?.id !== payload.product_id ||
            selectedProduct.brand_id !== invoice.receiving_brand_id || selectedProduct.active !== true) {
          throw new PurchaseCommandError("product-brand-mismatch", 403, "The selected product is invalid.");
        }
        groupRef = firestore.collection(COLLECTIONS.groups).doc(String(selectedProduct.group_id || ""));
        const groupSnapshot = await transaction.get(groupRef);
        selectedGroup = groupSnapshot.data();
        selectedUnit = catalogUnit(selectedProduct, payload.unit_id);
        catalogSnapshot(
            selectedProduct, selectedGroup, selectedUnit, invoice.receiving_brand_id,
        );
      }

      if (payload.action === "create_product") {
        const requestedGroupId = payload.group_id ||
          (task.original_group_text === "" ? uncategorizedGroupId(invoice.receiving_brand_id) : "");
        if (!requestedGroupId) {
          throw new PurchaseCommandError("group-required", 400, "A reviewed product group is required.");
        }
        groupRef = firestore.collection(COLLECTIONS.groups).doc(requestedGroupId);
        const groupSnapshot = await transaction.get(groupRef);
        selectedGroup = groupSnapshot.data();
        if (!groupSnapshot.exists && requestedGroupId === uncategorizedGroupId(invoice.receiving_brand_id)) {
          createGroup = true;
          groupAuditRef = firestore.collection(COLLECTIONS.productAudits).doc(randomUUID());
          selectedGroup = {
            id: requestedGroupId,
            brand_id: invoice.receiving_brand_id,
            name: "غير مصنف",
            normalized_name: normalizeCatalogText("غير مصنف"),
            is_system_group: true,
            system_key: "uncategorized",
            active: true,
            created_by: actor.uid,
            created_by_name: actor.name,
            created_at: timestamp,
            updated_by: actor.uid,
            updated_by_name: actor.name,
            updated_at: timestamp,
            last_audit_event_id: groupAuditRef.id,
          };
        } else if (!groupSnapshot.exists || selectedGroup?.brand_id !== invoice.receiving_brand_id ||
            selectedGroup.active !== true) {
          throw new PurchaseCommandError("group-invalid", 409, "The selected group is invalid.");
        }
        const normalizedName = normalizeCatalogText(payload.material_name);
        if (!normalizedName) {
          throw new PurchaseCommandError(
              "invalid-argument", 400, "The normalized product name is invalid.",
          );
        }
        const normalizedCode = normalizeLegacyCode(payload.legacy_code);
        const nameKeyId = productUniqueKeyId({
          brandId: invoice.receiving_brand_id,
          keyType: "name",
          normalizedValue: normalizedName,
        });
        const codeKeyId = normalizedCode ? productUniqueKeyId({
          brandId: invoice.receiving_brand_id,
          keyType: "legacy_code",
          normalizedValue: normalizedCode,
        }) : null;
        nameKeyRef = firestore.collection(COLLECTIONS.uniqueProductKeys).doc(nameKeyId);
        codeKeyRef = codeKeyId ? firestore.collection(COLLECTIONS.uniqueProductKeys).doc(codeKeyId) : null;
        nameKeySnapshot = await transaction.get(nameKeyRef);
        codeKeySnapshot = codeKeyRef ? await transaction.get(codeKeyRef) : null;
        if (nameKeySnapshot.exists || codeKeySnapshot?.exists) {
          throw new PurchaseCommandError("catalog-duplicate", 409, "A normalized duplicate product exists.");
        }
        productAuditRef = firestore.collection(COLLECTIONS.productAudits).doc(randomUUID());
        selectedProductRef = productRef;
        selectedProduct = compact({
          id: productRef.id,
          brand_id: invoice.receiving_brand_id,
          group_id: requestedGroupId,
          name: payload.material_name,
          normalized_name: normalizedName,
          legacy_code: payload.legacy_code,
          units: payload.units,
          primary_unit_id: payload.primary_unit_id,
          active: true,
          version: 1,
          name_unique_key_id: nameKeyId,
          legacy_code_unique_key_id: codeKeyId || undefined,
          last_audit_event_id: productAuditRef.id,
          created_by: actor.uid,
          created_by_name: actor.name,
          created_at: timestamp,
          updated_by: actor.uid,
          updated_by_name: actor.name,
          updated_at: timestamp,
        });
        selectedUnit = catalogUnit(selectedProduct, payload.primary_unit_id);
      }

      if (payload.action === "mark_synchronized") {
        selectedProductRef = firestore.collection(COLLECTIONS.products).doc(task.canonical_product_id);
        const selectedProductSnapshot = await transaction.get(selectedProductRef);
        selectedProduct = selectedProductSnapshot.data();
        if (!selectedProductSnapshot.exists || selectedProduct?.brand_id !== invoice.receiving_brand_id) {
          throw new PurchaseCommandError("product-brand-mismatch", 409, "The resolved product is unavailable.");
        }
      }

      const profileProductId = selectedProduct?.id;
      if (profileProductId && (payload.accounting_reference || payload.sync_state ||
          payload.action === "mark_synchronized")) {
        accountingProfileRef = firestore.collection(COLLECTIONS.accountingProfiles).doc(profileProductId);
        accountingProfileSnapshot = await transaction.get(accountingProfileRef);
        accountingAuditRef = firestore.collection(COLLECTIONS.productAudits).doc(randomUUID());
      }

      let nextStatus = task.status;
      let actionName;
      let canonical;
      if (payload.action === "request_clarification") {
        nextStatus = REVIEW_STATUS.clarification;
        actionName = "clarification_requested";
      } else if (payload.action === "return_to_pending") {
        nextStatus = REVIEW_STATUS.pending;
        actionName = "clarification_returned";
      } else if (payload.action === "link_existing") {
        nextStatus = REVIEW_STATUS.linked;
        actionName = "linked_existing_product";
        canonical = catalogSnapshot(
            selectedProduct, selectedGroup, selectedUnit, invoice.receiving_brand_id,
        );
      } else if (payload.action === "create_product") {
        nextStatus = REVIEW_STATUS.created;
        actionName = "created_catalog_product";
        canonical = catalogSnapshot(
            selectedProduct, selectedGroup, selectedUnit, invoice.receiving_brand_id,
        );
      } else {
        nextStatus = REVIEW_STATUS.synchronized;
        actionName = "marked_synchronized";
        canonical = {
          canonical_product_id: item.canonical_product_id,
          canonical_product_version: item.canonical_product_version,
          canonical_product_name: item.canonical_product_name,
          canonical_product_legacy_code: item.canonical_product_legacy_code,
          canonical_group_id: item.canonical_group_id,
          canonical_group_name: item.canonical_group_name,
          canonical_group_legacy_code: item.canonical_group_legacy_code,
          canonical_unit_id: item.canonical_unit_id,
          canonical_unit_value: item.canonical_unit_value,
          canonical_unit_raw_value: item.canonical_unit_raw_value,
        };
      }

      const nextTaskRevision = task.revision + 1;
      const nextInvoiceRevision = invoice.revision + 1;
      const nextItem = compact({
        ...item,
        ...(canonical || {}),
        invoice_revision: nextInvoiceRevision,
        review_status: nextStatus,
      });
      const allItems = await readItems(transaction, invoiceRef, invoice);
      const nextItems = allItems.map((entry) => entry.item_id === item.item_id ? nextItem : entry);
      const nextDigest = purchaseItemDigest(nextItems);

      let lateMemory = [];
      let lateLatestSnapshots = [];
      // Append price memory only when an unmatched item receives its first
      // canonical identity. Follow-up actions such as synchronization must not
      // attempt to recreate the immutable history event.
      if (canonical && !item.canonical_product_id && price?.pricing_state === "confirmed") {
        const protectedItem = Array.isArray(price.items) ?
          price.items.find((entry) => entry.item_id === item.item_id) : null;
        if (!protectedItem || typeof protectedItem.unit_price !== "number") {
          throw new PurchaseCommandError("price-snapshot-invalid", 409, "The price snapshot is invalid.");
        }
        lateMemory = priceMemoryEntries(firestore, invoice.id, [{
          ...protectedItem,
          ...canonical,
          receiving_brand_id: invoice.receiving_brand_id,
        }], invoice.currency);
        lateLatestSnapshots = await Promise.all(lateMemory.map((entry) => transaction.get(entry.latestRef)));
        lateLatestSnapshots.forEach((snapshot, index) =>
          validateLatest(snapshot, lateMemory[index], invoice.currency));
        const historySnapshots = await Promise.all(
            lateMemory.map((entry) => transaction.get(entry.historyRef)),
        );
        if (historySnapshots.some((snapshot) => snapshot.exists)) {
          throw new PurchaseCommandError("price-history-conflict", 409, "A price history event exists.");
        }
      }

      if (createGroup) {
        transaction.set(groupRef, selectedGroup);
        transaction.set(groupAuditRef, auditData({
          id: groupAuditRef.id,
          entityType: "product_group",
          entityId: selectedGroup.id,
          brandId: invoice.receiving_brand_id,
          action: "system_group_created",
          actor,
          timestamp,
          after: groupAuditSnapshot(selectedGroup),
        }));
      }
      if (payload.action === "create_product") {
        transaction.set(selectedProductRef, selectedProduct);
        transaction.set(nameKeyRef, uniqueKeyData({
          id: nameKeyRef.id,
          brandId: invoice.receiving_brand_id,
          keyType: "name",
          normalizedValue: selectedProduct.normalized_name,
          productId: selectedProduct.id,
          actor,
          timestamp,
        }));
        if (codeKeyRef) {
          transaction.set(codeKeyRef, uniqueKeyData({
            id: codeKeyRef.id,
            brandId: invoice.receiving_brand_id,
            keyType: "legacy_code",
            normalizedValue: normalizeLegacyCode(selectedProduct.legacy_code),
            productId: selectedProduct.id,
            actor,
            timestamp,
          }));
        }
        transaction.set(productAuditRef, auditData({
          id: productAuditRef.id,
          entityType: "product",
          entityId: selectedProduct.id,
          brandId: invoice.receiving_brand_id,
          action: "created",
          actor,
          timestamp,
          after: productAuditSnapshot(selectedProduct),
        }));
      }
      if (accountingProfileRef) {
        const current = accountingProfileSnapshot.data();
        const reference = payload.accounting_reference || current?.accounting_reference;
        const syncState = payload.action === "mark_synchronized" ? "synced" :
          (payload.sync_state || current?.sync_state || "not_synced");
        const profile = compact({
          ...accountingProfileData({
            productId: selectedProduct.id,
            brandId: invoice.receiving_brand_id,
            reference,
            syncState,
            actor,
            timestamp,
            auditId: accountingAuditRef.id,
          }),
          created_by: current?.created_by || actor.uid,
          created_at: current?.created_at || timestamp,
        });
        transaction.set(accountingProfileRef, profile);
        transaction.set(accountingAuditRef, compact({
          id: accountingAuditRef.id,
          entity_type: "product_accounting_profile",
          entity_id: selectedProduct.id,
          brand_id: invoice.receiving_brand_id,
          action: current ? "updated" : "created",
          ...(current ? {before: current} : {}),
          after: profile,
          actor_uid: actor.uid,
          actor_name: actor.name,
          actor_role: actor.role,
          created_at: timestamp,
        }));
      }

      transaction.update(taskRef, compact({
        status: nextStatus,
        revision: nextTaskRevision,
        canonical_product_id: canonical?.canonical_product_id || task.canonical_product_id,
        canonical_product_version: canonical?.canonical_product_version || task.canonical_product_version,
        canonical_product_name: canonical?.canonical_product_name || task.canonical_product_name,
        canonical_unit_id: canonical?.canonical_unit_id || task.canonical_unit_id,
        canonical_unit_value: canonical?.canonical_unit_value || task.canonical_unit_value,
        accounting_reference: payload.accounting_reference || task.accounting_reference,
        sync_state: payload.action === "mark_synchronized" ? "synced" :
          (payload.sync_state || task.sync_state),
        updated_by: actor.uid,
        updated_by_name: actor.name,
        updated_at: timestamp,
        history: taskHistory(task, actionName, actor, timestamp, payload.note, {
          before_status: task.status,
          after_status: nextStatus,
          canonical_product_id: canonical?.canonical_product_id,
        }),
      }));
      transaction.set(itemRef, nextItem);
      transaction.update(invoiceRef, {
        revision: nextInvoiceRevision,
        item_digest: nextDigest,
        last_updated: timestamp,
      });
      if (priceSnapshot.exists && price?.locked !== true) {
        const update = {invoice_revision: nextInvoiceRevision, item_digest: nextDigest};
        if (canonical && price.pricing_state === "confirmed") {
          update.items = price.items.map((entry) => entry.item_id === item.item_id ? compact({
            ...entry,
            canonical_product_id: canonical.canonical_product_id,
            canonical_product_version: canonical.canonical_product_version,
            canonical_unit_id: canonical.canonical_unit_id,
            canonical_unit_value: canonical.canonical_unit_value,
          }) : entry);
        }
        transaction.update(priceRef, update);
      }
      if (lateMemory.length > 0) {
        const priceActor = {
          uid: String(price.confirmed_by || invoice.created_by),
          name: String(price.confirmed_by_name || invoice.created_by_name),
          role: "collector",
        };
        writePriceMemory(
            transaction, lateMemory, lateLatestSnapshots, invoice.currency,
            invoice.id, priceActor, timestamp,
        );
      }
      const publicEventDetails = payload.action === "request_clarification" ? {
        action: "purchase_material_clarification_requested",
        message: "طلب المحاسب توضيح بيانات مادة في فاتورة المشتريات.",
      } : payload.action === "return_to_pending" ? {
        action: "purchase_material_review_resumed",
        message: "أعيدت مادة فاتورة المشتريات إلى قائمة المراجعة.",
      } : payload.action === "mark_synchronized" ? {
        action: "purchase_material_synchronized",
        message: "تم تأكيد مزامنة مادة فاتورة المشتريات محاسبيًا.",
      } : {
        action: "purchase_material_reconciled",
        message: invoice.status === STATUS.postedToAccounting ?
          "تمت مطابقة مادة الفاتورة بعد الترحيل دون تغيير البيانات المالية التاريخية." :
          "تمت مطابقة مادة فاتورة المشتريات مع الكتالوج.",
      };
      const publicEvent = eventData(
          publicEventDetails.action,
          publicEventDetails.message,
          actor,
          timestamp,
      );
      writeEvent(transaction, firestore, {
        invoice,
        event: publicEvent,
        revision: nextInvoiceRevision,
        suffix: taskId,
      });
      return {
        statusCode: 200,
        responseData: {
          ...responseFor(invoice.id, invoice.status, nextInvoiceRevision),
          task_id: taskId,
          task_status: nextStatus,
          task_revision: nextTaskRevision,
          ...(canonical?.canonical_product_id ? {product_id: canonical.canonical_product_id} : {}),
        },
      };
    },
  });
}

function approximatelyEqual(left, right) {
  if (left === right) return true;
  const scale = Math.max(1, Math.abs(left), Math.abs(right));
  return Math.abs(left - right) <= Number.EPSILON * scale * 2;
}

function assertProtectedPrice(invoice, items, price) {
  if (!price || !hasOnlyKeys(price, PROTECTED_PRICE_KEYS) || price.locked !== false ||
      price.id !== invoice.id || price.invoice_id !== invoice.id ||
      price.invoice_revision !== invoice.revision || price.pricing_revision !== 1 ||
      price.pricing_state !== "confirmed" || price.item_count !== invoice.item_count ||
      price.item_digest !== invoice.item_digest || price.currency !== invoice.currency ||
      price.confirmed_by_role !== "collector" || !Array.isArray(price.items) ||
      price.items.length !== items.length || typeof price.invoice_total !== "number" ||
      !Number.isFinite(price.invoice_total) || price.invoice_total < 0) {
    throw new PurchaseCommandError("price-snapshot-invalid", 409, "The protected prices are invalid.");
  }
  const publicById = new Map(items.map((item) => [item.item_id, item]));
  const ids = new Set();
  let total = 0;
  for (const protectedItem of price.items) {
    const item = publicById.get(protectedItem?.item_id);
    if (!item || ids.has(protectedItem.item_id) ||
        protectedItem.receiving_brand_id !== invoice.receiving_brand_id ||
        protectedItem.source_type !== item.source_type ||
        protectedItem.original_material_name !== item.original_material_name ||
        protectedItem.original_unit_text !== item.original_unit_text ||
        protectedItem.ordered_quantity !== item.ordered_quantity ||
        protectedItem.received_quantity !== item.received_quantity ||
        protectedItem.canonical_product_id !== item.canonical_product_id ||
        protectedItem.canonical_unit_id !== item.canonical_unit_id ||
        typeof protectedItem.unit_price !== "number" || protectedItem.unit_price < 0 ||
        typeof protectedItem.line_total !== "number" || protectedItem.line_total < 0 ||
        !approximatelyEqual(
            protectedItem.line_total,
            protectedItem.unit_price * protectedItem.received_quantity,
        )) {
      throw new PurchaseCommandError("price-snapshot-mismatch", 409, "Protected prices do not match.");
    }
    ids.add(protectedItem.item_id);
    total += protectedItem.line_total;
  }
  if (!approximatelyEqual(total, price.invoice_total)) {
    throw new PurchaseCommandError("price-snapshot-mismatch", 409, "The protected total is invalid.");
  }
}

async function postToAccounting({firestore, actorUid, invoiceId, payload, idempotencyKey, timestamp}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const priceRef = firestore.collection(COLLECTIONS.prices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotent({
    firestore,
    command: "post_purchase_accounting",
    actorUid,
    expectedRole: "accountant",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const [invoiceSnapshot, priceSnapshot] = await Promise.all([
        transaction.get(invoiceRef), transaction.get(priceRef),
      ]);
      const invoice = requireInvoice(invoiceSnapshot, invoiceId);
      requireState(invoice, STATUS.pendingAccountingEntry, payload.expected_revision);
      const items = await readItems(transaction, invoiceRef, invoice);
      const price = priceSnapshot.data();
      assertProtectedPrice(invoice, items, price);
      const tasksSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.reviewTasks).where("invoice_id", "==", invoiceId),
      );
      const unresolved = tasksSnapshot.docs.filter((doc) => ![
        REVIEW_STATUS.linked, REVIEW_STATUS.created, REVIEW_STATUS.synchronized,
      ].includes(doc.data()?.status));
      if (unresolved.length > 0 && !payload.override_unresolved_materials) {
        throw new PurchaseCommandError(
            "unresolved-materials", 409, "Product review tasks must be resolved before posting.",
        );
      }

      const branchSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.branches).doc(invoice.receiving_branch_id),
      );
      const managers = await activeBranchManagers(
          transaction, firestore, invoice.receiving_branch_id, branchSnapshot.data(),
      );
      const collectors = await activeUsersByRole(transaction, firestore, "collector");
      const revision = invoice.revision + 1;
      const override = unresolved.length > 0 ? {
        used: true,
        reason: payload.override_reason,
        unresolved_task_ids: unresolved.map((doc) => doc.id).sort(),
        approved_by: actor.uid,
        approved_by_name: actor.name,
        approved_at: timestamp,
      } : undefined;
      transaction.update(priceRef, compact({
        locked: true,
        locked_by: actor.uid,
        locked_by_name: actor.name,
        locked_at: timestamp,
        locked_invoice_revision: revision,
        accounting_reference: payload.accounting_reference,
        accountant_notes: payload.accountant_notes,
        posting_override: override,
      }));
      const event = eventData(
          unresolved.length > 0 ? "purchase_posted_with_review_override" : "purchase_posted",
          unresolved.length > 0 ?
            "تم ترحيل فاتورة المشتريات باستثناء محاسبي مدقق مع بقاء مواد في قائمة المراجعة." :
            "تم ترحيل فاتورة المشتريات إلى النظام المحاسبي.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, compact({
        status: STATUS.postedToAccounting,
        revision,
        posted_by: actor.uid,
        posted_by_name: actor.name,
        posted_at: timestamp,
        posted_with_unresolved_override: unresolved.length > 0 ? true : undefined,
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      }));
      writeEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: [...managers, ...collectors],
        invoice,
        type: unresolved.length > 0 ?
          "purchase_accounting_posted_with_override" : "purchase_accounting_posted",
        title: "تم ترحيل فاتورة المشتريات",
        message: `تم ترحيل فاتورة المشتريات ${invoice.purchase_number}.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, STATUS.postedToAccounting, revision),
      };
    },
  });
}

function createAuthentication({admin, firestore}) {
  const auth = admin.auth();
  return async (request, response, next) => {
    try {
      const token = bearerToken(request);
      if (!token) {
        throw new PurchaseCommandError("unauthenticated", 401, "Authentication is required.");
      }
      let decoded;
      try {
        decoded = await auth.verifyIdToken(token, true);
      } catch (_) {
        throw new PurchaseCommandError("unauthenticated", 401, "Authentication is required.");
      }
      const snapshot = await firestore.collection(COLLECTIONS.users).doc(decoded.uid).get();
      if (!snapshot.exists || !isOperationalProfile(snapshot.data())) {
        throw new PurchaseCommandError("forbidden", 403, "The account cannot perform this operation.");
      }
      request.purchaseAuth = {uid: decoded.uid};
      next();
    } catch (error) {
      const details = publicError(error);
      response.status(details.status).json(details.body);
    }
  };
}

function commandRoute({firestore, admin, now, randomUUID, validator, execute, taskRoute = false}) {
  return async (request, response) => {
    try {
      const idempotencyKey = validateIdempotencyKey(request.get("idempotency-key"));
      const payload = validator(request.body);
      const invoiceId = request.params.invoiceId === undefined ? undefined :
        documentId(request.params.invoiceId, "invoice_id");
      const taskId = request.params.taskId === undefined ? undefined :
        documentId(request.params.taskId, "task_id");
      const result = await execute({
        firestore,
        actorUid: request.purchaseAuth.uid,
        ...(invoiceId ? {invoiceId} : {}),
        ...(taskRoute && taskId ? {taskId} : {}),
        payload,
        idempotencyKey,
        timestamp: timestampFor(admin, now),
        randomUUID,
      });
      response.status(result.replay ? 200 : result.statusCode).json({
        ...result.responseData,
        ...(result.replay ? {idempotent_replay: true} : {}),
      });
    } catch (error) {
      const details = publicError(error);
      response.status(details.status).json(details.body);
    }
  };
}

function createPurchaseInvoiceCommandRouter({
  admin, firestore, now = () => new Date(), randomUUID = crypto.randomUUID,
}) {
  if (!admin || !firestore) throw new Error("Firebase Admin and Firestore are required.");
  const router = express.Router();
  router.use(createAuthentication({admin, firestore}));
  router.post("/purchase-invoices", commandRoute({
    firestore, admin, now, randomUUID, validator: validateCreatePayload,
    execute: createPurchaseInvoice,
  }));
  router.post("/purchase-invoices/:invoiceId/confirm-receipt", commandRoute({
    firestore, admin, now, randomUUID, validator: validateReceiptPayload,
    execute: confirmReceipt,
  }));
  router.post("/purchase-invoices/:invoiceId/confirm-prices", commandRoute({
    firestore, admin, now, randomUUID, validator: validatePricingPayload,
    execute: confirmPrices,
  }));
  router.post("/purchase-invoices/:invoiceId/post-accounting", commandRoute({
    firestore, admin, now, randomUUID, validator: validatePostingPayload,
    execute: postToAccounting,
  }));
  router.post("/product-review-tasks/:taskId/decide", commandRoute({
    firestore, admin, now, randomUUID, validator: validateReviewPayload,
    execute: reviewProductTask, taskRoute: true,
  }));
  return router;
}

module.exports = {
  COLLECTIONS,
  PURCHASE_JSON_LIMIT,
  REVIEW_STATUS,
  STATUS,
  assertProtectedPrice,
  createPurchaseInvoice,
  createPurchaseInvoiceCommandRouter,
  confirmPrices,
  confirmReceipt,
  finalPriceItems,
  isOperationalProfile,
  postToAccounting,
  reviewProductTask,
};
