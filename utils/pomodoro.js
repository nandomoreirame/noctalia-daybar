.pragma library

// Pomodoro phase machine, extracted from the MIT "pomodoro" Noctalia plugin
// (see THIRD_PARTY.md). Same semantics as the original:
//   - a finished WORK goes to LONG when completed+1 >= sessionsBeforeLong, else SHORT
//   - a finished SHORT increments `completed`; a finished LONG resets it to 0

var WORK = 0;
var SHORT = 1;
var LONG = 2;

// cfg: { work, short, long } in seconds, sessionsBeforeLong, autoStartBreaks, autoStartWork
function durationFor(mode, cfg) {
  if (mode === SHORT) return cfg.short;
  if (mode === LONG) return cfg.long;
  return cfg.work;
}

function nextPhase(state, cfg) {
  if (state.mode === WORK) {
    return { mode: state.completed + 1 >= cfg.sessionsBeforeLong ? LONG : SHORT, completed: state.completed };
  }
  return { mode: WORK, completed: state.mode === LONG ? 0 : state.completed + 1 };
}

// What happens when a phase timer reaches zero.
function finish(state, cfg) {
  const next = nextPhase(state, cfg);
  return {
    next: next,
    remaining: durationFor(next.mode, cfg),
    workCompleted: state.mode === WORK,
    autoStart: state.mode === WORK ? !!cfg.autoStartBreaks : !!cfg.autoStartWork
  };
}

// "mm:ss", or "h:mm:ss" past one hour.
function formatClock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const pad = (n) => (n < 10 ? "0" : "") + n;
  return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s % 60);
}
