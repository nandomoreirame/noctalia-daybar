.pragma library
.import "../duration.js" as Duration

// Timer capture: "/t 10m chá" starts a countdown (replacing the one set), "/t" alone
// pauses or resumes the timer that is set, "/t parar" (or "stop") resets it.
var TYPE = "timer";
// "/t" with nothing after it is a command, not an empty capture.
var ALLOW_EMPTY = true;
var STOP_WORDS = ["parar", "stop"];

function build(text) {
  const body = String(text || "").trim();
  if (!body) return { ok: true, type: TYPE, action: "timerToggle", payload: {} };
  if (STOP_WORDS.indexOf(body.toLowerCase()) >= 0) return { ok: true, type: TYPE, action: "timerStop", payload: {} };
  const d = Duration.parseDuration(body);
  if (!d.ok) return { ok: false, type: TYPE, error: d.error };
  return { ok: true, type: TYPE, action: "startTimer", payload: { seconds: d.seconds, label: d.label } };
}

// i18n key of the preview line, given the timer state { set, running, ringing }. For
// startTimer the overlay shows the clock and label and appends this key when non-empty.
function previewKey(action, timer) {
  if (action === "timerStop") return "capture.timer.stop";
  if (action === "timerToggle") {
    if (!timer.set) return "capture.error.no-timer";
    if (timer.ringing) return "capture.timer.dismiss";
    return timer.running ? "capture.timer.pause" : "capture.timer.resume";
  }
  return timer.set ? "capture.timer.replaces" : "";
}
