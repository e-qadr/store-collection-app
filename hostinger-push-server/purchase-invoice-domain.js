const crypto = require("node:crypto");

const MAX_ITEMS = 50;
const MAX_ID_BYTES = 128;
const MAX_ITEM_ID_BYTES = 64;
const MAX_UNIT_ID_BYTES = 64;
const MAX_NOTES_BYTES = 1000;
const MAX_LINE_NOTES_BYTES = 200;
const MAX_MATERIAL_BYTES = 400;
const MAX_GROUP_BYTES = 300;
const MAX_UNIT_BYTES = 100;
const MAX_SUPPLIER_BYTES = 300;
const MAX_REFERENCE_BYTES = 200;
const MAX_ACCOUNTING_REFERENCE_BYTES = 200;
const MAX_PRICE = 1_000_000_000_000_000;
const MAX_QUANTITY = 1_000_000_000_000_000;
const DOCUMENT_ID_PATTERN = /^[A-Za-z0-9_-]+$/;
const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9._:-]+$/;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f]/;
const SUPPORTED_CURRENCIES = new Set(["YER", "SAR", "USD"]);
const ACCOUNTING_SYNC_STATES = new Set(["not_synced", "pending", "synced", "sync_error"]);

class PurchaseCommandError extends Error {
  constructor(code, status = 400, message = "The request could not be completed.") {
    super(message);
    this.name = "PurchaseCommandError";
    this.code = code;
    this.status = status;
  }
}

function isPlainObject(value) {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function object(value, field = "body") {
  if (!isPlainObject(value)) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} must be an object.`);
  }
  return value;
}

function onlyKeys(value, allowed, field) {
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} has unknown fields.`);
  }
}

