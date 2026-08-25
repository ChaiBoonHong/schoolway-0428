"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  GoogleRoutesClient,
  RoutesApiError,
  parseDurationSeconds,
  decodePolyline,
  parseRouteResult,
  sanitizeRoutesFailure,
  sleep,
} = require("./routes_client");

test("parseDurationSeconds returns integer seconds", () => {
  assert.equal(parseDurationSeconds("3600s"), 3600);
  assert.equal(parseDurationSeconds("0s"), 0);
  assert.equal(parseDurationSeconds(null), null);
  assert.equal(parseDurationSeconds("abc"), null);
  assert.equal(parseDurationSeconds("-1s"), null);
});

test("decodePolyline produces known coordinates", () => {
  // A simple polyline encoding: `_p~iF~ps|U_ulLnnqC_mqNvxq`@
  // This is a known test from Google's encoded polyline algorithm.
  const result = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
  assert.equal(result.length, 3);
  const [lat1, lng1] = result[0];
  const [lat2, lng2] = result[1];
  const [lat3, lng3] = result[2];
  assert.ok(Math.abs(lat1 - 38.5) < 0.01);
  assert.ok(Math.abs(lng1 - -120.2) < 0.01);
});

test("decodePolyline returns empty for short input", () => {
  assert.equal(decodePolyline("").length, 0);
});

test("parseRouteResult returns null for empty payload", () => {
  assert.equal(parseRouteResult(null), null);
  assert.equal(parseRouteResult({}), null);
  assert.equal(parseRouteResult({ routes: [] }), null);
});

test("parseRouteResult extracts route fields", () => {
  const payload = {
    routes: [
      {
        distanceMeters: 12345,
        duration: "600s",
        durationStatic: "580s",
        polyline: { encodedPolyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@" },
        legs: [
          {
            distanceMeters: 5000,
            duration: "240s",
            durationStatic: "230s",
            polyline: { encodedPolyline: "_p~iF~ps|U" },
          },
          {
            distanceMeters: 7345,
            duration: "360s",
            durationStatic: "350s",
            polyline: { encodedPolyline: "_ulLnnqC_mqNvxq`@" },
          },
        ],
      },
    ],
  };
  const result = parseRouteResult(payload);
  assert.ok(result);
  assert.equal(result.distanceMeters, 12345);
  assert.equal(result.durationSeconds, 600);
  assert.equal(result.durationStaticSeconds, 580);
  assert.equal(result.legs.length, 2);
  assert.equal(result.legs[0].distanceMeters, 5000);
  assert.equal(result.legs[1].durationSeconds, 360);
});

test("parseRouteResult returns null when no valid polyline", () => {
  const payload = {
    routes: [{ distanceMeters: 100, polyline: {} }],
  };
  assert.equal(parseRouteResult(payload), null);
});

test("GoogleRoutesClient requires an API key", async () => {
  const client = new GoogleRoutesClient({ apiKey: null });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    { name: "RoutesApiError", code: "routes-api-key-missing" },
  );
});

test("GoogleRoutesClient requires at least two waypoints", async () => {
  const client = new GoogleRoutesClient({ apiKey: "test-key" });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2]], routingPreference: "TRAFFIC_UNAWARE" }),
    RoutesApiError,
  );
});

test("GoogleRoutesClient rejects more than 26 waypoints", async () => {
  const client = new GoogleRoutesClient({ apiKey: "test-key" });
  const many = Array.from({ length: 27 }, (_, i) => [i, i + 1]);
  await assert.rejects(
    client.computeRoutes({ waypoints: many, routingPreference: "TRAFFIC_UNAWARE" }),
    RoutesApiError,
  );
});

test("GoogleRoutesClient handles 200 response", async () => {
  const http = async () => ({
    status: 200,
    body: {
      routes: [
        {
          distanceMeters: 5000,
          duration: "300s",
          durationStatic: "290s",
          polyline: { encodedPolyline: "_{oF_{oF" },
          legs: [{ distanceMeters: 5000, duration: "300s", durationStatic: "290s" }],
        },
      ],
    },
  });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  const result = await client.computeRoutes({
    waypoints: [[1, 2], [3, 4]],
    routingPreference: "TRAFFIC_UNAWARE",
  });
  assert.ok(result.encodedPolyline);
  assert.equal(result.distanceMeters, 5000);
  assert.equal(result.durationSeconds, 300);
});

