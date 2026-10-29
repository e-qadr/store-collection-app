"use strict";

// This module is intentionally free of Firestore dependencies.  It defines the
// stable contract consumed by the notification inbox and the future tasks view.
// Keep money, item lines, attachments and other private entity data out of this
// document: the application reads the authoritative entity after navigation.

const TASKS = Object.freeze({
  purchase_invoices: Object.freeze({
    purchase_invoice_created: task("confirm_receipt", "تأكيد استلام الكميات", "أنت مدير الفرع المستلم", "high"),
    purchase_product_review_required: task("review_products", "مراجعة المواد", "أنت المحاسب المسؤول عن مراجعة المواد", "high"),
    purchase_receipt_sent_to_accounting: task("post_to_accounting", "ترحيل الفاتورة محاسبياً", "أنت المحاسب المسؤول عن الترحيل", "high"),
    purchase_receipt_confirmed: task("confirm_prices", "تأكيد الأسعار", "أنت المدير العام المسؤول عن التسعير", "high"),
    purchase_prices_confirmed: task("post_to_accounting", "ترحيل الفاتورة محاسبياً", "أنت المحاسب المسؤول عن الترحيل", "high"),
    purchase_amendment_requested: task("approve_amendment", "مراجعة واعتماد التعديل", "أنت من المشاركين الفعليين في الفاتورة", "high"),
  }),
  inter_branch_invoices: Object.freeze({
    inter_branch_v2_direct_created: task("confirm_receipt", "تأكيد الاستلام", "أنت مسؤول عن استلام الفاتورة في الفرع المستلم", "high"),
    inter_branch_v3_direct_created: task("confirm_receipt", "تأكيد الاستلام", "أنت مسؤول عن استلام الفاتورة في الفرع المستلم", "high"),
    inter_branch_v2_receipt_confirmed: task("confirm_prices", "تأكيد الأسعار", "أنت المدير العام المسؤول عن التسعير", "high"),
    inter_branch_v3_receipt_confirmed: task("post_dual_accounting", "ترحيل الفرعين محاسبياً", "أنت المحاسب المسؤول عن ترحيل طرفي المناقلة", "high"),
    inter_branch_v2_prices_confirmed: task("post_dual_accounting", "ترحيل الفرعين محاسبياً", "أنت المحاسب المسؤول عن ترحيل طرفي المناقلة", "high"),
    inter_branch_v3_amendment_requested: task("approve_amendment", "مراجعة واعتماد التعديل", "أنت من المشاركين الفعليين في الفاتورة", "high"),
    inter_branch_v3_cancellation_requested: task("approve_cancellation", "مراجعة واعتماد الإلغاء", "أنت من المشاركين الفعليين في الفاتورة", "high"),
  }),
  branch_requests: Object.freeze({
    branch_request_created: task("handle_branch_request", "مراجعة الطلب وتحديد الإجراء", "أنت الجهة المختصة بطلب الفرع", "high"),
    branch_task_assigned: task("complete_assigned_task", "تنفيذ مهمة الفرع", "هذه المهمة مسندة إلى فرعك", "high"),
    administrative_task_assigned: task("complete_assigned_task", "تنفيذ المهمة الإدارية", "هذه المهمة مسندة إلى دورك", "high"),
  }),
  cash_expense_requests: Object.freeze({
    cash_expense_created: task("review_cash_expense", "مراجعة سند الصرف", "أنت المدير العام المسؤول عن المراجعة", "high"),
    cash_expense_invoice_required: task("attach_invoice", "إرفاق فاتورة المصروف", "أنت مدير الفرع منشئ السند", "high"),
    cash_expense_general_manager_approved: task("approve_cash_expense", "الاعتماد المحاسبي", "أنت المحاسب المسؤول عن الاعتماد", "high"),
    cash_expense_invoice_ready: task("approve_cash_expense", "الاعتماد المحاسبي", "أنت المحاسب المسؤول عن الاعتماد", "high"),
    cash_expense_edit_requested: task("approve_amendment", "مراجعة واعتماد التعديل", "أنت من المشاركين الفعليين في السند", "high"),
  }),
  consumable_requests: Object.freeze({
    consumable_request_created: task("review_consumable_request", "مراجعة طلب المستهلكات", "أنت المدير العام المسؤول عن المراجعة", "high"),
    consumable_collector_reviewed: task("approve_consumable_request", "الاعتماد المحاسبي", "أنت المحاسب المسؤول عن الاعتماد", "high"),
  }),
  transactions: Object.freeze({
    collection_created: task("approve_collection_voucher", "مراجعة واعتماد السند", "أنت مدير الفرع المسؤول عن اعتماد السند", "high"),
    collection_reserved_for_collection: task("collect_reserved_voucher", "تأكيد التحصيل الفعلي", "أنت المدير العام المسؤول عن التحصيل", "high"),
    collection_accountant_edit_requested: task("edit_collection_voucher", "تعديل سند التحصيل", "طلب المحاسب تعديل السند الذي أنشأته", "high"),
    collection_manager_approved: task("approve_collection_voucher", "المراجعة والاعتماد المحاسبي", "أنت المحاسب المسؤول عن السند", "high"),
    collection_difference_pending_review: task("review_collection_difference", "مراجعة فرق التحصيل", "أنت المحاسب المسؤول عن اعتماد الفرق", "high"),
    collection_amendment_requested: task("approve_amendment", "مراجعة واعتماد التعديل", "أنت من المشاركين الفعليين في سند التحصيل", "high"),
  }),
});

