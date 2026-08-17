const crypto = require("node:crypto");
const express = require("express");

const {
  CommandError,
  SUPPORTED_CURRENCIES,
  assertNoPriceLikeKeys,
  canonicalRequestHash,
  deterministicDocumentId,
  documentId,
  invoiceItemDigest,
  invoiceNumberFor,
  productPriceLatestKey,
  publicError,
  validateCreatePayload,
  validateIdempotencyKey,
  validatePostingPayload,
  validatePricingPayload,
  validateReceiptPayload,
} = require("./inter-branch-invoice-domain");

const COLLECTIONS = Object.freeze({
  users: "users",
  branches: "branches",
  brands: "brands",
  products: "products",
  groups: "product_groups",
  invoices: "inter_branch_invoices",
  invoiceEvents: "inter_branch_invoice_events",
  counters: "inter_branch_invoice_counters",
  invoicePrices: "inter_branch_invoice_prices",
  priceLatest: "product_price_latest",
  priceHistory: "product_price_history",
  commands: "inter_branch_invoice_commands",
  notifications: "notifications",
});

const STATUS = Object.freeze({
  pendingReceiverReview: "pendingReceiverReview",
  pendingPriceEntry: "pendingPriceEntry",
  pendingAccountingEntry: "pendingAccountingEntry",
  postedToAccounting: "postedToAccounting",
});

const ITEMS_SUBCOLLECTION = "items";
const INTER_BRANCH_JSON_LIMIT = "32kb";

const OPERATIONAL_ROLES = new Set(["manager", "collector", "accountant", "admin"]);
const CATALOG_SNAPSHOT_LIMITS = Object.freeze({
  productNameBytes: 400,
  groupNameBytes: 300,
  legacyCodeBytes: 128,
  unitValueBytes: 100,
});

const PUBLIC_INVOICE_KEYS = new Set([
  "id",
  "schema_version",
  "workflow_version",
  "creation_mode",
  "status",
  "revision",
  "invoice_number",
  "branch_code",
  "sending_branch_id",
  "sending_branch_name",
  "sending_brand_id",
  "receiving_branch_id",
  "receiving_branch_name",
  "receiving_brand_id",
  "branch_ids",
  "item_count",
  "invoice_notes",
  "receiver_notes",
  "item_digest",
  "created_by",
  "created_by_name",
  "created_by_role",
  "created_at",
  "receipt_confirmed_by",
  "receipt_confirmed_by_name",
  "receipt_confirmed_at",
  "accounting_reference",
  "posted_by",
  "posted_by_name",
  "posted_at",
  "last_updated",
  "history",
]);

const PUBLIC_ITEM_KEYS = new Set([
  "id",
  "invoice_id",
  "schema_version",
  "workflow_version",
  "creation_mode",
  "invoice_revision",
  "branch_ids",
  "sending_branch_id",
  "receiving_branch_id",
  "line_number",
  "item_id",
  "product_id",
  "product_version",
  "product_brand_id",
  "product_name",
  "product_legacy_code",
  "group_id",
  "group_name",
  "group_legacy_code",
  "unit_id",
  "unit_value",
  "unit_raw_value",
  "supplied_quantity",
  "line_notes",
  "received_quantity",
  "damaged_quantity",
  "missing_quantity",
  "discrepancy_notes",
]);

const PUBLIC_HISTORY_KEYS = new Set([
  "action",
  "message",
  "actor_id",
  "actor_name",
  "actor_role",
  "timestamp",
]);

const PROTECTED_SNAPSHOT_KEYS = new Set([
  "id",
  "invoice_id",
  "invoice_revision",
  "pricing_revision",
  "item_count",
  "item_digest",
  "currency",
  "items",
  "invoice_total",
  "pricing_notes",
  "confirmed_by",
  "confirmed_by_name",
  "confirmed_by_role",
  "confirmed_at",
  "locked",
]);

const PROTECTED_ITEM_KEYS = new Set([
  "item_id",
  "product_id",
  "product_brand_id",
  "unit_id",
  "unit_value",
  "supplied_quantity",
  "received_quantity",
  "unit_price",
  "line_total",
]);

function bearerToken(request) {
  const authorization = request.get("authorization") || "";
  return authorization.match(/^Bearer\s+(.+)$/i)?.[1];
}

function isOperationalProfile(profile) {
  return profile &&
    profile.isActive !== false &&
    profile.mustChangePassword !== true &&
    OPERATIONAL_ROLES.has(String(profile.role || ""));
}

function actorFromProfile(uid, profile) {
  return {
    uid,
    name: boundedSnapshotString(profile.name, uid, 200),
    role: String(profile.role || ""),
    branchId: String(profile.branchId || "").trim(),
  };
}

function boundedSnapshotString(value, fallback, maxCharacters) {
  const text = String(value || "").trim();
  return (text || String(fallback)).slice(0, maxCharacters);
}

function catalogSnapshotString(value, maximumBytes, {optional = false} = {}) {
  const text = String(value || "").trim();
  if ((!text && !optional) || Buffer.byteLength(text, "utf8") > maximumBytes) {
    throw new CommandError(
        "catalog-snapshot-invalid",
        409,
        "A catalog snapshot is incomplete or outside the supported size.",
    );
  }
  return text;
}

function optionalStoredString(value, maximumBytes) {
  return value === undefined ||
    (typeof value === "string" &&
      value.trim().length > 0 &&
      Buffer.byteLength(value, "utf8") <= maximumBytes);
}

function timestampFor(admin, now) {
  return admin.firestore.Timestamp.fromDate(now());
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
  if (!Array.isArray(invoice.history)) {
    throw new CommandError("invoice-malformed", 409, "The invoice history is invalid.");
  }
  return [...invoice.history, event];
}

function hasOnlyKeys(value, allowedKeys) {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.keys(value).every((key) => allowedKeys.has(key));
}

