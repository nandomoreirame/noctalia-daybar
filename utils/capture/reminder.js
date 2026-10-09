.pragma library
.import "../when.js" as When
.import "../dates.js" as Dates

// Reminder capture: 15-minute event with an alarm at start, plus a local toast.
var TYPE = "reminder";
var DURATION_MINUTES = 15;

function build(text, now) {
  const w = When.parseWhen(text, now);
  if (!w.title) return { ok: false, type: TYPE, error: "empty-title" };
  if (!w.start) return { ok: false, type: TYPE, error: "needs-time" };
  const end = Dates.addMinutes(w.date, w.start, DURATION_MINUTES);
  return {
    ok: true,
    type: TYPE,
    action: "createReminder",
    payload: { title: w.title, date: w.date, start: w.start, endDate: end.date, endTime: end.time, alarm: true }
  };
}
