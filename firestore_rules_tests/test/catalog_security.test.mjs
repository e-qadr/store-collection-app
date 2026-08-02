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
  normalizedValue = 'منتج جديد',
} = {}) {
  return {
    id,
    brand_id: brandA,
    key_type: 'name',
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
  const auditId = options.auditId ?? `${id}-audit`;
  const batch = writeBatch(database);
  batch.set(
    doc(database, 'products', id),
    newProduct({ ...options, id, uniqueKeyId, auditId }),
  );
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
    changed_by: 'collector-user',
    changed_by_name: 'General manager',
    changed_by_role: 'collector',
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
    changed_by: 'collector-user',
    changed_by_name: 'General manager',
    changed_by_role: 'collector',
    changed_at: serverTimestamp(),
    version,
  };
}

async function createPricePair(database) {
  const batch = writeBatch(database);
  batch.set(doc(database, 'product_price_latest', 'latest-a'), latestPrice());
  batch.set(doc(database, 'product_price_history', 'history-a'), historyPrice());
  return batch.commit();
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

test('manager, branch employee, and inactive users cannot directly read prices', async () => {
  const collector = databaseFor('collector-user');
  await assertSucceeds(createPricePair(collector));

  for (const uid of ['manager-a', 'employee-a', 'inactive-user']) {
    const database = databaseFor(uid);
    await assertFails(getDoc(doc(database, 'product_price_latest', 'latest-a')));
    await assertFails(getDocs(collection(database, 'product_price_latest')));
    await assertFails(getDoc(doc(database, 'product_price_history', 'history-a')));
    await assertFails(getDocs(collection(database, 'product_price_history')));
  }
});

test('protected roles can read price memory but standalone latest writes fail', async () => {
  const collector = databaseFor('collector-user');
  const accountant = databaseFor('accountant-user');
  const admin = databaseFor('admin-user');

  await assertFails(setDoc(
    doc(collector, 'product_price_latest', 'orphan-latest'),
    latestPrice({ id: 'orphan-latest', historyId: 'missing-history' }),
  ));
  await assertSucceeds(createPricePair(collector));

  for (const database of [collector, accountant, admin]) {
    await assertSucceeds(getDoc(doc(database, 'product_price_latest', 'latest-a')));
    await assertSucceeds(getDocs(collection(database, 'product_price_history')));
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
  await assertSucceeds(createPricePair(collector));

  await assertFails(updateDoc(
    doc(collector, 'product_price_history', 'history-a'),
    { price: 999 },
  ));
  await assertFails(deleteDoc(doc(collector, 'product_price_history', 'history-a')));
  await assertFails(deleteDoc(doc(collector, 'product_price_latest', 'latest-a')));
});

test('latest price updates require a new matching immutable history record', async () => {
  const collector = databaseFor('collector-user');
  await assertSucceeds(createPricePair(collector));

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
  await assertSucceeds(batch.commit());

  const snapshot = await assertSucceeds(getDoc(
    doc(collector, 'product_price_latest', 'latest-a'),
  ));
  assert.equal(snapshot.data().price, 150);
  assert.equal(snapshot.data().version, 2);
});
