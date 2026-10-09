import { describe, it, expect } from "vitest";
import { WORK, SHORT, LONG, durationFor, nextPhase, finish, formatClock } from "../utils/pomodoro.js";

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
