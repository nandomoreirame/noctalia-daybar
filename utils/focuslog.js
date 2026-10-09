.pragma library

// Completed focus sessions per day: data.focusLog = { "YYYY-MM-DD": count }.

function sessionsOn(data, date) {
  const log = data.focusLog || {};
  return Number(log[date]) || 0;
}

function addSession(data, date) {
  const log = Object.assign({}, data.focusLog || {});
  log[date] = sessionsOn(data, date) + 1;
  return Object.assign({}, data, { focusLog: log });
}

// True only for the session that reaches the goal; a zero goal is disabled.
function goalJustReached(count, goal) {
  return goal > 0 && count === goal;
}
