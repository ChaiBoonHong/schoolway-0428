"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { HttpsError } = require("firebase-functions/v2/https");
const { RoutesApiError } = require("./routes_client");
const {
  normalizedStops,
  stopHashForStops,
  isGeometryFresh,
  computePlannedRouteGeometry,
  computeTrafficEta,
  buildStopEtas,
  projectBusOntoStops,
  decodeGeometryPolyline,
  tripWaypointForRouteIndex,
  MAX_PLANNED_STOPS,
} = require("./routing_service");
const { MockFirestore } = require("./mock_firestore");

function encodePolyline(points) {
  const toSigned = (value) => {
    let number = value < 0 ? ~(value << 1) : value << 1;
    let result = "";
    while (number >= 0x20) {
      result += String.fromCharCode((0x20 | (number & 0x1f)) + 63);
      number >>= 5;
    }
    result += String.fromCharCode(number + 63);
    return result;
  };
  let result = "";
  let prevLat = 0;
  let prevLng = 0;
  for (const [lat, lng] of points) {
    const lat5 = Math.round(lat * 1e5);
    const lng5 = Math.round(lng * 1e5);
    result += toSigned(lat5 - prevLat);
    result += toSigned(lng5 - prevLng);
    prevLat = lat5;
    prevLng = lng5;
  }
  return result;
}

function routeData(stops, overrides = {}) {
  return {
    name: "Route A",
    stops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
    waypoints: [],
    expectedDurationMinutes: 45,
    ...overrides,
  };
}

function sessionData(overrides = {}) {
  return {
    driverUid: "driver1",
    busId: "bus1",
    routeId: "route1",
    status: "Active",
    tripDirection: "toSchool",
    serviceStopRouteIndices: [],
    ...overrides,
  };
}

function gpsData({ latitude = 3.1, longitude = 101.7, timestamp } = {}) {
  return {
    latitude,
    longitude,
    speed: 40,
    heading: 90,
    accuracy: 5,
    timestamp: timestamp || new Date(),
  };
}

function mockRoutesClient(overrides = {}) {
  const calls = [];
  return {
    apiKey: "test-key",
    calls,
    async computeRoutes(options) {
      calls.push(options);
      if (overrides.fail) throw overrides.fail;
      if (overrides.noRoute) {
        throw new RoutesApiError("routes-no-route", "No drivable route.");
      }
      const legs = options.waypoints.slice(1).map((wp, i) => ({
        index: i,
        distanceMeters: 1000 + i * 100,
        durationSeconds: 120 + i * 60,
        durationStaticSeconds: 100 + i * 60,
        encodedPolyline: "leg" + i,
      }));
      return {
        encodedPolyline: encodePolyline(options.waypoints),
        distanceMeters: legs.reduce((sum, leg) => sum + leg.distanceMeters, 0),
        durationSeconds: legs.reduce((sum, leg) => sum + leg.durationSeconds, 0),
        durationStaticSeconds: legs.reduce((sum, leg) => sum + leg.durationStaticSeconds, 0),
        legs,
      };
    },
  };
}

function seedRoute(db, routeId, stops, overrides) {
  const data = routeData(stops, overrides);
  db.collection("planned_routes").doc(routeId).set(data);
  return data;
}

function seedSession(db, sessionId, overrides) {
  const data = sessionData(overrides);
  db.collection("route_sessions").doc(sessionId).set(data);
  return data;
}

test("normalizedStops rejects missing, too-few, too-many, and invalid stops", () => {
  assert.throws(() => normalizedStops(undefined), HttpsError);
  assert.throws(() => normalizedStops([]), HttpsError);
  assert.throws(() => normalizedStops([[1, 2]]), HttpsError);
  assert.throws(() => normalizedStops([[1, 2], [3, 4], "x"]), HttpsError);
  assert.throws(() => normalizedStops([[1, 2], [91, 4]]), HttpsError);
  assert.throws(() => normalizedStops([[1, 2], [3, 181]]), HttpsError);
  const tooMany = Array.from({ length: MAX_PLANNED_STOPS + 1 }, (_, i) => [i, i]);
  assert.throws(() => normalizedStops(tooMany), HttpsError);
});

test("normalizedStops accepts valid ordered coordinates", () => {
  const result = normalizedStops([
    { latitude: 3.1, longitude: 101.7 },
    { latitude: 3.2, longitude: 101.8 },
  ]);
  assert.deepEqual(result, [[3.1, 101.7], [3.2, 101.8]]);
});

