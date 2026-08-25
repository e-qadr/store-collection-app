const assert = require("node:assert/strict");
const test = require("node:test");

const {
  MAX_ITEMS,
  MAX_CATALOG_UNITS,
  PurchaseCommandError,
  normalizeCatalogText,
  productPriceLatestKey,
  purchaseItemDigest,
  validateCreatePayload,
  validateCatalogPricePayload,
  validatePostingPayload,
  validatePricingPayload,
  validateReceiptPayload,
  validateReviewPayload,
} = require("../purchase-invoice-domain");

function fillUtf8Bytes(prefix, maximumBytes, character = "م") {
  const prefixBytes = Buffer.byteLength(prefix, "utf8");
  const characterBytes = Buffer.byteLength(character, "utf8");
  const count = Math.floor((maximumBytes - prefixBytes) / characterBytes);
  const remainder = maximumBytes - prefixBytes - (count * characterBytes);
  return `${prefix}${character.repeat(count)}${"x".repeat(remainder)}`;
}

test("purchase creation accepts catalog, unmatched, optional supplier fields, and provisional prices", () => {
  const result = validateCreatePayload({
    receiving_branch_id: "branch-r",
    currency: "yer",
    supplier_name: " مورد ",
    supplier_invoice_number: " INV-1 ",
    supplier_invoice_date: "2026-08-03",
    items: [
      {
        source_type: "catalog",
        product_id: "product-1",
        unit_id: "primary",
        ordered_quantity: 2,
        provisional_unit_price: 10,
      },
      {
        source_type: "unmatched",
        material_name: "مادة جديدة",
        group_text: "",
        unit_text: "حبة",
        ordered_quantity: 1,
      },
    ],
  });
  assert.equal(result.currency, "YER");
  assert.equal(result.supplier_name, "مورد");
  assert.equal(result.items[1].group_text, "");
  assert.equal(result.items[0].provisional_unit_price, 10);
});

test("purchase creation validates closed source-specific schemas and duplicate selections", () => {
  assert.throws(() => validateCreatePayload({
    receiving_branch_id: "branch-r",
    currency: "YER",
    purchase_number: "PUR-9999",
    items: [{source_type: "catalog", product_id: "product-1", unit_id: "primary", ordered_quantity: 1}],
  }), (error) => error instanceof PurchaseCommandError && error.code === "invalid-argument");
  assert.throws(() => validateCreatePayload({
    receiving_branch_id: "branch-r",
    currency: "YER",
    items: [{
      source_type: "catalog",
      product_id: "product-1",
      unit_id: "primary",
      material_name: "forbidden",
      ordered_quantity: 1,
    }],
  }), (error) => error instanceof PurchaseCommandError && error.code === "invalid-argument");
  assert.throws(() => validateCreatePayload({
    receiving_branch_id: "branch-r",
    currency: "YER",
    items: [
      {source_type: "catalog", product_id: "product-1", unit_id: "primary", ordered_quantity: 1},
      {source_type: "catalog", product_id: "product-1", unit_id: "primary", ordered_quantity: 2},
    ],
  }), (error) => error.code === "duplicate-item");
  assert.throws(() => validateCreatePayload({
    receiving_branch_id: "branch-r",
    currency: "YER",
    items: Array.from({length: MAX_ITEMS + 1}, (_, index) => ({
      source_type: "catalog",
      product_id: `product-${index}`,
      unit_id: "primary",
      ordered_quantity: 1,
    })),
  }), (error) => error.code === "invalid-argument");
});

