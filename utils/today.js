.pragma library
.import "dates.js" as Dates
.import "events.js" as Events
.import "tasks.js" as Tasks

// Builds the Today checklist:
//   1. today's calendar events (untimed first, then by time)
//   2. today's tasks and overdue undone tasks, timed by time, then untimed
// Item: { kind, id, uid, calendar, title, time, done, overdue, pomodoros }

function eventItems(events, data, iso) {
  return Events.eventsOn(events, iso).map((ev) => ({
    kind: "event",
    id: Tasks.eventKey(ev.uid, iso),
    uid: ev.uid,
    calendar: ev.calendar || "",
    title: ev.summary,
    time: ev.time,
    done: !!data.eventChecks[Tasks.eventKey(ev.uid, iso)],
    overdue: false,
    pomodoros: 0
  }));
}

function compareTasks(a, b) {
  if (a.time && b.time) return a.time < b.time ? -1 : a.time > b.time ? 1 : 0;
  if (a.time) return -1;
  if (b.time) return 1;
  return String(a.createdAt || "") < String(b.createdAt || "") ? -1 : 1;
}

function taskItem(t, iso) {
  return {
    kind: "task",
    id: t.id,
    uid: null,
    calendar: "",
    title: t.title,
    time: t.time,
    done: t.done,
    overdue: (t.date || iso) < iso,
    pomodoros: t.pomodoros
  };
}

function taskItems(data, iso) {
  return data.tasks
    .filter((t) => {
      const date = t.date || iso;
      return date === iso || (date < iso && !t.done);
    })
    .slice()
    .sort(compareTasks)
    .map((t) => taskItem(t, iso));
}

// Calendar day list for any day: that day's events, then the tasks dated on it
// (an undated task belongs to today). No overdue carry-over: that is Today's job.
function dayItems(events, data, iso, todayIso) {
  const tasks = data.tasks
    .filter((t) => (t.date || todayIso) === iso)
    .slice()
    .sort(compareTasks)
    .map((t) => Object.assign(taskItem(t, iso), { overdue: false }));
  return eventItems(events, data, iso).concat(tasks);
}

function buildToday(events, data, now) {
  const iso = Dates.isoDate(now);
  return eventItems(events, data, iso).concat(taskItems(data, iso));
}
