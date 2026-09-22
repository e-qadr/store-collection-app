import {after, before, beforeEach, test} from 'node:test';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {
  Timestamp, collection, deleteDoc, doc, getDoc, getDocs, query,
  runTransaction, serverTimestamp, setDoc, updateDoc, where,
} from 'firebase/firestore';
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
    await setDoc(doc(database, 'branch_transaction_counters', 'branch-a'), {
      branch_id: 'branch-a', branch_code: 'AA', next_number: 3,
    });
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

function reservedVoucher({id = 'reserved-1', number = 'AA003'} = {}) {
  return {
    ...voucher({status: 'reservedForCollection'}),
    id, transaction_number: number, collectorId: '',
    collection_workflow: 'accountant_reserved', reviewed_amount: 10,
    reviewed_by: 'accountant-a', reviewed_by_name: 'Accountant',
    reviewed_at: serverTimestamp(), reservation_at: serverTimestamp(),
    reservation_reference: 'review', physical_collection_completed: false,
    last_updated: serverTimestamp(),
  };
}

async function allocateVoucher(database, {id, reserved}) {
  const counterRef = doc(database, 'branch_transaction_counters', 'branch-a');
  const transactionRef = doc(database, 'transactions', id);
  return runTransaction(database, async (transaction) => {
    const counter = await transaction.get(counterRef);
    const next = counter.data().next_number;
    const number = `AA${String(next).padStart(3, '0')}`;
    const data = reserved
      ? reservedVoucher({id, number})
      : {...voucher(), id, transaction_number: number, collectorId: 'collector-a'};
    transaction.set(transactionRef, data);
    transaction.update(counterRef, {next_number: next + 1});
    return number;
  });
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

test('accountant may reserve a branch voucher but branch managers see only their own reservation', async () => {
  await assertSucceeds(setDoc(
    doc(db('accountant-a'), 'transactions', 'reserved-1'),
    reservedVoucher(),
  ));
  await assertFails(setDoc(
    doc(db('manager-a'), 'transactions', 'reserved-manager'),
    reservedVoucher({id: 'reserved-manager', number: 'AA004'}),
  ));
  await assertSucceeds(getDoc(doc(db('manager-a'), 'transactions', 'reserved-1')));
  await assertFails(getDoc(doc(db('manager-b'), 'transactions', 'reserved-1')));
  await assertSucceeds(getDocs(query(
    collection(db('manager-a'), 'transactions'), where('branchId', '==', 'branch-a'),
  )));
});

test('direct and accountant reservations allocate distinct numbers from one shared counter', async () => {
  const reservedNumber = await allocateVoucher(
    db('accountant-a'), {id: 'reserved-concurrent', reserved: true},
  );
  const directNumber = await allocateVoucher(
    db('collector-a'), {id: 'direct-concurrent', reserved: false},
  );
  const numbers = new Set([reservedNumber, directNumber]);
  if (numbers.size !== 2) throw new Error('counter allocated a duplicate voucher number');
  const counter = await getDoc(doc(db('collector-a'), 'branch_transaction_counters', 'branch-a'));
  if (counter.data().next_number !== 5) throw new Error('counter did not advance atomically');
});

test('concurrent Collection allocations never duplicate a branch voucher number', async () => {
  // This exercises Firestore's transaction retry/serialization itself. Role
  // boundaries are asserted separately above; disabling rules avoids the
  // emulator's concurrent-auth evaluation limit from masking the atomicity
  // assertion.
  await environment.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    const [first, second] = await Promise.all([
      allocateVoucher(database, {id: 'direct-concurrent-a', reserved: false}),
      allocateVoucher(database, {id: 'direct-concurrent-b', reserved: false}),
    ]);
    if (new Set([first, second]).size !== 2) {
      throw new Error('concurrent Collection allocations produced a duplicate number');
    }
    const counter = await getDoc(doc(database, 'branch_transaction_counters', 'branch-a'));
    if (counter.data().next_number !== 5) throw new Error('counter did not advance twice');
  });
});

test('only collector records physical receipt and cannot silently overwrite reviewed amount', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'transactions', 'reserved-1'), {
      ...reservedVoucher(),
      reviewed_at: timestamp, reservation_at: timestamp, last_updated: timestamp,
    });
  });
  const ref = doc(db('collector-a'), 'transactions', 'reserved-1');
  await assertFails(updateDoc(ref, {
    amount: 99, status: 'pending', collectorId: 'collector-a',
    physical_collection_completed: true, physical_collected_by: 'collector-a',
    physical_collected_by_name: 'Collector', physical_collected_at: serverTimestamp(),
    physical_collection_amount: 99, last_updated: serverTimestamp(), history: history(),
  }));
  await assertSucceeds(updateDoc(ref, {
    status: 'pending', collectorId: 'collector-a',
    physical_collection_completed: true, physical_collected_by: 'collector-a',
    physical_collected_by_name: 'Collector', physical_collected_at: serverTimestamp(),
    physical_collection_amount: 10, last_updated: serverTimestamp(), history: history(),
  }));
  const completed = await getDoc(ref);
  if (completed.data().transaction_number !== 'AA003') {
    throw new Error('physical collection changed the accountant-reserved number');
  }
});

test('amount differences require accountant review, while cancelled reservation numbers are not reused', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'transactions', 'reserved-1'), {
      ...reservedVoucher(), reviewed_at: timestamp, reservation_at: timestamp, last_updated: timestamp,
    });
  });
  const collectorRef = doc(db('collector-a'), 'transactions', 'reserved-1');
  await assertSucceeds(updateDoc(collectorRef, {
    status: 'collectionDifferencePendingReview', collectorId: 'collector-a',
    physical_collection_completed: true, physical_collected_by: 'collector-a',
    physical_collected_by_name: 'Collector', physical_collected_at: serverTimestamp(),
    physical_collection_amount: 12, collection_difference: 2,
    collection_difference_reason: 'Cashier count differs', last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(updateDoc(collectorRef, {
    status: 'pending', amount: 12, last_updated: serverTimestamp(), history: history(),
  }));
  await assertSucceeds(updateDoc(doc(db('accountant-a'), 'transactions', 'reserved-1'), {
    status: 'pending', amount: 12, difference_reviewed_by: 'accountant-a',
    difference_reviewed_by_name: 'Accountant', difference_reviewed_at: serverTimestamp(),
    accountant_notes: 'Reviewed', last_updated: serverTimestamp(), history: history(),
  }));

  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'transactions', 'reserved-cancel'), {
      ...reservedVoucher({id: 'reserved-cancel', number: 'AA003'}),
      reviewed_at: timestamp, reservation_at: timestamp, last_updated: timestamp,
    });
    await setDoc(doc(context.firestore(), 'branch_transaction_counters', 'branch-a'), {
      branch_id: 'branch-a', branch_code: 'AA', next_number: 4,
    });
  });
  await assertSucceeds(updateDoc(doc(db('accountant-a'), 'transactions', 'reserved-cancel'), {
    status: 'reservedCancelled', reservation_cancelled_by: 'accountant-a',
    reservation_cancelled_by_name: 'Accountant', reservation_cancelled_at: serverTimestamp(),
    reservation_cancellation_reason: 'Income duplicated', last_updated: serverTimestamp(), history: history(),
  }));
  const nextNumber = await allocateVoucher(db('collector-a'), {id: 'after-cancel', reserved: false});
  if (nextNumber === 'AA003') throw new Error('cancelled reservation number was reused');
});
