"use strict";

const crypto = require("node:crypto");
const path = require("node:path");
const {spawnSync} = require("node:child_process");

const COLLECTIONS = Object.freeze({
  brands: "brands",
  users: "users",
  groups: "product_groups",
  products: "products",
  uniqueKeys: "product_unique_keys",
  audits: "product_audit_events",
  manifests: "catalog_import_manifests",
  runState: "catalog_import_run_state",
  rollbackManifests: "catalog_import_rollback_manifests",
});

const PROFILES = Object.freeze({
  al_asalah_legacy_catalog: Object.freeze({
    brandId: "TlOswncJiWX7mwsf3U4e",
    brandName: "الأصالة",
  }),
  eqlid_legacy_catalog: Object.freeze({
    brandId: "WLMnMVT6u1H2VQ0qziJ3",
    brandName: "اقليد",
  }),
});

const UNCATEGORIZED_NAME = "غير مصنف";
const UNCATEGORIZED_KEY = "uncategorized";

function checksum(value) {
  return crypto.createHash("sha256").update(stableJson(value)).digest("hex");
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function normalizeCatalogText(value) {
  return String(value || "").trim().toLowerCase()
      .replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/gu, "")
      .replace(/\u0640/gu, "")
      .replace(/[\u0622\u0623\u0625\u0671]/gu, "\u0627")
      .replace(/\u0649/gu, "\u064A")
      .replace(/\s+/gu, " ");
}

function normalizeLegacyCode(value) {
  return String(value || "").trim().toUpperCase().replace(/\s+/gu, "");
}

function keyFragment(value) {
  return Buffer.from(value, "utf8").toString("base64url");
}

function uniqueKeyId(brandId, keyType, normalizedValue) {
  return `${keyFragment(brandId)}-${keyType}-${keyFragment(normalizedValue)}`;
}

function deterministicId(prefix, ...parts) {
  return `${prefix}-${checksum(parts).slice(0, 40)}`;
}

function expectedConfirmation({projectId, runId, planChecksum}) {
  return `APPLY_CATALOG_IMPORT:${projectId}:${runId}:${planChecksum}`;
}

function expectedRollbackConfirmation({projectId, runId, planChecksum}) {
  return `ROLLBACK_CATALOG_IMPORT:${projectId}:${runId}:${planChecksum}`;
}

function validateProfileContract({profile, brandId, brandName}) {
  const contract = PROFILES[profile];
  if (!contract) throw codedError("unsupported-profile");
  if (brandId !== contract.brandId) throw codedError("brand-id-mismatch");
  if (String(brandName || "").trim() !== contract.brandName) {
    throw codedError("brand-name-mismatch");
  }
  return contract;
}

async function readProductionContext({firestore, profile, brandId, brandName, actorUid}) {
  const contract = validateProfileContract({profile, brandId, brandName});
  const [brand, actor, groups, products, uniqueKeys, manifests] = await Promise.all([
    firestore.collection(COLLECTIONS.brands).doc(brandId).get(),
    firestore.collection(COLLECTIONS.users).doc(actorUid).get(),
    firestore.collection(COLLECTIONS.groups).where("brand_id", "==", brandId).get(),
    firestore.collection(COLLECTIONS.products).where("brand_id", "==", brandId).get(),
    firestore.collection(COLLECTIONS.uniqueKeys).where("brand_id", "==", brandId).get(),
    firestore.collection(COLLECTIONS.manifests).where("brand_id", "==", brandId).get(),
  ]);
  if (!brand.exists) throw codedError("brand-not-found");
  const liveBrandName = String(brand.data()?.name || "").trim();
  if (liveBrandName !== contract.brandName) throw codedError("live-brand-name-mismatch");
  if (!actor.exists) throw codedError("actor-not-found");
  const actorData = actor.data() || {};
  if (actorData.role !== "accountant" || actorData.isActive === false ||
      actorData.mustChangePassword === true) {
    throw codedError("active-accountant-required");
  }
  return {
    brand: {id: brandId, name: liveBrandName},
    actor: {
      uid: actorUid,
      name: String(actorData.name || actorData.displayName || actorUid),
      role: "accountant",
    },
    groups: snapshotsToMap(groups),
    products: snapshotsToMap(products),
    uniqueKeys: snapshotsToMap(uniqueKeys),
    manifests: snapshotsToMap(manifests),
  };
}

function snapshotsToMap(snapshot) {
  return new Map((snapshot?.docs || []).map((document) => [
    document.id,
    clone(document.data()),
  ]));
}

