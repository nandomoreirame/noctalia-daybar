.pragma library
.import "dates.js" as Dates

// Local reminder schedule. A reminder that became due while the shell was down
// fires only if it is at most GRACE_MINUTES late; older ones expire silently
// (the Google event alarm already covered them).

var GRACE_MINUTES = 10;

function addReminder(data, fields, id) {
  const reminder = { id: id, title: fields.title, date: fields.date, time: fields.time, fired: false };
  return Object.assign({}, data, { reminders: data.reminders.concat([reminder]) });
}

// Returns { fire: [reminder], expire: [reminder] } for reminders not fired yet.
function dueReminders(data, now) {
  const fire = [];
  const expire = [];
  const graceMs = GRACE_MINUTES * 60000;
  for (const r of data.reminders) {
    if (r.fired) continue;
    const at = Dates.toDate(r.date, r.time).getTime();
    if (at > now.getTime()) continue;
    if (now.getTime() - at <= graceMs) fire.push(r);
    else expire.push(r);
  }
  return { fire: fire, expire: expire };
}

function markFired(data, ids) {
  return Object.assign({}, data, {
    reminders: data.reminders.map((r) => ids.indexOf(r.id) < 0 ? r : Object.assign({}, r, { fired: true }))
  });
}
