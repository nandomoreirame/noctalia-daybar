local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Tbl = modules.load("lib/tbl.luau")

describe("tbl", function()
	it("merges b over a into a new table without touching a", function()
		local a = { x = 1, y = 2 }
		local b = { y = 9, z = 3 }
		local out = Tbl.merge(a, b)
		assert.same(out, { x = 1, y = 9, z = 3 })
		assert.same(a, { x = 1, y = 2 })
		assert.equal(out == a, false)
	end)

	it("copies a list into a new sequence", function()
		local src = { "a", "b", "c" }
		local out = Tbl.copyList(src)
		assert.same(out, { "a", "b", "c" })
		assert.equal(out == src, false)
		src[1] = "z"
		assert.equal(out[1], "a")
	end)

	it("maps, filters, finds, indexes and contains over a sequence", function()
		local nums = { 1, 2, 3, 4 }
		assert.same(Tbl.map(nums, function(n)
			return n * 2
		end), { 2, 4, 6, 8 })
		assert.same(Tbl.filter(nums, function(n)
			return n % 2 == 0
		end), { 2, 4 })
		assert.equal(Tbl.find(nums, function(n)
			return n > 2
		end), 3)
		assert.equal(Tbl.find(nums, function(n)
			return n > 9
		end), nil)
		assert.equal(Tbl.indexOf(nums, 3), 3)
		assert.equal(Tbl.indexOf(nums, 9), nil)
		assert.equal(Tbl.contains(nums, 4), true)
		assert.equal(Tbl.contains(nums, 9), false)
	end)

	it("detects arrays versus keyed tables", function()
		assert.equal(Tbl.isArray({}), true)
		assert.equal(Tbl.isArray({ 1, 2, 3 }), true)
		assert.equal(Tbl.isArray({ a = 1 }), false)
		assert.equal(Tbl.isArray({ 1, a = 2 }), false)
	end)
end)
