local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local FetchPool = modules.load("lib/fetchpool.luau")

local function job(id, token)
	return { id = id, token = token or 1, url = "https://" .. id .. ".com" }
end
local function ids(list)
	local out = {}
	for i, j in ipairs(list) do
		out[i] = j.id
	end
	return out
end

describe("fetch pool", function()
	it("starts up to the limit and queues the rest", function()
		local p = FetchPool.createPool(3)
		local started = {}
		for _, id in ipairs({ "a", "b", "c", "d" }) do
			local r = FetchPool.request(p, job(id))
			p = r.pool
			for _, j in ipairs(r.start) do
				table.insert(started, j)
			end
		end
		assert.same(ids(started), { "a", "b", "c" })
		assert.same(ids(p.queue), { "d" })
	end)

	it("starts the next queued job when one finishes", function()
		local p = FetchPool.createPool(1)
		p = FetchPool.request(p, job("a")).pool
		p = FetchPool.request(p, job("b")).pool
		local r = FetchPool.finish(p, "a")
		assert.same(ids(r.start), { "b" })
		assert.same(ids(r.pool.running), { "b" })
	end)

	it("replaces a queued job for the same id with the newer token", function()
		local p = FetchPool.createPool(1)
		p = FetchPool.request(p, job("a")).pool
		p = FetchPool.request(p, job("b", 1)).pool
		p = FetchPool.request(p, job("b", 2)).pool
		assert.same(p.queue, { job("b", 2) })
	end)

	it("queues a refetch of a running id until that run finishes", function()
		local p = FetchPool.createPool(3)
		p = FetchPool.request(p, job("a", 1)).pool
		local r = FetchPool.request(p, job("a", 2))
		assert.same(r.start, {})
		assert.same(FetchPool.finish(r.pool, "a").start, { job("a", 2) })
	end)

	it("skips a queued job whose id is running and starts the one after it", function()
		local p = FetchPool.createPool(2)
		p = FetchPool.request(p, job("a", 1)).pool
		p = FetchPool.request(p, job("a", 2)).pool
		local r = FetchPool.request(p, job("b"))
		assert.same(ids(r.start), { "b" })
		assert.same(r.pool.queue, { job("a", 2) })
	end)

	it("ignores finish for an id that is not running and can drop the queue", function()
		local p = FetchPool.createPool(1)
		p = FetchPool.request(p, job("a")).pool
		p = FetchPool.request(p, job("b")).pool
		local r = FetchPool.finish(p, "zz")
		assert.same(r.start, {})
		assert.equal(r.pool, p)
		p = FetchPool.clearQueue(p)
		assert.same(p.queue, {})
		assert.same(ids(p.running), { "a" })
	end)

	it("drops the queue and reports the dropped jobs", function()
		local p = FetchPool.createPool(1)
		p = FetchPool.request(p, job("a")).pool
		p = FetchPool.request(p, job("b")).pool
		local r = FetchPool.dropQueue(p)
		assert.same(r.dropped, { job("b") })
		assert.same(r.pool.queue, {})
		assert.same(ids(r.pool.running), { "a" })
	end)
end)
