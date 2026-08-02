const crypto = require("node:crypto");

const MAX_ITEMS = 13;
const MAX_IDEMPOTENCY_KEY_BYTES = 128;
const MAX_DOCUMENT_ID_BYTES = 128;
const MAX_UNIT_ID_BYTES = 64;
const MAX_ITEM_ID_BYTES = 64;
const MAX_INVOICE_NOTES_BYTES = 1000;
const MAX_LINE_NOTES_BYTES = 100;
const MAX_ACCOUNTING_REFERENCE_BYTES = 200;
const MAX_PRICE = 1_000_000_000_000_000;
const MAX_QUANTITY = 1_000_000_000_000_000;
const SUPPORTED_CURRENCIES = new Set(["YER", "SAR", "USD"]);
const DOCUMENT_ID_PATTERN = /^[A-Za-z0-9_-]+$/;
const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9._:-]+$/;
const PRICE_LIKE_KEY_PATTERN =
  /(?:^|_)(?:price|prices|total|cost|amount|currency|suggestion|suggested)(?:_|$)/i;

class CommandError extends Error {
  constructor(code, status = 400, message = "The request could not be completed.") {
    super(message);
    this.name = "CommandError";
    this.code = code;
    this.status = status;
  }
}

function utf8ByteLength(value) {
  return Buffer.byteLength(String(value), "utf8");
}

function isPlainObject(value) {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function requirePlainObject(value, fieldName = "body") {
  if (!isPlainObject(value)) {
    throw new CommandError("invalid-argument", 400, `${fieldName} must be an object.`);
  }
  return value;
}

function requireOnlyKeys(object, allowedKeys, fieldName) {
  const unknown = Object.keys(object).filter((key) => !allowedKeys.has(key));
  if (unknown.length > 0) {
    throw new CommandError("invalid-argument", 400, `${fieldName} has unknown fields.`);
  }
}

function requiredString(value, fieldName, maxBytes, pattern) {
  if (typeof value !== "string") {
    throw new CommandError("invalid-argument", 400, `${fieldName} is required.`);
  }
  const result = value.trim();
  if (!result || utf8ByteLength(result) > maxBytes || (pattern && !pattern.test(result))) {
    throw new CommandError("invalid-argument", 400, `${fieldName} is invalid.`);
  }
  return result;
}

function optionalString(value, fieldName, maxBytes) {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new CommandError("invalid-argument", 400, `${fieldName} is invalid.`);
  }
  const result = value.trim();
  if (!result) return undefined;
  if (utf8ByteLength(result) > maxBytes) {
    throw new CommandError("invalid-argument", 400, `${fieldName} is too long.`);
  }
  return result;
}

function documentId(value, fieldName, maxBytes = MAX_DOCUMENT_ID_BYTES) {
  return requiredString(value, fieldName, maxBytes, DOCUMENT_ID_PATTERN);
}

function finiteNumber(value, fieldName, {minimum = 0, maximum = MAX_QUANTITY} = {}) {
  if (typeof value !== "number" ||
      !Number.isFinite(value) ||
      value < minimum ||
      value > maximum) {
    throw new CommandError("invalid-argument", 400, `${fieldName} is invalid.`);
  }
  return value;
}

function positiveRevision(value) {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new CommandError("invalid-argument", 400, "expected_revision is invalid.");
  }
  return value;
}

function boundedItems(value, fieldName = "items") {
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_ITEMS) {
    throw new CommandError(
        "invalid-argument",
        400,
        `${fieldName} must contain between 1 and ${MAX_ITEMS} items.`,
    );
  }
  return value;
}

function assertNoPriceLikeKeys(value, path = "body") {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoPriceLikeKeys(entry, `${path}[${index}]`));
    return;
  }
  if (!isPlainObject(value)) return;
  for (const [key, nested] of Object.entries(value)) {
    if (PRICE_LIKE_KEY_PATTERN.test(key)) {
      throw new CommandError("price-field-forbidden", 400, `${path} has a forbidden field.`);
    }
    assertNoPriceLikeKeys(nested, `${path}.${key}`);
  }
}

