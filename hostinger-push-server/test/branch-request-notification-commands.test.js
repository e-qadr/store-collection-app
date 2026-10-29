const assert = require("node:assert/strict");
const http = require("node:http");
const test = require("node:test");
const express = require("express");

const {
  createBranchRequestNotificationRouter,
} = require("../branch-request-notification-commands");
const {FakeFirestore, fakeAdmin} = require("./support/fake-firestore");

function seed() {
  return {
    users: {
      manager: {role: "manager", branchId: "branch-1", isActive: true},
      collector: {role: "collector", isActive: true},
      accountant: {role: "accountant", isActive: true},
      inactiveCollector: {role: "collector", isActive: false},
    },
    branches: {
      "branch-1": {branch_manager_id: "manager"},
    },
    branch_requests: {
      request: {
        id: "request",
        title: "توريد مستلزمات",
        branch_id: "branch-1",
        direction: "branch_to_administration",
        status: "new",
        executor_role: "collector",
        created_by: "manager",
      },
      task: {
        id: "task",
        title: "جرد أسبوعي",
        branch_id: "branch-1",
        direction: "administration_to_branch",
        status: "new",
        executor_role: "manager",
        created_by: "collector",
      },
    },
  };
}

async function withServer(firestore, callback) {
  const app = express();
  app.use(express.json({limit: "16kb"}));
  app.use("/v1", createBranchRequestNotificationRouter({
    admin: fakeAdmin(),
    firestore,
  }));
  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function post(baseUrl, path, uid) {
  return fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {authorization: `Bearer token-${uid}`},
  });
}

test("server derives recipients and task metadata for a branch request", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const response = await post(
        baseUrl,
        "/v1/notifications/branch-requests/request/request_created",
        "manager",
    );
    assert.equal(response.status, 201);
    const replay = await post(
        baseUrl,
        "/v1/notifications/branch-requests/request/request_created",
        "manager",
    );
    assert.equal(replay.status, 201);
  });

  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "collector");
  assert.equal(notifications[0].notification_type, "branch_request_created");
  assert.equal(notifications[0].requires_action, true);
  assert.equal(notifications[0].task_status, "open");
  assert.equal(notifications[0].branch_request_id, "request");
});

test("server sends an accountant-targeted branch request to the accountant only", async () => {
  const data = seed();
  data.branch_requests.request.executor_role = "accountant";
  const firestore = new FakeFirestore(data);
  await withServer(firestore, async (baseUrl) => {
    const response = await post(
        baseUrl,
        "/v1/notifications/branch-requests/request/request_created",
        "manager",
    );
    assert.equal(response.status, 201);
  });

  const notifications = firestore.documents("notifications");
  assert.equal(notifications.length, 1);
  assert.equal(notifications[0].recipient_id, "accountant");
  assert.match(notifications[0].message, /المحاسب/);
});

test("server rejects spoofed branch-task notification actors", async () => {
  const firestore = new FakeFirestore(seed());
  await withServer(firestore, async (baseUrl) => {
    const response = await post(
        baseUrl,
        "/v1/notifications/branch-requests/task/branch_task_assigned",
        "manager",
    );
    assert.equal(response.status, 403);
  });
  assert.equal(firestore.documents("notifications").length, 0);
});
