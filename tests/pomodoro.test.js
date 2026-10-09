import { describe, it, expect } from "vitest";
import { WORK, SHORT, LONG, durationFor, nextPhase, finish, formatClock, configFrom, idleRemaining, canFocusTask } from "../utils/pomodoro.js";

const cfg = { work: 1500, short: 300, long: 900, sessionsBeforeLong: 2, autoStartBreaks: true, autoStartWork: false };

describe("pomodoro", () => {
  it("maps modes to durations", () => {
    expect([WORK, SHORT, LONG].map((m) => durationFor(m, cfg))).toEqual([1500, 300, 900]);
  });

  it("cycles work -> short -> work -> long -> work", () => {
    let s = { mode: WORK, completed: 0 };
    const seen = [];
    for (let i = 0; i < 5; i++) {
      s = nextPhase(s, cfg);
      seen.push([s.mode, s.completed]);
    }
    expect(seen).toEqual([[SHORT, 0], [WORK, 1], [LONG, 1], [WORK, 0], [SHORT, 0]]);
  });

  it("reports work completion and auto-start per phase", () => {
    expect(finish({ mode: WORK, completed: 0 }, cfg)).toEqual({ next: { mode: SHORT, completed: 0 }, remaining: 300, workCompleted: true, autoStart: true });
    expect(finish({ mode: SHORT, completed: 0 }, cfg)).toMatchObject({ workCompleted: false, autoStart: false, remaining: 1500 });
  });

  it("formats the clock", () => {
    expect(formatClock(1500)).toBe("25:00");
    expect(formatClock(59)).toBe("00:59");
    expect(formatClock(3725)).toBe("1:02:05");
    expect(formatClock(-3)).toBe("00:00");
  });
});

describe("pomodoro config", () => {
  const defaults = { workDuration: 25, shortBreakDuration: 5, longBreakDuration: 15, sessionsBeforeLongBreak: 4, dailyPomodoroGoal: 8, autoStartBreaks: false, autoStartWork: true };

  it("converts minutes to seconds and keeps the flags", () => {
    expect(configFrom(defaults)).toEqual({ work: 1500, short: 300, long: 900, sessionsBeforeLong: 4, dailyGoal: 8, autoStartBreaks: false, autoStartWork: true });
  });

  it("clamps out-of-range and non-numeric values", () => {
    const cfg = configFrom({ ...defaults, workDuration: 0, shortBreakDuration: 999, longBreakDuration: "x", sessionsBeforeLongBreak: -3, dailyPomodoroGoal: 99 });
    expect(cfg).toMatchObject({ work: 60, short: 3600, long: 900, sessionsBeforeLong: 1, dailyGoal: 24 });
  });

  it("allows a zero daily goal (disabled)", () => {
    expect(configFrom({ ...defaults, dailyPomodoroGoal: 0 }).dailyGoal).toBe(0);
  });
});

describe("pomodoro idle resize", () => {
  it("follows the new duration while the phase has not started", () => {
    expect(idleRemaining(false, 1500, WORK, { ...cfg, work: 3000 })).toBe(3000);
    expect(idleRemaining(false, 300, SHORT, { ...cfg, short: 600 })).toBe(600);
  });

  it("keeps the remaining time of a started (running or paused) phase", () => {
    expect(idleRemaining(true, 1234, WORK, { ...cfg, work: 3000 })).toBe(1234);
  });
});

describe("pomodoro task shortcut", () => {
  it("is blocked only while a focus session is running", () => {
    expect(canFocusTask(true, WORK)).toBe(false);
    expect(canFocusTask(false, WORK)).toBe(true);
    expect(canFocusTask(true, SHORT)).toBe(true);
    expect(canFocusTask(true, LONG)).toBe(true);
    expect(canFocusTask(false, LONG)).toBe(true);
  });
});
