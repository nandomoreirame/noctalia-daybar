import { describe, it, expect } from "vitest";
import { VERSION, createEmpty, parse, serialize, makeId } from "../utils/store.js";

describe("store", () => {
  it("creates an empty v2 store", () => {
    expect(VERSION).toBe(2);
    expect(createEmpty()).toEqual({ version: 2, tasks: [], eventChecks: {}, reminders: [], bookmarks: [], notes: [], focusLog: {}, ui: { lastTab: "" } });
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
    expect(data.bookmarks).toEqual([]);
    expect(data.links).toBeUndefined();
    expect(data.focusLog).toEqual({});
  });

  it("drops v1 links and notes without migrating them", () => {
    const { data } = parse(JSON.stringify({ version: 1, links: [{ id: "l", url: "https://x.com" }], notes: [{ id: "n", text: "x" }], tasks: [{ id: "t", title: "keep" }] }));
    expect(data.bookmarks).toEqual([]);
    expect(data.notes).toEqual([]);
    expect(data.tasks.map((t) => t.id)).toEqual(["t"]);
    expect(data.links).toBeUndefined();
  });

  it("keeps v2 bookmarks and notes", () => {
    const b = { id: "b", url: "https://x.com", title: "x.com", description: "", image: "", imageUrl: "", status: "ok", token: 1, createdAt: "t", savedAt: "t" };
    const n = { id: "n", text: "# hi", createdAt: "t", updatedAt: "t" };
    const { data } = parse(JSON.stringify({ version: 2, bookmarks: [b], notes: [n] }));
    expect(data.bookmarks).toEqual([b]);
    expect(data.notes).toEqual([n]);
  });

  it("resets a pending bookmark fetch left over from a previous run", () => {
    const b = { id: "b", url: "https://x.com", title: "x.com", description: "", image: "", imageUrl: "", status: "pending", token: 3, createdAt: "t", savedAt: "t" };
    expect(parse(JSON.stringify({ version: 2, bookmarks: [b] })).data.bookmarks[0].status).toBe("failed");
  });

  it("keeps valid focus log counts and drops junk entries", () => {
    const { data } = parse(JSON.stringify({ focusLog: { "2026-10-09": 3, "2026-10-08": "x", "oops": 2, "2026-10-07": -1 } }));
    expect(data.focusLog).toEqual({ "2026-10-09": 3 });
  });

  it("keeps a known last tab and drops anything else", () => {
    expect(parse(JSON.stringify({ ui: { lastTab: "focus" } })).data.ui).toEqual({ lastTab: "focus" });
    expect(parse(JSON.stringify({ ui: { lastTab: "nope" } })).data.ui).toEqual({ lastTab: "" });
    expect(parse(JSON.stringify({ ui: "x" })).data.ui).toEqual({ lastTab: "" });
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

  it("drops bookmarks and notes without an id", () => {
    const { data } = parse(JSON.stringify({ version: 2, bookmarks: [null, { url: "x" }, { id: "b", url: "https://x.com", status: "ok" }], notes: [null, { text: "x" }, { id: "n", text: "t" }] }));
    expect(data.bookmarks.map((b) => b.id)).toEqual(["b"]);
    expect(data.notes.map((n) => n.id)).toEqual(["n"]);
  });
});

