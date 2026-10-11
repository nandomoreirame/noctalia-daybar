.pragma library

// Free-form countdown durations for the timer: "90s", "10m", "10min", "1h", "1h30",
// "1h30m", "1h30min", "1:30" (m:ss), "1:02:03" (h:mm:ss) or a bare number of minutes.
// A field out of range (seconds or minutes above 59) yields -1, read as invalid.
var MAX_SECONDS = 24 * 3600;

// Words with an explicit h/m/s unit. Consecutive ones add up ("1h 30m").
var UNIT_PATTERNS = [
  [/^(\d+)h(?:(\d{1,2})(?:m|min)?)?$/, (m) => (m[2] && +m[2] > 59 ? -1 : +m[1] * 3600 + (m[2] ? +m[2] * 60 : 0))],
  [/^(\d+)(?:m|min)$/, (m) => +m[1] * 60],
  [/^(\d+)s$/, (m) => +m[1]]
];
// Clock forms, used only when no unit word exists, so a time in the label
// ("reunião às 14:30 5m") does not win over the duration.
var CLOCK_PATTERNS = [
  [/^(\d+):(\d{2}):(\d{2})$/, (m) => (+m[2] > 59 || +m[3] > 59 ? -1 : +m[1] * 3600 + +m[2] * 60 + +m[3])],
  [/^(\d+):(\d{2})$/, (m) => (+m[2] > 59 ? -1 : +m[1] * 60 + +m[2])]
];
// A bare number counts as minutes only as the first word ("10 chá"), never
// inside the label ("ler 3 capítulos").
var BARE_MINUTES = /^(\d+)$/;

function match(patterns, token) {
  for (const [re, toSeconds] of patterns) {
    const m = re.exec(token);
    if (m) return toSeconds(m);
  }
  return null;
}

function result(seconds, words, from, to) {
  if (seconds <= 0 || seconds > MAX_SECONDS) return { ok: false, error: "invalid-duration" };
  return { ok: true, seconds: seconds, label: words.slice(0, from).concat(words.slice(to)).join(" ") };
}

// -> { ok: true, seconds, label } | { ok: false, error: "needs-duration" | "invalid-duration" }
// Unit words win (the first run of them is summed), then the first clock form, then a
// leading bare number; the other words form the label.
function parseDuration(text) {
  const words = String(text || "").trim().split(/\s+/).filter((w) => w);
  const lower = words.map((w) => w.toLowerCase());

  const first = lower.findIndex((w) => match(UNIT_PATTERNS, w) !== null);
  if (first >= 0) {
    let total = 0;
    let end = first;
    while (end < lower.length) {
      const s = match(UNIT_PATTERNS, lower[end]);
      if (s === null) break;
      if (s < 0) return { ok: false, error: "invalid-duration" };
      total += s;
      end += 1;
    }
    return result(total, words, first, end);
  }

  for (let i = 0; i < lower.length; i++) {
    const s = match(CLOCK_PATTERNS, lower[i]);
    if (s !== null) return result(s, words, i, i + 1);
  }

  const bare = lower.length > 0 ? BARE_MINUTES.exec(lower[0]) : null;
  if (bare) return result(+bare[1] * 60, words, 0, 1);
  return { ok: false, error: "needs-duration" };
}
