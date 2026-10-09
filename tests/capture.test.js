import { describe, it, expect } from "vitest";
import * as Task from "../utils/capture/task.js";
import * as Event from "../utils/capture/event.js";
import * as Reminder from "../utils/capture/reminder.js";
import * as Note from "../utils/capture/note.js";
import * as Link from "../utils/capture/link.js";
import * as Calculation from "../utils/capture/calculation.js";

const NOW = new Date(2026, 9, 9, 15, 0);

describe("capture handlers", () => {
  it("task: defaults to today and keeps the parsed time", () => {
    expect(Task.build("comprar pão", NOW)).toEqual({ ok: true, type: "task", action: "addTask", payload: { title: "comprar pão", date: "2026-10-09", time: null } });
    expect(Task.build("comprar pão amanhã 9h", NOW).payload).toEqual({ title: "comprar pão", date: "2026-10-10", time: "09:00" });
    expect(Task.build("amanhã", NOW)).toEqual({ ok: false, type: "task", error: "empty-title" });
  });

  it("event: needs date and time, defaults to 1h", () => {
    expect(Event.build("reunião sexta 15h", NOW).payload).toEqual({ title: "reunião", date: "2026-10-16", start: "15:00", endDate: "2026-10-16", endTime: "16:00", alarm: false });
    expect(Event.build("reunião sexta 15h-15h30", NOW).payload.endTime).toBe("15:30");
    expect(Event.build("reunião sexta", NOW)).toEqual({ ok: false, type: "event", error: "needs-date-time" });
  });

  it("reminder: needs a time, lasts 15 minutes with alarm", () => {
    expect(Reminder.build("pagar boleto amanhã 10h", NOW)).toEqual({
      ok: true, type: "reminder", action: "createReminder",
      payload: { title: "pagar boleto", date: "2026-10-10", start: "10:00", endDate: "2026-10-10", endTime: "10:15", alarm: true }
    });
    expect(Reminder.build("pagar boleto amanhã", NOW)).toEqual({ ok: false, type: "reminder", error: "needs-time" });
  });

  it("note and link", () => {
    expect(Note.build("  ideia: app  ")).toEqual({ ok: true, type: "note", action: "addNote", payload: { text: "ideia: app" } });
    expect(Note.build("   ").ok).toBe(false);
    expect(Link.build("https://a.dev").payload).toEqual({ url: "https://a.dev" });
    expect(Link.build("a.dev")).toEqual({ ok: false, type: "link", error: "invalid-url" });
  });

  it("calculation", () => {
    expect(Calculation.build("2+2")).toEqual({ ok: true, type: "calculation", action: "copy", payload: { value: 4, display: "4" } });
    expect(Calculation.build("2/0")).toEqual({ ok: false, type: "calculation", error: "division-by-zero" });
  });
});
