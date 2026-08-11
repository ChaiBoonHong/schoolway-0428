const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");
const { notificationPolicy } = require("./notification_policy");

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
      const role = userDoc.data().role;

      let preferences = null;
      const canonicalPrefs = await userDoc.ref
        .collection("notification_prefs")
        .doc("settings")
        .get();
      if (canonicalPrefs.exists) {
        preferences = canonicalPrefs.data();
      } else {
        const legacyPrefs = await db
          .collection("users")
          .doc(authUid)
          .collection("notification_prefs")
          .doc("settings")
          .get();
        if (legacyPrefs.exists) preferences = legacyPrefs.data();
      }

      const policy = notificationPolicy(data, preferences, role);
      if (!policy.deliver) {
        await snap.ref.delete();
        console.log(`Notification disabled by ${userDoc.id}`);
        return;
      }
      if (data.isCritical !== policy.critical || !data.category) {
        await snap.ref.update({
          category: data.category || data.type || "system",
          isCritical: policy.critical,
        });
      }
      if (policy.quiet) {
        console.log(`Notification retained in inbox during quiet hours for ${userDoc.id}`);
        return;
      }

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

      if (policy.critical) {
        message.android = {
          priority: "high",
          notification: {
            channelId: "schoolway_emergency",
            priority: "max",
            sound: "default",
          },
        };
        message.apns = {
          headers: { "apns-priority": "10" },
          payload: { aps: { "interruption-level": "time-sensitive" } },
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
