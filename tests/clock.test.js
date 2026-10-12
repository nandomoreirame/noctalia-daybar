import { describe, it, expect } from "vitest";
import { barSource, progress, middleClickTarget, chipAction, TIMER_CHIP, TIMER_ICON, shownClock, cornerAnchors, ringSize, CORNERS, RING_SIZES } from "../utils/clock.js";

describe("barSource", () => {
  const base = { pomodoroRunning: false, timerRunning: false, alarmSource: "" };

  it("shows the running clock first", () => {
    expect(barSource({ ...base, timerRunning: true })).toBe("timer");
    expect(barSource({ ...base, pomodoroRunning: true, alarmSource: "timer" })).toBe("pomodoro");
    // Never expected (starting one pauses the other), but the timer must still win.
    expect(barSource({ ...base, timerRunning: true, pomodoroRunning: true, alarmSource: "pomodoro" })).toBe("timer");
  });

  it("falls back to the clock whose alarm rings, else nothing", () => {
    expect(barSource({ ...base, alarmSource: "timer" })).toBe("timer");
    expect(barSource({ ...base, alarmSource: "pomodoro" })).toBe("pomodoro");
    expect(barSource(base)).toBe("");
    expect(barSource({ ...base, alarmSource: "junk" })).toBe("");
  });
});

describe("progress", () => {
  it("is remaining over total, clamped to [0, 1]", () => {
    expect(progress(150, 300)).toBe(0.5);
    expect(progress(400, 300)).toBe(1);
    expect(progress(-2, 300)).toBe(0);
  });

  it("is 0 without a positive total", () => {
    expect(progress(10, 0)).toBe(0);
    expect(progress(10, undefined)).toBe(0);
  });
});

describe("middleClickTarget", () => {
  it("drives the clock shown, else the pomodoro", () => {
    expect(middleClickTarget("timer")).toBe("timer");
    expect(middleClickTarget("pomodoro")).toBe("pomodoro");
    expect(middleClickTarget("")).toBe("pomodoro");
  });
});

describe("chipAction", () => {
  // modes: WORK 0, SHORT 1, LONG 2
  it("the Timer chip only switches the view", () => {
    expect(chipAction(TIMER_CHIP, "pomodoro", 0)).toBe("show-timer");
    expect(chipAction(TIMER_CHIP, "timer", 0)).toBe("show-timer");
  });

  it("the current pomodoro mode seen from the Timer view switches back without a reset", () => {
    expect(chipAction(1, "timer", 1)).toBe("show-pomodoro");
    expect(chipAction(0, "timer", 0)).toBe("show-pomodoro");
  });

  it("any other pomodoro chip sets the mode, as before", () => {
    expect(chipAction(2, "timer", 1)).toBe("set-mode");
    expect(chipAction(1, "pomodoro", 1)).toBe("set-mode");
  });

  it("names the timer icon", () => {
    expect(TIMER_ICON).toBe("alarm");
  });
});

describe("shownClock", () => {
  const base = { pomodoroRunning: false, timerRunning: false, alarmSource: "", focusPanel: "pomodoro" };

  it("follows the bar rule while a clock runs or rings", () => {
    expect(shownClock({ ...base, timerRunning: true })).toBe("timer");
    expect(shownClock({ ...base, pomodoroRunning: true, focusPanel: "timer" })).toBe("pomodoro");
    expect(shownClock({ ...base, alarmSource: "timer" })).toBe("timer");
  });

  it("falls back to the Focus view when nothing runs", () => {
    expect(shownClock(base)).toBe("pomodoro");
    expect(shownClock({ ...base, focusPanel: "timer" })).toBe("timer");
    expect(shownClock({ ...base, focusPanel: "junk" })).toBe("pomodoro");
  });
});

describe("cornerAnchors", () => {
  it("anchors two edges per corner", () => {
    expect(cornerAnchors("top-left")).toEqual({ top: true, bottom: false, left: true, right: false });
    expect(cornerAnchors("top-right")).toEqual({ top: true, bottom: false, left: false, right: true });
    expect(cornerAnchors("bottom-left")).toEqual({ top: false, bottom: true, left: true, right: false });
    expect(cornerAnchors("bottom-right")).toEqual({ top: false, bottom: true, left: false, right: true });
  });

  it("falls back to top-right", () => {
    for (const c of ["middle", "", undefined, null, 3]) expect(cornerAnchors(c)).toEqual(cornerAnchors("top-right"));
    expect(CORNERS).toEqual(["top-left", "top-right", "bottom-left", "bottom-right"]);
  });
});

describe("ringSize", () => {
  it("maps the size setting to the ring in px, medium by default", () => {
    expect(["small", "medium", "large"].map(ringSize)).toEqual([90, 130, 180]);
    for (const s of ["huge", 999, undefined, "constructor"]) expect(ringSize(s)).toBe(130);
    expect(Object.keys(RING_SIZES)).toEqual(["small", "medium", "large"]);
  });
});
