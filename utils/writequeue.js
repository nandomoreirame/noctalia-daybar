.pragma library

// Serial queue for calendar writes plus a coalescing flag for the follow-up sync.
// Pure state transitions; Main.qml owns the processes and the callbacks.
// Each job carries a token so a duplicate or late completion signal settles nothing.

function createQueue() {
  return { pending: [], active: null, seq: 0 };
}

// Returns { queue, start }: `start` is the job to launch now, or null when busy.
function enqueue(q, payload) {
  const job = { token: q.seq + 1, payload: payload };
  if (q.active) return { queue: { pending: q.pending.concat([job]), active: q.active, seq: job.token }, start: null };
  return { queue: { pending: q.pending, active: job, seq: job.token }, start: job };
}

// Returns { queue, settled, start }. A token that is not the active job is ignored.
function settle(q, token) {
  if (!q.active || q.active.token !== token) return { queue: q, settled: null, start: null };
  const next = q.pending.length > 0 ? q.pending[0] : null;
  return { queue: { pending: q.pending.slice(1), active: next, seq: q.seq }, settled: q.active, start: next };
}

function createSync() {
  return { running: false, pending: false };
}

// Returns { state, start }. A request during a running sync is remembered once.
function requestSync(s) {
  if (s.running) return { state: { running: true, pending: true }, start: false };
  return { state: { running: true, pending: false }, start: true };
}

// Returns { state, start }: reruns once when a request arrived mid-sync.
function syncFinished(s) {
  if (s.pending) return { state: { running: true, pending: false }, start: true };
  return { state: { running: false, pending: false }, start: false };
}
