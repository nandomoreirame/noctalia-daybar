local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it

local Ring = modules.load("lib/ring.luau")

describe("ring", function()
	it("has one step per percent", function()
		assert.equal(Ring.STEPS, 100)
		assert.equal(Ring.step(0), 0)
		assert.equal(Ring.step(0.504), 50)
		assert.equal(Ring.step(1), 100)
		assert.equal(Ring.step(-1), 0)
		assert.equal(Ring.step(7), 100)
	end)

	it("draws the track and an arc whose dash covers the progress", function()
		local svg = Ring.svg(25, "#ffb38a")
		assert.equal(string.find(svg, "<svg", 1, true) ~= nil, true)
		assert.equal(string.find(svg, 'stroke="#ffb38a"', 1, true) ~= nil, true)
		-- Track at low opacity, arc starting at 12 o'clock.
		assert.equal(string.find(svg, 'stroke-opacity="0.2"', 1, true) ~= nil, true)
		assert.equal(string.find(svg, "rotate(-90", 1, true) ~= nil, true)
		local dash = string.match(svg, 'stroke%-dasharray="([%d%.]+) ')
		local circumference = 2 * math.pi * Ring.RADIUS
		assert.equal(math.abs(tonumber(dash) - circumference * 0.25) < 0.01, true)
	end)

	it("draws no arc at 0 percent", function()
		local svg = Ring.svg(0, "#ffb38a")
		assert.equal(string.find(svg, "stroke-dasharray", 1, true), nil)
	end)

	it("names the color directory without the hash and rejects bad colors", function()
		assert.equal(Ring.dirName("#FFB38A"), "ffb38a")
		assert.equal(Ring.dirName("primary"), nil)
		assert.equal(Ring.dirName(nil), nil)
	end)
end)
