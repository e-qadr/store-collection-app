"use strict";

const crypto = require("crypto");
const express = require("express");
const {buildNotificationDocument, closeOpenTasks} = require("./notification-task-policy");

const COLLECTION = "cash_expense_requests";
const MODULE = COLLECTION;
const EVENTS = new Set(["created", "manager_updated_before_review", "general_manager_decision", "invoice_ready", "accounting_approved", "edit_requested", "edit_decision"]);

const value = (item) => String(item || "").trim();
const fail = (code, status, message) => Object.assign(new Error(message), {code, status, publicMessage: message});
const timestamp = (admin) => admin.firestore.FieldValue?.serverTimestamp?.() || new Date();
const notificationId = (id, event, recipient) => crypto.createHash("sha256")
    .update(`cash-expense-notification:${id}:${event}:${recipient}`).digest("hex");

function token(request) {
  return (request.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1] || "";
}

function active(profile, role) {
  return profile?.isActive !== false && profile?.mustChangePassword !== true && (!role || profile?.role === role);
}

async function roleUsers(firestore, role) {
  const results = await firestore.collection("users").where("role", "==", role).get();
  return results.docs.filter((doc) => active(doc.data(), role)).map((doc) => doc.id);
}

function approvalUsers(request) {
  const required = Array.isArray(request.edit_request?.required_parties) ? request.edit_request.required_parties : [];
  const approvals = request.edit_approvals || {};
  const candidates = {
    manager: value(request.created_by),
    general_manager: value(request.reviewed_by),
    accountant: value(request.approved_by),
  };
  return required.filter((party) => !approvals[party]).map((party) => candidates[party]).filter(Boolean);
}

function definition(event, request, actorId, actor) {
  const number = value(request.request_number) || `CE-${request.id || ""}`;
  const status = value(request.status);
  const title = value(request.title) || "بدون عنوان";
  const actorOwns = (field) => value(String(field).split(".").reduce(
      (current, key) => current?.[key], request)) === actorId;
  if (!active(actor)) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
  switch (event) {
    case "created":
      if (!(actor.role === "manager" && actorOwns("created_by") && status === "pendingGeneralManagerReview")) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      return {type: "cash_expense_created", title: "سند صرف نقدي جديد", message: `سند الصرف رقم ${number} بانتظار مراجعة المدير العام.`, recipientRole: "collector"};
    case "manager_updated_before_review":
      if (!(actor.role === "manager" && actorOwns("created_by") && status === "pendingGeneralManagerReview")) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      return {type: "cash_expense_manager_updated_after_edit", title: "سند صرف معدل بانتظار المراجعة", message: `عدّل مدير الفرع سند الصرف رقم ${number} قبل مراجعة المدير العام.`, recipientRole: "collector"};
    case "general_manager_decision":
      if (!(actor.role === "collector" && actorOwns("reviewed_by"))) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      if (status === "pendingInvoiceAttachment") return {type: "cash_expense_invoice_required", title: "سند الصرف يحتاج فاتورة", message: `اعتمد المدير العام السند رقم ${number} وهو بانتظار إرفاق الفاتورة.`, recipients: [value(request.created_by)]};
      if (status === "pendingAccountingApproval") return {type: "cash_expense_general_manager_approved", title: "سند صرف جاهز للمحاسبة", message: `اعتمد المدير العام سند الصرف رقم ${number} وهو بانتظار اعتمادك.`, recipientRole: "accountant"};
      if (status === "rejectedByGeneralManager") return {type: "cash_expense_rejected_by_general_manager", title: "تم رفض سند الصرف", message: `رُفض سند الصرف رقم ${number}.`, recipients: [value(request.created_by)]};
      break;
    case "invoice_ready":
      if (!(actor.role === "manager" && actorOwns("invoice_approved_by") && status === "pendingAccountingApproval")) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      return {type: "cash_expense_invoice_ready", title: "سند صرف بانتظار الاعتماد المحاسبي", message: `تم تجهيز فاتورة سند الصرف رقم ${number} لاعتماد المحاسب.`, recipientRole: "accountant"};
    case "accounting_approved":
      if (!(actor.role === "accountant" && actorOwns("approved_by") && status === "approvedByAccountant")) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      return {type: "cash_expense_accounting_approved", title: "تم اعتماد سند الصرف", message: `اعتمد المحاسب سند الصرف رقم ${number} نهائياً.`, recipients: [value(request.created_by), value(request.reviewed_by), value(request.invoice_approved_by)]};
    case "edit_requested":
      if (!(status === "editPendingApprovals" && actorOwns("edit_request.requested_by"))) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      return {type: "cash_expense_edit_requested", title: "طلب تعديل سند صرف", message: `سند الصرف رقم ${number} لديه طلب تعديل بانتظار موافقتك.`, recipients: approvalUsers(request)};
    case "edit_decision": {
      const party = actor.role === "manager" ? "manager" : actor.role === "collector" ? "general_manager" : actor.role === "accountant" ? "accountant" : "";
      if (!party || value(request.edit_approvals?.[party]?.actor_id) !== actorId) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
      const approved = request.edit_approvals?.[party]?.approved === true;
      return {type: approved ? "cash_expense_edit_decision" : "cash_expense_edit_rejected", title: approved ? "تم تسجيل قرار تعديل السند" : "تم رفض طلب تعديل سند الصرف", message: approved ? `تم تسجيل قرار على تعديل السند رقم ${number}.` : `تم رفض طلب تعديل السند رقم ${number}.`, recipients: [value(request.edit_request?.requested_by), value(request.created_by)]};
    }
    default: break;
  }
  throw fail("invalid-state", 409, "حالة السند لا تطابق الإشعار المطلوب.");
}

