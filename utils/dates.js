.pragma library

// Local-time date helpers. Dates travel as "YYYY-MM-DD" strings and times as
// "HH:MM" strings so they serialize to JSON without timezone drift.

function pad2(n) {
  return (n < 10 ? "0" : "") + n;
}

function isoDate(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function parseIsoDate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || "");
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isoDate(d) === s ? d : null;
}

function addDays(d, n) {
  const r = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  r.setDate(r.getDate() + n);
  return r;
}

function hhmm(d) {
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function minutesOf(time) {
  const m = /^(\d{2}):(\d{2})$/.exec(time || "");
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

function toDate(date, time) {
  const base = parseIsoDate(date);
  const minutes = time ? minutesOf(time) : 0;
  return new Date(base.getFullYear(), base.getMonth(), base.getDate(), 0, minutes);
}

function addMinutes(date, time, minutes) {
  const d = toDate(date, time);
  d.setMinutes(d.getMinutes() + minutes);
  return { date: isoDate(d), time: hhmm(d) };
}
