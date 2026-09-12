import {after, before, beforeEach, test} from 'node:test';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {Timestamp, deleteDoc, doc, setDoc, serverTimestamp, updateDoc} from 'firebase/firestore';
import {readFile} from 'node:fs/promises';

const projectId = 'demo-store-collection-expenses';
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
      ['manager-a', 'manager', 'branch-a'], ['manager-b', 'manager', 'branch-b'],
      ['collector-a', 'collector', ''], ['accountant-a', 'accountant', ''], ['employee-a', 'employee', 'branch-a'],
    ]) {
      await setDoc(doc(database, 'users', uid), {role, isActive: true, mustChangePassword: false, ...(branchId ? {branchId} : {})});
    }
    await setDoc(doc(database, 'cash_expense_requests', 'expense-1'), expense());
  });
});

function db(uid) { return environment.authenticatedContext(uid).firestore(); }
function history() { return [{action: 'created', actor_role: 'manager', timestamp}]; }
function expense({status = 'pendingGeneralManagerReview'} = {}) {
  return {
    id: 'expense-1', request_number: 'AA0001', branch_id: 'branch-a', branch_name: 'A',
    title: 'Expense', description: 'Operational', requested_amount: 10, approved_amount: 10,
    currency: 'YER', status, created_by: 'manager-a', created_at: timestamp,
    last_updated: timestamp, history: history(),
  };
}

test('only the assigned branch manager can create an expense request', async () => {
  const created = {...expense(), id: 'expense-2', request_number: 'AA0002', created_at: serverTimestamp(), last_updated: serverTimestamp()};
  await assertSucceeds(setDoc(doc(db('manager-a'), 'cash_expense_requests', 'expense-2'), created));
  await assertFails(setDoc(doc(db('manager-b'), 'cash_expense_requests', 'expense-3'), {
    ...created, id: 'expense-3', created_by: 'manager-b',
  }));
});

test('general manager approval and rejection are state- and actor-bound', async () => {
  await assertSucceeds(updateDoc(doc(db('collector-a'), 'cash_expense_requests', 'expense-1'), {
    status: 'rejectedByGeneralManager', rejection_reason: 'Missing evidence', general_manager_notes: 'Missing evidence',
    reviewed_by: 'collector-a', reviewed_at: serverTimestamp(), last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(updateDoc(doc(db('accountant-a'), 'cash_expense_requests', 'expense-1'), {
    status: 'approvedByAccountant', approved_by: 'accountant-a', approved_at: serverTimestamp(),
    accounting_reference: 'A-1', last_updated: serverTimestamp(), history: history(),
  }));
});

test('the manager invoice decision and accountant final approval remain allowed in order', async () => {
  await assertSucceeds(updateDoc(doc(db('collector-a'), 'cash_expense_requests', 'expense-1'), {
    status: 'pendingInvoiceAttachment', title: 'Reviewed expense', description: 'Reviewed', approved_amount: 9,
    reviewed_by: 'collector-a', reviewed_at: serverTimestamp(), last_updated: serverTimestamp(), history: history(),
  }));
  await assertSucceeds(updateDoc(doc(db('manager-a'), 'cash_expense_requests', 'expense-1'), {
    status: 'pendingAccountingApproval', invoice_notes: 'No attachment available',
    invoice_approved_by: 'manager-a', invoice_approved_at: serverTimestamp(), last_updated: serverTimestamp(), history: history(),
  }));
  await assertSucceeds(updateDoc(doc(db('accountant-a'), 'cash_expense_requests', 'expense-1'), {
    status: 'approvedByAccountant', accounting_reference: 'ACC-1', approved_by: 'accountant-a',
    approved_at: serverTimestamp(), last_updated: serverTimestamp(), history: history(),
  }));
});

test('wrong-branch writes and all hard deletes are denied', async () => {
  await assertFails(updateDoc(doc(db('manager-b'), 'cash_expense_requests', 'expense-1'), {
    status: 'pendingAccountingApproval', invoice_approved_by: 'manager-b', invoice_approved_at: serverTimestamp(),
    last_updated: serverTimestamp(), history: history(),
  }));
  await assertFails(deleteDoc(doc(db('manager-a'), 'cash_expense_requests', 'expense-1')));
});
