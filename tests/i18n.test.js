import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, existsSync } from "node:fs";

const root = new URL("../", import.meta.url);
const load = (lang) => JSON.parse(readFileSync(new URL(`i18n/${lang}.json`, root), "utf8"));
const en = load("en");
const pt = load("pt");

function flatten(obj, prefix = "") {
  return Object.entries(obj).flatMap(([k, v]) => (v && typeof v === "object" ? flatten(v, prefix + k + ".") : [prefix + k]));
}

function qmlFiles() {
  const top = readdirSync(root).filter((f) => f.endsWith(".qml"));
  const dir = new URL("components/", root);
  const nested = existsSync(dir) ? readdirSync(dir).filter((f) => f.endsWith(".qml")).map((f) => "components/" + f) : [];
  return top.concat(nested);
}

// Keys built at runtime ("capture.error." + code) are listed here explicitly.
const DYNAMIC = [
  ...["empty", "empty-title", "needs-date-time", "needs-time", "invalid-url", "syntax", "division-by-zero", "overflow", "calendar-not-configured", "khal-failed"].map((c) => "capture.error." + c),
  ...["task", "event", "reminder", "note", "link", "calculation"].map((t) => "capture.type." + t),
  ...["task", "event", "reminder", "note", "link"].map((t) => "capture.saved." + t),
  ...["today", "tomorrow"].map((d) => "when." + d),
  ...["calendar", "today", "focus", "inbox"].map((t) => "tabs." + t),
  ...["work", "short", "long"].map((m) => "focus.mode." + m),
  "focus.toast-work-done",
  "focus.toast-break-done",
  "focus.toast-goal-reached",
  "settings.work-duration",
  "settings.short-break",
  "settings.long-break",
  "settings.sessions",
  "settings.daily-goal"
];

describe("i18n", () => {
  it("has the same keys in en and pt", () => {
    expect(flatten(pt).sort()).toEqual(flatten(en).sort());
  });

  it("defines every key used by the QML files", () => {
    const keys = new Set(flatten(en));
    const used = new Set(DYNAMIC);
    for (const file of qmlFiles()) {
      const src = readFileSync(new URL(file, root), "utf8");
      for (const m of src.matchAll(/\btr\("([a-z0-9.-]+)"/g)) if (!m[1].endsWith(".")) used.add(m[1]);
    }
    const missing = [...used].filter((k) => !keys.has(k));
    expect(missing).toEqual([]);
  });
});
