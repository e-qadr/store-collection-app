"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  applyCatalogImport,
  applyRollback,
  assertCheckpointStateCapacity,
  buildCatalogImportPlan,
  buildRollbackPlan,
  CHECKPOINT_BATCH_SIZE,
  checkpointStateBytes,
  expectedConfirmation,
  expectedRollbackConfirmation,
  MAX_CHECKPOINT_STATE_BYTES,
  readProductionContext,
  retryAbortedFirestoreOperation,
} = require("../catalog-import-executor");
const {FakeFirestore} = require("./support/fake-firestore");

const BRAND_ID = "TlOswncJiWX7mwsf3U4e";
const BRAND_NAME = "الأصالة";
const PROFILE = "al_asalah_legacy_catalog";
const EQLID_BRAND_ID = "WLMnMVT6u1H2VQ0qziJ3";
const EQLID_BRAND_NAME = "إقليد";
const EQLID_PROFILE = "eqlid_legacy_catalog";
const ACTOR = "accountant-1";
const PROJECT = "production-project";

function seed() {
  return {
    brands: {[BRAND_ID]: {id: BRAND_ID, name: BRAND_NAME}},
    users: {
      [ACTOR]: {
        name: "محاسب الاختبار", role: "accountant", isActive: true,
        mustChangePassword: false,
      },
    },
  };
}

function preview({missingGroup = false, missingUnit = false} = {}) {
  const groupId = missingGroup ?
    `system-group-${BRAND_ID}-uncategorized` : "group-fixture";
  const record = {
    source_profile: PROFILE,
    source_hash: "a".repeat(64),
    source_sheet: "Page1",
    source_row: 7,
    brand_id: BRAND_ID,
    raw_material_value: "1001-منتج اختبار",
    raw_group_value: missingGroup ? "" : "1-مجموعة اختبار",
    raw_units: {primary: missingUnit ? "" : "حبة", unit_2: "علبة", unit_3: ""},
    legacy_code: "1001",
    product_name: "منتج اختبار",
    group_legacy_code: missingGroup ? null : "1",
    group_name: missingGroup ? null : "مجموعة اختبار",
    group_resolution: {
      original_group_missing: missingGroup,
      fallback_system_group_assigned: missingGroup && !missingUnit,
      ...(missingGroup && !missingUnit ? {
        fallback_system_group_key: "uncategorized",
        fallback_system_group_id: groupId,
      } : {}),
    },
    fingerprint: "b".repeat(64),
    issues: missingUnit ? [{code: "missing_primary_unit", severity: "error"}] : [],
  };
  const entry = {action: "create", assigned_group_id: groupId, record};
  return {
    dry_run: true,
    writes_performed: false,
    prices_parsed: false,
    source: {
      sha256: "a".repeat(64), worksheet: "Page1", source_rows: 12,
    },
    creates: missingUnit ? [] : [entry],
    updates: [],
    unchanged: [],
    blocked_other: missingUnit ? [record] : [],
    normal_group_plans: missingGroup || missingUnit ? [] : [{
      group_id: groupId,
      name: "مجموعة اختبار",
      normalized_name: "مجموعة اختبار",
      source_legacy_codes: ["1"],
    }],
    system_group_plans: missingGroup && !missingUnit ? [{group_id: groupId}] : [],
    duplicates: [],
    skipped_rows: [{source_row: 1, reason: "report_title"}],
  };
}

function previewWithSourceValidationReviews(count = 1) {
  const value = preview();
  value.blocked_other = Array.from({length: count}, (_, index) => ({
    ...value.creates[0].record,
    source_row: 8 + index,
    raw_units: {primary: "", unit_2: "", unit_3: ""},
    issues: [{code: "missing_primary_unit", severity: "error"}],
  }));
  return value;
}

function previewWithProducts(count) {
  const value = preview();
  const first = value.creates[0];
  value.creates = Array.from({length: count}, (_, index) => {
    const ordinal = index + 1;
    return {
      ...first,
      record: {
        ...first.record,
        source_row: 6 + ordinal,
        raw_material_value: `${1000 + ordinal}-منتج اختبار ${ordinal}`,
        legacy_code: String(1000 + ordinal),
        product_name: `منتج اختبار ${ordinal}`,
        fingerprint: ordinal.toString(16).padStart(64, "0"),
      },
    };
  });
  return value;
}

