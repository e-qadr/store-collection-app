import {after, before, beforeEach, test} from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {readFile} from 'node:fs/promises';
import {
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-store-collection-purchase';
const timestamp = Timestamp.fromMillis(1_780_000_000_000);
const digest = 'b'.repeat(64);
let environment;

before(async () => {
  const rules = await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8');
  environment = await initializeTestEnvironment({projectId, firestore: {rules}});
});

after(async () => environment.cleanup());

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const batch = writeBatch(database);
    for (const [uid, role, branchId, extra] of [
      ['manager-r', 'manager', 'branch-r', {}],
      ['manager-x', 'manager', 'branch-x', {}],
      ['employee-r', 'employee', 'branch-r', {}],
      ['collector-user', 'collector', '', {}],
      ['accountant-user', 'accountant', '', {}],
      ['admin-user', 'admin', '', {}],
      ['unknown-user', 'mystery', 'branch-r', {}],
      ['inactive-user', 'manager', 'branch-r', {isActive: false}],
      ['forced-user', 'manager', 'branch-r', {mustChangePassword: true}],
    ]) {
      batch.set(doc(database, 'users', uid), {
        role,
        isActive: true,
        mustChangePassword: false,
        ...(branchId ? {branchId} : {}),
        ...extra,
      });
    }
    batch.set(doc(database, 'brands', 'brand-r'), {id: 'brand-r', name: 'R'});
    batch.set(doc(database, 'branches', 'branch-r'), {
      id: 'branch-r', name: 'R', brand_id: 'brand-r', branch_manager_id: 'manager-r',
    });
    batch.set(doc(database, 'branches', 'branch-x'), {
      id: 'branch-x', name: 'X', brand_id: 'brand-r', branch_manager_id: 'manager-x',
    });
    await batch.commit();
  });
});

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function history() {
  return [{
    action: 'purchase_invoice_created',
    message: 'Public event without financial data',
    actor_id: 'collector-user',
    actor_name: 'Collector',
    actor_role: 'collector',
    timestamp,
  }];
}

function header({id = 'purchase-1', status = 'pendingReceiverReview', extra = {}} = {}) {
  return {
    id,
    schema_version: 1,
    workflow_version: 1,
    workflow_identity: 'purchase_invoice_v1',
    status,
    revision: 1,
    purchase_number: 'PUR-0001',
    receiving_branch_id: 'branch-r',
    receiving_branch_name: 'R',
    receiving_brand_id: 'brand-r',
    branch_ids: ['branch-r'],
    item_count: 1,
    item_digest: digest,
    currency: 'YER',
    supplier_name: 'Supplier',
    created_by: 'collector-user',
    created_by_name: 'Collector',
    created_by_role: 'collector',
    created_at: timestamp,
    last_updated: timestamp,
    history: history(),
    ...extra,
  };
}

function item({invoiceId = 'purchase-1', id = 'item-1', extra = {}} = {}) {
  return {
    id,
    invoice_id: invoiceId,
    schema_version: 1,
    workflow_version: 1,
    workflow_identity: 'purchase_invoice_v1',
    invoice_revision: 1,
    branch_ids: ['branch-r'],
    receiving_branch_id: 'branch-r',
    receiving_brand_id: 'brand-r',
    line_number: 1,
    item_id: id,
    source_type: 'unmatched',
    original_material_name: 'Material',
    original_group_text: '',
    original_unit_text: 'Unit',
    review_task_id: 'task-1',
    review_status: 'pending_review',
    ordered_quantity: 2,
    ...extra,
  };
}

function event({id = 'event-1', invoiceId = 'purchase-1', extra = {}} = {}) {
  return {
    id,
    invoice_id: invoiceId,
    workflow_version: 1,
    workflow_identity: 'purchase_invoice_v1',
    receiving_branch_id: 'branch-r',
    branch_ids: ['branch-r'],
    revision: 1,
    action: 'purchase_invoice_created',
    message: 'Public event',
    actor_id: 'collector-user',
    actor_name: 'Collector',
    actor_role: 'collector',
    created_at: timestamp,
    ...extra,
  };
}

async function seedPurchase({status = 'pendingReceiverReview'} = {}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const batch = writeBatch(database);
    batch.set(doc(database, 'purchase_invoices', 'purchase-1'), header({status}));
    batch.set(doc(database, 'purchase_invoices', 'purchase-1', 'items', 'item-1'), item());
    batch.set(doc(database, 'purchase_invoice_events', 'event-1'), event());
    batch.set(doc(database, 'purchase_invoice_prices', 'purchase-1'), {
      id: 'purchase-1', invoice_id: 'purchase-1', unit_price: 15, invoice_total: 30,
    });
    batch.set(doc(database, 'product_review_tasks', 'task-1'), {
      id: 'task-1', invoice_id: 'purchase-1', item_id: 'item-1', status: 'pending_review',
      brand_id: 'brand-r', updated_at: timestamp,
    });
    await batch.commit();
  });
}

