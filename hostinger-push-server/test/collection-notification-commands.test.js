const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

const {createCollectionNotificationRouter} = require("../collection-notification-commands");
const {FakeFirestore, fakeAdmin} = require("./support/fake-firestore");

function seed() {
  return {
    users: {
      collector: {role: "collector", isActive: true},
      manager: {role: "manager", branchId: "branch-1", isActive: true},
      accountant: {role: "accountant", isActive: true},
      accountantTwo: {role: "accountant", isActive: true},
      outsider: {role: "manager", branchId: "branch-2", isActive: true},
    },
    transactions: {
      voucher: {
        transaction_number: "TR0001", branchId: "branch-1", status: "approvedByManager",
        collectorId: "collector",
        collection_approval_participants: {
          collector: {user_id: "collector"}, manager: {user_id: "manager"},
        },
      },
    },
  };
}

async function withServer(firestore, callback) {
  const app = express();
  app.use("/v1", createCollectionNotificationRouter({admin: fakeAdmin(), firestore}));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try { await callback(`http://127.0.0.1:${server.address().port}`); } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function post(baseUrl, event, uid) {
  return fetch(`${baseUrl}/v1/notifications/collections/voucher/${event}`, {
    method: "POST", headers: {authorization: `Bearer token-${uid}`},
  });
}

test("collection creation derives the responsible branch manager instead of trusting the client", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({status: "pending"});
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "created", "collector")).status, 201);
    assert.equal((await post(baseUrl, "created", "outsider")).status, 403);
  });
  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "manager");
  assert.equal(notifications[0].notification_type, "collection_created");
  assert.equal(notifications[0].requires_action, true);
});
test("reserved collection sends the actionable task only to the collector", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({
    status: "reservedForCollection", reviewed_by: "accountant",
  });
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "reserved", "accountant")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  const collectorTask = notifications.find((item) => item.recipient_id === "collector");
  const managerActivity = notifications.find((item) => item.recipient_id === "manager");
  assert.equal(collectorTask.notification_type, "collection_reserved_for_collection");
  assert.equal(collectorTask.requires_action, true);
  assert.equal(managerActivity.notification_type, "collection_reserved_observation");
  assert.equal(managerActivity.requires_action, false);
});
test("accountant edit request is a task for the original collector only", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({
    status: "editRequestedByCollector",
    history: [{actor_id: "accountant", action: "edit_requested_by_accountant"}],
  });
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "accountant_edit_requested", "accountant")).status, 201);
    assert.equal((await post(baseUrl, "accountant_edit_requested", "outsider")).status, 403);
  });
  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "collector");
  assert.equal(notifications[0].notification_type, "collection_accountant_edit_requested");
  assert.equal(notifications[0].requires_action, true);
});

test("manager approval creates an accountant-only collection task", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "manager_approved", "manager")).status, 201);
    assert.equal((await post(baseUrl, "manager_approved", "manager")).status, 201);
    assert.equal((await post(baseUrl, "manager_approved", "outsider")).status, 403);
  });
  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 2);
  assert.deepEqual(notifications.map((item) => item.recipient_id).sort(), ["accountant", "accountantTwo"]);
  assert.ok(notifications.every((item) => item.notification_type === "collection_manager_approved"));
  assert.ok(notifications.every((item) => item.requires_action));
});

test("manager approval closes the exact manager creation task", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({status: "pending"});
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "created", "collector")).status, 201);
    await firestore.collection("transactions").doc("voucher").update({status: "approvedByManager"});
    assert.equal((await post(baseUrl, "manager_approved", "manager")).status, 201);
  });
  const originalTask = firestore.documents("notifications")
      .find((item) => item.notification_type === "collection_created");
  assert.equal(originalTask.task_status, "completed");
});

test("accountant approval closes only the accountant task and informs participants", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "manager_approved", "manager")).status, 201);
    await firestore.collection("transactions").doc("voucher").update({
      status: "approvedByAccountant",
      collection_approval_participants: {
        collector: {user_id: "collector"}, manager: {user_id: "manager"},
        accountant: {user_id: "accountant"},
      },
    });
    assert.equal((await post(baseUrl, "accountant_approved", "accountant")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  const task = notifications.find((item) => item.notification_type === "collection_manager_approved");
  assert.equal(task.task_status, "completed");
  assert.ok(notifications
      .filter((item) => item.notification_type === "collection_manager_approved")
      .every((item) => item.task_status === "completed"));
  const activityRecipients = notifications
      .filter((item) => item.notification_type === "collection_accountant_approved")
      .map((item) => item.recipient_id).sort();
  assert.deepEqual(activityRecipients, ["collector", "manager"]);
});

test("physical collection difference creates and then resolves an accountant-only task", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({
    status: "collectionDifferencePendingReview",
    physical_collected_by: "collector",
  });
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "difference_pending", "collector")).status, 201);
    await firestore.collection("transactions").doc("voucher").update({
      status: "pending", difference_reviewed_by: "accountant",
    });
    assert.equal((await post(baseUrl, "difference_decision", "accountant")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  const task = notifications.find((item) => item.notification_type === "collection_difference_pending_review");
  assert.equal(task.recipient_id, "accountant");
  assert.equal(task.task_status, "completed");
  assert.ok(notifications
      .filter((item) => item.notification_type === "collection_difference_pending_review")
      .every((item) => item.task_status === "completed"));
  const recipients = notifications
      .filter((item) => item.notification_type === "collection_difference_reviewed")
      .map((item) => item.recipient_id).sort();
  assert.deepEqual(recipients, ["collector", "manager"]);
});

test("completed physical collection closes the collector task without creating a false task for observers", async () => {
  const firestore = new FakeFirestore(seed());
  await firestore.collection("transactions").doc("voucher").update({
    status: "reservedForCollection", reviewed_by: "accountant",
  });
  await withServer(firestore, async (baseUrl) => {
    assert.equal((await post(baseUrl, "reserved", "accountant")).status, 201);
    await firestore.collection("transactions").doc("voucher").update({
      status: "pending", physical_collected_by: "collector",
    });
    assert.equal((await post(baseUrl, "collected", "collector")).status, 201);
  });
  const notifications = firestore.documents("notifications");
  const task = notifications.find((item) => item.notification_type === "collection_reserved_for_collection");
  assert.equal(task.task_status, "completed");
  assert.ok(notifications
      .filter((item) => item.notification_type === "collection_voucher_physically_collected")
      .every((item) => item.requires_action === false));
});

