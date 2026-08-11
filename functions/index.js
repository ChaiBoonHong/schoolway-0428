const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");

admin.initializeApp();
setGlobalOptions({ region: "asia-southeast1" });

exports.sendNotificationOnBoarding = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    database: "schoolway"
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (!data) return;

    const authUid = data.userId;
    const title = data.title;
    const body = data.body;

    if (!authUid) {
      console.log("No authUid (userId) provided for notification");
      return;
    }

    try {
      const db = getFirestore(admin.app(), "schoolway");
      
      // Find the user document that matches this authUid
      const usersSnapshot = await db
        .collection("users")
        .where("authUid", "==", authUid)
        .limit(1)
        .get();

      if (usersSnapshot.empty) {
        console.log(`User with authUid ${authUid} not found`);
        return;
      }

      const userDoc = usersSnapshot.docs[0];
      const fcmToken = userDoc.data().fcmToken;

      if (!fcmToken) {
        console.log(`User ${userDoc.id} has no fcmToken`);
        return;
      }

      const message = {
        notification: {
          title: title || "New Notification",
          body: body || "",
        },
        token: fcmToken,
      };

      if (data.type === "emergency") {
        message.android = {
          priority: "high",
          notification: {
            channelId: "schoolway_emergency",
            priority: "max",
            sound: "default",
          },
        };
      }

      // Send the native push notification via FCM (HTTP v1 API)
      const response = await admin.messaging().send(message);
      console.log(`Successfully sent message to ${userDoc.id}:`, response);
    } catch (error) {
      console.error("Error sending push notification:", error);
    }
  }
);
