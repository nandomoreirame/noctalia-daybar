-- Loads plugin modules for tests the way the Noctalia host does.
--
-- The host resolves require("./x.luau") relative to the requiring file and needs
-- the .luau suffix; the Luau CLI rejects that suffix. run-tests wraps every
-- source (lib/**/*.luau, views/*.luau, root *.luau, fixtures, JSON, plugin.toml)
-- into tests/.generated/<sanitized>.src.luau returning the text, and this module
-- compiles it with a host-style require injected into the chunk env.

local Modules = {}

local cache: { [string]: any } = {}

-- "lib/pace.luau" -> "../.generated/lib_pace.src"; "translations/pt-BR.json" -> "../.generated/translations_pt-BR_json.src"
function Modules.generated(path: string): string
	local base = string.gsub(path, "^%./", "")
	base = string.gsub(base, "%.luau$", "")
	base = string.gsub(base, "[/\\.]", "_")
	return "../.generated/" .. base .. ".src"
end

local function dirOf(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function join(dir: string, rel: string): string
	local parts = {}
	for part in string.gmatch(dir, "[^/]+") do
		table.insert(parts, part)
	end
	for part in string.gmatch(rel, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

function Modules.text(path: string): string
	local ok, source = pcall(function()
		return require(Modules.generated(path))
	end)
	if not ok or typeof(source) ~= "string" then
		error(string.format("modules: no source for %s (run ./run-tests): %s", path, tostring(source)), 2)
	end
	return source
end

function Modules.requirer(fromPath: string): (string) -> any
	return function(rel: string): any
		if typeof(rel) ~= "string" or not string.match(rel, "^%.%.?/") or not string.match(rel, "%.luau$") then
			error("require path must be relative and end in .luau", 2)
		end
		return Modules.load(join(dirOf(fromPath), rel))
	end
end

function Modules.load(path: string): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local chunk, err = loadstring(Modules.text(path), "@" .. path)
	if chunk == nil then
		error(string.format("modules: compile error in %s: %s", path, tostring(err)), 2)
	end
	setfenv(chunk, setmetatable({ require = Modules.requirer(path) }, { __index = _G }))
	local value = chunk()
	if value == nil then
		error(string.format("modules: %s returned nil", path), 2)
	end
	cache[path] = value
	return value
end

return Modules
