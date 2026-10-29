"use strict";

const crypto = require("crypto");
const express = require("express");
const {buildNotificationDocument, closeOpenTasks} = require("./notification-task-policy");

const value = (input) => String(input || "").trim();
const fail = (code, status, message) => Object.assign(new Error(message), {code, status, publicMessage: message});
const time = (admin) => admin.firestore.FieldValue?.serverTimestamp?.() || new Date();
const taskId = (id, event, uid) => crypto.createHash("sha256").update(`collection-notification:${id}:${event}:${uid}`).digest("hex");
const token = (request) => (request.get("authorization") || "").match(/^Bearer\s+(.+)$/i)?.[1] || "";

function active(profile) {
  return profile?.isActive !== false && profile?.mustChangePassword !== true;
}

async function roleUsers(firestore, role) {
  const snapshot = await firestore.collection("users").where("role", "==", role).get();
  return snapshot.docs.filter((document) => active(document.data()))
      .map((document) => document.id);
}

async function branchRoleUsers(firestore, role, branchId) {
  if (!branchId) return [];
  const snapshot = await firestore.collection("users")
      .where("role", "==", role).where("branchId", "==", branchId).get();
  return snapshot.docs.filter((document) => active(document.data()))
      .map((document) => document.id);
}

async function activeUserIds(firestore, ids) {
  const unique = [...new Set(ids.map(value).filter(Boolean))];
  if (unique.length === 0) return [];
  const snapshots = await firestore.getAll(...unique.map((uid) => firestore.collection("users").doc(uid)));
  return snapshots.filter((snapshot) => snapshot.exists && active(snapshot.data()))
      .map((snapshot) => snapshot.id);
}

function participantId(voucher, role) {
  return value(voucher.collection_approval_participants?.[role]?.user_id);
}

function participantRecipients(voucher, {exclude = []} = {}) {
  const excluded = new Set(exclude.map(value));
  return [...new Set([
    value(voucher.collectorId),
    value(voucher.physical_collected_by),
    participantId(voucher, "collector"),
    participantId(voucher, "manager"),
    participantId(voucher, "accountant"),
  ])].filter((uid) => uid && !excluded.has(uid));
}

function historyActor(data) {
  const events = Array.isArray(data.history) ? data.history : [];
  const latest = events[events.length - 1] || {};
  return value(latest.actor_id);
}

