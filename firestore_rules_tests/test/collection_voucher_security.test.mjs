import {after, before, beforeEach, test} from 'node:test';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {Timestamp, deleteDoc, doc, setDoc, serverTimestamp, updateDoc} from 'firebase/firestore';
import {readFile} from 'node:fs/promises';

const projectId = 'demo-store-collection-vouchers';
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
      ['collector-a', 'collector', ''], ['manager-a', 'manager', 'branch-a'],
      ['manager-b', 'manager', 'branch-b'], ['accountant-a', 'accountant', ''],
      ['employee-a', 'employee', 'branch-a'],
    ]) {
      await setDoc(doc(database, 'users', uid), {role, isActive: true, mustChangePassword: false, ...(branchId ? {branchId} : {})});
    }
    await setDoc(doc(database, 'transactions', 'voucher-1'), voucher());
  });
});

function db(uid) { return environment.authenticatedContext(uid).firestore(); }
function history() { return [{action: 'created', actor_role: 'collector', timestamp}]; }
function voucher({status = 'pending'} = {}) {
  return {
    id: 'voucher-1', transaction_number: 'AA000', branchId: 'branch-a', branch_code: 'AA',
    collectorId: 'collector-a', amount: 10, currency: 'YER', amount_matches: null,
    dateFrom: timestamp, dateTo: timestamp, transaction_date: timestamp, timestamp,
    notes: '', status, history: history(), last_updated: timestamp,
  };
}

test('only the recorded collector can create a Collection voucher', async () => {
  const created = {...voucher(), id: 'voucher-2', transaction_number: 'AA001'};
  await assertSucceeds(setDoc(doc(db('collector-a'), 'transactions', 'voucher-2'), created));
  await assertFails(setDoc(doc(db('employee-a'), 'transactions', 'voucher-3'), {
    ...created, id: 'voucher-3', collectorId: 'employee-a',
  }));
});

test('only the receiving branch manager may make the pending decision', async () => {
  const change = {status: 'approvedByManager', last_updated: serverTimestamp(), history: history()};
  await assertSucceeds(updateDoc(doc(db('manager-a'), 'transactions', 'voucher-1'), change));
  await assertFails(updateDoc(doc(db('manager-b'), 'transactions', 'voucher-1'), {
    status: 'rejectedByManager', manager_notes: 'not mine', last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(updateDoc(doc(db('employee-a'), 'transactions', 'voucher-1'), change));
});

test('final vouchers cannot be rewritten or hard-deleted by clients', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'transactions', 'voucher-1'), voucher({status: 'approvedByAccountant'}));
  });
  await assertFails(updateDoc(doc(db('manager-a'), 'transactions', 'voucher-1'), {
    amount: 999, last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(deleteDoc(doc(db('accountant-a'), 'transactions', 'voucher-1')));
});

test('the accountant may finalize only the manager-approved voucher', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'transactions', 'voucher-1'), voucher({status: 'approvedByManager'}));
  });
  await assertSucceeds(updateDoc(doc(db('accountant-a'), 'transactions', 'voucher-1'), {
    status: 'approvedByAccountant', accountant_notes: 'Posted', last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(updateDoc(doc(db('collector-a'), 'transactions', 'voucher-1'), {
    status: 'approvedByManager', last_updated: serverTimestamp(), history: history(),
  }));
});
