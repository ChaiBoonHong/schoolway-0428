"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { Timestamp } = require("firebase-admin/firestore");
const {
  REMINDER_MS,
  GPS_STALE_MS,
  distanceToRouteMeters,
  processGpsGeofence,
  claimDueReminder,
} = require("./geofence_service");

function encode(points) {
  let previousLat = 0;
  let previousLng = 0;
  const value = (input) => {
    let number = input < 0 ? ~(input << 1) : input << 1;
    let output = "";
    while (number >= 0x20) {
      output += String.fromCharCode((0x20 | (number & 0x1f)) + 63);
      number >>= 5;
    }
    return output + String.fromCharCode(number + 63);
  };
  return points.map(([lat, lng]) => {
    const lat5 = Math.round(lat * 1e5);
    const lng5 = Math.round(lng * 1e5);
    const output = value(lat5 - previousLat) + value(lng5 - previousLng);
    previousLat = lat5;
    previousLng = lng5;
    return output;
  }).join("");
}

function fakeDatabase() {
  const values = new Map([
    ["school_config/main", { geofenceEnabled: true, routeCorridorMeters: 300 }],
    ["route_sessions/session-1", {
      status: "Active", busId: "bus-1", driverUid: "driver-1", routeId: "route-1",
    }],
    ["planned_routes/route-1", {
      googleGeometry: { encodedPolyline: encode([[3.1, 101.1], [3.11, 101.1]]) },
    }],
  ]);
  const ref = (path) => ({
    path,
    get id() { return path.split("/").at(-1); },
    async get() { return snapshot(path); },
  });
  const snapshot = (path) => ({
    exists: values.has(path),
    data: () => values.get(path),
    ref: ref(path),
  });
  return {
    values,
    collection(name) {
      return { doc: (id) => ref(`${name}/${id}`) };
    },
    async runTransaction(callback) {
      return callback({
        get: async (document) => snapshot(document.path),
        set(document, data, options) {
          values.set(document.path, options?.merge
            ? { ...(values.get(document.path) || {}), ...data }
            : data);
        },
      });
    },
  };
}

function gps(at, latitude = 3.2) {
  return {
    sessionId: "session-1", driverUid: "driver-1", latitude, longitude: 101.1,
    timestamp: Timestamp.fromDate(at), isSimulated: false,
  };
}

test("route distance distinguishes points inside and outside the corridor", () => {
  const route = [[3.1, 101.1], [3.11, 101.1]];
  assert.ok(distanceToRouteMeters(3.105, 101.1001, route) < 20);
  assert.ok(distanceToRouteMeters(3.2, 101.1, route) > 9000);
});

test("first outside fix alerts, suppresses duplicates, resets inside, and re-alerts", async () => {
  const database = fakeDatabase();
  const start = new Date("2026-01-01T00:00:00Z");
  assert.equal((await processGpsGeofence(database, "bus-1", gps(start), start)).reason, "alerted");
  const second = new Date(start.getTime() + 1000);
  assert.equal((await processGpsGeofence(database, "bus-1", gps(second), second)).reason,
    "outside-existing");
  const inside = new Date(start.getTime() + 2000);
  assert.equal((await processGpsGeofence(database, "bus-1", gps(inside, 3.105), inside)).reason,
    "inside");
  const reexit = new Date(start.getTime() + 3000);
  assert.equal((await processGpsGeofence(database, "bus-1", gps(reexit), reexit)).reason,
    "alerted");
  assert.equal([...database.values.keys()].filter((key) =>
    key.startsWith("route_deviation_alerts/")).length, 2);
});

test("simulated outside GPS can trigger a route-deviation alert", async () => {
  const database = fakeDatabase();
  const now = new Date("2026-01-01T00:00:00Z");
  const result = await processGpsGeofence(database, "bus-1", {
    ...gps(now),
    isSimulated: true,
  }, now);

  assert.equal(result.reason, "alerted");
  assert.equal(database.values.has(
    `route_deviation_alerts/${result.alertId}`,
  ), true);
});

test("due reminders repeat after five minutes and mark stale locations", async () => {
  const database = fakeDatabase();
  const start = new Date("2026-01-01T00:00:00Z");
  await processGpsGeofence(database, "bus-1", gps(start), start);
  const stateRef = database.collection("geofence_states").doc("session-1");
  assert.equal(await claimDueReminder(database, stateRef,
    new Date(start.getTime() + REMINDER_MS - 1)), null);
  const alertId = await claimDueReminder(database, stateRef,
    new Date(start.getTime() + REMINDER_MS));
  assert.equal(alertId, "session-1-1767225600000-1");
  const alert = database.values.get(`route_deviation_alerts/${alertId}`);
  assert.equal(alert.isReminder, true);
  assert.equal(alert.isLocationStale, REMINDER_MS > GPS_STALE_MS);
});

test("completed sessions stop reminders", async () => {
  const database = fakeDatabase();
  const start = new Date("2026-01-01T00:00:00Z");
  await processGpsGeofence(database, "bus-1", gps(start), start);
  database.values.get("route_sessions/session-1").status = "Completed";
  const stateRef = database.collection("geofence_states").doc("session-1");
  assert.equal(await claimDueReminder(database, stateRef,
    new Date(start.getTime() + REMINDER_MS)), null);
  assert.equal(database.values.get("geofence_states/session-1").outside, false);
});

test("stale GPS updates and missing route geometry cannot create alerts", async () => {
  const database = fakeDatabase();
  const start = new Date("2026-01-01T00:00:00Z");
  await processGpsGeofence(database, "bus-1", gps(start), start);
  assert.equal((await processGpsGeofence(database, "bus-1", gps(start),
    new Date(start.getTime() + 1000))).reason, "stale-update");
  database.values.get("planned_routes/route-1").googleGeometry.encodedPolyline = "";
  const later = new Date(start.getTime() + 2000);
  assert.equal((await processGpsGeofence(database, "bus-1", gps(later), later)).reason,
    "missing-geometry");
  assert.equal([...database.values.keys()].filter((key) =>
    key.startsWith("route_deviation_alerts/")).length, 1);
});
