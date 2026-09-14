"use strict";

const crypto = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const {
  GoogleRoutesClient,
  decodePolyline,
  sanitizeRoutesFailure,
} = require("./routes_client");

const MAX_PLANNED_STOPS = 26;
const GEOMETRY_CACHE_DURATION_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
// GPS is uploaded every second. Refresh traffic often enough for the map to
// feel live while still deduplicating all viewers through one shared cache.
const TRAFFIC_FRESH_MS = 2 * 1000;
const TRAFFIC_EXPIRY_MS = 5 * 60 * 1000; // "updated … ago" window
const LEASE_DURATION_MS = 10 * 1000;
const LEASE_WAIT_MS = 5 * 1000;
const GPS_STALE_MS = 90 * 1000;

function sha256Hex(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function normalizedStops(rawStops) {
  if (!Array.isArray(rawStops)) {
    throw new HttpsError("invalid-argument", "stops must be an array.");
  }
  if (rawStops.length < 2) {
    throw new HttpsError(
      "invalid-argument",
      "At least two stops are required.",
    );
  }
  if (rawStops.length > MAX_PLANNED_STOPS) {
    throw new HttpsError(
      "invalid-argument",
      `At most ${MAX_PLANNED_STOPS} stops are supported. Split the route into smaller routes.`,
    );
  }
  return rawStops.map((raw, index) => {
    if (raw == null || typeof raw !== "object") {
      throw new HttpsError(
        "invalid-argument",
        `stop[${index}] must be an object.`,
      );
    }
    const latitude = Number(raw.latitude);
    const longitude = Number(raw.longitude);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      throw new HttpsError(
        "invalid-argument",
        `stop[${index}] has invalid coordinates.`,
      );
    }
    return [latitude, longitude];
  });
}

function stopsToMapList(stops) {
  return stops.map(([latitude, longitude]) => ({
    latitude,
    longitude,
  }));
}

function stopHashForStops(stops) {
  return sha256Hex(
    stops.map(([lat, lng]) => `${lat.toFixed(6)},${lng.toFixed(6)}`).join("|"),
  );
}

function isGeometryFresh(geometry, now) {
  if (!geometry || geometry.provider !== "google") return false;
  const expiresAt = geometry.expiresAt?.toDate?.() ?? geometry.expiresAt;
  if (!expiresAt) return false;
  return new Date(expiresAt).getTime() > now.getTime();
}

function buildGoogleGeometry({ route, stopHash, parsed, now }) {
  const generatedAt = new Date(now.getTime());
  const expiresAt = new Date(now.getTime() + GEOMETRY_CACHE_DURATION_MS);
  const legs = (parsed.legs || []).map((leg) => ({
    index: leg.index,
    distanceMeters: leg.distanceMeters,
    durationSeconds: leg.durationSeconds,
    durationStaticSeconds: leg.durationStaticSeconds,
    encodedPolyline: leg.encodedPolyline,
  }));
  return {
    provider: "google",
    version: 1,
    encodedPolyline: parsed.encodedPolyline,
    distanceMeters: parsed.distanceMeters,
    durationSeconds: parsed.durationSeconds,
    durationStaticSeconds: parsed.durationStaticSeconds,
    stopHash,
    stops: stopsToMapList(route),
    legs,
    generatedAt,
    expiresAt,
  };
}

function routeWaypointsForTrip(routeData, direction) {
  const stops = Array.isArray(routeData.stops) ? routeData.stops : [];
  const waypoints = Array.isArray(routeData.waypoints) ? routeData.waypoints : [];
  const ordered = stops.length > 0 ? stops : waypoints;
  const asPairs = ordered.map((stop) => [
    Number(stop.latitude),
    Number(stop.longitude),
  ]);
  return direction === "fromSchool" ? asPairs.reverse() : asPairs;
}

