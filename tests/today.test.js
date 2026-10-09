import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addTask, toggleTask, toggleEventCheck } from "../utils/tasks.js";
import { buildToday } from "../utils/today.js";

const NOW = new Date(2026, 9, 9, 15, 0);
const at = (h, mi = 0, d = 9) => new Date(2026, 9, d, h, mi).getTime() / 1000;
const T0 = "2026-10-09T10:00:00.000Z";

describe("buildToday", () => {
  let data = createEmpty();
  data = addTask(data, { title: "sem hora", date: "2026-10-09" }, "t-untimed", "2026-10-09T09:00:00.000Z");
  data = addTask(data, { title: "banco", date: "2026-10-09", time: "16:00" }, "t-16", T0);
  data = addTask(data, { title: "atrasada", date: "2026-10-07", time: "09:00" }, "t-late", T0);
  data = addTask(data, { title: "atrasada feita", date: "2026-10-07" }, "t-late-done", T0);
  data = toggleTask(data, "t-late-done", T0);
  data = addTask(data, { title: "amanhã", date: "2026-10-10" }, "t-tomorrow", T0);
  data = toggleEventCheck(data, "e-am", "2026-10-09");

  const events = [
    { uid: "e-pm", summary: "reunião", start: at(14), end: at(15), calendar: "Eventos" },
    { uid: "e-am", summary: "café", start: at(8), end: at(9), calendar: "Eventos" },
    { uid: "e-next", summary: "amanhã", start: at(9, 0, 10), end: at(10, 0, 10), calendar: "Eventos" }
  ];

  it("orders events by time, then timed tasks, then untimed tasks", () => {
    const items = buildToday(events, data, NOW);
    expect(items.map((i) => i.id)).toEqual(["e-am|2026-10-09", "e-pm|2026-10-09", "t-late", "t-16", "t-untimed"]);
  });

  it("flags overdue tasks and checked events", () => {
    const items = buildToday(events, data, NOW);
    expect(items.find((i) => i.id === "t-late").overdue).toBe(true);
    expect(items.find((i) => i.id === "t-16").overdue).toBe(false);
    expect(items.find((i) => i.uid === "e-am").done).toBe(true);
    expect(items.find((i) => i.uid === "e-pm").done).toBe(false);
  });

  it("works with no calendar events", () => {
    expect(buildToday(null, createEmpty(), NOW)).toEqual([]);
  });

  it("carries the calendar name on events and an empty one on tasks", () => {
    const items = buildToday(events, data, NOW);
    expect(items.filter((i) => i.kind === "event").map((i) => i.calendar)).toEqual(["Eventos", "Eventos"]);
    expect(items.filter((i) => i.kind === "task").every((i) => i.calendar === "")).toBe(true);
  });
});
