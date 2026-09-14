"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const functions = require("./index");

test("Firestore indexes cover compound production queries", () => {
  const config = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, "..", "firestore.indexes.json"),
    "utf8",
  ));
  const signatures = new Set(config.indexes.map((index) => [
    index.collectionGroup,
    ...index.fields.map((field) =>
      `${field.fieldPath}:${field.order || field.arrayConfig}`),
  ].join("|")));

  assert.ok(signatures.has(
    "route_sessions|busId:ASCENDING|status:ASCENDING|endTime:DESCENDING",
  ));
  assert.ok(signatures.has("incidents|busId:ASCENDING|timestamp:DESCENDING"));
  assert.ok(signatures.has(
    "geofence_states|outside:ASCENDING|nextReminderAt:ASCENDING",
  ));
  assert.ok(signatures.has("route_sessions|driverUid:ASCENDING|status:ASCENDING"));
});

test("requiredString trims valid values", () => {
  assert.equal(functions._test.requiredString(" value ", "field"), "value");
});

test("requiredString rejects empty values", () => {
  assert.throws(() => functions._test.requiredString(" ", "field"));
});

test("normalizedRole accepts only supported roles", () => {
  assert.equal(functions._test.normalizedRole("admin"), "admin");
  assert.equal(functions._test.normalizedRole("Parent"), "parent");
  assert.throws(() => functions._test.normalizedRole("owner"));
});

test("backend logging redacts sensitive values", () => {
  const redacted = functions._test.redact(
    "email=parent@example.com token=abc123 password=hunter2",
  );
  assert.doesNotMatch(redacted, /parent@example\.com|abc123|hunter2/);
  assert.match(redacted, /REDACTED/);
});

test("unexpected callable errors receive a safe incident reference", () => {
  const result = functions._test.sanitizedCallableError(
    new Error("private payload"),
    "test",
  );
  assert.equal(result.code, "internal");
  assert.doesNotMatch(result.message, /private payload/);
  assert.match(result.message, /SW-[A-F0-9]{6}/);
});

test("getRoutesApiKey retrieves secret from environment fallback", () => {
  const previous = process.env.GOOGLE_ROUTES_API_KEY;
  try {
    process.env.GOOGLE_ROUTES_API_KEY = "mock-env-secret-key-12345";
    assert.equal(functions._test.getRoutesApiKey(), "mock-env-secret-key-12345");
  } finally {
    if (previous !== undefined) {
      process.env.GOOGLE_ROUTES_API_KEY = previous;
    } else {
      delete process.env.GOOGLE_ROUTES_API_KEY;
    }
  }
});

test("route deviation recipients include only currently onboarded students", () => {
  const timestamp = (value) => ({ toMillis: () => value });
  assert.deepEqual(
    functions._test.onboardStudentIdsFromEvents([
      { studentId: "onboard", eventType: "board", timestamp: timestamp(1) },
      { studentId: "alighted", eventType: "board", timestamp: timestamp(2) },
      { studentId: "alighted", eventType: "alight", timestamp: timestamp(3) },
      { studentId: "onboard", eventType: "board", timestamp: timestamp(4) },
    ]),
    ["onboard"],
  );
});

test("route deviation recipients include active admins and active onboard parents", async () => {
  const timestamp = (value) => ({ toMillis: () => value });
  const documents = {
    "students/onboard": { parentAuthUids: ["active-parent", "inactive-parent"] },
    "students/alighted": { parentAuthUids: ["other-parent"] },
    "users/active-parent": { role: "parent", isActive: true },
    "users/inactive-parent": { role: "parent", isActive: false },
  };
  const database = {
    collection(name) {
      return { doc(id) { return { async get() {
        const data = documents[`${name}/${id}`];
        return { exists: data != null, data: () => data };
      } }; } };
    },
  };
  const attendance = [
    { data: () => ({ studentId: "onboard", eventType: "board", timestamp: timestamp(2) }) },
    { data: () => ({ studentId: "alighted", eventType: "board", timestamp: timestamp(1) }) },
    { data: () => ({ studentId: "alighted", eventType: "alight", timestamp: timestamp(3) }) },
  ];
  const admins = [
    { id: "active-admin", data: () => ({ isActive: true }) },
    { id: "inactive-admin", data: () => ({ isActive: false }) },
  ];
  const recipients = await functions._test.routeDeviationRecipients(
    database, attendance, admins,
  );
  assert.deepEqual([...recipients.entries()], [
    ["active-admin", ["onboard"]],
    ["active-parent", ["onboard"]],
  ]);
});

test("route completion is blocked while enabled geofence state is outside", () => {
  assert.throws(
    () => functions._test.assertSessionCanEnd(
      { onBoardCount: 0 },
      { outside: true },
      { geofenceEnabled: true },
    ),
    (error) => error.code === "failed-precondition" &&
      /outside the route geofence/.test(error.message),
  );
});

test("route completion is allowed inside or when geofencing is disabled", () => {
  assert.doesNotThrow(() => functions._test.assertSessionCanEnd(
    { onBoardCount: 0 }, { outside: false }, { geofenceEnabled: true },
  ));
  assert.doesNotThrow(() => functions._test.assertSessionCanEnd(
    { onBoardCount: 0 }, { outside: true }, { geofenceEnabled: false },
  ));
});

test("parent bus access is derived from linked students only", async () => {
  const writes = [];
  const removals = [];
  const database = {
    collection(name) {
      if (name === "students") {
        return {
          where: () => ({
            get: async () => ({
              docs: [
                { data: () => ({ assignedBusId: "bus-a" }) },
                { data: () => ({ assignedBusId: " bus-a " }) },
                { data: () => ({ assignedBusId: "bus-b" }) },
                { data: () => ({ assignedBusId: "" }) },
              ],
            }),
          }),
        };
      }
      assert.equal(name, "bus_access");
      return {
        doc: (busId) => ({ busId }),
        where(field, operator, value) {
          assert.equal(field, "members");
          assert.equal(operator, "array-contains");
          assert.equal(value, "parent-a");
          return {
            get: async () => ({
              docs: [{ id: "bus-c", ref: { busId: "bus-c" } }],
            }),
          };
        },
      };
    },
    batch() {
      return {
        set(docRef, data) {
          writes.push({ busId: docRef.busId, data });
        },
        update(docRef, data) {
          removals.push({ busId: docRef.busId, data });
        },
        commit: async () => {},
      };
    },
  };

  const result = await functions._test.syncParentBusAccess(database, "parent-a");

  assert.deepEqual(result, {
    busIds: ["bus-a", "bus-b"],
    added: ["bus-a", "bus-b"],
    removed: ["bus-c"],
  });
  assert.deepEqual(writes.map(({ busId }) => busId), ["bus-a", "bus-b"]);
  assert.deepEqual(removals.map(({ busId }) => busId), ["bus-c"]);
  for (const write of [...writes, ...removals]) {
    assert.ok(write.data.members);
    assert.ok(write.data.updatedAt);
  }
});