function tripWaypointForRouteIndex(orderedStops, routeIndex, direction) {
  const tripIndex = direction === "fromSchool"
    ? orderedStops.length - 1 - routeIndex
    : routeIndex;
  return tripIndex >= 0 && tripIndex < orderedStops.length
    ? orderedStops[tripIndex]
    : null;
}

function decodeGeometryPolyline(geometry, direction) {
  const encoded = geometry?.encodedPolyline;
  if (typeof encoded !== "string" || encoded.length < 2) return [];
  const points = decodePolyline(encoded);
  return direction === "fromSchool" ? points.reverse() : points;
}

/**
 * Determines progress along the ordered trip stops.
 * Prefers the latest completed geofence event; otherwise projects the bus
 * position onto the baseline Google polyline (forward projection).
 */
async function determineProgress({ db, session, busPosition, routeData }) {
  const direction = String(session.tripDirection || "toSchool");
  const baselinePoints = decodeGeometryPolyline(
    routeData.googleGeometry,
    direction,
  );
  const orderedStops = routeWaypointsForTrip(routeData, direction);

  let completedIndex = -1;
  const geofence = await db
    .collection("route_sessions")
    .doc(session.id)
    .collection("geofence_events")
    .orderBy("timestamp", "desc")
    .limit(20)
    .get();
  const arrivals = [];
  for (const doc of geofence.docs) {
    const data = doc.data();
    if (data.type === "at_stop" && data.tripOrderIndex != null) {
      arrivals.push({ index: data.tripOrderIndex, at: data.timestamp?.toDate?.() || new Date(0) });
    }
  }
  if (arrivals.length > 0) {
    arrivals.sort((a, b) => b.at.getTime() - a.at.getTime());
    completedIndex = Math.max(
      completedIndex,
      Number(arrivals[0].index),
    );
  }

  if (completedIndex < 0 && baselinePoints.length >= 2) {
    completedIndex = projectBusOntoStops({
      busPosition,
      baselinePoints,
      orderedStops,
    });
  }
  return { completedIndex, orderedStops, baselinePoints };
}

function projectBusOntoStops({ busPosition, baselinePoints, orderedStops }) {
  const along = cumulativeLengths(baselinePoints);
  const busAlong = distanceAlongPolyline(busPosition, baselinePoints, along);
  let completed = -1;
  for (let i = 0; i < orderedStops.length; i++) {
    const stop = orderedStops[i];
    const stopAlong = distanceAlongPolyline(stop, baselinePoints, along);
    const lead = busAlong - stopAlong;
    if (lead < -5) continue;
    if (i === 0 && lead < 5) {
      // A bus that has not started the route still projects onto the first
      // point; only treat the first stop as complete when the bus is nearby.
      const distanceToFirst = haversineMeters(
        busPosition[0],
        busPosition[1],
        stop[0],
        stop[1],
      );
      if (distanceToFirst > 150) continue;
    }
    completed = i;
  }
  return completed;
}

function cumulativeLengths(points) {
  const cumulative = [0];
  for (let i = 1; i < points.length; i++) {
    const previous = points[i - 1];
    const current = points[i];
    cumulative.push(
      cumulative[i - 1] +
        haversineMeters(previous[0], previous[1], current[0], current[1]),
    );
  }
  return cumulative;
}

function distanceAlongPolyline(point, points, cumulative) {
  let best = Infinity;
  let bestAlong = 0;
  for (let i = 0; i < points.length - 1; i++) {
    const a = points[i];
    const b = points[i + 1];
    const length = cumulative[i + 1] - cumulative[i];
    const t = projectFraction(point, a, b);
    const projected = [
      a[0] + (b[0] - a[0]) * t,
      a[1] + (b[1] - a[1]) * t,
    ];
    const distance =
      haversineMeters(point[0], point[1], projected[0], projected[1]);
    if (distance < best) {
      best = distance;
      bestAlong = cumulative[i] + length * t;
    }
  }
  return bestAlong;
}

