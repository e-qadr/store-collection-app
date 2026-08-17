import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFile } from 'node:fs/promises';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-store-collection-inter-branch';
const brandA = 'brand-a';
const brandB = 'brand-b';
const fixedTimestamp = Timestamp.fromMillis(1_750_000_000_000);
const digest = 'a'.repeat(64);

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
    const batch = writeBatch(database);
    batch.set(doc(database, 'branches', 'branch-a'), {
      id: 'branch-a', name: 'A', brand_id: brandA, branch_code: 'AA',
    });
    batch.set(doc(database, 'branches', 'branch-b'), {
      id: 'branch-b', name: 'B', brand_id: brandB, branch_code: 'BB',
    });
    batch.set(doc(database, 'branches', 'branch-c'), {
      id: 'branch-c', name: 'C', brand_id: brandA, branch_code: 'CC',
    });
    for (const [uid, role, branchId, extra] of [
      ['manager-a', 'manager', 'branch-a', {}],
      ['manager-b', 'manager', 'branch-b', {}],
      ['manager-c', 'manager', 'branch-c', {}],
      ['manager-unassigned', 'manager', null, {branchId: null}],
      ['collector-user', 'collector', '', {}],
      ['accountant-user', 'accountant', '', {}],
      ['admin-user', 'admin', '', {}],
      ['employee-user', 'employee', 'branch-a', {}],
      ['unknown-user', 'mystery', 'branch-a', {}],
      ['inactive-user', 'manager', 'branch-a', {isActive: false}],
      ['password-user', 'manager', 'branch-a', {mustChangePassword: true}],
    ]) {
      batch.set(doc(database, 'users', uid), {
        role,
        isActive: true,
        mustChangePassword: false,
        ...(branchId ? {branchId} : {}),
        ...extra,
      });
    }
    await batch.commit();
  });
});

function databaseFor(uid) {
  return testEnvironment.authenticatedContext(uid).firestore();
}

async function seed(collectionName, id, data) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), collectionName, id), data);
  });
}

function v2Item(index = 0, extra = {}, invoiceId = 'invoice-v2') {
  const itemId = `item-${index}`;
  return {
    id: itemId,
    invoice_id: invoiceId,
    schema_version: 2,
    workflow_version: 2,
    creation_mode: 'direct_supplier_invoice',
    invoice_revision: 1,
    branch_ids: ['branch-a', 'branch-b'],
    sending_branch_id: 'branch-a',
    receiving_branch_id: 'branch-b',
    line_number: index + 1,
    item_id: itemId,
    product_id: `product-${index}`,
    product_version: 1,
    product_brand_id: brandA,
    product_name: `Product ${index}`,
    group_id: 'group-a',
    group_name: 'Group A',
    unit_id: 'primary',
    unit_value: 'حبة',
    unit_raw_value: 'حبه',
    supplied_quantity: index + 1,
    ...extra,
  };
}

function publicHistory(action = 'direct_invoice_created', extra = {}) {
  return {
    action,
    message: 'Public non-price event',
    actor_id: 'manager-a',
    actor_name: 'Manager A',
    actor_role: 'manager',
    timestamp: fixedTimestamp,
    ...extra,
  };
}

function v2Invoice({
  id = 'invoice-v2',
  status = 'pendingReceiverReview',
  itemCount = 1,
  extra = {},
} = {}) {
  const received = status !== 'pendingReceiverReview';
  const posted = status === 'postedToAccounting';
  return {
    id,
    schema_version: 2,
    workflow_version: 2,
    creation_mode: 'direct_supplier_invoice',
    status,
    revision: status === 'pendingReceiverReview' ? 1 : posted ? 4 : 2,
    invoice_number: 'AA0042',
    branch_code: 'AA',
    sending_branch_id: 'branch-a',
    sending_branch_name: 'A',
    sending_brand_id: brandA,
    receiving_branch_id: 'branch-b',
    receiving_branch_name: 'B',
    receiving_brand_id: brandB,
    branch_ids: ['branch-a', 'branch-b'],
    item_count: itemCount,
    item_digest: digest,
    ...(received ? {
      receipt_confirmed_by: 'manager-b',
      receipt_confirmed_by_name: 'Manager B',
      receipt_confirmed_at: fixedTimestamp,
    } : {}),
    ...(posted ? {
      accounting_reference: 'ACCOUNTING-42',
      posted_by: 'accountant-user',
      posted_by_name: 'Accountant',
      posted_at: fixedTimestamp,
    } : {}),
    created_by: 'manager-a',
    created_by_name: 'Manager A',
    created_by_role: 'manager',
    created_at: fixedTimestamp,
    last_updated: fixedTimestamp,
    history: [publicHistory()],
    ...extra,
  };
}

