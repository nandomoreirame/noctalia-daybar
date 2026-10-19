--!strict
-- Entry loader for plugin unit tests.
--
-- Luau CLI has no `io`, so entry SOURCE cannot be read from disk at runtime.
-- `./run-tests` pre-generates `tests/.generated/<sanitized>.src.luau` modules
-- that `return [==[...source...]==]`. This loader require()s that string,
-- compiles it with loadstring, and setfenv()s the mock host env.
--
-- Shape of the returned table:
--   loaded.env   -- mock env (noctalia, barWidget, ...); lifecycle fns live here
--   loaded.call(name, ...)  -- invoke env[name](...); errors if missing
--
-- The env uses __index -> _G so entry scripts get the safe Luau stdlib
-- (string, table, math, os.clock/time/date, pcall, error, type, typeof, ...).

local mock = require("./noctalia_mock")
local modules = require("./modules")

local Entry = {}

export type LoadedEntry = {
	env: any,
	call: (string, ...any) -> any,
}

function Entry.load(entryPath: string, opts: any?): LoadedEntry
	local source = modules.text(entryPath)

	local env = mock.new(opts)
	env.require = modules.requirer(entryPath)
	-- Stdlib fallback: entry scripts use string/table/math/pcall/... normally.
	setmetatable(env, {
		__index = _G,
	})

	local chunk, compileErr = loadstring(source :: string, "@" .. entryPath)
	if chunk == nil then
		error(
			string.format("entry.load: compile error in %s: %s", entryPath, tostring(compileErr)),
			2
		)
	end
	setfenv(chunk, env)
	chunk()

	local loaded: LoadedEntry = {
		env = env,
		call = function(name: string, ...: any): any
			local fn = env[name]
			if typeof(fn) ~= "function" then
				error(string.format("entry: no lifecycle function %q", tostring(name)), 2)
			end
			return fn(...)
		end,
	}
	return loaded
end

return Entry
