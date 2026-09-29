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
    await setDoc(doc(database, 'branches', 'branch-r'), {
      id: 'branch-r', name: 'R', branch_type: 'branch', active: true,
    });
    await setDoc(doc(database, 'branches', 'branch-x'), {
      id: 'branch-x', name: 'X', branch_type: 'branch', active: true,
    });
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
    direction: 'branch_to_administration',
    executor_role: 'collector',
    created_by: createdBy,
    created_by_name: 'Manager R',
    created_by_role: 'manager',
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
    direction: 'branch_to_administration', executor_role: 'collector',
    created_by_role: 'manager',
    created_at: serverTimestamp(),
    last_updated: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(db('manager-r'), 'branch_requests', 'request-new'), created));
  await assertFails(setDoc(doc(db('manager-x'), 'branch_requests', 'request-bad'), {
    ...created, id: 'request-bad', branch_id: 'branch-r', created_by: 'manager-x',
  }));
  await assertFails(setDoc(doc(db('collector-user'), 'branch_requests', 'request-collector'), {
    ...created, id: 'request-collector', created_by: 'collector-user', created_by_role: 'collector',
  }));
});

test('General Manager and accountant can assign a task only to an operational branch', async () => {
  const assigned = {
    ...request({id: 'assigned-task'}),
    direction: 'administration_to_branch', executor_role: 'manager',
    created_by: 'collector-user', created_by_name: 'General Manager',
    created_by_role: 'collector', created_at: serverTimestamp(), last_updated: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(db('collector-user'), 'branch_requests', 'assigned-task'), assigned));
  await assertSucceeds(setDoc(doc(db('accountant-user'), 'branch_requests', 'accountant-task'), {
    ...assigned, id: 'accountant-task', created_by: 'accountant-user',
    created_by_name: 'Accountant', created_by_role: 'accountant',
  }));
  await assertFails(setDoc(doc(db('collector-user'), 'branch_requests', 'bad-task'), {
    ...assigned, id: 'bad-task', branch_id: 'missing-branch', branch_name: 'Missing',
  }));
});

test('General Manager and accountant can assign each other an administrative task', async () => {
  const toAccountant = {
    ...request({id: 'to-accountant', branchId: 'administration', branchName: 'الإدارة'}),
    direction: 'administration_to_administration', executor_role: 'accountant',
    created_by: 'collector-user', created_by_name: 'General Manager',
    created_by_role: 'collector', created_at: serverTimestamp(), last_updated: serverTimestamp(),
  };
  await assertSucceeds(setDoc(doc(db('collector-user'), 'branch_requests', 'to-accountant'), toAccountant));
  await assertSucceeds(setDoc(doc(db('accountant-user'), 'branch_requests', 'to-collector'), {
    ...toAccountant, id: 'to-collector', executor_role: 'collector',
    created_by: 'accountant-user', created_by_name: 'Accountant', created_by_role: 'accountant',
  }));
  await assertFails(setDoc(doc(db('accountant-user'), 'branch_requests', 'wrong-recipient'), {
    ...toAccountant, id: 'wrong-recipient', created_by: 'accountant-user',
    created_by_name: 'Accountant', created_by_role: 'accountant',
  }));
  await assertSucceeds(getDocs(query(
    collection(db('accountant-user'), 'branch_requests'),
    where('executor_role', '==', 'accountant'),
  )));
});

test('the assigned administrative role alone starts and completes the task', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'branch_requests', 'to-accountant'), {
      ...request({id: 'to-accountant', branchId: 'administration', branchName: 'الإدارة'}),
      direction: 'administration_to_administration', executor_role: 'accountant',
      created_by: 'collector-user', created_by_name: 'General Manager', created_by_role: 'collector',
    });
  });
  const accountantRef = doc(db('accountant-user'), 'branch_requests', 'to-accountant');
  await assertSucceeds(updateDoc(accountantRef, {
    status: 'in_progress', started_by: 'accountant-user', started_by_name: 'Accountant',
    started_by_role: 'accountant', started_at: serverTimestamp(), last_updated: serverTimestamp(),
    history: [...history(), ...history('started')],
  }));
  await assertSucceeds(updateDoc(accountantRef, {
    status: 'completed', completed_by: 'accountant-user', completed_by_name: 'Accountant',
    completed_at: serverTimestamp(), completion_note: 'Completed safely', last_updated: serverTimestamp(),
    history: [...history(), ...history('started'), ...history('completed')],
  }));
});

test('a branch manager executes an accountant task while the accountant reads only tasks they created', async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'branch_requests', 'accountant-task'), {
      ...request({id: 'accountant-task'}),
      direction: 'administration_to_branch', executor_role: 'manager',
      created_by: 'accountant-user', created_by_name: 'Accountant', created_by_role: 'accountant',
    });
  });
  await assertSucceeds(getDoc(doc(db('accountant-user'), 'branch_requests', 'accountant-task')));
  await assertSucceeds(getDocs(query(
    collection(db('accountant-user'), 'branch_requests'),
    where('created_by', '==', 'accountant-user'),
  )));
  const managerRef = doc(db('manager-r'), 'branch_requests', 'accountant-task');
  await assertSucceeds(updateDoc(managerRef, {
    status: 'in_progress', started_by: 'manager-r', started_by_name: 'Manager R',
    started_by_role: 'manager', started_at: serverTimestamp(), last_updated: serverTimestamp(),
    history: [...history(), ...history('started')],
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
    status: 'in_progress', started_by: 'collector-user', started_by_name: 'General Manager', started_by_role: 'collector',
    started_at: serverTimestamp(), last_updated: serverTimestamp(), history: [...history(), ...history('started')],
  }));
  await assertSucceeds(updateDoc(collectorRef, {
    status: 'completed', completed_by: 'collector-user', completed_by_name: 'General Manager',
    completed_at: serverTimestamp(), completion_note: 'Completed safely', last_updated: serverTimestamp(),
    history: [...history(), ...history('started'), ...history('completed')],
  }));
  await assertFails(deleteDoc(collectorRef));
});

test('the creator may edit a request only before work starts', async () => {
  const managerRef = doc(db('manager-r'), 'branch_requests', 'request-r');
  await assertSucceeds(updateDoc(managerRef, {
    title: 'Updated lighting', last_updated: serverTimestamp(),
    history: [...history(), ...history('edited')],
  }));
});

test('the assigned executor can reject an open request with a reason', async () => {
  const collectorRef = doc(db('collector-user'), 'branch_requests', 'request-r');
  await assertSucceeds(updateDoc(collectorRef, {
    status: 'rejected', rejected_by: 'collector-user', rejected_by_name: 'General Manager',
    rejected_by_role: 'collector', rejected_at: serverTimestamp(), rejection_reason: 'Need additional details',
    last_updated: serverTimestamp(), history: [...history(), ...history('rejected')],
  }));
});
