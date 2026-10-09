import { describe, it, expect } from "vitest";
import { pad2, isoDate, parseIsoDate, addDays, hhmm, minutesOf, addMinutes, toDate } from "../utils/dates.js";

describe("dates", () => {
  it("pads to two digits", () => {
    expect(pad2(3)).toBe("03");
    expect(pad2(12)).toBe("12");
  });

  it("formats and parses local ISO dates", () => {
    expect(isoDate(new Date(2026, 9, 9, 23, 59))).toBe("2026-10-09");
    expect(isoDate(parseIsoDate("2026-02-28"))).toBe("2026-02-28");
    expect(parseIsoDate("2026-13-01")).toBeNull();
    expect(parseIsoDate("nope")).toBeNull();
  });

  it("adds days across month and year boundaries", () => {
    expect(isoDate(addDays(new Date(2026, 9, 31), 1))).toBe("2026-11-01");
    expect(isoDate(addDays(new Date(2026, 11, 31), 1))).toBe("2027-01-01");
    expect(isoDate(addDays(new Date(2026, 9, 1), -3))).toBe("2026-09-28");
  });

  it("formats and parses HH:MM", () => {
    expect(hhmm(new Date(2026, 0, 1, 9, 5))).toBe("09:05");
    expect(minutesOf("15:30")).toBe(930);
    expect(minutesOf("9:30")).toBeNull();
  });

  it("adds minutes rolling over midnight", () => {
    expect(addMinutes("2026-10-09", "23:30", 60)).toEqual({ date: "2026-10-10", time: "00:30" });
    expect(addMinutes("2026-10-09", "15:00", 15)).toEqual({ date: "2026-10-09", time: "15:15" });
  });

  it("builds a local Date from date and time", () => {
    expect(toDate("2026-10-09", "15:30").getTime()).toBe(new Date(2026, 9, 9, 15, 30).getTime());
    expect(toDate("2026-10-09", null).getTime()).toBe(new Date(2026, 9, 9).getTime());
  });
});