test("GoogleRoutesClient handles 429 (quota)", async () => {
  const http = async () => ({ status: 429, body: null });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-quota-exceeded",
  );
});

test("GoogleRoutesClient handles 500 (server error)", async () => {
  const http = async () => ({ status: 500, body: null });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-server-error",
  );
});

test("GoogleRoutesClient handles 403 (forbidden)", async () => {
  const http = async () => ({ status: 403, body: null });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-forbidden",
  );
});

test("GoogleRoutesClient handles 400 with detail", async () => {
  const http = async () => ({
    status: 400,
    body: { error: { message: "Invalid request: API key not valid" } },
  });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-invalid-request",
  );
});

test("GoogleRoutesClient handles network error", async () => {
  const http = async () => {
    throw new Error("ECONNREFUSED");
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-network-error",
  );
});

test("GoogleRoutesClient handles no-route response", async () => {
  const http = async () => ({
    status: 200,
    body: { routes: [{ polyline: { encodedPolyline: "" } }] },
  });
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await assert.rejects(
    client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" }),
    (err) => err.code === "routes-no-route",
  );
});

test("GoogleRoutesClient sends the planned-route field mask", async () => {
  let headers = null;
  const http = async (opts) => {
    headers = opts.headers;
    return { status: 200, body: { routes: [{ distanceMeters: 1, duration: "1s", polyline: { encodedPolyline: "ab" } }] } };
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" });
  assert.ok(headers["X-Goog-FieldMask"]);
  assert.ok(headers["X-Goog-FieldMask"].includes("routes.durationStatic"));
  assert.ok(headers["X-Goog-FieldMask"].includes("routes.legs.duration"));
  assert.ok(headers["X-Goog-FieldMask"].includes("routes.polyline.encodedPolyline"));
});

test("GoogleRoutesClient sends the traffic-eta field mask", async () => {
  let headers = null;
  const http = async (opts) => {
    headers = opts.headers;
    return { status: 200, body: { routes: [{ distanceMeters: 1, duration: "1s", polyline: { encodedPolyline: "ab" } }] } };
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_AWARE_OPTIMAL" });
  assert.ok(headers["X-Goog-FieldMask"].includes("routes.legs.durationStatic"));
  assert.ok(headers["X-Goog-FieldMask"].includes("routes.polyline.encodedPolyline"));
});

test("GoogleRoutesClient defaults to DRIVE travel mode", async () => {
  let body = null;
  const http = async (opts) => {
    body = opts.body;
    return { status: 200, body: { routes: [{ distanceMeters: 1, duration: "1s", polyline: { encodedPolyline: "ab" } }] } };
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE" });
  assert.equal(body.travelMode, "DRIVE");
});

test("GoogleRoutesClient accepts TRUCK travel mode", async () => {
  let body = null;
  const http = async (opts) => {
    body = opts.body;
    return { status: 200, body: { routes: [{ distanceMeters: 1, duration: "1s", polyline: { encodedPolyline: "ab" } }] } };
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE", travelMode: "TRUCK" });
  assert.equal(body.travelMode, "TRUCK");
});

test("GoogleRoutesClient respects a custom timeout", async () => {
  let providedTimeout = null;
  const http = async (opts) => {
    providedTimeout = opts.timeoutMs;
    return { status: 200, body: { routes: [{ distanceMeters: 1, duration: "1s", polyline: { encodedPolyline: "ab" } }] } };
  };
  const client = new GoogleRoutesClient({ apiKey: "test-key", http });
  await client.computeRoutes({ waypoints: [[1, 2], [3, 4]], routingPreference: "TRAFFIC_UNAWARE", timeoutMs: 5000 });
  assert.equal(providedTimeout, 5000);
});

test("sanitizeRoutesFailure hides API key details", () => {
  const error = new RoutesApiError("routes-server-error", "server error");
  const result = sanitizeRoutesFailure(error, "AIzaSy...");
  assert.equal(result.code, "routes-server-error");
  assert.doesNotMatch(result.message, /AIzaSy/);
  assert.ok(result.message.length > 5);
});