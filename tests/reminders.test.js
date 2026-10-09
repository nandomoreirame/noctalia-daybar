import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addReminder, dueReminders, markFired } from "../utils/reminders.js";

describe("reminders", () => {
  let data = createEmpty();
  data = addReminder(data, { title: "early", date: "2026-10-09", time: "14:00" }, "r1");
  data = addReminder(data, { title: "now", date: "2026-10-09", time: "14:55" }, "r2");
  data = addReminder(data, { title: "later", date: "2026-10-09", time: "16:00" }, "r3");

  it("splits due reminders into fire and expire", () => {
    const due = dueReminders(data, new Date(2026, 9, 9, 15, 0));
    expect(due.fire.map((r) => r.id)).toEqual(["r2"]);
    expect(due.expire.map((r) => r.id)).toEqual(["r1"]);
  });

  it("does not return fired reminders again", () => {
    const fired = markFired(data, ["r1", "r2"]);
    expect(dueReminders(fired, new Date(2026, 9, 9, 15, 0))).toEqual({ fire: [], expire: [] });
    expect(fired.reminders.find((r) => r.id === "r3").fired).toBe(false);
  });
});
