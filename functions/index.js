const { onDocumentCreated, onDocumentWritten } = require(
  "firebase-functions/v2/firestore",
);
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const crypto = require("node:crypto");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { notificationPolicy } = require("./notification_policy");
const { processGpsGeofence, claimDueReminder } = require("./geofence_service");
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
  await requireRole(request, ["admin", "administrator"]);
}

async function requireRole(request, allowedRoles) {
  if (!request.auth?.uid) {
    logger.warn("Callable authorization denied", {
      operation: "requireRole",
      reason: "unauthenticated",
    });
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const caller = await db.collection("users").doc(request.auth.uid).get();
  const role = String(caller.data()?.role || "").toLowerCase();
  if (!caller.exists || caller.data()?.isActive !== true) {
    logger.warn("Callable authorization denied", {
      operation: "requireRole",
      reason: "inactive-account",
    });
    throw new HttpsError("permission-denied", "This account is inactive.");
  }
  if (!allowedRoles.includes(role)) {
    logger.warn("Callable authorization denied", {
      operation: "requireRole",
      reason: "insufficient-role",
    });
    throw new HttpsError("permission-denied", "This operation is not permitted.");
  }
  return { uid: request.auth.uid, role, profile: caller.data() };
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
  const memberships = await database
    .collection("bus_access")
    .where("members", "array-contains", uid)
    .get();
  const authoritative = new Set(busIds);
  const existing = new Set(memberships.docs.map((document) => document.id));
  const batch = database.batch();
  const added = busIds.filter((busId) => !existing.has(busId));
  const removed = [...existing].filter((busId) => !authoritative.has(busId));
  for (const busId of busIds) {
    batch.set(
      database.collection("bus_access").doc(busId),
      {
        members: FieldValue.arrayUnion(uid),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  for (const document of memberships.docs) {
    if (!authoritative.has(document.id)) {
      batch.update(document.ref, {
        members: FieldValue.arrayRemove(uid),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }
  await batch.commit();
  return { busIds, added, removed };
}

exports.ensureParentBusAccess = onCall({ cors: true }, async (request) => {
  const { uid } = await requireRole(request, ["parent"]);
  try {
    return await syncParentBusAccess(db, uid);
  } catch (error) {
    throw sanitizedCallableError(error, "ensureParentBusAccess");
  }
});

function finiteNumber(value, field, minimum, maximum) {
  if (typeof value !== "number" || !Number.isFinite(value) ||
      value < minimum || value > maximum) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function validTripDirection(value) {
  if (value !== "toSchool" && value !== "fromSchool") {
    throw new HttpsError("invalid-argument", "tripDirection is invalid.");
  }
  return value;
}

function nextAttendanceType(lastEventType) {
  return String(lastEventType || "").toLowerCase() === "board" ? "alight" : "board";
}

function requiresSchoolArea(direction, eventType) {
  return (direction === "toSchool" && eventType === "alight") ||
    (direction === "fromSchool" && eventType === "board");
}

function distanceMeters(latitudeA, longitudeA, latitudeB, longitudeB) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const deltaLatitude = radians(latitudeB - latitudeA);
  const deltaLongitude = radians(longitudeB - longitudeA);
  const a = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(latitudeA)) * Math.cos(radians(latitudeB)) *
    Math.sin(deltaLongitude / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function parseCapturedAt(value) {
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", "capturedAt is invalid.");
  }
  if (date.getTime() > Date.now() + 5 * 60 * 1000) {
    throw new HttpsError("invalid-argument", "capturedAt is in the future.");
  }
  return date;
}

function assertSessionCanEnd(session, geofenceState, geofenceConfig) {
  if ((session.onBoardCount || 0) > 0) {
    throw new HttpsError("failed-precondition", "Students are still onboard.");
  }
  if (geofenceConfig?.geofenceEnabled === true && geofenceState?.outside === true) {
    throw new HttpsError(
      "failed-precondition",
      "The bus is outside the route geofence. Return inside before ending the trip.",
    );
  }
}

exports.checkReachability = onCall({ cors: true }, async (request) => {
  await requireRole(request, ["admin", "administrator", "driver", "parent"]);
  return { reachable: true, serverTime: new Date().toISOString() };
});

exports.startRouteSession = onCall({ cors: true }, async (request) => {
  const { uid } = await requireRole(request, ["driver"]);
  const data = request.data || {};
  const busId = requiredString(data.busId, "busId", 128);
  const direction = validTripDirection(data.tripDirection || "toSchool");
  const requestedRouteId = String(data.routeId || "").trim() || null;
  const stopIndices = Array.isArray(data.serviceStopRouteIndices) ?
    [...new Set(data.serviceStopRouteIndices.filter(Number.isInteger))] : [];
  if (stopIndices.some((value) => value < 0 || value > 10000)) {
    throw new HttpsError("invalid-argument", "serviceStopRouteIndices is invalid.");
  }
  const busRef = db.collection("buses").doc(busId);
  const sessionRef = db.collection("route_sessions").doc();
  try {
    return await db.runTransaction(async (transaction) => {
      const activeQuery = db.collection("route_sessions")
        .where("busId", "==", busId)
        .where("status", "==", "Active")
        .limit(2);
      const [busDocument, activeSessions] = await Promise.all([
        transaction.get(busRef),
        transaction.get(activeQuery),
      ]);
      if (!busDocument.exists || busDocument.data().currentDriverUid !== uid) {
        throw new HttpsError("permission-denied", "The bus is not assigned to this driver.");
      }
      if (activeSessions.size > 1) {
        throw new HttpsError("failed-precondition", "Multiple active sessions require administrator repair.");
      }
      if (!activeSessions.empty) {
        const active = activeSessions.docs[0];
        if (active.data().driverUid !== uid) {
          throw new HttpsError("failed-precondition", "This bus already has an active session.");
        }
        transaction.update(busRef, {
          status: "Active",
          currentSessionId: active.id,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { sessionId: active.id, resumed: true };
      }
      if (String(busDocument.data().status || "Idle").toLowerCase() === "active") {
        throw new HttpsError("failed-precondition", "The bus has an inconsistent active state.");
      }
      const assignedRouteId = String(busDocument.data().assignedRouteId || "").trim() || null;
      if (requestedRouteId && assignedRouteId && requestedRouteId !== assignedRouteId) {
        throw new HttpsError("failed-precondition", "The requested route is not assigned to this bus.");
      }
      transaction.create(sessionRef, {
        driverUid: uid,
        busId,
        routeId: requestedRouteId || assignedRouteId,
        startTime: FieldValue.serverTimestamp(),
        endTime: null,
        status: "Active",
        gpsTrackingEnabled: true,
        tripDirection: direction,
        serviceStopRouteIndices: stopIndices,
        onBoardCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(busRef, {
        status: "Active",
        currentSessionId: sessionRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { sessionId: sessionRef.id, resumed: false };
    });
  } catch (error) {
    throw sanitizedCallableError(error, "startRouteSession");
  }
});

exports.endRouteSession = onCall({ cors: true }, async (request) => {
  const { uid } = await requireRole(request, ["driver"]);
  const sessionId = requiredString(request.data?.sessionId, "sessionId", 128);
  const sessionRef = db.collection("route_sessions").doc(sessionId);
  try {
    return await db.runTransaction(async (transaction) => {
      const sessionDocument = await transaction.get(sessionRef);
      if (!sessionDocument.exists) {
        throw new HttpsError("not-found", "The route session was not found.");
      }
      const session = sessionDocument.data();
      const busRef = db.collection("buses").doc(session.busId);
      const stateRef = db.collection("geofence_states").doc(sessionId);
      const configRef = db.collection("school_config").doc("main");
      const [busDocument, stateDocument, configDocument] = await Promise.all([
        transaction.get(busRef),
        transaction.get(stateRef),
        transaction.get(configRef),
      ]);
      if (session.driverUid !== uid || !busDocument.exists ||
          busDocument.data().currentDriverUid !== uid) {
        throw new HttpsError("permission-denied", "The route session is not assigned to this driver.");
      }
      if (session.status === "Completed") return { sessionId, completed: true };
      if (session.status !== "Active" ||
          (busDocument.data().currentSessionId &&
           busDocument.data().currentSessionId !== sessionId)) {
        throw new HttpsError("failed-precondition", "The route session state is inconsistent.");
      }
      assertSessionCanEnd(
        session,
        stateDocument.exists ? stateDocument.data() : null,
        configDocument.exists ? configDocument.data() : null,
      );
      transaction.update(sessionRef, {
        status: "Completed",
        endTime: FieldValue.serverTimestamp(),
        gpsTrackingEnabled: false,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(busRef, {
        status: "Idle",
        currentSessionId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { sessionId, completed: true };
    });
  } catch (error) {
    throw sanitizedCallableError(error, "endRouteSession");
  }
});

exports.recordAttendance = onCall({ cors: true }, async (request) => {
  const { uid } = await requireRole(request, ["driver"]);
  const data = request.data || {};
  const eventId = requiredString(data.eventId, "eventId", 128);
  const sessionId = requiredString(data.sessionId, "sessionId", 128);
  const studentId = requiredString(data.studentId, "studentId", 128);
  const capturedAt = parseCapturedAt(data.capturedAt);
  const location = data.location || {};
  const latitude = finiteNumber(location.latitude, "latitude", -90, 90);
  const longitude = finiteNumber(location.longitude, "longitude", -180, 180);
  const accuracy = finiteNumber(location.accuracy, "accuracy", 0, 100);
  const locationCapturedAt = parseCapturedAt(location.capturedAt);
  if (Math.abs(locationCapturedAt.getTime() - capturedAt.getTime()) > 60000) {
    throw new HttpsError("failed-precondition", "The attendance GPS fix is stale.");
  }
  const isManual = data.isManual === true;
  const manualNote = isManual ? requiredString(data.manualNote, "manualNote", 500) : null;
  const sessionRef = db.collection("route_sessions").doc(sessionId);
  const studentRef = db.collection("students").doc(studentId);
  const eventRef = db.collection("boarding_events").doc(eventId);
  const stateRef = sessionRef.collection("attendance_state").doc(studentId);
  const previousEvents = await db.collection("boarding_events")
    .where("sessionId", "==", sessionId)
    .where("studentId", "==", studentId)
    .orderBy("timestamp", "desc")
    .limit(1)
    .get();
  const legacyLastType = previousEvents.empty ? null : previousEvents.docs[0].data().eventType;
  try {
    return await db.runTransaction(async (transaction) => {
      const [eventDocument, sessionDocument, studentDocument, stateDocument] =
        await Promise.all([
          transaction.get(eventRef),
          transaction.get(sessionRef),
          transaction.get(studentRef),
          transaction.get(stateRef),
        ]);
      if (eventDocument.exists) {
        const existing = eventDocument.data();
        if (existing.driverUid !== uid || existing.sessionId !== sessionId ||
            existing.studentId !== studentId) {
          throw new HttpsError("already-exists", "The attendance identifier is already in use.");
        }
        return { eventId, eventType: existing.eventType, duplicate: true };
      }
      if (!sessionDocument.exists || sessionDocument.data().status !== "Active") {
        throw new HttpsError("failed-precondition", "Attendance requires an active route session.");
      }
      const session = sessionDocument.data();
      if (session.driverUid !== uid) {
        throw new HttpsError("permission-denied", "The route session is not assigned to this driver.");
      }
      const busRef = db.collection("buses").doc(session.busId);
      const busDocument = await transaction.get(busRef);
      if (!busDocument.exists || busDocument.data().currentDriverUid !== uid ||
          (busDocument.data().currentSessionId &&
           busDocument.data().currentSessionId !== sessionId)) {
        throw new HttpsError("failed-precondition", "The bus and route session are inconsistent.");
      }
      if (!studentDocument.exists || studentDocument.data().assignedBusId !== session.busId) {
        throw new HttpsError("permission-denied", "The student is not assigned to this bus.");
      }
      const previousType = stateDocument.exists ?
        stateDocument.data().lastEventType : legacyLastType;
      const eventType = nextAttendanceType(previousType);
      if (requiresSchoolArea(session.tripDirection || "toSchool", eventType)) {
        const configDocument = await transaction.get(db.collection("school_config").doc("main"));
        const config = configDocument.data() || {};
        if (config.geofenceEnabled === true) {
          const schoolLatitude = finiteNumber(config.schoolLatitude, "schoolLatitude", -90, 90);
          const schoolLongitude = finiteNumber(config.schoolLongitude, "schoolLongitude", -180, 180);
          const radius = finiteNumber(config.schoolRadiusMeters || 250,
            "schoolRadiusMeters", 100, 10000);
          if (distanceMeters(latitude, longitude, schoolLatitude, schoolLongitude) > radius) {
            throw new HttpsError("failed-precondition", "Attendance is outside the school area.");
          }
        }
      }
      const nextCount = eventType === "board" ?
        (session.onBoardCount || 0) + 1 : Math.max(0, (session.onBoardCount || 0) - 1);
      transaction.create(eventRef, {
        studentId,
        busId: session.busId,
        driverUid: uid,
        sessionId,
        eventType,
        location: {
          name: String(location.name || "GPS").slice(0, 80),
          latitude,
          longitude,
          accuracy,
          capturedAt: Timestamp.fromDate(locationCapturedAt),
        },
        timestamp: Timestamp.fromDate(capturedAt),
        recordedAt: FieldValue.serverTimestamp(),
        nfcCardId: String(studentDocument.data().nfcCardId || "") || null,
        synced: true,
        isManual,
        manualNote,
        isCorrected: false,
        correctionReason: null,
      });
      transaction.set(stateRef, {
        lastEventType: eventType,
        lastEventId: eventId,
        lastRecordedAt: FieldValue.serverTimestamp(),
      });
      transaction.update(sessionRef, {
        onBoardCount: nextCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { eventId, eventType, duplicate: false };
    });
  } catch (error) {
    throw sanitizedCallableError(error, "recordAttendance");
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

function getRoutesApiKey() {
  try {
    const secretVal = googleRoutesApiKey.value();
    if (secretVal) return secretVal;
  } catch {
    // Secret not bound in local emulation / test context
  }
  return process.env.GOOGLE_ROUTES_API_KEY || "";
}

function routesClientFor(key) {
  return new GoogleRoutesClient({ apiKey: key || getRoutesApiKey() });
}

function wrapRoutesCallable(handler) {
  return onCall(
    { cors: true, secrets: [googleRoutesApiKey], timeoutSeconds: 540 },
    async (request) => {
    const key = getRoutesApiKey();
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
  { document: "users/{uid}", database: "schoolway", retry: true },
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
  { document: "students/{studentId}", database: "schoolway", retry: true },
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
        const access = db.collection("bus_access").doc(busId);
        if (remaining.empty) {
          await access.set(
            {
              members: FieldValue.arrayRemove(uid),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        } else {
          await access.set(
            {
              members: FieldValue.arrayUnion(uid),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
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

async function routeDeviationRecipients(database, attendanceDocs, adminDocs) {
  const studentIds = onboardStudentIdsFromEvents(
    attendanceDocs.map((document) => document.data()),
  );
  const students = await Promise.all(
    studentIds.map((studentId) => database.collection("students").doc(studentId).get()),
  );
  const recipients = new Map();
  for (const admin of adminDocs) {
    if (admin.data().isActive === true) recipients.set(admin.id, studentIds);
  }
  const parentIds = new Set();
  students.forEach((student, index) => {
    if (!student.exists) return;
    for (const parentUid of student.data().parentAuthUids || []) {
      parentIds.add(parentUid);
      const linked = recipients.get(parentUid) || [];
      recipients.set(parentUid, [...new Set([...linked, studentIds[index]])]);
    }
  });
  const parentProfiles = await Promise.all(
    [...parentIds].map((uid) => database.collection("users").doc(uid).get()),
  );
  parentProfiles.forEach((profile, index) => {
    const uid = [...parentIds][index];
    if (!profile.exists || profile.data().isActive !== true ||
        String(profile.data().role || "").toLowerCase() !== "parent") {
      recipients.delete(uid);
    }
  });
  return recipients;
}

exports.notifyBoardingEvent = onDocumentCreated(
  { document: "boarding_events/{eventId}", database: "schoolway", retry: true },
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
  { document: "emergency_alerts/{alertId}", database: "schoolway", retry: true },
  async (event) => {
    const data = event.data?.data();
    if (!data?.busId) return;
    const access = await db.collection("bus_access").doc(data.busId).get();
    const admins = await db
      .collection("users")
      .where("role", "in", ["admin", "administrator"])
      .get();
    const recipients = new Set([
      ...(access.exists && Array.isArray(access.data()?.members)
        ? access.data().members
        : []),
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

exports.detectRouteDeviation = onDocumentWritten(
  { document: "gps_tracking/{busId}", database: "schoolway", retry: true },
  async (event) => {
    if (!event.data?.after?.exists) return;
    const result = await processGpsGeofence(
      db,
      event.params.busId,
      event.data.after.data(),
    );
    if (["missing-geometry", "invalid-corridor"].includes(result.reason)) {
      logger.warn("Route geofence update could not be evaluated", {
        operation: "detectRouteDeviation",
        busId: event.params.busId,
        reason: result.reason,
      });
    }
  },
);

exports.sendRouteDeviationReminders = onSchedule(
  { schedule: "every 1 minutes", timeZone: "UTC", retryCount: 3 },
  async () => {
    const now = new Date();
    const due = await db.collection("geofence_states")
      .where("outside", "==", true)
      .where("nextReminderAt", "<=", Timestamp.fromDate(now))
      .limit(200)
      .get();
    await Promise.all(due.docs.map((state) => claimDueReminder(db, state.ref, now)));
  },
);

exports.stopGeofenceOnSessionEnd = onDocumentWritten(
  { document: "route_sessions/{sessionId}", database: "schoolway", retry: true },
  async (event) => {
    const after = event.data?.after;
    if (after?.exists && String(after.data()?.status || "").toLowerCase() === "active") return;
    await db.collection("geofence_states").doc(event.params.sessionId).set({
      outside: false,
      nextReminderAt: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  },
);

exports.stopGeofencesWhenDisabled = onDocumentWritten(
  { document: "school_config/main", database: "schoolway", retry: true },
  async (event) => {
    if (event.data?.after?.data()?.geofenceEnabled === true) return;
    const activeStates = await db.collection("geofence_states")
      .where("outside", "==", true)
      .get();
    if (activeStates.empty) return;
    const batch = db.batch();
    for (const state of activeStates.docs) {
      batch.set(state.ref, {
        outside: false,
        nextReminderAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
  },
);

exports.notifyRouteDeviation = onDocumentCreated(
  { document: "route_deviation_alerts/{alertId}", database: "schoolway", retry: true },
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
    const recipientStudentIds = await routeDeviationRecipients(
      db, attendance.docs, admins.docs,
    );
    await Promise.all(
      [...recipientStudentIds.entries()].map(([uid, visibleStudentIds]) => createNotification(
        uid,
        event.params.alertId,
        {
          title: "Bus left the planned route",
          body: data.isReminder
            ? data.isLocationStale
              ? "The bus was last known outside the route geofence. Location data is not current."
              : "The bus remains outside the configured route geofence."
            : "The bus moved outside the configured route geofence.",
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
          mandatorySafetyAlert: true,
          reminderSequence: data.reminderSequence || 0,
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
    if (!user.exists || user.data().isActive !== true) return;
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
  requireRole,
  finiteNumber,
  validTripDirection,
  nextAttendanceType,
  requiresSchoolArea,
  distanceMeters,
  parseCapturedAt,
  assertSessionCanEnd,
  onboardStudentIdsFromEvents,
  routeDeviationRecipients,
  syncParentBusAccess,
  getRoutesApiKey,
};
