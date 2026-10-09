.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Task capture: local task; no date means today.
var TYPE = "task";

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  return { ok: true, type: TYPE, action: "addTask", payload: { title: w.title, date: w.date || Dates.isoDate(now), time: w.start } };
}
