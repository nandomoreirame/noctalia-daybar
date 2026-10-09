import { describe, it, expect } from "vitest";
import { VERSION, createEmpty, parse, serialize, makeId } from "../utils/store.js";

describe("store", () => {
  it("creates an empty versioned store", () => {
    expect(createEmpty()).toEqual({ version: VERSION, tasks: [], eventChecks: {}, reminders: [], links: [], notes: [] });
  });

  it("treats empty or missing text as a fresh store", () => {
    expect(parse("")).toEqual({ data: createEmpty(), corrupt: false });
    expect(parse(null)).toEqual({ data: createEmpty(), corrupt: false });
  });

  it("flags invalid JSON and non-object roots as corrupt", () => {
    expect(parse("{oops").corrupt).toBe(true);
    expect(parse("[1,2]").corrupt).toBe(true);
    expect(parse("42").corrupt).toBe(true);
  });

  it("migrates an unversioned file filling defaults", () => {
    const { data, corrupt } = parse(JSON.stringify({ tasks: [{ id: "a", title: "x" }, { title: "no id" }], eventChecks: [] }));
    expect(corrupt).toBe(false);
    expect(data.version).toBe(VERSION);
    expect(data.tasks).toEqual([{
      id: "a", title: "x", date: null, time: null, done: false, doneAt: null,
      pomodoros: 0, source: "local", externalId: null, createdAt: null
    }]);
    expect(data.eventChecks).toEqual({});
    expect(data.links).toEqual([]);
  });

  it("round-trips through serialize", () => {
    const data = createEmpty();
    data.notes.push({ id: "n1", text: "olá", createdAt: "2026-10-09T15:00:00.000Z" });
    expect(parse(serialize(data)).data).toEqual(data);
  });

  it("builds ids from time and randomness", () => {
    expect(makeId(1000, 0.5)).toBe("rs-" + (500000000).toString(36));
    expect(makeId(1000, 0.1)).not.toBe(makeId(1000, 0.2));
  });
});
