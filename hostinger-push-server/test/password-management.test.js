const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

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