function runLegacyPreview({profile, sourceFile, brandId, brandName, repoRoot}) {
  const command = process.platform === "win32" ? "dart.exe" : "dart";
  const result = spawnSync(command, [
    "run", "tool/legacy_catalog_dry_run.dart",
    "--profile", profile,
    "--file", path.resolve(sourceFile),
    "--brand-id", brandId,
    "--brand-name", brandName,
    "--details",
  ], {
    cwd: repoRoot || path.resolve(__dirname, ".."),
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    windowsHide: true,
  });
  if (result.status !== 0) {
    const message = String(result.stderr || "legacy preview failed").trim();
    throw codedError("legacy-preview-failed", message);
  }
  return JSON.parse(result.stdout);
}

function buildCatalogImportPlan({preview, context, profile}) {
  if (!preview?.dry_run || preview?.writes_performed !== false ||
      preview?.prices_parsed !== false) throw codedError("invalid-preview-contract");
  validateProfileContract({
    profile,
    brandId: context.brand.id,
    brandName: context.brand.name,
  });
  const source = preview.source || {};
  if (!/^[a-f0-9]{64}$/i.test(String(source.sha256 || ""))) {
    throw codedError("invalid-source-hash");
  }
  const runId = deterministicId(
      "catalog-import", profile, context.brand.id, source.sha256,
  );
  const groups = classifyGroups({preview, context, runId});
  const blockedGroupIds = new Set(groups.conflicts.map((entry) => entry.group_id));
  const candidates = [
    ...(preview.creates || []),
    ...(preview.updates || []),
    ...(preview.unchanged || []),
  ];
  const products = [];
  const reviews = [];
  for (const entry of candidates) {
    const record = entry.record || {};
    if (!record.product_name || !record.raw_units?.primary || !record.fingerprint) {
      reviews.push(reviewEntry(record, "invalid-ready-record"));
      continue;
    }
    const groupId = entry.assigned_group_id;
    if (!groupId || blockedGroupIds.has(groupId)) {
      reviews.push(reviewEntry(record, "group-conflict"));
      continue;
    }
    const product = plannedProduct({entry, context, runId});
    const classification = classifyProduct({product, context, runId});
    if (classification.action === "review") reviews.push(classification.review);
    else products.push({...product, action: classification.action});
  }
  for (const record of preview.blocked_other || []) {
    reviews.push(reviewEntry(record, "source-validation-required"));
  }
  for (const duplicate of preview.duplicates || []) {
    for (const row of duplicate.source_rows || []) {
      reviews.push({source_row: row, reason: "source-duplicate"});
    }
  }
  const skippedRows = (preview.skipped_rows || []).map((entry) => ({
    source_row: entry.source_row,
    reason: entry.reason,
  }));
  const core = {
    schema_version: 1,
    run_id: runId,
    profile,
    brand_id: context.brand.id,
    brand_name: context.brand.name,
    source_sha256: source.sha256,
    source_sheet: source.worksheet,
    source_row_count: source.source_rows,
    desired_group_ids: [...groups.create, ...groups.unchanged]
        .map((entry) => entry.group_id).sort(),
    group_conflicts: groups.conflicts,
    desired_product_ids: products.map((entry) => entry.product.id).sort(),
    review_rows: deduplicateRows(reviews),
    skipped_rows: deduplicateRows(skippedRows),
  };
  const planChecksum = checksum(core);
  return {
    ...core,
    groups_to_create: groups.create.map((entry) => entry.group_id),
    groups_unchanged: groups.unchanged.map((entry) => entry.group_id),
    products_to_create: products.filter((entry) => entry.action === "create")
        .map((entry) => entry.product.id),
    products_unchanged: products.filter((entry) => entry.action === "unchanged")
        .map((entry) => entry.product.id),
    plan_checksum: planChecksum,
    confirmation: expectedConfirmation({
      projectId: "<PROJECT_ID>", runId, planChecksum,
    }),
    actor: context.actor,
    groupOperations: groups,
    productOperations: products,
    prior_manifest_present: context.manifests.has(runId),
    counts: {
      groups_create: groups.create.length,
      groups_unchanged: groups.unchanged.length,
      group_conflicts: groups.conflicts.length,
      products_create: products.filter((entry) => entry.action === "create").length,
      products_unchanged: products.filter((entry) => entry.action === "unchanged").length,
      review_rows: core.review_rows.length,
      skipped_rows: core.skipped_rows.length,
    },
  };
}

function classifyGroups({preview, context, runId}) {
  const requested = [];
  for (const group of preview.normal_group_plans || []) {
    requested.push({
      group_id: group.group_id,
      name: group.name,
      normalized_name: group.normalized_name,
      legacy_code: singleLegacyCode(group.source_legacy_codes),
      is_system_group: false,
    });
  }
  for (const group of preview.system_group_plans || []) {
    requested.push({
      group_id: group.group_id,
      name: UNCATEGORIZED_NAME,
      normalized_name: normalizeCatalogText(UNCATEGORIZED_NAME),
      is_system_group: true,
      system_key: UNCATEGORIZED_KEY,
    });
  }
  const create = [];
  const unchanged = [];
  const conflicts = [];
  for (const group of requested.sort((a, b) => a.group_id.localeCompare(b.group_id))) {
    const existing = context.groups.get(group.group_id);
    if (!existing) {
      create.push({...group, audit_id: deterministicId("audit", runId, "group", group.group_id)});
    } else if (groupMatches(existing, group, context.brand.id)) {
      unchanged.push(group);
    } else {
      conflicts.push({group_id: group.group_id, reason: "existing-group-differs"});
    }
  }
  return {create, unchanged, conflicts};
}