async function dispatch({admin, firestore, actorId, transactionId, event}) {
  const [snapshot, actorSnapshot] = await Promise.all([
    firestore.collection("transactions").doc(transactionId).get(),
    firestore.collection("users").doc(actorId).get(),
  ]);
  if (!snapshot.exists) throw fail("not-found", 404, "تعذر العثور على سند التحصيل.");
  if (!active(actorSnapshot.data())) throw fail("forbidden", 403, "لا تملك صلاحية تنفيذ هذا الإجراء.");
  const voucher = snapshot.data() || {};
  const amendment = voucher.collection_amendment || {};
  const number = value(voucher.transaction_number) || transactionId;
  const stamp = time(admin);

  if (event === "created") {
    if (!(["pending", "approvedByCollector"].includes(value(voucher.status))) ||
        value(voucher.collectorId) !== actorId || actorSnapshot.data()?.role !== "collector") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار السند الجديد.");
    }
    const recipients = await branchRoleUsers(firestore, "manager", value(voucher.branchId));
    await firestore.runTransaction(async (transaction) => {
      for (const uid of recipients) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "سند جديد بانتظار الاعتماد",
          message: `تم إنشاء السند رقم ${number} في فرعك.`, module: "transactions",
          entityCollection: "transactions", entityId: transactionId, branchId: value(voucher.branchId),
          referenceNumber: number, notificationType: "collection_created", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "reserved") {
    if (voucher.status !== "reservedForCollection" || value(voucher.reviewed_by) !== actorId ||
        actorSnapshot.data()?.role !== "accountant") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار السند المحجوز.");
    }
    const [collectors, managers] = await Promise.all([
      roleUsers(firestore, "collector"),
      branchRoleUsers(firestore, "manager", value(voucher.branchId)),
    ]);
    await firestore.runTransaction(async (transaction) => {
      for (const uid of collectors) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "سند تحصيل مراجع بانتظار التحصيل",
          message: `حجز المحاسب السند رقم ${number} بانتظار الاستلام الفعلي.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_reserved_for_collection", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
      for (const uid of managers) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, `${event}:manager`, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "سند تحصيل مراجع بانتظار التحصيل",
          message: `حجز المحاسب السند رقم ${number} بانتظار الاستلام الفعلي.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_reserved_observation", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "accountant_edit_requested") {
    if (voucher.status !== "editRequestedByCollector" || actorSnapshot.data()?.role !== "accountant" ||
        historyActor(voucher) !== actorId) {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال طلب التعديل.");
    }
    const recipients = await activeUserIds(firestore, [value(voucher.collectorId)]);
    await firestore.runTransaction(async (transaction) => {
      for (const uid of recipients) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "سند التحصيل يحتاج إلى تعديل",
          message: `طلب المحاسب تعديل السند رقم ${number}. يرجى مراجعته وتحديثه.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_accountant_edit_requested", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "manager_approved") {
    if (voucher.status !== "approvedByManager" ||
        value(voucher.collection_approval_participants?.manager?.user_id) !== actorId ||
        actorSnapshot.data()?.role !== "manager") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار الاعتماد.");
    }
    const recipients = await roleUsers(firestore, "accountant");
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: [actorId],
        notificationTypes: ["collection_created"], timestamp: stamp,
      });
      for (const uid of recipients) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({id: ref.id, recipientId: uid, title: "سند جاهز للمراجعة المالية", message: `اعتمد مدير الفرع السند رقم ${number} وأصبح جاهزاً للمراجعة.`, module: "transactions", entityCollection: "transactions", entityId: transactionId, branchId: value(voucher.branchId), referenceNumber: number, notificationType: "collection_manager_approved", timestamp: stamp, extraData: {transaction_id: transactionId, transaction_number: number}}));
      }
    });
    return;
  }

  if (event === "accountant_approved") {
    if (voucher.status !== "approvedByAccountant" ||
        participantId(voucher, "accountant") !== actorId ||
        actorSnapshot.data()?.role !== "accountant") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار الاعتماد.");
    }
    const accountants = await roleUsers(firestore, "accountant");
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: accountants,
        notificationTypes: ["collection_manager_approved", "collection_difference_pending_review"],
        timestamp: stamp,
      });
      for (const uid of participantRecipients(voucher, {exclude: [actorId]})) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "تم اعتماد سند التحصيل نهائياً",
          message: `اعتمد المحاسب السند رقم ${number} اعتماداً نهائياً.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_accountant_approved", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "difference_pending") {
    if (voucher.status !== "collectionDifferencePendingReview" ||
        value(voucher.physical_collected_by) !== actorId ||
        actorSnapshot.data()?.role !== "collector") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار فرق التحصيل.");
    }
    const recipients = await roleUsers(firestore, "accountant");
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: [actorId],
        notificationTypes: ["collection_reserved_for_collection"], timestamp: stamp,
      });
      for (const uid of recipients) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "فرق تحصيل بانتظار مراجعتك",
          message: `سُجل فرق في تحصيل السند رقم ${number} ويحتاج اعتمادك.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_difference_pending_review", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "collected") {
    if (voucher.status !== "pending" || value(voucher.physical_collected_by) !== actorId ||
        actorSnapshot.data()?.role !== "collector") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار التحصيل.");
    }
    const [accountants, managers] = await Promise.all([
      roleUsers(firestore, "accountant"),
      branchRoleUsers(firestore, "manager", value(voucher.branchId)),
    ]);
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: [actorId],
        notificationTypes: ["collection_reserved_for_collection"], timestamp: stamp,
      });
      for (const uid of [...new Set([...accountants, ...managers])]) {
        if (uid === actorId) continue;
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "تم التحصيل الفعلي للسند",
          message: `تم تسجيل التحصيل الفعلي للسند رقم ${number} ودخل مساره المعتاد.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_voucher_physically_collected", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "difference_decision") {
    if (voucher.status !== "pending" || value(voucher.difference_reviewed_by) !== actorId ||
        actorSnapshot.data()?.role !== "accountant") {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال قرار فرق التحصيل.");
    }
    const accountants = await roleUsers(firestore, "accountant");
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: accountants,
        notificationTypes: ["collection_difference_pending_review"], timestamp: stamp,
      });
      for (const uid of participantRecipients(voucher, {exclude: [actorId]})) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({
          id: ref.id, recipientId: uid, title: "تمت مراجعة فرق التحصيل",
          message: `راجع المحاسب فرق تحصيل السند رقم ${number} وأعاده لمساره المعتاد.`,
          module: "transactions", entityCollection: "transactions", entityId: transactionId,
          branchId: value(voucher.branchId), referenceNumber: number,
          notificationType: "collection_difference_reviewed", timestamp: stamp,
          extraData: {transaction_id: transactionId, transaction_number: number},
        }));
      }
    });
    return;
  }

  if (event === "amendment_requested") {
    const requester = value(amendment.requested_by?.user_id);
    const approvers = amendment.required_approvers && typeof amendment.required_approvers === "object" ? amendment.required_approvers : {};
    if (amendment.state !== "pending" || requester !== actorId || Object.keys(approvers).length === 0) {
      throw fail("forbidden", 403, "لا تملك صلاحية إرسال إشعار هذا التعديل.");
    }
    await firestore.runTransaction(async (transaction) => {
      await closeOpenTasks(transaction, firestore, {
        entityId: transactionId, recipientIds: [actorId],
        notificationTypes: ["collection_accountant_edit_requested"], timestamp: stamp,
      });
      for (const uid of Object.keys(approvers).filter((uid) => uid && uid !== actorId)) {
        const ref = firestore.collection("notifications").doc(taskId(transactionId, event, uid));
        transaction.set(ref, buildNotificationDocument({id: ref.id, recipientId: uid, title: "تعديل سند تحصيل بانتظار موافقتك", message: `يوجد تعديل على السند رقم ${number} يحتاج مراجعتك وموافقتك.`, module: "transactions", entityCollection: "transactions", entityId: transactionId, branchId: value(voucher.branchId), referenceNumber: number, notificationType: "collection_amendment_requested", timestamp: stamp, extraData: {transaction_id: transactionId, transaction_number: number}}));
      }
    });
    return;
  }

  if (event === "amendment_decision") {
    const approvals = amendment.approvals && typeof amendment.approvals === "object" ? amendment.approvals : {};
    const approvedByActor = value(approvals[actorId]?.user_id || approvals[actorId]?.actor_id) === actorId;
    const completedByActor = historyActor(voucher) === actorId;
    if (!approvedByActor && !completedByActor) throw fail("forbidden", 403, "لا تملك صلاحية إرسال قرار هذا التعديل.");
    await firestore.runTransaction((transaction) => closeOpenTasks(transaction, firestore, {entityId: transactionId, recipientIds: [actorId], notificationTypes: ["collection_amendment_requested"], timestamp: stamp, resolution: amendment.state === "pending" ? "completed" : "resolved"}));
    return;
  }
  throw fail("invalid-argument", 400, "نوع إشعار غير صالح.");
}

function createCollectionNotificationRouter({admin, firestore}) {
  const router = express.Router(); const auth = admin.auth();
  router.post("/notifications/collections/:transactionId/:event", async (request, response) => {
    try { const raw = token(request); if (!raw) throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً."); let decoded; try { decoded = await auth.verifyIdToken(raw, true); } catch (_) { throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً."); } const event = value(request.params.event); if (!["created", "reserved", "accountant_edit_requested", "amendment_requested", "amendment_decision", "manager_approved", "accountant_approved", "difference_pending", "difference_decision", "collected"].includes(event)) throw fail("invalid-argument", 400, "بيانات الإشعار غير صالحة."); await dispatch({admin, firestore, actorId: decoded.uid, transactionId: value(request.params.transactionId), event}); response.status(201).json({ok: true}); } catch (error) { response.status(error.status || 500).json({error: {code: error.code || "internal", message: error.publicMessage || "تعذر إرسال الإشعار بأمان."}}); }
  }); return router;
}
module.exports = {createCollectionNotificationRouter};
