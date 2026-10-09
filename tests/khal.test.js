import { describe, it, expect } from "vitest";
import { newEventArgs, syncArgs, printCalendarsArgs, parseCalendars, sanitizeSummary } from "../utils/khal.js";

describe("khal argv", () => {
  it("builds khal new for an event", () => {
    expect(newEventArgs({ calendar: "pessoal", date: "2026-10-16", start: "15:00", endDate: "2026-10-16", endTime: "16:00", title: "reunião", alarm: false }))
      .toEqual(["khal", "new", "-a", "pessoal", "--", "2026-10-16 15:00", "2026-10-16 16:00", "reunião"]);
  });

  it("adds an alarm at start for reminders and omits an empty calendar", () => {
    expect(newEventArgs({ calendar: "", date: "2026-10-10", start: "09:00", endDate: "2026-10-10", endTime: "09:15", title: "pagar boleto", alarm: true }))
      .toEqual(["khal", "new", "--alarms", "0m", "--", "2026-10-10 09:00", "2026-10-10 09:15", "pagar boleto"]);
  });

  it("keeps hostile titles as a single inert argument", () => {
    const args = newEventArgs({ calendar: "c", date: "2026-10-10", start: "09:00", endDate: "2026-10-10", endTime: "10:00", title: "--help; rm -rf ~ :: desc\nx", alarm: false });
    expect(args[args.length - 1]).toBe("--help; rm -rf ~ : desc x");
    expect(args.indexOf("--")).toBeLessThan(args.length - 1);
  });

  it("sanitizes summaries", () => {
    expect(sanitizeSummary("  a::b \r\n c ")).toBe("a:b c");
    expect(sanitizeSummary("a:::b")).toBe("a:b");
    expect(sanitizeSummary("a::::::b")).toBe("a:b");
  });

  it("builds sync and calendar listing commands", () => {
    expect(syncArgs()).toEqual(["vdirsyncer", "sync"]);
    expect(printCalendarsArgs()).toEqual(["khal", "printcalendars"]);
    expect(parseCalendars("pessoal\ntrabalho\n\n")).toEqual(["pessoal", "trabalho"]);
  });
});