function groupMatches(existing, planned, brandId) {
  return existing.id === planned.group_id && existing.brand_id === brandId &&
    existing.name === planned.name &&
    existing.normalized_name === planned.normalized_name &&
    existing.active === true && existing.is_system_group === planned.is_system_group &&
    String(existing.system_key || "") === String(planned.system_key || "") &&
    normalizeLegacyCode(existing.legacy_code) === normalizeLegacyCode(planned.legacy_code);
}

function plannedProduct({entry, context, runId}) {
  const record = entry.record;
  const normalizedName = normalizeCatalogText(record.product_name);
  const normalizedCode = normalizeLegacyCode(record.legacy_code);
  const nameKeyId = uniqueKeyId(context.brand.id, "name", normalizedName);
  const codeKeyId = normalizedCode ?
    uniqueKeyId(context.brand.id, "legacy_code", normalizedCode) : undefined;
  const productId = deterministicId(
      "import-product", context.brand.id, record.fingerprint,
  );
  const auditId = deterministicId("audit", runId, "product", productId);
  const units = [
    ["primary", record.raw_units.primary],
    ["unit_2", record.raw_units.unit_2],
    ["unit_3", record.raw_units.unit_3],
  ].filter(([, value]) => String(value || "").trim()).map(([unitId, value]) => ({
    unit_id: unitId,
    display_value: String(value).trim(),
    raw_value: String(value),
  }));
  const sourceMetadata = {
    source_profile: record.source_profile,
    source_file_sha256: record.source_hash,
    source_sheet: record.source_sheet,
    source_row: record.source_row,
    raw_material_value: record.raw_material_value,
    raw_group_value: record.raw_group_value,
    raw_primary_unit: record.raw_units.primary,
    raw_unit_2: record.raw_units.unit_2 || "",
    raw_unit_3: record.raw_units.unit_3 || "",
    source_fingerprint: record.fingerprint,
    import_id: runId,
    original_group_missing: record.group_resolution?.original_group_missing === true,
    fallback_system_group_assigned:
      record.group_resolution?.fallback_system_group_assigned === true,
  };
  if (sourceMetadata.fallback_system_group_assigned) {
    sourceMetadata.fallback_system_group_key = UNCATEGORIZED_KEY;
    sourceMetadata.fallback_system_group_id =
      `system-group-${context.brand.id}-${UNCATEGORIZED_KEY}`;
  }
  const product = compact({
    id: productId,
    brand_id: context.brand.id,
    group_id: entry.assigned_group_id,
    name: record.product_name,
    normalized_name: normalizedName,
    legacy_code: record.legacy_code || undefined,
    units,
    primary_unit_id: "primary",
    active: true,
    version: 1,
    name_unique_key_id: nameKeyId,
    legacy_code_unique_key_id: codeKeyId,
    source_metadata: sourceMetadata,
    last_audit_event_id: auditId,
  });
  assertNoPriceFields(product);
  return {product, auditId, nameKeyId, codeKeyId, sourceRow: record.source_row};
}

function classifyProduct({product, context, runId}) {
  const {nameKeyId, codeKeyId} = product;
  const nameKey = context.uniqueKeys.get(nameKeyId);
  const codeKey = codeKeyId ? context.uniqueKeys.get(codeKeyId) : undefined;
  const ids = new Set([nameKey?.product_id, codeKey?.product_id].filter(Boolean));
  if (ids.size > 1) {
    return {action: "review", review: {
      source_row: product.sourceRow, reason: "unique-keys-point-to-different-products",
    }};
  }
  const keyedId = [...ids][0];
  const deterministicExisting = context.products.get(product.product.id);
  const keyedExisting = keyedId ? context.products.get(keyedId) : undefined;
  if (keyedId && !keyedExisting) {
    return {action: "review", review: {
      source_row: product.sourceRow, reason: "orphaned-unique-key",
    }};
  }
  const existing = keyedExisting || deterministicExisting;
  if (!existing) return {action: "create"};
  const metadata = existing.source_metadata || {};
  const exactImported = existing.id === product.product.id &&
    metadata.import_id === runId &&
    metadata.source_fingerprint === product.product.source_metadata.source_fingerprint &&
    checksum(withoutMutableCatalogFields(existing)) ===
      checksum(withoutMutableCatalogFields(product.product));
  if (!exactImported) {
    return {action: "review", review: {
      source_row: product.sourceRow,
      reason: "existing-product-preserved-for-accountant-review",
    }};
  }
  if ((nameKey && nameKey.product_id !== existing.id) ||
      (codeKey && codeKey.product_id !== existing.id)) {
    return {action: "review", review: {
      source_row: product.sourceRow, reason: "unique-key-conflict",
    }};
  }
  return {action: "unchanged"};
}

