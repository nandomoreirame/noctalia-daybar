--!strict
-- Bounded pool for preview fetches. Pure state; the service owns the processes.
-- job: { id, token, url }. At most one running job per id.

local Tbl = require("./tbl.luau")

local FetchPool = {}

export type Job = { id: string, token: number, url: string }
export type Pool = { limit: number, queue: { Job }, running: { Job } }

function FetchPool.createPool(limit: number): Pool
	return { limit = limit, queue = {}, running = {} }
end

local function isRunning(running: { Job }, id: string): boolean
	for _, j in ipairs(running) do
		if j.id == id then
			return true
		end
	end
	return false
end

local function drain(pool: Pool): { pool: Pool, start: { Job } }
	local start: { Job } = {}
	local queue = Tbl.copyList(pool.queue) :: { Job }
	local running = Tbl.copyList(pool.running) :: { Job }
	local i = 1
	while #running < pool.limit and i <= #queue do
		local nextJob = queue[i]
		if isRunning(running, nextJob.id) then
			i += 1
		else
			table.remove(queue, i)
			table.insert(running, nextJob)
			table.insert(start, nextJob)
		end
	end
	return { pool = { limit = pool.limit, queue = queue, running = running }, start = start }
end

function FetchPool.request(pool: Pool, job: Job): { pool: Pool, start: { Job } }
	local queue = Tbl.filter(pool.queue, function(j)
		return j.id ~= job.id
	end) :: { Job }
	table.insert(queue, job)
	return drain({ limit = pool.limit, queue = queue, running = pool.running })
end

function FetchPool.finish(pool: Pool, id: string): { pool: Pool, start: { Job } }
	if not isRunning(pool.running, id) then
		return { pool = pool, start = {} }
	end
	return drain({
		limit = pool.limit,
		queue = pool.queue,
		running = Tbl.filter(pool.running, function(j)
			return j.id ~= id
		end) :: { Job },
	})
end

function FetchPool.clearQueue(pool: Pool): Pool
	return { limit = pool.limit, queue = {}, running = pool.running }
end

-- Like clearQueue, but also returns the dropped jobs so callers can update them.
function FetchPool.dropQueue(pool: Pool): { pool: Pool, dropped: { Job } }
	return { pool = FetchPool.clearQueue(pool), dropped = Tbl.copyList(pool.queue) :: { Job } }
end

return FetchPool