function projectFraction(point, a, b) {
  const ax = a[0];
  const ay = a[1];
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return 0;
  const t = ((point[0] - ax) * dx + (point[1] - ay) * dy) / lengthSquared;
  return Math.min(1, Math.max(0, t));
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const radius = 6371000;
  const toRadians = Math.PI / 180;
  const dLat = (lat2 - lat1) * toRadians;
  const dLon = (lon2 - lon1) * toRadians;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * toRadians) *
      Math.cos(lat2 * toRadians) *
      Math.sin(dLon / 2) ** 2;
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function loadRouteWithGeometry(db, routeId) {
  if (!routeId) return null;
  const routeRef = db.collection("planned_routes").doc(routeId);
  const routeSnap = await routeRef.get();
  if (!routeSnap.exists) return null;
  return { ref: routeRef, data: routeSnap.data() };
}

/**
 * Admin-only planned route geometry. Returns cached Google geometry when
 * present and unexpired; otherwise calls Google with TRAFFIC_UNAWARE.
 */
async function computePlannedRouteGeometry({
  db,
  routeId,
  rawStops,
  routesClient,
  now = new Date(),
  logger = console,
}) {
  const stops = normalizedStops(rawStops);
  const stopHash = stopHashForStops(stops);

  let routeRef = null;
  if (routeId) {
    const loaded = await loadRouteWithGeometry(db, routeId);
    if (!loaded) {
      throw new HttpsError("not-found", "The planned route was not found.");
    }
    routeRef = loaded.ref;
    const savedStops = Array.isArray(loaded.data.stops) ? loaded.data.stops : [];
    if (savedStops.length > 0) {
      const savedHash = stopHashForStops(
        savedStops.map((s) => [Number(s.latitude), Number(s.longitude)]),
      );
      if (savedHash !== stopHash) {
        throw new HttpsError(
          "failed-precondition",
          "The saved route stops changed; refresh the route and retry.",
        );
      }
    }
    const cached = loaded.data.googleGeometry;
    if (isGeometryFresh(cached, now) && cached.stopHash === stopHash) {
      return {
        cached: true,
        geometry: cached,
        stops,
        routeId,
      };
    }
  }

  const parsed = await routesClient.computeRoutes({
    waypoints: stops,
    routingPreference: "TRAFFIC_UNAWARE",
  });
  logger.info("Planned route geometry computed", {
    operation: "plannedRouteGeometry",
    routeId: routeId || null,
    outcome: "computed",
    stops: stops.length,
  });
  const geometry = buildGoogleGeometry({
    route: stops,
    stopHash,
    parsed,
    now,
  });

  if (routeRef) {
    const patch = {
      googleGeometry: geometry,
      updatedAt: new Date(now.getTime()),
    };
    const loaded = await routeRef.get();
    if (loaded.exists) {
      const savedStops = Array.isArray(loaded.data()?.stops)
        ? loaded.data().stops
        : [];
      if (savedStops.length === 0) {
        // Legacy routes keep waypoints as geometry, but ordered stops must be
        // the permanent source of truth.
        patch.stops = stopsToMapList(stops);
      }
    }
    await routeRef.set(patch, { merge: true });
  }

  return {
    cached: false,
    geometry,
    stops,
    routeId: routeId || null,
  };
}

/** Humanized labels for the ordered stops (1-based in trip order). */
function orderedStopLabels(orderedStops, serviceIndices) {
  const labels = [];
  for (let i = 0; i < orderedStops.length; i++) {
    labels.push({
      stopIndex: i,
      routeStopIndex: serviceIndices.length > 0 ? serviceIndices[i] : i,
      label: `Stop ${i + 1}`,
    });
  }
  return labels;
}