function withoutMutableCatalogFields(value) {
  const copy = clone(value);
  for (const key of [
    "created_by", "created_by_name", "created_at", "updated_by",
    "updated_by_name", "updated_at",
  ]) delete copy[key];
  return copy;
}

async function applyCatalogImport({firestore, plan, projectId, confirmation, clock = () => new Date()}) {
  if (!projectId) throw codedError("project-id-required");
  const required = expectedConfirmation({
    projectId, runId: plan.run_id, planChecksum: plan.plan_checksum,
  });
  if (confirmation !== required) throw codedError("apply-confirmation-mismatch");
  if (plan.group_conflicts.length || plan.review_rows.length) {
    throw codedError("unresolved-catalog-review-blocks-apply");
  }
  const stateRef = firestore.collection(COLLECTIONS.runState).doc(plan.run_id);
  await firestore.runTransaction(async (transaction) => {
    const state = await transaction.get(stateRef);
    const current = state.data();
    if (current && current.plan_checksum !== plan.plan_checksum) {
      throw codedError("run-state-plan-conflict");
    }
    transaction.set(stateRef, {
      schema_version: 1,
      run_id: plan.run_id,
      plan_checksum: plan.plan_checksum,
      status: "applying",
      brand_id: plan.brand_id,
      source_sha256: plan.source_sha256,
      actor_uid: plan.actor.uid,
      started_at: current?.started_at || clock(),
      updated_at: clock(),
      completed_group_ids: current?.completed_group_ids || [],
      completed_product_ids: current?.completed_product_ids || [],
    });
  });

  for (const group of plan.groupOperations.create) {
    await ensureGroup({firestore, plan, group, clock});
    await checkpoint({firestore, plan, clock, field: "completed_group_ids", id: group.group_id});
  }
  for (const entry of plan.productOperations.filter((item) =>
    item.action === "create" || item.action === "unchanged")) {
    await ensureProduct({firestore, plan, entry, clock});
    await checkpoint({firestore, plan, clock, field: "completed_product_ids", id: entry.product.id});
  }
  const completedAt = clock();
  const manifestRef = firestore.collection(COLLECTIONS.manifests).doc(plan.run_id);
  await firestore.runTransaction(async (transaction) => {
    const [manifest, state] = await Promise.all([
      transaction.get(manifestRef), transaction.get(stateRef),
    ]);
    const existing = manifest.data();
    const immutableManifest = manifestData(plan, state.data(), completedAt);
    if (existing && (existing.plan_checksum !== plan.plan_checksum ||
        existing.source_sha256 !== plan.source_sha256 ||
        existing.brand_id !== plan.brand_id)) {
      throw codedError("immutable-manifest-conflict");
    }
    if (!existing) transaction.set(manifestRef, immutableManifest);
    transaction.set(stateRef, {
      ...state.data(), status: "completed", updated_at: completedAt,
      completed_at: existing?.completed_at || completedAt,
    });
  });
  return {run_id: plan.run_id, status: "completed", counts: plan.counts};
}

async function ensureGroup({firestore, plan, group, clock}) {
  const groupRef = firestore.collection(COLLECTIONS.groups).doc(group.group_id);
  const auditRef = firestore.collection(COLLECTIONS.audits).doc(group.audit_id);
  await firestore.runTransaction(async (transaction) => {
    const [existingGroup, existingAudit] = await Promise.all([
      transaction.get(groupRef), transaction.get(auditRef),
    ]);
    if (existingGroup.exists) {
      if (!groupMatches(existingGroup.data(), group, plan.brand_id)) {
        throw codedError("group-changed-after-plan");
      }
      return;
    }
    if (existingAudit.exists) throw codedError("orphaned-group-audit");
    const now = clock();
    const groupData = compact({
      id: group.group_id,
      brand_id: plan.brand_id,
      name: group.name,
      normalized_name: group.normalized_name,
      legacy_code: group.legacy_code,
      is_system_group: group.is_system_group,
      system_key: group.system_key,
      active: true,
      created_by: plan.actor.uid,
      created_by_name: plan.actor.name,
      created_at: now,
      updated_by: plan.actor.uid,
      updated_by_name: plan.actor.name,
      updated_at: now,
      last_audit_event_id: group.audit_id,
    });
    transaction.set(groupRef, groupData);
    transaction.set(auditRef, auditData({
      id: group.audit_id,
      entityType: "product_group",
      entityId: group.group_id,
      brandId: plan.brand_id,
      action: group.is_system_group ? "system_group_created" : "created",
      after: groupData,
      actor: plan.actor,
      createdAt: now,
      reason: `catalog_import:${plan.run_id}`,
    }));
  });
}

