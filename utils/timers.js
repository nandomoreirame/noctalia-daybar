.pragma library
.import "duration.js" as Duration
.import "pomodoro.js" as Pomodoro

// The last timers started (newest first), shown as one-click chips in the Timer view
// and kept in data.json `recentTimers`. Entries: { seconds, label }.

var MAX_RECENT = 4;
var CHIP_LABEL_CHARS = 18;

function sameTimer(a, b) {
  return a.seconds === b.seconds && a.label === b.label;
}

function isValid(e) {
  return !!e && typeof e === "object" && Number.isInteger(e.seconds) && e.seconds > 0 && e.seconds <= Duration.MAX_SECONDS;
}

// Stored list -> at most MAX_RECENT valid entries; a non-string label becomes "".
function normalizeRecent(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isValid).slice(0, MAX_RECENT).map((e) => ({ seconds: e.seconds, label: typeof e.label === "string" ? e.label : "" }));
}

// New list with `entry` first and its older copy dropped; the same list when it is
// already first, so starting the same timer again does not schedule a write.
function addRecent(list, entry) {
  if (list.length > 0 && sameTimer(list[0], entry)) return list;
  const e = { seconds: entry.seconds, label: entry.label || "" };
  return [e].concat(list.filter((x) => !sameTimer(x, e))).slice(0, MAX_RECENT);
}

// Store-level wrapper: same data object back when nothing changes.
function recordRecent(data, entry) {
  const list = Array.isArray(data.recentTimers) ? data.recentTimers : [];
  const next = addRecent(list, entry);
  return next === list && Array.isArray(data.recentTimers) ? data : Object.assign({}, data, { recentTimers: next });
}

// "05:00" or "05:00 · chá"; long labels are cut with an ellipsis.
function chipText(entry) {
  const label = entry.label.length > CHIP_LABEL_CHARS ? entry.label.slice(0, CHIP_LABEL_CHARS - 1) + "…" : entry.label;
  return Pomodoro.formatClock(entry.seconds) + (label ? " · " + label : "");
}
