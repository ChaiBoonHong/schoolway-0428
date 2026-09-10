const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const crypto = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { notificationPolicy } = require("./notification_policy");
const { GoogleRoutesClient } = require("./routes_client");
const {
  handleComputePlannedRoute,
  handleGetTrafficEta,
  handleMigrateRouteGeometry,
} = require("./routes_callables");

const googleRoutesApiKey = defineSecret("GOOGLE_ROUTES_API_KEY");

const firebaseApp = initializeApp();
setGlobalOptions({ region: "asia-southeast1", maxInstances: 20 });
const db = getFirestore(firebaseApp, "schoolway");
const auth = getAuth(firebaseApp);
const messaging = getMessaging(firebaseApp);

function incidentId() {
  return `SW-${crypto.randomBytes(3).toString("hex").toUpperCase()}`;
}

function redact(value) {
  return String(value || "")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[REDACTED_EMAIL]")
    .replace(/(password|secret|token|authorization|api[_-]?key)\s*[:=]\s*\S+/gi,
      "$1=[REDACTED]")
    .replace(/bearer\s+[a-z0-9._~+/=-]+/gi, "Bearer [REDACTED]")
    .slice(0, 4000);
}

function logFailure(level, operation, error, reference = incidentId()) {
  const write = level === "warning" ? logger.warn : logger.error;
  write("SchoolWay operation failed", {
    operation,
    incidentId: reference,
    errorType: error?.constructor?.name || "Error",
    errorCode: redact(error?.code || "unknown"),
    stack: redact(error?.stack || ""),
  });
  return reference;
}

function sanitizedCallableError(error, operation) {
  if (error instanceof HttpsError) return error;
  const reference = logFailure("error", operation, error);
  return new HttpsError(
    "internal",
    `The operation could not be completed. Reference ${reference}.`,
  );
}

async function requireAdmin(request) {
  if (!request.auth?.uid) {
    logger.warn("Callable authorization denied", {
      operation: "requireAdmin",
      reason: "unauthenticated",
    });
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const caller = await db.collection("users").doc(request.auth.uid).get();
  const role = String(caller.data()?.role || "").toLowerCase();
  if (!caller.exists || (role !== "admin" && role !== "administrator")) {
    logger.warn("Callable authorization denied", {
      operation: "requireAdmin",
      reason: "insufficient-role",
    });
    throw new HttpsError("permission-denied", "Administrator access is required.");
  }
}

function requiredString(value, field, maxLength = 200) {
  const normalized = String(value || "").trim();
  if (!normalized || normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", field + " is invalid.");
  }
  return normalized;
}

function normalizedRole(value) {
  const role = String(value || "").trim().toLowerCase();
  if (!["admin", "driver", "parent"].includes(role)) {
    throw new HttpsError("invalid-argument", "role is invalid.");
  }
  return role;
}

async function syncParentBusAccess(database, uid) {
  const students = await database
    .collection("students")
    .where("parentAuthUids", "array-contains", uid)
    .get();
  const busIds = [...new Set(students.docs
    .map((student) => String(student.data().assignedBusId || "").trim())
    .filter(Boolean))];
  await Promise.all(busIds.map((busId) => database
    .collection("bus_access")
    .doc(busId)
    .collection("members")
    .doc(uid)
    .set({ uid, updatedAt: FieldValue.serverTimestamp() })));
  return busIds;
}

exports.ensureParentBusAccess = onCall({ cors: true }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const caller = await db.collection("users").doc(uid).get();
  if (!caller.exists || String(caller.data()?.role || "").toLowerCase() !== "parent") {
    throw new HttpsError("permission-denied", "Parent access is required.");
  }
  try {
    const busIds = await syncParentBusAccess(db, uid);
    return { busIds };
  } catch (error) {
    throw sanitizedCallableError(error, "ensureParentBusAccess");
  }
});