function buildStopEtas({ parsed, orderedStops, orderedLabels }) {
  const etas = [];
  let accumulatedSeconds = 0;
  const legs = parsed.legs || [];
  for (let i = 0; i < orderedStops.length; i++) {
    const leg = legs[i];
    if (leg && typeof leg.durationSeconds === "number") {
      accumulatedSeconds += leg.durationSeconds;
    }
    const meta = orderedLabels[i] || {};
    etas.push({
      stopIndex: orderedStops[i].index,
      routeStopIndex: meta.routeStopIndex,
      label: meta.label || `Stop ${i + 1}`,
      etaSeconds: Math.max(0, Math.round(accumulatedSeconds)),
      etaMinutes: Math.max(1, Math.round(accumulatedSeconds / 60)),
    });
  }
  return etas;
}

function buildCacheKey(session) {
  return sha256Hex(
    [
      session.id,
      session.routeId,
      session.busId,
      String(session.tripDirection || "toSchool"),
      (session.serviceStopRouteIndices || []).join(","),
    ].join("|"),
  );
}

function toDate(value) {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") return value.toDate();
  return new Date(value);
}

async function readCache(db, sessionId, now) {
  const ref = db.collection("routing_cache").doc(sessionId);
  const snap = await ref.get();
  if (!snap.exists) return { ref, cached: null };
  const data = snap.data();
  return {
    ref,
    cached: {
      ...data,
      generatedAt: toDate(data.generatedAt),
      expiresAt: toDate(data.expiresAt),
      leaseUntil: toDate(data.leaseUntil),
      sourceGpsTime: toDate(data.sourceGpsTime),
    },
  };
}

function cacheIsFresh(cached, now, freshnessMs) {
  return (
    cached?.generatedAt != null &&
    now.getTime() - cached.generatedAt.getTime() <= freshnessMs
  );
}

function cacheCanBeUsedAsStationaryFallback({
  cached,
  now,
  session,
  cacheKey,
  progressMatch,
}) {
  return Boolean(
    cached?.generatedAt &&
      cached.expiresAt &&
      cached.expiresAt.getTime() > now.getTime() &&
      cached.stopHash === cacheKey &&
      cached.routeId === session.routeId &&
      progressMatch,
  );
}

function leaseIsHeld(cached, now) {
  return cached?.leaseUntil != null && cached.leaseUntil.getTime() > now.getTime();
}

async function getGeofenceCompletedIndex(db, sessionId) {
  const events = await db
    .collection("route_sessions")
    .doc(sessionId)
    .collection("geofence_events")
    .orderBy("timestamp", "desc")
    .limit(20)
    .get();
  let index = -1;
  for (const doc of events.docs) {
    const data = doc.data();
    if (data.type === "at_stop" && data.tripOrderIndex != null) {
      index = Math.max(index, Number(data.tripOrderIndex));
    }
  }
  return index;
}

/**
 * Traffic-aware ETA for an active session.
 *
 * All inputs are derived server-side. The client supplies only `sessionId`;
 * coordinates, route geometry, role, and stop ownership are never trusted from
 * the client. One short shared cache per session deduplicates concurrent
 * Driver/Parent requests. GPS position does NOT invalidate the cache within
 * the freshness window — only session/route changes or completed-stop changes
 * cause a recalculate.
 */
