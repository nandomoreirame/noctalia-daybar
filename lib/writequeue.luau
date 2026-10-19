--!strict
-- Serial queue for calendar writes plus a coalescing flag for the follow-up sync.
-- Pure state transitions; the service owns the processes and the callbacks.
-- Each job carries a token so a duplicate or late completion signal settles nothing.

local Tbl = require("./tbl.luau")

local WriteQueue = {}

export type Job = { token: number, payload: any }
export type Queue = { pending: { Job }, active: Job?, seq: number }
export type Sync = { running: boolean, pending: boolean }

function WriteQueue.createQueue(): Queue
	return { pending = {}, active = nil, seq = 0 }
end

-- Returns { queue, start }: `start` is the job to launch now, or nil when busy.
function WriteQueue.enqueue(q: Queue, payload: any): { queue: Queue, start: Job? }
	local job: Job = { token = q.seq + 1, payload = payload }
	if q.active ~= nil then
		local pending = Tbl.copyList(q.pending) :: { Job }
		table.insert(pending, job)
		return { queue = { pending = pending, active = q.active, seq = job.token }, start = nil }
	end
	return { queue = { pending = q.pending, active = job, seq = job.token }, start = job }
end

-- Returns { queue, settled, start }. A token that is not the active job is ignored.
function WriteQueue.settle(q: Queue, token: number): { queue: Queue, settled: Job?, start: Job? }
	local active = q.active
	if active == nil or active.token ~= token then
		return { queue = q, settled = nil, start = nil }
	end
	local nextJob = q.pending[1]
	local rest = {}
	for i = 2, #q.pending do
		table.insert(rest, q.pending[i])
	end
	return { queue = { pending = rest, active = nextJob, seq = q.seq }, settled = active, start = nextJob }
end

function WriteQueue.createSync(): Sync
	return { running = false, pending = false }
end

-- Returns { state, start }. A request during a running sync is remembered once.
function WriteQueue.requestSync(s: Sync): { state: Sync, start: boolean }
	if s.running then
		return { state = { running = true, pending = true }, start = false }
	end
	return { state = { running = true, pending = false }, start = true }
end

-- Returns { state, start }: reruns once when a request arrived mid-sync.
function WriteQueue.syncFinished(s: Sync): { state: Sync, start: boolean }
	if s.pending then
		return { state = { running = true, pending = false }, start = true }
	end
	return { state = { running = false, pending = false }, start = false }
end

return WriteQueue