function task(actionKind, actionLabel, audienceReason, priority) {
  return Object.freeze({actionKind, actionLabel, audienceReason, priority});
}

function notificationTaskMetadata({module, notificationType}) {
  const definition = TASKS[module]?.[notificationType];
  if (!definition) {
    return {
      notification_schema_version: 2,
      delivery_kind: "activity",
      requires_action: false,
      action_kind: null,
      action_label: null,
      audience_reason: "للمتابعة",
      priority: "normal",
      task_status: "not_applicable",
    };
  }

  return {
    notification_schema_version: 2,
    delivery_kind: "task",
    requires_action: true,
    action_kind: definition.actionKind,
    action_label: definition.actionLabel,
    audience_reason: definition.audienceReason,
    priority: definition.priority,
    task_status: "open",
  };
}

function pushEligibility(userSnapshotExists, profile) {
  if (!userSnapshotExists || profile?.isActive === false) {
    return {eligible: false, status: "recipient_inactive"};
  }
  if (profile?.notifications_enabled === false) {
    return {eligible: false, status: "notifications_disabled"};
  }
  return {eligible: true, status: null};
}

function cleanIds(values) {
  return [...new Set(values
      .map((value) => String(value || "").trim())
      .filter(Boolean))];
}

function safeExtraData(extraData) {
  const safe = {};
  for (const [key, value] of Object.entries(extraData || {})) {
    // Notification rows must remain an inbox pointer, not a second financial
    // record.  The app fetches protected values only from the entity screen.
    if (/(?:price|total|amount|cost|accounting|attachment|items?)/i.test(key)) continue;
    safe[key] = value;
  }
  return safe;
}

function buildNotificationDocument({
  id,
  recipientId,
  title,
  message,
  module,
  entityCollection,
  entityId,
  branchId,
  branchIds = [],
  referenceNumber,
  notificationType,
  timestamp,
  extraData = {},
}) {
  const recipient = String(recipientId || "").trim();
  const entity = String(entityId || "").trim();
  const type = String(notificationType || "").trim();
  const resolvedBranches = cleanIds([branchId, ...branchIds]);

  if (!id || !recipient || !module || !entityCollection || !entity || !type) {
    throw new TypeError("Notification documents require stable identity fields.");
  }

  return {
    ...safeExtraData(extraData),
    id: String(id),
    recipient_id: recipient,
    title: String(title || "إشعار جديد"),
    message: String(message || ""),
    is_read: false,
    push_status: "pending",
    module: String(module),
    entity_collection: String(entityCollection),
    entity_id: entity,
    branch_id: resolvedBranches[0] || null,
    branch_ids: resolvedBranches,
    reference_number: String(referenceNumber || ""),
    notification_type: type,
    ...notificationTaskMetadata({module, notificationType: type}),
    created_at: timestamp,
  };
}

async function closeOpenTasks(transaction, firestore, {
  entityId,
  recipientIds,
  notificationTypes,
  timestamp,
  resolution = "completed",
}) {
  const entity = String(entityId || "").trim();
  const recipients = cleanIds(recipientIds || []);
  const types = new Set(cleanIds(notificationTypes || []));
  if (!entity || recipients.length === 0 || types.size === 0) return 0;

  let closed = 0;
  for (const recipientId of recipients) {
    const snapshot = await transaction.get(
        firestore.collection("notifications")
            .where("entity_id", "==", entity)
            .where("recipient_id", "==", recipientId)
            .where("requires_action", "==", true)
            .limit(50),
    );
    for (const document of snapshot.docs) {
      const data = document.data();
      if (data?.task_status !== "open" || !types.has(data?.notification_type)) continue;
      transaction.update(document.ref, {
        task_status: resolution,
        task_resolved_at: timestamp,
        task_resolution: resolution,
      });
      closed += 1;
    }
  }
  return closed;
}

module.exports = {
  buildNotificationDocument,
  closeOpenTasks,
  notificationTaskMetadata,
  pushEligibility,
};