async function computeTrafficEta({
  db,
  sessionId,
  callerUid,
  role,
  routesClient,
  now = new Date(),
  logger = console,
  leaseWaitMs = LEASE_WAIT_MS,
  gpsStaleMs = GPS_STALE_MS,
}) {
  if (!sessionId || String(sessionId).trim().length === 0) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }
  const sessionRef = db.collection("route_sessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();
  if (!sessionSnap.exists) {
    throw new HttpsError("not-found", "The route session was not found.");
  }
  const session = { id: sessionId, ...sessionSnap.data() };

  const isAdmin = role === "admin" || role === "administrator";
  const isDriver = role === "driver" && session.driverUid === callerUid;
  let isParent = false;
  if (role === "parent") {
    const access = await db.collection("bus_access").doc(session.busId).get();
    isParent = access.exists &&
      Array.isArray(access.data()?.members) &&
      access.data().members.includes(callerUid);
  }
  if (!isAdmin && !isDriver && !isParent) {
    throw new HttpsError(
      "permission-denied",
      "You do not have access to this route session.",
    );
  }

  if (String(session.status || "").toLowerCase() !== "active") {
    return {
      reason: "inactive-session",
      sessionId,
      routeId: session.routeId || null,
    };
  }

  const route = await loadRouteWithGeometry(db, session.routeId);
  if (!route) {
    return { reason: "no-route", sessionId, routeId: session.routeId || null };
  }
  const routeData = route.data;
  const geometry = routeData.googleGeometry;
  if (!geometry || geometry.provider !== "google") {
    return {
      reason: "no-google-geometry",
      sessionId,
      routeId: session.routeId,
    };
  }

  const direction = String(session.tripDirection || "toSchool");
  const orderedStops = routeWaypointsForTrip(routeData, direction);

  const serviceIndices = Array.isArray(session.serviceStopRouteIndices)
    ? session.serviceStopRouteIndices.map(Number)
    : [];

  const servedStopPositions = [];
  if (serviceIndices.length > 0) {
    for (let i = 0; i < serviceIndices.length; i++) {
      const routeIndex = serviceIndices[i];
      if (routeIndex >= 0 && routeIndex < orderedStops.length) {
        const stop = tripWaypointForRouteIndex(orderedStops, routeIndex, direction);
        if (stop) servedStopPositions.push({ index: i, stop });
      }
    }
  } else {
    servedStopPositions.push(
      ...orderedStops.map((stop, index) => ({ index, stop })),
    );
  }

  const parentStopIndexes = await authorizedStopIndexes({
    db,
    session,
    callerUid,
    role,
    direction,
    totalStops: orderedStops.length,
  });
  if (parentStopIndexes && parentStopIndexes.size === 0) {
    return {
      reason: "parent-no-linked-students",
      sessionId,
      routeId: session.routeId,
    };
  }

  const cacheKey = buildCacheKey(session);
  const cache = await readCache(db, sessionId, now);
  const cached = cache.cached;

  const geofenceCompletedIndex = await getGeofenceCompletedIndex(db, sessionId);
  const hasAuthoritativeProgress = geofenceCompletedIndex >= 0;
  const progressMatch =
    !hasAuthoritativeProgress ||
    cached?.completedStopIndex === geofenceCompletedIndex;

  const remaining = servedStopPositions.filter(
    (entry) => entry.index > (hasAuthoritativeProgress ? geofenceCompletedIndex : -1),
  );

  if (remaining.length === 0) {
    return {
      reason: "all-stops-completed",
      sessionId,
      routeId: session.routeId,
      completedStopIndex: geofenceCompletedIndex,
    };
  }

  if (
    cacheIsFresh(cached, now, TRAFFIC_FRESH_MS) &&
    cached.stopHash === cacheKey &&
    progressMatch &&
    cached.routeId === session.routeId
  ) {
    logger.info("Traffic ETA served from shared cache", {
      operation: "trafficEta",
      sessionId,
      outcome: "cache-hit",
      cached: true,
      generatedAgeMs: now.getTime() - cached.generatedAt.getTime(),
    });
    return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
      reason: "ok",
      cached: true,
    });
  }

  if (leaseIsHeld(cached, now)) {
    if (cached && cached.generatedAt) {
      return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
        reason: "ok",
        cached: true,
        stale: !cacheIsFresh(cached, now, TRAFFIC_EXPIRY_MS),
      });
    }
    if (leaseWaitMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, Math.min(1200, leaseWaitMs)));
      const retried = await readCache(db, sessionId, now);
      if (
        retried.cached?.generatedAt &&
        retried.cached.stopHash === cacheKey
      ) {
        return snapshotFromCache(retried.cached, sessionId, role, parentStopIndexes, {
          reason: "ok",
          cached: true,
          stale: !cacheIsFresh(retried.cached, now, TRAFFIC_EXPIRY_MS),
        });
      }
    }
  }

  const gpsSnap = await db.collection("gps_tracking").doc(session.busId).get();
  const gps = gpsSnap.exists ? gpsSnap.data() : null;
  const sourceGpsTime =
    gps?.timestamp?.toDate?.() ?? (gps?.timestamp ? new Date(gps.timestamp) : null);
  if (!sourceGpsTime || !gps || typeof gps.latitude !== "number") {
    if (cacheCanBeUsedAsStationaryFallback({ cached, now, session, cacheKey, progressMatch })) {
      return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
        reason: "ok",
        cached: true,
        stale: true,
      });
    }
    return { reason: "no-gps", sessionId, routeId: session.routeId };
  }
  if (now.getTime() - sourceGpsTime.getTime() > gpsStaleMs) {
    if (cacheCanBeUsedAsStationaryFallback({ cached, now, session, cacheKey, progressMatch })) {
      return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
        reason: "ok",
        cached: true,
        stale: true,
      });
    }
    return { reason: "stale-gps", sessionId, routeId: session.routeId };
  }
  const busPosition = [gps.latitude, gps.longitude];

  let completedIndex = geofenceCompletedIndex;
  if (!hasAuthoritativeProgress) {
    const baselinePoints = decodeGeometryPolyline(geometry, direction);
    if (baselinePoints.length >= 2 && servedStopPositions.length > 0) {
      completedIndex = projectBusOntoStops({
        busPosition,
        baselinePoints,
        orderedStops: servedStopPositions.map((entry) => entry.stop),
      });
    }
  }

  const remainingForCompute = servedStopPositions.filter(
    (entry) => entry.index > completedIndex,
  );

  const leaseToken = crypto.randomUUID();
  let acquired = false;
  logger.info("Traffic ETA request missing a fresh cache", {
    operation: "trafficEta",
    sessionId,
    outcome: "cache-miss",
  });
  try {
    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(cache.ref);
      const current = snap.exists ? snap.data() : null;
      const leaseUntil = current?.leaseUntil?.toDate?.()
        ? new Date(current.leaseUntil.toDate())
        : current?.leaseUntil
          ? new Date(current.leaseUntil)
          : null;
      if (
        current &&
        leaseUntil &&
        leaseUntil.getTime() > now.getTime() &&
        current.leaseOwner !== leaseToken
      ) {
        throw new LeaseHeldError();
      }
      transaction.set(
        cache.ref,
        {
          leaseOwner: leaseToken,
          leaseUntil: new Date(now.getTime() + LEASE_DURATION_MS),
        },
        { merge: true },
      );
      acquired = true;
    });
  } catch (error) {
    if (error instanceof LeaseHeldError) {
      if (cached?.generatedAt) {
        return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
          reason: "ok",
          cached: true,
          stale: !cacheIsFresh(cached, now, TRAFFIC_EXPIRY_MS),
        });
      }
      throw new HttpsError(
        "unavailable",
        "Traffic ETA is being refreshed; please retry shortly.",
      );
    }
    throw error;
  }

  if (!acquired) {
    throw new HttpsError(
      "unavailable",
      "Traffic ETA is being refreshed; please retry shortly.",
    );
  }

  const waypoints = [
    busPosition,
    ...remainingForCompute.map((entry) => entry.stop),
  ];

  if (remainingForCompute.length === 0) {
    await clearLease(db, sessionId, leaseToken, now);
    return {
      reason: "all-stops-completed",
      sessionId,
      routeId: session.routeId,
      completedStopIndex: completedIndex,
    };
  }

  let parsed;
  try {
    parsed = await routesClient.computeRoutes({
      waypoints,
      routingPreference: "TRAFFIC_AWARE_OPTIMAL",
    });
    logger.info("Traffic ETA computed from Routes API", {
      operation: "trafficEta",
      sessionId,
      outcome: "computed",
      waypoints: waypoints.length,
    });
  } catch (error) {
    logger.warn("Traffic ETA request failed", {
      operation: "getTrafficEta.compute",
      sessionId,
      failure: sanitizeRoutesFailure(error, routesClient.apiKey),
    });
    await clearLease(db, sessionId, leaseToken, now);
    if (cacheCanBeUsedAsStationaryFallback({ cached, now, session, cacheKey, progressMatch })) {
      return snapshotFromCache(cached, sessionId, role, parentStopIndexes, {
        reason: "ok",
        cached: true,
        stale: true,
      });
    }
    throw new HttpsError(
      "unavailable",
      "Traffic ETA is temporarily unavailable.",
    );
  }

  const orderedLabels = remainingForCompute.map((entry, tripIndex) => {
    let routeStopIndex = entry.index;
    if (serviceIndices.length > 0) {
      routeStopIndex = serviceIndices[entry.index];
    } else if (direction === "fromSchool") {
      routeStopIndex = orderedStops.length - 1 - entry.index;
    }
    return {
      stopIndex: entry.index,
      tripIndex,
      routeStopIndex,
      label: `Stop ${tripIndex + 1}`,
    };
  });
  const stopEtas = filterEtasForRole(
    buildStopEtas({ parsed, orderedStops: remainingForCompute, orderedLabels }),
    role,
    parentStopIndexes,
  );
  const generatedAt = new Date(now.getTime());
  const expiresAt = new Date(now.getTime() + TRAFFIC_EXPIRY_MS);
  const snapshotData = {
    sessionId,
    routeId: session.routeId,
    busId: session.busId,
    reason: "ok",
    cached: false,
    sourceGpsTime,
    generatedAt,
    expiresAt,
    polyline: parsed.encodedPolyline,
    distanceMeters: parsed.distanceMeters,
    durationSeconds: parsed.durationSeconds,
    stopEtas,
    completedStopIndex: completedIndex,
    tripDirection: direction,
  };

  await db.runTransaction(async (transaction) => {
    const snap = await transaction.get(cache.ref);
    const current = snap.exists ? snap.data() : null;
    if (
      current &&
      current.leaseOwner &&
      current.leaseOwner !== leaseToken &&
      (current.leaseUntil?.toDate?.() ? new Date(current.leaseUntil.toDate()) : null)?.getTime() > now.getTime()
    ) {
      return;
    }
    transaction.set(cache.ref, {
      stopHash: cacheKey,
      sessionId,
      routeId: session.routeId,
      busId: session.busId,
      sourceGpsTime,
      generatedAt,
      expiresAt,
      completedStopIndex: completedIndex,
      polyline: snapshotData.polyline,
      distanceMeters: snapshotData.distanceMeters,
      durationSeconds: snapshotData.durationSeconds,
      stopEtas,
      tripDirection: direction,
      leaseOwner: null,
      leaseUntil: null,
    });
  });

  return snapshotData;
}

