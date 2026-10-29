"use strict";

// The request itself continues to be written by the established Firestore
// workflow. This router only creates its notification after independently
// checking the authenticated actor against that persisted request.
const express = require("express");
const crypto = require("crypto");
const {buildNotificationDocument, closeOpenTasks} = require("./notification-task-policy");

const MODULE = "branch_requests";
const COLLECTION = "branch_requests";
const EVENTS = new Set([
  "request_created",
  "branch_task_assigned",
  "administrative_task_assigned",
  "completed",
  "rejected",
]);

function fail(code, status, message) {
  return Object.assign(new Error(message), {code, status, publicMessage: message});
}

function bearerToken(request) {
  const value = request.get("authorization") || "";
  return value.match(/^Bearer\s+(.+)$/i)?.[1] || "";
}

function stringValue(value) {
  return String(value || "").trim();
}

function serverTimestamp(admin) {
  return admin.firestore.FieldValue?.serverTimestamp?.() || new Date();
}

function isActive(profile, role) {
  return profile?.isActive !== false && profile?.mustChangePassword !== true &&
    (!role || profile?.role === role);
}

function notificationId({requestId, event, recipientId}) {
  // A retry after a lost mobile response must not create a second task.
  return crypto.createHash("sha256")
      .update(`branch-request-notification:${requestId}:${event}:${recipientId}`)
      .digest("hex");
}

async function usersByRole(firestore, role) {
  if (!role) return [];
  const snapshot = await firestore.collection("users").where("role", "==", role).get();
  return snapshot.docs.filter((document) => isActive(document.data(), role))
      .map((document) => document.id);
}

async function branchManagers(firestore, branchId) {
  if (!branchId) return [];
  const [branch, profiles] = await Promise.all([
    firestore.collection("branches").doc(branchId).get(),
    firestore.collection("users").where("branchId", "==", branchId).get(),
  ]);
  const recipients = new Set(profiles.docs
      .filter((document) => isActive(document.data(), "manager"))
      .map((document) => document.id));
  const assigned = stringValue(branch.data()?.branch_manager_id);
  if (assigned) {
    const profile = await firestore.collection("users").doc(assigned).get();
    if (isActive(profile.data(), "manager")) recipients.add(assigned);
  }
  return [...recipients];
}

function definitionFor(event, request) {
  const requestTitle = stringValue(request.title) || "بدون عنوان";
  const executorRole = stringValue(request.executor_role) === "accountant" ?
    "accountant" : "collector";
  const executorLabel = executorRole === "accountant" ? "المحاسب" : "المدير العام";
  switch (event) {
    case "request_created":
      return {
        type: "branch_request_created",
        title: "طلب جديد من فرع",
        message: `ورد طلب جديد من الفرع للمراجعة لدى ${executorLabel}: ${requestTitle}.`,
        recipientKind: "request_executor",
        direction: "branch_to_administration",
        status: "new",
        role: "manager",
        owner: "created_by",
      };
    case "branch_task_assigned":
      return {
        type: "branch_task_assigned",
        title: "مهمة جديدة للفرع",
        message: `وردت مهمة جديدة: ${requestTitle}.`,
        recipientKind: "branch_managers",
        direction: "administration_to_branch",
        status: "new",
        roles: ["collector", "accountant"],
        owner: "created_by",
      };
    case "administrative_task_assigned":
      return {
        type: "administrative_task_assigned",
        title: "مهمة جديدة من الإدارة",
        message: `وردت لك مهمة إدارية: ${requestTitle}.`,
        recipientKind: "executor_role",
        direction: "administration_to_administration",
        status: "new",
        roles: ["collector", "accountant"],
        owner: "created_by",
      };
    case "completed":
      return {
        type: "branch_request_completed",
        title: "تم إنجاز الطلب",
        message: `تم إنجاز الطلب: ${requestTitle}.`,
        recipientKind: "requester_and_managers",
        status: "completed",
        owner: "completed_by",
      };
    case "rejected":
      return {
        type: "branch_request_rejected",
        title: "تم رفض الطلب",
        message: `تم رفض الطلب: ${requestTitle}.`,
        recipientKind: "requester",
        status: "rejected",
        owner: "rejected_by",
      };
    default:
      throw fail("invalid-argument", 400, "نوع إشعار غير صالح.");
  }
}

