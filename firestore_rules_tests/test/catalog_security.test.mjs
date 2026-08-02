import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteField,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-store-collection-catalog';
const brandA = 'TlOswncJiWX7mwsf3U4e';
const brandB = 'WLMnMVT6u1H2VQ0qziJ3';
const uncategorizedKey = 'uncategorized';
const uncategorizedName = 'غير مصنف';
const fixedTimestamp = Timestamp.fromMillis(1_700_000_000_000);

let testEnvironment;

before(async () => {
  const rules = await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8');
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });
});

after(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const writes = writeBatch(database);

    writes.set(doc(database, 'brands', brandA), { name: 'الأصالة' });
    writes.set(doc(database, 'brands', brandB), { name: 'اقليد' });
    writes.set(doc(database, 'branches', 'branch-a'), {
      name: 'Al-Asalah branch',
      brand_id: brandA,
    });
    writes.set(doc(database, 'branches', 'branch-b'), {
      name: 'Eqlid branch',
      brand_id: brandB,
    });

    writes.set(doc(database, 'users', 'accountant-user'), user('accountant'));
    writes.set(doc(database, 'users', 'collector-user'), user('collector'));
    writes.set(doc(database, 'users', 'admin-user'), user('admin'));
    writes.set(
      doc(database, 'users', 'manager-a'),
      user('manager', 'branch-a'),
    );
    writes.set(
      doc(database, 'users', 'manager-b'),
      user('manager', 'branch-b'),
    );
    writes.set(
      doc(database, 'users', 'employee-a'),
      user('employee', 'branch-a'),
    );
    writes.set(doc(database, 'users', 'inactive-user'), {
      ...user('manager', 'branch-a'),
      isActive: false,
    });
    writes.set(doc(database, 'users', 'inactive-collector-user'), {
      ...user('collector'),
      isActive: false,
    });
    writes.set(doc(database, 'users', 'unknown-role-user'), user('mystery'));

    writes.set(doc(database, 'product_groups', 'group-a'), seededGroup({
      id: 'group-a',
      brandId: brandA,
      name: 'عطور',
    }));
    writes.set(doc(database, 'product_groups', 'group-b'), seededGroup({
      id: 'group-b',
      brandId: brandB,
      name: 'مواد غذائية',
    }));
    writes.set(doc(database, 'products', 'seed-product-a'), seededProduct({
      id: 'seed-product-a',
      brandId: brandA,
      groupId: 'group-a',
      uniqueKeyId: 'seed-name-key-a',
      name: 'منتج أصالة',
    }));
    writes.set(doc(database, 'products', 'seed-product-b'), seededProduct({
      id: 'seed-product-b',
      brandId: brandB,
      groupId: 'group-b',
      uniqueKeyId: 'seed-name-key-b',
      name: 'منتج اقليد',
    }));
    await writes.commit();
  });
});

function user(role, branchId) {
  return {
    role,
    isActive: true,
    mustChangePassword: false,
    ...(branchId ? { branchId } : {}),
  };
}

function databaseFor(uid) {
  return testEnvironment.authenticatedContext(uid).firestore();
}

function seededGroup({ id, brandId, name }) {
  return {
    id,
    brand_id: brandId,
    name,
    normalized_name: name,
    active: true,
    created_by: 'seed',
    created_by_name: 'Seed',
    created_at: fixedTimestamp,
    updated_by: 'seed',
    updated_by_name: 'Seed',
    updated_at: fixedTimestamp,
  };
}

function systemGroupId(brandId) {
  return `system-group-${brandId}-uncategorized`;
}

function systemGroupPayload({
  brandId,
  groupId = systemGroupId(brandId),
  auditId = `${groupId}-audit`,
  actorUid = 'accountant-user',
  actorName = 'Accountant',
}) {
  return {
    id: groupId,
    brand_id: brandId,
    name: uncategorizedName,
    normalized_name: uncategorizedName,
    is_system_group: true,
    system_key: uncategorizedKey,
    active: true,
    last_audit_event_id: auditId,
    created_by: actorUid,
    created_by_name: actorName,
    created_at: serverTimestamp(),
    updated_by: actorUid,
    updated_by_name: actorName,
    updated_at: serverTimestamp(),
  };
}

async function createSystemGroupWithAudit(database, {
  brandId = brandA,
  groupId = systemGroupId(brandId),
  auditId = `${groupId}-audit`,
  actorUid = 'accountant-user',
  actorName = 'Accountant',
  actorRole = 'accountant',
} = {}) {
  const batch = writeBatch(database);
  batch.set(
    doc(database, 'product_groups', groupId),
    systemGroupPayload({ brandId, groupId, auditId, actorUid, actorName }),
  );
  batch.set(doc(database, 'product_audit_events', auditId), {
    id: auditId,
    entity_type: 'product_group',
    entity_id: groupId,
    brand_id: brandId,
    action: 'system_group_created',
    after: {
      id: groupId,
      name: uncategorizedName,
      system_key: uncategorizedKey,
    },
    actor_uid: actorUid,
    actor_name: actorName,
    actor_role: actorRole,
    created_at: serverTimestamp(),
  });
  return batch.commit();
}

function seededProduct({ id, brandId, groupId, uniqueKeyId, name }) {
  return {
    id,
    brand_id: brandId,
    group_id: groupId,
    name,
    normalized_name: name,
    units: [
      {
        unit_id: 'primary',
        display_value: 'حبه',
        raw_value: 'حبه',
      },
    ],
    primary_unit_id: 'primary',
    active: true,
    version: 1,
    name_unique_key_id: uniqueKeyId,
    created_by: 'seed',
    created_by_name: 'Seed',
    created_at: fixedTimestamp,
    updated_by: 'seed',
    updated_by_name: 'Seed',
    updated_at: fixedTimestamp,
  };
}

