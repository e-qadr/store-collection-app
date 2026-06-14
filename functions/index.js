const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});

exports.sendTransactionNotification = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => {
      const notification = event.data?.data();
      if (!notification) return;

      const recipientId = notification.recipient_id;
      if (!recipientId) {
        logger.warn("Notification has no recipient_id", {
          notificationId: event.params.notificationId,
        });
        return;
      }

      const userRef = admin.firestore().collection("users").doc(recipientId);
      const userSnapshot = await userRef.get();
      const tokens = [...new Set(userSnapshot.data()?.notification_tokens ?? [])]
          .filter((token) => typeof token === "string" && token.length > 0);

      if (tokens.length === 0) {
        await event.data.ref.update({
          push_status: "no_tokens",
          push_processed_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const response = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: String(notification.title ?? "إشعار جديد"),
          body: String(notification.message ?? ""),
        },
        data: {
          notification_id: event.params.notificationId,
          transaction_id: String(notification.transaction_id ?? ""),
          branch_id: String(notification.branch_id ?? ""),
          transaction_number: String(notification.transaction_number ?? ""),
        },
        android: {
          priority: "high",
          notification: {
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      const invalidTokens = [];
      response.responses.forEach((result, index) => {
        const code = result.error?.code;
        if (code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token") {
          invalidTokens.push(tokens[index]);
        }
      });

      if (invalidTokens.length > 0) {
        await userRef.update({
          notification_tokens:
              admin.firestore.FieldValue.arrayRemove(...invalidTokens),
        });
      }

      await event.data.ref.update({
        push_status: response.failureCount === 0 ? "sent" : "partially_sent",
        push_success_count: response.successCount,
        push_failure_count: response.failureCount,
        push_processed_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    },
);
