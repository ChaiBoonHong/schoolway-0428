"use strict";

const { https } = require("node:https");

const ROUTES_BASE_HOST = "routes.googleapis.com";
const ROUTES_PATH = "/directions/v2:computeRoutes";

const PLANNED_ROUTE_FIELD_MASK = [
  "routes.duration",
  "routes.distanceMeters",
  "routes.polyline.encodedPolyline",
  "routes.legs.duration",
  "routes.legs.distanceMeters",
].join(",");

const TRAFFIC_ETA_FIELD_MASK = [
  "routes.duration",
  "routes.distanceMeters",
  "routes.polyline.encodedPolyline",
  "routes.legs.duration",
  "routes.legs.distanceMeters",
].join(",");

class RoutesApiError extends Error {
  constructor(code, message, cause) {
    super(message);
    this.name = "RoutesApiError";
    this.code = code;
    this.cause = cause;
  }
}

function parseDurationSeconds(value) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text.endsWith("s")) return null;
  const number = Number(text.slice(0, -1));
  return Number.isFinite(number) && number >= 0 ? Math.round(number) : null;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function postJson({ host, path, headers, body, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const payload = Buffer.from(JSON.stringify(body), "utf8");
    const request = https.request(
      {
        host,
        path,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": payload.length,
          ...headers,
        },
      },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("end", () => {
          const raw = Buffer.concat(chunks).toString("utf8");
          let parsed = null;
          try {
            parsed = raw ? JSON.parse(raw) : null;
          } catch {
            parsed = null;
          }
          resolve({ status: response.statusCode || 0, body: parsed, raw });
        });
      },
    );
    request.on("error", (error) => reject(error));
    request.setTimeout(timeoutMs, () => {
      request.destroy(new Error("request timed out"));
    });
    request.write(payload);
    request.end();
  });
}

function encodeLocations(coordinates) {
  return coordinates.map(([latitude, longitude]) => ({
    location: {
      latLng: {
        latitude: Number(latitude.toFixed(6)),
        longitude: Number(longitude.toFixed(6)),
      },
    },
  }));
}

function parseRouteResult(payload) {
  if (!payload) return null;
  const routes = Array.isArray(payload.routes) ? payload.routes : [];
  if (routes.length === 0) return null;
  const route = routes[0];
  const encodedPolyline =
    route.polyline && typeof route.polyline.encodedPolyline === "string"
      ? route.polyline.encodedPolyline
      : null;
  if (!encodedPolyline || encodedPolyline.length < 2) return null;
  const legs = Array.isArray(route.legs) ? route.legs : [];
  return {
    encodedPolyline,
    distanceMeters:
      typeof route.distanceMeters === "number" ? route.distanceMeters : null,
    durationSeconds: parseDurationSeconds(route.duration),
    durationStaticSeconds: parseDurationSeconds(route.durationStatic),
    legs: legs.map((leg, index) => ({
      index,
      distanceMeters:
        typeof leg.distanceMeters === "number" ? leg.distanceMeters : null,
      durationSeconds: parseDurationSeconds(leg.duration),
      durationStaticSeconds: parseDurationSeconds(leg.durationStatic),
      encodedPolyline:
        leg.polyline && typeof leg.polyline.encodedPolyline === "string"
          ? leg.polyline.encodedPolyline
          : null,
    })),
  };
}

function sanitizeRoutesFailure(error, key) {
  if (error instanceof RoutesApiError) {
    return { code: error.code, message: error.message };
  }
  const reference =
    "G-" +
    Math.random().toString(36).slice(2, 10).toUpperCase();
  return {
    code: "routes-request-failed",
    message: `The route service could not be reached. Reference ${reference}.`,
    apiKeyLength: key ? String(key).length : 0,
  };
}

/**
 * Thin client for the Google Routes API.
 *
 * The API key must be provided by the caller (Cloud Functions Secret Manager)
 * so no key material lives in this module or in request logs.
 */
class GoogleRoutesClient {
  constructor({ apiKey, http = postJson, now = Date.now }) {
    this.apiKey = apiKey;
    this.http = http;
    this.now = now;
  }