exports.adminCreateUser = onCall({ cors: true }, async (request) => {
  await requireAdmin(request);
  const data = request.data || {};
  const email = requiredString(data.email, "email", 320).toLowerCase();
  const password = requiredString(data.password, "password", 256);
  const username = requiredString(data.username, "username", 64);
  const role = normalizedRole(data.role);
  if (password.length < 8) {
    throw new HttpsError("invalid-argument", "password must contain 8 characters.");
  }

  let authUser;
  try {
    const duplicateUsername = await db
      .collection("users")
      .where("username", "==", username)
      .limit(1)
      .get();
    if (!duplicateUsername.empty) {
      throw new HttpsError("already-exists", "This username is already in use.");
    }
    authUser = await auth.createUser({
      email,
      password,
      displayName: [data.firstName, data.lastName]
        .map((value) => String(value || "").trim())
        .filter(Boolean)
        .join(" "),
      disabled: data.isActive === false,
    });
    const profile = {
      authUid: authUser.uid,
      username,
      email,
      role,
      isActive: data.isActive !== false,
      firstName: String(data.firstName || "").trim(),
      lastName: String(data.lastName || "").trim(),
      phoneNumber: String(data.phoneNumber || "").trim(),
      countryCode: String(data.countryCode || "+60").trim(),
      gender: data.gender || null,
      birthday: data.birthday || null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    await db.collection("users").doc(authUser.uid).set(profile);
    return { uid: authUser.uid };
  } catch (error) {
    if (authUser?.uid) {
      try {
        await auth.deleteUser(authUser.uid);
      } catch (rollbackError) {
        const rollbackReference = logFailure(
          "error",
          "adminCreateUser.rollback",
          rollbackError,
        );
        logger.error("Account creation rollback requires attention", {
          operation: "adminCreateUser.rollback",
          incidentId: rollbackReference,
        });
      }
    }
    if (error instanceof HttpsError) throw error;
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account already uses this email.");
    }
    throw sanitizedCallableError(error, "adminCreateUser");
  }
});

exports.adminUpdateUser = onCall({ cors: true }, async (request) => {
  await requireAdmin(request);
  const data = request.data || {};
  const uid = requiredString(data.uid, "uid", 128);
  const patch = {};
  if (data.role != null) patch.role = normalizedRole(data.role);
  if (data.isActive != null) patch.isActive = data.isActive === true;
  for (const field of [
    "username",
    "firstName",
    "lastName",
    "phoneNumber",
    "countryCode",
    "gender",
  ]) {
    if (data[field] != null) patch[field] = String(data[field]).trim();
  }
  if (data.email != null) {
    patch.email = requiredString(data.email, "email", 320).toLowerCase();
  }
  if (data.username != null) {
    const duplicate = await db
      .collection("users")
      .where("username", "==", patch.username)
      .limit(1)
      .get();
    if (duplicate.docs.some((document) => document.id !== uid)) {
      throw new HttpsError("already-exists", "This username is already in use.");
    }
  }
  patch.updatedAt = FieldValue.serverTimestamp();
  await db.collection("users").doc(uid).update(patch);
  if (data.isActive != null || data.email != null) {
    await auth.updateUser(uid, {
      ...(data.isActive != null ? { disabled: data.isActive !== true } : {}),
      ...(data.email != null ? { email: patch.email } : {}),
    });
  }
  return { uid };
});

exports.adminDeleteUser = onCall({ cors: true }, async (request) => {
  await requireAdmin(request);
  const uid = requiredString(request.data?.uid, "uid", 128);
  if (uid === request.auth.uid) {
    throw new HttpsError("failed-precondition", "Administrators cannot delete themselves.");
  }
  await auth.deleteUser(uid);
  await db.recursiveDelete(db.collection("users").doc(uid));
  await db.collection("user_directory").doc(uid).delete();
  return { uid };
});

function routesClientFor(key) {
  return new GoogleRoutesClient({ apiKey: key });
}

function wrapRoutesCallable(handler) {
  return onCall(
    { cors: true, secrets: [googleRoutesApiKey], timeoutSeconds: 540 },
    async (request) => {
    const key = googleRoutesApiKey.value();
    const client = routesClientFor(key);
    return handler({
      db,
      request,
      routesClient: client,
      now: new Date(),
    });
  });
}

/**
 * Admin-only: computes (and caches for 30 days) Google DRIVE geometry for an
 * ordered stop plan, using TRAFFIC_UNAWARE for a stable baseline.
 */
exports.computePlannedRoute = wrapRoutesCallable(handleComputePlannedRoute);

