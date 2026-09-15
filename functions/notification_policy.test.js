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

test("admins receive emergency alerts regardless of parent preference fields", () => {
  assert.deepEqual(
    notificationPolicy(
      { category: "emergency" },
      { notificationsEnabled: false },
      "admin",
    ),
    { deliver: true, critical: true, quiet: false },
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

test("route deviation is mandatory, critical, and bypasses quiet hours", () => {
  const result = notificationPolicy(
    { category: "route_deviation", studentIds: ["student-1"] },
    {
      notificationsEnabled: false,
      quietHoursEnabled: true,
      quietStart: { hour: 0, minute: 0 },
      quietEnd: { hour: 23, minute: 59 },
      students: { "student-1": { route_deviation: false } },
      critical: { "student-1": { route_deviation: false } },
    },
    "parent",
  );
  assert.deepEqual(result, { deliver: true, critical: true, quiet: false });
});
