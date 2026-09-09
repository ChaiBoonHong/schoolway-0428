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
