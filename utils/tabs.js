.pragma library

// Toolbar tabs and which one the panel opens on.

var TABS = ["calendar", "today", "focus", "bookmarks", "notes"];
var FALLBACK = "today";
var ICONS = { calendar: "calendar", today: "list-check", focus: "hourglass", bookmarks: "bookmark", notes: "notes" };

function isTab(key) {
  return TABS.indexOf(key) >= 0;
}

// An IPC `open <tab>` request wins; then the "initialTab" setting, where "last"
// means the tab the user had open last time.
function initialTab(requested, setting, lastTab) {
  if (isTab(requested)) return requested;
  if (setting === "last") return isTab(lastTab) ? lastTab : FALLBACK;
  return isTab(setting) ? setting : FALLBACK;
}

// Same object back when nothing changes, so selecting the current tab does not
// schedule a write.
function setLastTab(data, key) {
  const ui = data.ui || {};
  if (!isTab(key) || ui.lastTab === key) return data;
  return Object.assign({}, data, { ui: Object.assign({}, ui, { lastTab: key }) });
}
