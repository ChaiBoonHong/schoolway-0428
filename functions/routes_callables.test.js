"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { HttpsError } = require("firebase-functions/v2/https");
const { MockFirestore } = require("./mock_firestore");
const {
  handleComputePlannedRoute,
  handleGetTrafficEta,
  handleMigrateRouteGeometry,
  requireRole,
} = require("./routes_callables");
const { stopHashForStops } = require("./routing_service");

function seedUser(db, uid, role) {
  db.collection("users").doc(uid).set({ role, isActive: true });
}

function mockRoutesClient() {
  const calls = [];
  return {
    apiKey: "test-key",
    calls,
    async computeRoutes(options) {
      calls.push(options);
      const legs = options.waypoints.slice(1).map((wp, i) => ({
        index: i,
        distanceMeters: 1000,
        durationSeconds: 120,
        durationStaticSeconds: 100,
        encodedPolyline: "leg",
      }));
      return {
        encodedPolyline: "encoded",
        distanceMeters: 3000,
        durationSeconds: 240,
        durationStaticSeconds: 200,
        legs,
      };
    },
  };
}

test("requireRole rejects unauthenticated requests", async () => {
  const db = new MockFirestore();
  await assert.rejects(
    requireRole(db, { auth: null, data: {} }, ["admin"]),
    (error) => error.code === "unauthenticated",
  );
});

test("requireRole rejects a parent calling an admin operation", async () => {
  const db = new MockFirestore();
  seedUser(db, "p1", "parent");
  await assert.rejects(
    requireRole(db, { auth: { uid: "p1" }, data: {} }, ["admin"]),
    (error) => error.code === "permission-denied",
  );
});

test("handleComputePlannedRoute denies non-admin callers", async () => {
  const db = new MockFirestore();
  seedUser(db, "p1", "parent");
  const client = mockRoutesClient();
  await assert.rejects(
    handleComputePlannedRoute({
      db,
      request: { auth: { uid: "p1" }, data: { stops: [{ latitude: 3.1, longitude: 101.7 }, { latitude: 3.2, longitude: 101.8 }] } },
      routesClient: client,
    }),
    (error) => error.code === "permission-denied",
  );
});

test("handleComputePlannedRoute returns geometry for an admin", async () => {
  const db = new MockFirestore();
  seedUser(db, "a1", "admin");
  const client = mockRoutesClient();
  const result = await handleComputePlannedRoute({
    db,
    request: {
      auth: { uid: "a1" },
      data: {
        stops: [
          { latitude: 3.1, longitude: 101.7 },
          { latitude: 3.2, longitude: 101.8 },
        ],
      },
    },
    routesClient: client,
  });
  assert.ok(result.encodedPolyline);
  assert.ok(result.stopHash);
  assert.equal(result.stops.length, 2);
  assert.ok(client.calls[0].routingPreference, "TRAFFIC_UNAWARE");
});

test("handleComputePlannedRoute rejects invalid stops", async () => {
  const db = new MockFirestore();
  seedUser(db, "a1", "admin");
  const client = mockRoutesClient();
  await assert.rejects(
    handleComputePlannedRoute({
      db,
      request: { auth: { uid: "a1" }, data: { stops: [{ latitude: 91, longitude: 101.7 }] } },
      routesClient: client,
    }),
    (error) => error.code === "invalid-argument",
  );
});

test("handleGetTrafficEta requires a sessionId", async () => {
  const db = new MockFirestore();
  seedUser(db, "d1", "driver");
  const client = mockRoutesClient();
  await assert.rejects(
    handleGetTrafficEta({
      db,
      request: { auth: { uid: "d1" }, data: {} },
      routesClient: client,
    }),
    (error) => error.code === "invalid-argument",
  );
});