function newProduct({
  id = 'new-product',
  name = 'منتج جديد',
  uniqueKeyId = 'new-name-key',
  auditId = 'new-product-audit',
  units,
  extra = {},
} = {}) {
  return {
    id,
    brand_id: brandA,
    group_id: 'group-a',
    name,
    normalized_name: name,
    units: units ?? [
      {
        unit_id: 'primary',
        display_value: 'علبة',
        raw_value: 'علبة',
      },
    ],
    primary_unit_id: 'primary',
    active: true,
    version: 1,
    name_unique_key_id: uniqueKeyId,
    last_audit_event_id: auditId,
    source_metadata: {},
    created_by: 'accountant-user',
    created_by_name: 'Accountant',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
    ...extra,
  };
}

function newUniqueKey({
  id = 'new-name-key',
  productId = 'new-product',
  keyType = 'name',
  normalizedValue = 'منتج جديد',
} = {}) {
  return {
    id,
    brand_id: brandA,
    key_type: keyType,
    normalized_value: normalizedValue,
    product_id: productId,
    active: true,
    created_by: 'accountant-user',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_at: serverTimestamp(),
  };
}

async function createProductAndKey(database, options = {}) {
  const id = options.id ?? 'new-product';
  const uniqueKeyId = options.uniqueKeyId ?? 'new-name-key';
  const legacyKeyId = options.legacyKeyId;
  const auditId = options.auditId ?? `${id}-audit`;
  const productExtra = {
    ...(options.extra ?? {}),
    ...(legacyKeyId
      ? {
          legacy_code: options.legacyCode,
          legacy_code_unique_key_id: legacyKeyId,
        }
      : {}),
  };
  const batch = writeBatch(database);
  batch.set(
    doc(database, 'products', id),
    newProduct({ ...options, id, uniqueKeyId, auditId, extra: productExtra }),
  );
  if (legacyKeyId) {
    batch.set(
      doc(database, 'product_unique_keys', legacyKeyId),
      newUniqueKey({
        id: legacyKeyId,
        productId: id,
        keyType: 'legacy_code',
        normalizedValue: options.legacyCode,
      }),
    );
  }
  batch.set(
    doc(database, 'product_unique_keys', uniqueKeyId),
    newUniqueKey({
      id: uniqueKeyId,
      productId: id,
      normalizedValue: options.name ?? 'منتج جديد',
    }),
  );
  batch.set(doc(database, 'product_audit_events', auditId), {
    id: auditId,
    entity_type: 'product',
    entity_id: id,
    brand_id: brandA,
    action: 'created',
    after: { id, name: options.name ?? 'منتج جديد' },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  return batch.commit();
}

function latestPrice({
  id = 'latest-a',
  historyId = 'history-a',
  version = 1,
  price = 125,
  unitId = 'primary',
  unitValue = 'حبه',
  actorUid = 'collector-user',
  actorName = 'General manager',
  actorRole = 'collector',
} = {}) {
  return {
    id,
    latest_key: id,
    history_event_id: historyId,
    brand_id: brandA,
    product_id: 'seed-product-a',
    unit_id: unitId,
    unit_value: unitValue,
    currency: 'YER',
    price,
    source_invoice_id: 'invoice-local-test',
    changed_by: actorUid,
    changed_by_name: actorName,
    changed_by_role: actorRole,
    changed_at: serverTimestamp(),
    version,
  };
}

function historyPrice({
  id = 'history-a',
  latestId = 'latest-a',
  version = 1,
  price = 125,
  previousPrice,
  previousSourceInvoiceId,
  unitId = 'primary',
  unitValue = 'حبه',
  actorUid = 'collector-user',
  actorName = 'General manager',
  actorRole = 'collector',
} = {}) {
  return {
    id,
    latest_key: latestId,
    brand_id: brandA,
    product_id: 'seed-product-a',
    unit_id: unitId,
    unit_value: unitValue,
    currency: 'YER',
    price,
    ...(previousPrice === undefined ? {} : { previous_price: previousPrice }),
    ...(previousPrice === undefined
      ? {}
      : {
          previous_source_invoice_id:
            previousSourceInvoiceId ?? 'invoice-local-test',
        }),
    source_invoice_id: 'invoice-local-test',
    changed_by: actorUid,
    changed_by_name: actorName,
    changed_by_role: actorRole,
    changed_at: serverTimestamp(),
    version,
  };
}

async function createPricePair(database, {
  latestId = 'latest-a',
  historyId = 'history-a',
  actorUid = 'collector-user',
  actorName = 'General manager',
  actorRole = 'collector',
} = {}) {
  const batch = writeBatch(database);
  batch.set(
    doc(database, 'product_price_latest', latestId),
    latestPrice({
      id: latestId,
      historyId,
      actorUid,
      actorName,
      actorRole,
    }),
  );
  batch.set(
    doc(database, 'product_price_history', historyId),
    historyPrice({
      id: historyId,
      latestId,
      actorUid,
      actorName,
      actorRole,
    }),
  );
  return batch.commit();
}

async function seedPricePairWithoutRules(options = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await createPricePair(context.firestore(), options);
  });
}

test('branch users can read only catalog documents for their branch brand', async () => {
  const manager = databaseFor('manager-a');
  const employee = databaseFor('employee-a');

  await assertSucceeds(getDoc(doc(manager, 'products', 'seed-product-a')));
  await assertFails(getDoc(doc(manager, 'products', 'seed-product-b')));
  await assertSucceeds(getDoc(doc(employee, 'product_groups', 'group-a')));
  await assertFails(getDoc(doc(employee, 'product_groups', 'group-b')));

  await assertSucceeds(getDocs(query(
    collection(manager, 'products'),
    where('brand_id', '==', brandA),
  )));
  await assertFails(getDocs(collection(manager, 'products')));
  await assertFails(getDocs(query(
    collection(manager, 'products'),
    where('brand_id', '==', brandB),
  )));
});