function validateCreatePayload(body) {
  const input = requirePlainObject(body);
  assertNoPriceLikeKeys(input);
  requireOnlyKeys(
      input,
      new Set(["receiving_branch_id", "items", "invoice_notes"]),
      "body",
  );
  const items = boundedItems(input.items).map((raw, index) => {
    const item = requirePlainObject(raw, `items[${index}]`);
    requireOnlyKeys(
        item,
        new Set(["product_id", "unit_id", "supplied_quantity", "line_notes"]),
        `items[${index}]`,
    );
    return {
      product_id: documentId(item.product_id, `items[${index}].product_id`),
      unit_id: documentId(item.unit_id, `items[${index}].unit_id`, MAX_UNIT_ID_BYTES),
      supplied_quantity: finiteNumber(
          item.supplied_quantity,
          `items[${index}].supplied_quantity`,
          {minimum: Number.MIN_VALUE},
      ),
      line_notes: optionalString(
          item.line_notes,
          `items[${index}].line_notes`,
          MAX_LINE_NOTES_BYTES,
      ),
    };
  });
  const uniqueSelections = new Set();
  for (const item of items) {
    const key = `${item.product_id}\u001f${item.unit_id}`;
    if (uniqueSelections.has(key)) {
      throw new CommandError("duplicate-item", 400, "A product and unit may appear only once.");
    }
    uniqueSelections.add(key);
  }
  return {
    receiving_branch_id: documentId(input.receiving_branch_id, "receiving_branch_id"),
    invoice_notes: optionalString(
        input.invoice_notes,
        "invoice_notes",
        MAX_INVOICE_NOTES_BYTES,
    ),
    items,
  };
}

function validateReceiptPayload(body) {
  const input = requirePlainObject(body);
  assertNoPriceLikeKeys(input);
  requireOnlyKeys(
      input,
      new Set(["expected_revision", "items", "receiver_notes"]),
      "body",
  );
  const items = boundedItems(input.items).map((raw, index) => {
    const item = requirePlainObject(raw, `items[${index}]`);
    requireOnlyKeys(
        item,
        new Set([
          "item_id",
          "received_quantity",
          "damaged_quantity",
          "missing_quantity",
          "discrepancy_notes",
        ]),
        `items[${index}]`,
    );
    const receivedQuantity = finiteNumber(
        item.received_quantity,
        `items[${index}].received_quantity`,
    );
    const damagedQuantity = item.damaged_quantity === undefined ?
      0 : finiteNumber(item.damaged_quantity, `items[${index}].damaged_quantity`);
    const missingQuantity = item.missing_quantity === undefined ?
      0 : finiteNumber(item.missing_quantity, `items[${index}].missing_quantity`);
    if (damagedQuantity > receivedQuantity) {
      throw new CommandError(
          "invalid-argument",
          400,
          "Damaged quantity cannot exceed the received quantity.",
      );
    }
    return {
      item_id: documentId(item.item_id, `items[${index}].item_id`, MAX_ITEM_ID_BYTES),
      received_quantity: receivedQuantity,
      damaged_quantity: damagedQuantity,
      missing_quantity: missingQuantity,
      discrepancy_notes: optionalString(
          item.discrepancy_notes,
          `items[${index}].discrepancy_notes`,
          MAX_LINE_NOTES_BYTES,
      ),
    };
  });
  ensureUniqueItemIds(items);
  return {
    expected_revision: positiveRevision(input.expected_revision),
    receiver_notes: optionalString(
        input.receiver_notes,
        "receiver_notes",
        MAX_INVOICE_NOTES_BYTES,
    ),
    items,
  };
}

function validatePricingPayload(body) {
  const input = requirePlainObject(body);
  requireOnlyKeys(
      input,
      new Set(["expected_revision", "currency", "items", "pricing_notes"]),
      "body",
  );
  const currency = requiredString(input.currency, "currency", 3).toUpperCase();
  if (!SUPPORTED_CURRENCIES.has(currency)) {
    throw new CommandError("invalid-argument", 400, "currency is unsupported.");
  }
  const items = boundedItems(input.items).map((raw, index) => {
    const item = requirePlainObject(raw, `items[${index}]`);
    requireOnlyKeys(item, new Set(["item_id", "unit_price"]), `items[${index}]`);
    return {
      item_id: documentId(item.item_id, `items[${index}].item_id`, MAX_ITEM_ID_BYTES),
      unit_price: finiteNumber(
          item.unit_price,
          `items[${index}].unit_price`,
          {maximum: MAX_PRICE},
      ),
    };
  });
  ensureUniqueItemIds(items);
  return {
    expected_revision: positiveRevision(input.expected_revision),
    currency,
    pricing_notes: optionalString(
        input.pricing_notes,
        "pricing_notes",
        MAX_INVOICE_NOTES_BYTES,
    ),
    items,
  };
}

