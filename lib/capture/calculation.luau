--!strict
-- Calculation capture ("=2+2"): Enter copies the result and keeps the overlay open.

local Calc = require("../calc.luau")

local Calculation = {}

Calculation.TYPE = "calculation"

function Calculation.build(expr: any): { [string]: any }
	local r = Calc.evaluate(expr)
	if not r.ok then
		return { ok = false, type = Calculation.TYPE, error = r.error }
	end
	return {
		ok = true,
		type = Calculation.TYPE,
		action = "copy",
		payload = { value = r.value, display = Calc.formatNumber(r.value) },
	}
end

return Calculation
