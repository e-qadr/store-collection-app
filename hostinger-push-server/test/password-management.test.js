const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");
const {FakeFirestore} = require("./support/fake-firestore");

const {
  GENERIC_RESET_MESSAGE,
  SlidingWindowRateLimiter,
  createPasswordManagementRouter,
  secureTemporaryPassword,
  validatePassword,
} = require("../password-management");

function fakeAdmin(role = "collector") {
  return {
    auth: () => ({
      verifyIdToken: async () => ({uid: "actor", auth_time: 1000}),
    }),
    firestore: {
      FieldValue: {
        serverTimestamp: () => "server-time",
      },
      Timestamp: {fromDate: (date) => date},
    },
    role,
  };
}

function fakeFirestore(role = "collector") {
  return {
    collection: (name) => ({
      doc: () => ({
        get: async () => ({
          exists: name === "users",
          data: () => ({role, isActive: true}),
        }),
      }),
    }),
  };
}

function managementAdmin() {
  const authUsers = new Map();
  let nextUid = 0;
  const auth = {
    verifyIdToken: async (token) => {
      if (token !== "admin-token") throw new Error("Invalid token");
      return {uid: "admin-user", auth_time: 1000};
    },
    createUser: async ({email, displayName, disabled}) => {
      const uid = `created-${++nextUid}`;
      authUsers.set(uid, {email, displayName, disabled});
      return {uid};
    },
    updateUser: async (uid, updates) => {
      authUsers.set(uid, {...(authUsers.get(uid) || {}), ...updates});
      return {uid};
    },
    revokeRefreshTokens: async (uid) => {
      authUsers.set(uid, {...(authUsers.get(uid) || {}), refreshTokensRevoked: true});
    },
    deleteUser: async (uid) => authUsers.delete(uid),
  };
  return {
    admin: {
      auth: () => auth,
      firestore: {
        FieldValue: {serverTimestamp: () => "server-time"},
        Timestamp: {fromDate: (date) => date},
      },
    },
    authUsers,
  };
}

function managementFixture() {
  const firestore = new FakeFirestore({
    users: {
      "admin-user": {role: "admin", isActive: true},
      "manager-1": {role: "manager", isActive: true, branchId: null},
      "manager-2": {role: "manager", isActive: true, branchId: "branch-a"},
    },
    branches: {
      "branch-a": {id: "branch-a", branch_manager_id: "manager-2"},
      "branch-b": {id: "branch-b", branch_manager_id: null},
    },
  });
  const state = managementAdmin();
  return {
    firestore,
    authUsers: state.authUsers,
    router: createPasswordManagementRouter({
      admin: state.admin,
      firestore,
      now: () => new Date("2026-08-17T00:00:00.000Z"),
      randomBytes: () => Buffer.alloc(48, 7),
    }),
  };
}

