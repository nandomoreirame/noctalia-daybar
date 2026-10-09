.pragma library
.import "dates.js" as Dates

// Helpers over Noctalia CalendarService events:
//   { uid, calendar, summary, start, end, location, description }
// where start/end are UNIX timestamps in SECONDS.

function dayBounds(iso) {
  const start = Dates.parseIsoDate(iso);
  return { start: start.getTime(), end: Dates.addDays(start, 1).getTime() };
}

function overlapsDay(ev, iso) {
  const b = dayBounds(iso);
  const s = ev.start * 1000;
  const e = Math.max(ev.end * 1000, s + 1);
  return s < b.end && e > b.start;
}

// All-day = starts at local midnight and lasts a whole number of days.
function isAllDay(ev) {
  const s = new Date(ev.start * 1000);
  const durationMs = (ev.end - ev.start) * 1000;
  return s.getHours() === 0 && s.getMinutes() === 0 && durationMs > 0 && durationMs % 86400000 === 0;
}

// "HH:MM" when the event starts on that day with a time, else null.
function timeOn(ev, iso) {
  if (isAllDay(ev)) return null;
  const s = new Date(ev.start * 1000);
  return Dates.isoDate(s) === iso ? Dates.hhmm(s) : null;
}

function compareTime(a, b) {
  if (a === b) return 0;
  if (a === null) return -1;
  if (b === null) return 1;
  return a < b ? -1 : 1;
}

// Events of one day, untimed (all-day or continuing) first, then by start time.
function eventsOn(events, iso) {
  return (events || [])
    .filter((ev) => overlapsDay(ev, iso))
    .map((ev) => ({ ev: ev, time: timeOn(ev, iso) }))
    .sort((a, b) => compareTime(a.time, b.time) || (a.ev.start - b.ev.start))
    .map((x) => Object.assign({}, x.ev, { time: x.time }));
}