test("stopHashForStops is deterministic and order-sensitive", () => {
  const a = stopHashForStops([[3.1, 101.7], [3.2, 101.8]]);
  const b = stopHashForStops([[3.1, 101.7], [3.2, 101.8]]);
  const c = stopHashForStops([[3.2, 101.8], [3.1, 101.7]]);
  assert.equal(a, b);
  assert.notEqual(a, c);
});

test("isGeometryFresh respects provider and expiry", () => {
  const now = new Date();
  const fresh = {
    provider: "google",
    expiresAt: new Date(now.getTime() + 60000),
  };
  const expired = {
    provider: "google",
    expiresAt: new Date(now.getTime() - 60000),
  };
  const nonGoogle = { provider: "legacy", expiresAt: new Date(now.getTime() + 60000) };
  assert.equal(isGeometryFresh(fresh, now), true);
  assert.equal(isGeometryFresh(expired, now), false);
  assert.equal(isGeometryFresh(nonGoogle, now), false);
  assert.equal(isGeometryFresh(null, now), false);
});

test("computePlannedRouteGeometry computes and persists for a new route id", async () => {
  const db = new MockFirestore();
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]]);
  const client = mockRoutesClient();
  const result = await computePlannedRouteGeometry({
    db,
    routeId: "route1",
    rawStops: [
      { latitude: 3.1, longitude: 101.7 },
      { latitude: 3.2, longitude: 101.8 },
    ],
    routesClient: client,
    now: new Date("2026-01-01T00:00:00Z"),
  });
  assert.equal(result.cached, false);
  assert.equal(result.geometry.provider, "google");
  assert.ok(result.geometry.encodedPolyline);
  assert.ok(result.geometry.expiresAt > result.geometry.generatedAt);
  assert.equal(client.calls.length, 1);
  const stored = db.dump(["planned_routes", "route1"]);
  assert.ok(stored.googleGeometry);
  assert.equal(stored.googleGeometry.stopHash, result.geometry.stopHash);
});

test("computePlannedRouteGeometry returns cached fresh geometry without calling Google", async () => {
  const db = new MockFirestore();
  const now = new Date("2026-01-01T00:00:00Z");
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  const geometry = {
    provider: "google",
    version: 1,
    encodedPolyline: "abc",
    distanceMeters: 5000,
    durationSeconds: 300,
    stopHash: stopHashForStops(stops),
    stops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
    generatedAt: new Date(now.getTime() - 1000),
    expiresAt: new Date(now.getTime() + 3600000),
  };
  seedRoute(db, "route1", stops, { googleGeometry: geometry });
  const client = mockRoutesClient();
  const result = await computePlannedRouteGeometry({
    db,
    routeId: "route1",
    rawStops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
    routesClient: client,
    now,
  });
  assert.equal(result.cached, true);
  assert.equal(client.calls.length, 0);
});

test("computePlannedRouteGeometry recomputes when geometry is expired", async () => {
  const db = new MockFirestore();
  const now = new Date("2026-01-01T00:00:00Z");
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  const stale = {
    provider: "google",
    version: 1,
    encodedPolyline: "stale",
    distanceMeters: 1,
    durationSeconds: 1,
    stopHash: stopHashForStops(stops),
    stops: [],
    generatedAt: new Date(now.getTime() - 4000000000),
    expiresAt: new Date(now.getTime() - 1000),
  };
  seedRoute(db, "route1", stops, { googleGeometry: stale });
  const client = mockRoutesClient();
  const result = await computePlannedRouteGeometry({
    db,
    routeId: "route1",
    rawStops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
    routesClient: client,
    now,
  });
  assert.equal(result.cached, false);
  assert.equal(client.calls.length, 1);
});

test("computePlannedRouteGeometry rejects when saved stops changed", async () => {
  const db = new MockFirestore();
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]]);
  const client = mockRoutesClient();
  await assert.rejects(
    computePlannedRouteGeometry({
      db,
      routeId: "route1",
      rawStops: [
        { latitude: 3.9, longitude: 101.9 },
        { latitude: 3.2, longitude: 101.8 },
      ],
      routesClient: client,
    }),
    (error) => error.code === "failed-precondition",
  );
});