async function ensureProduct({firestore, plan, entry, clock}) {
  const product = entry.product;
  const productRef = firestore.collection(COLLECTIONS.products).doc(product.id);
  const auditRef = firestore.collection(COLLECTIONS.audits).doc(entry.auditId);
  const nameKeyRef = firestore.collection(COLLECTIONS.uniqueKeys).doc(entry.nameKeyId);
  const codeKeyRef = entry.codeKeyId ?
    firestore.collection(COLLECTIONS.uniqueKeys).doc(entry.codeKeyId) : undefined;
  await firestore.runTransaction(async (transaction) => {
    const [brand, group, existingProduct, audit, nameKey, codeKey] = await Promise.all([
      transaction.get(firestore.collection(COLLECTIONS.brands).doc(plan.brand_id)),
      transaction.get(firestore.collection(COLLECTIONS.groups).doc(product.group_id)),
      transaction.get(productRef), transaction.get(auditRef),
      transaction.get(nameKeyRef),
      codeKeyRef ? transaction.get(codeKeyRef) : Promise.resolve(undefined),
    ]);
    if (!brand.exists || brand.data()?.name !== plan.brand_name) {
      throw codedError("brand-changed-after-plan");
    }
    if (!group.exists || group.data()?.brand_id !== plan.brand_id ||
        group.data()?.active !== true) throw codedError("product-group-not-ready");
    if (existingProduct.exists) {
      const current = existingProduct.data();
      if (current?.source_metadata?.import_id !== plan.run_id ||
          current?.source_metadata?.source_fingerprint !==
            product.source_metadata.source_fingerprint) {
        throw codedError("product-changed-after-plan");
      }
    } else {
      if (audit.exists) throw codedError("orphaned-product-audit");
      const now = clock();
      const productData = {
        ...product,
        created_by: plan.actor.uid,
        created_by_name: plan.actor.name,
        created_at: now,
        updated_by: plan.actor.uid,
        updated_by_name: plan.actor.name,
        updated_at: now,
      };
      assertNoPriceFields(productData);
      transaction.set(productRef, productData);
      transaction.set(auditRef, auditData({
        id: entry.auditId, entityType: "product", entityId: product.id,
        brandId: plan.brand_id, action: "created", after: productData,
        actor: plan.actor, createdAt: now,
        reason: `catalog_import:${plan.run_id}`,
      }));
    }
    ensureUniqueKeyWrite({
      transaction, snapshot: nameKey, reference: nameKeyRef,
      id: entry.nameKeyId, keyType: "name",
      normalizedValue: product.normalized_name, productId: product.id,
      plan, clock,
    });
    if (codeKeyRef) {
      ensureUniqueKeyWrite({
        transaction, snapshot: codeKey, reference: codeKeyRef,
        id: entry.codeKeyId, keyType: "legacy_code",
        normalizedValue: normalizeLegacyCode(product.legacy_code),
        productId: product.id, plan, clock,
      });
    }
  });
}

function ensureUniqueKeyWrite({transaction, snapshot, reference, id, keyType,
  normalizedValue, productId, plan, clock}) {
  if (snapshot?.exists) {
    const current = snapshot.data();
    if (current.product_id !== productId || current.brand_id !== plan.brand_id ||
        current.key_type !== keyType || current.normalized_value !== normalizedValue) {
      throw codedError("unique-key-changed-after-plan");
    }
    return;
  }
  const now = clock();
  transaction.set(reference, {
    id, brand_id: plan.brand_id, key_type: keyType,
    normalized_value: normalizedValue, product_id: productId, active: true,
    created_by: plan.actor.uid, created_at: now,
    updated_by: plan.actor.uid, updated_at: now,
  });
}

async function checkpoint({firestore, plan, clock, field, id}) {
  const reference = firestore.collection(COLLECTIONS.runState).doc(plan.run_id);
  await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists || snapshot.data()?.plan_checksum !== plan.plan_checksum) {
      throw codedError("run-state-missing");
    }
    const completed = new Set(snapshot.data()[field] || []);
    completed.add(id);
    transaction.set(reference, {
      ...snapshot.data(), [field]: [...completed].sort(), updated_at: clock(),
    });
  });
}

