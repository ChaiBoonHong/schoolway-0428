"use strict";

const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { decodePolyline } = require("./routes_client");

const REMINDER_MS = 5 * 60 * 1000;
const GPS_STALE_MS = 2 * 60 * 1000;

function timestampMillis(value) {
  if (value?.toMillis) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return Number(value) || 0;
}

function distanceToRouteMeters(latitude, longitude, points) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || points.length < 2) {
    return Infinity;
  }
  const radians = Math.PI / 180;
  const earthRadius = 6371000;
  const originLat = latitude * radians;
  let best = Infinity;
  for (let index = 0; index < points.length - 1; index++) {
    const [aLat, aLng] = points[index];
    const [bLat, bLng] = points[index + 1];
    const ax = (aLng - longitude) * radians * Math.cos(originLat) * earthRadius;
    const ay = (aLat - latitude) * radians * earthRadius;
    const bx = (bLng - longitude) * radians * Math.cos(originLat) * earthRadius;
    const by = (bLat - latitude) * radians * earthRadius;
    const dx = bx - ax;
    const dy = by - ay;
    const lengthSquared = dx * dx + dy * dy;
    const fraction = lengthSquared === 0
      ? 0
      : Math.max(0, Math.min(1, -(ax * dx + ay * dy) / lengthSquared));
    best = Math.min(best, Math.hypot(ax + fraction * dx, ay + fraction * dy));
  }
  return best;
}

function alertData({ sessionId, busId, driverUid, gps, corridorMeters,
  excursionId, sequence, stale = false, now }) {
  return {
    sessionId,
    busId,
    driverUid,
    latitude: gps.latitude,
    longitude: gps.longitude,
    corridorMeters,
    status: "active",
    excursionId,
    reminderSequence: sequence,
    isReminder: sequence > 0,
    isLocationStale: stale,
    gpsTimestamp: gps.timestamp,
    timestamp: Timestamp.fromDate(now),
  };
}

async function processGpsGeofence(database, busId, gps, now = new Date()) {
  // Simulated GPS is accepted so the driver's test joystick exercises the
  // complete route-deviation and notification flow.
  if (!gps || gps.sessionId == null ||
      !Number.isFinite(gps.latitude) || !Number.isFinite(gps.longitude) ||
      gps.latitude < -90 || gps.latitude > 90 || gps.longitude < -180 ||
      gps.longitude > 180) return { reason: "invalid-gps" };
  const gpsMillis = timestampMillis(gps.timestamp);
  if (!gpsMillis || gpsMillis > now.getTime() + 60 * 1000 ||
      now.getTime() - gpsMillis > GPS_STALE_MS) return { reason: "invalid-time" };

  const [configDoc, sessionDoc] = await Promise.all([
    database.collection("school_config").doc("main").get(),
    database.collection("route_sessions").doc(gps.sessionId).get(),
  ]);
  const config = configDoc.data() || {};
  const session = sessionDoc.data() || {};
  if (config.geofenceEnabled !== true) return { reason: "disabled" };
  if (!sessionDoc.exists || String(session.status || "").toLowerCase() !== "active" ||
      session.busId !== busId || session.driverUid !== gps.driverUid) {
    return { reason: "invalid-session" };
  }
  const corridorMeters = Number(config.routeCorridorMeters);
  if (!Number.isFinite(corridorMeters) || corridorMeters < 100 || corridorMeters > 10000) {
    return { reason: "invalid-corridor" };
  }
  if (typeof session.routeId !== "string" || session.routeId.length === 0) {
    return { reason: "missing-geometry" };
  }
  const routeDoc = await database.collection("planned_routes").doc(session.routeId).get();
  const encoded = routeDoc.data()?.googleGeometry?.encodedPolyline;
  if (!routeDoc.exists || typeof encoded !== "string" || encoded.length === 0) {
    return { reason: "missing-geometry" };
  }
  const points = decodePolyline(encoded);
  const distanceMeters = distanceToRouteMeters(gps.latitude, gps.longitude, points);
  const outside = distanceMeters > corridorMeters;
  const stateRef = database.collection("geofence_states").doc(gps.sessionId);

  return database.runTransaction(async (transaction) => {
    const stateDoc = await transaction.get(stateRef);
    const state = stateDoc.data() || {};
    if (timestampMillis(state.lastGpsTimestamp) >= gpsMillis) return { reason: "stale-update" };
    if (!outside) {
      transaction.set(stateRef, {
        sessionId: gps.sessionId, busId, outside: false,
        lastGpsTimestamp: gps.timestamp, lastDistanceMeters: distanceMeters,
        nextReminderAt: FieldValue.delete(), updatedAt: Timestamp.fromDate(now),
      }, { merge: true });
      return { reason: "inside" };
    }

    const common = {
      sessionId: gps.sessionId, busId, outside: true,
      lastGpsTimestamp: gps.timestamp, lastDistanceMeters: distanceMeters,
      lastOutsideLocation: { latitude: gps.latitude, longitude: gps.longitude },
      driverUid: gps.driverUid, corridorMeters, updatedAt: Timestamp.fromDate(now),
    };
    if (state.outside === true) {
      transaction.set(stateRef, common, { merge: true });
      return { reason: "outside-existing" };
    }
    const excursionId = `${gps.sessionId}-${gpsMillis}`;
    const alertId = `${excursionId}-0`;
    transaction.set(database.collection("route_deviation_alerts").doc(alertId),
      alertData({ sessionId: gps.sessionId, busId, driverUid: gps.driverUid, gps,
        corridorMeters, excursionId, sequence: 0, now }));
    transaction.set(stateRef, {
      ...common, excursionId, reminderSequence: 0,
      lastAlertAt: Timestamp.fromDate(now),
      nextReminderAt: Timestamp.fromMillis(now.getTime() + REMINDER_MS),
    }, { merge: true });
    return { reason: "alerted", alertId };
  });
}