test("computePlannedRouteGeometry works without a route id (preview)", async () => {
  const db = new MockFirestore();
  const client = mockRoutesClient();
  const result = await computePlannedRouteGeometry({
    db,
    routeId: null,
    rawStops: [
      { latitude: 3.1, longitude: 101.7 },
      { latitude: 3.2, longitude: 101.8 },
      { latitude: 3.3, longitude: 101.9 },
    ],
    routesClient: client,
  });
  assert.equal(result.cached, false);
  assert.equal(client.calls.length, 1);
  assert.equal(client.calls[0].routingPreference, "TRAFFIC_UNAWARE");
  assert.equal(client.calls[0].waypoints.length, 3);
});

test("computeTrafficEta denies a parent who is not a member", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1");
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]], {
    googleGeometry: { provider: "google", encodedPolyline: "x" },
  });
  const client = mockRoutesClient();
  await assert.rejects(
    computeTrafficEta({
      db,
      sessionId: "s1",
      callerUid: "stranger",
      role: "parent",
      routesClient: client,
    }),
    (error) => error.code === "permission-denied",
  );
});

test("computeTrafficEta denies an unassigned driver", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1", { driverUid: "driver1" });
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]], {
    googleGeometry: { provider: "google", encodedPolyline: "x" },
  });
  const client = mockRoutesClient();
  await assert.rejects(
    computeTrafficEta({
      db,
      sessionId: "s1",
      callerUid: "other-driver",
      role: "driver",
      routesClient: client,
    }),
    (error) => error.code === "permission-denied",
  );
});

test("computeTrafficEta allows the assigned driver", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { driverUid: "driver1", serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  db.collection("gps_tracking").doc("bus1").set(
    gpsData({ latitude: 3.05, longitude: 101.65 }),
  );
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "driver1",
    role: "driver",
    routesClient: client,
  });
  assert.equal(result.reason, "ok");
  assert.equal(client.calls.length, 1);
  assert.equal(client.calls[0].routingPreference, "TRAFFIC_AWARE_OPTIMAL");
  assert.equal(client.calls[0].waypoints.length, 4); // bus + 3 stops
  assert.equal(result.stopEtas.length, 3);
  assert.ok(result.stopEtas[2].etaMinutes >= result.stopEtas[0].etaMinutes);
  assert.ok(result.polyline);
  assert.ok(result.generatedAt);
  assert.ok(result.expiresAt > result.generatedAt);
});

test("computeTrafficEta repairs a route without saved Google geometry", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops);
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  const client = mockRoutesClient();

  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });

  assert.equal(result.reason, "ok");
  assert.equal(client.calls.length, 2);
  assert.equal(client.calls[0].routingPreference, "TRAFFIC_UNAWARE");
  assert.equal(client.calls[1].routingPreference, "TRAFFIC_AWARE_OPTIMAL");
  assert.equal(client.calls[0].waypoints.length, 3);
  assert.equal(client.calls[1].waypoints.length, 3);
  assert.equal(db.dump(["planned_routes", "route1"]).googleGeometry.provider, "google");
});

test("computeTrafficEta keeps the missing-geometry reason when repair fails", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1");
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]]);
  const client = mockRoutesClient({ fail: new RoutesApiError("routes-server-error", "boom") });

  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });

  assert.equal(result.reason, "no-google-geometry");
  assert.equal(client.calls.length, 1);
});

test("computeTrafficEta returns inactive-session for completed sessions", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1", { status: "Completed" });
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]], {
    googleGeometry: { provider: "google", encodedPolyline: "x" },
  });
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });
  assert.equal(result.reason, "inactive-session");
  assert.equal(client.calls.length, 0);
});

test("computeTrafficEta returns stale-gps and never calls Google", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  const now = new Date("2026-01-01T00:00:00Z");
  db.collection("gps_tracking").doc("bus1").set(
    gpsData({ timestamp: new Date(now.getTime() - 600000) }),
  );
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now,
  });
  assert.equal(result.reason, "stale-gps");
  assert.equal(client.calls.length, 0);
});

