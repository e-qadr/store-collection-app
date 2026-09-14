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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const projectId = 'demo-store-collection-branch-requests';
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
    ]) {
      await setDoc(doc(database, 'users', uid), {
        role, isActive: true, mustChangePassword: false,
        ...(branchId ? {branchId} : {}),
      });
    }
    await setDoc(doc(database, 'branch_requests', 'request-r'), request());
    await setDoc(doc(database, 'branch_requests', 'request-x'), request({
      id: 'request-x', branchId: 'branch-x', branchName: 'X', createdBy: 'manager-x',
    }));
  });
});

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function history(action = 'created') {
  return [{
    action,
    message: action,
    actor_id: 'manager-r',
    actor_name: 'Manager R',
    actor_role: 'manager',
    timestamp,
  }];
}

function request({
  id = 'request-r',
  branchId = 'branch-r',
  branchName = 'R',
  createdBy = 'manager-r',
} = {}) {
  return {
    id,
    branch_id: branchId,
    branch_name: branchName,
    title: 'Repair lighting',
    description: 'The display lighting needs repair.',
    category: 'maintenance',
    priority: 'important',
    status: 'new',
    created_by: createdBy,
    created_by_name: 'Manager R',
    created_at: timestamp,
    last_updated: timestamp,
    history: history(),
  };
}

test('branch managers may list and get only their assigned branch requests', async () => {
  await assertSucceeds(getDocs(query(
    collection(db('manager-r'), 'branch_requests'),
    where('branch_id', '==', 'branch-r'),
  )));
  await assertFails(getDocs(collection(db('manager-r'), 'branch_requests')));
  await assertFails(getDoc(doc(db('manager-r'), 'branch_requests', 'request-x')));
  await assertSucceeds(getDocs(collection(db('collector-user'), 'branch_requests')));
  await assertFails(getDocs(collection(db('accountant-user'), 'branch_requests')));
});

test('only the assigned branch manager can create a new branch request', async () => {
  const created = {
    ...request({id: 'request-new'}),
    created_at: serverTimestamp(),
    last_updated: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(db('manager-r'), 'branch_requests', 'request-new'), created));
  await assertFails(setDoc(doc(db('manager-x'), 'branch_requests', 'request-bad'), {
    ...created, id: 'request-bad', branch_id: 'branch-r', created_by: 'manager-x',
  }));
  await assertFails(setDoc(doc(db('collector-user'), 'branch_requests', 'request-collector'), {
    ...created, id: 'request-collector', created_by: 'collector-user',
  }));
});

test('only the collector can advance new to in progress and then complete', async () => {
  const managerRef = doc(db('manager-r'), 'branch_requests', 'request-r');
  await assertFails(updateDoc(managerRef, {
    status: 'in_progress', started_by: 'manager-r', started_by_name: 'Manager R',
    started_at: serverTimestamp(), last_updated: serverTimestamp(), history: [...history(), ...history('started')],
  }));

  const collectorRef = doc(db('collector-user'), 'branch_requests', 'request-r');
  await assertFails(updateDoc(collectorRef, {
    status: 'completed', completed_by: 'collector-user', completed_by_name: 'General Manager',
    completed_at: serverTimestamp(), completion_note: '', last_updated: serverTimestamp(),
    history: [...history(), ...history('completed')],
  }));
  await assertSucceeds(updateDoc(collectorRef, {
    status: 'in_progress', started_by: 'collector-user', started_by_name: 'General Manager',
    started_at: serverTimestamp(), last_updated: serverTimestamp(), history: [...history(), ...history('started')],
  }));
  await assertSucceeds(updateDoc(collectorRef, {
    status: 'completed', completed_by: 'collector-user', completed_by_name: 'General Manager',
    completed_at: serverTimestamp(), completion_note: 'Completed safely', last_updated: serverTimestamp(),
    history: [...history(), ...history('started'), ...history('completed')],
  }));
  await assertFails(deleteDoc(collectorRef));
});
