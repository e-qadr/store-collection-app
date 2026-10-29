const crypto = require("node:crypto");
const express = require("express");
const {buildNotificationDocument, closeOpenTasks} = require("./notification-task-policy");

const {
  CommandError,
  SUPPORTED_CURRENCIES,
  assertNoPriceLikeKeys,
  canonicalRequestHash,
  deterministicDocumentId,
  documentId,
  invoiceNumberFor,
  invoiceItemDigest,
  productPriceLatestKey,
  publicError,
  validateCreatePayload,
  validateAmendmentDecisionPayload,
  validateAmendmentRequestPayload,
  validateCancellationRequestPayload,
  validateIdempotencyKey,
  validateLegacyDualAccountingSetupPayload,
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
  pendingDualAccounting: "pendingDualAccounting",
  editPendingApprovals: "editPendingApprovals",
  cancellationPendingApprovals: "cancellationPendingApprovals",
  cancelled: "cancelled",
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
  "catalog_branch_side",
  "status",
  "revision",
  "invoice_number",
  "branch_code",
  "sending_branch_id",
  "sending_branch_name",
  "sending_brand_id",
  "receiving_branch_id",
  "receiving_branch_name",
  "receiving_branch_type",
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
  "participant_ids",
  "previous_status",
  "cancellation_request",
  "cancellation_approvals",
  "last_cancellation",
  "amendment_request",
  "amendment_approvals",
  "last_amendment",
  "source_accounting_status",
  "source_accounting_reference",
  "source_accounting_posted_by",
  "source_accounting_posted_by_name",
  "source_accounting_posted_at",
  "receiving_accounting_status",
  "receiving_accounting_reference",
  "receiving_accounting_posted_by",
  "receiving_accounting_posted_by_name",
  "receiving_accounting_posted_at",
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
      item.schema_version !== invoice.schema_version ||
      item.workflow_version !== invoice.workflow_version ||
      item.creation_mode !== invoice.creation_mode ||
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
      item.product_brand_id !== (invoice.workflow_version >= 3 &&
        invoice.catalog_branch_side === 'sending' ?
        invoice.sending_brand_id : invoice.receiving_brand_id) ||
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
  const directV2 = invoice?.schema_version === 2 &&
    invoice?.workflow_version === 2 &&
    invoice?.creation_mode === "direct_supplier_invoice";
  const directV3 = invoice?.schema_version === 3 &&
    invoice?.workflow_version === 3 &&
    invoice?.creation_mode === "direct_transfer_invoice";
  if (!directV2 && !directV3) {
    throw new CommandError(
        "unsupported-workflow",
        409,
        "This command is available only for direct transfer invoices.",
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

/// Returns only the minimum stable identity needed to migrate a historical
/// transfer. Older records can contain price fields and other legacy shapes,
/// so they must never pass through the closed public-invoice validator.
function requireLegacyAccountingInvoice(snapshot, expectedId, {
  requireMigration = false,
} = {}) {
  if (!snapshot.exists) {
    throw new CommandError("invoice-not-found", 404, "The invoice was not found.");
  }
  const raw = snapshot.data();
  const dualInitialized = raw?.legacy_dual_accounting?.active === true;
  const expectedState = requireMigration ?
    (raw.status === STATUS.pendingAccountingEntry ||
     raw.status === STATUS.postedToAccounting) :
    raw.status === STATUS.pendingDualAccounting;
  if (!raw || typeof raw !== "object" ||
      Number(raw.workflow_version || 1) >= 3 ||
      (requireMigration ? dualInitialized : !dualInitialized) ||
      !expectedState) {
    throw new CommandError(
        "unsupported-legacy-accounting",
        409,
        "This historical invoice cannot be converted to dual accounting.",
    );
  }
  const sendingBranchId = String(raw.sending_branch_id || "").trim();
  const receivingBranchId = String(raw.receiving_branch_id || "").trim();
  if (!sendingBranchId || !receivingBranchId) {
    throw new CommandError(
        "unsupported-legacy-accounting",
        409,
        "The historical invoice does not have both branches.",
    );
  }
  const storedId = String(raw.id || "").trim();
  if (storedId && storedId !== expectedId) {
    throw new CommandError("invoice-malformed", 409, "The invoice identity is invalid.");
  }
  const revision = Number.isSafeInteger(raw.revision) && raw.revision >= 0 ?
    raw.revision : 0;
  return {
    ...raw,
    id: expectedId,
    revision,
    sending_branch_id: sendingBranchId,
    receiving_branch_id: receivingBranchId,
    invoice_number: String(raw.invoice_number || expectedId).trim() || expectedId,
    history: Array.isArray(raw.history) ? raw.history : [],
  };
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

function isMainBranch(branchData) {
  return String(branchData?.branch_type || "").trim() === "main";
}

function assertCanonicalMainBranch(branch, brand) {
  if (!isMainBranch(branch.data)) return;
  const configuredId = String(brand?.main_branch_id || "").trim();
  if (configuredId !== branch.id) {
    throw new CommandError(
        "main-branch-invalid",
        409,
        "The main branch is not the canonical branch for its brand.",
    );
  }
}

function requireBrand(snapshot, brandId) {
  if (!snapshot.exists || !activeDocument(snapshot.data())) {
    throw new CommandError("branch-brand-invalid", 409, "A branch brand is unavailable.");
  }
  const data = snapshot.data();
  const storedId = String(data?.id || "").trim();
  if (storedId && storedId !== brandId) {
    throw new CommandError("branch-brand-invalid", 409, "A branch brand is inconsistent.");
  }
  return data;
}

async function readActor(transaction, firestore, uid, expectedRole) {
  const snapshot = await transaction.get(firestore.collection(COLLECTIONS.users).doc(uid));
  const profile = snapshot.data();
  if (!snapshot.exists || !isOperationalProfile(profile)) {
    throw new CommandError("forbidden", 403, "The account cannot perform this operation.");
  }
  const actor = actorFromProfile(uid, profile);
  const expectedRoles = Array.isArray(expectedRole) ? expectedRole : [expectedRole];
  if (!expectedRoles.includes(actor.role)) {
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

async function activeReceivingRecipients(transaction, firestore, branch) {
  return isMainBranch(branch.data) ?
    activeUsersByRole(transaction, firestore, "collector") :
    activeBranchManagers(transaction, firestore, branch.id, branch.data);
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
    transaction.set(reference, buildNotificationDocument({
      id: reference.id,
      recipientId: uid,
      title,
      message,
      module: COLLECTIONS.invoices,
      entityCollection: COLLECTIONS.invoices,
      entityId: invoice.id,
      branchId: invoice.sending_branch_id,
      branchIds: [invoice.sending_branch_id, invoice.receiving_branch_id],
      referenceNumber: invoice.invoice_number,
      notificationType: type,
      timestamp,
      extraData: {inter_branch_invoice_id: invoice.id},
    }));
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
    workflow_version: invoice.workflow_version,
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

/**
 * Resolve transfer lines from the *sending* branch catalogue.  This is kept
 * server-side for both creation and amendments so a client cannot select an
 * item that only belongs to the receiving branch.
 */
async function buildTransferCatalogItems({
  transaction,
  firestore,
  inputs,
  invoiceId,
  supplying,
  receiving,
  revision,
  randomUUID,
}) {
  const productSnapshots = await Promise.all(inputs.map((item) =>
    transaction.get(firestore.collection(COLLECTIONS.products).doc(item.product_id))));
  const productData = productSnapshots.map((snapshot, index) => {
    if (!snapshot.exists) {
      throw new CommandError('product-not-found', 404, 'A selected product was not found.');
    }
    const product = snapshot.data();
    if (product.id !== inputs[index].product_id ||
        !Number.isSafeInteger(product.version) || product.version < 1) {
      throw new CommandError('catalog-snapshot-invalid', 409, 'A product identity is invalid.');
    }
    if (String(product.brand_id || '') !== supplying.brandId) {
      throw new CommandError(
          'product-brand-mismatch',
          403,
          'A selected product does not belong to the sending branch brand.',
      );
    }
    const groupId = String(product.group_id || '').trim();
    if (!groupId) {
      throw new CommandError('catalog-snapshot-invalid', 409, 'A product group is missing.');
    }
    return {product, groupId, productId: inputs[index].product_id};
  });
  const uniqueGroupIds = [...new Set(productData.map((entry) => entry.groupId))];
  const groupSnapshots = await Promise.all(uniqueGroupIds.map((groupId) =>
    transaction.get(firestore.collection(COLLECTIONS.groups).doc(groupId))));
  const groups = new Map();
  groupSnapshots.forEach((snapshot, index) => {
    const groupId = uniqueGroupIds[index];
    const group = snapshot.data();
    if (!snapshot.exists || group?.id !== groupId ||
        !activeCatalogDocument(group) ||
        String(group.brand_id || '') !== supplying.brandId) {
      throw new CommandError(
          'group-invalid',
          409,
          'A product group is not active for the sending branch brand.',
      );
    }
    groups.set(groupId, group);
  });
  return productData.map((entry, index) => ({
    ...buildPublicCatalogItem({
      input: inputs[index],
      productId: entry.productId,
      product: entry.product,
      group: groups.get(entry.groupId),
      itemId: randomUUID(),
      invoiceId,
      supplyingBranchId: supplying.id,
      receivingBranchId: receiving.id,
      lineNumber: index + 1,
    }),
    schema_version: 3,
    workflow_version: 3,
    creation_mode: 'direct_transfer_invoice',
    invoice_revision: revision,
  }));
}

function transferCounterNextNumber(snapshot, supplyingBranch) {
  // Mirror the Collection voucher counter's lazy zero start while retaining
  // the Transfer counter namespace and its established branch identity.
  if (!snapshot.exists) return 0;
  const data = snapshot.data();
  if (!Number.isSafeInteger(data?.next_number) ||
      data.next_number < 0 || data.next_number > 1000) {
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
      if (isMainBranch(supplying.data)) {
        throw new CommandError(
            "main-branch-source-not-supported",
            403,
            "A main branch cannot be used as a transfer source.",
        );
      }
      const [supplyingBrandSnapshot, receivingBrandSnapshot] = await Promise.all([
        transaction.get(firestore.collection(COLLECTIONS.brands).doc(supplying.brandId)),
        transaction.get(firestore.collection(COLLECTIONS.brands).doc(receiving.brandId)),
      ]);
      requireBrand(supplyingBrandSnapshot, supplying.brandId);
      const receivingBrandData = requireBrand(receivingBrandSnapshot, receiving.brandId);
      const nextNumber = transferCounterNextNumber(counterSnapshot, supplying);
      if (nextNumber > 999) {
        throw new CommandError(
            "counter-exhausted",
            409,
            "وصل تسلسل فواتير الفرع إلى 999. يلزم اعتماد سياسة ترقيم جديدة قبل إنشاء فاتورة أخرى.",
        );
      }
      const invoiceNumber = invoiceNumberFor(supplying.code, nextNumber);
      assertCanonicalMainBranch(receiving, receivingBrandData);

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
              "A selected product does not belong to the sending branch brand.",
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
          throw new CommandError(
              "group-invalid",
              409,
              "A product group is not active for the sending branch brand.",
          );
        }
        groups.set(groupId, group);
      });
      const recipients = await activeReceivingRecipients(transaction, firestore, receiving);
      if (recipients.length === 0) {
        throw new CommandError(
            isMainBranch(receiving.data) ?
              "general-manager-not-configured" : "receiving-manager-not-configured",
            409,
            "The receiving branch has no active responsible user.",
        );
      }

      const items = productData.map((entry, index) => ({
        ...buildPublicCatalogItem({
        input: payload.items[index],
        productId: entry.productId,
        product: entry.product,
        group: groups.get(entry.groupId),
        itemId: plannedItemIds[index],
        invoiceId: invoiceRef.id,
        supplyingBranchId: supplying.id,
        receivingBranchId: receiving.id,
          lineNumber: index + 1,
        }),
        schema_version: 3,
        workflow_version: 3,
        creation_mode: "direct_transfer_invoice",
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
        schema_version: 3,
        workflow_version: 3,
        creation_mode: "direct_transfer_invoice",
        catalog_branch_side: "sending",
        status: STATUS.pendingReceiverReview,
        revision: 1,
        invoice_number: invoiceNumber,
        branch_code: supplying.code,
        sending_branch_id: supplying.id,
        sending_branch_name: supplying.name,
        sending_brand_id: supplying.brandId,
        receiving_branch_id: receiving.id,
        receiving_branch_name: receiving.name,
        receiving_branch_type: isMainBranch(receiving.data) ? "main" : "branch",
        receiving_brand_id: receiving.brandId,
        branch_ids: [supplying.id, receiving.id],
        item_count: items.length,
        item_digest: itemDigest,
        ...(payload.invoice_notes ? {invoice_notes: payload.invoice_notes} : {}),
        created_by: actor.uid,
        created_by_name: actor.name,
        created_by_role: actor.role,
        participant_ids: [actor.uid],
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
      transaction.set(counterRef, {
        branch_id: supplying.id,
        branch_code: supplying.code,
        next_number: nextNumber + 1,
        last_invoice_number: invoiceNumber,
        last_updated: timestamp,
      }, {merge: true});
      writeNotifications(transaction, firestore, {
        recipients,
        invoice: publicInvoice,
        type: "inter_branch_v2_direct_created",
        title: isMainBranch(receiving.data) ?
          "فاتورة تحويل بانتظار استلام الإدارة الرئيسية" :
          "فاتورة تحويل بين الفروع بانتظار الاستلام",
        message: isMainBranch(receiving.data) ?
          `الفاتورة رقم ${invoiceNumber} بانتظار تأكيد المدير العام للاستلام.` :
          `الفاتورة رقم ${invoiceNumber} بانتظار مراجعة الفرع المستلم.`,
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
    if (receipt.missing_quantity > maximumMissing ||
        Math.abs((receipt.received_quantity + receipt.missing_quantity) - supplied) > 0.000001) {
      throw new CommandError(
          "quantity-inconsistent",
          400,
          "Received and missing quantities must explain the supplied quantity.",
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
    expectedRole: ["manager", "collector"],
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const rawInvoice = invoiceSnapshot.exists ? invoiceSnapshot.data() : null;
      const branchId = String(rawInvoice?.receiving_branch_id || "");
      if (!invoiceSnapshot.exists || !branchId) {
        throw new CommandError("forbidden", 403, "You cannot act for this branch.");
      }
      const branchSnapshot = await transaction.get(
          firestore.collection(COLLECTIONS.branches).doc(branchId),
      );
      const branch = cleanBranch(branchSnapshot, branchId);
      if (isMainBranch(branch.data)) {
        if (actor.role !== "collector") {
          throw new CommandError("forbidden", 403, "Only the general manager may receive for the main branch.");
        }
        const brandSnapshot = await transaction.get(
            firestore.collection(COLLECTIONS.brands).doc(branch.brandId),
        );
        requireBrand(brandSnapshot, branch.brandId);
        assertCanonicalMainBranch(branch, brandSnapshot.data());
      } else {
        if (actor.branchId !== branchId) {
          throw new CommandError("forbidden", 403, "You cannot act for this branch.");
        }
        assertActorManagesBranch(actor, branch.id, branch.data);
      }
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      requireStatusAndRevision(invoice, STATUS.pendingReceiverReview, payload.expected_revision);
      const storedItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      const revision = invoice.revision + 1;
      const items = receiptItemsForInvoice(storedItems, payload.items).map((item) => ({
        ...item,
        invoice_revision: revision,
      }));
      const itemDigest = invoiceItemDigest(items);
      const isVersion3 = invoice.workflow_version >= 3;
      // A historical invoice that has been migrated to the dual-accounting
      // path can be returned to receipt review after its receiving branch is
      // corrected.  Treat that receipt exactly like the modern dual workflow:
      // the source-side posting must remain posted while only the receiving
      // side returns to pending.
      const isLegacyDualAccounting = invoice.legacy_dual_accounting?.active === true;
      const usesDualAccounting = isVersion3 || isLegacyDualAccounting;
      const nextRecipients = await activeUsersByRole(
          transaction, firestore, usesDualAccounting ? "accountant" : "collector");
      if (nextRecipients.length === 0) {
        throw new CommandError(
            usesDualAccounting ? "accountant-not-configured" : "general-manager-not-configured",
            409,
            usesDualAccounting ? "No active accountant is configured." :
              "No active general manager is configured.",
        );
      }
      const event = eventData(
          "receipt_confirmed",
          isMainBranch(branch.data) ?
            "أكد المدير العام استلام الإدارة الرئيسية للكميات." :
            "أكد مدير الفرع المستلم الكميات المستلمة.",
          actor,
          timestamp,
      );
      await closeOpenTasks(transaction, firestore, {
        entityId: invoiceId,
        recipientIds: [actor.uid],
        notificationTypes: [
          "inter_branch_v2_direct_created",
          "inter_branch_v3_direct_created",
        ],
        timestamp,
      });
      transaction.update(invoiceRef, {
        item_digest: itemDigest,
        status: usesDualAccounting ? STATUS.pendingDualAccounting : STATUS.pendingPriceEntry,
        revision,
        ...(payload.receiver_notes ? {receiver_notes: payload.receiver_notes} : {}),
        receipt_confirmed_by: actor.uid,
        receipt_confirmed_by_name: actor.name,
        receipt_confirmed_at: timestamp,
        ...(usesDualAccounting ? {
          participant_ids: [...new Set([
            ...(Array.isArray(invoice.participant_ids) ? invoice.participant_ids : []),
            actor.uid,
          ])],
          source_accounting_status: isLegacyDualAccounting ?
            (invoice.source_accounting_status || "pending") : "pending",
          receiving_accounting_status: "pending",
        } : {}),
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      });
      items.forEach((item) => {
        assertClosedPublicItem({...invoice, revision}, item, item.item_id);
        transaction.set(invoiceItemsCollection(invoiceRef).doc(item.item_id), item);
      });
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: nextRecipients,
        invoice,
        type: usesDualAccounting ? "inter_branch_v3_receipt_confirmed" :
          "inter_branch_v2_receipt_confirmed",
        title: usesDualAccounting ? "فاتورة مناقلة بانتظار الترحيل المحاسبي" :
          "فاتورة تحويل بانتظار التسعير",
        message: usesDualAccounting ?
          `تم تأكيد الاستلام للفاتورة رقم ${invoice.invoice_number}. يلزم ترحيل الصادر والوارد.` :
          `تم تأكيد استلام الفاتورة رقم ${invoice.invoice_number}.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {
        statusCode: 200,
        responseData: responseFor(
            invoiceId,
            null,
            usesDualAccounting ? STATUS.pendingDualAccounting : STATUS.pendingPriceEntry,
            revision,
        ),
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
      await closeOpenTasks(transaction, firestore, {
        entityId: invoiceId,
        recipientIds: [actor.uid],
        notificationTypes: ["inter_branch_v2_receipt_confirmed"],
        timestamp,
      });
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

function transferParticipants(invoice) {
  const ids = Array.isArray(invoice.participant_ids) ? invoice.participant_ids : [];
  const unique = [...new Set(ids.filter((id) => typeof id === 'string' && id.trim()))];
  if (unique.length === 0) {
    throw new CommandError('invoice-malformed', 409, 'The invoice participants are invalid.');
  }
  return unique;
}

function pendingAmendment(invoice) {
  const request = invoice.amendment_request;
  if (!request || typeof request !== 'object' || Array.isArray(request) ||
      request.state !== 'pending' || !Array.isArray(request.required_approver_ids) ||
      !Array.isArray(request.proposed_items)) {
    throw new CommandError('amendment-not-found', 409, 'There is no pending amendment.');
  }
  const approvers = [...new Set(request.required_approver_ids.filter((id) =>
    typeof id === 'string' && id.trim()))];
  if (approvers.length === 0 || approvers.length !== request.required_approver_ids.length) {
    throw new CommandError('invoice-malformed', 409, 'The amendment approvers are invalid.');
  }
  return {...request, required_approver_ids: approvers};
}

function pendingCancellation(invoice) {
  const request = invoice.cancellation_request;
  if (!request || typeof request !== 'object' || Array.isArray(request) ||
      request.state !== 'pending' || !Array.isArray(request.required_approver_ids)) {
    throw new CommandError('cancellation-not-found', 409, 'There is no pending cancellation.');
  }
  const approvers = [...new Set(request.required_approver_ids.filter((id) =>
    typeof id === 'string' && id.trim()))];
  if (approvers.length === 0 || approvers.length !== request.required_approver_ids.length) {
    throw new CommandError('invoice-malformed', 409, 'The cancellation approvers are invalid.');
  }
  return {...request, required_approver_ids: approvers};
}

async function transferBranchesForInvoice(transaction, firestore, invoice) {
  const [supplyingSnapshot, receivingSnapshot] = await Promise.all([
    transaction.get(firestore.collection(COLLECTIONS.branches).doc(invoice.sending_branch_id)),
    transaction.get(firestore.collection(COLLECTIONS.branches).doc(invoice.receiving_branch_id)),
  ]);
  return {
    supplying: cleanBranch(supplyingSnapshot, invoice.sending_branch_id),
    receiving: cleanBranch(receivingSnapshot, invoice.receiving_branch_id),
  };
}

function amendmentSummary({
  id,
  state,
  reason,
  actor,
  requester = actor,
  timestamp,
  rejectionReason,
  proposalCount,
}) {
  return {
    id,
    state,
    reason,
    // The person taking the final decision may differ from the person who
    // originally requested the amendment. Keep the audit trail attributed to
    // the requester in both the approved and rejected outcomes.
    requested_by: requester.uid,
    requested_by_name: requester.name,
    requested_by_role: requester.role,
    requested_at: timestamp,
    proposal_item_count: proposalCount,
    ...(rejectionReason ? {rejection_reason: rejectionReason} : {}),
  };
}

function cancellationSummary({
  id,
  state,
  reason,
  actor,
  requester = actor,
  timestamp,
  rejectionReason,
}) {
  return {
    id,
    state,
    reason,
    requested_by: requester.uid,
    requested_by_name: requester.name,
    requested_by_role: requester.role,
    requested_at: timestamp,
    ...(rejectionReason ? {rejection_reason: rejectionReason} : {}),
  };
}

function updateItemDocuments(transaction, invoiceRef, previousItems, nextItems) {
  previousItems.forEach((item) => transaction.delete(
      invoiceItemsCollection(invoiceRef).doc(item.item_id)));
  nextItems.forEach((item) => transaction.set(
      invoiceItemsCollection(invoiceRef).doc(item.item_id), item));
}

async function requestAmendment({
  admin,
  firestore,
  actorUid,
  invoiceId,
  payload,
  idempotencyKey,
  timestamp,
  randomUUID,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotentTransaction({
    admin,
    firestore,
    command: 'request_amendment',
    actorUid,
    expectedRole: ['manager', 'collector', 'accountant'],
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      if (invoice.workflow_version < 3) {
        throw new CommandError('unsupported-workflow', 409, 'This amendment flow requires a transfer invoice.');
      }
      requireStatusAndRevision(invoice, invoice.status, payload.expected_revision);
      if (invoice.status === STATUS.editPendingApprovals) {
        throw new CommandError('amendment-already-pending', 409, 'An amendment is already pending.');
      }
      if (invoice.status !== STATUS.pendingReceiverReview &&
          invoice.status !== STATUS.pendingDualAccounting &&
          invoice.status !== STATUS.postedToAccounting) {
        throw new CommandError('invalid-state', 409, 'The invoice cannot be amended in its current state.');
      }
      const {supplying, receiving} = await transferBranchesForInvoice(
          transaction, firestore, invoice);
      const directBeforeReceipt = invoice.status === STATUS.pendingReceiverReview &&
        actor.role === 'manager' && invoice.created_by === actor.uid;
      if (directBeforeReceipt) {
        assertActorManagesBranch(actor, supplying.id, supplying.data);
      } else if (!transferParticipants(invoice).includes(actor.uid)) {
        throw new CommandError('forbidden', 403, 'Only a recorded participant may request this amendment.');
      }

      const revision = invoice.revision + 1;
      const proposedItems = await buildTransferCatalogItems({
        transaction,
        firestore,
        inputs: payload.items,
        invoiceId,
        supplying,
        receiving,
        revision,
        randomUUID,
      });
      const itemDigest = invoiceItemDigest(proposedItems);
      const currentItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      const amendmentId = randomUUID();

      if (directBeforeReceipt) {
        const event = eventData(
            'amendment_applied_directly',
            'عدّل منشئ الفاتورة المواد قبل تأكيد الاستلام.',
            actor,
            timestamp,
        );
        const nextInvoice = {
          ...invoice,
          revision,
          catalog_branch_side: 'sending',
          item_count: proposedItems.length,
          item_digest: itemDigest,
          ...(payload.invoice_notes ? {invoice_notes: payload.invoice_notes} : {}),
          last_amendment: amendmentSummary({
            id: amendmentId,
            state: 'applied_directly',
            reason: payload.reason,
            actor,
            timestamp,
            proposalCount: proposedItems.length,
          }),
          last_updated: timestamp,
          history: historyWithEvent(invoice, event),
        };
        if (!payload.invoice_notes) delete nextInvoice.invoice_notes;
        assertNoPriceLikeKeys(nextInvoice, 'invoice');
        assertClosedPublicInvoice(nextInvoice);
        proposedItems.forEach((item) => assertClosedPublicItem(nextInvoice, item, item.item_id));
        transaction.set(invoiceRef, nextInvoice);
        updateItemDocuments(transaction, invoiceRef, currentItems, proposedItems);
        writePublicEvent(transaction, firestore, {invoice, event, revision});
        const recipients = await activeReceivingRecipients(transaction, firestore, receiving);
        writeNotifications(transaction, firestore, {
          recipients,
          invoice,
          type: 'inter_branch_v3_direct_amendment_applied',
          title: 'تم تعديل فاتورة المناقلة',
          message: `تم تعديل الفاتورة رقم ${invoice.invoice_number} قبل تأكيد الاستلام.`,
          revision,
          timestamp,
          excludeUid: actor.uid,
        });
        return {statusCode: 200, responseData: responseFor(
            invoiceId, null, STATUS.pendingReceiverReview, revision)};
      }

      const requiredApprovers = transferParticipants(invoice);
      const event = eventData(
          'amendment_requested',
          'تم طلب تعديل فاتورة المناقلة وبانتظار موافقة جميع المشاركين.',
          actor,
          timestamp,
      );
      const amendmentRequest = {
        ...amendmentSummary({
          id: amendmentId,
          state: 'pending',
          reason: payload.reason,
          actor,
          timestamp,
          proposalCount: proposedItems.length,
        }),
        required_approver_ids: requiredApprovers,
        proposed_items: proposedItems,
        ...(payload.invoice_notes ? {proposed_invoice_notes: payload.invoice_notes} : {}),
      };
      const nextInvoice = {
        ...invoice,
        previous_status: invoice.status,
        status: STATUS.editPendingApprovals,
        revision,
        amendment_request: amendmentRequest,
        amendment_approvals: {
          [actor.uid]: {
            approved: true,
            actor_name: actor.name,
            actor_role: actor.role,
            reason: payload.reason,
            at: timestamp,
          },
        },
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      };
      assertNoPriceLikeKeys(nextInvoice, 'invoice');
      assertClosedPublicInvoice(nextInvoice);
      transaction.set(invoiceRef, nextInvoice);
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: requiredApprovers,
        invoice,
        type: 'inter_branch_v3_amendment_requested',
        title: 'طلب تعديل فاتورة مناقلة',
        message: `يوجد طلب تعديل للفاتورة رقم ${invoice.invoice_number} بانتظار موافقتك.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {statusCode: 200, responseData: responseFor(
          invoiceId, null, STATUS.editPendingApprovals, revision)};
    },
  });
}

async function decideAmendment({
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
    command: 'decide_amendment',
    actorUid,
    expectedRole: ['manager', 'collector', 'accountant'],
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      if (invoice.workflow_version < 3) {
        throw new CommandError('unsupported-workflow', 409, 'This amendment flow requires a transfer invoice.');
      }
      requireStatusAndRevision(invoice, STATUS.editPendingApprovals, payload.expected_revision);
      const amendment = pendingAmendment(invoice);
      if (!amendment.required_approver_ids.includes(actor.uid)) {
        throw new CommandError('forbidden', 403, 'You are not an approver for this amendment.');
      }
      const approvals = invoice.amendment_approvals && typeof invoice.amendment_approvals === 'object' ?
        {...invoice.amendment_approvals} : {};
      if (approvals[actor.uid]) {
        throw new CommandError('decision-already-recorded', 409, 'Your decision was already recorded.');
      }
      const revision = invoice.revision + 1;
      if (!payload.approved) {
        const event = eventData(
            'amendment_rejected',
            'تم رفض طلب تعديل فاتورة المناقلة وإعادة الفاتورة إلى مسارها السابق.',
            actor,
            timestamp,
        );
        const nextInvoice = {
          ...invoice,
          status: invoice.previous_status,
          revision,
          last_amendment: amendmentSummary({
            id: amendment.id,
            state: 'rejected',
            reason: amendment.reason,
            actor,
            requester: {
              uid: amendment.requested_by,
              name: amendment.requested_by_name,
              role: amendment.requested_by_role,
            },
            timestamp,
            rejectionReason: payload.reason,
            proposalCount: amendment.proposal_item_count,
          }),
          last_updated: timestamp,
          history: historyWithEvent(invoice, event),
        };
        delete nextInvoice.previous_status;
        delete nextInvoice.amendment_request;
        delete nextInvoice.amendment_approvals;
        assertNoPriceLikeKeys(nextInvoice, 'invoice');
        assertClosedPublicInvoice(nextInvoice);
        await closeOpenTasks(transaction, firestore, {
          entityId: invoiceId,
          recipientIds: amendment.required_approver_ids,
          notificationTypes: ['inter_branch_v3_amendment_requested'],
          timestamp,
          resolution: 'cancelled',
        });
        transaction.set(invoiceRef, nextInvoice);
        writePublicEvent(transaction, firestore, {invoice, event, revision});
        writeNotifications(transaction, firestore, {
          recipients: amendment.required_approver_ids,
          invoice,
          type: 'inter_branch_v3_amendment_rejected',
          title: 'تم رفض تعديل فاتورة المناقلة',
          message: `تم رفض طلب تعديل الفاتورة رقم ${invoice.invoice_number}: ${payload.reason}.`,
          revision,
          timestamp,
          excludeUid: actor.uid,
        });
        return {statusCode: 200, responseData: responseFor(
            invoiceId, null, invoice.previous_status, revision)};
      }

      approvals[actor.uid] = {
        approved: true,
        actor_name: actor.name,
        actor_role: actor.role,
        ...(payload.reason ? {reason: payload.reason} : {}),
        at: timestamp,
      };
      const allApproved = amendment.required_approver_ids.every((uid) => approvals[uid]?.approved === true);
      if (!allApproved) {
        const event = eventData(
            'amendment_approved',
            'سجّل أحد المشاركين موافقته على تعديل فاتورة المناقلة.',
            actor,
            timestamp,
        );
        const nextInvoice = {
          ...invoice,
          revision,
          amendment_approvals: approvals,
          last_updated: timestamp,
          history: historyWithEvent(invoice, event),
        };
        assertNoPriceLikeKeys(nextInvoice, 'invoice');
        assertClosedPublicInvoice(nextInvoice);
        await closeOpenTasks(transaction, firestore, {
          entityId: invoiceId,
          recipientIds: [actor.uid],
          notificationTypes: ['inter_branch_v3_amendment_requested'],
          timestamp,
        });
        transaction.set(invoiceRef, nextInvoice);
        writePublicEvent(transaction, firestore, {invoice, event, revision});
        return {statusCode: 200, responseData: responseFor(
            invoiceId, null, STATUS.editPendingApprovals, revision)};
      }

      const proposedItems = amendment.proposed_items.map((item) => ({
        ...item,
        invoice_revision: revision,
      }));
      const currentItems = await readV2PublicItems(transaction, invoiceRef, invoice);
      const nextDigest = invoiceItemDigest(proposedItems);
      const event = eventData(
          'amendment_applied',
          'اكتملت الموافقات وطُبّق تعديل فاتورة المناقلة. يلزم تأكيد الاستلام والترحيل من جديد.',
          actor,
          timestamp,
      );
      const nextInvoice = {
        ...invoice,
        status: STATUS.pendingReceiverReview,
        revision,
        catalog_branch_side: 'sending',
        item_count: proposedItems.length,
        item_digest: nextDigest,
        ...(amendment.proposed_invoice_notes ? {invoice_notes: amendment.proposed_invoice_notes} : {}),
        source_accounting_status: 'pending',
        receiving_accounting_status: 'pending',
        last_amendment: amendmentSummary({
          id: amendment.id,
          state: 'applied',
          reason: amendment.reason,
          actor,
          requester: {
            uid: amendment.requested_by,
            name: amendment.requested_by_name,
            role: amendment.requested_by_role,
          },
          timestamp,
          proposalCount: proposedItems.length,
        }),
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      };
      [
        'previous_status', 'amendment_request', 'amendment_approvals',
        'receipt_confirmed_by', 'receipt_confirmed_by_name', 'receipt_confirmed_at',
        'receiver_notes', 'source_accounting_reference', 'source_accounting_posted_by',
        'source_accounting_posted_by_name', 'source_accounting_posted_at',
        'receiving_accounting_reference', 'receiving_accounting_posted_by',
        'receiving_accounting_posted_by_name', 'receiving_accounting_posted_at',
      ].forEach((key) => delete nextInvoice[key]);
      if (!amendment.proposed_invoice_notes) delete nextInvoice.invoice_notes;
      assertNoPriceLikeKeys(nextInvoice, 'invoice');
      assertClosedPublicInvoice(nextInvoice);
      proposedItems.forEach((item) => assertClosedPublicItem(nextInvoice, item, item.item_id));
      await closeOpenTasks(transaction, firestore, {
        entityId: invoiceId,
        recipientIds: amendment.required_approver_ids,
        notificationTypes: ['inter_branch_v3_amendment_requested'],
        timestamp,
      });
      transaction.set(invoiceRef, nextInvoice);
      updateItemDocuments(transaction, invoiceRef, currentItems, proposedItems);
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: transferParticipants(invoice),
        invoice,
        type: 'inter_branch_v3_amendment_applied',
        title: 'تم اعتماد تعديل فاتورة المناقلة',
        message: `تم اعتماد تعديل الفاتورة رقم ${invoice.invoice_number}. يلزم تأكيد الاستلام ثم إعادة الترحيل.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {statusCode: 200, responseData: responseFor(
          invoiceId, null, STATUS.pendingReceiverReview, revision)};
    },
  });
}

async function requestCancellation({
  admin,
  firestore,
  actorUid,
  invoiceId,
  payload,
  idempotencyKey,
  timestamp,
  randomUUID,
}) {
  const invoiceRef = firestore.collection(COLLECTIONS.invoices).doc(invoiceId);
  const requestHash = canonicalRequestHash({invoice_id: invoiceId, ...payload});
  return runIdempotentTransaction({
    admin,
    firestore,
    command: 'request_cancellation',
    actorUid,
    expectedRole: ['manager', 'collector', 'accountant'],
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      if (invoice.workflow_version < 3) {
        throw new CommandError('unsupported-workflow', 409, 'This cancellation flow requires a transfer invoice.');
      }
      requireStatusAndRevision(invoice, invoice.status, payload.expected_revision);
      if (invoice.status === STATUS.cancellationPendingApprovals ||
          invoice.status === STATUS.editPendingApprovals) {
        throw new CommandError('shared-request-already-pending', 409, 'A shared request is already pending.');
      }
      if (invoice.status !== STATUS.pendingReceiverReview &&
          invoice.status !== STATUS.pendingDualAccounting &&
          invoice.status !== STATUS.postedToAccounting) {
        throw new CommandError('invalid-state', 409, 'The invoice cannot be cancelled in its current state.');
      }

      const directBeforeReceipt = invoice.status === STATUS.pendingReceiverReview &&
        actor.role === 'manager' && invoice.created_by === actor.uid;
      if (!directBeforeReceipt && !transferParticipants(invoice).includes(actor.uid)) {
        throw new CommandError('forbidden', 403, 'Only a recorded participant may request this cancellation.');
      }

      const requiredApprovers = transferParticipants(invoice);
      const cancellationId = randomUUID();
      const revision = invoice.revision + 1;
      const request = {
        ...cancellationSummary({
          id: cancellationId,
          state: 'pending',
          reason: payload.reason,
          actor,
          timestamp,
        }),
        required_approver_ids: requiredApprovers,
      };
      const approvals = {
        [actor.uid]: {
          approved: true,
          actor_name: actor.name,
          actor_role: actor.role,
          reason: payload.reason,
          at: timestamp,
        },
      };
      const directCancellation = requiredApprovers.length === 1;
      const event = eventData(
          directCancellation ? 'cancellation_applied_directly' : 'cancellation_requested',
          directCancellation ?
            'ألغى منشئ فاتورة المناقلة الفاتورة قبل تأكيد الاستلام.' :
            'تم طلب إلغاء فاتورة المناقلة وبانتظار موافقة جميع المشاركين.',
          actor,
          timestamp,
      );
      const nextInvoice = {
        ...invoice,
        status: directCancellation ? STATUS.cancelled : STATUS.cancellationPendingApprovals,
        revision,
        ...(directCancellation ? {
          last_cancellation: cancellationSummary({
            id: cancellationId,
            state: 'applied_directly',
            reason: payload.reason,
            actor,
            timestamp,
          }),
        } : {
          previous_status: invoice.status,
          cancellation_request: request,
          cancellation_approvals: approvals,
        }),
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      };
      assertNoPriceLikeKeys(nextInvoice, 'invoice');
      assertClosedPublicInvoice(nextInvoice);
      transaction.set(invoiceRef, nextInvoice);
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      if (!directCancellation) {
        writeNotifications(transaction, firestore, {
          recipients: requiredApprovers,
          invoice,
          type: 'inter_branch_v3_cancellation_requested',
          title: 'طلب إلغاء فاتورة مناقلة',
          message: `يوجد طلب إلغاء للفاتورة رقم ${invoice.invoice_number} بانتظار موافقتك.`,
          revision,
          timestamp,
          excludeUid: actor.uid,
        });
      }
      return {statusCode: 200, responseData: responseFor(
          invoiceId, null, nextInvoice.status, revision)};
    },
  });
}

async function decideCancellation({
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
    command: 'decide_cancellation',
    actorUid,
    expectedRole: ['manager', 'collector', 'accountant'],
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoiceSnapshot = await transaction.get(invoiceRef);
      const invoice = requireV2Invoice(invoiceSnapshot, invoiceId);
      if (invoice.workflow_version < 3) {
        throw new CommandError('unsupported-workflow', 409, 'This cancellation flow requires a transfer invoice.');
      }
      requireStatusAndRevision(
          invoice, STATUS.cancellationPendingApprovals, payload.expected_revision);
      const cancellation = pendingCancellation(invoice);
      if (!cancellation.required_approver_ids.includes(actor.uid)) {
        throw new CommandError('forbidden', 403, 'You are not an approver for this cancellation.');
      }
      const approvals = invoice.cancellation_approvals &&
          typeof invoice.cancellation_approvals === 'object' ?
        {...invoice.cancellation_approvals} : {};
      if (approvals[actor.uid]) {
        throw new CommandError('decision-already-recorded', 409, 'Your decision was already recorded.');
      }
      const revision = invoice.revision + 1;
      const requester = {
        uid: cancellation.requested_by,
        name: cancellation.requested_by_name,
        role: cancellation.requested_by_role,
      };
      if (!payload.approved) {
        const event = eventData(
            'cancellation_rejected',
            'تم رفض طلب إلغاء فاتورة المناقلة وإعادة الفاتورة إلى مسارها السابق.',
            actor,
            timestamp,
        );
        const nextInvoice = {
          ...invoice,
          status: invoice.previous_status,
          revision,
          last_cancellation: cancellationSummary({
            id: cancellation.id,
            state: 'rejected',
            reason: cancellation.reason,
            actor,
            requester,
            timestamp,
            rejectionReason: payload.reason,
          }),
          last_updated: timestamp,
          history: historyWithEvent(invoice, event),
        };
        ['previous_status', 'cancellation_request', 'cancellation_approvals']
            .forEach((key) => delete nextInvoice[key]);
        assertNoPriceLikeKeys(nextInvoice, 'invoice');
        assertClosedPublicInvoice(nextInvoice);
        await closeOpenTasks(transaction, firestore, {
          entityId: invoiceId,
          recipientIds: cancellation.required_approver_ids,
          notificationTypes: ['inter_branch_v3_cancellation_requested'],
          timestamp,
          resolution: 'cancelled',
        });
        transaction.set(invoiceRef, nextInvoice);
        writePublicEvent(transaction, firestore, {invoice, event, revision});
        writeNotifications(transaction, firestore, {
          recipients: cancellation.required_approver_ids,
          invoice,
          type: 'inter_branch_v3_cancellation_rejected',
          title: 'تم رفض إلغاء فاتورة المناقلة',
          message: `تم رفض طلب إلغاء الفاتورة رقم ${invoice.invoice_number}: ${payload.reason}.`,
          revision,
          timestamp,
          excludeUid: actor.uid,
        });
        return {statusCode: 200, responseData: responseFor(
            invoiceId, null, invoice.previous_status, revision)};
      }

      approvals[actor.uid] = {
        approved: true,
        actor_name: actor.name,
        actor_role: actor.role,
        ...(payload.reason ? {reason: payload.reason} : {}),
        at: timestamp,
      };
      const allApproved = cancellation.required_approver_ids.every(
          (uid) => approvals[uid]?.approved === true);
      if (!allApproved) {
        const event = eventData(
            'cancellation_approved',
            'سجّل أحد المشاركين موافقته على إلغاء فاتورة المناقلة.',
            actor,
            timestamp,
        );
        const nextInvoice = {
          ...invoice,
          revision,
          cancellation_approvals: approvals,
          last_updated: timestamp,
          history: historyWithEvent(invoice, event),
        };
        assertNoPriceLikeKeys(nextInvoice, 'invoice');
        assertClosedPublicInvoice(nextInvoice);
        await closeOpenTasks(transaction, firestore, {
          entityId: invoiceId,
          recipientIds: [actor.uid],
          notificationTypes: ['inter_branch_v3_cancellation_requested'],
          timestamp,
        });
        transaction.set(invoiceRef, nextInvoice);
        writePublicEvent(transaction, firestore, {invoice, event, revision});
        return {statusCode: 200, responseData: responseFor(
            invoiceId, null, STATUS.cancellationPendingApprovals, revision)};
      }

      const event = eventData(
          'cancellation_applied',
          'اكتملت الموافقات وأُلغيت فاتورة المناقلة.',
          actor,
          timestamp,
      );
      const nextInvoice = {
        ...invoice,
        status: STATUS.cancelled,
        revision,
        last_cancellation: cancellationSummary({
          id: cancellation.id,
          state: 'applied',
          reason: cancellation.reason,
          actor,
          requester,
          timestamp,
        }),
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      };
      ['previous_status', 'cancellation_request', 'cancellation_approvals']
          .forEach((key) => delete nextInvoice[key]);
      assertNoPriceLikeKeys(nextInvoice, 'invoice');
      assertClosedPublicInvoice(nextInvoice);
      await closeOpenTasks(transaction, firestore, {
        entityId: invoiceId,
        recipientIds: cancellation.required_approver_ids,
        notificationTypes: ['inter_branch_v3_cancellation_requested'],
        timestamp,
      });
      transaction.set(invoiceRef, nextInvoice);
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      writeNotifications(transaction, firestore, {
        recipients: cancellation.required_approver_ids,
        invoice,
        type: 'inter_branch_v3_cancellation_applied',
        title: 'تم إلغاء فاتورة المناقلة',
        message: `تم إلغاء الفاتورة رقم ${invoice.invoice_number} بعد اكتمال الموافقات.`,
        revision,
        timestamp,
        excludeUid: actor.uid,
      });
      return {statusCode: 200, responseData: responseFor(
          invoiceId, null, STATUS.cancelled, revision)};
    },
  });
}

async function initializeLegacyDualAccounting({
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
    command: "initialize_legacy_dual_accounting",
    actorUid,
    expectedRole: "accountant",
    idempotencyKey,
    requestHash,
    timestamp,
    execute: async (transaction, actor) => {
      const invoice = requireLegacyAccountingInvoice(
          await transaction.get(invoiceRef), invoiceId, {requireMigration: true});
      if (invoice.revision !== payload.expected_revision) {
        throw new CommandError("stale-revision", 409, "The invoice revision has changed.");
      }
      const existingSide = payload.existing_posting_side;
      const existingReference = payload.existing_accounting_reference ||
        String(invoice.accounting_reference || "").trim();
      const existingIsSource = existingSide === "source";
      const existingIsReceiving = existingSide === "receiving";
      const revision = invoice.revision + 1;
      const event = eventData(
          "legacy_dual_accounting_initialized",
          existingSide === "none" ?
            "تم تجهيز الفاتورة القديمة لترحيل الصادر والوارد." :
            "تم تسجيل الترحيل السابق وتجهيز الجانب المحاسبي المتبقي.",
          actor,
          timestamp,
      );
      const participants = [...new Set([
        ...(Array.isArray(invoice.participant_ids) ? invoice.participant_ids : []),
        actor.uid,
      ])];
      transaction.update(invoiceRef, {
        id: invoice.id,
        status: STATUS.pendingDualAccounting,
        revision,
        participant_ids: participants,
        legacy_dual_accounting: {
          active: true,
          initialized_by: actor.uid,
          initialized_by_name: actor.name,
          initialized_at: timestamp,
          existing_posting_side: existingSide,
        },
        source_accounting_status: existingIsSource ? "posted" : "pending",
        receiving_accounting_status: existingIsReceiving ? "posted" : "pending",
        ...(existingIsSource ? {
          source_accounting_reference: existingReference || "ترحيل سابق",
          source_accounting_posted_by: String(invoice.posted_by || "").trim() || actor.uid,
          source_accounting_posted_by_name:
            String(invoice.posted_by_name || "").trim() || actor.name,
          source_accounting_posted_at: invoice.posted_at || timestamp,
        } : {}),
        ...(existingIsReceiving ? {
          receiving_accounting_reference: existingReference || "ترحيل سابق",
          receiving_accounting_posted_by: String(invoice.posted_by || "").trim() || actor.uid,
          receiving_accounting_posted_by_name:
            String(invoice.posted_by_name || "").trim() || actor.name,
          receiving_accounting_posted_at: invoice.posted_at || timestamp,
        } : {}),
        last_updated: timestamp,
        history: historyWithEvent(invoice, event),
      });
      writePublicEvent(transaction, firestore, {invoice, event, revision});
      return {
        statusCode: 200,
        responseData: responseFor(
            invoiceId, invoice.invoice_number, STATUS.pendingDualAccounting, revision),
      };
    },
  });
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
      const rawInvoice = invoiceSnapshot.data();
      const isLegacyDual = rawInvoice?.legacy_dual_accounting?.active === true;
      const invoice = isLegacyDual ?
        requireLegacyAccountingInvoice(invoiceSnapshot, invoiceId) :
        requireV2Invoice(invoiceSnapshot, invoiceId);
      if (invoice.workflow_version >= 3 || isLegacyDual) {
        requireStatusAndRevision(
            invoice,
            STATUS.pendingDualAccounting,
            payload.expected_revision,
        );
        const side = String(payload.posting_side || "").trim();
        if (side !== "source" && side !== "receiving") {
          throw new CommandError(
              "invalid-argument",
              400,
              "A source or receiving accounting side is required.",
          );
        }
        const statusField = side === "source" ?
          "source_accounting_status" : "receiving_accounting_status";
        const referenceField = side === "source" ?
          "source_accounting_reference" : "receiving_accounting_reference";
        const actorField = side === "source" ?
          "source_accounting_posted_by" : "receiving_accounting_posted_by";
        const actorNameField = side === "source" ?
          "source_accounting_posted_by_name" : "receiving_accounting_posted_by_name";
        const postedAtField = side === "source" ?
          "source_accounting_posted_at" : "receiving_accounting_posted_at";
        if (invoice[statusField] === "posted") {
          throw new CommandError(
              "accounting-side-already-posted",
              409,
              "This accounting side was already posted.",
          );
        }
        const otherStatusField = side === "source" ?
          "receiving_accounting_status" : "source_accounting_status";
        const completed = invoice[otherStatusField] === "posted";
        const revision = invoice.revision + 1;
        const publicEvent = eventData(
            side === "source" ? "source_accounting_posted" :
              "receiving_accounting_posted",
            side === "source" ?
              "تم ترحيل حركة المناقلة الصادرة محاسبيًا." :
              "تم ترحيل حركة المناقلة الواردة محاسبيًا.",
            actor,
            timestamp,
        );
        if (completed) {
          await closeOpenTasks(transaction, firestore, {
            entityId: invoiceId,
            recipientIds: [actor.uid],
            notificationTypes: ["inter_branch_v3_receipt_confirmed"],
            timestamp,
          });
        }
        transaction.update(invoiceRef, {
          [statusField]: "posted",
          [referenceField]: payload.accounting_reference,
          [actorField]: actor.uid,
          [actorNameField]: actor.name,
          [postedAtField]: timestamp,
          participant_ids: [...new Set([
            ...(Array.isArray(invoice.participant_ids) ? invoice.participant_ids : []),
            actor.uid,
          ])],
          status: completed ? STATUS.postedToAccounting : STATUS.pendingDualAccounting,
          revision,
          last_updated: timestamp,
          history: historyWithEvent(invoice, publicEvent),
        });
        writePublicEvent(transaction, firestore, {invoice, event: publicEvent, revision});
        if (completed) {
          writeNotifications(transaction, firestore, {
            recipients: Array.isArray(invoice.participant_ids) ?
              invoice.participant_ids : [],
            invoice,
            type: "inter_branch_v3_accounting_completed",
            title: "اكتمل ترحيل فاتورة المناقلة",
            message: `اكتمل ترحيل الصادر والوارد للفاتورة رقم ${invoice.invoice_number}.`,
            revision,
            timestamp,
            excludeUid: actor.uid,
          });
        }
        return {
          statusCode: 200,
          responseData: responseFor(
              invoiceId,
              null,
              completed ? STATUS.postedToAccounting : STATUS.pendingDualAccounting,
              revision,
          ),
        };
      }
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
      const receivingBranch = {
        id: invoice.receiving_branch_id,
        data: receivingBranchSnapshot.data(),
      };
      const receiverManagers = await activeReceivingRecipients(
          transaction, firestore, receivingBranch);
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
      await closeOpenTasks(transaction, firestore, {
        entityId: invoiceId,
        recipientIds: [actor.uid],
        notificationTypes: ["inter_branch_v2_prices_confirmed"],
        timestamp,
      });
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

function createOperationalAuthentication({admin}) {
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
  router.use(createOperationalAuthentication({admin}));
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
  router.post("/inter-branch-invoices/:invoiceId/initialize-legacy-dual-accounting", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateLegacyDualAccountingSetupPayload,
    execute: initializeLegacyDualAccounting,
  }));
  router.post("/inter-branch-invoices/:invoiceId/post-accounting", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validatePostingPayload,
    execute: postToAccounting,
  }));
  router.post("/inter-branch-invoices/:invoiceId/request-amendment", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateAmendmentRequestPayload,
    execute: requestAmendment,
  }));
  router.post("/inter-branch-invoices/:invoiceId/decide-amendment", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateAmendmentDecisionPayload,
    execute: decideAmendment,
  }));
  router.post("/inter-branch-invoices/:invoiceId/request-cancellation", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateCancellationRequestPayload,
    execute: requestCancellation,
  }));
  router.post("/inter-branch-invoices/:invoiceId/decide-cancellation", commandRoute({
    admin,
    firestore,
    now,
    randomUUID,
    validator: validateAmendmentDecisionPayload,
    execute: decideCancellation,
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
  decideAmendment,
  decideCancellation,
  isOperationalProfile,
  initializeLegacyDualAccounting,
  notificationReference,
  postToAccounting,
  priceItemsForInvoice,
  receiptItemsForInvoice,
  requestAmendment,
  requestCancellation,
  safeJsonErrorHandler,
};
