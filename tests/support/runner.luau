--!strict
-- Minimal describe/it runner. Counters live in this module (require-cache shared
-- across files in one `luau` invocation). Call finish() from finish.luau.

local Runner = {}

local passed = 0
local failed = 0

function Runner.describe(name: string, fn: () -> ())
	print(name)
	fn()
end

function Runner.it(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. ": " .. tostring(err))
	end
end

function Runner.stats(): { passed: number, failed: number }
	return { passed = passed, failed = failed }
end

function Runner.finish()
	print(string.format("%d passed, %d failed", passed, failed))
	if failed > 0 then
		error(string.format("%d test(s) failed", failed), 0)
	end
end

return Runner
