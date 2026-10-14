import { describe, it, expect } from "vitest";
import { overlapsDay, isAllDay, timeOn, endTimeOn, timeRange, eventsOn, compareTime, nextEvent } from "../utils/events.js";

const at = (y, mo, d, h = 0, mi = 0) => new Date(y, mo, d, h, mi).getTime() / 1000;
const ev = (uid, start, end, summary = uid) => ({ uid, summary, start, end, calendar: "c" });

describe("events", () => {
  const meeting = ev("m", at(2026, 9, 9, 15), at(2026, 9, 9, 16));
  const allDay = ev("a", at(2026, 9, 9), at(2026, 9, 10));
  const trip = ev("t", at(2026, 9, 8, 10), at(2026, 9, 11, 10));
  const tomorrow = ev("x", at(2026, 9, 10, 9), at(2026, 9, 10, 10));
  const breakfast = ev("b", at(2026, 9, 9, 8), at(2026, 9, 9, 9));

  it("detects overlap with a day", () => {
    expect(overlapsDay(meeting, "2026-10-09")).toBe(true);
    expect(overlapsDay(allDay, "2026-10-10")).toBe(false);
    expect(overlapsDay(trip, "2026-10-10")).toBe(true);
    expect(overlapsDay(tomorrow, "2026-10-09")).toBe(false);
  });

  it("detects all-day events", () => {
    expect(isAllDay(allDay)).toBe(true);
    expect(isAllDay(meeting)).toBe(false);
  });

  it("gives a start time only on the starting day", () => {
    expect(timeOn(meeting, "2026-10-09")).toBe("15:00");
    expect(timeOn(trip, "2026-10-09")).toBeNull();
    expect(timeOn(allDay, "2026-10-09")).toBeNull();
  });

  it("gives an end time only when the event ends on that day", () => {
    expect(endTimeOn(meeting, "2026-10-09")).toBe("16:00");
    expect(endTimeOn(trip, "2026-10-09")).toBeNull();
    expect(endTimeOn(trip, "2026-10-11")).toBe("10:00");
    expect(endTimeOn(allDay, "2026-10-09")).toBeNull();
    expect(endTimeOn(ev("late", at(2026, 9, 9, 23), at(2026, 9, 10, 0)), "2026-10-09")).toBeNull();
  });

  it("joins start and end into a range, or keeps whatever exists", () => {
    expect(timeRange({ time: "16:00", endTime: "17:00" })).toBe("16:00–17:00");
    expect(timeRange({ time: "16:00", endTime: null })).toBe("16:00");
    expect(timeRange({ time: "16:00" })).toBe("16:00");
    expect(timeRange({ time: "16:00", endTime: "16:00" })).toBe("16:00");
    expect(timeRange({ time: null, endTime: "10:00" })).toBeNull();
  });

  it("carries the end time on the day's list", () => {
    const list = eventsOn([meeting, trip], "2026-10-09");
    expect(list.map((e) => [e.uid, e.time, e.endTime])).toEqual([["t", null, null], ["m", "15:00", "16:00"]]);
  });

  it("lists a day's events, untimed first then by time", () => {
    const list = eventsOn([meeting, tomorrow, breakfast, allDay, trip], "2026-10-09");
    expect(list.map((e) => [e.uid, e.time])).toEqual([["t", null], ["a", null], ["b", "08:00"], ["m", "15:00"]]);
  });

  it("orders null times first", () => {
    expect(compareTime(null, "09:00")).toBe(-1);
    expect(compareTime("10:00", "09:00")).toBe(1);
  });
});

describe("nextEvent", () => {
  const now = new Date(2026, 9, 9, 15, 0);

  it("picks the earliest timed event of today that has not ended, including one in progress", () => {
    const events = [
      ev("later", at(2026, 9, 10, 9), at(2026, 9, 10, 10), "Dentista"),
      ev("past", at(2026, 9, 9, 8), at(2026, 9, 9, 9), "Café"),
      ev("now", at(2026, 9, 9, 14, 30), at(2026, 9, 9, 15, 30), "Reunião"),
      ev("allday", at(2026, 9, 9), at(2026, 9, 10), "Feriado")
    ];
    expect(nextEvent(events, now)).toEqual({ uid: "now", summary: "Reunião", date: "2026-10-09", time: "14:30" });
  });

  it("ignores events on other days", () => {
    expect(nextEvent([ev("tomorrow", at(2026, 9, 10, 9), at(2026, 9, 10, 10), "Dentista")], now)).toBeNull();
  });

  it("returns null when nothing is ahead", () => {
    expect(nextEvent([ev("past", at(2026, 9, 9, 8), at(2026, 9, 9, 9))], now)).toBeNull();
    expect(nextEvent([], now)).toBeNull();
    expect(nextEvent(null, now)).toBeNull();
  });
});
