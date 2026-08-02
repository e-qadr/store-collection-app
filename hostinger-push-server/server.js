require("dotenv").config();

const express = require("express");
const admin = require("firebase-admin");

const app = express();
const port = Number(process.env.PORT || 3000);
const pollIntervalMs = Number(process.env.POLL_INTERVAL_MS || 5000);
const androidNotificationChannelId =
  process.env.ANDROID_NOTIFICATION_CHANNEL_ID || "high_importance_channel";

let workerRunning = false;
let lastWorkerRunAt;
let lastWorkerError;
let firestore;
let firebaseConfigurationError;

function loadFirebaseCredential() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_BASE64) {
    const json = Buffer.from(
        process.env.FIREBASE_SERVICE_ACCOUNT_BASE64,
        "base64",
    ).toString("utf8");
    return JSON.parse(json);
  }

  const requiredEnvironmentVariables = [
    "FIREBASE_PROJECT_ID",
    "FIREBASE_CLIENT_EMAIL",
    "FIREBASE_PRIVATE_KEY",
  ];
  const missing = requiredEnvironmentVariables.filter(
      (variable) => !process.env[variable],
  );
  if (missing.length > 0) {
    throw new Error(`Missing environment variables: ${missing.join(", ")}`);
  }

  return {
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY
        .replace(/^["']|["']$/g, "")
        .replace(/\\n/g, "\n"),
  };
}

function stringValue(value) {
  if (value === undefined || value === null) return "";
  return String(value);
}

function notificationDataPayload(reference, notification, title, body) {
  const module = stringValue(
      notification.module ?? notification.entity_collection ?? "transactions",
  );
  const entityCollection = stringValue(
      notification.entity_collection ?? module,
  );
  const transactionId = stringValue(notification.transaction_id);
  const entityId = stringValue(notification.entity_id ?? transactionId);
  const referenceNumber = stringValue(
      notification.reference_number ?? notification.transaction_number,
  );
  const branchIds = Array.isArray(notification.branch_ids) ?
    notification.branch_ids.map(stringValue).filter(Boolean).join(",") :
    "";

  return {
    notification_id: reference.id,
    title,
    message: body,
    module,
    entity_id: entityId,
    entity_collection: entityCollection,
    reference_number: referenceNumber,
    notification_type: stringValue(notification.notification_type),
    branch_id: stringValue(notification.branch_id),
    branch_ids: branchIds,
    transaction_id: transactionId,
    transaction_number: stringValue(notification.transaction_number),
    consumable_request_id: stringValue(notification.consumable_request_id),
    cash_expense_request_id: stringValue(notification.cash_expense_request_id),
    inter_branch_invoice_id: stringValue(notification.inter_branch_invoice_id),
  };
}

try {
  admin.initializeApp({
    credential: admin.credential.cert(loadFirebaseCredential()),
  });
  firestore = admin.firestore();
} catch (error) {
  firebaseConfigurationError = String(error?.message ?? error);
  console.error("Firebase configuration failed", error);
}

app.get("/", (_request, response) => {
  response.json({
    service: "store-collection-push-server",
    status: firebaseConfigurationError ? "configuration_error" : "running",
  });
});

app.get("/health", (_request, response) => {
  response.status(firebaseConfigurationError ? 500 : 200).json({
    status: firebaseConfigurationError ? "configuration_error" : "ok",
    firebaseReady: !firebaseConfigurationError,
    configurationError: firebaseConfigurationError ?? null,
    workerRunning,
    pollIntervalMs,
    androidNotificationChannelId,
    lastWorkerRunAt: lastWorkerRunAt ?? null,
    lastWorkerError: lastWorkerError ?? null,
    timestamp: new Date().toISOString(),
  });
});

async function claimNotification(reference) {
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.data();
    if (!snapshot.exists || data?.push_status !== "pending") return null;

    transaction.update(reference, {
      push_status: "processing",
      push_processing_started_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return data;
  });
}

async function processNotification(reference) {
  const notification = await claimNotification(reference);
  if (!notification) return;

  try {
    const recipientId = notification.recipient_id;
    const userReference = firestore.collection("users").doc(recipientId);
    const userSnapshot = await userReference.get();
    const tokens = [...new Set(userSnapshot.data()?.notification_tokens ?? [])]
        .filter((token) => typeof token === "string" && token.length > 0);

    if (tokens.length === 0) {
      await reference.update({
        push_status: "no_tokens",
        push_processed_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const title = String(notification.title ?? "إشعار جديد");
    const body = String(notification.message ?? "");
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        body,
      },
      data: notificationDataPayload(reference, notification, title, body),
      android: {
        priority: "high",
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          channelId: androidNotificationChannelId,
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          defaultSound: true,
          defaultVibrateTimings: true,
          priority: "high",
          sound: "default",
          visibility: "public",
        },
      },
      apns: {
        headers: {"apns-priority": "10"},
        payload: {aps: {sound: "default", badge: 1}},
      },
    });

    const invalidTokens = [];
    result.responses.forEach((response, index) => {
      const code = response.error?.code;
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token") {
        invalidTokens.push(tokens[index]);
      }
    });

    if (invalidTokens.length > 0) {
      await userReference.update({
        notification_tokens:
            admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }

    await reference.update({
      push_status: result.failureCount === 0 ? "sent" : "partially_sent",
      push_success_count: result.successCount,
      push_failure_count: result.failureCount,
      push_message_ids: result.responses
          .map((response) => response.messageId)
          .filter(Boolean),
      push_error_codes: result.responses
          .map((response) => response.error?.code)
          .filter(Boolean),
      push_processed_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error(`Failed notification ${reference.id}`, error);
    await reference.update({
      push_status: "pending",
      push_last_error: String(error?.message ?? error),
      push_last_error_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

async function processPendingNotifications() {
  if (workerRunning || !firestore) return;
  workerRunning = true;

  try {
    lastWorkerRunAt = new Date().toISOString();
    lastWorkerError = undefined;
    const snapshot = await firestore
        .collection("notifications")
        .where("push_status", "==", "pending")
        .limit(25)
        .get();

    await Promise.all(snapshot.docs.map((document) =>
      processNotification(document.ref)));
  } catch (error) {
    lastWorkerError = String(error?.message ?? error);
    console.error("Notification worker failed", error);
  } finally {
    workerRunning = false;
  }
}

app.listen(port, () => {
  console.log(`Push server listening on port ${port}`);
  processPendingNotifications();
  setInterval(processPendingNotifications, pollIntervalMs);
});