async function context(firestore) {
  return readProductionContext({
    firestore, profile: PROFILE, brandId: BRAND_ID,
    brandName: BRAND_NAME, actorUid: ACTOR,
  });
}

test("live brand and active accountant must exactly match the source profile", async () => {
  const missingBrand = new FakeFirestore({users: seed().users});
  await assert.rejects(() => context(missingBrand), (error) =>
    error.code === "brand-not-found");

  const wrongName = seed();
  wrongName.brands[BRAND_ID].name = "علامة أخرى";
  await assert.rejects(() => context(new FakeFirestore(wrongName)), (error) =>
    error.code === "live-brand-name-mismatch");

  const wrongRole = seed();
  wrongRole.users[ACTOR].role = "manager";
  await assert.rejects(() => context(new FakeFirestore(wrongRole)), (error) =>
    error.code === "active-accountant-required");
});

test("Eqlid requires the canonical production brand spelling", async () => {
  const firestore = new FakeFirestore({
    brands: {
      [EQLID_BRAND_ID]: {id: EQLID_BRAND_ID, name: EQLID_BRAND_NAME},
    },
    users: seed().users,
  });
  const result = await readProductionContext({
    firestore,
    profile: EQLID_PROFILE,
    brandId: EQLID_BRAND_ID,
    brandName: EQLID_BRAND_NAME,
    actorUid: ACTOR,
  });
  assert.equal(result.brand.name, EQLID_BRAND_NAME);

  await assert.rejects(() => readProductionContext({
    firestore,
    profile: EQLID_PROFILE,
    brandId: EQLID_BRAND_ID,
    brandName: "اقليد",
    actorUid: ACTOR,
  }), (error) => error.code === "brand-name-mismatch");
});

test("apply requires the exact second confirmation and creates no price fields", async () => {
  const firestore = new FakeFirestore(seed());
  const plan = buildCatalogImportPlan({
    preview: preview(), context: await context(firestore), profile: PROFILE,
  });
  assert.equal(plan.counts.products_create, 1);
  assert.equal(plan.counts.groups_create, 1);
  await assert.rejects(() => applyCatalogImport({
    firestore, plan, projectId: PROJECT, confirmation: "wrong",
  }), (error) => error.code === "apply-confirmation-mismatch");
  assert.equal(firestore.documents("products").length, 0);

  const confirmation = expectedConfirmation({
    projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
  });
  const result = await applyCatalogImport({
    firestore, plan, projectId: PROJECT, confirmation,
    clock: () => new Date("2026-08-06T10:00:00.000Z"),
  });
  assert.equal(result.status, "completed");
  const product = firestore.documents("products")[0];
  assert.equal(product.source_metadata.source_fingerprint, "b".repeat(64));
  assert.equal(product.source_metadata.import_id, plan.run_id);
  assert.equal(JSON.stringify(product).match(/price|cost|currency/gi), null);
  assert.equal(firestore.documents("catalog_import_manifests").length, 1);
  assert.equal(firestore.documents("product_audit_events").length, 2);
});

test("same import resumes idempotently while manual products are never overwritten", async () => {
  const firestore = new FakeFirestore(seed());
  let currentContext = await context(firestore);
  let plan = buildCatalogImportPlan({preview: preview(), context: currentContext, profile: PROFILE});
  const confirmation = expectedConfirmation({
    projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
  });
  await applyCatalogImport({firestore, plan, projectId: PROJECT, confirmation});

  currentContext = await context(firestore);
  plan = buildCatalogImportPlan({preview: preview(), context: currentContext, profile: PROFILE});
  assert.equal(plan.counts.products_create, 0);
  assert.equal(plan.counts.products_unchanged, 1);
  const retryConfirmation = expectedConfirmation({
    projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
  });
  await applyCatalogImport({firestore, plan, projectId: PROJECT, confirmation: retryConfirmation});
  assert.equal(firestore.documents("products").length, 1);
  assert.equal(firestore.documents("catalog_import_manifests").length, 1);

  const product = firestore.documents("products")[0];
  firestore._collection("products").set(product.id, {...product, version: 2, name: "تصحيح يدوي"});
  const protectedPlan = buildCatalogImportPlan({
    preview: preview(), context: await context(firestore), profile: PROFILE,
  });
  assert.equal(protectedPlan.counts.products_create, 0);
  assert.equal(protectedPlan.review_rows[0].reason,
      "existing-product-preserved-for-accountant-review");
});

