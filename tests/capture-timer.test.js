import { describe, it, expect } from "vitest";
import * as Timer from "../utils/capture/timer.js";
import * as PomodoroCommand from "../utils/capture/pomodoro.js";

describe("timer capture", () => {
  it("starts a timer with a duration and label", () => {
    expect(Timer.build("chá 5m")).toEqual({ ok: true, type: "timer", action: "startTimer", payload: { seconds: 300, label: "chá" } });
  });

  it("toggles with an empty body and resets with parar/stop", () => {
    expect(Timer.build("")).toMatchObject({ ok: true, action: "timerToggle" });
    expect(Timer.build("PARAR")).toMatchObject({ ok: true, action: "timerStop" });
    expect(Timer.build("stop")).toMatchObject({ ok: true, action: "timerStop" });
  });

  it("passes the parser error through", () => {
    expect(Timer.build("chá")).toEqual({ ok: false, type: "timer", error: "needs-duration" });
    expect(Timer.build("25h")).toEqual({ ok: false, type: "timer", error: "invalid-duration" });
  });

  it("allows an empty body only through its prefix", () => {
    expect(Timer.ALLOW_EMPTY).toBe(true);
  });

  it("names the preview line from the timer state", () => {
    const none = { set: false, running: false };
    const paused = { set: true, running: false };
    const running = { set: true, running: true };
    expect(Timer.previewKey("startTimer", none)).toBe("");
    expect(Timer.previewKey("startTimer", paused)).toBe("capture.timer.replaces");
    expect(Timer.previewKey("timerToggle", none)).toBe("capture.error.no-timer");
    expect(Timer.previewKey("timerToggle", paused)).toBe("capture.timer.resume");
    expect(Timer.previewKey("timerToggle", running)).toBe("capture.timer.pause");
    expect(Timer.previewKey("timerStop", running)).toBe("capture.timer.stop");
    // While its alarm rings, "/t" only silences it instead of restarting the countdown.
    expect(Timer.previewKey("timerToggle", { set: true, running: false, ringing: true })).toBe("capture.timer.dismiss");
  });
});

describe("pomodoro command capture", () => {
  it.each([
    ["", "toggle"],
    ["foco", "work"],
    ["Focus", "work"],
    ["curta", "short"],
    ["pausa  curta", "short"],
    ["short", "short"],
    ["longa", "long"],
    ["pausa longa", "long"],
    ["parar", "stop"],
    ["stop", "stop"]
  ])("'%s' -> %s", (text, command) => {
    expect(PomodoroCommand.build(text)).toEqual({ ok: true, type: "pomodoro", action: "pomodoro", payload: { command } });
  });

  it("rejects anything else", () => {
    expect(PomodoroCommand.build("agora")).toEqual({ ok: false, type: "pomodoro", error: "unknown-command" });
    expect(PomodoroCommand.build("constructor")).toEqual({ ok: false, type: "pomodoro", error: "unknown-command" });
  });

  // modes: WORK 0, SHORT 1, LONG 2
  it("plans what Enter does from the pomodoro state", () => {
    expect(PomodoroCommand.plan("toggle", { running: true, mode: 0 })).toEqual({ op: "pause", switchTo: -1 });
    expect(PomodoroCommand.plan("toggle", { running: false, mode: 0 })).toEqual({ op: "start", switchTo: -1 });
    expect(PomodoroCommand.plan("short", { running: false, mode: 1 })).toEqual({ op: "start", switchTo: -1 });
    expect(PomodoroCommand.plan("long", { running: true, mode: 0 })).toEqual({ op: "start", switchTo: 2 });
    expect(PomodoroCommand.plan("stop", { running: true, mode: 2 })).toEqual({ op: "reset", switchTo: -1 });
  });

  it("names the preview line", () => {
    expect(PomodoroCommand.previewKey("toggle", { running: true, mode: 0 })).toBe("capture.pomodoro.pause");
    expect(PomodoroCommand.previewKey("toggle", { running: false, mode: 1 })).toBe("capture.pomodoro.start-short");
    expect(PomodoroCommand.previewKey("work", { running: false, mode: 2 })).toBe("capture.pomodoro.start-work");
    expect(PomodoroCommand.previewKey("stop", { running: false, mode: 0 })).toBe("capture.pomodoro.stop");
  });
});
