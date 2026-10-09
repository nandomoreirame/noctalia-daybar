.pragma library

// Pure task and event-check operations. Every function returns a NEW data object;
// Main.qml persists the result.

function withTasks(data, tasks) {
  return Object.assign({}, data, { tasks: tasks });
}

function addTask(data, fields, id, nowIso) {
  const task = {
    id: id,
    title: fields.title,
    date: fields.date || null,
    time: fields.time || null,
    done: false,
    doneAt: null,
    pomodoros: 0,
    source: "local",
    externalId: null,
    createdAt: nowIso
  };
  return withTasks(data, data.tasks.concat([task]));
}

function toggleTask(data, id, nowIso) {
  return withTasks(data, data.tasks.map((t) => t.id !== id ? t : Object.assign({}, t, { done: !t.done, doneAt: t.done ? null : nowIso })));
}

function deleteTask(data, id) {
  return withTasks(data, data.tasks.filter((t) => t.id !== id));
}

function addPomodoro(data, id) {
  return withTasks(data, data.tasks.map((t) => t.id !== id ? t : Object.assign({}, t, { pomodoros: t.pomodoros + 1 })));
}

function eventKey(uid, date) {
  return uid + "|" + date;
}

function toggleEventCheck(data, uid, date) {
  const checks = Object.assign({}, data.eventChecks);
  const key = eventKey(uid, date);
  if (checks[key]) delete checks[key];
  else checks[key] = true;
  return Object.assign({}, data, { eventChecks: checks });
}
