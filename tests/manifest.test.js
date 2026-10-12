import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";

const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"));

describe("manifest", () => {
  it("declares the plugin identity", () => {
    expect(manifest.id).toBe("daybar");
    expect(manifest.license).toBe("MIT");
  });

  it("points every entry point at an existing file", () => {
    for (const file of Object.values(manifest.entryPoints)) {
      expect(existsSync(new URL("../" + file, import.meta.url)), file).toBe(true);
    }
  });

  it("ships the default settings the services read", () => {
    expect(Object.keys(manifest.metadata.defaultSettings).sort()).toEqual([
      "autoStartBreaks", "autoStartWork", "clockCorner", "clockSize", "dailyPomodoroGoal", "defaultCalendar", "fetchPreviews", "focusModeCommand", "initialTab",
      "longBreakDuration", "playSound", "sessionsBeforeLongBreak", "shortBreakDuration", "workDuration"
    ]);
  });
});