test("missing groups use only the exact system fallback; invalid units stay review-only", async () => {
  const firestore = new FakeFirestore(seed());
  let plan = buildCatalogImportPlan({
    preview: preview({missingGroup: true}), context: await context(firestore), profile: PROFILE,
  });
  assert.equal(plan.groupOperations.create[0].name, "غير مصنف");
  assert.equal(plan.productOperations[0].product.source_metadata.original_group_missing, true);
  assert.equal(plan.productOperations[0].product.source_metadata.raw_group_value, "");

  plan = buildCatalogImportPlan({
    preview: preview({missingUnit: true}), context: await context(firestore), profile: PROFILE,
  });
  assert.equal(plan.counts.products_create, 0);
  assert.deepEqual(plan.review_rows, [{source_row: 7, reason: "source-validation-required"}]);
});

test("the seven source-validation-required Eqlid rows stay excluded and recorded", async () => {
  const firestore = new FakeFirestore(seed());
  const plan = buildCatalogImportPlan({
    preview: previewWithSourceValidationReviews(7),
    context: await context(firestore), profile: PROFILE,
  });
  assert.equal(plan.counts.products_create, 1);
  assert.deepEqual(plan.review_rows, Array.from({length: 7}, (_, index) => ({
    source_row: 8 + index, reason: "source-validation-required",
  })));

  await applyCatalogImport({
    firestore, plan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
    }),
  });

  assert.equal(firestore.documents("products").length, 1);
  assert.deepEqual(
      firestore.documents("products").map((product) => product.source_metadata.source_row),
      [7]);
  const manifest = firestore.documents("catalog_import_manifests")[0];
  assert.deepEqual(manifest.review_rows, Array.from({length: 7}, (_, index) => ({
    source_row: 8 + index, reason: "source-validation-required",
  })));
  assert.equal(manifest.applied_counts.products, 1);
  assert.equal(JSON.stringify(firestore.documents("products")).match(/price|cost|currency/gi), null);
});

test("checkpoint retries only transient Firestore aborted errors", async () => {
  let attempts = 0;
  const waits = [];
  const result = await retryAbortedFirestoreOperation(async () => {
    attempts += 1;
    if (attempts < 3) throw Object.assign(new Error("aborted"), {code: 10});
    return "completed";
  }, {wait: async (milliseconds) => { waits.push(milliseconds); }});
  assert.equal(result, "completed");
  assert.equal(attempts, 3);
  assert.deepEqual(waits, [1000, 2000]);

  attempts = 0;
  await assert.rejects(() => retryAbortedFirestoreOperation(async () => {
    attempts += 1;
    throw Object.assign(new Error("permission denied"), {code: 7});
  }, {wait: async () => { throw new Error("must not wait"); }}), /permission denied/);
  assert.equal(attempts, 1);
});

test("a lost response after an atomic product chunk stops without retrying code 8", async () => {
  const firestore = new FakeFirestore(seed());
  const initialPlan = buildCatalogImportPlan({
    preview: previewWithProducts(3), context: await context(firestore), profile: PROFILE,
  });
  const expectedIds = initialPlan.productOperations.map((entry) => entry.product.id).sort();
  const originalRunTransaction = firestore.runTransaction.bind(firestore);
  let transactionCount = 0;
  firestore.runTransaction = (callback) => {
    transactionCount += 1;
    return originalRunTransaction(callback).then((result) => {
      if (transactionCount === 3) {
        throw Object.assign(new Error("resource exhausted"), {code: 8});
      }
      return result;
    });
  };

  await assert.rejects(() => applyCatalogImport({
    firestore, plan: initialPlan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: initialPlan.run_id, planChecksum: initialPlan.plan_checksum,
    }),
    checkpointBatchSize: 2,
    chunkPauseMs: 0,
  }), (error) => error.code === 8);

  assert.equal(transactionCount, 3);
  assert.equal(firestore.documents("products").length, 2);
  assert.equal(firestore.documents("catalog_import_manifests").length, 0);
  const committedChunk = firestore.document(
      `catalog_import_run_state/${initialPlan.run_id}/chunks`, "products-0000");
  assert.deepEqual([...committedChunk.operation_ids].sort(), expectedIds.slice(0, 2));

  firestore.runTransaction = originalRunTransaction;
  const resumedPlan = buildCatalogImportPlan({
    preview: previewWithProducts(3), context: await context(firestore), profile: PROFILE,
  });
  assert.equal(resumedPlan.counts.products_create, 1);
  assert.equal(resumedPlan.counts.products_unchanged, 2);
  await applyCatalogImport({
    firestore, plan: resumedPlan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: resumedPlan.run_id, planChecksum: resumedPlan.plan_checksum,
    }),
    checkpointBatchSize: 2,
    chunkPauseMs: 0,
  });

  const finalProducts = firestore.documents("products").map((product) => product.id).sort();
  assert.deepEqual(finalProducts, expectedIds);
  assert.equal(new Set(finalProducts).size, 3);
  const state = firestore.document("catalog_import_run_state", resumedPlan.run_id);
  assert.deepEqual([...state.initial_product_ids].sort(), expectedIds);
  const manifest = firestore.documents("catalog_import_manifests")[0];
  assert.equal(manifest.status, "completed");
  assert.equal(manifest.applied_counts.products, 3);
});