async function seedV2InvoiceWithItems({
  id = 'invoice-v2',
  itemCount = 1,
  status = 'pendingReceiverReview',
} = {}) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const batch = writeBatch(database);
    batch.set(doc(database, 'inter_branch_invoices', id), v2Invoice({
      id,
      itemCount,
      status,
    }));
    for (let index = 0; index < itemCount; index += 1) {
      const received = status === 'pendingReceiverReview' ? {} : {
        received_quantity: index + 1,
        damaged_quantity: 0,
        missing_quantity: 0,
      };
      const item = v2Item(index, received, id);
      batch.set(doc(database, 'inter_branch_invoices', id, 'items', item.id), item);
    }
    await batch.commit();
  });
}

function legacyInvoice({id = 'legacy-request', status = 'requestPending'} = {}) {
  return {
    id,
    status,
    sending_branch_id: 'branch-a',
    sending_branch_name: 'A',
    receiving_branch_id: 'branch-b',
    receiving_branch_name: 'B',
    branch_ids: ['branch-a', 'branch-b'],
    item_name: 'Legacy product',
    requested_quantity: 1,
    unit: 'حبة',
    created_by: 'manager-b',
    created_at: fixedTimestamp,
    last_updated: fixedTimestamp,
    history: [],
  };
}

test('v2 public invoices are readable only by participant managers and supervisors', async () => {
  await seed('inter_branch_invoices', 'invoice-v2', v2Invoice());

  for (const uid of [
    'manager-a', 'manager-b', 'collector-user', 'accountant-user', 'admin-user',
  ]) {
    await assertSucceeds(getDoc(doc(databaseFor(uid), 'inter_branch_invoices', 'invoice-v2')));
  }
  for (const uid of [
    'manager-c', 'manager-unassigned', 'employee-user', 'unknown-user', 'inactive-user', 'password-user',
  ]) {
    await assertFails(getDoc(doc(databaseFor(uid), 'inter_branch_invoices', 'invoice-v2')));
  }
  const managerA = databaseFor('manager-a');
  await assertSucceeds(getDocs(query(
    collection(managerA, 'inter_branch_invoices'),
    where('branch_ids', 'array-contains', 'branch-a'),
    limit(50),
  )));

  await seed('inter_branch_invoices', 'invoice-id-mismatch', v2Invoice({
    id: 'different-invoice-id',
  }));
  await assertFails(getDoc(doc(
    databaseFor('manager-a'), 'inter_branch_invoices', 'invoice-id-mismatch',
  )));
  await assertFails(getDocs(query(
    collection(managerA, 'inter_branch_invoices'),
    limit(50),
  )));
  await assertFails(getDocs(query(
    collection(managerA, 'inter_branch_invoices'),
    where('branch_ids', 'array-contains', 'branch-c'),
    limit(50),
  )));
});

test('manager without a branch is denied all branch-scoped inter-branch reads', async () => {
  await seed('inter_branch_invoices', 'invoice-v2', v2Invoice());
  const manager = databaseFor('manager-unassigned');
  await assertFails(getDoc(doc(manager, 'inter_branch_invoices', 'invoice-v2')));
  await assertFails(getDocs(query(
    collection(manager, 'inter_branch_invoices'),
    where('branch_ids', 'array-contains', 'branch-a'),
    limit(50),
  )));
});

