import { describe, it, expect } from "vitest";
import { titleOf, snippetOf, isBlank, add, update, remove, sorted, search } from "../utils/notes.js";

const T0 = "2026-10-09T15:00:00.000Z";
const T1 = "2026-10-09T16:00:00.000Z";

describe("notes derived fields", () => {
  it.each([
    ["# Shopping list\n- milk", "Shopping list"],
    ["\n\n  **Bold** and _it_ `code`  \nmore", "Bold and it code"],
    ["- [x] done item", "done item"],
    ["> quoted [link](https://x.com) ![img](a.png)", "quoted link img"],
    ["1. first", "first"],
    ["   \n  ", ""]
  ])("titleOf(%j) = %j", (text, title) => {
    expect(titleOf(text)).toBe(title);
  });

  it("snippets the text after the title line as one plain line, capped at 140", () => {
    expect(snippetOf("# Title\n\nFirst **line**\n- second")).toBe("First line second");
    expect(snippetOf("only title")).toBe("");
    expect(snippetOf("t\n" + "word ".repeat(100)).length).toBe(140);
  });

  it("detects blank notes", () => {
    expect(isBlank("  \n\t ")).toBe(true);
    expect(isBlank("x")).toBe(false);
  });
});

describe("notes operations", () => {
  it("adds with created and updated timestamps", () => {
    const data = add({ notes: [] }, "  hello  ", "n1", T0);
    expect(data.notes).toEqual([{ id: "n1", text: "hello", createdAt: T0, updatedAt: T0 }]);
  });

  it("updates text and timestamp, returns the same object when unchanged", () => {
    const data = add({ notes: [] }, "a", "n1", T0);
    const next = update(data, "n1", "b", T1);
    expect(next.notes[0]).toEqual({ id: "n1", text: "b", createdAt: T0, updatedAt: T1 });
    expect(update(next, "n1", "b", "2026-10-09T17:00:00.000Z")).toBe(next);
    expect(update(next, "zz", "c", T1)).toBe(next);
  });

  it("keeps the text verbatim on update (no trim) so the editor cursor does not jump", () => {
    const data = add({ notes: [] }, "a", "n1", T0);
    expect(update(data, "n1", "line \n", T1).notes[0].text).toBe("line \n");
  });

  it("removes, sorts by last edit and searches without accents", () => {
    let data = add({ notes: [] }, "Reunião", "a", T0);
    data = add(data, "Café", "b", T0);
    data = update(data, "a", "Reunião de equipe", T1);
    expect(sorted(data.notes).map((n) => n.id)).toEqual(["a", "b"]);
    expect(search(data.notes, "reuniao").map((n) => n.id)).toEqual(["a"]);
    expect(remove(data, "a").notes.map((n) => n.id)).toEqual(["b"]);
  });
});
