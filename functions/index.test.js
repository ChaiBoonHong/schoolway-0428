"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const functions = require("./index");

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

test("parent bus access is derived from linked students only", async () => {
  const writes = [];
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
        doc: (busId) => ({
          collection: () => ({
            doc: (uid) => ({ busId, uid }),
          }),
        }),
      };
    },
    collectionGroup(name) {
      assert.equal(name, "members");
      return {
        where: () => ({
          get: async () => ({ docs: [] }),
        }),
      };
    },
    batch() {
      return {
        set(docRef, data) {
          writes.push({ busId: docRef.busId, uid: docRef.uid, data });
        },
        delete() {},
        commit: async () => {},
      };
    },
  };

  const result = await functions._test.syncParentBusAccess(database, "parent-a");

  assert.deepEqual(result.busIds, ["bus-a", "bus-b"]);
  assert.deepEqual(writes.map(({ busId, uid }) => ({ busId, uid })), [
    { busId: "bus-a", uid: "parent-a" },
    { busId: "bus-b", uid: "parent-a" },
  ]);
});
