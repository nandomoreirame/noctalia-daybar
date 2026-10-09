.pragma library

// Pomodoro phase machine, extracted from the MIT "pomodoro" Noctalia plugin
// (see THIRD_PARTY.md). Same semantics as the original:
//   - a finished WORK goes to LONG when completed+1 >= sessionsBeforeLong, else SHORT
//   - a finished SHORT increments `completed`; a finished LONG resets it to 0

var WORK = 0;
var SHORT = 1;
var LONG = 2;

// Integer setting clamped to [min, max]; non-numeric values fall back to `fallback`.
function clampInt(value, min, max, fallback) {
  const n = Math.round(Number(value));
  if (!isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

// Plugin settings (minutes) -> phase config (seconds), with the same bounds as the
// settings UI, so a hand-edited settings.json cannot produce a 0 s or negative phase.
function configFrom(s) {
  return {
    work: clampInt(s.workDuration, 1, 180, 25) * 60,
    short: clampInt(s.shortBreakDuration, 1, 60, 5) * 60,
    long: clampInt(s.longBreakDuration, 1, 120, 15) * 60,
    sessionsBeforeLong: clampInt(s.sessionsBeforeLongBreak, 1, 12, 4),
    dailyGoal: clampInt(s.dailyPomodoroGoal, 0, 24, 8),
    autoStartBreaks: !!s.autoStartBreaks,
    autoStartWork: !!s.autoStartWork
  };
}

// Remaining seconds after a config change: an untouched phase follows the new
// duration; a started one (running or paused) keeps its countdown.
function idleRemaining(started, remaining, mode, cfg) {
  return started ? remaining : durationFor(mode, cfg);
}

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