async function dispatch({admin, firestore, actorId, requestId, event}) {
  const [expenseSnapshot, actorSnapshot] = await Promise.all([
    firestore.collection(COLLECTION).doc(requestId).get(),
    firestore.collection("users").doc(actorId).get(),
  ]);
  if (!expenseSnapshot.exists) throw fail("not-found", 404, "تعذر العثور على سند الصرف.");
  const request = expenseSnapshot.data() || {};
  const item = definition(event, request, actorId, actorSnapshot.data());
  const recipients = (item.recipients || await roleUsers(firestore, item.recipientRole))
      .filter((id) => id && id !== actorId);
  const now = timestamp(admin);
  await firestore.runTransaction(async (transaction) => {
    if (["general_manager_decision", "invoice_ready", "accounting_approved", "edit_decision"].includes(event)) {
      await closeOpenTasks(transaction, firestore, {entityId: requestId, recipientIds: [actorId], notificationTypes: ["cash_expense_created", "cash_expense_invoice_required", "cash_expense_general_manager_approved", "cash_expense_invoice_ready", "cash_expense_edit_requested"], timestamp: now, resolution: event === "edit_decision" && item.type === "cash_expense_edit_rejected" ? "rejected" : "completed"});
    }
    for (const recipientId of [...new Set(recipients)]) {
      const ref = firestore.collection("notifications").doc(notificationId(requestId, event, recipientId));
      transaction.set(ref, buildNotificationDocument({id: ref.id, recipientId, title: item.title, message: item.message, module: MODULE, entityCollection: COLLECTION, entityId: requestId, branchId: value(request.branch_id), referenceNumber: value(request.request_number), notificationType: item.type, timestamp: now, extraData: {cash_expense_request_id: requestId}}));
    }
  });
}

function createCashExpenseNotificationRouter({admin, firestore}) {
  const router = express.Router();
  const auth = admin.auth();
  router.post("/notifications/cash-expenses/:requestId/:event", async (request, response) => {
    try {
      const rawToken = token(request);
      if (!rawToken) throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً.");
      let decoded;
      try { decoded = await auth.verifyIdToken(rawToken, true); } catch (_) { throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً."); }
      const requestId = value(request.params.requestId);
      const event = value(request.params.event);
      if (!requestId || !EVENTS.has(event)) throw fail("invalid-argument", 400, "بيانات الإشعار غير صالحة.");
      await dispatch({admin, firestore, actorId: decoded.uid, requestId, event});
      response.status(201).json({ok: true});
    } catch (error) {
      response.status(error.status || 500).json({error: {code: error.code || "internal", message: error.publicMessage || "تعذر إرسال الإشعار بأمان."}});
    }
  });
  return router;
}

module.exports = {createCashExpenseNotificationRouter};
