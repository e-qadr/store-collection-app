import {after, before, beforeEach, test} from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {readFile} from 'node:fs/promises';
import {
  Timestamp,
  deleteDoc,
  doc,
  setDoc,
  serverTimestamp,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-store-collection-consumables';
const timestamp = Timestamp.fromMillis(1_780_000_000_000);
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
    for (const [uid, role, branchId] of [
      ['manager-r', 'manager', 'branch-r'],
      ['manager-x', 'manager', 'branch-x'],
      ['collector-user', 'collector', ''],
      ['accountant-user', 'accountant', ''],
      ['employee-r', 'employee', 'branch-r'],
    ]) {
      await setDoc(doc(database, 'users', uid), {
        role, isActive: true, mustChangePassword: false,
        ...(branchId ? {branchId} : {}),
      });
    }
    await setDoc(doc(database, 'consumable_requests', 'request-1'), request());
  });
});

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function history(action = 'request_created') {
  return [{
    action,
    actor_id: 'manager-r',
    actor_name: 'Manager',
    actor_role: 'manager',
    timestamp,
  }];
}

function request({status = 'pendingCollectorReview'} = {}) {
  return {
    id: 'request-1',
    request_number: 'CR-0001',
    branch_id: 'branch-r',
    branch_name: 'R',
    items: [{name: 'Material', unit: 'Piece', requested_quantity: 2, collector_quantity: 2}],
    item_name: 'Material', unit: 'Piece', requested_quantity: 2, collector_quantity: 2,
    status, created_by: 'manager-r', created_at: timestamp, last_updated: timestamp,
    history: history(),
  };
}

test('only the assigned manager can create a pending consumable request', async () => {
  const created = {
    ...request(), id: 'request-2', request_number: 'CR-0002',
    created_at: serverTimestamp(), last_updated: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(db('manager-r'), 'consumable_requests', 'request-2'), created));
  await assertFails(setDoc(doc(db('manager-x'), 'consumable_requests', 'request-3'), {
    ...created, id: 'request-3', created_by: 'manager-x',
  }));
});

test('collector rejection requires a reason and preserves the request', async () => {
  const reference = doc(db('collector-user'), 'consumable_requests', 'request-1');
  await assertFails(updateDoc(reference, {
    status: 'rejectedByCollector', rejection_reason: '', rejected_by: 'collector-user',
    rejected_by_name: 'Collector', rejected_by_role: 'collector',
    rejected_at: serverTimestamp(), last_updated: serverTimestamp(), history: history('collector_rejected'),
  }));
  await assertSucceeds(updateDoc(reference, {
    status: 'rejectedByCollector', rejection_reason: 'Quantity cannot be supplied',
    rejected_by: 'collector-user', rejected_by_name: 'Collector', rejected_by_role: 'collector',
    rejected_at: serverTimestamp(), last_updated: serverTimestamp(), history: history('collector_rejected'),
  }));
  await assertFails(deleteDoc(reference));
});

test('accountant rejection is available only after collector review', async () => {
  const accountantRef = doc(db('accountant-user'), 'consumable_requests', 'request-1');
  await assertFails(updateDoc(accountantRef, {
    status: 'rejectedByAccountant', rejection_reason: 'No accounting approval',
    rejected_by: 'accountant-user', rejected_by_name: 'Accountant', rejected_by_role: 'accountant',
    rejected_at: serverTimestamp(), last_updated: serverTimestamp(), history: history('accountant_rejected'),
  }));
  await environment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), 'consumable_requests', 'request-1'), {
      status: 'pendingAccountingApproval', reviewed_by: 'collector-user', reviewed_at: timestamp,
    });
  });
  await assertSucceeds(updateDoc(accountantRef, {
    status: 'rejectedByAccountant', rejection_reason: 'No accounting approval',
    rejected_by: 'accountant-user', rejected_by_name: 'Accountant', rejected_by_role: 'accountant',
    rejected_at: serverTimestamp(), last_updated: serverTimestamp(), history: history('accountant_rejected'),
  }));
  await assertFails(updateDoc(doc(db('employee-r'), 'consumable_requests', 'request-1'), {
    status: 'pendingAccountingApproval', last_updated: serverTimestamp(), history: history('tamper'),
  }));
});
