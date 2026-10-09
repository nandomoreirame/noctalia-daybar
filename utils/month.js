.pragma library
.import "dates.js" as Dates
.import "events.js" as Events

// Monday-first 6x7 month grid: [{ date, day, inMonth, today, hasEvents, hasTasks }].
// hasTasks: a pending task is dated that day (undated tasks belong to today).
function monthGrid(year, month, now, events, tasks) {
  const first = new Date(year, month, 1);
  const offset = (first.getDay() + 6) % 7;
  const start = Dates.addDays(first, -offset);
  const todayIso = Dates.isoDate(now);
  const pending = {};
  for (const t of tasks || []) if (!t.done) pending[t.date || todayIso] = true;
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const d = Dates.addDays(start, i);
    const iso = Dates.isoDate(d);
    cells.push({
      date: iso,
      day: d.getDate(),
      inMonth: d.getMonth() === month,
      today: iso === todayIso,
      hasEvents: (events || []).some((ev) => Events.overlapsDay(ev, iso)),
      hasTasks: !!pending[iso]
    });
  }
  return cells;
}

// Moves a {year, month} pair by `delta` months.
function shiftMonth(year, month, delta) {
  const d = new Date(year, month + delta, 1);
  return { year: d.getFullYear(), month: d.getMonth() };
}
