.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Event capture: Google Calendar event via khal; 1h when no end is given.
var TYPE = "event";
var DEFAULT_MINUTES = 60;

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  if (!w.date || !w.start) return { ok: false, type: TYPE, error: "needs-date-time" };
  const end = w.end ? { date: w.date, time: w.end } : Dates.addMinutes(w.date, w.start, DEFAULT_MINUTES);
  return {
    ok: true,
    type: TYPE,
    action: "createEvent",
    payload: { title: w.title, date: w.date, start: w.start, endDate: end.date, endTime: end.time, alarm: false }
  };
}
