.pragma library

// Deleting a synced event = removing its .ics file from the khal/vdirsyncer vdir,
// then syncing. Pure helpers; Main.qml runs the commands (argv arrays only).

// Roots from every `path = ...` line of the khal config ("~" expanded, "/*" stripped).
function calendarRoots(configText, home) {
  const roots = [];
  for (const line of String(configText || "").split(/\r?\n/)) {
    const m = /^\s*path\s*=\s*(.+?)\s*$/.exec(line);
    if (!m) continue;
    let p = m[1].replace(/^["']|["']$/g, "");
    if (p.indexOf("~/") === 0) p = home + p.slice(1);
    p = p.replace(/\/\*+$/, "").replace(/\/+$/, "");
    if (p.charAt(0) === "/" && roots.indexOf(p) < 0) roots.push(p);
  }
  return roots;
}

function collectionsArgs(roots) {
  return ["grep", "-rH", "--include=displayname", "", "--"].concat(roots);
}

// "<dir>/displayname:<name>" lines -> [{ dir, id, name }]
function parseCollections(stdout) {
  const out = [];
  for (const line of String(stdout || "").split("\n")) {
    const i = line.indexOf("/displayname:");
    if (i <= 0) continue;
    const dir = line.slice(0, i);
    out.push({ dir: dir, id: dir.slice(dir.lastIndexOf("/") + 1), name: line.slice(i + "/displayname:".length).trim() });
  }
  return out;
}

// Google's generated calendars (holidays, birthdays) reject writes.
function isReadOnlyCollection(id) {
  return /@virtual$/i.test(id) || /#holiday/i.test(id);
}

function isWritableCalendar(collections, calendarName) {
  return collections.some((c) => c.name === calendarName && !isReadOnlyCollection(c.id));
}

function escapeRegex(text) {
  return String(text).replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
}

// File names are not UIDs, so match the exact UID line (LF or CRLF endings).
function findArgs(uid, roots) {
  return ["grep", "-rlP", "--include=*.ics", "-e", "^UID:" + escapeRegex(uid) + "\\r?$", "--"].concat(roots);
}

function parsePaths(stdout) {
  return String(stdout || "").split("\n").map((l) => l.trim()).filter((l) => /^\/.+\.ics$/.test(l));
}

function dirOf(path) {
  return path.slice(0, path.lastIndexOf("/"));
}

// One match is used as is; several are narrowed to the event's calendar.
function pickFile(paths, collections, calendarName) {
  if (paths.length === 0) return { ok: false, error: "not-found" };
  if (paths.length === 1) return { ok: true, path: paths[0] };
  const dirs = collections.filter((c) => c.name === calendarName).map((c) => c.dir);
  const hits = paths.filter((p) => dirs.indexOf(dirOf(p)) >= 0);
  return hits.length === 1 ? { ok: true, path: hits[0] } : { ok: false, error: "ambiguous" };
}

// Property names start a line; "RRULE:" inside a DESCRIPTION value does not.
function isRecurring(icsText) {
  return /^(RRULE|RECURRENCE-ID)[;:]/m.test(String(icsText || ""));
}

function isDeletablePath(path, roots) {
  const p = String(path || "");
  if (!/\.ics$/.test(p) || /(^|\/)\.{1,2}(\/|$)/.test(p)) return false;
  return roots.some((r) => p.indexOf(r + "/") === 0);
}

function deleteArgs(path) {
  return ["rm", "-f", "--", path];
}

function readArgs(path) {
  return ["cat", "--", path];
}

function removeEventChecks(data, uid) {
  const checks = {};
  for (const key of Object.keys(data.eventChecks || {})) if (key.indexOf(uid + "|") !== 0) checks[key] = data.eventChecks[key];
  return Object.assign({}, data, { eventChecks: checks });
}

// Same array back when nothing is hidden, so bindings do not churn.
function hideEvents(events, hiddenUids) {
  if (!events) return [];
  if (hiddenUids.length === 0) return events;
  return events.filter((ev) => hiddenUids.indexOf(ev.uid) < 0);
}