test("computeTrafficEta keeps a recent ETA available while a bus is stationary", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  const gpsTime = new Date("2026-01-01T00:00:00Z");
  db.collection("gps_tracking").doc("bus1").set(gpsData({ timestamp: gpsTime }));
  const client = mockRoutesClient();
  const first = await computeTrafficEta({
    db, sessionId: "s1", callerUid: "admin1", role: "admin", routesClient: client,
    now: new Date("2026-01-01T00:00:10Z"),
  });
  const stationary = await computeTrafficEta({
    db, sessionId: "s1", callerUid: "admin1", role: "admin", routesClient: client,
    now: new Date("2026-01-01T00:02:00Z"),
  });

  assert.equal(first.reason, "ok");
  assert.equal(stationary.reason, "ok");
  assert.equal(stationary.cached, true);
  assert.equal(stationary.stale, true);
  assert.deepEqual(stationary.stopEtas, first.stopEtas);
  assert.equal(client.calls.length, 1);
});

test("computeTrafficEta serves a fresh cache without calling Google again", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  const gpsTime = new Date("2026-01-01T00:10:00Z");
  db.collection("gps_tracking").doc("bus1").set(gpsData({ timestamp: gpsTime }));
  const client = mockRoutesClient();
  const first = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:10:30Z"),
  });
  assert.equal(first.reason, "ok");
  assert.equal(client.calls.length, 1);

  const second = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:10:31Z"),
  });
  assert.equal(second.reason, "ok");
  assert.equal(second.cached, true);
  assert.equal(client.calls.length, 1);
});

test("traffic ETA cache is short enough for near-live map updates", () => {
  const { TRAFFIC_FRESH_MS } = require("./routing_service");
  assert.equal(TRAFFIC_FRESH_MS, 2 * 1000);
});

test("computeTrafficEta recomputes after the freshness window", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  db.collection("gps_tracking").doc("bus1").set(
    gpsData({ latitude: 3.05, longitude: 101.65, timestamp: new Date("2026-01-01T00:10:20Z") }),
  );
  const client = mockRoutesClient();
  await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:10:30Z"),
  });
  await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:11:45Z"), // outside the 15s freshness window
  });
  assert.equal(client.calls.length, 2);
});

test("computeTrafficEta refreshes when a stop is completed", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  const client = mockRoutesClient();
  await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:10:30Z"),
  });
  db.collection("route_sessions").doc("s1").collection("geofence_events").add({
    type: "at_stop",
    tripOrderIndex: 1,
    timestamp: new Date("2026-01-01T00:11:00Z"),
  });
  const second = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
    now: new Date("2026-01-01T00:11:10Z"),
  });
  assert.equal(client.calls.length, 2);
  assert.equal(second.completedStopIndex, 1);
  assert.equal(second.stopEtas.length, 1); // only remaining stop 2
});

test("computeTrafficEta returns all-stops-completed when every stop arrived", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  db.collection("route_sessions").doc("s1").collection("geofence_events").add({
    type: "at_stop",
    tripOrderIndex: 1,
    timestamp: new Date(),
  });
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });
  assert.equal(result.reason, "all-stops-completed");
  assert.equal(client.calls.length, 0);
});

test("computeTrafficEta appends the configured school after the final student stop", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.25, 101.85]];
  const school = [3.3, 101.9];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  db.collection("school_config").doc("main").set({
    schoolLatitude: school[0], schoolLongitude: school[1],
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData({
    latitude: 3.05, longitude: 101.65,
  }));
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db, sessionId: "s1", callerUid: "admin1", role: "admin", routesClient: client,
  });

  assert.deepEqual(client.calls[0].waypoints, [
    [3.05, 101.65], stops[0], stops[1], school,
  ]);
  assert.equal(result.stopEtas.length, 2);
  assert.equal(result.durationSeconds, 120 + 180 + 240);
});

test("computeTrafficEta keeps the school leg after the final student stop", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  const school = [3.3, 101.9];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  db.collection("school_config").doc("main").set({
    schoolLatitude: school[0], schoolLongitude: school[1],
  });
  db.collection("route_sessions").doc("s1").collection("geofence_events").add({
    type: "at_stop", tripOrderIndex: 1, timestamp: new Date(),
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData({
    latitude: 3.2, longitude: 101.8,
  }));
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db, sessionId: "s1", callerUid: "admin1", role: "admin", routesClient: client,
  });

  assert.deepEqual(client.calls[0].waypoints, [[3.2, 101.8], school]);
  assert.equal(result.stopEtas.length, 0);
  assert.equal(result.durationSeconds, 120);
});

