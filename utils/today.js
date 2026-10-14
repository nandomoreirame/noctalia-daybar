.pragma library
.import "dates.js" as Dates
.import "events.js" as Events
.import "tasks.js" as Tasks
.import "eventdelete.js" as EventDelete

// Builds the Today checklist:
//   1. today's calendar events (untimed first, then by time)
//   2. today's tasks and overdue undone tasks, timed by time, then untimed
// Item: { kind, id, uid, calendar, title, time, endTime, done, overdue, pomodoros, checkable }
// Events from read-only calendars (holidays, birthdays, subscriptions) are not
// checkable: no checkbox, never done, left out of the progress counts.

function eventItems(events, data, iso, collections) {
  return Events.eventsOn(events, iso).map((ev) => {
    const checkable = !EventDelete.isReadOnlyCalendar(collections, ev.calendar);
    return {
      kind: "event",
      id: Tasks.eventKey(ev.uid, iso),
      uid: ev.uid,
      calendar: ev.calendar || "",
      title: ev.summary,
      time: ev.time,
      endTime: ev.endTime,
      done: checkable && !!data.eventChecks[Tasks.eventKey(ev.uid, iso)],
      overdue: false,
      pomodoros: 0,
      checkable: checkable
    };
  });
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
    pomodoros: t.pomodoros,
    checkable: true
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
function dayItems(events, data, iso, todayIso, collections) {
  const tasks = data.tasks
    .filter((t) => (t.date || todayIso) === iso)
    .slice()
    .sort(compareTasks)
    .map((t) => Object.assign(taskItem(t, iso), { overdue: false }));
  return eventItems(events, data, iso, collections).concat(tasks);
}

function buildToday(events, data, now, collections) {
  const iso = Dates.isoDate(now);
  return eventItems(events, data, iso, collections).concat(taskItems(data, iso));
}

// { done, total } of a checklist; items with checkable === false do not count.
function progress(items) {
  const list = items.filter((i) => i.checkable !== false);
  return { done: list.filter((i) => i.done).length, total: list.length };
}

// Same list as the Today tab (events, today's and overdue tasks).
function todayProgress(events, data, iso, collections) {
  return progress(eventItems(events, data, iso, collections).concat(taskItems(data, iso)));
}

// Same list as the Calendar day list for that day.
function dayProgress(events, data, iso, collections) {
  return progress(dayItems(events, data, iso, iso, collections));
}

// "Label (done/total)", or just the label when the list is empty.
function withProgress(label, p) {
  return p && p.total > 0 ? label + " (" + p.done + "/" + p.total + ")" : label;
}

// "Label (n)", or just the label when there is nothing.
function withCount(label, n) {
  return n > 0 ? label + " (" + n + ")" : label;
}
