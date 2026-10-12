.pragma library
.import "tabs.js" as Tabs

// data.json schema, parsing and migration. Pure: file I/O lives in Main.qml.
// Tasks carry `source`/`externalId` so a future Google Tasks sync can map them.
// v2: links were replaced by bookmarks; v1 links/notes are dropped (test data).

var VERSION = 2;

function createEmpty() {
  return { version: VERSION, tasks: [], eventChecks: {}, reminders: [], bookmarks: [], notes: [], focusLog: {}, ui: { lastTab: "", clockWindow: false, clockOverlay: false } };
}

function list(value) {
  return Array.isArray(value) ? value : [];
}

function normalizeTask(t) {
  return {
    id: String(t.id),
    title: String(t.title || ""),
    date: t.date || null,
    time: t.time || null,
    done: !!t.done,
    doneAt: t.doneAt || null,
    pomodoros: Number(t.pomodoros) || 0,
    source: t.source || "local",
    externalId: t.externalId || null,
    createdAt: t.createdAt || null
  };
}

// Keeps only "YYYY-MM-DD": positive integer pairs.
function normalizeFocusLog(log) {
  const out = {};
  if (!log || typeof log !== "object" || Array.isArray(log)) return out;
  for (const date of Object.keys(log)) {
    const n = log[date];
    if (/^\d{4}-\d{2}-\d{2}$/.test(date) && typeof n === "number" && Number.isInteger(n) && n > 0) out[date] = n;
  }
  return out;
}

// Detached clock forms that reopen after a restart.
var UI_FLAGS = ["clockWindow", "clockOverlay"];

function normalizeUi(ui) {
  const src = ui && typeof ui === "object" ? ui : {};
  const out = { lastTab: Tabs.isTab(src.lastTab) ? src.lastTab : "" };
  for (const key of UI_FLAGS) out[key] = src[key] === true;
  return out;
}

// Same object back when nothing changes, so toggling to the current state does not
// schedule a write. A missing flag counts as false.
function setUiFlag(data, key, value) {
  if (UI_FLAGS.indexOf(key) < 0) return data;
  const ui = data.ui || {};
  const v = !!value;
  if (!!ui[key] === v) return data;
  const patch = {};
  patch[key] = v;
  return Object.assign({}, data, { ui: Object.assign({}, ui, patch) });
}

// A fetch cannot survive a restart; a bookmark still "pending" on load failed.
function normalizeBookmark(b) {
  return b && b.status === "pending" ? Object.assign({}, b, { status: "failed" }) : b;
}

function hasId(item) {
  return !!item && typeof item === "object" && item.id !== undefined && item.id !== null;
}

function migrate(raw) {
  const checks = raw.eventChecks;
  return {
    version: VERSION,
    tasks: list(raw.tasks).filter((t) => t && t.id !== undefined).map(normalizeTask),
    eventChecks: checks && typeof checks === "object" && !Array.isArray(checks) ? checks : {},
    reminders: list(raw.reminders),
    bookmarks: raw.version >= 2 ? list(raw.bookmarks).filter(hasId).map(normalizeBookmark) : [],
    notes: raw.version >= 2 ? list(raw.notes).filter(hasId) : [],
    focusLog: normalizeFocusLog(raw.focusLog),
    ui: normalizeUi(raw.ui)
  };
}

// Returns { data, corrupt }. Empty/missing text is a fresh store, not corruption.
function parse(text) {
  if (text === null || text === undefined || String(text).trim() === "") {
    return { data: createEmpty(), corrupt: false };
  }
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    return { data: createEmpty(), corrupt: true };
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return { data: createEmpty(), corrupt: true };
  }
  return { data: migrate(raw), corrupt: false };
}

function serialize(data) {
  return JSON.stringify(data, null, 2) + "\n";
}

// Collision-resistant id: time base36 + random base36. `rand` is injectable for tests.
function makeId(nowMs, rand) {
  return nowMs.toString(36) + "-" + Math.floor(rand * 1e9).toString(36);
}
