"use strict";
const crypto = require("crypto");
const express = require("express");
const {buildNotificationDocument, closeOpenTasks} = require("./notification-task-policy");
const COLLECTION = "consumable_requests";
const EVENTS = new Set(["created", "collector_reviewed", "accounting_approved", "rejected"]);
const value = (item) => String(item || "").trim();
const fail = (code, status, message) => Object.assign(new Error(message), {code, status, publicMessage: message});
const now = (admin) => admin.firestore.FieldValue?.serverTimestamp?.() || new Date();
const notificationId = (id, event, recipient) => crypto.createHash("sha256").update(`consumable-notification:${id}:${event}:${recipient}`).digest("hex");
const token = (request) => (request.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1] || "";
const active = (profile, role) => profile?.isActive !== false && profile?.mustChangePassword !== true && (!role || profile?.role === role);

async function roleUsers(firestore, role) {
  const result = await firestore.collection("users").where("role", "==", role).get();
  return result.docs.filter((doc) => active(doc.data(), role)).map((doc) => doc.id);
}

function definition(event, request, actorId, actor) {
  const number = value(request.request_number) || "طلب المستهلكات";
  const status = value(request.status);
  if (!active(actor)) throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
  if (event === "created" && actor.role === "manager" && value(request.created_by) === actorId && status === "pendingCollectorReview") return {type: "consumable_request_created", title: "طلب مستهلكات جديد", message: `طلب المستهلكات رقم ${number} بانتظار مراجعة المدير العام.`, role: "collector"};
  if (event === "collector_reviewed" && actor.role === "collector" && value(request.reviewed_by) === actorId && status === "pendingAccountingApproval") return {type: "consumable_collector_reviewed", title: "طلب مستهلكات جاهز للمحاسبة", message: `تمت مراجعة طلب المستهلكات رقم ${number} وهو بانتظار اعتمادك.`, role: "accountant"};
  if (event === "accounting_approved" && actor.role === "accountant" && value(request.approved_by) === actorId && status === "approvedByAccountant") return {type: "consumable_accounting_approved", title: "تم اعتماد طلب المستهلكات", message: `تم اعتماد طلب المستهلكات رقم ${number} نهائياً.`, recipients: [value(request.created_by), value(request.reviewed_by)]};
  if (event === "rejected" && value(request.rejected_by) === actorId && ["rejectedByCollector", "rejectedByAccountant"].includes(status)) return {type: "consumable_request_rejected", title: "تم رفض طلب المستهلكات", message: `تم رفض طلب المستهلكات رقم ${number}.`, recipients: [value(request.created_by), status === "rejectedByAccountant" ? value(request.reviewed_by) : ""]};
  throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
}

async function dispatch({admin, firestore, actorId, requestId, event}) {
  const [snapshot, actorSnapshot] = await Promise.all([firestore.collection(COLLECTION).doc(requestId).get(), firestore.collection("users").doc(actorId).get()]);
  if (!snapshot.exists) throw fail("not-found", 404, "تعذر العثور على طلب المستهلكات.");
  const request = snapshot.data() || {};
  const item = definition(event, request, actorId, actorSnapshot.data());
  const recipients = (item.recipients || await roleUsers(firestore, item.role)).filter((id) => id && id !== actorId);
  const serverTime = now(admin);
  await firestore.runTransaction(async (transaction) => {
    if (event !== "created") await closeOpenTasks(transaction, firestore, {entityId: requestId, recipientIds: [actorId], notificationTypes: ["consumable_request_created", "consumable_collector_reviewed"], timestamp: serverTime, resolution: event === "rejected" ? "rejected" : "completed"});
    for (const recipientId of [...new Set(recipients)]) {
      const ref = firestore.collection("notifications").doc(notificationId(requestId, event, recipientId));
      transaction.set(ref, buildNotificationDocument({id: ref.id, recipientId, title: item.title, message: item.message, module: COLLECTION, entityCollection: COLLECTION, entityId: requestId, branchId: value(request.branch_id), referenceNumber: value(request.request_number), notificationType: item.type, timestamp: serverTime, extraData: {consumable_request_id: requestId}}));
    }
  });
}

function createConsumableNotificationRouter({admin, firestore}) {
  const router = express.Router(); const auth = admin.auth();
  router.post("/notifications/consumables/:requestId/:event", async (request, response) => {
    try { const rawToken = token(request); if (!rawToken) throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً."); let decoded; try { decoded = await auth.verifyIdToken(rawToken, true); } catch (_) { throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً."); } const requestId = value(request.params.requestId); const event = value(request.params.event); if (!requestId || !EVENTS.has(event)) throw fail("invalid-argument", 400, "بيانات الإشعار غير صالحة."); await dispatch({admin, firestore, actorId: decoded.uid, requestId, event}); response.status(201).json({ok: true}); } catch (error) { response.status(error.status || 500).json({error: {code: error.code || "internal", message: error.publicMessage || "تعذر إرسال الإشعار بأمان."}}); }
  }); return router;
}
module.exports = {createConsumableNotificationRouter};
