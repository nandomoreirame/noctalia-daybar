.pragma library
.import "cmd.js" as Cmd

// Deleting a synced event = removing its .ics file from the khal/vdirsyncer vdir,
// then syncing. Pure helpers; Main.qml runs the commands (argv arrays only).

function expandHome(path, home) {
  let p = String(path || "");
  if (p.indexOf("~/") === 0) return home + p.slice(1);
  if (p.indexOf("$HOME/") === 0) return home + p.slice("$HOME".length);
  if (p.indexOf("${HOME}/") === 0) return home + p.slice("${HOME}".length);
  return p;
}

function normalizeRootPath(raw, home) {
  let p = String(raw || "").replace(/^["']|["']$/g, "");
  p = expandHome(p, home);
  // Trailing slashes first so "dir/*/" becomes "dir/*", then strip /*, then
  // trailing slashes again.
  p = p.replace(/\/+$/, "").replace(/\/\*$/, "").replace(/\/+$/, "");
  return p;
}

// Roots from every `path = ...` line of the khal config ("~" / $HOME expanded,
// "/*" stripped).
function calendarRoots(configText, home) {
  const roots = [];
  for (const line of String(configText || "").split(/\r?\n/)) {
    const m = /^\s*path\s*=\s*(.+?)\s*$/.exec(line);
    if (!m) continue;
    const p = normalizeRootPath(m[1], home);
    if (p.charAt(0) === "/" && roots.indexOf(p) < 0) roots.push(p);
  }
  return roots;
}

// [[name]] sections under [calendars]: [{ name, path, type }].
function calendarSections(configText, home) {
  const sections = [];
  let current = null;
  for (const line of String(configText || "").split(/\r?\n/)) {
    const name = /^\s*\[\[([^\]]+)\]\]\s*$/.exec(line);
    if (name) {
      current = { name: name[1], path: "", type: "" };
      sections.push(current);
      continue;
    }
    if (!current) continue;
    const path = /^\s*path\s*=\s*(.+?)\s*$/.exec(line);
    if (path) {
      current.path = normalizeRootPath(path[1], home);
      continue;
    }
    const type = /^\s*type\s*=\s*(.+?)\s*$/.exec(line);
    if (type) current.type = type[1].replace(/^["']|["']$/g, "").trim();
  }
  return sections.filter((s) => s.path.charAt(0) === "/");
}

function collectionsArgs(roots) {
  return ["grep", "-rH", "--include=displayname", "", "--"].concat(roots);
}

// "<dir>/displayname:<name>" lines -> [{ dir, id, name }]. When a collection
// dir equals a type=calendar section path, the section name wins.
function parseCollections(stdout, sections) {
  const out = [];
  const byDir = {};
  for (const line of String(stdout || "").split("\n")) {
    const i = line.indexOf("/displayname:");
    if (i <= 0) continue;
    const dir = line.slice(0, i);
    const col = { dir: dir, id: dir.slice(dir.lastIndexOf("/") + 1), name: line.slice(i + "/displayname:".length).trim() };
    out.push(col);
    byDir[dir] = col;
  }
  const list = sections || [];
  for (const s of list) {
    if (s.type !== "calendar") continue;
    if (byDir[s.path]) {
      byDir[s.path].name = s.name;
    } else {
      const col = { dir: s.path, id: s.path.slice(s.path.lastIndexOf("/") + 1), name: s.name };
      out.push(col);
      byDir[s.path] = col;
    }
  }
  return out;
}

// Google's generated calendars (holidays, birthdays, ICS subscriptions, shared
// group calendars) reject writes.
function isReadOnlyCollection(id) {
  const s = String(id || "");
  return /@virtual$/i.test(s)
    || /#holiday/i.test(s)
    || /#contacts@group\.v\.calendar\.google\.com/i.test(s)
    || /@import\.calendar\.google\.com$/i.test(s)
    || /@group\.v\.calendar\.google\.com/i.test(s);
}

function isWritableCalendar(collections, calendarName) {
  return collections.some((c) => c.name === calendarName && !isReadOnlyCollection(c.id));
}

// True only when the name is known and every collection carrying it is read-only;
// unknown calendars (collections not loaded, no khal config) stay writable.
function isReadOnlyCalendar(collections, calendarName) {
  const matching = (collections || []).filter((c) => c.name === calendarName);
  return matching.length > 0 && matching.every((c) => isReadOnlyCollection(c.id));
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

// Require the file's directory to be a collection whose name equals the event's
// calendar; refuse read-only collections. One or many grep hits share this rule.
function pickFile(paths, collections, calendarName) {
  if (paths.length === 0) return { ok: false, error: "not-found" };
  const matching = collections.filter((c) => c.name === calendarName);
  const dirs = matching.map((c) => c.dir);
  const hits = paths.filter((p) => dirs.indexOf(dirOf(p)) >= 0);
  if (hits.length !== 1) return { ok: false, error: "ambiguous" };
  const col = matching.find((c) => c.dir === dirOf(hits[0]));
  if (col && isReadOnlyCollection(col.id)) return { ok: false, error: "read-only" };
  return { ok: true, path: hits[0] };
}

// Property names start a line inside a VEVENT; RRULE in VTIMEZONE must not count.
function isRecurring(icsText) {
  const text = String(icsText || "");
  const re = /BEGIN:VEVENT([\s\S]*?)END:VEVENT/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (/^(RRULE|RECURRENCE-ID)[;:]/m.test(m[1])) return true;
  }
  return false;
}

function isDeletablePath(path, roots) {
  const p = String(path || "");
  if (!/\.ics$/.test(p) || /(^|\/)\.{1,2}(\/|$)/.test(p)) return false;
  return roots.some((r) => p.indexOf(r + "/") === 0);
}

function deleteArgs(path) {
  return Cmd.removeFileArgs(path);
}

function readArgs(path) {
  return ["cat", "--", path];
}

// Checks are keyed by uid only (no calendar on the check record).
function removeEventChecks(data, uid) {
  const checks = {};
  for (const key of Object.keys(data.eventChecks || {})) if (key.indexOf(uid + "|") !== 0) checks[key] = data.eventChecks[key];
  return Object.assign({}, data, { eventChecks: checks });
}

function eventKey(uid, calendar) {
  return String(uid || "") + "\u0001" + String(calendar || "");
}

// Same array back when nothing is hidden, so bindings do not churn. Keys are
// eventKey(uid, calendar); an event is hidden only when both match.
function hideEvents(events, hiddenKeys) {
  if (!events) return [];
  if (hiddenKeys.length === 0) return events;
  return events.filter((ev) => hiddenKeys.indexOf(eventKey(ev.uid, ev.calendar)) < 0);
}
