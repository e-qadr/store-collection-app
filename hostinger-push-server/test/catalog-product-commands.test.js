const assert = require("node:assert/strict");
const test = require("node:test");

const {
  validateCatalogProductPayload,
} = require("../purchase-invoice-commands");

function units(count) {
  return Array.from({length: count}, (_, index) => ({
    unit_id: index === 0 ? "primary" : `unit_${index + 1}`,
    display_value: `وحدة ${index + 1}`,
    raw_value: `وحدة ${index + 1}`,
    base_unit_factor: index === 0 ? 1 : index + 1,
  }));
}

function payload(overrides = {}) {
  return {
    brand_id: "brand-r",
    group_id: "group-r",
    name: "مادة اختبار",
    units: units(1),
    primary_unit_id: "primary",
    source_metadata: {source_profile: "manual"},
    ...overrides,
  };
}

test("trusted catalog command accepts fifty dynamic units", () => {
  const result = validateCatalogProductPayload(payload({units: units(50)}), {
    mode: "create",
  });
  assert.equal(result.units.length, 50);
  assert.equal(result.primary_unit_id, "primary");
});

test("trusted catalog command rejects a fifty-first unit and invalid primary factor", () => {
  assert.throws(
      () => validateCatalogProductPayload(payload({units: units(51)}), {mode: "create"}),
      {code: "invalid-catalog-product"},
  );
  assert.throws(
      () => validateCatalogProductPayload(payload({
        units: [{...units(1)[0], base_unit_factor: 2}],
      }), {mode: "create"}),
      {code: "invalid-catalog-product"},
  );
});

test("trusted catalog command rejects price fields nested inside a unit", () => {
  assert.throws(
      () => validateCatalogProductPayload(payload({
        units: [{...units(1)[0], price: 500}],
      }), {mode: "create"}),
      {code: "invalid-catalog-product"},
  );
  assert.throws(
      () => validateCatalogProductPayload(payload({
        source_metadata: {source_profile: "manual", nested: {cost: 5}},
      }), {mode: "create"}),
      {code: "invalid-catalog-product"},
  );
});
