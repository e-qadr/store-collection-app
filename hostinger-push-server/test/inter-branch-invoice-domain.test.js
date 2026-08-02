const assert = require("node:assert/strict");
const test = require("node:test");

const {
  CommandError,
  MAX_ITEMS,
  canonicalRequestHash,
  invoiceItemDigest,
  invoiceNumberFor,
  productPriceLatestKey,
  utf8ByteLength,
  validateCreatePayload,
  validateIdempotencyKey,
  validatePostingPayload,
  validatePricingPayload,
  validateReceiptPayload,
} = require("../inter-branch-invoice-domain");

test("direct creation accepts a bounded, price-free catalog payload", () => {
  const payload = validateCreatePayload({
    receiving_branch_id: "branch-b",
    invoice_notes: "ملاحظات عامة",
    items: [{
      product_id: "product-1",
      unit_id: "unit_2",
      supplied_quantity: 12.5,
      line_notes: "سليم",
    }],
  });
  assert.equal(payload.items[0].supplied_quantity, 12.5);
  assert.throws(
      () => validateCreatePayload({
        receiving_branch_id: "branch-b",
        items: [{
          product_id: "product-1",
          unit_id: "unit_2",
          supplied_quantity: 1,
          unit_price: 3,
        }],
      }),
      (error) => error instanceof CommandError && error.code === "price-field-forbidden",
  );
});

test("creation rejects duplicate catalog selections and more than MAX_ITEMS", () => {
  const duplicate = {
    receiving_branch_id: "branch-b",
    items: [
      {product_id: "product-1", unit_id: "primary", supplied_quantity: 1},
      {product_id: "product-1", unit_id: "primary", supplied_quantity: 2},
    ],
  };
  assert.throws(
      () => validateCreatePayload(duplicate),
      (error) => error.code === "duplicate-item",
  );
  assert.throws(
      () => validateCreatePayload({
        receiving_branch_id: "branch-b",
        items: Array.from({length: MAX_ITEMS + 1}, (_, index) => ({
          product_id: `product-${index}`,
          unit_id: "primary",
          supplied_quantity: 1,
        })),
      }),
      (error) => error.code === "invalid-argument",
  );
});

test("transition payloads require a complete safe shape", () => {
  const receipt = validateReceiptPayload({
    expected_revision: 1,
    receiver_notes: "تمت المراجعة",
    items: [{
      item_id: "item-1",
      received_quantity: 8,
      damaged_quantity: 1,
      missing_quantity: 2,
      discrepancy_notes: "نقص",
    }],
  });
  assert.equal(receipt.items[0].missing_quantity, 2);
  assert.throws(
      () => validateReceiptPayload({
        expected_revision: 1,
        items: [{item_id: "item-1", received_quantity: 1, damaged_quantity: 2}],
      }),
      (error) => error.code === "invalid-argument",
  );

  const pricing = validatePricingPayload({
    expected_revision: 2,
    currency: "yer",
    items: [{item_id: "item-1", unit_price: 0}],
  });
  assert.equal(pricing.currency, "YER");
  assert.throws(
      () => validatePricingPayload({
        expected_revision: 2,
        currency: "EUR",
        items: [{item_id: "item-1", unit_price: 1}],
      }),
      (error) => error.code === "invalid-argument",
  );

  const posting = validatePostingPayload({
    expected_revision: 3,
    accounting_reference: "ACC-1",
    accounting_notes: "ملاحظة محمية",
  });
  assert.equal(posting.accounting_reference, "ACC-1");

  const maximumReceiptItems = Array.from({length: MAX_ITEMS}, (_, index) => ({
    item_id: `receipt-${index}`,
    received_quantity: 1,
  }));
  assert.equal(validateReceiptPayload({
    expected_revision: 1,
    items: maximumReceiptItems,
  }).items.length, MAX_ITEMS);
  assert.throws(
      () => validateReceiptPayload({
        expected_revision: 1,
        items: [...maximumReceiptItems, {item_id: "receipt-overflow", received_quantity: 1}],
      }),
      (error) => error.code === "invalid-argument",
  );

  const maximumPricingItems = Array.from({length: MAX_ITEMS}, (_, index) => ({
    item_id: `pricing-${index}`,
    unit_price: 1,
  }));
  assert.equal(validatePricingPayload({
    expected_revision: 2,
    currency: "YER",
    items: maximumPricingItems,
  }).items.length, MAX_ITEMS);
  assert.throws(
      () => validatePricingPayload({
        expected_revision: 2,
        currency: "YER",
        items: [...maximumPricingItems, {item_id: "pricing-overflow", unit_price: 1}],
      }),
      (error) => error.code === "invalid-argument",
  );
});

test("idempotency keys have an ASCII minimum and maximum", () => {
  assert.equal(validateIdempotencyKey("request-0001"), "request-0001");
  assert.throws(() => validateIdempotencyKey("short"), /idempotency-key/);
  assert.throws(() => validateIdempotencyKey("contains space"), /idempotency-key/);
});

test("legacy invoice number formatting preserves zero and values above four digits", () => {
  assert.equal(invoiceNumberFor("ab", 0), "AB0000");
  assert.equal(invoiceNumberFor("AB", 10000), "AB10000");
  assert.throws(
      () => invoiceNumberFor("A1", 1),
      (error) => error.code === "branch-code-invalid",
  );
});

test("price-memory key exactly matches the Dart base64url contract", () => {
  const values = ["brand-a", "product-1", "unit_2", "YER"];
  const expected = Buffer.from(values.join("\u001f"), "utf8").toString("base64url");
  assert.equal(productPriceLatestKey({
    brandId: values[0],
    productId: values[1],
    unitId: values[2],
    currency: values[3],
  }), expected);
});

test("item digest is stable and includes confirmed quantities", () => {
  const item = {
    item_id: "item-1",
    product_id: "product-1",
    product_brand_id: "brand-a",
    unit_id: "primary",
    unit_value: "حبة",
    supplied_quantity: 10,
    received_quantity: 8,
  };
  assert.equal(invoiceItemDigest([item]), invoiceItemDigest([{...item}]));
  assert.notEqual(
      invoiceItemDigest([item]),
      invoiceItemDigest([{...item, received_quantity: 9}]),
  );
});

test("the measured worst-case 13-line creation remains below 16kb", () => {
  const payload = {
    receiving_branch_id: "b".repeat(128),
    invoice_notes: "م".repeat(500),
    items: Array.from({length: MAX_ITEMS}, (_, index) => ({
      product_id: `${"p".repeat(125)}${String(index).padStart(3, "0")}`,
      unit_id: "u".repeat(64),
      supplied_quantity: 1000000000000000,
      line_notes: "م".repeat(50),
    })),
  };
  const bytes = utf8ByteLength(JSON.stringify(payload));
  assert.equal(bytes, 6071);
  assert.equal((16 * 1024) - bytes, 10313);
  assert.ok(bytes < 16 * 1024);
  assert.equal(canonicalRequestHash(payload).length, 64);
});
