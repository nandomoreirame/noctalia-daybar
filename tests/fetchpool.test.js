import { describe, it, expect } from "vitest";
import { createPool, request, finish, clearQueue, dropQueue } from "../utils/fetchpool.js";

const job = (id, token = 1) => ({ id, token, url: "https://" + id + ".com" });

describe("fetch pool", () => {
  it("starts up to the limit and queues the rest", () => {
    let p = createPool(3);
    const started = [];
    for (const id of ["a", "b", "c", "d"]) {
      const r = request(p, job(id));
      p = r.pool;
      started.push(...r.start);
    }
    expect(started.map((j) => j.id)).toEqual(["a", "b", "c"]);
    expect(p.queue.map((j) => j.id)).toEqual(["d"]);
  });

  it("starts the next queued job when one finishes", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b")).pool;
    const r = finish(p, "a");
    expect(r.start.map((j) => j.id)).toEqual(["b"]);
    expect(r.pool.running.map((j) => j.id)).toEqual(["b"]);
  });

  it("replaces a queued job for the same id with the newer token", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b", 1)).pool;
    p = request(p, job("b", 2)).pool;
    expect(p.queue).toEqual([job("b", 2)]);
  });

  it("queues a refetch of a running id until that run finishes", () => {
    let p = createPool(3);
    p = request(p, job("a", 1)).pool;
    const r = request(p, job("a", 2));
    expect(r.start).toEqual([]);
    expect(finish(r.pool, "a").start).toEqual([job("a", 2)]);
  });

  it("ignores finish for an id that is not running and can drop the queue", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b")).pool;
    expect(finish(p, "zz").start).toEqual([]);
    p = clearQueue(p);
    expect(p.queue).toEqual([]);
    expect(p.running.map((j) => j.id)).toEqual(["a"]);
  });

  it("drops the queue and reports the dropped jobs", () => {
    let p = createPool(1);
    p = request(p, job("a")).pool;
    p = request(p, job("b")).pool;
    const r = dropQueue(p);
    expect(r.dropped).toEqual([job("b")]);
    expect(r.pool.queue).toEqual([]);
    expect(r.pool.running.map((j) => j.id)).toEqual(["a"]);
  });
});