class LeaseHeldError extends Error {
  constructor() {
    super("lease held");
    this.name = "LeaseHeldError";
  }
}

async function clearLease(db, sessionId, leaseToken, now) {
  await db.runTransaction(async (transaction) => {
    const ref = db.collection("routing_cache").doc(sessionId);
    const snap = await transaction.get(ref);
    const current = snap.exists ? snap.data() : null;
    if (current?.leaseOwner !== leaseToken) return;
    transaction.update(ref, { leaseOwner: null, leaseUntil: null });
  });
}

function snapshotFromCache(cached, sessionId, role, parentStopIndexes, meta) {
  const filteredEtas = filterEtasForRole(cached.stopEtas, role, parentStopIndexes);
  return {
    sessionId,
    routeId: cached.routeId,
    busId: cached.busId,
    reason: "ok",
    cached: true,
    stale: meta.stale === true,
    sourceGpsTime: cached.sourceGpsTime,
    generatedAt: cached.generatedAt,
    expiresAt: cached.expiresAt,
    polyline: cached.polyline,
    distanceMeters: cached.distanceMeters,
    durationSeconds: cached.durationSeconds,
    stopEtas: filteredEtas,
    completedStopIndex: cached.completedStopIndex,
    tripDirection: cached.tripDirection,
  };
}

