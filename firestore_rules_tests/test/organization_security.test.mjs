import {after, before, beforeEach, test} from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {readFile} from 'node:fs/promises';
import {deleteDoc, doc, setDoc, updateDoc} from 'firebase/firestore';

const projectId = 'demo-store-collection-organization';
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
    await setDoc(doc(database, 'users', 'admin-user'), {
      role: 'admin', isActive: true, mustChangePassword: false,
    });
    await setDoc(doc(database, 'users', 'manager-user'), {
      role: 'manager', isActive: true, mustChangePassword: false, branchId: 'branch-1',
    });
    await setDoc(doc(database, 'brands', 'brand-1'), {id: 'brand-1', name: 'Brand', active: true});
    await setDoc(doc(database, 'branches', 'branch-1'), {
      id: 'branch-1', name: 'Branch', brand_id: 'brand-1', branch_code: 'BR', active: true,
    });
    await setDoc(doc(database, 'branch_codes', 'BR'), {branch_id: 'branch-1'});
  });
});

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

test('only admins can archive organization records and no client can hard-delete them', async () => {
  await assertSucceeds(updateDoc(doc(db('admin-user'), 'brands', 'brand-1'), {
    active: false, archive_reason: 'Retired', archived_by: 'admin-user',
  }));
  await assertSucceeds(updateDoc(doc(db('admin-user'), 'branches', 'branch-1'), {
    active: false, archive_reason: 'Closed', archived_by: 'admin-user',
  }));
  await assertFails(updateDoc(doc(db('manager-user'), 'branches', 'branch-1'), {active: true}));
  await assertFails(deleteDoc(doc(db('admin-user'), 'brands', 'brand-1')));
  await assertFails(deleteDoc(doc(db('admin-user'), 'branches', 'branch-1')));
  await assertFails(deleteDoc(doc(db('admin-user'), 'branch_codes', 'BR')));
});