test('purchase headers are branch-scoped for managers and role-constrained for queues', async () => {
  await seedPurchase();
  await assertSucceeds(getDoc(doc(db('manager-r'), 'purchase_invoices', 'purchase-1')));
  await assertFails(getDoc(doc(db('manager-x'), 'purchase_invoices', 'purchase-1')));
  for (const uid of ['collector-user', 'accountant-user', 'admin-user']) {
    await assertSucceeds(getDoc(doc(db(uid), 'purchase_invoices', 'purchase-1')));
  }
  for (const uid of ['employee-r', 'unknown-user', 'inactive-user', 'forced-user']) {
    await assertFails(getDoc(doc(db(uid), 'purchase_invoices', 'purchase-1')));
  }
  await assertSucceeds(getDocs(query(
    collection(db('manager-r'), 'purchase_invoices'),
    where('receiving_branch_id', '==', 'branch-r'),
    orderBy('last_updated', 'desc'),
    limit(100),
  )));
  await assertFails(getDocs(query(
    collection(db('manager-r'), 'purchase_invoices'),
    where('receiving_branch_id', '==', 'branch-x'),
    limit(100),
  )));
  await assertFails(getDocs(query(collection(db('manager-r'), 'purchase_invoices'), limit(100))));
  await assertFails(getDocs(query(collection(db('collector-user'), 'purchase_invoices'), limit(100))));
  await assertSucceeds(getDocs(query(
    collection(db('collector-user'), 'purchase_invoices'),
    where('status', '==', 'pendingPriceEntry'),
    limit(100),
  )));
});

test('public purchase items and events remain branch-scoped and reject injected price fields', async () => {
  await seedPurchase();
  await assertSucceeds(getDoc(doc(
    db('manager-r'), 'purchase_invoices', 'purchase-1', 'items', 'item-1',
  )));
  await assertFails(getDoc(doc(
    db('manager-x'), 'purchase_invoices', 'purchase-1', 'items', 'item-1',
  )));
  await assertSucceeds(getDocs(collection(
    db('manager-r'), 'purchase_invoices', 'purchase-1', 'items',
  )));
  await assertSucceeds(getDocs(query(
    collection(db('manager-r'), 'purchase_invoice_events'),
    where('invoice_id', '==', 'purchase-1'),
    where('receiving_branch_id', '==', 'branch-r'),
  )));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'purchase_invoices', 'bad-header'), header({
      id: 'bad-header', extra: {unit_price: 5},
    }));
    await setDoc(
      doc(context.firestore(), 'purchase_invoices', 'purchase-1', 'items', 'bad-item'),
      item({id: 'bad-item', extra: {line_total: 10}}),
    );
    await setDoc(doc(context.firestore(), 'purchase_invoice_events', 'bad-event'), event({
      id: 'bad-event', extra: {invoice_total: 10},
    }));
  });
  await assertFails(getDoc(doc(db('collector-user'), 'purchase_invoices', 'bad-header')));
  await assertFails(getDoc(doc(
    db('collector-user'), 'purchase_invoices', 'purchase-1', 'items', 'bad-item',
  )));
  await assertFails(getDoc(doc(db('collector-user'), 'purchase_invoice_events', 'bad-event')));
});

test('purchase prices, accounting data, and review tasks are denied to managers and employees', async () => {
  await seedPurchase();
  for (const uid of ['manager-r', 'manager-x', 'employee-r', 'unknown-user']) {
    await assertFails(getDoc(doc(db(uid), 'purchase_invoice_prices', 'purchase-1')));
    await assertFails(getDoc(doc(db(uid), 'product_review_tasks', 'task-1')));
  }
  for (const uid of ['collector-user', 'accountant-user', 'admin-user']) {
    await assertSucceeds(getDoc(doc(db(uid), 'purchase_invoice_prices', 'purchase-1')));
  }
  await assertSucceeds(getDoc(doc(db('accountant-user'), 'product_review_tasks', 'task-1')));
  await assertSucceeds(getDocs(query(
    collection(db('accountant-user'), 'product_review_tasks'),
    where('status', '==', 'pending_review'),
    orderBy('updated_at', 'desc'),
  )));
  await assertSucceeds(getDoc(doc(db('collector-user'), 'product_review_tasks', 'task-1')));
  await assertSucceeds(getDocs(query(
    collection(db('collector-user'), 'product_review_tasks'),
    where('status', '==', 'pending_review'),
    orderBy('updated_at', 'desc'),
  )));
});

test('all purchase workflow documents are backend-only for writes', async () => {
  await seedPurchase();
  for (const [collectionName, id] of [
    ['purchase_invoices', 'purchase-1'],
    ['purchase_invoice_events', 'event-1'],
    ['purchase_invoice_prices', 'purchase-1'],
    ['product_review_tasks', 'task-1'],
    ['purchase_invoice_commands', 'command-1'],
    ['purchase_invoice_unique_keys', 'key-1'],
  ]) {
    await assertFails(updateDoc(doc(db('accountant-user'), collectionName, id), {tampered: true}));
  }
  await assertFails(updateDoc(doc(
    db('manager-r'), 'purchase_invoices', 'purchase-1', 'items', 'item-1',
  ), {received_quantity: 2}));
});