test("a legacy checkpoint gap is reconciled without duplicate catalog ownership", async () => {
  const firestore = new FakeFirestore(seed());
  const initialPlan = buildCatalogImportPlan({
    preview: previewWithProducts(3), context: await context(firestore), profile: PROFILE,
  });
  const expectedIds = initialPlan.productOperations.map((entry) => entry.product.id).sort();
  const originalRunTransaction = firestore.runTransaction.bind(firestore);
  let transactionCount = 0;
  firestore.runTransaction = (callback) => {
    transactionCount += 1;
    return originalRunTransaction(callback).then((result) => {
      if (transactionCount === 3) {
        throw Object.assign(new Error("response lost"), {code: 8});
      }
      return result;
    });
  };
  await assert.rejects(() => applyCatalogImport({
    firestore, plan: initialPlan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: initialPlan.run_id, planChecksum: initialPlan.plan_checksum,
    }),
    checkpointBatchSize: 2,
    chunkPauseMs: 0,
  }), (error) => error.code === 8);
  firestore._collection(`catalog_import_run_state/${initialPlan.run_id}/chunks`)
      .delete("products-0000");
  firestore.runTransaction = originalRunTransaction;

  const resumedPlan = buildCatalogImportPlan({
    preview: previewWithProducts(3), context: await context(firestore), profile: PROFILE,
  });
  await applyCatalogImport({
    firestore, plan: resumedPlan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: resumedPlan.run_id, planChecksum: resumedPlan.plan_checksum,
    }),
    checkpointBatchSize: 2,
    chunkPauseMs: 0,
  });

  const finalProducts = firestore.documents("products").map((product) => product.id).sort();
  assert.deepEqual(finalProducts, expectedIds);
  assert.equal(firestore.documents("product_unique_keys").length, 6);
  assert.equal(firestore.documents("catalog_import_manifests").length, 1);
});

test("bounded chunk transactions materially reduce request attempts without exceeding writes", async () => {
  const firestore = new FakeFirestore(seed());
  const plan = buildCatalogImportPlan({
    preview: previewWithProducts(100), context: await context(firestore), profile: PROFILE,
  });
  await applyCatalogImport({
    firestore, plan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
    }),
    checkpointBatchSize: 25,
    chunkPauseMs: 0,
  });

  assert.equal(firestore.documents("products").length, 100);
  assert.equal(firestore.transactionCalls, 7);
  assert.equal(firestore.maxTransactionWrites, 101);
  assert.equal(firestore.transactionReadBatches.length, 6);
  assert.equal(firestore.getAllCalls, 1);
  assert.equal(firestore.documents(`catalog_import_run_state/${plan.run_id}/chunks`).length, 5);
  assert.equal(firestore.documents("catalog_import_manifests").length, 1);
});