test("computeTrafficEta completes when the bus reaches the terminal geofence", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", stops, {
    googleGeometry: { provider: "google", encodedPolyline: encodePolyline(stops) },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData({
    // Within the 200m terminal geofence but before the exact endpoint.
    latitude: 3.199,
    longitude: 101.799,
  }));
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });
  assert.equal(result.reason, "all-stops-completed");
  assert.equal(result.completedStopIndex, 1);
  assert.equal(client.calls.length, 0);
});

test("computeTrafficEta only returns ETAs for a parent's linked child stops", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  db.collection("bus_access").doc("bus1").set({ members: ["parent1"] });
  db.collection("students").doc("student1").set({
    studentId: "S1",
    firstName: "Child",
    lastName: "One",
    nfcCardId: "nfc1",
    parentAuthUids: ["parent1"],
    assignedBusId: "bus1",
    assignedRouteId: "route1",
    pickupStopIndex: 1,
    dropoffStopIndex: 1,
    status: "Active",
  });
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "parent1",
    role: "parent",
    routesClient: client,
  });
  assert.equal(result.reason, "ok");
  assert.equal(result.stopEtas.length, 1);
  assert.equal(result.stopEtas[0].routeStopIndex, 1);
});

test("computeTrafficEta returns parent-no-linked-students for unrelated parent", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]], {
    googleGeometry: { provider: "google", encodedPolyline: "x" },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  db.collection("bus_access").doc("bus1").set({ members: ["parent1"] });
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "parent1",
    role: "parent",
    routesClient: client,
  });
  assert.equal(result.reason, "parent-no-linked-students");
});

test("computeTrafficEta uses forward projection when no geofence events exist", async () => {
  const db = new MockFirestore();
  const stops = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1, 2] });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  // Bus position near stop 2 (index 1 in trip order), before stop 3.
  db.collection("gps_tracking").doc("bus1").set(
    gpsData({ latitude: 3.25, longitude: 101.85 }),
  );
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "admin1",
    role: "admin",
    routesClient: client,
  });
  assert.equal(result.reason, "ok");
  assert.equal(client.calls[0].waypoints[0][0], 3.25);
  assert.ok(result.stopEtas.length >= 1);
});

test("computeTrafficEta sanitizes API failures and never leaks the key", async () => {
  const db = new MockFirestore();
  seedSession(db, "s1", { serviceStopRouteIndices: [0, 1] });
  seedRoute(db, "route1", [[3.1, 101.7], [3.2, 101.8]], {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline([[3.1, 101.7], [3.2, 101.8]]),
    },
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());
  const client = mockRoutesClient({ fail: new RoutesApiError("routes-server-error", "boom") });
  await assert.rejects(
    computeTrafficEta({
      db,
      sessionId: "s1",
      callerUid: "admin1",
      role: "admin",
      routesClient: client,
    }),
    (error) => error.code === "unavailable",
  );
  const cache = db.dump(["routing_cache", "s1"]);
  assert.equal(cache.leaseOwner, null);
});

test("buildStopEtas accumulates leg durations", () => {
  const parsed = {
    legs: [
      { durationSeconds: 120 },
      { durationSeconds: 240 },
      { durationSeconds: 300 },
    ],
  };
  const etas = buildStopEtas({
    parsed,
    orderedStops: [{ index: 0 }, { index: 1 }, { index: 2 }],
    orderedLabels: [
      { stopIndex: 0, routeStopIndex: 0, label: "Stop 1" },
      { stopIndex: 1, routeStopIndex: 1, label: "Stop 2" },
      { stopIndex: 2, routeStopIndex: 2, label: "Stop 3" },
    ],
  });
  assert.equal(etas.length, 3);
  assert.equal(etas[0].etaMinutes, 2); // 120s
  assert.equal(etas[0].etaSeconds, 120);
  assert.equal(etas[1].etaMinutes, 6); // 360s
  assert.equal(etas[1].etaSeconds, 360);
  assert.equal(etas[2].etaMinutes, 11); // 660s
  assert.equal(etas[2].stopIndex, 2);
});

