.pragma library

// Shared rules for the two countdowns (pomodoro and timer). Only one counts at a
// time: starting one pauses the other.

var TIMER_ICON = "alarm";
// Chip value of the Timer chip in the Focus tab (pomodoro modes are 0..2).
var TIMER_CHIP = -1;

// Which clock the bar shows: the running one, else the one whose alarm rings.
// state: { pomodoroRunning, timerRunning, alarmSource } -> "timer" | "pomodoro" | ""
function barSource(state) {
  if (state.timerRunning) return "timer";
  if (state.pomodoroRunning) return "pomodoro";
  return state.alarmSource === "timer" || state.alarmSource === "pomodoro" ? state.alarmSource : "";
}

// Ring fill: remaining over total, clamped to [0, 1]; 0 without a positive total.
function progress(remaining, total) {
  if (!(total > 0)) return 0;
  return Math.min(1, Math.max(0, remaining / total));
}

// Middle click on the bar pauses or resumes the clock shown, else the pomodoro.
function middleClickTarget(source) {
  return source === "timer" ? "timer" : "pomodoro";
}

// Focus tab chip click -> "show-timer" | "show-pomodoro" | "set-mode".
// Coming back from the Timer view to the current pomodoro mode must not reset it.
function chipAction(chip, view, mode) {
  if (chip === TIMER_CHIP) return "show-timer";
  if (view === "timer" && chip === mode) return "show-pomodoro";
  return "set-mode";
}

// Detached clock (window and corner overlay): the bar's clock while one runs or rings,
// else the clock of the view selected in the Focus tab. Never "".
function shownClock(state) {
  const source = barSource(state);
  if (source) return source;
  return state.focusPanel === "timer" ? "timer" : "pomodoro";
}

var CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"];
var DEFAULT_CORNER = "top-right";

// Overlay corner setting -> PanelWindow anchors; unknown values use the default.
function cornerAnchors(corner) {
  const c = CORNERS.indexOf(corner) >= 0 ? corner : DEFAULT_CORNER;
  return { top: c.indexOf("top") === 0, bottom: c.indexOf("bottom") === 0, left: c.endsWith("left"), right: c.endsWith("right") };
}

// Overlay size setting -> ring diameter in px (before UI scale).
var RING_SIZES = { small: 90, medium: 130, large: 180 };
var DEFAULT_SIZE = "medium";

function ringSize(size) {
  return Object.prototype.hasOwnProperty.call(RING_SIZES, size) ? RING_SIZES[size] : RING_SIZES[DEFAULT_SIZE];
}