function manifestData(plan, runState, completedAt) {
  return {
    schema_version: 1,
    id: plan.run_id,
    run_id: plan.run_id,
    status: "completed",
    plan_checksum: plan.plan_checksum,
    source_sha256: plan.source_sha256,
    source_profile: plan.profile,
    source_sheet: plan.source_sheet,
    source_row_count: plan.source_row_count,
    brand_id: plan.brand_id,
    brand_name: plan.brand_name,
    actor_uid: plan.actor.uid,
    actor_name: plan.actor.name,
    planned_counts: clone(plan.counts),
    applied_counts: {
      groups: (runState?.completed_group_ids || []).length,
      products: (runState?.completed_product_ids || []).length,
    },
    created_group_ids: [...plan.groups_to_create],
    created_product_ids: [...plan.products_to_create],
    skipped_rows: clone(plan.skipped_rows),
    review_rows: clone(plan.review_rows),
    started_at: runState?.started_at,
    completed_at: completedAt,
  };
}

async function buildRollbackPlan({firestore, runId, referenceCheck = defaultReferenceCheck}) {
  const manifestSnapshot = await firestore.collection(COLLECTIONS.manifests).doc(runId).get();
  if (!manifestSnapshot.exists) throw codedError("import-manifest-not-found");
  const manifest = manifestSnapshot.data();
  const candidates = [];
  const blocked = [];
  for (const productId of manifest.created_product_ids || []) {
    const snapshot = await firestore.collection(COLLECTIONS.products).doc(productId).get();
    const product = snapshot.data();
    if (!snapshot.exists || product.active === false) continue;
    const expectedAudit = deterministicId("audit", runId, "product", productId);
    const unchanged = product.version === 1 && product.last_audit_event_id === expectedAudit &&
      product.source_metadata?.import_id === runId;
    const references = unchanged ? await referenceCheck(firestore, productId) : ["manual_change"];
    if (unchanged && references.length === 0) candidates.push(productId);
    else blocked.push({product_id: productId, reason: unchanged ? "referenced" : "modified"});
  }
  const candidateSet = new Set(candidates);
  const groupCandidates = [];
  const blockedGroups = [];
  for (const groupId of manifest.created_group_ids || []) {
    if (groupId === `system-group-${manifest.brand_id}-${UNCATEGORIZED_KEY}`) continue;
    const groupSnapshot = await firestore.collection(COLLECTIONS.groups).doc(groupId).get();
    const group = groupSnapshot.data();
    if (!groupSnapshot.exists || group.active === false) continue;
    const expectedAudit = deterministicId("audit", runId, "group", groupId);
    const activeProducts = await firestore.collection(COLLECTIONS.products)
        .where("group_id", "==", groupId).get();
    const foreignProduct = activeProducts.docs.some((document) =>
      document.data()?.active === true && !candidateSet.has(document.id));
    if (group.last_audit_event_id === expectedAudit && !foreignProduct) {
      groupCandidates.push(groupId);
    } else {
      blockedGroups.push({group_id: groupId, reason: foreignProduct ?
        "group-has-retained-products" : "group-modified"});
    }
  }
  const core = {
    schema_version: 1, run_id: runId, import_plan_checksum: manifest.plan_checksum,
    archive_product_ids: candidates.sort(), blocked: blocked.sort((a, b) =>
      a.product_id.localeCompare(b.product_id)),
    archive_group_ids: groupCandidates.sort(),
    blocked_groups: blockedGroups.sort((a, b) => a.group_id.localeCompare(b.group_id)),
  };
  return {...core, plan_checksum: checksum(core), manifest};
}

