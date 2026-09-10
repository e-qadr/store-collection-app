"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {buildBackfillPlan, isCompleteCanonicalItem, productForOperation} =
  require("../purchase-catalog-backfill");

function candidate({id, name = "مواد أصلية", group = "مواد غذائية", unit = "حبة"} = {}) {
  return {
    id,
    path: `purchase_invoices/invoice-1/items/${id}`,
    data: {
      source_type: "unmatched",
      receiving_brand_id: "brand-1",
      original_material_name: name,
      original_group_text: group,
      original_unit_text: unit,
      line_number: 1,
    },
  };
}

function context() {
  return {
    groups: new Map([["brand-1", [{
      id: "group-1", brand_id: "brand-1", name: "مواد غذائية",
      normalized_name: "مواد غذائية", active: true,
    }]]]),
    products: new Map([["brand-1", []]]),
  };
}

function containsProtectedKey(value) {
  if (!value || typeof value !== "object") return false;
  return Object.entries(value).some(([key, child]) =>
    /(price|cost|amount|currency|سعر)/iu.test(key) || containsProtectedKey(child),
  );
}

test("purchase catalog backfill creates only one canonical operation for identical sources", () => {
  const plan = buildBackfillPlan({
    projectId: "store-collection-app",
    scannedCount: 2,
    scanReachedLimit: false,
    candidates: [candidate({id: "line-2"}), candidate({id: "line-1"})],
    ...context(),
  });

  assert.equal(plan.counts.safe_products, 1);
  assert.equal(plan.counts.skipped, 0);
  assert.equal(plan.operations[0].source_invoice_item_paths.length, 2);
  const product = productForOperation(plan.operations[0], plan);
  assert.equal(product.group_id, "group-1");
  assert.equal(product.units[0].raw_value, "حبة");
  assert.equal(containsProtectedKey(product), false);
});

test("purchase catalog backfill skips an existing name with a different unit", () => {
  const state = context();
  state.products.set("brand-1", [{
    id: "existing-product",
    brand_id: "brand-1",
    group_id: "group-1",
    name: "مواد أصلية",
    normalized_name: "مواد أصلية",
    active: true,
    units: [{unit_id: "primary", display_value: "كرتون", raw_value: "كرتون"}],
  }]);
  const plan = buildBackfillPlan({
    projectId: "store-collection-app",
    scannedCount: 1,
    scanReachedLimit: false,
    candidates: [candidate({id: "line-1"})],
    ...state,
  });

  assert.equal(plan.counts.safe_products, 0);
  assert.equal(plan.counts.skipped, 1);
  assert.equal(
      plan.candidates[0].reason,
      "existing-product-name-conflict-or-unit-mismatch",
  );
});

test("only fully canonical purchase items are excluded from the bounded audit", () => {
  assert.equal(isCompleteCanonicalItem({
    canonical_product_id: "product", canonical_group_id: "group", canonical_unit_id: "unit",
  }), true);
  assert.equal(isCompleteCanonicalItem({canonical_product_id: "product"}), false);
});
