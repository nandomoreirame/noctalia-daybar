.pragma library
.import "dates.js" as Dates

// Natural-language "when" parser for pt-BR capture text.
//   parseWhen("comprar pão amanhã 9h", now)
//   -> { title: "comprar pão", date: "2026-10-10", start: "09:00", end: null }
// JS `\b` treats accented letters as non-word characters, so tokens are delimited
// with explicit whitespace/punctuation lookarounds instead.

var END = "(?=$|[\\s,.;!?])";
var LEAD = "(^|\\s)(?:(?:na|no|para|pra|em|de|às|as|a)\\s+)?";
var TIME = "(\\d{1,2})(?:h(\\d{2})?|:(\\d{2}))";
var TIME_OPT = "(\\d{1,2})(?:h(\\d{2})?|:(\\d{2}))?";
var RANGE_SEP = "\\s*(?:-|até|às|as)\\s*";

var RELATIVE_DAYS = [
  ["depois de amanh[ãa]", 2],
  ["amanh[ãa]", 1],
  ["hoje", 0]
];

// [pattern, day of week, doubles as an ordinal adjective ("a sexta parte")]
var WEEKDAYS = [
  ["domingo", 0, false],
  ["segunda(?:-feira)?", 1, true],
  ["ter[çc]a(?:-feira)?", 2, true],
  ["quarta(?:-feira)?", 3, true],
  ["quinta(?:-feira)?", 4, true],
  ["sexta(?:-feira)?", 5, true],
  ["s[áa]bado", 6, false]
];

// What may follow an ordinal-capable weekday for it to still read as a day:
// end of text, punctuation or a time ("sexta 15h"). A following word means an
// adjective ("segunda reunião"), unless the word opens the text ("segunda revisar PR").
var WEEKDAY_FOLLOW = /^(?:\s*$|\s*[,.;!?]|\s+\d{1,2}(?:h|:))/;

// Finds the first match of `re` in state.rest; when `accept(match)` returns a
// non-null value, removes the match (keeping its leading whitespace) and returns it.
function take(state, re, accept) {
  const m = re.exec(state.rest);
  if (!m) return null;
  const value = accept(m);
  if (value === null) return null;
  state.rest = state.rest.slice(0, m.index) + m[1] + state.rest.slice(m.index + m[0].length);
  return value;
}

function toTime(hours, minA, minB) {
  const h = Number(hours);
  const m = Number(minA || minB || 0);
  if (h > 23 || m > 59) return null;
  return Dates.pad2(h) + ":" + Dates.pad2(m);
}

function parseDay(state, today) {
  for (const [word, offset] of RELATIVE_DAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), () => Dates.isoDate(Dates.addDays(today, offset)));
    if (v) return v;
  }
  for (const [word, dow, ordinal] of WEEKDAYS) {
    const v = take(state, new RegExp(LEAD + word + END, "i"), (m) => {
      if (ordinal && !/-feira$/i.test(m[0]) && m.index > 0 && !WEEKDAY_FOLLOW.test(state.rest.slice(m.index + m[0].length)))
        return null;
      const diff = (dow - today.getDay() + 7) % 7 || 7;
      return Dates.isoDate(Dates.addDays(today, diff));
    });
    if (v) return v;
  }
  return take(state, new RegExp(LEAD + "(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?" + END, "i"), (m) => {
    const day = Number(m[2]);
    const month = Number(m[3]) - 1;
    const year = m[4] ? Number(m[4].length === 2 ? "20" + m[4] : m[4]) : today.getFullYear();
    let d = new Date(year, month, day);
    if (d.getMonth() !== month || d.getDate() !== day) return null;
    if (!m[4] && d < today) d = new Date(year + 1, month, day);
    return Dates.isoDate(d);
  });
}

function parseTimes(state) {
  const range = take(state, new RegExp(LEAD + TIME + RANGE_SEP + TIME_OPT + END, "i"), (m) => {
    // A bare end number ("às 10") followed by a word is a quantity, not a time.
    const bareEnd = /\d$/.test(m[0]) && !/(?:h|:)\d*$/i.test(m[0]);
    if (bareEnd && /^\s+[^\s\d]/.test(state.rest.slice(m.index + m[0].length))) return null;
    const start = toTime(m[2], m[3], m[4]);
    const end = toTime(m[5], m[6], m[7]);
    if (!start || !end || Dates.minutesOf(end) <= Dates.minutesOf(start)) return null;
    return { start: start, end: end };
  });
  if (range) return range;
  const start = take(state, new RegExp(LEAD + TIME + END, "i"), (m) => toTime(m[2], m[3], m[4]));
  return { start: start, end: null };
}

function parseWhen(text, now) {
  const state = { rest: String(text || "") };
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let date = parseDay(state, today);
  const times = parseTimes(state);
  if (!date && times.start) {
    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const past = Dates.minutesOf(times.start) <= nowMinutes;
    date = Dates.isoDate(past ? Dates.addDays(today, 1) : today);
  }
  const title = state.rest.replace(/\s+/g, " ").trim();
  return { title: title, date: date, start: times.start, end: times.end };
}