/**
 * Authenticated Driver/Parent/Admin: traffic-aware ETA and polyline for an
 * active route session, derived entirely server-side.
 */
exports.getTrafficEta = wrapRoutesCallable(handleGetTrafficEta);

/**
 * Admin-only: staged regeneration of every saved route’s Google geometry from
 * its ordered stops. Never deletes valid legacy data.
 */
exports.migrateRouteGeometry = wrapRoutesCallable(handleMigrateRouteGeometry);

exports.syncUserDirectory = onDocumentWritten(
  { document: "users/{uid}", database: "schoolway" },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after;
    const directory = db.collection("user_directory").doc(uid);
    if (!after?.exists) {
      await directory.delete();
      return;
    }
    const data = after.data();
    await directory.set({
      username: data.username || "",
      displayName: [data.firstName, data.lastName].filter(Boolean).join(" ").trim(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  },
);

exports.syncBusAccess = onDocumentWritten(
  { document: "students/{studentId}", database: "schoolway" },
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    const pairs = new Map();
    for (const data of [before, after]) {
      if (!data?.assignedBusId) continue;
      for (const uid of data.parentAuthUids || []) {
        pairs.set(data.assignedBusId + ":" + uid, {
          busId: data.assignedBusId,
          uid,
        });
      }
    }
    await Promise.all(
      [...pairs.values()].map(async ({ busId, uid }) => {
        const remaining = await db
          .collection("students")
          .where("assignedBusId", "==", busId)
          .where("parentAuthUids", "array-contains", uid)
          .limit(1)
          .get();
        const member = db
          .collection("bus_access")
          .doc(busId)
          .collection("members")
          .doc(uid);
        if (remaining.empty) {
          await member.delete();
        } else {
          await member.set({ uid, updatedAt: FieldValue.serverTimestamp() });
        }
      }),
    );
  },
);

async function createNotification(recipientUid, sourceId, data) {
  const id = sourceId + "_" + recipientUid;
  await db.collection("notifications").doc(id).set(
    {
      ...data,
      recipientUid,
      read: false,
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function onboardStudentIdsFromEvents(events) {
  const latest = new Map();
  for (const event of events) {
    if (!event?.studentId) continue;
    const millis = event.timestamp?.toMillis?.() ?? (Number(event.timestamp) || 0);
    const prior = latest.get(event.studentId);
    if (!prior || millis >= prior.millis) {
      latest.set(event.studentId, { millis, eventType: event.eventType });
    }
  }
  return [...latest.entries()]
    .filter(([, event]) => ["board", "boarded"].includes(
      String(event.eventType || "").toLowerCase(),
    ))
    .map(([studentId]) => studentId);
}

exports.notifyBoardingEvent = onDocumentCreated(
  { document: "boarding_events/{eventId}", database: "schoolway" },
  async (event) => {
    const data = event.data?.data();
    if (!data?.studentId) return;
    const student = await db.collection("students").doc(data.studentId).get();
    if (!student.exists) return;
    const studentData = student.data();
    const isBoarding = data.eventType === "board";
    await Promise.all(
      (studentData.parentAuthUids || []).map((uid) =>
        createNotification(uid, event.params.eventId, {
          title: isBoarding ? "Child boarded the bus" : "Child left the bus",
          body:
            (studentData.firstName || "Your child") +
            (isBoarding ? " boarded" : " left") +
            " the bus.",
          type: isBoarding ? "boarding" : "dropoff",
          category: isBoarding ? "boarding" : "dropoff",
          studentId: data.studentId,
          studentIds: [data.studentId],
        }),
      ),
    );
  },
);

exports.notifyEmergencyAlert = onDocumentCreated(
  { document: "emergency_alerts/{alertId}", database: "schoolway" },
  async (event) => {
    const data = event.data?.data();
    if (!data?.busId) return;
    const parents = await db
      .collection("bus_access")
      .doc(data.busId)
      .collection("members")
      .get();
    const admins = await db
      .collection("users")
      .where("role", "in", ["admin", "administrator"])
      .get();
    const recipients = new Set([
      ...parents.docs.map((doc) => doc.id),
      ...admins.docs.map((doc) => doc.id),
    ]);
    await Promise.all(
      [...recipients].map((uid) =>
        createNotification(uid, event.params.alertId, {
          title: "Emergency alert",
          body: "A driver reported an emergency. Open SchoolWay for details.",
          type: "emergency",
          category: "emergency",
          relatedAlertId: event.params.alertId,
          location: data.location || null,
          isCritical: true,
        }),
      ),
    );
  },
);

exports.notifyRouteDeviation = onDocumentCreated(
  { document: "route_deviation_alerts/{alertId}", database: "schoolway" },
  async (event) => {
    const data = event.data?.data();
    if (!data?.busId || !data?.sessionId) return;
    const [attendance, admins] = await Promise.all([
      db.collection("boarding_events")
        .where("sessionId", "==", data.sessionId)
        .get(),
      db.collection("users")
        .where("role", "in", ["admin", "administrator"])
        .get(),
    ]);
    const studentIds = onboardStudentIdsFromEvents(
      attendance.docs.map((doc) => doc.data()),
    );
    const students = await Promise.all(
      studentIds.map((studentId) => db.collection("students").doc(studentId).get()),
    );
    const recipientStudentIds = new Map();
    for (const admin of admins.docs) {
      recipientStudentIds.set(admin.id, studentIds);
    }
    students.forEach((student, index) => {
      if (!student.exists) return;
      for (const parentUid of student.data().parentAuthUids || []) {
        const linked = recipientStudentIds.get(parentUid) || [];
        recipientStudentIds.set(parentUid, [...linked, studentIds[index]]);
      }
    });
    await Promise.all(
      [...recipientStudentIds.entries()].map(([uid, visibleStudentIds]) => createNotification(
        uid,
        event.params.alertId,
        {
          title: "Bus left the planned route",
          body: "The bus moved outside the configured route geofence.",
          type: "route_deviation",
          category: "route_deviation",
          busId: data.busId,
          sessionId: data.sessionId,
          studentIds: visibleStudentIds,
          location: {
            latitude: data.latitude,
            longitude: data.longitude,
          },
          isCritical: true,
        },
      )),
    );
  },
);

exports.sendPushOnNotification = onDocumentCreated(
  { document: "notifications/{notificationId}", database: "schoolway" },
  async (event) => {
    const snap = event.data;
    const data = snap?.data();
    const recipientUid = data?.recipientUid;
    if (!snap || !recipientUid) return;

    const user = await db.collection("users").doc(recipientUid).get();
    if (!user.exists || user.data().isActive === false) return;
    const preferences = await user.ref
      .collection("notification_prefs")
      .doc("settings")
      .get();
    const policy = notificationPolicy(
      data,
      preferences.exists ? preferences.data() : null,
      user.data().role,
    );
    if (!policy.deliver) {
      await snap.ref.delete();
      return;
    }
    await snap.ref.set({ isCritical: policy.critical }, { merge: true });
    if (policy.quiet) return;

    const devices = await user.ref.collection("devices").get();
    const tokenDocs = devices.docs.filter(
      (doc) => typeof doc.data().token === "string" && doc.data().token.length > 0,
    );
    if (tokenDocs.length === 0) return;

    const message = {
      notification: {
        title: data.title || "SchoolWay",
        body: data.body || "",
      },
      tokens: tokenDocs.map((doc) => doc.data().token),
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

    let result;
    try {
      result = await messaging.sendEachForMulticast(message);
    } catch (error) {
      logFailure("error", "sendPushOnNotification.send", error);
      throw error;
    }
    const stale = [];
    result.responses.forEach((response, index) => {
      if (
        !response.success &&
        [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(response.error?.code)
      ) {
        stale.push(tokenDocs[index].ref.delete());
      }
    });
    await Promise.all(stale);
    if (result.failureCount > 0) {
      logger.warn("Push notification was only partially delivered", {
        operation: "sendPushOnNotification",
        successCount: result.successCount,
        failureCount: result.failureCount,
        invalidTokensRemoved: stale.length,
      });
    }
  },
);

module.exports._test = {
  requiredString,
  normalizedRole,
  redact,
  sanitizedCallableError,
  routesClientFor,
  requireAdmin,
  onboardStudentIdsFromEvents,
  syncParentBusAccess,
};