function requiredString(value, field, maximumBytes, pattern) {
  if (typeof value !== "string") {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is required.`);
  }
  const clean = value.trim();
  if (!clean || CONTROL_CHARACTER_PATTERN.test(clean) ||
      Buffer.byteLength(clean, "utf8") > maximumBytes ||
      (pattern && !pattern.test(clean))) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  return clean;
}

function optionalString(value, field, maximumBytes, {preserveEmpty = false} = {}) {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  const clean = value.trim();
  if (!clean) return preserveEmpty ? "" : undefined;
  if (CONTROL_CHARACTER_PATTERN.test(clean) || Buffer.byteLength(clean, "utf8") > maximumBytes) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  return clean;
}

function documentId(value, field, maximumBytes = MAX_ID_BYTES) {
  return requiredString(value, field, maximumBytes, DOCUMENT_ID_PATTERN);
}

function number(value, field, {minimum = 0, maximum = MAX_QUANTITY} = {}) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < minimum || value > maximum) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  return value;
}

function revision(value, field = "expected_revision") {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  return value;
}

function boundedItems(value, field = "items") {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_ITEMS) {
    throw new PurchaseCommandError(
        "invalid-argument",
        400,
        `${field} must contain between 1 and ${MAX_ITEMS} items.`,
    );
  }
  return value;
}

function currency(value) {
  const clean = requiredString(value, "currency", 3).toUpperCase();
  if (!SUPPORTED_CURRENCIES.has(clean)) {
    throw new PurchaseCommandError("invalid-argument", 400, "currency is unsupported.");
  }
  return clean;
}

function optionalDate(value, field) {
  const clean = optionalString(value, field, 10);
  if (clean === undefined) return undefined;
  if (!DATE_PATTERN.test(clean)) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  const [year, month, day] = clean.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 ||
      date.getUTCDate() !== day) {
    throw new PurchaseCommandError("invalid-argument", 400, `${field} is invalid.`);
  }
  return clean;
}

function validateCreatePayload(body) {
  const input = object(body);
  onlyKeys(input, new Set([
    "receiving_branch_id", "currency", "supplier_name", "supplier_invoice_number",
    "supplier_invoice_date", "general_manager_notes", "items",
  ]), "body");
  const items = boundedItems(input.items).map((raw, index) => {
    const item = object(raw, `items[${index}]`);
    onlyKeys(item, new Set([
      "source_type", "product_id", "unit_id", "material_name", "group_text",
      "unit_text", "ordered_quantity", "line_notes", "provisional_unit_price",
    ]), `items[${index}]`);
    const sourceType = requiredString(item.source_type, `items[${index}].source_type`, 16);
    if (sourceType !== "catalog" && sourceType !== "unmatched") {
      throw new PurchaseCommandError("invalid-argument", 400, "source_type is invalid.");
    }
    const common = {
      source_type: sourceType,
      ordered_quantity: number(
          item.ordered_quantity,
          `items[${index}].ordered_quantity`,
          {minimum: Number.MIN_VALUE},
      ),
      line_notes: optionalString(
          item.line_notes,
          `items[${index}].line_notes`,
          MAX_LINE_NOTES_BYTES,
      ),
      provisional_unit_price: item.provisional_unit_price === undefined ? undefined :
        number(item.provisional_unit_price, `items[${index}].provisional_unit_price`, {
          maximum: MAX_PRICE,
        }),
    };
    if (sourceType === "catalog") {
      if (item.material_name !== undefined || item.group_text !== undefined ||
          item.unit_text !== undefined) {
        throw new PurchaseCommandError("invalid-argument", 400, "Catalog item fields are invalid.");
      }
      return compact({
        ...common,
        product_id: documentId(item.product_id, `items[${index}].product_id`),
        unit_id: documentId(item.unit_id, `items[${index}].unit_id`, MAX_UNIT_ID_BYTES),
      });
    }
    if (item.product_id !== undefined || item.unit_id !== undefined) {
      throw new PurchaseCommandError("invalid-argument", 400, "Unmatched item fields are invalid.");
    }
    return compact({
      ...common,
      material_name: requiredString(
          item.material_name,
          `items[${index}].material_name`,
          MAX_MATERIAL_BYTES,
      ),
      group_text: optionalString(
          item.group_text,
          `items[${index}].group_text`,
          MAX_GROUP_BYTES,
          {preserveEmpty: true},
      ) ?? "",
      unit_text: requiredString(item.unit_text, `items[${index}].unit_text`, MAX_UNIT_BYTES),
    });
  });
  const selections = new Set();
  for (const item of items) {
    const key = item.source_type === "catalog" ?
      `catalog\u001f${item.product_id}\u001f${item.unit_id}` :
      `unmatched\u001f${normalizeCatalogText(item.material_name)}\u001f${normalizeCatalogText(item.unit_text)}`;
    if (selections.has(key)) {
      throw new PurchaseCommandError("duplicate-item", 400, "An invoice item may appear only once.");
    }
    selections.add(key);
  }
  return compact({
    receiving_branch_id: documentId(input.receiving_branch_id, "receiving_branch_id"),
    currency: currency(input.currency),
    supplier_name: optionalString(input.supplier_name, "supplier_name", MAX_SUPPLIER_BYTES),
    supplier_invoice_number: optionalString(
        input.supplier_invoice_number,
        "supplier_invoice_number",
        MAX_REFERENCE_BYTES,
    ),
    supplier_invoice_date: optionalDate(input.supplier_invoice_date, "supplier_invoice_date"),
    general_manager_notes: optionalString(
        input.general_manager_notes,
        "general_manager_notes",
        MAX_NOTES_BYTES,
    ),
    items,
  });
}

function validateReceiptPayload(body) {
  const input = object(body);
  onlyKeys(input, new Set(["expected_revision", "items", "receiver_notes"]), "body");
  const items = boundedItems(input.items).map((raw, index) => {
    const item = object(raw, `items[${index}]`);
    onlyKeys(item, new Set([
      "item_id", "received_quantity", "damaged_quantity", "missing_quantity",
      "discrepancy_notes",
    ]), `items[${index}]`);
    const received = number(item.received_quantity, `items[${index}].received_quantity`);
    const damaged = item.damaged_quantity === undefined ? 0 :
      number(item.damaged_quantity, `items[${index}].damaged_quantity`);
    const missing = item.missing_quantity === undefined ? 0 :
      number(item.missing_quantity, `items[${index}].missing_quantity`);
    if (damaged > received) {
      throw new PurchaseCommandError("invalid-argument", 400, "Damaged quantity is invalid.");
    }
    return compact({
      item_id: documentId(item.item_id, `items[${index}].item_id`, MAX_ITEM_ID_BYTES),
      received_quantity: received,
      damaged_quantity: damaged,
      missing_quantity: missing,
      discrepancy_notes: optionalString(
          item.discrepancy_notes,
          `items[${index}].discrepancy_notes`,
          MAX_LINE_NOTES_BYTES,
      ),
    });
  });
  ensureUniqueItemIds(items);
  return compact({
    expected_revision: revision(input.expected_revision),
    receiver_notes: optionalString(input.receiver_notes, "receiver_notes", MAX_NOTES_BYTES),
    items,
  });
}

function validatePricingPayload(body) {
  const input = object(body);
  onlyKeys(input, new Set(["expected_revision", "items", "pricing_notes"]), "body");
  const items = boundedItems(input.items).map((raw, index) => {
    const item = object(raw, `items[${index}]`);
    onlyKeys(item, new Set(["item_id", "unit_price"]), `items[${index}]`);
    return {
      item_id: documentId(item.item_id, `items[${index}].item_id`, MAX_ITEM_ID_BYTES),
      unit_price: number(item.unit_price, `items[${index}].unit_price`, {maximum: MAX_PRICE}),
    };
  });
  ensureUniqueItemIds(items);
  return compact({
    expected_revision: revision(input.expected_revision),
    pricing_notes: optionalString(input.pricing_notes, "pricing_notes", MAX_NOTES_BYTES),
    items,
  });
}

function validatePostingPayload(body) {
  const input = object(body);
  onlyKeys(input, new Set([
    "expected_revision", "accounting_reference", "accountant_notes",
    "override_unresolved_materials", "override_reason",
  ]), "body");
  const override = input.override_unresolved_materials === true;
  if (input.override_unresolved_materials !== undefined &&
      typeof input.override_unresolved_materials !== "boolean") {
    throw new PurchaseCommandError("invalid-argument", 400, "override is invalid.");
  }
  const reason = optionalString(input.override_reason, "override_reason", MAX_NOTES_BYTES);
  if (override && !reason) {
    throw new PurchaseCommandError("override-reason-required", 400, "An override reason is required.");
  }
  if (!override && reason) {
    throw new PurchaseCommandError("invalid-argument", 400, "An override reason is not allowed.");
  }
  return compact({
    expected_revision: revision(input.expected_revision),
    accounting_reference: requiredString(
        input.accounting_reference,
        "accounting_reference",
        MAX_ACCOUNTING_REFERENCE_BYTES,
    ),
    accountant_notes: optionalString(input.accountant_notes, "accountant_notes", MAX_NOTES_BYTES),
    override_unresolved_materials: override,
    override_reason: reason,
  });
}

const REVIEW_ACTIONS = new Set([
  "link_existing", "create_product", "request_clarification", "return_to_pending",
  "mark_synchronized",
]);

function validateReviewPayload(body) {
  const input = object(body);
  onlyKeys(input, new Set([
    "expected_revision", "expected_invoice_revision", "action", "product_id", "unit_id",
    "group_id", "material_name", "legacy_code", "units", "primary_unit_id",
    "accounting_reference", "sync_state", "note",
  ]), "body");
  const action = requiredString(input.action, "action", 32);
  if (!REVIEW_ACTIONS.has(action)) {
    throw new PurchaseCommandError("invalid-argument", 400, "action is invalid.");
  }
  const result = {
    expected_revision: revision(input.expected_revision),
    expected_invoice_revision: revision(input.expected_invoice_revision, "expected_invoice_revision"),
    action,
    note: optionalString(input.note, "note", MAX_NOTES_BYTES),
    product_id: input.product_id === undefined ? undefined : documentId(input.product_id, "product_id"),
    unit_id: input.unit_id === undefined ? undefined :
      documentId(input.unit_id, "unit_id", MAX_UNIT_ID_BYTES),
    group_id: input.group_id === undefined ? undefined : documentId(input.group_id, "group_id"),
    material_name: optionalString(input.material_name, "material_name", MAX_MATERIAL_BYTES),
    legacy_code: optionalString(input.legacy_code, "legacy_code", 128),
    primary_unit_id: input.primary_unit_id === undefined ? undefined :
      documentId(input.primary_unit_id, "primary_unit_id", MAX_UNIT_ID_BYTES),
    accounting_reference: optionalString(
        input.accounting_reference,
        "accounting_reference",
        MAX_ACCOUNTING_REFERENCE_BYTES,
    ),
    sync_state: optionalString(input.sync_state, "sync_state", 40),
  };
  if (result.sync_state && !ACCOUNTING_SYNC_STATES.has(result.sync_state)) {
    throw new PurchaseCommandError("invalid-argument", 400, "sync_state is invalid.");
  }
  if (action === "mark_synchronized" && result.sync_state && result.sync_state !== "synced") {
    throw new PurchaseCommandError("invalid-argument", 400, "sync_state is invalid.");
  }
  if (action === "link_existing" && (!result.product_id || !result.unit_id)) {
    throw new PurchaseCommandError("invalid-argument", 400, "product_id and unit_id are required.");
  }
  if (action === "create_product") {
    if (!result.material_name || !result.primary_unit_id || !Array.isArray(input.units)) {
      throw new PurchaseCommandError("invalid-argument", 400, "New product data is incomplete.");
    }
    const units = input.units.map((raw, index) => {
      const unit = object(raw, `units[${index}]`);
      onlyKeys(unit, new Set(["unit_id", "display_value", "raw_value"]), `units[${index}]`);
      return {
        unit_id: documentId(unit.unit_id, `units[${index}].unit_id`, MAX_UNIT_ID_BYTES),
        display_value: requiredString(
            unit.display_value,
            `units[${index}].display_value`,
            MAX_UNIT_BYTES,
        ),
        raw_value: requiredString(unit.raw_value, `units[${index}].raw_value`, MAX_UNIT_BYTES),
      };
    });
    if (units.length < 1 || units.length > 3 ||
        new Set(units.map((unit) => unit.unit_id)).size !== units.length ||
        !units.some((unit) => unit.unit_id === result.primary_unit_id)) {
      throw new PurchaseCommandError("invalid-argument", 400, "Product units are invalid.");
    }
    result.units = units;
  } else if (input.units !== undefined) {
    throw new PurchaseCommandError("invalid-argument", 400, "units are not allowed.");
  }
  if (["request_clarification", "return_to_pending"].includes(action) && !result.note) {
    throw new PurchaseCommandError("invalid-argument", 400, "A note is required.");
  }
  return compact(result);
}

function ensureUniqueItemIds(items) {
  if (new Set(items.map((item) => item.item_id)).size !== items.length) {
    throw new PurchaseCommandError("duplicate-item", 400, "Each item_id must appear once.");
  }
}

function validateIdempotencyKey(value) {
  const key = requiredString(value, "idempotency-key", 128, IDEMPOTENCY_KEY_PATTERN);
  if (Buffer.byteLength(key, "utf8") < 8) {
    throw new PurchaseCommandError("invalid-argument", 400, "idempotency-key is invalid.");
  }
  return key;
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isPlainObject(value)) {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function canonicalRequestHash(value) {
  return crypto.createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function compact(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined));
}

function purchaseItemDigest(items) {
  const stable = items.map((item) => compact({
    item_id: item.item_id,
    line_number: item.line_number,
    source_type: item.source_type,
    original_material_name: item.original_material_name,
    original_group_text: item.original_group_text,
    original_unit_text: item.original_unit_text,
    canonical_product_id: item.canonical_product_id,
    canonical_product_version: item.canonical_product_version,
    canonical_product_name: item.canonical_product_name,
    canonical_group_id: item.canonical_group_id,
    canonical_group_name: item.canonical_group_name,
    canonical_unit_id: item.canonical_unit_id,
    canonical_unit_value: item.canonical_unit_value,
    canonical_unit_raw_value: item.canonical_unit_raw_value,
    review_status: item.review_status,
    ordered_quantity: item.ordered_quantity,
    line_notes: item.line_notes,
    received_quantity: item.received_quantity,
    damaged_quantity: item.damaged_quantity,
    missing_quantity: item.missing_quantity,
    discrepancy_notes: item.discrepancy_notes,
  })).sort((left, right) => left.line_number - right.line_number ||
    left.item_id.localeCompare(right.item_id));
  return crypto.createHash("sha256").update(canonicalJson(stable)).digest("hex");
}

function deterministicDocumentId(...parts) {
  return crypto.createHash("sha256").update(parts.join("\u001f")).digest("hex");
}

function normalizeCatalogText(value) {
  return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "")
      .replace(/\u0640/g, "")
      .replace(/[\u0622\u0623\u0625\u0671]/g, "\u0627")
      .replace(/\u0649/g, "\u064A")
      .replace(/\s+/g, " ");
}

function normalizeLegacyCode(value) {
  return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
}

function base64Key(value) {
  return Buffer.from(value, "utf8").toString("base64url");
}

function productUniqueKeyId({brandId, keyType, normalizedValue}) {
  return `${base64Key(brandId)}-${keyType}-${base64Key(normalizedValue)}`;
}

function productPriceLatestKey({brandId, productId, unitId, currency: value}) {
  return base64Key([brandId, productId, unitId, value].join("\u001f"));
}

function uncategorizedGroupId(brandId) {
  return `system-group-${brandId}-uncategorized`;
}

function publicError(error) {
  if (error instanceof PurchaseCommandError) {
    return {status: error.status, body: {error: {code: error.code, message: error.message}}};
  }
  return {
    status: 500,
    body: {error: {code: "internal", message: "The operation could not be completed safely."}},
  };
}

module.exports = {
  MAX_ITEMS,
  ACCOUNTING_SYNC_STATES,
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
};
