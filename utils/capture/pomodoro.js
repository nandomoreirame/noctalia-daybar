.pragma library
.import "../pomodoro.js" as Pomodoro

// Pomodoro commands, reachable only through "/p": "/p" starts or pauses, "/p foco",
// "/p curta", "/p longa" switch to that phase (if different) and start it, "/p parar" resets.
var TYPE = "pomodoro";
var ALLOW_EMPTY = true;
var COMMANDS = {
  "": "toggle",
  "foco": "work",
  "focus": "work",
  "curta": "short",
  "pausa curta": "short",
  "short": "short",
  "longa": "long",
  "pausa longa": "long",
  "long": "long",
  "parar": "stop",
  "stop": "stop"
};
var MODES = { work: Pomodoro.WORK, short: Pomodoro.SHORT, long: Pomodoro.LONG };
var MODE_NAMES = ["work", "short", "long"];

function build(text) {
  const key = String(text || "").trim().toLowerCase().replace(/\s+/g, " ");
  if (!Object.prototype.hasOwnProperty.call(COMMANDS, key)) return { ok: false, type: TYPE, error: "unknown-command" };
  return { ok: true, type: TYPE, action: "pomodoro", payload: { command: COMMANDS[key] } };
}

// What Enter does, given { running, mode }: { op: "start" | "pause" | "reset", switchTo }.
// switchTo is the phase to set first, or -1 to keep the current one (a paused phase resumes).
function plan(command, state) {
  if (command === "stop") return { op: "reset", switchTo: -1 };
  if (command === "toggle") return { op: state.running ? "pause" : "start", switchTo: -1 };
  const mode = MODES[command];
  return { op: "start", switchTo: mode === state.mode ? -1 : mode };
}

// i18n key of the preview line.
function previewKey(command, state) {
  const p = plan(command, state);
  if (p.op === "reset") return "capture.pomodoro.stop";
  if (p.op === "pause") return "capture.pomodoro.pause";
  return "capture.pomodoro.start-" + MODE_NAMES[p.switchTo >= 0 ? p.switchTo : state.mode];
}