function validatePostingPayload(body) {
  const input = requirePlainObject(body);
  assertNoPriceLikeKeys(input);
  requireOnlyKeys(
      input,
      new Set(["expected_revision", "accounting_reference", "accounting_notes"]),
      "body",
  );
  return {
    expected_revision: positiveRevision(input.expected_revision),
    accounting_reference: requiredString(
        input.accounting_reference,
        "accounting_reference",
        MAX_ACCOUNTING_REFERENCE_BYTES,
    ),
    accounting_notes: optionalString(
        input.accounting_notes,
        "accounting_notes",
        MAX_INVOICE_NOTES_BYTES,
    ),
  };
}

function ensureUniqueItemIds(items) {
  const ids = new Set();
  for (const item of items) {
    if (ids.has(item.item_id)) {
      throw new CommandError("duplicate-item", 400, "Each item_id must appear once.");
    }
    ids.add(item.item_id);
  }
}

function validateIdempotencyKey(value) {
  const key = requiredString(
      value,
      "idempotency-key",
      MAX_IDEMPOTENCY_KEY_BYTES,
      IDEMPOTENCY_KEY_PATTERN,
  );
  if (utf8ByteLength(key) < 8) {
    throw new CommandError("invalid-argument", 400, "idempotency-key is invalid.");
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

function invoiceItemDigest(items) {
  const snapshots = items.map((item) => ({
    item_id: String(item.item_id),
    product_id: String(item.product_id),
    product_brand_id: String(item.product_brand_id),
    unit_id: String(item.unit_id),
    unit_value: String(item.unit_value),
    supplied_quantity: Number(item.supplied_quantity),
    received_quantity: Number(item.received_quantity),
  }));
  return crypto.createHash("sha256").update(canonicalJson(snapshots)).digest("hex");
}

function deterministicDocumentId(...parts) {
  return crypto.createHash("sha256").update(parts.join("\u001f")).digest("hex");
}

function productPriceLatestKey({brandId, productId, unitId, currency}) {
  const parts = [brandId, productId, unitId, currency].map((value) => String(value).trim());
  if (parts.some((value) => !value)) {
    throw new CommandError("internal", 500, "A protected price key could not be built.");
  }
  return Buffer.from(parts.join("\u001f"), "utf8").toString("base64url");
}

function invoiceNumberFor(branchCode, nextNumber) {
  const code = String(branchCode || "").trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) {
    throw new CommandError("branch-code-invalid", 409, "The supplying branch code is not configured.");
  }
  if (!Number.isSafeInteger(nextNumber) || nextNumber < 0) {
    throw new CommandError("counter-invalid", 409, "The invoice counter is not configured.");
  }
  return `${code}${String(nextNumber).padStart(4, "0")}`;
}

function publicError(error) {
  if (error instanceof CommandError) {
    return {
      status: error.status,
      body: {error: {code: error.code, message: error.message}},
    };
  }
  return {
    status: 500,
    body: {
      error: {
        code: "internal",
        message: "The operation could not be completed safely.",
      },
    },
  };
}

module.exports = {
  CommandError,
  MAX_ITEMS,
  SUPPORTED_CURRENCIES,
  assertNoPriceLikeKeys,
  canonicalJson,
  canonicalRequestHash,
  deterministicDocumentId,
  documentId,
  invoiceItemDigest,
  invoiceNumberFor,
  isPlainObject,
  productPriceLatestKey,
  publicError,
  utf8ByteLength,
  validateCreatePayload,
  validateIdempotencyKey,
  validatePostingPayload,
  validatePricingPayload,
  validateReceiptPayload,
};