function authorize({actorId, actor, request, definition}) {
  if (!isActive(actor) ||
      (definition.role && actor.role !== definition.role) ||
      (definition.roles && !definition.roles.includes(actor.role)) ||
      (definition.owner && stringValue(request[definition.owner]) !== actorId) ||
      (definition.status && request.status !== definition.status) ||
      (definition.direction && request.direction !== definition.direction)) {
    throw fail("forbidden", 403, "لا تملك صلاحية إرسال هذا الإشعار.");
  }
}

async function recipientsFor(firestore, request, kind) {
  const branchId = stringValue(request.branch_id);
  if (kind === "collectors") return usersByRole(firestore, "collector");
  if (kind === "request_executor") {
    const executorRole = stringValue(request.executor_role) === "accountant" ?
      "accountant" : "collector";
    return usersByRole(firestore, executorRole);
  }
  if (kind === "branch_managers") return branchManagers(firestore, branchId);
  if (kind === "executor_role") return usersByRole(firestore, stringValue(request.executor_role));
  if (kind === "requester") return [stringValue(request.created_by)].filter(Boolean);
  if (kind === "requester_and_managers") {
    return [...new Set([stringValue(request.created_by), ...await branchManagers(firestore, branchId)])]
        .filter(Boolean);
  }
  return [];
}

async function dispatch({admin, firestore, actorId, requestId, event}) {
  const requestReference = firestore.collection(COLLECTION).doc(requestId);
  const [requestSnapshot, actorSnapshot] = await Promise.all([
    requestReference.get(),
    firestore.collection("users").doc(actorId).get(),
  ]);
  if (!requestSnapshot.exists) throw fail("not-found", 404, "تعذر العثور على الطلب.");
  const request = requestSnapshot.data() || {};
  const definition = definitionFor(event, request);
  authorize({actorId, actor: actorSnapshot.data(), request, definition});
  const recipients = (await recipientsFor(firestore, request, definition.recipientKind))
      .filter((recipient) => recipient && recipient !== actorId);
  const timestamp = serverTimestamp(admin);

  await firestore.runTransaction(async (transaction) => {
    // An executor completing/rejecting a request can close only their own
    // actionable task. Other users' historical tasks stay untouched.
    if (event === "completed" || event === "rejected") {
      await closeOpenTasks(transaction, firestore, {
        entityId: requestId,
        recipientIds: [actorId],
        notificationTypes: [
          "branch_request_created",
          "branch_task_assigned",
          "administrative_task_assigned",
        ],
        timestamp,
        resolution: event === "rejected" ? "rejected" : "completed",
      });
    }
    for (const recipientId of recipients) {
      const reference = firestore.collection("notifications").doc(notificationId({
        requestId,
        event,
        recipientId,
      }));
      transaction.set(reference, buildNotificationDocument({
        id: reference.id,
        recipientId,
        title: definition.title,
        message: definition.message,
        module: MODULE,
        entityCollection: COLLECTION,
        entityId: requestId,
        branchId: stringValue(request.branch_id),
        referenceNumber: requestId,
        notificationType: definition.type,
        timestamp,
        extraData: {branch_request_id: requestId},
      }));
    }
  });
  return {recipientCount: recipients.length};
}

function createBranchRequestNotificationRouter({admin, firestore}) {
  if (!admin || !firestore) throw new Error("Firebase Admin and Firestore are required.");
  const router = express.Router();
  const auth = admin.auth();
  router.post("/notifications/branch-requests/:requestId/:event", async (request, response) => {
    try {
      const token = bearerToken(request);
      if (!token) throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً.");
      let decoded;
      try {
        decoded = await auth.verifyIdToken(token, true);
      } catch (_) {
        throw fail("unauthenticated", 401, "يجب تسجيل الدخول أولاً.");
      }
      const requestId = stringValue(request.params.requestId);
      const event = stringValue(request.params.event);
      if (!requestId || !EVENTS.has(event)) {
        throw fail("invalid-argument", 400, "بيانات الإشعار غير صالحة.");
      }
      const result = await dispatch({admin, firestore, actorId: decoded.uid, requestId, event});
      response.status(201).json({ok: true, ...result});
    } catch (error) {
      response.status(error.status || 500).json({
        error: {
          code: error.code || "internal",
          message: error.publicMessage || "تعذر إرسال الإشعار بأمان.",
        },
      });
    }
  });
  return router;
}

module.exports = {createBranchRequestNotificationRouter};