test("receipt, pricing, posting override, and review payloads are closed", () => {
  assert.deepEqual(validateCatalogPricePayload({
    product_id: "product-1",
    unit_id: "primary",
    currency: "sar",
    price: 45,
  }), {
    product_id: "product-1",
    unit_id: "primary",
    currency: "SAR",
    price: 45,
  });
  assert.throws(() => validateCatalogPricePayload({
    product_id: "product-1",
    unit_id: "primary",
    currency: "SAR",
    price: -1,
  }), (error) => error.code === "invalid-argument");
  assert.equal(validateReceiptPayload({
    expected_revision: 1,
    items: [{item_id: "item-1", received_quantity: 1}],
  }).items[0].missing_quantity, 0);
  assert.equal(validatePricingPayload({
    expected_revision: 2,
    items: [{item_id: "item-1", unit_price: 0}],
  }).items[0].unit_price, 0);
  assert.throws(() => validatePostingPayload({
    expected_revision: 3,
    accounting_reference: "A-1",
    override_unresolved_materials: true,
  }), (error) => error.code === "override-reason-required");
  assert.equal(validatePostingPayload({
    expected_revision: 3,
    accounting_reference: "A-1",
    override_unresolved_materials: true,
    override_reason: "استثناء معتمد",
  }).override_unresolved_materials, true);
  assert.equal(validateReviewPayload({
    expected_revision: 1,
    expected_invoice_revision: 2,
    action: "link_existing",
    product_id: "product-1",
    unit_id: "primary",
  }).action, "link_existing");
  assert.equal(validateReviewPayload({
    expected_revision: 2,
    expected_invoice_revision: 3,
    action: "mark_synchronized",
    sync_state: "synced",
  }).sync_state, "synced");
  assert.throws(() => validateReviewPayload({
    expected_revision: 2,
    expected_invoice_revision: 3,
    action: "mark_synchronized",
    sync_state: "synchronized",
  }), (error) => error.code === "invalid-argument");
});

test("review product validation supports the bounded dynamic catalog unit limit", () => {
  const units = Array.from({length: MAX_CATALOG_UNITS}, (_, index) => ({
    unit_id: index === 0 ? "primary" : `unit_${index + 1}`,
    display_value: `Unit ${index + 1}`,
    raw_value: `Unit ${index + 1}`,
  }));
  assert.equal(validateReviewPayload({
    expected_revision: 1,
    expected_invoice_revision: 1,
    action: "create_product",
    material_name: "New product",
    primary_unit_id: "primary",
    units,
  }).units.length, MAX_CATALOG_UNITS);
  assert.throws(() => validateReviewPayload({
    expected_revision: 1,
    expected_invoice_revision: 1,
    action: "create_product",
    material_name: "Too many units",
    primary_unit_id: "primary",
    units: [...units, {
      unit_id: "unit_4", display_value: "Unit 4", raw_value: "Unit 4",
    }],
  }), (error) => error.code === "invalid-argument");
});

test("catalog normalization, price key, and item digest stay deterministic", () => {
  assert.equal(normalizeCatalogText("  أَصــناف   جديدة "), "اصناف جديدة");
  const expected = Buffer.from("brand\u001fproduct\u001fprimary\u001fYER", "utf8")
      .toString("base64url");
  assert.equal(productPriceLatestKey({
    brandId: "brand", productId: "product", unitId: "primary", currency: "YER",
  }), expected);
  const item = {
    item_id: "item-1",
    line_number: 1,
    source_type: "unmatched",
    original_material_name: "مادة",
    original_group_text: "",
    original_unit_text: "حبة",
    review_status: "pending_review",
    ordered_quantity: 1,
  };
  assert.equal(purchaseItemDigest([item]), purchaseItemDigest([{...item}]));
  assert.notEqual(
      purchaseItemDigest([item]),
      purchaseItemDigest([{...item, review_status: "linked_material"}]),
  );
});

test("measured maximum valid purchase creation fits only the route-specific 64kb parser", () => {
  const body = {
    receiving_branch_id: "b".repeat(128),
    currency: "YER",
    supplier_name: "م".repeat(150),
    supplier_invoice_number: "R".repeat(200),
    supplier_invoice_date: "2026-08-03",
    general_manager_notes: "م".repeat(500),
    items: Array.from({length: 50}, (_, index) => ({
      source_type: "unmatched",
      material_name: fillUtf8Bytes(`${index}-`, 400),
      group_text: "ج".repeat(150),
      unit_text: "و".repeat(50),
      ordered_quantity: 1_000_000_000_000_000,
      line_notes: "ن".repeat(100),
      provisional_unit_price: 1_000_000_000_000_000,
    })),
  };
  const bytes = Buffer.byteLength(JSON.stringify(body), "utf8");
  assert.equal(bytes, 60_393);
  assert.ok(bytes > 16 * 1024, `expected ${bytes} > 16kb`);
  assert.ok(bytes < 64 * 1024, `expected ${bytes} < 64kb`);
  assert.equal(validateCreatePayload(body).items.length, 50);
});