async function applyRollback({firestore, plan, projectId, confirmation,
  actor, clock = () => new Date(), referenceCheck = defaultReferenceCheck}) {
  const required = expectedRollbackConfirmation({
    projectId, runId: plan.run_id, planChecksum: plan.plan_checksum,
  });
  if (confirmation !== required) throw codedError("rollback-confirmation-mismatch");
  if (plan.blocked.length || plan.blocked_groups.length) {
    throw codedError("unsafe-rollback-blocked");
  }
  for (const productId of plan.archive_product_ids) {
    if ((await referenceCheck(firestore, productId)).length) {
      throw codedError("product-became-referenced");
    }
    const productRef = firestore.collection(COLLECTIONS.products).doc(productId);
    await firestore.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(productRef);
      const current = currentSnapshot.data();
      const createAudit = deterministicId("audit", plan.run_id, "product", productId);
      if (!currentSnapshot.exists || current.active === false) return;
      if (current.version !== 1 || current.last_audit_event_id !== createAudit ||
          current.source_metadata?.import_id !== plan.run_id) {
        throw codedError("rollback-product-changed");
      }
      const now = clock();
      const rollbackAuditId = deterministicId("audit", plan.run_id, "rollback", productId);
      const after = {
        ...current, active: false, version: 2,
        updated_by: actor.uid, updated_by_name: actor.name, updated_at: now,
        archived_by: actor.uid, archived_by_name: actor.name, archived_at: now,
        last_audit_event_id: rollbackAuditId,
      };
      transaction.set(productRef, after);
      for (const keyId of [current.name_unique_key_id, current.legacy_code_unique_key_id].filter(Boolean)) {
        const keyRef = firestore.collection(COLLECTIONS.uniqueKeys).doc(keyId);
        const key = await transaction.get(keyRef);
        if (!key.exists || key.data()?.product_id !== productId) {
          throw codedError("rollback-unique-key-conflict");
        }
        transaction.set(keyRef, {...key.data(), active: false, updated_by: actor.uid, updated_at: now});
      }
      transaction.set(firestore.collection(COLLECTIONS.audits).doc(rollbackAuditId),
          auditData({
            id: rollbackAuditId, entityType: "product", entityId: productId,
            brandId: current.brand_id, action: "archived", before: current,
            after, actor, createdAt: now, reason: `rollback_catalog_import:${plan.run_id}`,
          }));
    });
  }
  for (const groupId of plan.archive_group_ids) {
    const groupRef = firestore.collection(COLLECTIONS.groups).doc(groupId);
    await firestore.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(groupRef);
      const current = currentSnapshot.data();
      if (!currentSnapshot.exists || current.active === false) return;
      const expectedAudit = deterministicId("audit", plan.run_id, "group", groupId);
      if (current.last_audit_event_id !== expectedAudit || current.is_system_group === true) {
        throw codedError("rollback-group-changed");
      }
      const activeProducts = await transaction.get(
          firestore.collection(COLLECTIONS.products)
              .where("group_id", "==", groupId),
      );
      if (activeProducts.docs.some((document) => document.data()?.active === true)) {
        throw codedError("rollback-group-not-empty");
      }
      const now = clock();
      const rollbackAuditId = deterministicId("audit", plan.run_id, "rollback-group", groupId);
      const after = {
        ...current, active: false, updated_by: actor.uid,
        updated_by_name: actor.name, updated_at: now,
        archived_by: actor.uid, archived_by_name: actor.name, archived_at: now,
        last_audit_event_id: rollbackAuditId,
      };
      transaction.set(groupRef, after);
      transaction.set(firestore.collection(COLLECTIONS.audits).doc(rollbackAuditId),
          auditData({
            id: rollbackAuditId, entityType: "product_group", entityId: groupId,
            brandId: current.brand_id, action: "archived", before: current,
            after, actor, createdAt: now, reason: `rollback_catalog_import:${plan.run_id}`,
          }));
    });
  }
  const rollbackId = deterministicId("catalog-rollback", plan.run_id, plan.plan_checksum);
  const rollbackRef = firestore.collection(COLLECTIONS.rollbackManifests).doc(rollbackId);
  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(rollbackRef);
    const data = {
      schema_version: 1, id: rollbackId, run_id: plan.run_id,
      plan_checksum: plan.plan_checksum, archived_product_ids: plan.archive_product_ids,
      archived_group_ids: plan.archive_group_ids,
      actor_uid: actor.uid, actor_name: actor.name, completed_at: clock(),
    };
    if (existing.exists && (existing.data()?.plan_checksum !== plan.plan_checksum ||
        existing.data()?.run_id !== plan.run_id)) {
      throw codedError("rollback-manifest-conflict");
    }
    if (!existing.exists) transaction.set(rollbackRef, data);
  });
  return {
    run_id: plan.run_id,
    archived_products: plan.archive_product_ids.length,
    archived_groups: plan.archive_group_ids.length,
  };
}

async function defaultReferenceCheck(firestore, productId) {
  const checks = [
    firestore.collectionGroup("items").where("product_id", "==", productId).get(),
    firestore.collectionGroup("items").where("canonical_product_id", "==", productId).get(),
    firestore.collection("product_review_tasks").where("product_id", "==", productId).get(),
  ];
  const snapshots = await Promise.all(checks);
  return snapshots.flatMap((snapshot) => snapshot.docs.map((document) => document.ref.path));
}

function auditData({id, entityType, entityId, brandId, action, before, after,
  actor, createdAt, reason}) {
  return compact({
    id, entity_type: entityType, entity_id: entityId, brand_id: brandId,
    action, before, after, reason, actor_uid: actor.uid, actor_name: actor.name,
    actor_role: actor.role, created_at: createdAt,
  });
}

function assertNoPriceFields(value, currentPath = []) {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (/(price|cost|amount|currency|سعر)/iu.test(key)) {
      throw codedError("catalog-price-field-forbidden", [...currentPath, key].join("."));
    }
    assertNoPriceFields(child, [...currentPath, key]);
  }
}

function reviewEntry(record, reason) {
  return {source_row: record?.source_row, reason};
}

function deduplicateRows(entries) {
  const values = new Map();
  for (const entry of entries) {
    const clean = {source_row: entry.source_row, reason: entry.reason};
    values.set(`${clean.source_row}:${clean.reason}`, clean);
  }
  return [...values.values()].sort((a, b) =>
    Number(a.source_row || 0) - Number(b.source_row || 0) ||
      a.reason.localeCompare(b.reason));
}