function hasAllKeys(value, requiredKeys) {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    [...requiredKeys].every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

function assertClosedPublicInvoice(invoice) {
  if (!hasOnlyKeys(invoice, PUBLIC_INVOICE_KEYS) ||
      !Array.isArray(invoice.history) ||
      invoice.history.some((event) => !hasOnlyKeys(event, PUBLIC_HISTORY_KEYS))) {
    throw new CommandError(
        "invoice-malformed",
        409,
        "The public invoice contains fields outside the supported schema.",
    );
  }
}


const REQUIRED_PUBLIC_ITEM_KEYS = new Set([
  "id",
  "invoice_id",
  "schema_version",
  "workflow_version",
  "creation_mode",
  "invoice_revision",
  "branch_ids",
  "sending_branch_id",
  "receiving_branch_id",
  "line_number",
  "item_id",
  "product_id",
  "product_version",
  "product_brand_id",
  "product_name",
  "group_id",
  "group_name",
  "unit_id",
  "unit_value",
  "unit_raw_value",
  "supplied_quantity",
]);

function assertClosedPublicItem(invoice, item, expectedId) {
  try {
    assertNoPriceLikeKeys(item, "invoice_item");
  } catch (error) {
    if (error instanceof CommandError && error.code === "price-field-forbidden") {
      throw new CommandError(
          "public-price-field-forbidden",
          409,
          "A public invoice item contains a forbidden protected field.",
      );
    }
    throw error;
  }
  if (!hasOnlyKeys(item, PUBLIC_ITEM_KEYS) ||
      !hasAllKeys(item, REQUIRED_PUBLIC_ITEM_KEYS) ||
      item.id !== expectedId ||
      item.item_id !== expectedId ||
      item.invoice_id !== invoice.id ||
      item.schema_version !== 2 ||
      item.workflow_version !== 2 ||
      item.creation_mode !== "direct_supplier_invoice" ||
      !Number.isSafeInteger(item.invoice_revision) ||
      item.invoice_revision < 1 ||
      item.invoice_revision > invoice.revision ||
      !Array.isArray(item.branch_ids) ||
      item.branch_ids.length !== 2 ||
      item.branch_ids[0] !== invoice.sending_branch_id ||
      item.branch_ids[1] !== invoice.receiving_branch_id ||
      item.sending_branch_id !== invoice.sending_branch_id ||
      item.receiving_branch_id !== invoice.receiving_branch_id ||
      !Number.isSafeInteger(item.line_number) ||
      item.line_number < 1 ||
      item.line_number > invoice.item_count ||
      typeof item.product_id !== "string" || !item.product_id ||
      !Number.isSafeInteger(item.product_version) || item.product_version < 1 ||
      item.product_brand_id !== invoice.sending_brand_id ||
      typeof item.product_name !== "string" || !item.product_name ||
      Buffer.byteLength(item.product_name, "utf8") > CATALOG_SNAPSHOT_LIMITS.productNameBytes ||
      !optionalStoredString(
          item.product_legacy_code,
          CATALOG_SNAPSHOT_LIMITS.legacyCodeBytes,
      ) ||
      typeof item.group_id !== "string" || !item.group_id ||
      typeof item.group_name !== "string" || !item.group_name ||
      Buffer.byteLength(item.group_name, "utf8") > CATALOG_SNAPSHOT_LIMITS.groupNameBytes ||
      !optionalStoredString(
          item.group_legacy_code,
          CATALOG_SNAPSHOT_LIMITS.legacyCodeBytes,
      ) ||
      typeof item.unit_id !== "string" || !item.unit_id ||
      typeof item.unit_value !== "string" || !item.unit_value ||
      Buffer.byteLength(item.unit_value, "utf8") > CATALOG_SNAPSHOT_LIMITS.unitValueBytes ||
      typeof item.unit_raw_value !== "string" || !item.unit_raw_value ||
      Buffer.byteLength(item.unit_raw_value, "utf8") > CATALOG_SNAPSHOT_LIMITS.unitValueBytes ||
      !optionalStoredString(item.line_notes, 100) ||
      !optionalStoredString(item.discrepancy_notes, 100) ||
      typeof item.supplied_quantity !== "number" ||
      !Number.isFinite(item.supplied_quantity) || item.supplied_quantity <= 0) {
    throw new CommandError("invoice-item-malformed", 409, "A public invoice item is invalid.");
  }
  if (item.received_quantity !== undefined &&
      (typeof item.received_quantity !== "number" ||
       !Number.isFinite(item.received_quantity) || item.received_quantity < 0)) {
    throw new CommandError("invoice-item-malformed", 409, "A received quantity is invalid.");
  }
  if (item.damaged_quantity !== undefined &&
      (typeof item.damaged_quantity !== "number" ||
       !Number.isFinite(item.damaged_quantity) || item.damaged_quantity < 0 ||
       item.damaged_quantity > item.received_quantity)) {
    throw new CommandError("invoice-item-malformed", 409, "A damaged quantity is invalid.");
  }
  if (item.missing_quantity !== undefined &&
      (typeof item.missing_quantity !== "number" ||
       !Number.isFinite(item.missing_quantity) || item.missing_quantity < 0)) {
    throw new CommandError("invoice-item-malformed", 409, "A missing quantity is invalid.");
  }
}

function requireV2Invoice(snapshot, expectedId) {
  if (!snapshot.exists) {
    throw new CommandError("invoice-not-found", 404, "The invoice was not found.");
  }
  const invoice = snapshot.data();
  if (invoice?.schema_version !== 2 ||
      invoice?.workflow_version !== 2 ||
      invoice?.creation_mode !== "direct_supplier_invoice") {
    throw new CommandError(
        "unsupported-workflow",
        409,
        "This command is available only for direct version-2 invoices.",
    );
  }
  if (!Number.isSafeInteger(invoice.revision) || invoice.revision < 1 ||
      !Number.isSafeInteger(invoice.item_count) || invoice.item_count < 1 ||
      invoice.item_count > 50 ||
      typeof invoice.item_digest !== "string" ||
      !/^[a-f0-9]{64}$/.test(invoice.item_digest)) {
    throw new CommandError("invoice-malformed", 409, "The invoice is invalid.");
  }
  if (expectedId && invoice.id !== expectedId) {
    throw new CommandError("invoice-malformed", 409, "The invoice identity is invalid.");
  }
  try {
    assertNoPriceLikeKeys(invoice, "invoice");
  } catch (error) {
    if (error instanceof CommandError && error.code === "price-field-forbidden") {
      throw new CommandError(
          "public-price-field-forbidden",
          409,
          "The public invoice contains a forbidden protected field.",
      );
    }
    throw error;
  }
  assertClosedPublicInvoice(invoice);
  return invoice;
}

function requireStatusAndRevision(invoice, status, revision) {
  if (invoice.status !== status) {
    throw new CommandError("invalid-state", 409, "The invoice is not in the required state.");
  }
  if (invoice.revision !== revision) {
    throw new CommandError("stale-revision", 409, "The invoice revision has changed.");
  }
}

function invoiceItemsCollection(invoiceRef) {
  return invoiceRef.collection(ITEMS_SUBCOLLECTION);
}

async function readV2PublicItems(transaction, invoiceRef, invoice) {
  const snapshot = await transaction.get(
      invoiceItemsCollection(invoiceRef).orderBy("line_number", "asc"),
  );
  if (snapshot.size !== invoice.item_count || snapshot.docs.length !== invoice.item_count) {
    throw new CommandError("items-mismatch", 409, "The invoice item count is inconsistent.");
  }
  const items = snapshot.docs.map((document) => {
    const item = document.data();
    assertClosedPublicItem(invoice, item, document.id);
    return item;
  });
  const itemIds = new Set();
  const lineNumbers = new Set();
  const selections = new Set();
  for (const item of items) {
    const selection = `${item.product_id}\u001f${item.unit_id}`;
    if (itemIds.has(item.item_id) ||
        lineNumbers.has(item.line_number) ||
        selections.has(selection)) {
      throw new CommandError("items-mismatch", 409, "The invoice contains duplicate items.");
    }
    itemIds.add(item.item_id);
    lineNumbers.add(item.line_number);
    selections.add(selection);
  }
  for (let lineNumber = 1; lineNumber <= invoice.item_count; lineNumber += 1) {
    if (!lineNumbers.has(lineNumber)) {
      throw new CommandError("items-mismatch", 409, "The invoice item order is incomplete.");
    }
  }
  if (invoiceItemDigest(items) !== invoice.item_digest) {
    throw new CommandError("item-digest-mismatch", 409, "The invoice item snapshot changed.");
  }
  return items;
}

function assertActorManagesBranch(actor, branchId, branch) {
  if (actor.role !== "manager" || actor.branchId !== branchId) {
    throw new CommandError("forbidden", 403, "You cannot act for this branch.");
  }
  const assignedManager = String(branch.branch_manager_id || "").trim();
  if (assignedManager && assignedManager !== actor.uid) {
    throw new CommandError("forbidden", 403, "You cannot act for this branch.");
  }
}

function activeDocument(data) {
  return data &&
    data.active !== false &&
    data.isActive !== false &&
    data.is_active !== false;
}

function activeCatalogDocument(data) {
  return data && data.active === true;
}

function cleanBranch(snapshot, branchId) {
  if (!snapshot.exists || !activeDocument(snapshot.data())) {
    throw new CommandError("branch-not-found", 404, "The selected branch is not active.");
  }
  const data = snapshot.data();
  const brandId = String(data.brand_id || "").trim();
  if (!brandId) {
    throw new CommandError("branch-brand-missing", 409, "The branch brand is not configured.");
  }
  return {
    id: branchId,
    name: boundedSnapshotString(data.name, branchId, 200),
    brandId,
    code: String(data.branch_code || "").trim().toUpperCase(),
    data,
  };
}

function requireBrand(snapshot, brandId) {
  if (!snapshot.exists || !activeDocument(snapshot.data())) {
    throw new CommandError("branch-brand-invalid", 409, "A branch brand is unavailable.");
  }
  const storedId = String(snapshot.data()?.id || "").trim();
  if (storedId && storedId !== brandId) {
    throw new CommandError("branch-brand-invalid", 409, "A branch brand is inconsistent.");
  }
}

async function readActor(transaction, firestore, uid, expectedRole) {
  const snapshot = await transaction.get(firestore.collection(COLLECTIONS.users).doc(uid));
  const profile = snapshot.data();
  if (!snapshot.exists || !isOperationalProfile(profile)) {
    throw new CommandError("forbidden", 403, "The account cannot perform this operation.");
  }
  const actor = actorFromProfile(uid, profile);
  if (actor.role !== expectedRole) {
    throw new CommandError("forbidden", 403, "The role cannot perform this operation.");
  }
  return actor;
}

function commandReference(firestore, command, actorUid, idempotencyKey) {
  const id = deterministicDocumentId("inter-branch-v2", command, actorUid, idempotencyKey);
  return firestore.collection(COLLECTIONS.commands).doc(id);
}

function readReplay(snapshot, command, actorUid, requestHash) {
  if (!snapshot.exists) return null;
  const data = snapshot.data();
  if (data?.command !== command ||
      data?.actor_uid !== actorUid ||
      data?.request_hash !== requestHash) {
    throw new CommandError(
        "idempotency-conflict",
        409,
        "The idempotency key was already used for another request.",
    );
  }
  if (!data.response_data || typeof data.response_data !== "object") {
    throw new CommandError("idempotency-record-invalid", 409, "The command receipt is invalid.");
  }
  return {
    statusCode: Number.isInteger(data.status_code) ? data.status_code : 200,
    responseData: data.response_data,
    replay: true,
  };
}

async function runIdempotentTransaction({
  admin,
  firestore,
  command,
  actorUid,
  expectedRole,
  idempotencyKey,
  requestHash,
  timestamp,
  execute,
}) {
  const commandRef = commandReference(firestore, command, actorUid, idempotencyKey);
  return firestore.runTransaction(async (transaction) => {
    const actor = await readActor(transaction, firestore, actorUid, expectedRole);
    const commandSnapshot = await transaction.get(commandRef);
    const replay = readReplay(commandSnapshot, command, actorUid, requestHash);
    if (replay) return replay;

    const result = await execute(transaction, actor);
    transaction.set(commandRef, {
      id: commandRef.id,
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
  const query = firestore.collection(COLLECTIONS.users).where("role", "==", role);
  const snapshot = await transaction.get(query);
  return snapshot.docs
      .filter((doc) => isOperationalProfile(doc.data()) && doc.data()?.role === role)
      .map((doc) => actorFromProfile(doc.id, doc.data()));
}

async function activeBranchManagers(transaction, firestore, branchId, branchData) {
  const recipients = new Map();
  const assignedUid = String(branchData?.branch_manager_id || "").trim();
  if (assignedUid) {
    const assigned = await transaction.get(firestore.collection(COLLECTIONS.users).doc(assignedUid));
    const profile = assigned.data();
    if (assigned.exists &&
        isOperationalProfile(profile) &&
        profile.role === "manager" &&
        String(profile.branchId || "") === branchId) {
      recipients.set(assignedUid, actorFromProfile(assignedUid, profile));
    }
    return [...recipients.values()];
  }

  const query = firestore.collection(COLLECTIONS.users).where("branchId", "==", branchId);
  const snapshot = await transaction.get(query);
  for (const doc of snapshot.docs) {
    const profile = doc.data();
    if (isOperationalProfile(profile) && profile.role === "manager") {
      recipients.set(doc.id, actorFromProfile(doc.id, profile));
    }
  }
  return [...recipients.values()];
}

function notificationReference(firestore, invoiceId, type, revision, recipientId) {
  const id = deterministicDocumentId(
      "inter-branch-v2-notification",
      invoiceId,
      type,
      String(revision),
      recipientId,
  );
  return firestore.collection(COLLECTIONS.notifications).doc(id);
}

function writeNotifications(transaction, firestore, {
  recipients,
  invoice,
  type,
  title,
  message,
  revision,
  timestamp,
  excludeUid,
}) {
  const unique = new Set();
  for (const recipient of recipients) {
    const uid = typeof recipient === "string" ? recipient : recipient.uid;
    if (!uid || uid === excludeUid || unique.has(uid)) continue;
    unique.add(uid);
    const reference = notificationReference(firestore, invoice.id, type, revision, uid);
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
      branch_id: invoice.sending_branch_id,
      branch_ids: [invoice.sending_branch_id, invoice.receiving_branch_id],
      reference_number: invoice.invoice_number,
      notification_type: type,
      inter_branch_invoice_id: invoice.id,
      created_at: timestamp,
    });
  }
}

function writePublicEvent(transaction, firestore, {invoice, event, revision}) {
  const eventId = deterministicDocumentId(
      "inter-branch-v2-event",
      invoice.id,
      String(revision),
      event.action,
  );
  transaction.set(firestore.collection(COLLECTIONS.invoiceEvents).doc(eventId), {
    id: eventId,
    invoice_id: invoice.id,
    workflow_version: 2,
    branch_ids: [invoice.sending_branch_id, invoice.receiving_branch_id],
    revision,
    action: event.action,
    message: event.message,
    actor_id: event.actor_id,
    actor_name: event.actor_name,
    actor_role: event.actor_role,
    created_at: event.timestamp,
  });
}

function catalogUnit(product, unitId) {
  if (!Array.isArray(product.units)) return null;
  return product.units.find((unit) =>
    unit && typeof unit === "object" && String(unit.unit_id || "") === unitId) || null;
}

function buildPublicCatalogItem({
  input,
  productId,
  product,
  group,
  itemId,
  invoiceId,
  supplyingBranchId,
  receivingBranchId,
  lineNumber,
}) {
  if (!activeCatalogDocument(product)) {
    throw new CommandError("product-inactive", 409, "A selected product is not active.");
  }
  const unit = catalogUnit(product, input.unit_id);
  if (!unit || unit.active === false) {
    throw new CommandError("unit-invalid", 409, "A selected unit does not belong to its product.");
  }
  const productName = catalogSnapshotString(
      product.name,
      CATALOG_SNAPSHOT_LIMITS.productNameBytes,
  );
  const groupName = catalogSnapshotString(
      group.name,
      CATALOG_SNAPSHOT_LIMITS.groupNameBytes,
  );
  const unitValue = catalogSnapshotString(
      unit.display_value,
      CATALOG_SNAPSHOT_LIMITS.unitValueBytes,
  );
  const unitRawValue = catalogSnapshotString(
      unit.raw_value || unitValue,
      CATALOG_SNAPSHOT_LIMITS.unitValueBytes,
  );
  const productLegacyCode = catalogSnapshotString(
      product.legacy_code,
      CATALOG_SNAPSHOT_LIMITS.legacyCodeBytes,
      {optional: true},
  );
  const groupLegacyCode = catalogSnapshotString(
      group.legacy_code,
      CATALOG_SNAPSHOT_LIMITS.legacyCodeBytes,
      {optional: true},
  );
  return {
    id: itemId,
    invoice_id: invoiceId,
    schema_version: 2,
    workflow_version: 2,
    creation_mode: "direct_supplier_invoice",
    invoice_revision: 1,
    branch_ids: [supplyingBranchId, receivingBranchId],
    sending_branch_id: supplyingBranchId,
    receiving_branch_id: receivingBranchId,
    line_number: lineNumber,
    item_id: itemId,
    product_id: productId,
    product_version: Number.isSafeInteger(product.version) ? product.version : 1,
    product_brand_id: String(product.brand_id),
    product_name: productName,
    ...(productLegacyCode ? {product_legacy_code: productLegacyCode} : {}),
    group_id: String(product.group_id),
    group_name: groupName,
    ...(groupLegacyCode ? {group_legacy_code: groupLegacyCode} : {}),
    unit_id: input.unit_id,
    unit_value: unitValue,
    unit_raw_value: unitRawValue,
    supplied_quantity: input.supplied_quantity,
    ...(input.line_notes ? {line_notes: input.line_notes} : {}),
  };
}

function validateCounter(snapshot, supplyingBranch) {
  if (!snapshot.exists) {
    throw new CommandError(
        "counter-uninitialized",
        409,
        "The supplying branch invoice counter must be initialized explicitly.",
    );
  }
  const data = snapshot.data();
  if (!Number.isSafeInteger(data?.next_number) ||
      data.next_number < 1 ||
      data.next_number >= Number.MAX_SAFE_INTEGER) {
    throw new CommandError("counter-invalid", 409, "The invoice counter is invalid.");
  }
  if (data.branch_id !== undefined && data.branch_id !== supplyingBranch.id) {
    throw new CommandError("counter-invalid", 409, "The invoice counter branch does not match.");
  }
  if (data.branch_code !== undefined &&
      String(data.branch_code).trim().toUpperCase() !== supplyingBranch.code) {
    throw new CommandError("counter-invalid", 409, "The invoice counter branch code does not match.");
  }
  return data.next_number;
}

function responseFor(invoiceId, invoiceNumber, status, revision) {
  return {
    invoice_id: invoiceId,
    ...(invoiceNumber ? {invoice_number: invoiceNumber} : {}),
    status,
    revision,
  };
}

async function createDirectInvoice({
  admin,
  firestore,
  actorUid,
  payload,
  idempotencyKey,
  timestamp,
  randomUUID,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc();
  const plannedItemIds = payload.items.map(() => randomUUID());
  const requestHash = canonicalRequestHash(payload);

  return runIdempotentTransaction({
    admin,
    firestore,
    command: "create_direct_invoice",
    actorUid,
    expectedRole: "manager",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      if (!actor.branchId) {
        throw new CommandError("forbidden", 403, "The manager is not assigned to a branch.");
      }
      if (actor.branchId === payload.receiving_branch_id) {
        throw new CommandError("same-branch", 400, "The receiving branch must be different.");
      }
      const supplyingRef = firestore.collection(COLLECTIONS.branches).doc(actor.branchId);
      const receivingRef = firestore
          .collection(COLLECTIONS.branches)
          .doc(payload.receiving_branch_id);
      const counterRef = firestore.collection(COLLECTIONS.counters).doc(actor.branchId);
      const [supplyingSnapshot, receivingSnapshot, counterSnapshot] = await Promise.all([
        transaction.get(supplyingRef),
        transaction.get(receivingRef),
        transaction.get(counterRef),
      ]);
      const supplying = cleanBranch(supplyingSnapshot, actor.branchId);
      const receiving = cleanBranch(receivingSnapshot, payload.receiving_branch_id);
      assertActorManagesBranch(actor, supplying.id, supplying.data);
      const nextNumber = validateCounter(counterSnapshot, supplying);
      const invoiceNumber = invoiceNumberFor(supplying.code, nextNumber);

      const [supplyingBrandSnapshot, receivingBrandSnapshot] = await Promise.all([
        transaction.get(firestore.collection(COLLECTIONS.brands).doc(supplying.brandId)),
        transaction.get(firestore.collection(COLLECTIONS.brands).doc(receiving.brandId)),
      ]);
      requireBrand(supplyingBrandSnapshot, supplying.brandId);
      requireBrand(receivingBrandSnapshot, receiving.brandId);

      const productRefs = payload.items.map((item) =>
        firestore.collection(COLLECTIONS.products).doc(item.product_id));
      const productSnapshots = await Promise.all(
          productRefs.map((reference) => transaction.get(reference)),
      );
      const productData = productSnapshots.map((snapshot, index) => {
        if (!snapshot.exists) {
          throw new CommandError("product-not-found", 404, "A selected product was not found.");
        }
        const product = snapshot.data();
        if (product.id !== payload.items[index].product_id ||
            !Number.isSafeInteger(product.version) ||
            product.version < 1) {
          throw new CommandError("catalog-snapshot-invalid", 409, "A product identity is invalid.");
        }
        if (String(product.brand_id || "") !== supplying.brandId) {
          throw new CommandError(
              "product-brand-mismatch",
              403,
              "A selected product does not belong to the supplying brand.",
          );
        }
        const groupId = String(product.group_id || "").trim();
        if (!groupId) {
          throw new CommandError("catalog-snapshot-invalid", 409, "A product group is missing.");
        }
        return {product, groupId, productId: payload.items[index].product_id};
      });
      const uniqueGroupIds = [...new Set(productData.map((entry) => entry.groupId))];
      const groupSnapshots = await Promise.all(uniqueGroupIds.map((groupId) =>
        transaction.get(firestore.collection(COLLECTIONS.groups).doc(groupId))));
      const groups = new Map();
      groupSnapshots.forEach((snapshot, index) => {
        const groupId = uniqueGroupIds[index];
        const group = snapshot.data();
        if (!snapshot.exists ||
            group?.id !== groupId ||
            !activeCatalogDocument(group) ||
            String(group.brand_id || "") !== supplying.brandId) {
          throw new CommandError("group-invalid", 409, "A product group is not active for the brand.");
        }
        groups.set(groupId, group);
      });
      const recipients = await activeBranchManagers(
          transaction,
          firestore,
          receiving.id,
          receiving.data,
      );
      if (recipients.length === 0) {
        throw new CommandError(
            "receiving-manager-not-configured",
            409,
            "The receiving branch has no active manager.",
        );
      }

      const items = productData.map((entry, index) => buildPublicCatalogItem({
        input: payload.items[index],
        productId: entry.productId,
        product: entry.product,
        group: groups.get(entry.groupId),
        itemId: plannedItemIds[index],
        invoiceId: invoiceRef.id,
        supplyingBranchId: supplying.id,
        receivingBranchId: receiving.id,
        lineNumber: index + 1,
      }));
      const itemDigest = invoiceItemDigest(items);
      const createdEvent = eventData(
          "direct_invoice_created",
          "تم إنشاء فاتورة تحويل مباشرة وإرسالها إلى الفرع المستلم.",
          actor,
          timestamp,
      );
      const publicInvoice = {
        id: invoiceRef.id,
        schema_version: 2,
        workflow_version: 2,
        creation_mode: "direct_supplier_invoice",
        status: STATUS.pendingReceiverReview,
        revision: 1,
        invoice_number: invoiceNumber,
        branch_code: supplying.code,
        sending_branch_id: supplying.id,
        sending_branch_name: supplying.name,
        sending_brand_id: supplying.brandId,
        receiving_branch_id: receiving.id,
        receiving_branch_name: receiving.name,
        receiving_brand_id: receiving.brandId,
        branch_ids: [supplying.id, receiving.id],
        item_count: items.length,
        item_digest: itemDigest,
        ...(payload.invoice_notes ? {invoice_notes: payload.invoice_notes} : {}),
        created_by: actor.uid,
        created_by_name: actor.name,
        created_by_role: actor.role,
        created_at: timestamp,
        last_updated: timestamp,
        history: [createdEvent],
      };
      assertNoPriceLikeKeys(publicInvoice, "invoice");
      assertClosedPublicInvoice(publicInvoice);
      items.forEach((item) => assertClosedPublicItem(publicInvoice, item, item.item_id));

      transaction.set(invoiceRef, publicInvoice);
      items.forEach((item) => {
        transaction.set(invoiceItemsCollection(invoiceRef).doc(item.item_id), item);
      });
      writePublicEvent(transaction, firestore, {
        invoice: publicInvoice,
        event: createdEvent,
        revision: 1,
      });
      transaction.update(counterRef, {
        branch_id: supplying.id,
        branch_code: supplying.code,
        next_number: nextNumber + 1,
        last_invoice_number: invoiceNumber,
        last_updated: timestamp,
      });
      writeNotifications(transaction, firestore, {
        recipients,
        invoice: publicInvoice,
        type: "inter_branch_v2_direct_created",
        title: "فاتورة تحويل بين الفروع بانتظار الاستلام",
        message: `الفاتورة رقم ${invoiceNumber} بانتظار مراجعة الفرع المستلم.`,
        revision: 1,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 201,
        responseData: responseFor(
            invoiceRef.id,
            invoiceNumber,
            STATUS.pendingReceiverReview,
            1,
        ),
      };
    },
  });
}

function receiptItemsForInvoice(invoiceItems, receivedItems) {
  if (invoiceItems.length !== receivedItems.length) {
    throw new CommandError("items-mismatch", 409, "Every invoice item must be confirmed once.");
  }
  const receivedById = new Map(receivedItems.map((item) => [item.item_id, item]));
  return invoiceItems.map((rawItem) => {
    const item = rawItem && typeof rawItem === "object" ? rawItem : null;
    const itemId = String(item?.item_id || "");
    const receipt = receivedById.get(itemId);
    if (!item || !receipt) {
      throw new CommandError("items-mismatch", 409, "The receipt items do not match the invoice.");
    }
    const supplied = Number(item.supplied_quantity);
    if (!Number.isFinite(supplied) || supplied <= 0) {
      throw new CommandError("invoice-malformed", 409, "An invoice quantity is invalid.");
    }
    const maximumMissing = Math.max(supplied - receipt.received_quantity, 0);
    if (receipt.missing_quantity > maximumMissing) {
      throw new CommandError(
          "quantity-inconsistent",
          400,
          "Missing quantity cannot exceed the supplied quantity.",
      );
    }
    return {
      ...item,
      received_quantity: receipt.received_quantity,
      damaged_quantity: receipt.damaged_quantity,
      missing_quantity: receipt.missing_quantity,
      ...(receipt.discrepancy_notes ?
        {discrepancy_notes: receipt.discrepancy_notes} : {}),
    };
  });
}

async function confirmReceipt({
  admin,
  firestore,
  actorUid,
  invoiceId,
  payload,
  idempotencyKey,
  timestamp,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotentTransaction({
    admin,
    firestore,
    command: "confirm_receipt",
    actorUid,
    expectedRole: "manager",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const rawInvoice = invoiceSnapshot.exists ? invoiceSnapshot.data() : null;
      const branchId = String(rawInvoice?.receiving_branch_id || "");
      if (!invoiceSnapshot.exists || !branchId || actor.branchId !== branchId) {
        throw new CommandError("forbidden", 403, "You cannot act for this branch.");
      }
      const branchSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.branches).doc(branchId),
      );
      const branch = cleanBranch(branchSnapshot, branchId);
      assertActorManagesBranch(actor, branch.id, branch.data);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      requireStatusAndRevision(invoice, STATUS.pendingReceiverReview, payload.expected_revision);
      const storedItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      const revision = invoice.revision + 1;
      const items = receiptItemsForInvoice(storedItems, payload.items).map((item) => ({
        ...item,
        invoice_revision: revision,
      }));
      const itemDigest = invoiceItemDigest(items);
      const collectors = await activeUsersByRole(transaction, firestore, "collector");
      if (collectors.length === 0) {
        throw new CommandError(
            "general-manager-not-configured",
            409,
            "No active general manager is configured.",
        );
      }
      const event = eventData(
          "receipt_confirmed",
          "أكد مدير الفرع المستلم الكميات المستلمة.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, {
        item_digest: itemDigest,
        status: STATUS.pendingPriceEntry,
        revision,
        ...(payload.receiver_notes ? {receiver_notes: payload.receiver_notes} : {}),
        receipt_confirmed_by: actor.uid,
        receipt_confirmed_by_name: actor.name,
        receipt_confirmed_at: timestamp,
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      });
      items.forEach((item) => {
        assertClosedPublicItem({...invoice, revision}, item, item.item_id);
        transaction.set(invoiceItemsCollection(invoiceRef).doc(item.item_id), item);
      });
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: collectors,
        invoice,
        type: "inter_branch_v2_receipt_confirmed",
        title: "فاتورة تحويل بانتظار التسعير",
        message: `تم تأكيد استلام الفاتورة رقم ${invoice.invoice_number}.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, null, STATUS.pendingPriceEntry, revision),
      };
    },
  });
}

function priceItemsForInvoice(invoiceItems, pricingItems) {
  if (invoiceItems.length !== pricingItems.length) {
    throw new CommandError("items-mismatch", 409, "Every received item must be priced once.");
  }
  const prices = new Map(pricingItems.map((item) => [item.item_id, item.unit_price]));
  const invoiceItemIds = new Set();
  return invoiceItems.map((item) => {
    const itemId = String(item?.item_id || "");
    if (!prices.has(itemId) ||
        invoiceItemIds.has(itemId) ||
        !Number.isFinite(Number(item.received_quantity))) {
      throw new CommandError("items-mismatch", 409, "The pricing items do not match the invoice.");
    }
    invoiceItemIds.add(itemId);
    const unitPrice = prices.get(itemId);
    const lineTotal = Number(item.received_quantity) * unitPrice;
    if (!Number.isFinite(lineTotal)) {
      throw new CommandError("invalid-argument", 400, "A line total is outside the supported range.");
    }
    return {
      item_id: itemId,
      product_id: String(item.product_id),
      product_brand_id: String(item.product_brand_id),
      unit_id: String(item.unit_id),
      unit_value: String(item.unit_value),
      supplied_quantity: Number(item.supplied_quantity),
      received_quantity: Number(item.received_quantity),
      unit_price: unitPrice,
      line_total: lineTotal,
    };
  });
}

function validateExistingLatestPrice(snapshot, entry, currency) {
  if (!snapshot.exists) return;
  const previous = snapshot.data();
  if (previous?.id !== entry.latestKey ||
      previous?.latest_key !== entry.latestKey ||
      previous?.brand_id !== entry.item.product_brand_id ||
      previous?.product_id !== entry.item.product_id ||
      previous?.unit_id !== entry.item.unit_id ||
      typeof previous?.unit_value !== "string" ||
      !previous.unit_value.trim() ||
      previous?.currency !== currency ||
      typeof previous?.price !== "number" ||
      !Number.isFinite(previous.price) ||
      previous.price < 0 ||
      !Number.isSafeInteger(previous?.version) ||
      previous.version < 1 ||
      typeof previous?.source_invoice_id !== "string" ||
      !previous.source_invoice_id) {
    throw new CommandError(
        "price-memory-conflict",
        409,
        "The protected latest-price record is inconsistent.",
    );
  }
}

async function confirmPrices({
  admin,
  firestore,
  actorUid,
  invoiceId,
  payload,
  idempotencyKey,
  timestamp,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const snapshotRef = firestore.collection(COLLECTIONS.invoicePrices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotentTransaction({
    admin,
    firestore,
    command: "confirm_prices",
    actorUid,
    expectedRole: "collector",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const [invoiceSnapshot, protectedSnapshot] = await Promise.all([
        transaction.get(invoiceRef),
        transaction.get(snapshotRef),
      ]);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      requireStatusAndRevision(invoice, STATUS.pendingPriceEntry, payload.expected_revision);
      if (protectedSnapshot.exists) {
        throw new CommandError("price-snapshot-exists", 409, "The invoice was already priced.");
      }
      const storedItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      const protectedItems = priceItemsForInvoice(storedItems, payload.items);
      const recalculatedDigest = invoiceItemDigest(storedItems);
      if (!invoice.item_digest || invoice.item_digest !== recalculatedDigest) {
        throw new CommandError("item-digest-mismatch", 409, "The invoice item snapshot changed.");
      }
      const latestEntries = protectedItems.map((item) => {
        const latestKey = productPriceLatestKey({
          brandId: item.product_brand_id,
          productId: item.product_id,
          unitId: item.unit_id,
          currency: payload.currency,
        });
        const historyId = deterministicDocumentId(
            "inter-branch-v2-price-history",
            invoiceId,
            item.item_id,
            "1",
        );
        return {
          item,
          latestKey,
          latestRef: firestore.collection(COLLECTIONS.priceLatest).doc(latestKey),
          historyRef: firestore.collection(COLLECTIONS.priceHistory).doc(historyId),
        };
      });
      const latestSnapshots = await Promise.all(
          latestEntries.map((entry) => transaction.get(entry.latestRef)),
      );
      latestSnapshots.forEach((snapshot, index) =>
        validateExistingLatestPrice(snapshot, latestEntries[index], payload.currency));
      const historySnapshots = await Promise.all(
          latestEntries.map((entry) => transaction.get(entry.historyRef)),
      );
      if (historySnapshots.some((snapshot) => snapshot.exists)) {
        throw new CommandError("price-history-conflict", 409, "A protected history event exists.");
      }
      const accountants = await activeUsersByRole(transaction, firestore, "accountant");
      if (accountants.length === 0) {
        throw new CommandError("accountant-not-configured", 409, "No active accountant is configured.");
      }

      const revision = invoice.revision + 1;
      const invoiceTotal = protectedItems.reduce((total, item) => total + item.line_total, 0);
      if (!Number.isFinite(invoiceTotal)) {
        throw new CommandError("invalid-argument", 400, "The invoice total is outside the supported range.");
      }
      transaction.set(snapshotRef, {
        id: invoiceId,
        invoice_id: invoiceId,
        invoice_revision: revision,
        pricing_revision: 1,
        item_count: invoice.item_count,
        item_digest: invoice.item_digest,
        currency: payload.currency,
        items: protectedItems,
        invoice_total: invoiceTotal,
        ...(payload.pricing_notes ? {pricing_notes: payload.pricing_notes} : {}),
        confirmed_by: actor.uid,
        confirmed_by_name: actor.name,
        confirmed_by_role: actor.role,
        confirmed_at: timestamp,
        locked: false,
      });

      latestEntries.forEach((entry, index) => {
        const previous = latestSnapshots[index].data();
        const version = (Number.isSafeInteger(previous?.version) ? previous.version : 0) + 1;
        const common = {
          brand_id: entry.item.product_brand_id,
          product_id: entry.item.product_id,
          unit_id: entry.item.unit_id,
          unit_value: entry.item.unit_value,
          currency: payload.currency,
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
        transaction.set(entry.historyRef, {
          id: entry.historyRef.id,
          latest_key: entry.latestKey,
          ...common,
          ...(typeof previous?.price === "number" ? {previous_price: previous.price} : {}),
          ...(typeof previous?.source_invoice_id === "string" ?
            {previous_source_invoice_id: previous.source_invoice_id} : {}),
          ...(typeof previous?.unit_value === "string" &&
              previous.unit_value !== entry.item.unit_value ?
            {previous_unit_value: previous.unit_value} : {}),
        });
      });
      const publicEvent = eventData(
          "prices_confirmed",
          "أكد المدير العام تسعير الفاتورة.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, {
        status: STATUS.pendingAccountingEntry,
        revision,
        last_updated: timestamp,
        history: historyWithEvent(invoice, publicEvent),
      });
      writePublicEvent(transaction, firestore, {invoice, event: publicEvent, revision});
      writeNotifications(transaction, firestore, {
        recipients: accountants,
        invoice,
        type: "inter_branch_v2_prices_confirmed",
        title: "فاتورة تحويل جاهزة للترحيل المحاسبي",
        message: `الفاتورة رقم ${invoice.invoice_number} جاهزة للترحيل المحاسبي.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, null, STATUS.pendingAccountingEntry, revision),
      };
    },
  });
}