test('closed public fields and backend-only writes deny client price smuggling', async () => {
  const variants = {
    top: v2Invoice({id: 'bad-top', extra: {unit_price: 10}}),
    history: v2Invoice({
      id: 'bad-history',
      extra: {history: [publicHistory('created', {changes: {total_price: 10}})]},
    }),
    currency: v2Invoice({id: 'bad-currency', extra: {currency: 'YER'}}),
    accountingNote: v2Invoice({
      id: 'bad-accounting-note',
      status: 'postedToAccounting',
      extra: {accounting_notes: 'private'},
    }),
  };
  for (const [id, data] of Object.entries(variants)) {
    await seed('inter_branch_invoices', id, {...data, id});
    await assertFails(getDoc(doc(databaseFor('manager-a'), 'inter_branch_invoices', id)));
    await assertFails(getDoc(doc(databaseFor('collector-user'), 'inter_branch_invoices', id)));
  }

  await assertFails(setDoc(
    doc(databaseFor('manager-a'), 'inter_branch_invoices', 'bad-item'),
    v2Invoice({id: 'bad-item'}),
  ));
});

test('50-item headers remain readable while invalid item counts fail closed', async () => {
  await seed('inter_branch_invoices', 'max-lines', v2Invoice({
    id: 'max-lines', itemCount: 50,
  }));
  await seed('inter_branch_invoices', 'too-many-lines', v2Invoice({
    id: 'too-many-lines', itemCount: 51,
  }));
  await assertSucceeds(getDoc(doc(
    databaseFor('manager-a'), 'inter_branch_invoices', 'max-lines',
  )));
  await assertFails(getDoc(doc(
    databaseFor('manager-a'), 'inter_branch_invoices', 'too-many-lines',
  )));
});

test('v2 item subcollection is branch-scoped, closed, and backend-only', async () => {
  await seedV2InvoiceWithItems({itemCount: 50});
  const itemPath = ['inter_branch_invoices', 'invoice-v2', 'items', 'item-0'];
  for (const uid of [
    'manager-a', 'manager-b', 'collector-user', 'accountant-user', 'admin-user',
  ]) {
    await assertSucceeds(getDoc(doc(databaseFor(uid), ...itemPath)));
  }
  for (const uid of [
    'manager-c', 'employee-user', 'unknown-user', 'inactive-user', 'password-user',
  ]) {
    await assertFails(getDoc(doc(databaseFor(uid), ...itemPath)));
  }

  const managerAItems = collection(
    databaseFor('manager-a'),
    'inter_branch_invoices',
    'invoice-v2',
    'items',
  );
  await assertSucceeds(getDocs(query(
    managerAItems,
    where('branch_ids', 'array-contains', 'branch-a'),
    orderBy('line_number'),
    limit(50),
  )));
  await assertFails(getDocs(query(
    managerAItems,
    orderBy('line_number'),
    limit(50),
  )));
  await assertFails(getDocs(query(
    managerAItems,
    where('branch_ids', 'array-contains', 'branch-c'),
    orderBy('line_number'),
    limit(50),
  )));
  await assertSucceeds(getDocs(query(
    managerAItems,
    where('branch_ids', 'array-contains', 'branch-a'),
    orderBy('line_number'),
  )));

  const managerA = databaseFor('manager-a');
  await assertFails(setDoc(
    doc(managerA, 'inter_branch_invoices', 'invoice-v2', 'items', 'client-item'),
    v2Item(50, {id: 'client-item', item_id: 'client-item'}),
  ));
  await assertFails(updateDoc(doc(managerA, ...itemPath), {supplied_quantity: 99}));
  await assertFails(deleteDoc(doc(managerA, ...itemPath)));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, ...itemPath), v2Item(0, {unit_price: 10}));
  });
  await assertFails(getDoc(doc(databaseFor('manager-a'), ...itemPath)));
  await assertFails(getDoc(doc(databaseFor('collector-user'), ...itemPath)));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, ...itemPath), v2Item(0, {
      line_notes: {nested_total: 10},
    }));
  });
  await assertFails(getDoc(doc(databaseFor('manager-a'), ...itemPath)));
  await assertFails(getDoc(doc(databaseFor('collector-user'), ...itemPath)));
});

