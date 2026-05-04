const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "asia-southeast1" });

exports.getAuthUidByEmail = onCall(async (request) => {
  const auth = request.auth;
  if (!auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication is required."
    );
  }

  const adminUserSnap = await admin
    .firestore()
    .collection("users")
    .where("authUid", "==", auth.uid)
    .where("role", "==", "Admin")
    .limit(1)
    .get();
  if (adminUserSnap.empty) {
    throw new HttpsError(
      "permission-denied",
      "Only Admin users can resolve Firebase Auth UID by email."
    );
  }

  const emailRaw = request.data?.email;
  if (typeof emailRaw !== "string" || emailRaw.trim() === "") {
    throw new HttpsError("invalid-argument", "email is required.");
  }
  const email = emailRaw.trim().toLowerCase();

  try {
    const user = await admin.auth().getUserByEmail(email);
    return { uid: user.uid };
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      throw new HttpsError(
        "not-found",
        `No Firebase Auth user found for email "${email}".`
      );
    }
    throw new HttpsError("internal", error?.message || "Unknown error.");
  }
});