test("decodeGeometryPolyline decodes and reverses for fromSchool", () => {
  const points = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  const encoded = encodePolyline(points);
  const decoded = decodeGeometryPolyline({ encodedPolyline: encoded }, "toSchool");
  assert.equal(decoded.length, 3);
  assert.ok(Math.abs(decoded[0][0] - 3.1) < 1e-4);
  const reversed = decodeGeometryPolyline({ encodedPolyline: encoded }, "fromSchool");
  assert.ok(Math.abs(reversed[0][0] - 3.3) < 1e-4);
});

test("tripWaypointForRouteIndex maps original route indexes in trip order", () => {
  const orderedStops = [[3.3, 101.9], [3.2, 101.8], [3.1, 101.7]];
  assert.deepEqual(
    tripWaypointForRouteIndex(orderedStops, 2, "fromSchool"),
    orderedStops[0],
  );
  assert.deepEqual(
    tripWaypointForRouteIndex(orderedStops, 0, "fromSchool"),
    orderedStops[2],
  );
  assert.deepEqual(
    tripWaypointForRouteIndex(orderedStops, 1, "toSchool"),
    orderedStops[1],
  );
});

test("projectBusOntoStops returns the last stop behind the bus", () => {
  const baseline = [[3.1, 101.7], [3.2, 101.8], [3.3, 101.9]];
  const stops = baseline;
  const index = projectBusOntoStops({
    busPosition: [3.25, 101.85],
    baselinePoints: baseline,
    orderedStops: stops,
  });
  assert.equal(index, 1);
});

test("computeTrafficEta selects served stops by route index, not trip index", async () => {
  const db = new MockFirestore();
  const stops = [
    [3.1, 101.7], // route stop 0
    [3.2, 101.8], // route stop 1 (skipped — not in serviceStopRouteIndices)
    [3.3, 101.9], // route stop 2
  ];
  // Service only stops 0 and 2 — non-sequential indices must still resolve
  // the correct waypoint coordinates from orderedStops.
  seedSession(db, "s1", {
    driverUid: "driver1",
    serviceStopRouteIndices: [0, 2],
  });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  // Bus starts before stop 0 so all served stops are "remaining"
  db.collection("gps_tracking").doc("bus1").set(
    gpsData({ latitude: 3.0, longitude: 101.6 }),
  );
  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "driver1",
    role: "driver",
    routesClient: client,
  });
  assert.equal(result.reason, "ok");
  assert.equal(client.calls.length, 1);
  // waypoints = [busPosition, servedStop0, servedStop2]
  // Bug B would have sent servedStop1 ([3.2, 101.8]) instead of servedStop2 ([3.3, 101.9])
  assert.equal(client.calls[0].waypoints.length, 3);
  assert.equal(client.calls[0].waypoints[1][0], 3.1); // stop 0 — correct in both
  assert.equal(client.calls[0].waypoints[2][0], 3.3); // stop 2 — correct only after fix
  assert.notEqual(client.calls[0].waypoints[2][0], 3.2); // must NOT be stop 1
  assert.equal(result.stopEtas.length, 2);
  assert.equal(result.stopEtas[0].routeStopIndex, 0);
  assert.equal(result.stopEtas[1].routeStopIndex, 2);
});

test("computeTrafficEta maps selected from-school stops to reversed trip coordinates", async () => {
  const db = new MockFirestore();
  const stops = [
    [3.1, 101.7], // route stop 0
    [3.2, 101.8], // route stop 1
    [3.3, 101.9], // route stop 2 — first stop on the return trip
  ];
  seedSession(db, "s1", {
    driverUid: "driver1",
    tripDirection: "fromSchool",
    serviceStopRouteIndices: [2, 0],
  });
  seedRoute(db, "route1", stops, {
    googleGeometry: {
      provider: "google",
      encodedPolyline: encodePolyline(stops),
    },
  });
  db.collection("route_sessions").doc("s1").collection("geofence_events").add({
    type: "at_stop",
    tripOrderIndex: 0,
    timestamp: new Date(),
  });
  db.collection("gps_tracking").doc("bus1").set(gpsData());

  const client = mockRoutesClient();
  const result = await computeTrafficEta({
    db,
    sessionId: "s1",
    callerUid: "driver1",
    role: "driver",
    routesClient: client,
  });

  assert.equal(result.reason, "ok");
  assert.equal(client.calls.length, 1);
  assert.deepEqual(client.calls[0].waypoints.slice(1), [stops[0]]);
  assert.equal(result.stopEtas.length, 1);
  assert.equal(result.stopEtas[0].routeStopIndex, 0);
});