test('all direct v2 client writes and replays are backend-only', async () => {
  const managerA = databaseFor('manager-a');
  const managerB = databaseFor('manager-b');
  const collector = databaseFor('collector-user');
  await assertFails(setDoc(
    doc(managerA, 'inter_branch_invoices', 'client-create'),
    v2Invoice({id: 'client-create'}),
  ));
  await seed('inter_branch_invoices', 'invoice-v2', v2Invoice());
  await assertFails(updateDoc(doc(managerB, 'inter_branch_invoices', 'invoice-v2'), {
    status: 'pendingPriceEntry',
  }));
  await assertFails(updateDoc(doc(managerA, 'inter_branch_invoices', 'invoice-v2'), {
    sending_branch_id: 'branch-c',
  }));
  await assertFails(updateDoc(doc(collector, 'inter_branch_invoices', 'invoice-v2'), {
    status: 'pendingAccountingEntry',
  }));
  await assertFails(deleteDoc(doc(managerA, 'inter_branch_invoices', 'invoice-v2')));
});

test('protected invoice and product prices are readable only by protected roles and never client-writable', async () => {
  const protectedSnapshot = {
    id: 'invoice-v2',
    invoice_id: 'invoice-v2',
    invoice_revision: 2,
    pricing_revision: 1,
    currency: 'YER',
    items: [{item_id: 'item-0', unit_price: 10, line_total: 10}],
    invoice_total: 10,
    confirmed_by: 'collector-user',
    confirmed_at: fixedTimestamp,
    locked: true,
  };
  await seed('inter_branch_invoice_prices', 'invoice-v2', protectedSnapshot);
  await seed('inter_branch_invoice_price_history', 'history-v2', {
    id: 'history-v2', invoice_id: 'invoice-v2', price_fields: {total_price: 10},
  });
  await seed('product_price_latest', 'latest-v2', {price: 10});
  await seed('product_price_history', 'product-history-v2', {price: 10});

  for (const uid of ['collector-user', 'accountant-user', 'admin-user']) {
    const database = databaseFor(uid);
    await assertSucceeds(getDoc(doc(database, 'inter_branch_invoice_prices', 'invoice-v2')));
    await assertSucceeds(getDocs(collection(database, 'inter_branch_invoice_prices')));
    await assertSucceeds(getDocs(collection(database, 'inter_branch_invoice_price_history')));
    await assertSucceeds(getDoc(doc(database, 'product_price_latest', 'latest-v2')));
  }
  for (const uid of ['manager-a', 'manager-b', 'employee-user', 'unknown-user']) {
    const database = databaseFor(uid);
    await assertFails(getDoc(doc(database, 'inter_branch_invoice_prices', 'invoice-v2')));
    await assertFails(getDocs(collection(database, 'inter_branch_invoice_prices')));
    await assertFails(getDoc(doc(database, 'inter_branch_invoice_price_history', 'history-v2')));
    await assertFails(getDoc(doc(database, 'product_price_latest', 'latest-v2')));
  }

  for (const uid of ['collector-user', 'accountant-user', 'admin-user', 'manager-a']) {
    const database = databaseFor(uid);
    await assertFails(setDoc(
      doc(database, 'inter_branch_invoice_prices', `client-${uid}`),
      protectedSnapshot,
    ));
    await assertFails(updateDoc(
      doc(database, 'inter_branch_invoice_prices', 'invoice-v2'),
      {locked: false},
    ));
    await assertFails(setDoc(
      doc(database, 'product_price_latest', `client-${uid}`),
      {price: 99},
    ));
  }
});

test('private command receipts deny every direct read and write', async () => {
  await seed('inter_branch_invoice_commands', 'command-a', {
    id: 'command-a', command: 'create', actor_uid: 'manager-a', request_hash: 'hash',
  });
  for (const uid of ['manager-a', 'collector-user', 'accountant-user', 'admin-user']) {
    const database = databaseFor(uid);
    await assertFails(getDoc(doc(database, 'inter_branch_invoice_commands', 'command-a')));
    await assertFails(setDoc(doc(database, 'inter_branch_invoice_commands', `new-${uid}`), {
      id: `new-${uid}`,
    }));
  }
});

