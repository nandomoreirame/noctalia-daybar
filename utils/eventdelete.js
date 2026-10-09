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