test("handleGetTrafficEta returns inactive-session reason", async () => {
  const db = new MockFirestore();
  seedUser(db, "a1", "admin");
  db.collection("route_sessions").doc("s1").set({
    driverUid: "d1",
    busId: "bus1",
    routeId: "route1",
    status: "Completed",
    tripDirection: "toSchool",
  });
  db.collection("planned_routes").doc("route1").set({
    stops: [
      { latitude: 3.1, longitude: 101.7 },
      { latitude: 3.2, longitude: 101.8 },
    ],
    googleGeometry: { provider: "google", encodedPolyline: "x" },
  });
  const client = mockRoutesClient();
  const result = await handleGetTrafficEta({
    db,
    request: { auth: { uid: "a1" }, data: { sessionId: "s1" } },
    routesClient: client,
  });
  assert.equal(result.reason, "inactive-session");
});

test("handleMigrateRouteGeometry migrates routes that lack fresh geometry", async () => {
  const db = new MockFirestore();
  seedUser(db, "a1", "admin");
  const now = new Date("2026-01-01T00:00:00Z");
  const stops = [[3.1, 101.7], [3.2, 101.8]];
  // Route A: no geometry yet.
  db.collection("planned_routes").doc("rA").set({
    name: "A",
    stops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
  });
  // Route B: already has fresh matching geometry.
  db.collection("planned_routes").doc("rB").set({
    name: "B",
    stops: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
    googleGeometry: {
      provider: "google",
      encodedPolyline: "existing",
      stopHash: stopHashForStops(stops),
      generatedAt: new Date(now.getTime() - 1000),
      expiresAt: new Date(now.getTime() + 1000000),
    },
  });
  // Route C: legacy waypoints only.
  db.collection("planned_routes").doc("rC").set({
    name: "C",
    waypoints: stops.map(([latitude, longitude]) => ({ latitude, longitude })),
  });
  const client = mockRoutesClient();
  const result = await handleMigrateRouteGeometry({
    db,
    request: { auth: { uid: "a1" }, data: {} },
    routesClient: client,
    now,
  });
  assert.equal(result.total, 3);
  assert.equal(result.migrated, 2);
  assert.equal(result.skipped, 1);
  assert.equal(result.failed.length, 0);
  assert.equal(result.legacyRetained, true);
  const storedA = db.dump(["planned_routes", "rA"]);
  assert.ok(storedA.googleGeometry);
  // Legacy route gains ordered stops as source of truth.
  const storedC = db.dump(["planned_routes", "rC"]);
  assert.ok(storedC.stops.length === 2);
});

test("handleMigrateRouteGeometry records failures without aborting", async () => {
  const db = new MockFirestore();
  seedUser(db, "a1", "admin");
  db.collection("planned_routes").doc("rA").set({
    name: "A",
    stops: [
      { latitude: 3.1, longitude: 101.7 },
      { latitude: 3.2, longitude: 101.8 },
    ],
  });
  db.collection("planned_routes").doc("rB").set({
    name: "B",
    stops: [
      { latitude: 3.3, longitude: 101.9 },
      { latitude: 3.4, longitude: 102.0 },
    ],
  });
  let fail = false;
  const client = {
    apiKey: "test-key",
    async computeRoutes() {
      if (fail) throw new HttpsError("internal", "boom");
      fail = true;
      return {
        encodedPolyline: "e",
        distanceMeters: 1,
        durationSeconds: 1,
        durationStaticSeconds: 1,
        legs: [],
      };
    },
  };
  const result = await handleMigrateRouteGeometry({
    db,
    request: { auth: { uid: "a1" }, data: {} },
    routesClient: client,
  });
  assert.equal(result.total, 2);
  assert.equal(result.migrated, 1);
  assert.equal(result.failed.length, 1);
  assert.equal(result.failed[0].routeId, "rB");
});

test("handleMigrateRouteGeometry denies non-admin callers", async () => {
  const db = new MockFirestore();
  seedUser(db, "d1", "driver");
  const client = mockRoutesClient();
  await assert.rejects(
    handleMigrateRouteGeometry({
      db,
      request: { auth: { uid: "d1" }, data: {} },
      routesClient: client,
    }),
    (error) => error.code === "permission-denied",
  );
});