test("the Eqlid-sized 2131-product schedule is serial, complete, and bounded", async () => {
  const firestore = new FakeFirestore(seed());
  const plan = buildCatalogImportPlan({
    preview: previewWithProducts(2131), context: await context(firestore), profile: PROFILE,
  });
  const expectedIds = plan.productOperations.map((entry) => entry.product.id).sort();
  await applyCatalogImport({
    firestore, plan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
    }),
    checkpointBatchSize: 25,
    chunkPauseMs: 0,
  });

  const finalProducts = firestore.documents("products").map((product) => product.id).sort();
  assert.deepEqual(finalProducts, expectedIds);
  assert.equal(new Set(finalProducts).size, 2131);
  assert.equal(firestore.transactionCalls, 89);
  assert.equal(firestore.maxTransactionWrites, 101);
  assert.equal(firestore.documents(`catalog_import_run_state/${plan.run_id}/chunks`).length, 87);
  const manifest = firestore.documents("catalog_import_manifests")[0];
  assert.equal(manifest.applied_counts.products, 2131);
});

test("checkpoint capacity is bounded and the expected Eqlid scale fits safely", () => {
  const eqlidProductIds = Array.from({length: 2131}, (_, index) =>
    `product-${String(index).padStart(4, "0")}-${"x".repeat(43)}`);
  const eqlidBytes = checkpointStateBytes({
    groupIds: Array.from({length: 23}, (_, index) => `group-${index}`),
    productIds: eqlidProductIds,
  });
  assert.ok(eqlidBytes < MAX_CHECKPOINT_STATE_BYTES);
  assert.equal(CHECKPOINT_BATCH_SIZE, 25);

  const oversizedPlan = {
    groupOperations: {create: [], unchanged: []},
    productOperations: Array.from({length: 12000}, (_, index) => ({
      action: "create", product: {id: `product-${index}-${"x".repeat(64)}`},
    })),
  };
  assert.throws(() => assertCheckpointStateCapacity(oversizedPlan), (error) =>
    error.code === "run-state-capacity-exceeded");
});

for (const [label, reviewRows, groupConflicts] of [
  ["mixed review reasons", [
    {source_row: 8, reason: "source-validation-required"},
    {source_row: 9, reason: "existing-product-preserved-for-accountant-review"},
  ], []],
  ["unknown review reason", [
    {source_row: 8, reason: "unexpected-future-review-reason"},
  ], []],
  ["group conflict", [], [{group_id: "group-fixture"}]],
]) {
  test(`${label} still blocks catalog import`, async () => {
    const firestore = new FakeFirestore(seed());
    const plan = buildCatalogImportPlan({
      preview: preview(), context: await context(firestore), profile: PROFILE,
    });
    plan.review_rows = reviewRows;
    plan.group_conflicts = groupConflicts;
    await assert.rejects(() => applyCatalogImport({
      firestore, plan, projectId: PROJECT,
      confirmation: expectedConfirmation({
        projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
      }),
    }), (error) => error.code === "unresolved-catalog-review-blocks-apply");
    assert.equal(firestore.documents("products").length, 0);
    assert.equal(firestore.documents("catalog_import_manifests").length, 0);
  });
}

test("rollback archives only unchanged and unreferenced import records", async () => {
  const firestore = new FakeFirestore(seed());
  const plan = buildCatalogImportPlan({
    preview: preview(), context: await context(firestore), profile: PROFILE,
  });
  await applyCatalogImport({
    firestore, plan, projectId: PROJECT,
    confirmation: expectedConfirmation({
      projectId: PROJECT, runId: plan.run_id, planChecksum: plan.plan_checksum,
    }),
  });
  let rollback = await buildRollbackPlan({
    firestore, runId: plan.run_id, referenceCheck: async () => [],
  });
  assert.equal(rollback.archive_product_ids.length, 1);
  assert.equal(rollback.archive_group_ids.length, 1);
  const confirmation = expectedRollbackConfirmation({
    projectId: PROJECT, runId: plan.run_id, planChecksum: rollback.plan_checksum,
  });
  await applyRollback({
    firestore, plan: rollback, projectId: PROJECT, confirmation,
    actor: (await context(firestore)).actor, referenceCheck: async () => [],
  });
  assert.equal(firestore.documents("products")[0].active, false);
  assert.equal(firestore.documents("product_groups")[0].active, false);
  assert.equal(firestore.documents("product_unique_keys")[0].active, false);

  rollback = await buildRollbackPlan({
    firestore, runId: plan.run_id, referenceCheck: async () => ["invoice/ref"],
  });
  assert.equal(rollback.archive_product_ids.length, 0);
});
