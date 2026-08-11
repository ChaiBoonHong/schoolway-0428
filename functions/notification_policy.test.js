const test = require("node:test");
const assert = require("node:assert/strict");
const { notificationPolicy } = require("./notification_policy");

test("disabled categories are not delivered", () => {
  const result = notificationPolicy(
    { category: "boarding", studentIds: ["student-1"] },
    { students: { "student-1": { boarding: false } } },
    "parent",
  );
  assert.equal(result.deliver, false);
});

test("emergency is critical by default and routine alerts are not", () => {
  assert.equal(
    notificationPolicy(
      { category: "emergency", studentIds: ["student-1"] },
      {},
      "parent",
    ).critical,
    true,
  );
  assert.equal(
    notificationPolicy(
      { category: "boarding", studentIds: ["student-1"] },
      {},
      "parent",
    ).critical,
    false,
  );
});

test("one enabled child permits a single family emergency", () => {
  const result = notificationPolicy(
    { category: "emergency", studentIds: ["off", "on"] },
    { students: { off: { emergency: false } } },
    "parent",
  );
  assert.equal(result.deliver, true);
  assert.equal(result.critical, true);
});
