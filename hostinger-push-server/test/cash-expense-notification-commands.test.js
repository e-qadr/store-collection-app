const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

const {createCashExpenseNotificationRouter} = require("../cash-expense-notification-commands");
const {FakeFirestore, fakeAdmin} = require("./support/fake-firestore");

function seed() {
  return {
    users: {
      manager: {role: "manager", branchId: "branch-1", isActive: true},
      collector: {role: "collector", isActive: true},
      accountant: {role: "accountant", isActive: true},
      inactiveCollector: {role: "collector", isActive: false},
    },
    cash_expense_requests: {
      expense: {
        id: "expense", request_number: "BR0001", branch_id: "branch-1",
        title: "إصلاح", created_by: "manager",
        status: "pendingGeneralManagerReview",
      },
    },
  };
}

async function withServer(firestore, callback) {
  const app = express();
  app.use("/v1", createCashExpenseNotificationRouter({admin: fakeAdmin(), firestore}));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try { await callback(`http://127.0.0.1:${server.address().port}`); } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function post(baseUrl, uid) {
  return fetch(`${baseUrl}/v1/notifications/cash-expenses/expense/created`, {
    method: "POST", headers: {authorization: `Bearer token-${uid}`},
  });
}

function postEvent(baseUrl, event, uid) {
  return fetch(`${baseUrl}/v1/notifications/cash-expenses/expense/${event}`, {
    method: "POST", headers: {authorization: `Bearer token-${uid}`},
  });
}

test("cash-expense creation is a server-derived task and retry is idempotent", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "manager")).status, 201);
    assert.equal((await post(baseUrl, "manager")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "collector");
  assert.equal(notifications[0].notification_type, "cash_expense_created");
  assert.equal(notifications[0].requires_action, true);
});

test("cash-expense dispatch refuses a user who did not create the expense", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "collector")).status, 403);
  });
  assert.equal(firestore.documents("notifications").length, 0);
});

test("manager edit before review remains an activity for the actual reviewer", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await postEvent(baseUrl, "manager_updated_before_review", "manager")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "collector");
  assert.equal(notifications[0].requires_action, false);
  assert.equal(notifications[0].notification_type, "cash_expense_manager_updated_after_edit");
});