test('catalog supervisors can read all brands but only accountants can write', async () => {
  const accountant = databaseFor('accountant-user');
  const collector = databaseFor('collector-user');
  const admin = databaseFor('admin-user');
  const manager = databaseFor('manager-a');

  await assertSucceeds(getDocs(collection(accountant, 'products')));
  await assertSucceeds(getDocs(collection(collector, 'products')));
  await assertSucceeds(getDocs(collection(admin, 'products')));
  await assertSucceeds(createProductAndKey(accountant));

  await assertFails(createProductAndKey(collector, {
    id: 'collector-product',
    uniqueKeyId: 'collector-key',
  }));
  await assertFails(createProductAndKey(admin, {
    id: 'admin-product',
    uniqueKeyId: 'admin-key',
  }));
  await assertFails(createProductAndKey(manager, {
    id: 'manager-product',
    uniqueKeyId: 'manager-key',
  }));
});

test('group creation requires a linked audit and group deactivation is unavailable', async () => {
  const accountant = databaseFor('accountant-user');
  const groupId = 'new-group';
  const auditId = 'new-group-audit';
  const group = {
    id: groupId,
    brand_id: brandA,
    name: 'مجموعة جديدة',
    normalized_name: 'مجموعة جديدة',
    is_system_group: false,
    active: true,
    last_audit_event_id: auditId,
    created_by: 'accountant-user',
    created_by_name: 'Accountant',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  };

  await assertFails(setDoc(doc(accountant, 'product_groups', groupId), group));

  const emptyAfter = writeBatch(accountant);
  emptyAfter.set(doc(accountant, 'product_groups', groupId), group);
  emptyAfter.set(doc(accountant, 'product_audit_events', auditId), {
    id: auditId,
    entity_type: 'product_group',
    entity_id: groupId,
    brand_id: brandA,
    action: 'created',
    after: {},
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertFails(emptyAfter.commit());

  const batch = writeBatch(accountant);
  batch.set(doc(accountant, 'product_groups', groupId), group);
  batch.set(doc(accountant, 'product_audit_events', auditId), {
    id: auditId,
    entity_type: 'product_group',
    entity_id: groupId,
    brand_id: brandA,
    action: 'created',
    after: { id: groupId, name: 'مجموعة جديدة' },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(accountant, 'product_groups', groupId), {
    active: false,
  }));
});

test('each brand has one immutable deterministic uncategorized system group', async () => {
  const accountant = databaseFor('accountant-user');
  const groupAId = systemGroupId(brandA);
  const groupBId = systemGroupId(brandB);

  await assertSucceeds(createSystemGroupWithAudit(accountant, {
    brandId: brandA,
  }));

  const reservedIdAuditId = 'ordinary-reserved-id-audit';
  const reservedIdBatch = writeBatch(accountant);
  reservedIdBatch.set(doc(accountant, 'product_groups', groupBId), {
    id: groupBId,
    brand_id: brandB,
    name: 'مجموعة عادية',
    normalized_name: 'مجموعة عادية',
    is_system_group: false,
    active: true,
    last_audit_event_id: reservedIdAuditId,
    created_by: 'accountant-user',
    created_by_name: 'Accountant',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  reservedIdBatch.set(
    doc(accountant, 'product_audit_events', reservedIdAuditId),
    {
      id: reservedIdAuditId,
      entity_type: 'product_group',
      entity_id: groupBId,
      brand_id: brandB,
      action: 'created',
      after: { id: groupBId, name: 'مجموعة عادية' },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(reservedIdBatch.commit());

  await assertSucceeds(createSystemGroupWithAudit(accountant, {
    brandId: brandB,
  }));
  assert.notEqual(groupAId, groupBId);

  const systemGroups = await assertSucceeds(getDocs(query(
    collection(accountant, 'product_groups'),
    where('is_system_group', '==', true),
  )));
  assert.deepEqual(
    systemGroups.docs.map((snapshot) => snapshot.id).sort(),
    [groupAId, groupBId].sort(),
  );

  await assertFails(createSystemGroupWithAudit(accountant, {
    brandId: brandA,
    groupId: 'system-group-alternate-uncategorized',
    auditId: 'alternate-system-group-audit',
  }));
  await assertFails(createSystemGroupWithAudit(accountant, {
    brandId: brandA,
  }));

  const reservedNormalId = 'normal-group-claiming-system-name';
  const reservedAuditId = 'reserved-normal-group-audit';
  const reservedBatch = writeBatch(accountant);
  reservedBatch.set(doc(accountant, 'product_groups', reservedNormalId), {
    id: reservedNormalId,
    brand_id: brandA,
    name: uncategorizedName,
    normalized_name: uncategorizedName,
    is_system_group: false,
    active: true,
    last_audit_event_id: reservedAuditId,
    created_by: 'accountant-user',
    created_by_name: 'Accountant',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  reservedBatch.set(
    doc(accountant, 'product_audit_events', reservedAuditId),
    {
      id: reservedAuditId,
      entity_type: 'product_group',
      entity_id: reservedNormalId,
      brand_id: brandA,
      action: 'created',
      after: { id: reservedNormalId, name: uncategorizedName },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(reservedBatch.commit());

  for (const [suffix, overrides] of [
    ['title-name', {
      name: 'Uncategorized',
      normalized_name: 'Uncategorized',
    }],
    ['uppercase-normalized-name', {
      name: 'مجموعة عادية',
      normalized_name: 'UNCATEGORIZED',
    }],
    ['title-legacy-code', {
      name: 'مجموعة عادية',
      normalized_name: 'مجموعة عادية',
      legacy_code: 'Uncategorized',
    }],
  ]) {
    const variantGroupId = `normal-group-reserved-${suffix}`;
    const variantAuditId = `${variantGroupId}-audit`;
    const variantBatch = writeBatch(accountant);
    variantBatch.set(doc(accountant, 'product_groups', variantGroupId), {
      id: variantGroupId,
      brand_id: brandA,
      is_system_group: false,
      active: true,
      last_audit_event_id: variantAuditId,
      created_by: 'accountant-user',
      created_by_name: 'Accountant',
      created_at: serverTimestamp(),
      updated_by: 'accountant-user',
      updated_by_name: 'Accountant',
      updated_at: serverTimestamp(),
      ...overrides,
    });
    variantBatch.set(
      doc(accountant, 'product_audit_events', variantAuditId),
      {
        id: variantAuditId,
        entity_type: 'product_group',
        entity_id: variantGroupId,
        brand_id: brandA,
        action: 'created',
        after: { id: variantGroupId, ...overrides },
        actor_uid: 'accountant-user',
        actor_name: 'Accountant',
        actor_role: 'accountant',
        created_at: serverTimestamp(),
      },
    );
    await assertFails(variantBatch.commit());
  }

  const renameAuditId = 'system-group-rename-audit';
  const renameBatch = writeBatch(accountant);
  renameBatch.update(doc(accountant, 'product_groups', groupAId), {
    name: 'اسم آخر',
    normalized_name: 'اسم اخر',
    last_audit_event_id: renameAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  renameBatch.set(doc(accountant, 'product_audit_events', renameAuditId), {
    id: renameAuditId,
    entity_type: 'product_group',
    entity_id: groupAId,
    brand_id: brandA,
    action: 'updated',
    before: { name: uncategorizedName },
    after: { name: 'اسم آخر' },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertFails(renameBatch.commit());

  const archiveAuditId = 'system-group-archive-audit';
  const archiveBatch = writeBatch(accountant);
  archiveBatch.update(doc(accountant, 'product_groups', groupAId), {
    active: false,
    archived_by: 'accountant-user',
    archived_by_name: 'Accountant',
    archived_at: serverTimestamp(),
    last_audit_event_id: archiveAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  archiveBatch.set(doc(accountant, 'product_audit_events', archiveAuditId), {
    id: archiveAuditId,
    entity_type: 'product_group',
    entity_id: groupAId,
    brand_id: brandA,
    action: 'updated',
    before: { active: true },
    after: { active: false },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertFails(archiveBatch.commit());
  await assertFails(deleteDoc(doc(accountant, 'product_groups', groupAId)));
});

test('only the accountant can create or manipulate system groups', async () => {
  for (const actor of [
    {
      uid: 'collector-user',
      name: 'General manager',
      role: 'collector',
    },
    { uid: 'admin-user', name: 'Admin', role: 'admin' },
    { uid: 'manager-a', name: 'Manager', role: 'manager' },
    { uid: 'unknown-role-user', name: 'Unknown', role: 'mystery' },
  ]) {
    await assertFails(createSystemGroupWithAudit(databaseFor(actor.uid), {
      brandId: brandA,
      auditId: `system-group-${actor.uid}-audit`,
      actorUid: actor.uid,
      actorName: actor.name,
      actorRole: actor.role,
    }));
  }

  const accountant = databaseFor('accountant-user');
  await assertSucceeds(createSystemGroupWithAudit(accountant, {
    brandId: brandA,
  }));
  const groupId = systemGroupId(brandA);
  for (const actor of [
    {
      uid: 'collector-user',
      name: 'General manager',
      role: 'collector',
    },
    { uid: 'admin-user', name: 'Admin', role: 'admin' },
    { uid: 'manager-a', name: 'Manager', role: 'manager' },
    { uid: 'unknown-role-user', name: 'Unknown', role: 'mystery' },
  ]) {
    const database = databaseFor(actor.uid);
    const auditId = `system-group-update-${actor.uid}`;
    const batch = writeBatch(database);
    batch.update(doc(database, 'product_groups', groupId), {
      last_audit_event_id: auditId,
      updated_by: actor.uid,
      updated_by_name: actor.name,
      updated_at: serverTimestamp(),
    });
    batch.set(doc(database, 'product_audit_events', auditId), {
      id: auditId,
      entity_type: 'product_group',
      entity_id: groupId,
      brand_id: brandA,
      action: 'updated',
      before: { updated_by: 'accountant-user' },
      after: { updated_by: actor.uid },
      actor_uid: actor.uid,
      actor_name: actor.name,
      actor_role: actor.role,
      created_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  }
});

test('an audited product can move from fallback system group to a normal group', async () => {
  const accountant = databaseFor('accountant-user');
  const fallbackGroupId = systemGroupId(brandA);
  const fallbackSourceMetadata = {
    source_profile: 'eqlid_legacy_catalog',
    source_file_sha256: 'fallback-source-hash',
    source_sheet: 'Page1',
    source_row: 321,
    raw_material_value: '101 Legacy Material',
    raw_group_value: '',
    raw_primary_unit: 'حبه',
    raw_unit_2: 'علبة',
    raw_unit_3: '',
    import_id: 'dry-run-eqlid',
    original_group_missing: true,
    fallback_system_group_assigned: true,
    fallback_system_group_key: uncategorizedKey,
    fallback_system_group_id: fallbackGroupId,
  };
  await assertSucceeds(createSystemGroupWithAudit(accountant, {
    brandId: brandA,
  }));

  await assertFails(createProductAndKey(accountant, {
    id: 'invalid-fallback-metadata-product',
    uniqueKeyId: 'invalid-fallback-metadata-key',
    extra: {
      source_metadata: { original_group_missing: 'true' },
    },
  }));

  await assertFails(createProductAndKey(accountant, {
    id: 'missing-without-fallback-product',
    uniqueKeyId: 'missing-without-fallback-key',
    extra: {
      source_metadata: {
        source_profile: 'eqlid_legacy_catalog',
        original_group_missing: true,
        fallback_system_group_assigned: false,
      },
    },
  }));

  await assertFails(createProductAndKey(accountant, {
    id: 'invalid-fallback-group-product',
    uniqueKeyId: 'invalid-fallback-group-key',
    extra: {
      group_id: 'group-a',
      source_metadata: {
        source_profile: 'eqlid_legacy_catalog',
        original_group_missing: true,
        fallback_system_group_assigned: true,
        fallback_system_group_key: uncategorizedKey,
        fallback_system_group_id: fallbackGroupId,
      },
    },
  }));

  const productId = 'fallback-product';
  await assertSucceeds(createProductAndKey(accountant, {
    id: productId,
    uniqueKeyId: 'fallback-product-key',
    extra: {
      group_id: fallbackGroupId,
      source_metadata: fallbackSourceMetadata,
    },
  }));

  const productReference = doc(accountant, 'products', productId);
  const provenanceMutationAuditId = 'fallback-provenance-mutation-audit';
  const provenanceMutationBatch = writeBatch(accountant);
  provenanceMutationBatch.update(productReference, {
    group_id: 'group-a',
    source_metadata: {
      source_profile: 'eqlid_legacy_catalog',
      source_file_sha256: 'fallback-source-hash',
      source_sheet: 'Page1',
      source_row: 321,
      raw_material_value: '101 Legacy Material',
      raw_group_value: 'tampered group value',
      raw_primary_unit: 'حبه',
      raw_unit_2: 'علبة',
      raw_unit_3: '',
      import_id: 'dry-run-eqlid',
      original_group_missing: true,
      fallback_system_group_assigned: true,
      fallback_system_group_key: uncategorizedKey,
      fallback_system_group_id: fallbackGroupId,
    },
    version: 2,
    last_audit_event_id: provenanceMutationAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  provenanceMutationBatch.set(
    doc(accountant, 'product_audit_events', provenanceMutationAuditId),
    {
      id: provenanceMutationAuditId,
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'recategorized',
      before: {
        group_id: fallbackGroupId,
        fallback_system_group_assigned: true,
      },
      after: {
        group_id: 'group-a',
        fallback_system_group_assigned: true,
      },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(provenanceMutationBatch.commit());

  const untruthfulAuditId = 'fallback-untruthful-audit';
  const untruthfulBatch = writeBatch(accountant);
  untruthfulBatch.update(productReference, {
    group_id: 'group-a',
    version: 2,
    last_audit_event_id: untruthfulAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  untruthfulBatch.set(
    doc(accountant, 'product_audit_events', untruthfulAuditId),
    {
      id: untruthfulAuditId,
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'recategorized',
      before: {
        group_id: 'fabricated-group',
        version: 1,
      },
      after: {
        group_id: 'group-a',
        version: 2,
      },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(untruthfulBatch.commit());

  const fabricatedProvenanceAuditId = 'fallback-fabricated-provenance-audit';
  const fabricatedProvenanceBatch = writeBatch(accountant);
  fabricatedProvenanceBatch.update(productReference, {
    group_id: 'group-a',
    version: 2,
    last_audit_event_id: fabricatedProvenanceAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  fabricatedProvenanceBatch.set(
    doc(accountant, 'product_audit_events', fabricatedProvenanceAuditId),
    {
      id: fabricatedProvenanceAuditId,
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'recategorized',
      before: {
        group_id: fallbackGroupId,
        version: 1,
        source_metadata: {
          ...fallbackSourceMetadata,
          raw_group_value: 'fabricated audit-only provenance',
        },
      },
      after: {
        group_id: 'group-a',
        version: 2,
        source_metadata: fallbackSourceMetadata,
      },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(fabricatedProvenanceBatch.commit());

  const recategorizeAuditId = 'fallback-reassignment-audit';
  const recategorizeBatch = writeBatch(accountant);
  recategorizeBatch.update(productReference, {
    group_id: 'group-a',
    version: 2,
    last_audit_event_id: recategorizeAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  recategorizeBatch.set(
    doc(accountant, 'product_audit_events', recategorizeAuditId),
    {
      id: recategorizeAuditId,
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'recategorized',
      before: {
        group_id: fallbackGroupId,
        version: 1,
      },
      after: {
        group_id: 'group-a',
        version: 2,
      },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertSucceeds(recategorizeBatch.commit());

  const product = (await getDoc(productReference)).data();
  assert.equal(product.group_id, 'group-a');
  assert.equal(product.source_metadata.original_group_missing, true);
  assert.equal(product.source_metadata.fallback_system_group_assigned, true);
  assert.equal(product.source_metadata.fallback_system_group_key, uncategorizedKey);
  assert.equal(product.source_metadata.fallback_system_group_id, fallbackGroupId);
});

test('catalog rules reject top-level and nested protected-price fields', async () => {
  const accountant = databaseFor('accountant-user');

  await assertFails(createProductAndKey(accountant, {
    id: 'top-level-price-product',
    uniqueKeyId: 'top-level-price-key',
    extra: { price: 500 },
  }));

  await assertFails(createProductAndKey(accountant, {
    id: 'nested-price-product',
    uniqueKeyId: 'nested-price-key',
    units: [
      {
        unit_id: 'primary',
        display_value: 'حبه',
        raw_value: 'حبه',
        price: 500,
      },
    ],
  }));
});

test('a full three-unit legacy-coded import product stays under the rule limit', async () => {
  const accountant = databaseFor('accountant-user');
  await assertSucceeds(createProductAndKey(accountant, {
    id: 'full-import-product',
    name: 'منتج استيراد كامل',
    uniqueKeyId: 'full-import-name-key',
    legacyKeyId: 'full-import-code-key',
    legacyCode: '09-123',
    units: [
      {
        unit_id: 'primary',
        display_value: 'حبه',
        raw_value: 'حبه',
      },
      {
        unit_id: 'unit_2',
        display_value: 'علبة',
        raw_value: 'علبة',
      },
      {
        unit_id: 'unit_3',
        display_value: 'تولة',
        raw_value: 'تولة',
      },
    ],
    extra: {
      source_metadata: {
        source_profile: 'al_asalah_legacy_catalog',
        source_file_sha256: 'full-import-source-hash',
        source_sheet: 'Page1',
        source_row: 42,
        raw_material_value: '09-123-منتج استيراد كامل',
        raw_group_value: '9-عطور',
        raw_primary_unit: 'حبه',
        raw_unit_2: 'علبة',
        raw_unit_3: 'تولة',
        import_id: 'full-import-preview',
        original_group_missing: false,
        fallback_system_group_assigned: false,
      },
    },
  }));
});

test('duplicate keys cannot be reassigned and catalog records cannot be deleted', async () => {
  const accountant = databaseFor('accountant-user');
  await assertSucceeds(createProductAndKey(accountant));

  await assertFails(createProductAndKey(accountant, {
    id: 'duplicate-product',
    uniqueKeyId: 'new-name-key',
    name: 'منتج آخر',
  }));
  await assertFails(deleteDoc(doc(accountant, 'products', 'new-product')));
  await assertFails(deleteDoc(doc(accountant, 'product_groups', 'group-a')));
  await assertFails(deleteDoc(doc(accountant, 'product_unique_keys', 'new-name-key')));
});

test('product update, archive, and reactivate require fresh complete audits', async () => {
  const accountant = databaseFor('accountant-user');
  const productId = 'lifecycle-product';
  const productReference = doc(accountant, 'products', productId);
  await assertSucceeds(createProductAndKey(accountant, {
    id: productId,
    uniqueKeyId: 'lifecycle-product-key',
  }));

  const missingArchiveAudit = {
    active: false,
    version: 2,
    last_audit_event_id: 'missing-archive-audit',
    archived_by: 'accountant-user',
    archived_by_name: 'Accountant',
    archived_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  };
  await assertFails(updateDoc(productReference, missingArchiveAudit));

  const emptyReasonArchive = writeBatch(accountant);
  emptyReasonArchive.update(productReference, {
    ...missingArchiveAudit,
    last_audit_event_id: 'empty-reason-archive-audit',
  });
  emptyReasonArchive.set(
    doc(accountant, 'product_audit_events', 'empty-reason-archive-audit'),
    {
      id: 'empty-reason-archive-audit',
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'archived',
      before: { active: true, version: 1 },
      after: { active: false, version: 2 },
      reason: '',
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(emptyReasonArchive.commit());

  const wrongArchiveActor = writeBatch(accountant);
  wrongArchiveActor.update(productReference, {
    ...missingArchiveAudit,
    last_audit_event_id: 'wrong-archive-actor-audit',
    archived_by: 'different-user',
  });
  wrongArchiveActor.set(
    doc(accountant, 'product_audit_events', 'wrong-archive-actor-audit'),
    {
      id: 'wrong-archive-actor-audit',
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'archived',
      before: { active: true, version: 1 },
      after: { active: false, version: 2 },
      reason: 'سبب صالح لكن منفذ الأرشفة غير صالح',
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(wrongArchiveActor.commit());

  const archiveAuditId = 'archive-product-audit';
  const archiveBatch = writeBatch(accountant);
  archiveBatch.update(productReference, {
    ...missingArchiveAudit,
    last_audit_event_id: archiveAuditId,
  });
  archiveBatch.set(doc(accountant, 'product_audit_events', archiveAuditId), {
    id: archiveAuditId,
    entity_type: 'product',
    entity_id: productId,
    brand_id: brandA,
    action: 'archived',
    before: { active: true, version: 1 },
    after: { active: false, version: 2 },
    reason: 'لم يعد مستخدماً حالياً',
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertSucceeds(archiveBatch.commit());
  assert.equal((await getDoc(productReference)).data().active, false);

  const missingReactivateAudit = {
    active: true,
    version: 3,
    last_audit_event_id: 'missing-reactivate-audit',
    archived_by: deleteField(),
    archived_by_name: deleteField(),
    archived_at: deleteField(),
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  };
  await assertFails(updateDoc(productReference, missingReactivateAudit));

  const emptyReasonReactivate = writeBatch(accountant);
  emptyReasonReactivate.update(productReference, {
    ...missingReactivateAudit,
    last_audit_event_id: 'empty-reason-reactivate-audit',
  });
  emptyReasonReactivate.set(
    doc(accountant, 'product_audit_events', 'empty-reason-reactivate-audit'),
    {
      id: 'empty-reason-reactivate-audit',
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'reactivated',
      before: { active: false, version: 2 },
      after: { active: true, version: 3 },
      reason: '',
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(emptyReasonReactivate.commit());

  const lingeringArchiveFields = writeBatch(accountant);
  lingeringArchiveFields.update(productReference, {
    active: true,
    version: 3,
    last_audit_event_id: 'lingering-archive-fields-audit',
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  lingeringArchiveFields.set(
    doc(accountant, 'product_audit_events', 'lingering-archive-fields-audit'),
    {
      id: 'lingering-archive-fields-audit',
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'reactivated',
      before: { active: false, version: 2 },
      after: { active: true, version: 3 },
      reason: 'سبب صالح مع حقول أرشفة متبقية',
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(lingeringArchiveFields.commit());

  const reactivateAuditId = 'reactivate-product-audit';
  const reactivateBatch = writeBatch(accountant);
  reactivateBatch.update(productReference, {
    ...missingReactivateAudit,
    last_audit_event_id: reactivateAuditId,
  });
  reactivateBatch.set(
    doc(accountant, 'product_audit_events', reactivateAuditId),
    {
      id: reactivateAuditId,
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'reactivated',
      before: { active: false, version: 2 },
      after: { active: true, version: 3 },
      reason: 'إعادة المنتج للاستخدام',
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertSucceeds(reactivateBatch.commit());
  const reactivated = (await getDoc(productReference)).data();
  assert.equal(reactivated.active, true);
  assert.equal(Object.hasOwn(reactivated, 'archived_at'), false);

  const changedUnits = [
    {
      unit_id: 'primary',
      display_value: 'علبة كبيرة',
      raw_value: 'علبة كبيرة',
    },
  ];
  await assertFails(updateDoc(productReference, {
    units: changedUnits,
    version: 4,
    last_audit_event_id: 'missing-update-audit',
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  }));

  const incompleteUpdate = writeBatch(accountant);
  incompleteUpdate.update(productReference, {
    units: changedUnits,
    version: 4,
    last_audit_event_id: 'incomplete-update-audit',
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  incompleteUpdate.set(
    doc(accountant, 'product_audit_events', 'incomplete-update-audit'),
    {
      id: 'incomplete-update-audit',
      entity_type: 'product',
      entity_id: productId,
      brand_id: brandA,
      action: 'updated',
      before: {},
      after: { units: changedUnits, version: 4 },
      actor_uid: 'accountant-user',
      actor_name: 'Accountant',
      actor_role: 'accountant',
      created_at: serverTimestamp(),
    },
  );
  await assertFails(incompleteUpdate.commit());

  const updateAuditId = 'update-product-audit';
  const updateBatch = writeBatch(accountant);
  updateBatch.update(productReference, {
    units: changedUnits,
    version: 4,
    last_audit_event_id: updateAuditId,
    updated_by: 'accountant-user',
    updated_by_name: 'Accountant',
    updated_at: serverTimestamp(),
  });
  updateBatch.set(doc(accountant, 'product_audit_events', updateAuditId), {
    id: updateAuditId,
    entity_type: 'product',
    entity_id: productId,
    brand_id: brandA,
    action: 'updated',
    before: { units: [{ unit_id: 'primary', display_value: 'علبة' }], version: 3 },
    after: { units: changedUnits, version: 4 },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertSucceeds(updateBatch.commit());
  assert.equal((await getDoc(productReference)).data().version, 4);
  await assertFails(deleteDoc(productReference));
});

test('catalog audit events are accountant-authored and immutable', async () => {
  const accountant = databaseFor('accountant-user');
  const manager = databaseFor('manager-a');
  const collector = databaseFor('collector-user');
  const auditReference = doc(
    accountant,
    'product_audit_events',
    'audited-product-audit',
  );

  await assertFails(setDoc(doc(accountant, 'product_audit_events', 'orphan-audit'), {
    id: 'orphan-audit',
    entity_type: 'product',
    entity_id: 'seed-product-a',
    brand_id: brandA,
    action: 'updated',
    before: { name: 'قديم' },
    after: { name: 'جديد' },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  }));

  await assertSucceeds(createProductAndKey(accountant, {
    id: 'audited-product',
    uniqueKeyId: 'audited-product-key',
  }));

  await assertFails(getDoc(doc(
    manager,
    'product_audit_events',
    'audited-product-audit',
  )));
  await assertSucceeds(getDoc(doc(
    collector,
    'product_audit_events',
    'audited-product-audit',
  )));
  await assertFails(updateDoc(auditReference, { action: 'rewritten' }));
  await assertFails(deleteDoc(auditReference));
});

test('accounting profiles are private and every upsert requires a fresh audit', async () => {
  const accountant = databaseFor('accountant-user');
  const admin = databaseFor('admin-user');
  const manager = databaseFor('manager-a');
  const profileId = 'seed-product-a';
  const auditId = 'profile-audit';
  const profile = {
    id: profileId,
    product_id: profileId,
    brand_id: brandA,
    sync_state: 'pending',
    last_audit_event_id: auditId,
    created_by: 'accountant-user',
    created_at: serverTimestamp(),
    updated_by: 'accountant-user',
    updated_at: serverTimestamp(),
  };

  await assertFails(setDoc(
    doc(accountant, 'product_accounting_profiles', profileId),
    profile,
  ));

  const batch = writeBatch(accountant);
  batch.set(doc(accountant, 'product_accounting_profiles', profileId), profile);
  batch.set(doc(accountant, 'product_audit_events', auditId), {
    id: auditId,
    entity_type: 'product_accounting_profile',
    entity_id: profileId,
    brand_id: brandA,
    action: 'created',
    after: { product_id: profileId, sync_state: 'pending' },
    actor_uid: 'accountant-user',
    actor_name: 'Accountant',
    actor_role: 'accountant',
    created_at: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());

  await assertFails(getDoc(doc(
    manager,
    'product_accounting_profiles',
    profileId,
  )));
  await assertSucceeds(getDoc(doc(
    admin,
    'product_accounting_profiles',
    profileId,
  )));
  await assertFails(updateDoc(
    doc(accountant, 'product_accounting_profiles', profileId),
    { sync_state: 'synced' },
  ));
});

test('branch, inactive, and unknown users cannot directly read or write prices', async () => {
  await seedPricePairWithoutRules();

  for (const actor of [
    { uid: 'manager-a', name: 'Manager', role: 'manager' },
    { uid: 'employee-a', name: 'Employee', role: 'employee' },
    { uid: 'inactive-user', name: 'Inactive', role: 'manager' },
    {
      uid: 'inactive-collector-user',
      name: 'Inactive collector',
      role: 'collector',
    },
    { uid: 'unknown-role-user', name: 'Unknown', role: 'mystery' },
    { uid: 'missing-profile-user', name: 'Missing', role: 'mystery' },
  ]) {
    const database = databaseFor(actor.uid);
    await assertFails(getDoc(doc(database, 'product_price_latest', 'latest-a')));
    await assertFails(getDocs(collection(database, 'product_price_latest')));
    await assertFails(getDoc(doc(database, 'product_price_history', 'history-a')));
    await assertFails(getDocs(collection(database, 'product_price_history')));
    await assertFails(createPricePair(database, {
      latestId: `latest-${actor.uid}`,
      historyId: `history-${actor.uid}`,
      actorUid: actor.uid,
      actorName: actor.name,
      actorRole: actor.role,
    }));
  }
});

test('protected roles read price memory but every client write is backend-only', async () => {
  const collector = databaseFor('collector-user');
  const accountant = databaseFor('accountant-user');
  const admin = databaseFor('admin-user');

  await assertFails(setDoc(
    doc(collector, 'product_price_latest', 'orphan-latest'),
    latestPrice({ id: 'orphan-latest', historyId: 'missing-history' }),
  ));
  await seedPricePairWithoutRules();

  for (const database of [collector, accountant, admin]) {
    await assertSucceeds(getDoc(doc(database, 'product_price_latest', 'latest-a')));
    await assertSucceeds(getDocs(collection(database, 'product_price_history')));
  }

  for (const actor of [
    {
      database: collector,
      uid: 'collector-user',
      name: 'General manager',
      role: 'collector',
    },
    {
      database: accountant,
      uid: 'accountant-user',
      name: 'Accountant',
      role: 'accountant',
    },
    {
      database: admin,
      uid: 'admin-user',
      name: 'Admin',
      role: 'admin',
    },
  ]) {
    await assertFails(createPricePair(actor.database, {
      latestId: `latest-${actor.role}`,
      historyId: `history-${actor.role}`,
      actorUid: actor.uid,
      actorName: actor.name,
      actorRole: actor.role,
    }));

    const updateHistoryId = `history-update-${actor.role}`;
    const updateBatch = writeBatch(actor.database);
    updateBatch.update(
      doc(actor.database, 'product_price_latest', 'latest-a'),
      {
        history_event_id: updateHistoryId,
        price: 130,
        source_invoice_id: 'invoice-local-test',
        changed_by: actor.uid,
        changed_by_name: actor.name,
        changed_by_role: actor.role,
        changed_at: serverTimestamp(),
        version: 2,
      },
    );
    updateBatch.set(
      doc(actor.database, 'product_price_history', updateHistoryId),
      historyPrice({
        id: updateHistoryId,
        price: 130,
        previousPrice: 125,
        version: 2,
        actorUid: actor.uid,
        actorName: actor.name,
        actorRole: actor.role,
      }),
    );
    await assertFails(updateBatch.commit());
    await assertFails(deleteDoc(doc(
      actor.database,
      'product_price_latest',
      'latest-a',
    )));
    await assertFails(deleteDoc(doc(
      actor.database,
      'product_price_history',
      'history-a',
    )));
  }
});

test('price memory must reference an exact catalog product-unit snapshot', async () => {
  const collector = databaseFor('collector-user');
  const batch = writeBatch(collector);
  batch.set(
    doc(collector, 'product_price_latest', 'invalid-unit-latest'),
    latestPrice({
      id: 'invalid-unit-latest',
      historyId: 'invalid-unit-history',
      unitId: 'invented-unit',
      unitValue: 'وحدة مخترعة',
    }),
  );
  batch.set(
    doc(collector, 'product_price_history', 'invalid-unit-history'),
    historyPrice({
      id: 'invalid-unit-history',
      latestId: 'invalid-unit-latest',
      unitId: 'invented-unit',
      unitValue: 'وحدة مخترعة',
    }),
  );
  await assertFails(batch.commit());
});

test('price history is append-only and latest records cannot be deleted', async () => {
  const collector = databaseFor('collector-user');
  await seedPricePairWithoutRules();

  await assertFails(updateDoc(
    doc(collector, 'product_price_history', 'history-a'),
    { price: 999 },
  ));
  await assertFails(deleteDoc(doc(collector, 'product_price_history', 'history-a')));
  await assertFails(deleteDoc(doc(collector, 'product_price_latest', 'latest-a')));
});

test('latest price updates are denied to clients even with matching history', async () => {
  const collector = databaseFor('collector-user');
  await seedPricePairWithoutRules();

  await assertFails(updateDoc(
    doc(collector, 'product_price_latest', 'latest-a'),
    {
      price: 150,
      version: 2,
      changed_at: serverTimestamp(),
    },
  ));

  const wrongPreviousBatch = writeBatch(collector);
  wrongPreviousBatch.update(
    doc(collector, 'product_price_latest', 'latest-a'),
    {
      history_event_id: 'history-wrong-previous',
      price: 150,
      changed_at: serverTimestamp(),
      version: 2,
    },
  );
  wrongPreviousBatch.set(
    doc(collector, 'product_price_history', 'history-wrong-previous'),
    historyPrice({
      id: 'history-wrong-previous',
      price: 150,
      previousPrice: 999,
      previousSourceInvoiceId: 'incorrect-source',
      version: 2,
    }),
  );
  await assertFails(wrongPreviousBatch.commit());

  const batch = writeBatch(collector);
  batch.update(doc(collector, 'product_price_latest', 'latest-a'), {
    history_event_id: 'history-b',
    price: 150,
    changed_at: serverTimestamp(),
    version: 2,
  });
  batch.set(doc(collector, 'product_price_history', 'history-b'), historyPrice({
    id: 'history-b',
    price: 150,
    previousPrice: 125,
    version: 2,
  }));
  await assertFails(batch.commit());

  const snapshot = await assertSucceeds(getDoc(
    doc(collector, 'product_price_latest', 'latest-a'),
  ));
  assert.equal(snapshot.data().price, 125);
  assert.equal(snapshot.data().version, 1);
});
