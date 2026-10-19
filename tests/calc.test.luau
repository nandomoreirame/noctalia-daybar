local assert = require("./support/assert")
local runner = require("./support/runner")
local modules = require("./support/modules")

local describe, it = runner.describe, runner.it
local Calc = modules.load("lib/calc.luau")

describe("calc.evaluate", function()
	local okCases = {
		{ "2+2", 4 },
		{ "2+3*4", 14 },
		{ "(2+3)*4", 20 },
		{ "2^3^2", 512 },
		{ "-2^2", -4 },
		{ "-2*3", -6 },
		{ "--2", 2 },
		{ "+5", 5 },
		{ "2,5*2", 5 },
		{ "1.234,5+0,5", 1235 },
		{ "10/4", 2.5 },
		{ "200*15%", 30 },
		{ "(50+50)%", 1 },
		{ " 7 - 10 ", -3 },
		{ "1.000*2", 2000 },
		{ "1.000.000", 1000000 },
		{ "0.125*8", 1 },
		{ "2.50*2", 5 },
	}
	for _, c in ipairs(okCases) do
		it(c[1] .. " = " .. tostring(c[2]), function()
			assert.same(Calc.evaluate(c[1]), { ok = true, value = c[2] })
		end)
	end

	local errCases = {
		{ "", "empty" },
		{ "2/0", "division-by-zero" },
		{ "2+", "syntax" },
		{ "(2", "syntax" },
		{ "2)", "syntax" },
		{ "()", "syntax" },
		{ "2 3", "syntax" },
		{ "1.2.3", "syntax" },
		{ "*2", "syntax" },
		{ "constructor", "syntax" },
		{ "process.exit()", "syntax" },
		{ "9^999", "overflow" },
	}
	for _, c in ipairs(errCases) do
		it(c[1] .. " -> " .. c[2], function()
			assert.same(Calc.evaluate(c[1]), { ok = false, error = c[2] })
		end)
	end

	it("evaluates percent as postfix percent, never modulo", function()
		assert.equal(Calc.evaluate("200*15%").value, 30)
	end)

	it("rejects identifiers instead of evaluating them", function()
		assert.equal(Calc.evaluate("os.exit()").ok, false)
	end)
end)

describe("calc.formatNumber", function()
	it("uses comma decimals and hides float noise", function()
		assert.equal(Calc.formatNumber(0.1 + 0.2), "0,3")
		assert.equal(Calc.formatNumber(2.5), "2,5")
		assert.equal(Calc.formatNumber(4), "4")
		assert.equal(Calc.formatNumber(-1.5), "-1,5")
	end)

	it("rounds to significant digits so large results carry no float noise", function()
		assert.equal(Calc.formatNumber(1500000 * 1.1), "1650000")
		assert.equal(Calc.formatNumber(12345678.9 * 1.1), "13580246,79")
		assert.equal(Calc.formatNumber(1 / 3), "0,333333333333")
	end)
end)