async function postJson(baseUrl, path, body) {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      authorization: "Bearer admin-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function patchJson(baseUrl, path, body) {
  return fetch(`${baseUrl}${path}`, {
    method: "PATCH",
    headers: {
      authorization: "Bearer admin-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function withServer(router, callback) {
  const app = express();
  app.use(express.json());
  app.use("/v1", router);
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  try {
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("temporary passwords are strong, random, and contain every category", () => {
  const first = secureTemporaryPassword();
  const second = secureTemporaryPassword();
  assert.notEqual(first, second);
  assert.equal(first.length, 20);
  assert.equal(validatePassword(first), true);
});

test("password policy rejects short or incomplete passwords", () => {
  assert.equal(validatePassword("short"), false);
  assert.equal(validatePassword("alllowercase123!"), false);
  assert.equal(validatePassword("ValidPassword1!"), true);
});

test("sliding-window limiter rejects excess attempts and later recovers", () => {
  let time = 0;
  const limiter = new SlidingWindowRateLimiter({
    limit: 2,
    windowMs: 100,
    now: () => time,
  });
  assert.equal(limiter.take("key"), true);
  assert.equal(limiter.take("key"), true);
  assert.equal(limiter.take("key"), false);
  time = 101;
  assert.equal(limiter.take("key"), true);
});

test("normal users cannot call administrator operations", async () => {
  const router = createPasswordManagementRouter({
    admin: fakeAdmin("collector"),
    firestore: fakeFirestore("collector"),
    firebaseApiKey: "test-key",
    fetchImpl: async () => ({ok: true}),
  });
  await withServer(router, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/admin/users`, {
      method: "POST",
      headers: {
        authorization: "Bearer valid-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Normal user",
        email: "user@example.com",
        role: "collector",
      }),
    });
    assert.equal(response.status, 403);
    assert.equal((await response.json()).error.code, "forbidden");
  });
});

test("forgot-password response is neutral even when Firebase rejects email", async () => {
  const router = createPasswordManagementRouter({
    admin: fakeAdmin(),
    firestore: fakeFirestore(),
    firebaseApiKey: "test-key",
    fetchImpl: async () => ({ok: false}),
  });
  await withServer(router, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/v1/auth/forgot-password`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({email: "missing@example.com"}),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).message, GENERIC_RESET_MESSAGE);
  });
});

test("admins can create and edit users with no branch, including managers", async () => {
  const {firestore, router} = managementFixture();
  await withServer(router, async (baseUrl) => {
    let response = await postJson(baseUrl, "/v1/admin/users", {
      name: "Unassigned collector",
      email: "collector@example.com",
      role: "collector",
    });
    assert.equal(response.status, 201);
    const collector = (await response.json()).user.uid;
    assert.equal(firestore.document("users", collector).branchId, null);

    response = await patchJson(baseUrl, `/v1/admin/users/${collector}`, {
      role: "accountant",
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("users", collector).role, "accountant");
    assert.equal(firestore.document("users", collector).branchId, null);

    response = await postJson(baseUrl, "/v1/admin/users", {
      name: "Unassigned manager",
      email: "manager@example.com",
      role: "manager",
    });
    assert.equal(response.status, 201);
    const manager = (await response.json()).user.uid;
    assert.equal(firestore.document("users", manager).role, "manager");
    assert.equal(firestore.document("users", manager).branchId, null);
  });
});

test("manager assignment, reassignment, and removal keep both sides consistent", async () => {
  const {firestore, router} = managementFixture();
  await withServer(router, async (baseUrl) => {
    let response = await postJson(baseUrl, "/v1/admin/branches/branch-b/manager", {
      managerUid: "manager-1",
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("branches", "branch-b").branch_manager_id, "manager-1");
    assert.equal(firestore.document("users", "manager-1").branchId, "branch-b");

    response = await postJson(baseUrl, "/v1/admin/branches/branch-a/manager", {
      managerUid: "manager-1",
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("branches", "branch-a").branch_manager_id, "manager-1");
    assert.equal(firestore.document("branches", "branch-b").branch_manager_id, null);
    assert.equal(firestore.document("users", "manager-1").branchId, "branch-a");
    assert.equal(firestore.document("users", "manager-2").branchId, null);

    response = await postJson(baseUrl, "/v1/admin/branches/branch-a/manager", {});
    assert.equal(response.status, 200);
    assert.equal(firestore.document("branches", "branch-a").branch_manager_id, null);
    assert.equal(firestore.document("users", "manager-1").branchId, null);
  });
});

test("user PATCH assigns, moves, and removes active managers atomically", async () => {
  const {firestore, router} = managementFixture();
  await withServer(router, async (baseUrl) => {
    let response = await patchJson(baseUrl, "/v1/admin/users/manager-1", {
      branchId: "branch-b",
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("users", "manager-1").branchId, "branch-b");
    assert.equal(firestore.document("branches", "branch-b").branch_manager_id, "manager-1");

    response = await patchJson(baseUrl, "/v1/admin/users/manager-1", {
      branchId: "branch-a",
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("users", "manager-1").branchId, "branch-a");
    assert.equal(firestore.document("users", "manager-2").branchId, null);
    assert.equal(firestore.document("branches", "branch-a").branch_manager_id, "manager-1");
    assert.equal(firestore.document("branches", "branch-b").branch_manager_id, null);

    response = await patchJson(baseUrl, "/v1/admin/users/manager-1", {
      branchId: null,
    });
    assert.equal(response.status, 200);
    assert.equal(firestore.document("users", "manager-1").branchId, null);
    assert.equal(firestore.document("branches", "branch-a").branch_manager_id, null);
  });
});

test("user PATCH rejects inactive manager assignment and empty updates", async () => {
  const {firestore, router} = managementFixture();
  firestore._collection("users").set("manager-inactive", {
    role: "manager",
    isActive: false,
    branchId: null,
  });
  await withServer(router, async (baseUrl) => {
    let response = await patchJson(baseUrl, "/v1/admin/users/manager-inactive", {
      branchId: "branch-b",
    });
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.code, "invalid-argument");
    assert.equal(firestore.document("users", "manager-inactive").branchId, null);
    assert.equal(firestore.document("branches", "branch-b").branch_manager_id, null);

    response = await patchJson(baseUrl, "/v1/admin/users/manager-1", {});
    assert.equal(response.status, 400);
    assert.equal((await response.json()).error.code, "invalid-argument");
  });
});

test("deactivating an assigned manager clears stale branch references", async () => {
  const {firestore, authUsers, router} = managementFixture();
  await withServer(router, async (baseUrl) => {
    const response = await patchJson(baseUrl, "/v1/admin/users/manager-2", {
      isActive: false,
    });
    assert.equal(response.status, 200);
  });
  assert.equal(firestore.document("users", "manager-2").isActive, false);
  assert.equal(firestore.document("users", "manager-2").branchId, null);
  assert.equal(firestore.document("branches", "branch-a").branch_manager_id, null);
  assert.equal(authUsers.get("manager-2").disabled, true);
  assert.equal(authUsers.get("manager-2").refreshTokensRevoked, true);
});
