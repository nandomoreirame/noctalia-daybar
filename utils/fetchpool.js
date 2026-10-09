.pragma library

// Bounded pool for preview fetches. Pure state; Main.qml owns the processes.
// job: { id, token, url }. At most one running job per id.

function createPool(limit) {
  return { limit: limit, queue: [], running: [] };
}

function drain(pool) {
  const start = [];
  let queue = pool.queue.slice();
  let running = pool.running.slice();
  let i = 0;
  while (running.length < pool.limit && i < queue.length) {
    const next = queue[i];
    if (running.some((j) => j.id === next.id)) {
      i++;
      continue;
    }
    queue.splice(i, 1);
    running.push(next);
    start.push(next);
  }
  return { pool: { limit: pool.limit, queue: queue, running: running }, start: start };
}

function request(pool, job) {
  const queue = pool.queue.filter((j) => j.id !== job.id).concat([job]);
  return drain({ limit: pool.limit, queue: queue, running: pool.running });
}

function finish(pool, id) {
  if (!pool.running.some((j) => j.id === id)) return { pool: pool, start: [] };
  return drain({ limit: pool.limit, queue: pool.queue, running: pool.running.filter((j) => j.id !== id) });
}

function clearQueue(pool) {
  return { limit: pool.limit, queue: [], running: pool.running };
}
