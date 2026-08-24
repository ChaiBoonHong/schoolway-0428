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