function approximatelyEqual(left, right) {
  if (left === right) return true;
  const scale = Math.max(1, Math.abs(left), Math.abs(right));
  return Math.abs(left - right) <= Number.EPSILON * scale * 2;
}

function assertProtectedSnapshotMatchesInvoice(invoice, publicItems, snapshot) {
  if (!snapshot ||
      snapshot.locked !== false ||
      !hasOnlyKeys(snapshot, PROTECTED_SNAPSHOT_KEYS)) {
    throw new CommandError("price-snapshot-invalid", 409, "The protected price snapshot is unavailable.");
  }
  if (snapshot.id !== invoice.id ||
      snapshot.invoice_id !== invoice.id ||
      snapshot.invoice_revision !== invoice.revision ||
      !Number.isSafeInteger(snapshot.pricing_revision) ||
      snapshot.pricing_revision < 1 ||
      snapshot.item_count !== invoice.item_count ||
      snapshot.item_digest !== invoice.item_digest ||
      !SUPPORTED_CURRENCIES.has(snapshot.currency) ||
      !Number.isFinite(snapshot.invoice_total) ||
      snapshot.invoice_total < 0 ||
      snapshot.confirmed_by_role !== "collector" ||
      !Array.isArray(snapshot.items) ||
      snapshot.items.length !== publicItems.length) {
    throw new CommandError("price-snapshot-mismatch", 409, "The protected snapshot does not match.");
  }
  const digest = invoiceItemDigest(publicItems);
  if (digest !== invoice.item_digest) {
    throw new CommandError("item-digest-mismatch", 409, "The public item snapshot changed.");
  }
  const publicById = new Map(publicItems.map((item) => [item.item_id, item]));
  const protectedIds = new Set();
  let calculatedInvoiceTotal = 0;
  for (const item of snapshot.items) {
    const publicItem = publicById.get(item?.item_id);
    if (!publicItem ||
        protectedIds.has(item.item_id) ||
        !hasOnlyKeys(item, PROTECTED_ITEM_KEYS)) {
      throw new CommandError("price-snapshot-mismatch", 409, "The protected items do not match.");
    }
    protectedIds.add(item.item_id);
    const expectedLineTotal = Number(publicItem.received_quantity) * item.unit_price;
    if (item.product_id !== publicItem.product_id ||
        item.product_brand_id !== publicItem.product_brand_id ||
        item.unit_id !== publicItem.unit_id ||
        item.unit_value !== publicItem.unit_value ||
        item.supplied_quantity !== publicItem.supplied_quantity ||
        item.received_quantity !== publicItem.received_quantity ||
        !Number.isFinite(item.supplied_quantity) ||
        item.supplied_quantity <= 0 ||
        !Number.isFinite(item.received_quantity) ||
        item.received_quantity < 0 ||
        !Number.isFinite(item.unit_price) ||
        item.unit_price < 0 ||
        !Number.isFinite(item.line_total) ||
        item.line_total < 0 ||
        !Number.isFinite(expectedLineTotal) ||
        !approximatelyEqual(item.line_total, expectedLineTotal)) {
      throw new CommandError("price-snapshot-mismatch", 409, "The protected items do not match.");
    }
    calculatedInvoiceTotal += item.line_total;
    if (!Number.isFinite(calculatedInvoiceTotal)) {
      throw new CommandError("price-snapshot-mismatch", 409, "The protected total is invalid.");
    }
  }
  if (!approximatelyEqual(calculatedInvoiceTotal, snapshot.invoice_total)) {
    throw new CommandError("price-snapshot-mismatch", 409, "The protected total does not match.");
  }
}

