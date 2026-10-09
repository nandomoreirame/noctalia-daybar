.pragma library

// argv builders for khal/vdirsyncer. Always an array (Process.command), never a
// shell string, so user text cannot inject commands or options.
// Requires khal's [locale] formats set to ISO (see README):
//   dateformat = %Y-%m-%d, timeformat = %H:%M, datetimeformat = %Y-%m-%d %H:%M

function sanitizeSummary(title) {
  return String(title || "").replace(/::/g, ":").replace(/\s+/g, " ").trim();
}

// ev: { calendar, date, start, endDate, endTime, title, alarm }
function newEventArgs(ev) {
  const args = ["khal", "new"];
  if (ev.calendar) args.push("-a", ev.calendar);
  if (ev.alarm) args.push("--alarms", "0m");
  args.push("--", ev.date + " " + ev.start, ev.endDate + " " + ev.endTime, sanitizeSummary(ev.title));
  return args;
}

function syncArgs() {
  return ["vdirsyncer", "sync"];
}

function printCalendarsArgs() {
  return ["khal", "printcalendars"];
}

// `khal printcalendars` prints one calendar name per line.
function parseCalendars(stdout) {
  return String(stdout || "").split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
}