function filterEtasForRole(stopEtas, role, parentStopIndexes) {
  if (role === "parent" && parentStopIndexes) {
    return (stopEtas || []).filter((eta) => parentStopIndexes.has(eta.stopIndex));
  }
  return stopEtas || [];
}

/**
 * For Parents: the set of trip-order stop indexes that hold one of their
 * linked children. Admins and Drivers see every served stop.
 */
async function authorizedStopIndexes({
  db,
  session,
  callerUid,
  role,
  direction,
  totalStops,
}) {
  if (role === "admin" || role === "administrator" || role === "driver") {
    return null;
  }
  const students = await db
    .collection("students")
    .where("assignedBusId", "==", session.busId)
    .get();
  const indexes = new Set();
  for (const doc of students.docs) {
    const student = doc.data();
    const parents = student.parentAuthUids || [];
    if (!parents.includes(callerUid)) continue;
    if (String(student.status || "Active").toLowerCase() !== "active") continue;
    if (student.assignedRouteId && student.assignedRouteId !== session.routeId) {
      continue;
    }
    const index = studentStopIndex(student, direction);
    if (index == null) continue;
    const tripIndex = tripIndexForRouteStop(
      session,
      index,
      direction,
      totalStops,
    );
    if (tripIndex != null) indexes.add(tripIndex);
  }
  return indexes;
}

