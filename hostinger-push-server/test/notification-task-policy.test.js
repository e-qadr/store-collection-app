const assert = require("node:assert/strict");
const test = require("node:test");

const {
  buildNotificationDocument,
  closeOpenTasks,
  notificationTaskMetadata,
  pushEligibility,
} = require("../notification-task-policy");

test("task notifications carry a stable, user-facing action contract", () => {
  const document = buildNotificationDocument({
    id: "purchase-task-1",
    recipientId: "manager-r",
    title: "فاتورة مشتريات بانتظار الاستلام",
    message: "فاتورة المشتريات BR001 بانتظار مراجعة الكميات.",
    module: "purchase_invoices",
    entityCollection: "purchase_invoices",
    entityId: "invoice-1",
    branchId: "branch-r",
    branchIds: ["branch-r", "branch-r"],
    referenceNumber: "BR001",
    notificationType: "purchase_invoice_created",
    timestamp: "server-time",
    extraData: {purchase_invoice_id: "invoice-1", invoice_total: 999999},
  });

  assert.equal(document.notification_schema_version, 2);
  assert.equal(document.delivery_kind, "task");
  assert.equal(document.requires_action, true);
  assert.equal(document.action_kind, "confirm_receipt");
  assert.equal(document.action_label, "تأكيد استلام الكميات");
  assert.equal(document.audience_reason, "أنت مدير الفرع المستلم");
  assert.equal(document.task_status, "open");
  assert.deepEqual(document.branch_ids, ["branch-r"]);
  assert.equal(document.invoice_total, undefined);
});

test("activity notifications never become actionable tasks by default", () => {
  const metadata = notificationTaskMetadata({
    module: "inter_branch_invoices",
    notificationType: "inter_branch_v3_cancellation_applied",
  });

  assert.deepEqual(metadata, {
    notification_schema_version: 2,
    delivery_kind: "activity",
    requires_action: false,
    action_kind: null,
    action_label: null,
    audience_reason: "للمتابعة",
    priority: "normal",
    task_status: "not_applicable",
  });
});

test("notification identity fields cannot be overwritten by producer extras", () => {
  const document = buildNotificationDocument({
    id: "transfer-task-1",
    recipientId: "manager-r",
    title: "عنوان",
    message: "رسالة",
    module: "inter_branch_invoices",
    entityCollection: "inter_branch_invoices",
    entityId: "invoice-2",
    branchId: "branch-s",
    branchIds: ["branch-r"],
    referenceNumber: "TR001",
    notificationType: "inter_branch_v3_amendment_requested",
    timestamp: "server-time",
    extraData: {
      recipient_id: "wrong-user",
      module: "wrong-module",
      requires_action: false,
    },
  });

  assert.equal(document.recipient_id, "manager-r");
  assert.equal(document.module, "inter_branch_invoices");
  assert.equal(document.requires_action, true);
  assert.equal(document.action_kind, "approve_amendment");
  assert.deepEqual(document.branch_ids, ["branch-s", "branch-r"]);
});

test("Push delivery excludes inactive and opted-out recipients without treating them as errors", () => {
  assert.deepEqual(pushEligibility(false, undefined), {
    eligible: false,
    status: "recipient_inactive",
  });
  assert.deepEqual(pushEligibility(true, {isActive: false}), {
    eligible: false,
    status: "recipient_inactive",
  });
  assert.deepEqual(pushEligibility(true, {isActive: true, notifications_enabled: false}), {
    eligible: false,
    status: "notifications_disabled",
  });
  assert.deepEqual(pushEligibility(true, {isActive: true, notifications_enabled: true}), {
    eligible: true,
    status: null,
  });
});

test("only matching open tasks are closed for the acting recipient", async () => {
  const {FakeFirestore} = require("./support/fake-firestore");
  const firestore = new FakeFirestore({
    notifications: {
      matching: {
        entity_id: "invoice-1",
        recipient_id: "manager-r",
        requires_action: true,
        notification_type: "purchase_invoice_created",
        task_status: "open",
      },
      anotherRecipient: {
        entity_id: "invoice-1",
        recipient_id: "manager-x",
        requires_action: true,
        notification_type: "purchase_invoice_created",
        task_status: "open",
      },
      anotherAction: {
        entity_id: "invoice-1",
        recipient_id: "manager-r",
        requires_action: true,
        notification_type: "purchase_amendment_requested",
        task_status: "open",
      },
      activity: {
        entity_id: "invoice-1",
        recipient_id: "manager-r",
        requires_action: false,
        notification_type: "purchase_accounting_posted",
        task_status: "not_applicable",
      },
    },
  });

  await firestore.runTransaction((transaction) => closeOpenTasks(transaction, firestore, {
    entityId: "invoice-1",
    recipientIds: ["manager-r"],
    notificationTypes: ["purchase_invoice_created"],
    timestamp: "server-time",
  }));

  assert.equal(firestore.document("notifications", "matching").task_status, "completed");
  assert.equal(firestore.document("notifications", "matching").task_resolved_at, "server-time");
  assert.equal(firestore.document("notifications", "anotherRecipient").task_status, "open");
  assert.equal(firestore.document("notifications", "anotherAction").task_status, "open");
  assert.equal(firestore.document("notifications", "activity").task_status, "not_applicable");
});