async function postToAccounting({
  admin,
  firestore,
  actorUid,
  invoiceId,
  payload,
  idempotencyKey,
  timestamp,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const snapshotRef = firestore.collection(COLLECTIONS.invoicePrices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotentTransaction({
    admin,
    firestore,
    command: "post_accounting",
    actorUid,
    expectedRole: "accountant",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const [invoiceSnapshot, priceSnapshot] = await Promise.all([
        transaction.get(invoiceRef),
        transaction.get(snapshotRef),
      ]);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      requireStatusAndRevision(invoice, STATUS.pendingAccountingEntry, payload.expected_revision);
      const storedItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      assertProtectedSnapshotMatchesInvoice(invoice, storedItems, priceSnapshot.data());

      const [supplyingBranchSnapshot, receivingBranchSnapshot] = await Promise.all([
        transaction.get(
            firestore.collection(COLLECTIONS.branches).doc(invoice.sending_branch_id),
        ),
        transaction.get(
            firestore.collection(COLLECTIONS.branches).doc(invoice.receiving_branch_id),
        ),
      ]);
      const supplierManagers = await activeBranchManagers(
          transaction,
          firestore,
          invoice.sending_branch_id,
          supplyingBranchSnapshot.data(),
      );
      const receiverManagers = await activeBranchManagers(
          transaction,
          firestore,
          invoice.receiving_branch_id,
          receivingBranchSnapshot.data(),
      );
      const collectors = await activeUsersByRole(transaction, firestore, "collector");
      const revision = invoice.revision + 1;
      transaction.update(snapshotRef, {
        locked: true,
        locked_by: actor.uid,
        locked_by_name: actor.name,
        locked_at: timestamp,
        locked_invoice_revision: revision,
        ...(payload.accounting_notes ? {accounting_notes: payload.accounting_notes} : {}),
      });
      const publicEvent = eventData(
          "posted_to_accounting",
          "تم ترحيل الفاتورة إلى النظام المحاسبي.",
          actor,
          timestamp,
      );
      transaction.update(invoiceRef, {
        status: STATUS.postedToAccounting,
        revision,
        accounting_reference: payload.accounting_reference,
        posted_by: actor.uid,
        posted_by_name: actor.name,
        posted_at: timestamp,
        last_updated: timestamp,
        history: historyWithEvent(invoice, publicEvent),
      });
      writePublicEvent(transaction, firestore, {invoice, event: publicEvent, revision});
      writeNotifications(transaction, firestore, {
        recipients: [...supplierManagers, ...receiverManagers, ...collectors],
        invoice,
        type: "inter_branch_v2_accounting_posted",
        title: "تم ترحيل فاتورة التحويل محاسبيًا",
        message: `تم ترحيل الفاتورة رقم ${invoice.invoice_number} محاسبيًا.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(invoiceId, null, STATUS.postedToAccounting, revision),
      };
    },
  });
}

function createOperationalAuthentication({admin, firestore}) {
  const auth = admin.auth();
  return async (request, response, next) => {
    try {
      const token = bearerToken(request);
      if (!token) throw new CommandError("unauthenticated", 401, "Authentication is required.");
      let decoded;
      try {
        decoded = await auth.verifyIdToken(token, true);
      } catch (_) {
        throw new CommandError("unauthenticated", 401, "Authentication is required.");
      }
      const snapshot = await firestore.collection(COLLECTIONS.users).doc(decoded.uid).get();
      if (!snapshot.exists || !isOperationalProfile(snapshot.data())) {
        throw new CommandError("forbidden", 403, "The account cannot perform this operation.");
      }
      request.phase2Auth = {uid: decoded.uid};
      next();
    } catch (error) {
      const details = publicError(error);
      response.status(details.status).json(details.body);
    }
  };
}

function commandRoute({admin, firestore, now, randomUUID, validator, execute}) {
  return async (request, response) => {
    try {
      const idempotencyKey = validateIdempotencyKey(request.get("idempotency-key"));
      const payload = validator(request.body);
      const invoiceId = request.params.invoiceId === undefined ? undefined :
        documentId(request.params.invoiceId, "invoice_id");
      const result = await execute({
        admin,
        firestore,
        actorUid: request.phase2Auth.uid,
        ...(invoiceId ? {invoiceId} : {}),
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

function createInterBranchInvoiceCommandRouter({
  admin,
  firestore,
  now = () => new Date(),
  randomUUID = crypto.randomUUID,
}) {
  if (!admin || !firestore) throw new Error("Firebase Admin and Firestore are required.");
  const router = express.Router();
  router.use(createOperationalAuthentication({admin, firestore}));
  router.post("/inter-branch-invoices", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateCreatePayload,
    execute: createDirectInvoice,
  }));
  router.post("/inter-branch-invoices/:invoiceId/confirm-receipt", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateReceiptPayload,
    execute: confirmReceipt,
  }));
  router.post("/inter-branch-invoices/:invoiceId/confirm-prices", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validatePricingPayload,
    execute: confirmPrices,
  }));
  router.post("/inter-branch-invoices/:invoiceId/post-accounting", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validatePostingPayload,
    execute: postToAccounting,
  }));
  return router;
}

function safeJsonErrorHandler(error, _request, response, next) {
  if (error?.type === "entity.too.large") {
    response.status(413).json({
      error: {
        code: "payload-too-large",
        message: "The JSON request exceeds the allowed size.",
      },
    });
    return;
  }
  if (error instanceof SyntaxError && error?.status === 400 && "body" in error) {
    response.status(400).json({
      error: {
        code: "invalid-json",
        message: "The JSON request is invalid.",
      },
    });
    return;
  }
  next(error);
}

module.exports = {
  COLLECTIONS,
  INTER_BRANCH_JSON_LIMIT,
  STATUS,
  activeDocument,
  assertProtectedSnapshotMatchesInvoice,
  createDirectInvoice,
  createInterBranchInvoiceCommandRouter,
  isOperationalProfile,
  notificationReference,
  postToAccounting,
  priceItemsForInvoice,
  receiptItemsForInvoice,
  safeJsonErrorHandler,
};
