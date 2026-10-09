import { describe, it, expect } from "vitest";
import { createEmpty } from "../utils/store.js";
import { addTask, toggleTask, deleteTask, addPomodoro, eventKey, toggleEventCheck } from "../utils/tasks.js";

const T0 = "2026-10-09T15:00:00.000Z";

describe("tasks", () => {
  it("adds a local task without mutating the input", () => {
    const empty = createEmpty();
    const data = addTask(empty, { title: "comprar pão", date: "2026-10-10", time: "09:00" }, "t1", T0);
    expect(empty.tasks).toEqual([]);
    expect(data.tasks).toEqual([{
      id: "t1", title: "comprar pão", date: "2026-10-10", time: "09:00", done: false, doneAt: null,
      pomodoros: 0, source: "local", externalId: null, createdAt: T0
    }]);
  });

  it("toggles done and doneAt", () => {
    let data = addTask(createEmpty(), { title: "x", date: "2026-10-09" }, "t1", T0);
    data = toggleTask(data, "t1", "2026-10-09T16:00:00.000Z");
    expect(data.tasks[0].done).toBe(true);
    expect(data.tasks[0].doneAt).toBe("2026-10-09T16:00:00.000Z");
    data = toggleTask(data, "t1", "2026-10-09T17:00:00.000Z");
    expect(data.tasks[0]).toMatchObject({ done: false, doneAt: null });
  });

  it("deletes a task and counts pomodoros", () => {
    let data = addTask(createEmpty(), { title: "a", date: "2026-10-09" }, "a", T0);
    data = addTask(data, { title: "b", date: "2026-10-09" }, "b", T0);
    data = addPomodoro(addPomodoro(data, "b"), "b");
    expect(data.tasks.find((t) => t.id === "b").pomodoros).toBe(2);
    expect(deleteTask(data, "a").tasks.map((t) => t.id)).toEqual(["b"]);
  });

  it("toggles event checks per occurrence", () => {
    let data = toggleEventCheck(createEmpty(), "uid-1", "2026-10-09");
    expect(data.eventChecks).toEqual({ [eventKey("uid-1", "2026-10-09")]: true });
    data = toggleEventCheck(data, "uid-1", "2026-10-16");
    data = toggleEventCheck(data, "uid-1", "2026-10-09");
    expect(data.eventChecks).toEqual({ "uid-1|2026-10-16": true });
  });
});