function singleLegacyCode(values) {
  const normalized = [...new Set((values || []).map(normalizeLegacyCode).filter(Boolean))];
  return normalized.length === 1 ? normalized[0] : undefined;
}

function compact(value) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

function codedError(code, detail) {
  return Object.assign(new Error(detail ? `${code}: ${detail}` : code), {code});
}

function parseArguments(arguments_) {
  const options = {};
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--apply") {
      options.apply = true;
      continue;
    }
    if (!argument.startsWith("--") || index + 1 >= arguments_.length) {
      throw codedError("invalid-command-line");
    }
    options[argument.slice(2)] = arguments_[++index];
  }
  return options;
}

async function createAdminFirestore(projectId) {
  const admin = require("firebase-admin");
  if (admin.apps.length === 0) {
    admin.initializeApp({credential: admin.credential.applicationDefault(), projectId});
  }
  return admin.firestore();
}

async function main(arguments_ = process.argv.slice(2)) {
  const options = parseArguments(arguments_);
  for (const name of ["actor-uid", "project-id"]) {
    if (!String(options[name] || "").trim()) throw codedError(`missing-${name}`);
  }
  const firestore = await createAdminFirestore(options["project-id"]);
  if (options["rollback-run-id"]) {
    const rollback = await buildRollbackPlan({
      firestore, runId: options["rollback-run-id"],
    });
    const manifest = rollback.manifest;
    const rollbackContext = await readProductionContext({
      firestore, profile: manifest.source_profile, brandId: manifest.brand_id,
      brandName: manifest.brand_name, actorUid: options["actor-uid"],
    });
    const requiredConfirmation = expectedRollbackConfirmation({
      projectId: options["project-id"], runId: rollback.run_id,
      planChecksum: rollback.plan_checksum,
    });
    const publicRollback = {
      mode: options.apply ? "rollback_apply" : "rollback_dry_run",
      run_id: rollback.run_id, plan_checksum: rollback.plan_checksum,
      archive_product_ids: rollback.archive_product_ids,
      archive_group_ids: rollback.archive_group_ids,
      blocked: rollback.blocked, blocked_groups: rollback.blocked_groups,
      required_confirmation: requiredConfirmation,
    };
    if (!options.apply) {
      process.stdout.write(`${JSON.stringify(publicRollback, null, 2)}\n`);
      return publicRollback;
    }
    const result = await applyRollback({
      firestore, plan: rollback, projectId: options["project-id"],
      confirmation: options.confirm, actor: rollbackContext.actor,
    });
    process.stdout.write(`${JSON.stringify({...publicRollback, ...result}, null, 2)}\n`);
    return result;
  }
  for (const name of ["profile", "file", "brand-id", "brand-name"]) {
    if (!String(options[name] || "").trim()) throw codedError(`missing-${name}`);
  }
  const context = await readProductionContext({
    firestore, profile: options.profile, brandId: options["brand-id"],
    brandName: options["brand-name"], actorUid: options["actor-uid"],
  });
  const preview = runLegacyPreview({
    profile: options.profile, sourceFile: options.file,
    brandId: options["brand-id"], brandName: options["brand-name"],
  });
  const plan = buildCatalogImportPlan({preview, context, profile: options.profile});
  const publicPlan = {
    mode: options.apply ? "apply" : "dry_run",
    run_id: plan.run_id, plan_checksum: plan.plan_checksum,
    source_sha256: plan.source_sha256, brand_id: plan.brand_id,
    brand_name: plan.brand_name, counts: plan.counts,
    skipped_rows: plan.skipped_rows, review_rows: plan.review_rows,
    required_confirmation: expectedConfirmation({
      projectId: options["project-id"], runId: plan.run_id,
      planChecksum: plan.plan_checksum,
    }),
  };
  if (!options.apply) {
    process.stdout.write(`${JSON.stringify(publicPlan, null, 2)}\n`);
    return publicPlan;
  }
  const result = await applyCatalogImport({
    firestore, plan, projectId: options["project-id"], confirmation: options.confirm,
  });
  process.stdout.write(`${JSON.stringify({...publicPlan, ...result}, null, 2)}\n`);
  return result;
}

if (require.main === module) {
  main().catch((error) => {
    process.stderr.write(`${error.code || "catalog-import-failed"}\n`);
    process.exitCode = 2;
  });
}

module.exports = {
  COLLECTIONS,
  PROFILES,
  UNCATEGORIZED_NAME,
  applyCatalogImport,
  applyRollback,
  buildCatalogImportPlan,
  buildRollbackPlan,
  checksum,
  expectedConfirmation,
  expectedRollbackConfirmation,
  normalizeCatalogText,
  normalizeLegacyCode,
  readProductionContext,
  runLegacyPreview,
  uniqueKeyId,
};