test('public v2 events follow invoice branch visibility and reject nested additions', async () => {
  const event = {
    id: 'event-a',
    invoice_id: 'invoice-v2',
    workflow_version: 2,
    branch_ids: ['branch-a', 'branch-b'],
    revision: 1,
    action: 'direct_invoice_created',
    message: 'Created',
    actor_id: 'manager-a',
    actor_name: 'Manager A',
    actor_role: 'manager',
    created_at: fixedTimestamp,
  };
  await seed('inter_branch_invoice_events', 'event-a', event);
  await seed('inter_branch_invoice_events', 'event-bad', {
    ...event, id: 'event-bad', changes: {total_price: 10},
  });
  await seed('inter_branch_invoice_events', 'event-id-mismatch', {
    ...event, id: 'different-event-id',
  });
  await assertSucceeds(getDoc(doc(
    databaseFor('manager-b'), 'inter_branch_invoice_events', 'event-a',
  )));
  await assertFails(getDoc(doc(
    databaseFor('manager-c'), 'inter_branch_invoice_events', 'event-a',
  )));
  await assertFails(getDoc(doc(
    databaseFor('collector-user'), 'inter_branch_invoice_events', 'event-bad',
  )));
  await assertFails(getDoc(doc(
    databaseFor('collector-user'), 'inter_branch_invoice_events', 'event-id-mismatch',
  )));
  await assertFails(setDoc(
    doc(databaseFor('manager-a'), 'inter_branch_invoice_events', 'client-event'),
    {...event, id: 'client-event'},
  ));
});

test('legacy reads are participant-scoped and only expected request decision remains writable', async () => {
  await seed('inter_branch_invoices', 'legacy-request', legacyInvoice());
  for (const uid of ['manager-a', 'manager-b', 'collector-user', 'accountant-user']) {
    await assertSucceeds(getDoc(doc(
      databaseFor(uid), 'inter_branch_invoices', 'legacy-request',
    )));
  }
  for (const uid of ['manager-c', 'unknown-user', 'inactive-user']) {
    await assertFails(getDoc(doc(
      databaseFor(uid), 'inter_branch_invoices', 'legacy-request',
    )));
  }
  await assertFails(setDoc(
    doc(databaseFor('manager-b'), 'inter_branch_invoices', 'new-legacy'),
    legacyInvoice({id: 'new-legacy'}),
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-b'), 'inter_branch_invoices', 'legacy-request'),
    {status: 'pendingReceiverReview'},
  ));
  const approvedItems = [{
    name: 'Legacy product',
    unit: 'حبة',
    requested_quantity: 1,
    approved_quantity: 1,
    received_quantity: 1,
  }];
  const approvalUpdate = {
    status: 'pendingReceiverReview',
    invoice_number: 'AA0001',
    invoice_created_at: serverTimestamp(),
    approved_by: 'manager-a',
    approved_at: serverTimestamp(),
    approved_quantity: 1,
    items: approvedItems,
    last_updated: serverTimestamp(),
    history: [publicHistory('supplier_approved_invoice_created')],
  };
  await assertFails(updateDoc(
    doc(databaseFor('manager-a'), 'inter_branch_invoices', 'legacy-request'),
    {...approvalUpdate, unit_price: 99},
  ));
  await assertSucceeds(updateDoc(
    doc(databaseFor('manager-a'), 'inter_branch_invoices', 'legacy-request'),
    approvalUpdate,
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-a'), 'inter_branch_invoices', 'legacy-request'),
    {status: 'pendingReceiverReview'},
  ));

  await seed('inter_branch_invoices', 'legacy-receipt', {
    ...legacyInvoice({id: 'legacy-receipt', status: 'pendingReceiverReview'}),
    invoice_number: 'AA0002',
    items: approvedItems,
    history: [publicHistory('supplier_approved_invoice_created')],
  });
  const receiptUpdate = {
    status: 'pendingPriceEntry',
    received_quantity: 1,
    items: approvedItems,
    last_updated: serverTimestamp(),
    history: [
      publicHistory('supplier_approved_invoice_created'),
      publicHistory('receiver_confirmed'),
    ],
  };
  await assertFails(updateDoc(
    doc(databaseFor('manager-b'), 'inter_branch_invoices', 'legacy-receipt'),
    {...receiptUpdate, total_price: 99},
  ));
  await assertSucceeds(updateDoc(
    doc(databaseFor('manager-b'), 'inter_branch_invoices', 'legacy-receipt'),
    receiptUpdate,
  ));

  await seed('inter_branch_invoices', 'legacy-posted', legacyInvoice({
    id: 'legacy-posted', status: 'postedToAccounting',
  }));
  await assertFails(updateDoc(
    doc(databaseFor('accountant-user'), 'inter_branch_invoices', 'legacy-posted'),
    {accountant_notes: 'ordinary silent rewrite'},
  ));
});

