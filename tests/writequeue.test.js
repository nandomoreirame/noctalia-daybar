import { describe, it, expect } from "vitest";
import { createQueue, enqueue, settle, createSync, requestSync, syncFinished } from "../utils/writequeue.js";

describe("write queue", () => {
  it("starts the first job right away and queues the rest", () => {
    let q = createQueue();
    const a = enqueue(q, "A");
    expect(a.start).toEqual({ token: 1, payload: "A" });
    const b = enqueue(a.queue, "B");
    expect(b.start).toBeNull();
    q = b.queue;
    const s = settle(q, 1);
    expect(s.settled).toEqual({ token: 1, payload: "A" });
    expect(s.start).toEqual({ token: 2, payload: "B" });
    const done = settle(s.queue, 2);
    expect(done.start).toBeNull();
    expect(done.queue.active).toBeNull();
  });

  it("settles a job only once, so a late duplicate signal cannot skip the next job", () => {
    const a = enqueue(createQueue(), "A");
    const b = enqueue(a.queue, "B");
    const first = settle(b.queue, 1);
    const again = settle(first.queue, 1);
    expect(again.settled).toBeNull();
    expect(again.start).toBeNull();
    expect(again.queue).toEqual(first.queue);
  });
});

describe("sync coalescing", () => {
  it("starts a sync when idle", () => {
    expect(requestSync(createSync())).toEqual({ state: { running: true, pending: false }, start: true });
  });

  it("remembers a request made while a sync runs and reruns once afterwards", () => {
    let r = requestSync(createSync());
    r = requestSync(r.state);
    expect(r).toEqual({ state: { running: true, pending: true }, start: false });
    r = requestSync(r.state);
    expect(r.state.pending).toBe(true);
    const f = syncFinished(r.state);
    expect(f).toEqual({ state: { running: true, pending: false }, start: true });
    expect(syncFinished(f.state)).toEqual({ state: { running: false, pending: false }, start: false });
  });
});
