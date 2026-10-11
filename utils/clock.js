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
