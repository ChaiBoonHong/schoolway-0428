"use strict";

const { HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const {
  computePlannedRouteGeometry,
  computeTrafficEta,
  MAX_PLANNED_STOPS,
  stopHashForStops,
  isGeometryFresh,
  normalizedStops,
} = require("./routing_service");
const { sanitizeRoutesFailure } = require("./routes_client");

function callerRole(db, uid) {
  return db
    .collection("users")
    .doc(uid)
    .get()
    .then((snap) => String(snap.data()?.role || "").toLowerCase());
}

async function requireRole(db, request, allowedRoles) {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
  const uid = request.auth.uid;
  const role = await callerRole(db, uid);
  const normalized = role === "administrator" ? "admin" : role;
  if (!allowedRoles.includes(normalized)) {
    throw new HttpsError(
      "permission-denied",
      "You are not allowed to perform this operation.",
    );
  }
  return { uid, role: normalized };
}

function safeRequestData(request) {
  return request.data && typeof request.data === "object" ? request.data : {};
}

async function handleComputePlannedRoute({ db, request, routesClient, now = new Date() }) {
  const { role } = await requireRole(db, request, ["admin"]);
  const data = safeRequestData(request);
  const routeId =
    data.routeId && typeof data.routeId === "string" && data.routeId.trim()
      ? data.routeId.trim()
      : null;
  const result = await computePlannedRouteGeometry({
    db,
    routeId,
    rawStops: data.stops,
    routesClient,
    now,
    logger,
  });
  return {
    routeId: result.routeId,
    cached: result.cached,
    stopHash: result.geometry.stopHash,
    encodedPolyline: result.geometry.encodedPolyline,
    distanceMeters: result.geometry.distanceMeters,
    durationSeconds: result.geometry.durationSeconds,
    durationStaticSeconds: result.geometry.durationStaticSeconds,
    generatedAt: result.geometry.generatedAt,
    expiresAt: result.geometry.expiresAt,
    legs: (result.geometry.legs || []).map((leg) => ({
      index: leg.index,
      distanceMeters: leg.distanceMeters,
      durationSeconds: leg.durationSeconds,
      durationStaticSeconds: leg.durationStaticSeconds,
      encodedPolyline: leg.encodedPolyline,
    })),
    stops: result.stops.map(([latitude, longitude]) => ({
      latitude,
      longitude,
    })),
  };
}

async function handleGetTrafficEta({ db, request, routesClient, now = new Date() }) {
  const { uid, role } = await requireRole(db, request, ["admin", "driver", "parent"]);
  const data = safeRequestData(request);
  const sessionId = String(data.sessionId || "").trim();
  if (!sessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }
  return computeTrafficEta({
    db,
    sessionId,
    callerUid: uid,
    role,
    routesClient,
    now,
    logger,
  });
}

async function handleMigrateRouteGeometry({ db, request, routesClient, now = new Date() }) {
  const { role } = await requireRole(db, request, ["admin"]);
  if (role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Only administrators can run the route migration.",
    );
  }
  const snapshot = await db.collection("planned_routes").get();
  const total = snapshot.size;
  let migrated = 0;
  let skipped = 0;
  let tooLarge = 0;
  const failed = [];
  const nowDate = new Date(now.getTime());

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const stopsRaw = Array.isArray(data.stops) ? data.stops : [];
    const waypointsRaw = Array.isArray(data.waypoints) ? data.waypoints : [];
    const ordered = stopsRaw.length > 0 ? stopsRaw : waypointsRaw;

    if (ordered.length < 2) {
      skipped += 1;
      continue;
    }
    if (ordered.length > MAX_PLANNED_STOPS) {
      tooLarge += 1;
      failed.push({
        routeId: doc.id,
        name: data.name || doc.id,
        stops: ordered.length,
        error: `route has ${ordered.length} stops; split into routes of at most ${MAX_PLANNED_STOPS} stops`,
      });
      continue;
    }

    const normalized = normalizedStops(ordered.map((s) => ({ ...s })));
    const stopHash = stopHashForStops(normalized);
    const cached = data.googleGeometry;
    if (isGeometryFresh(cached, nowDate) && cached.stopHash === stopHash) {
      skipped += 1;
      continue;
    }

    try {
      const result = await computePlannedRouteGeometry({
        db,
        routeId: doc.id,
        rawStops: ordered,
        routesClient,
        now: nowDate,
        logger,
      });
      if (result.cached) {
        skipped += 1;
      } else {
        migrated += 1;
      }
    } catch (error) {
      const failure =
        error instanceof HttpsError
          ? error.message
          : sanitizeRoutesFailure(error, routesClient.apiKey).message;
      failed.push({
        routeId: doc.id,
        name: data.name || doc.id,
        stops: ordered.length,
        error: failure,
      });
      logger.warn("Route migration entry failed", {
        operation: "migrateRouteGeometry.entry",
        routeId: doc.id,
        failure,
      });
    }
  }

  return {
    total,
    migrated,
    skipped,
    tooLarge,
    failed,
    legacyRetained: true,
  };
}

module.exports = {
  handleComputePlannedRoute,
  handleGetTrafficEta,
  handleMigrateRouteGeometry,
  requireRole,
};