async function claimDueReminder(database, stateRef, now = new Date()) {
  return database.runTransaction(async (transaction) => {
    const stateDoc = await transaction.get(stateRef);
    if (!stateDoc.exists) return null;
    const state = stateDoc.data();
    if (state.outside !== true || timestampMillis(state.nextReminderAt) > now.getTime()) return null;
    const [sessionDoc, configDoc] = await Promise.all([
      transaction.get(database.collection("route_sessions").doc(state.sessionId)),
      transaction.get(database.collection("school_config").doc("main")),
    ]);
    const session = sessionDoc.data() || {};
    if (!sessionDoc.exists || String(session.status || "").toLowerCase() !== "active" ||
        configDoc.data()?.geofenceEnabled !== true) {
      transaction.set(stateRef, { outside: false, nextReminderAt: FieldValue.delete(),
        updatedAt: Timestamp.fromDate(now) }, { merge: true });
      return null;
    }
    const sequence = Number(state.reminderSequence || 0) + 1;
    const alertId = `${state.excursionId}-${sequence}`;
    const stale = now.getTime() - timestampMillis(state.lastGpsTimestamp) > GPS_STALE_MS;
    const gps = { ...state.lastOutsideLocation, timestamp: state.lastGpsTimestamp };
    transaction.set(database.collection("route_deviation_alerts").doc(alertId),
      alertData({ sessionId: state.sessionId, busId: state.busId,
        driverUid: state.driverUid, gps, corridorMeters: state.corridorMeters,
        excursionId: state.excursionId, sequence, stale, now }));
    transaction.set(stateRef, { reminderSequence: sequence,
      lastAlertAt: Timestamp.fromDate(now),
      nextReminderAt: Timestamp.fromMillis(now.getTime() + REMINDER_MS),
      updatedAt: Timestamp.fromDate(now) }, { merge: true });
    return alertId;
  });
}

module.exports = { REMINDER_MS, GPS_STALE_MS, timestampMillis,
  distanceToRouteMeters, processGpsGeofence, claimDueReminder };
