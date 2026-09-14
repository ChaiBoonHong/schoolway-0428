function notificationPolicy(data, preferences, role, now = new Date()) {
  const category = data.category || data.type || "system";
  const studentIds = Array.isArray(data.studentIds)
    ? data.studentIds
    : data.studentId
      ? [data.studentId]
      : [];
  const normalizedRole = String(role || "").toLowerCase();

  if (category === "route_deviation") {
    return { deliver: true, critical: true, quiet: false };
  }

  if (normalizedRole === "admin" || normalizedRole === "administrator") {
    return { deliver: true, critical: category === "emergency", quiet: false };
  }
  if (normalizedRole !== "parent") {
    return { deliver: true, critical: false, quiet: false };
  }

  const prefs = preferences || {};
  if (prefs.notificationsEnabled === false) {
    return { deliver: false, critical: false, quiet: false };
  }
  const enabledIds = studentIds.filter(
    (id) => prefs.students?.[id]?.[category] !== false,
  );
  const deliver = studentIds.length === 0 || enabledIds.length > 0;
  const critical = deliver && (enabledIds.length === 0
    ? category === "emergency"
    : enabledIds.some(
        (id) => prefs.critical?.[id]?.[category] ?? (category === "emergency"),
      ));
  return {
    deliver,
    critical,
    quiet: deliver && category !== "emergency" && isQuietHours(prefs, now),
  };
}

function isQuietHours(preferences, now) {
  if (!preferences.quietHoursEnabled) return false;
  if (!Number.isInteger(preferences.timezoneOffsetMinutes)) return false;
  const local = new Date(
    now.getTime() + preferences.timezoneOffsetMinutes * 60 * 1000,
  );
  const current = local.getUTCHours() * 60 + local.getUTCMinutes();
  const start = timeMinutes(preferences.quietStart, 22, 0);
  const end = timeMinutes(preferences.quietEnd, 6, 0);
  return start < end
    ? current >= start && current < end
    : current >= start || current < end;
}

function timeMinutes(value, defaultHour, defaultMinute) {
  return (value?.hour ?? defaultHour) * 60 + (value?.minute ?? defaultMinute);
}

module.exports = { notificationPolicy };