test('legacy counters are branch-manager scoped and strictly increment by one', async () => {
  const managerA = databaseFor('manager-a');
  await assertFails(setDoc(
    doc(databaseFor('manager-b'), 'inter_branch_invoice_counters', 'branch-a'),
    {
      branch_id: 'branch-a', branch_code: 'AA', next_number: 1,
      last_invoice_number: 'AA0000', last_updated: serverTimestamp(),
    },
  ));
  await assertSucceeds(setDoc(
    doc(managerA, 'inter_branch_invoice_counters', 'branch-a'),
    {
      branch_id: 'branch-a', branch_code: 'AA', next_number: 1,
      last_invoice_number: 'AA0000', last_updated: serverTimestamp(),
    },
  ));
  await assertFails(updateDoc(
    doc(managerA, 'inter_branch_invoice_counters', 'branch-a'),
    {next_number: 3, last_invoice_number: 'AA0002', last_updated: serverTimestamp()},
  ));
  await assertSucceeds(updateDoc(
    doc(managerA, 'inter_branch_invoice_counters', 'branch-a'),
    {next_number: 2, last_invoice_number: 'AA0001', last_updated: serverTimestamp()},
  ));
});

test('notification recipients retain read and device delivery updates while v2 creation is backend-only', async () => {
  const v2Notification = {
    id: 'notification-v2',
    recipient_id: 'manager-b',
    title: 'New invoice',
    message: 'Public notification',
    is_read: false,
    push_status: 'pending',
    module: 'inter_branch_invoices',
    entity_collection: 'inter_branch_invoices',
    entity_id: 'invoice-v2',
    notification_type: 'inter_branch_v2_direct_created',
    created_at: fixedTimestamp,
  };
  await seed('notifications', 'notification-v2', v2Notification);
  await assertSucceeds(getDoc(doc(
    databaseFor('manager-b'), 'notifications', 'notification-v2',
  )));
  await assertFails(getDoc(doc(
    databaseFor('manager-a'), 'notifications', 'notification-v2',
  )));
  await assertSucceeds(updateDoc(
    doc(databaseFor('manager-b'), 'notifications', 'notification-v2'),
    {is_read: true, read_at: serverTimestamp()},
  ));
  await assertSucceeds(updateDoc(
    doc(databaseFor('manager-b'), 'notifications', 'notification-v2'),
    {
      device_received_at: serverTimestamp(),
      device_received_state: 'foreground',
      device_platform: 'android',
    },
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-a'), 'notifications', 'notification-v2'),
    {
      device_received_at: serverTimestamp(),
      device_received_state: 'foreground',
      device_platform: 'android',
    },
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-b'), 'notifications', 'notification-v2'),
    {
      device_received_at: serverTimestamp(),
      device_received_state: 'forged-state',
      device_platform: 'android',
    },
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-b'), 'notifications', 'notification-v2'),
    {
      device_received_at: serverTimestamp(),
      device_received_state: 'opened',
      device_platform: 'untrusted-platform',
    },
  ));
  await assertFails(updateDoc(
    doc(databaseFor('manager-b'), 'notifications', 'notification-v2'),
    {message: 'rewritten'},
  ));
  await assertFails(setDoc(
    doc(databaseFor('manager-a'), 'notifications', 'client-v2'),
    {...v2Notification, id: 'client-v2'},
  ));
  await assertSucceeds(setDoc(
    doc(databaseFor('manager-a'), 'notifications', 'legacy-notification'),
    {
      ...v2Notification,
      id: 'legacy-notification',
      notification_type: 'inter_branch_request_created',
    },
  ));
  await assertSucceeds(setDoc(
    doc(databaseFor('employee-user'), 'notifications', 'other-module'),
    {
      id: 'other-module', recipient_id: 'employee-user', module: 'transactions',
      notification_type: 'transaction_created', is_read: false,
    },
  ));
});
