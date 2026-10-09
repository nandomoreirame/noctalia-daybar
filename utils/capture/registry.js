.pragma library
.import "task.js" as Task
.import "event.js" as Event
.import "reminder.js" as Reminder
.import "note.js" as Note
.import "link.js" as Link
.import "calculation.js" as Calculation

// Capture type resolution. Inference order:
//   1. "=" -> calculation (always)
//   2. prefix "/e" event, "/l" reminder, "/n" note
//   3. type forced with Tab
//   4. a lone http(s) URL -> link
//   5. task (default)
// To add a type: create capture/<type>.js with TYPE and build(text, now), then
// register it in HANDLERS, CYCLE and (optionally) PREFIXES.

var CYCLE = ["task", "event", "reminder", "note", "link"];
var PREFIXES = [["/e", "event"], ["/l", "reminder"], ["/n", "note"]];
var HANDLERS = { task: Task, event: Event, reminder: Reminder, note: Note, link: Link };

function resolve(text, forcedType, now) {
  const trimmed = String(text || "").trim();
  if (trimmed.charAt(0) === "=") return Calculation.build(trimmed.slice(1));

  let type = null;
  let body = trimmed;
  for (const [prefix, prefixType] of PREFIXES) {
    if (trimmed === prefix || trimmed.indexOf(prefix + " ") === 0) {
      type = prefixType;
      body = trimmed.slice(prefix.length).trim();
      break;
    }
  }
  if (!type) type = HANDLERS[forcedType] ? forcedType : (Link.isLink(trimmed) ? "link" : "task");
  if (!body) return { ok: false, type: type, error: "empty" };
  return HANDLERS[type].build(body, now);
}

function nextType(current) {
  const i = CYCLE.indexOf(current);
  return CYCLE[(i + 1) % CYCLE.length];
}
