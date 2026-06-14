require("dotenv").config();

const express = require("express");
const admin = require("firebase-admin");

const requiredEnvironmentVariables = [
  "FIREBASE_PROJECT_ID",
  "FIREBASE_CLIENT_EMAIL",
  "FIREBASE_PRIVATE_KEY",
];

for (const variable of requiredEnvironmentVariables) {
  if (!process.env[variable]) {
    throw new Error(`Missing required environment variable: ${variable}`);
  }
}

admin.initializeApp({
  credential: admin.credential.cert({
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, "\n"),
  }),
});

const firestore = admin.firestore();
const app = express();
const port = Number(process.env.PORT || 3000);
const pollIntervalMs = Number(process.env.POLL_INTERVAL_MS || 5000);

let workerRunning = false;

app.get("/", (_request, response) => {
  response.json({
    service: "store-collection-push-server",
    status: "running",
  });
});

app.get("/health", (_request, response) => {
  response.json({
    status: "ok",
    workerRunning,
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

    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: String(notification.title ?? "إشعار جديد"),
        body: String(notification.message ?? ""),
      },
      data: {
        notification_id: reference.id,
        transaction_id: String(notification.transaction_id ?? ""),
        branch_id: String(notification.branch_id ?? ""),
        transaction_number: String(notification.transaction_number ?? ""),
      },
      android: {
        priority: "high",
        notification: {sound: "default"},
      },
      apns: {
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
  if (workerRunning) return;
  workerRunning = true;

  try {
    const snapshot = await firestore
        .collection("notifications")
        .where("push_status", "==", "pending")
        .limit(25)
        .get();

    await Promise.all(snapshot.docs.map((document) =>
      processNotification(document.ref)));
  } catch (error) {
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
