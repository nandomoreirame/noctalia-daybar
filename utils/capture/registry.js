.pragma library
.import "task.js" as Task
.import "event.js" as Event
.import "reminder.js" as Reminder
.import "note.js" as Note
.import "link.js" as Link
.import "calculation.js" as Calculation
.import "timer.js" as Timer
.import "pomodoro.js" as PomodoroCommand

// Capture type resolution. Inference order:
//   1. "=" -> calculation (always)
//   2. "/p" -> pomodoro command (always; not in the Tab cycle)
//   3. prefix "/e" event, "/l" reminder, "/n" note, "/t" timer
//   4. type forced with Tab
//   5. a lone http(s) URL -> link
//   6. task (default)
// An empty body is rejected, except after a typed prefix whose handler sets
// ALLOW_EMPTY ("/t" alone is a command; an empty field on the Timer tab is not).
// To add a type: create capture/<type>.js with TYPE and build(text, now), then
// register it in HANDLERS, CYCLE and (optionally) PREFIXES.

var CYCLE = ["task", "event", "reminder", "note", "link", "timer"];
var PREFIXES = [["/e", "event"], ["/l", "reminder"], ["/n", "note"], ["/t", "timer"]];
var HANDLERS = { task: Task, event: Event, reminder: Reminder, note: Note, link: Link, timer: Timer };

function hasPrefix(text, prefix) {
  return text === prefix || text.indexOf(prefix + " ") === 0;
}

function resolve(text, forcedType, now) {
  const trimmed = String(text || "").trim();
  if (trimmed.charAt(0) === "=") return Calculation.build(trimmed.slice(1));
  if (hasPrefix(trimmed, "/p")) return PomodoroCommand.build(trimmed.slice(2));

  let type = null;
  let body = trimmed;
  for (const [prefix, prefixType] of PREFIXES) {
    if (hasPrefix(trimmed, prefix)) {
      type = prefixType;
      body = trimmed.slice(prefix.length).trim();
      break;
    }
  }
  const prefixed = type !== null;
  if (!type) type = HANDLERS[forcedType] ? forcedType : (Link.isLink(trimmed) ? "link" : "task");
  if (!body && !(prefixed && HANDLERS[type].ALLOW_EMPTY)) return { ok: false, type: type, error: "empty" };
  return HANDLERS[type].build(body, now);
}

function nextType(current) {
  const i = CYCLE.indexOf(current);
  return CYCLE[(i + 1) % CYCLE.length];
}

// Shift+Tab: one step back; a type outside the cycle wraps to the last one.
function prevType(current) {
  const i = CYCLE.indexOf(current);
  return CYCLE[i <= 0 ? CYCLE.length - 1 : i - 1];
}