function studentStopIndex(student, direction) {
  let index;
  if (direction === "fromSchool") {
    index = student.dropoffStopIndex;
    if (index == null) {
      const match = /^Stop\s+(\d+)\b/i.exec(String(student.dropoffStop || ""));
      index = match ? Number(match[1]) - 1 : null;
    }
  } else {
    index = student.pickupStopIndex;
    if (index == null) {
      const match = /^Stop\s+(\d+)\b/i.exec(String(student.pickupStop || ""));
      index = match ? Number(match[1]) - 1 : null;
    }
  }
  return index == null ? null : Number(index);
}

function tripIndexForRouteStop(session, routeStopIndex, direction, totalStops) {
  const routeStops = Array.isArray(session.serviceStopRouteIndices)
    ? session.serviceStopRouteIndices.map(Number)
    : [];
  if (routeStops.length > 0) {
    const tripIndex = routeStops.indexOf(routeStopIndex);
    return tripIndex < 0 ? null : tripIndex;
  }
  if (direction === "fromSchool") {
    return totalStops > 0 ? totalStops - 1 - routeStopIndex : routeStopIndex;
  }
  return routeStopIndex;
}

module.exports = {
  MAX_PLANNED_STOPS,
  GEOMETRY_CACHE_DURATION_MS,
  TRAFFIC_FRESH_MS,
  TRAFFIC_EXPIRY_MS,
  LEASE_DURATION_MS,
  GPS_STALE_MS,
  normalizedStops,
  stopHashForStops,
  isGeometryFresh,
  buildGoogleGeometry,
  routeWaypointsForTrip,
  tripWaypointForRouteIndex,
  determineProgress,
  computePlannedRouteGeometry,
  computeTrafficEta,
  buildStopEtas,
  orderedStopLabels,
  decodeGeometryPolyline,
  authorizedStopIndexes,
  projectBusOntoStops,
  haversineMeters,
  LeaseHeldError,
};