  /**
   * Calls `computeRoutes` with a fixed narrow field mask.
   *
   * @param {object} options
   * @param {Array<[number, number]>} options.waypoints ordered [lat, lng] pairs
   * @param {"TRAFFIC_UNAWARE"|"TRAFFIC_AWARE_OPTIMAL"} options.routingPreference
   * @param {"DRIVE"|"TRUCK"|"TWO_WHEELER"|"WALK"} [options.travelMode]
   * @param {number} [options.timeoutMs]
   */
  async computeRoutes({
    waypoints,
    routingPreference,
    travelMode = "DRIVE",
    timeoutMs = 12000,
  }) {
    if (!this.apiKey) {
      throw new RoutesApiError(
        "routes-api-key-missing",
        "The Routes API key is not configured.",
      );
    }
    if (!Array.isArray(waypoints) || waypoints.length < 2) {
      throw new RoutesApiError(
        "routes-invalid-waypoints",
        "At least two waypoints are required.",
      );
    }
    if (waypoints.length > 26) {
      throw new RoutesApiError(
        "routes-too-many-waypoints",
        "At most 26 ordered waypoints are supported per route.",
      );
    }

    const origin = encodeLocations([waypoints[0]])[0];
    const destination = encodeLocations([waypoints[waypoints.length - 1]])[0];
    const intermediates = encodeLocations(waypoints.slice(1, -1));

    const body = {
      origin,
      destination,
      travelMode,
      routingPreference,
      polylineEncoding: "ENCODED_POLYLINE",
      units: "METRIC",
    };
    if (intermediates.length > 0) body.intermediates = intermediates;

    const fieldMask =
      routingPreference === "TRAFFIC_AWARE_OPTIMAL"
        ? TRAFFIC_ETA_FIELD_MASK
        : PLANNED_ROUTE_FIELD_MASK;

    const startedAt = this.now();
    let result;
    try {
      result = await this.http({
        host: ROUTES_BASE_HOST,
        path: ROUTES_PATH,
        headers: {
          "X-Goog-Api-Key": this.apiKey,
          "X-Goog-FieldMask": fieldMask,
        },
        body,
        timeoutMs,
      });
    } catch (error) {
      throw new RoutesApiError(
        "routes-network-error",
        "The route service could not be reached.",
        error,
      );
    }
    const elapsedMs = this.now() - startedAt;

    if (result.status === 429) {
      throw new RoutesApiError(
        "routes-quota-exceeded",
        "The route service is temporarily over quota.",
      );
    }
    if (result.status >= 500) {
      throw new RoutesApiError(
        "routes-server-error",
        "The route service is temporarily unavailable.",
      );
    }
    if (result.status === 403) {
      throw new RoutesApiError(
        "routes-forbidden",
        "The route service rejected the request.",
      );
    }
    if (result.status === 400) {
      const detail = result.body?.error?.message || "";
      throw new RoutesApiError(
        "routes-invalid-request",
        "The route service rejected the request." +
          (detail ? ` ${sanitizeDetail(detail)}` : ""),
      );
    }
    if (result.status !== 200) {
      throw new RoutesApiError(
        "routes-http-" + String(result.status).slice(0, 3),
        "The route service returned an unexpected response.",
      );
    }

    const parsed = parseRouteResult(result.body);
    if (!parsed) {
      throw new RoutesApiError(
        "routes-no-route",
        "No drivable route could be found for the given stops.",
      );
    }
    return { ...parsed, elapsedMs };
  }
}

function sanitizeDetail(detail) {
  return String(detail)
    .replace(/\bapi[_-]?key\b/gi, "[REDACTED]")
    .slice(0, 300);
}

module.exports = {
  GoogleRoutesClient,
  RoutesApiError,
  parseDurationSeconds,
  decodePolyline,
  parseRouteResult,
  sanitizeRoutesFailure,
  sleep,
  PLANNED_ROUTE_FIELD_MASK,
  TRAFFIC_ETA_FIELD_MASK,
};

/** Decodes an encoded polyline (Google's algorithm) into [lat, lng] pairs. */
function decodePolyline(encoded) {
  const coordinates = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;
  while (index < encoded.length) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    latitude += result & 1 ? ~(result >> 1) : result >> 1;

    result = 0;
    shift = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    longitude += result & 1 ? ~(result >> 1) : result >> 1;

    coordinates.push([latitude * 1e-5, longitude * 1e-5]);
  }
  return coordinates;
}
