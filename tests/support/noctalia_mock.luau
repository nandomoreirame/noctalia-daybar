--!strict
-- Host mock for Noctalia v5 plugin entry scripts.
--
-- Luau CLI (0.742) findings that shaped this API:
--   * `_G` is READ-ONLY (`attempt to modify a readonly table`).
--   * There is no `io`, no `os.execute`, and `require` only accepts `./`, `../`, or `@` paths.
--   * `getfenv` / `setfenv` and `loadstring` DO work: inject host globals by giving a
--     chunk an env table, not by writing into `_G`.
--
-- Therefore this module exposes:
--   mock.new(opts) / mock.install(opts) -> env
--     env holds noctalia, barWidget, panel, ui, desktopWidget, shortcut, launcher
--   mock.calls(env, "barWidget.setText") -> { {arg...}, ... }
--
-- The entry loader should `setfenv`/`loadstring` with the returned env.
-- Unknown members error with "mock: <path> not implemented" so typos fail loudly.
-- getConfig is stricter than production: undeclared keys error (tests catch typos).

local Mock = {}

export type AsyncResult = {
	exitCode: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
	stdoutTruncated: boolean,
	stderrTruncated: boolean,
}

export type MockOpts = {
	config: { [string]: any }?,
	async: { [string]: AsyncResult }?,
	colors: { [string]: string }?,
	pluginDataDir: string?,
	fs: { [string]: string }?,
	now: number?,
	fileInfo: { [string]: any }?,
	vertical: boolean?,
	deferAsync: boolean?,
	commands: { [string]: boolean }?,
	clipboard: string?,
}

type CallLog = { [string]: { { any } } }

type EnvPrivate = {
	calls: CallLog,
	config: { [string]: any },
	async: { [string]: AsyncResult },
	colors: { [string]: string },
	fs: { [string]: any }, -- string content or true for directory
	pluginDataDir: string,
	state: { [string]: any },
	watchers: { [string]: { (any) -> () } },
	now: number,
	http: { any },
	fileInfo: { [string]: any },
	vertical: boolean,
	deferAsync: boolean,
	commands: { [string]: boolean },
	clipboard: string?,
	async_pending: { any },
	sound_pending: { any },
	download_pending: { any },
}

-- Side table: env identity -> private state (keeps host env clean for setfenv).
local privateByEnv: { [any]: EnvPrivate } = {}

local function record(priv: EnvPrivate, path: string, args: { any })
	local bucket = priv.calls[path]
	if bucket == nil then
		bucket = {}
		priv.calls[path] = bucket
	end
	table.insert(bucket, args)
end

local function recorder(priv: EnvPrivate, path: string, returnMode: string?): (...any) -> any
	return function(...: any): any
		local args = { ... }
		record(priv, path, args)
		if returnMode == "first" then
			return args[1]
		elseif returnMode == "true" then
			return true
		elseif returnMode == "false" then
			return false
		elseif returnMode == "nil" then
			return nil
		end
		return nil
	end
end

local function guardTable(path: string, members: { [string]: any }): any
	return setmetatable(members, {
		__index = function(_self, key: string): any
			error(string.format("mock: %s.%s not implemented", path, tostring(key)), 2)
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Minimal JSON codec (objects, arrays, strings with escapes, numbers, bool, null)
-- ---------------------------------------------------------------------------

local function jsonEncode(value: any, pretty: boolean?, indent: number?): (string?, string?)
	local ind = indent or 0
	local t = typeof(value)
	if value == nil then
		return "null", nil
	elseif t == "boolean" then
		return if value then "true" else "false", nil
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return nil, "cannot encode non-finite number"
		end
		return tostring(value), nil
	elseif t == "string" then
		local parts = { '"' }
		for i = 1, #value do
			local c = string.sub(value, i, i)
			local b = string.byte(c)
			if c == '"' then
				table.insert(parts, '\\"')
			elseif c == "\\" then
				table.insert(parts, "\\\\")
			elseif c == "\b" then
				table.insert(parts, "\\b")
			elseif c == "\f" then
				table.insert(parts, "\\f")
			elseif c == "\n" then
				table.insert(parts, "\\n")
			elseif c == "\r" then
				table.insert(parts, "\\r")
			elseif c == "\t" then
				table.insert(parts, "\\t")
			elseif b < 32 then
				table.insert(parts, string.format("\\u%04x", b))
			else
				table.insert(parts, c)
			end
		end
		table.insert(parts, '"')
		return table.concat(parts), nil
	elseif t == "table" then
		local tbl = value :: { [any]: any }
		-- Decide array vs object: array if keys are 1..n contiguous
		local maxIndex = 0
		local count = 0
		local isArray = true
		for k, _ in tbl do
			count += 1
			if typeof(k) ~= "number" or k ~= math.floor(k) or k < 1 then
				isArray = false
			else
				if k > maxIndex then
					maxIndex = k
				end
			end
		end
		if isArray and count > 0 and maxIndex ~= count then
			isArray = false -- sparse
		end
		if count == 0 then
			-- empty: encode as object {}
			isArray = false
		end

		local nl = if pretty then "\n" else ""
		local sp = if pretty then string.rep("  ", ind + 1) else ""
		local spClose = if pretty then string.rep("  ", ind) else ""

		if isArray then
			local items = {}
			for i = 1, maxIndex do
				local enc, err = jsonEncode(tbl[i], pretty, ind + 1)
				if err then
					return nil, err
				end
				table.insert(items, sp .. (enc :: string))
			end
			if pretty and #items > 0 then
				return "[" .. nl .. table.concat(items, "," .. nl) .. nl .. spClose .. "]", nil
			end
			return "[" .. table.concat(items, ",") .. "]", nil
		else
			local items = {}
			for k, v in tbl do
				if typeof(k) ~= "string" then
					return nil, "object keys must be strings"
				end
				if v ~= nil then
					local enc, err = jsonEncode(v, pretty, ind + 1)
					if err then
						return nil, err
					end
					local keyEnc = jsonEncode(k)
					table.insert(items, sp .. (keyEnc :: string) .. ":" .. (if pretty then " " else "") .. (enc :: string))
				end
			end
			if pretty and #items > 0 then
				return "{" .. nl .. table.concat(items, "," .. nl) .. nl .. spClose .. "}", nil
			end
			return "{" .. table.concat(items, ",") .. "}", nil
		end
	end
	return nil, "cannot encode type " .. t
end

local function jsonDecode(str: string): (any, string?)
	local i = 1
	local n = #str

	local function peek(): string
		return string.sub(str, i, i)
	end

	local function advance(): string
		local c = string.sub(str, i, i)
		i += 1
		return c
	end

	local function skipWs()
		while i <= n do
			local c = peek()
			if c == " " or c == "\t" or c == "\n" or c == "\r" then
				i += 1
			else
				break
			end
		end
	end

	local parseValue: () -> (any, string?)

	local function parseString(): (string?, string?)
		if advance() ~= '"' then
			return nil, "expected string"
		end
		local parts = {}
		while i <= n do
			local c = advance()
			if c == '"' then
				return table.concat(parts), nil
			elseif c == "\\" then
				local e = advance()
				if e == '"' or e == "\\" or e == "/" then
					table.insert(parts, e)
				elseif e == "b" then
					table.insert(parts, "\b")
				elseif e == "f" then
					table.insert(parts, "\f")
				elseif e == "n" then
					table.insert(parts, "\n")
				elseif e == "r" then
					table.insert(parts, "\r")
				elseif e == "t" then
					table.insert(parts, "\t")
				elseif e == "u" then
					local hex = string.sub(str, i, i + 3)
					if #hex < 4 then
						return nil, "bad unicode escape"
					end
					i += 4
					local code = tonumber(hex, 16)
					if code == nil then
						return nil, "bad unicode escape"
					end
					if code < 128 then
						table.insert(parts, string.char(code))
					elseif code < 2048 then
						table.insert(parts, string.char(192 + math.floor(code / 64), 128 + (code % 64)))
					else
						table.insert(
							parts,
							string.char(
								224 + math.floor(code / 4096),
								128 + (math.floor(code / 64) % 64),
								128 + (code % 64)
							)
						)
					end
				else
					return nil, "bad escape"
				end
			else
				table.insert(parts, c)
			end
		end
		return nil, "unterminated string"
	end

	local function parseNumber(): (number?, string?)
		local start = i
		if peek() == "-" then
			i += 1
		end
		if peek() == "0" then
			i += 1
		elseif string.match(peek(), "%d") then
			while string.match(peek(), "%d") do
				i += 1
			end
		else
			return nil, "bad number"
		end
		if peek() == "." then
			i += 1
			if not string.match(peek(), "%d") then
				return nil, "bad number"
			end
			while string.match(peek(), "%d") do
				i += 1
			end
		end
		local c = peek()
		if c == "e" or c == "E" then
			i += 1
			local s = peek()
			if s == "+" or s == "-" then
				i += 1
			end
			if not string.match(peek(), "%d") then
				return nil, "bad number"
			end
			while string.match(peek(), "%d") do
				i += 1
			end
		end
		local num = tonumber(string.sub(str, start, i - 1))
		if num == nil then
			return nil, "bad number"
		end
		return num, nil
	end

	local function parseArray(): (any, string?)
		advance() -- [
		skipWs()
		local arr = {}
		if peek() == "]" then
			advance()
			return arr, nil
		end
		while true do
			skipWs()
			local v, err = parseValue()
			if err then
				return nil, err
			end
			table.insert(arr, v)
			skipWs()
			local c = peek()
			if c == "]" then
				advance()
				return arr, nil
			elseif c == "," then
				advance()
			else
				return nil, "expected , or ]"
			end
		end
	end

	local function parseObject(): (any, string?)
		advance() -- {
		skipWs()
		local obj = {}
		if peek() == "}" then
			advance()
			return obj, nil
		end
		while true do
			skipWs()
			local key, kerr = parseString()
			if kerr then
				return nil, kerr
			end
			skipWs()
			if advance() ~= ":" then
				return nil, "expected :"
			end
			skipWs()
			local v, err = parseValue()
			if err then
				return nil, err
			end
			obj[key :: string] = v
			skipWs()
			local c = peek()
			if c == "}" then
				advance()
				return obj, nil
			elseif c == "," then
				advance()
			else
				return nil, "expected , or }"
			end
		end
	end

	parseValue = function(): (any, string?)
		skipWs()
		local c = peek()
		if c == '"' then
			return parseString()
		elseif c == "{" then
			return parseObject()
		elseif c == "[" then
			return parseArray()
		elseif c == "t" then
			if string.sub(str, i, i + 3) == "true" then
				i += 4
				return true, nil
			end
			return nil, "expected true"
		elseif c == "f" then
			if string.sub(str, i, i + 4) == "false" then
				i += 5
				return false, nil
			end
			return nil, "expected false"
		elseif c == "n" then
			if string.sub(str, i, i + 3) == "null" then
				i += 4
				return nil, nil
			end
			return nil, "expected null"
		elseif c == "-" or string.match(c, "%d") then
			return parseNumber()
		end
		return nil, "unexpected character"
	end

	local value, err = parseValue()
	if err then
		return nil, err
	end
	skipWs()
	if i <= n then
		return nil, "trailing junk"
	end
	return value, nil
end

-- ---------------------------------------------------------------------------
-- Build host env
-- ---------------------------------------------------------------------------

local function asyncKey(cmdOrArgv: any): string
	if typeof(cmdOrArgv) == "table" then
		local parts = {}
		for _, part in cmdOrArgv :: { any } do
			table.insert(parts, tostring(part))
		end
		return table.concat(parts, " ")
	end
	return tostring(cmdOrArgv)
end

-- Test translator: the key, then " name=value" for each substitution in name order.
local function fakeTr(key: string, subst: any?): string
	if typeof(subst) ~= "table" then
		return key
	end
	local names = {}
	for name in subst do
		table.insert(names, tostring(name))
	end
	table.sort(names)
	local out = key
	for _, name in names do
		out ..= " " .. name .. "=" .. tostring(subst[name])
	end
	return out
end

local function buildNoctalia(priv: EnvPrivate): any
	local stateApi = guardTable("noctalia.state", {
		set = function(key: string, value: any)
			record(priv, "noctalia.state.set", { key, value })
			priv.state[key] = value
			local watchers = priv.watchers[key]
			if watchers then
				for _, fn in watchers do
					fn(value)
				end
			end
		end,
		get = function(key: string): any
			record(priv, "noctalia.state.get", { key })
			return priv.state[key]
		end,
		watch = function(key: string, fn: (any) -> ())
			record(priv, "noctalia.state.watch", { key, fn })
			local list = priv.watchers[key]
			if list == nil then
				list = {}
				priv.watchers[key] = list
			end
			table.insert(list, fn)
		end,
	})

	local jsonApi = guardTable("noctalia.json", {
		encode = function(value: any, pretty: boolean?): (string?, string?)
			record(priv, "noctalia.json.encode", { value, pretty })
			return jsonEncode(value, pretty == true)
		end,
		decode = function(str: string): (any, string?)
			record(priv, "noctalia.json.decode", { str })
			return jsonDecode(str)
		end,
	})

	local stringApi = guardTable("noctalia.string", {
		trim = function(s: string): string
			record(priv, "noctalia.string.trim", { s })
			return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
		end,
		urlEncode = function(s: string): string
			record(priv, "noctalia.string.urlEncode", { s })
			local out = {}
			for i = 1, #s do
				local c = string.sub(s, i, i)
				local b = string.byte(c)
				if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or c == "-" or c == "_" or c == "." or c == "~" then
					table.insert(out, c)
				else
					table.insert(out, string.format("%%%02X", b))
				end
			end
			return table.concat(out)
		end,
		urlDecode = function(s: string): string
			record(priv, "noctalia.string.urlDecode", { s })
			s = string.gsub(s, "+", " ")
			s = string.gsub(s, "%%(%x%x)", function(hex)
				return string.char(tonumber(hex, 16) :: number)
			end)
			return s
		end,
	})

	return guardTable("noctalia", {
		setUpdateInterval = recorder(priv, "noctalia.setUpdateInterval"),
		log = recorder(priv, "noctalia.log"),
		notify = recorder(priv, "noctalia.notify"),
		notifyError = recorder(priv, "noctalia.notifyError"),
		isDarkMode = function(): boolean
			record(priv, "noctalia.isDarkMode", {})
			return false
		end,
		getColor = function(role: string): string?
			record(priv, "noctalia.getColor", { role })
			return priv.colors[role]
		end,
		getConfig = function(key: string): any
			record(priv, "noctalia.getConfig", { key })
			-- Stricter than production: undeclared keys error so tests catch typos.
			-- Declared keys are those present in opts.config (nil values cannot be declared).
			local found = false
			for k, _ in priv.config do
				if k == key then
					found = true
					break
				end
			end
			if not found then
				error(string.format("mock: getConfig undeclared key %q", tostring(key)), 2)
			end
			return priv.config[key]
		end,
		getSetting = recorder(priv, "noctalia.getSetting", "nil"),
		focusedOutputName = recorder(priv, "noctalia.focusedOutputName", "nil"),
		outputs = function(): { any }
			record(priv, "noctalia.outputs", {})
			return {}
		end,
		togglePanel = recorder(priv, "noctalia.togglePanel"),
		openSettings = recorder(priv, "noctalia.openSettings"),
		formatTime = function(pattern: string, _unix: number?, _tz: string?): string
			record(priv, "noctalia.formatTime", { pattern })
			return pattern
		end,
		nowMs = function(): number
			record(priv, "noctalia.nowMs", {})
			return priv.now
		end,
		copyToClipboard = recorder(priv, "noctalia.copyToClipboard", "true"),
		clipboardText = function(): string?
			record(priv, "noctalia.clipboardText", {})
			return priv.clipboard
		end,
		runAsync = function(cmdOrArgv: any, cb: ((AsyncResult) -> ())?): boolean
			record(priv, "noctalia.runAsync", { cmdOrArgv, cb })
			if priv.deferAsync then
				table.insert(priv.async_pending, { argv = cmdOrArgv, cb = cb })
				return true
			end
			if cb == nil then
				return true
			end
			local key = asyncKey(cmdOrArgv)
			local result = priv.async[key]
			if result == nil then
				error(string.format("mock: runAsync no scripted answer for %q", key), 2)
			end
			cb(result)
			return true
		end,
		runStream = recorder(priv, "noctalia.runStream", "true"),
		runInTerminal = recorder(priv, "noctalia.runInTerminal", "true"),
		commandExists = function(name: string): boolean
			record(priv, "noctalia.commandExists", { name })
			return priv.commands[name] == true
		end,
		getenv = function(name: string): string?
			record(priv, "noctalia.getenv", { name })
			return nil
		end,
		expandPath = function(path: string): string
			record(priv, "noctalia.expandPath", { path })
			if string.sub(path, 1, 2) == "~/" then
				return "/mock/home" .. string.sub(path, 2)
			end
			return path
		end,
		readFile = function(path: string): (string?, string?)
			record(priv, "noctalia.readFile", { path })
			local content = priv.fs[path]
			if typeof(content) == "string" then
				return content :: string, nil
			end
			return nil, "file not found: " .. path
		end,
		writeFile = function(path: string, content: string): (boolean, string?)
			record(priv, "noctalia.writeFile", { path, content })
			priv.fs[path] = content
			return true, nil
		end,
		fileExists = function(path: string): boolean
			record(priv, "noctalia.fileExists", { path })
			return priv.fs[path] ~= nil
		end,
		fileInfo = function(path: string): (any, string?)
			record(priv, "noctalia.fileInfo", { path })
			local info = priv.fileInfo[path]
			if info == nil then
				return nil, "not found: " .. path
			end
			return info, nil
		end,
		mkdirAll = function(path: string): (boolean, string?)
			record(priv, "noctalia.mkdirAll", { path })
			priv.fs[path] = true
			return true, nil
		end,
		removeFile = function(path: string): (boolean, string?)
			record(priv, "noctalia.removeFile", { path })
			if priv.fs[path] == true then
				return false, "is a directory"
			end
			priv.fs[path] = nil
			return true, nil
		end,
		renameFile = function(from: string, to: string): (boolean, string?)
			record(priv, "noctalia.renameFile", { from, to })
			local content = priv.fs[from]
			if content == nil then
				return false, "file not found: " .. from
			end
			priv.fs[to] = content
			priv.fs[from] = nil
			local info = priv.fileInfo[from]
			if info ~= nil then
				priv.fileInfo[to] = info
				priv.fileInfo[from] = nil
			end
			return true, nil
		end,
		listDir = function(dir: string): { string }
			record(priv, "noctalia.listDir", { dir })
			local prefix = dir .. "/"
			local names = {}
			for path, _ in priv.fs do
				if string.sub(path, 1, #prefix) == prefix then
					local rest = string.sub(path, #prefix + 1)
					if rest ~= "" and string.find(rest, "/", 1, true) == nil then
						table.insert(names, rest)
					end
				end
			end
			table.sort(names)
			return names
		end,
		pluginDir = function(): string
			record(priv, "noctalia.pluginDir", {})
			return "/mock/plugin"
		end,
		pluginDataDir = function(): string
			record(priv, "noctalia.pluginDataDir", {})
			return priv.pluginDataDir
		end,
		tr = function(key: string, subst: any?): string
			record(priv, "noctalia.tr", { key, subst })
			return fakeTr(key, subst)
		end,
		fuzzyScore = function(pattern: string, text: string): number?
			record(priv, "noctalia.fuzzyScore", { pattern, text })
			if string.find(text, pattern, 1, true) then
				return 1
			end
			return nil
		end,
		http = function(request: any, cb: any): boolean
			record(priv, "noctalia.http", { request, cb })
			table.insert(priv.http, { request = request, cb = cb })
			return true
		end,
		download = function(url: string, dest: string, cb: ((boolean) -> ())?): boolean
			record(priv, "noctalia.download", { url, dest, cb })
			table.insert(priv.download_pending, { url = url, dest = dest, cb = cb })
			return true
		end,
		sound = guardTable("noctalia.sound", {
			load = function(name: string, path: string, cb: ((boolean) -> ())?): boolean
				record(priv, "noctalia.sound.load", { name, path, cb })
				table.insert(priv.sound_pending, { name = name, path = path, cb = cb })
				return true
			end,
			play = recorder(priv, "noctalia.sound.play"),
		}),
		json = jsonApi,
		string = stringApi,
		state = stateApi,
	})
end

local function buildBarWidget(priv: EnvPrivate): any
	return guardTable("barWidget", {
		setText = recorder(priv, "barWidget.setText"),
		setGlyph = recorder(priv, "barWidget.setGlyph"),
		setImage = recorder(priv, "barWidget.setImage"),
		setTooltip = recorder(priv, "barWidget.setTooltip"),
		clearTooltip = recorder(priv, "barWidget.clearTooltip"),
		setFont = recorder(priv, "barWidget.setFont"),
		setColor = recorder(priv, "barWidget.setColor"),
		setGlyphColor = recorder(priv, "barWidget.setGlyphColor"),
		setVisible = recorder(priv, "barWidget.setVisible"),
		isVertical = function(): boolean
			record(priv, "barWidget.isVertical", {})
			return priv.vertical
		end,
		outputName = recorder(priv, "barWidget.outputName", "nil"),
		render = recorder(priv, "barWidget.render", "first"),
	})
end

local function buildPanel(priv: EnvPrivate): any
	return guardTable("panel", {
		render = recorder(priv, "panel.render", "first"),
		close = recorder(priv, "panel.close"),
		setWantsSecondTicks = recorder(priv, "panel.setWantsSecondTicks"),
		setNeedsFrameTick = recorder(priv, "panel.setNeedsFrameTick"),
		openContextMenu = recorder(priv, "panel.openContextMenu"),
	})
end

local function buildDesktopWidget(priv: EnvPrivate): any
	return guardTable("desktopWidget", {
		render = recorder(priv, "desktopWidget.render", "first"),
		setNeedsFrameTick = recorder(priv, "desktopWidget.setNeedsFrameTick"),
		setWantsSecondTicks = recorder(priv, "desktopWidget.setWantsSecondTicks"),
	})
end

local function buildUi(priv: EnvPrivate): any
	local function ctor(name: string): (...any) -> any
		return function(props: any, children: any?): any
			record(priv, "ui." .. name, { props, children })
			return { type = name, props = props or {}, children = children or {} }
		end
	end

	return guardTable("ui", {
		column = ctor("column"),
		row = ctor("row"),
		label = ctor("label"),
		button = ctor("button"),
		image = ctor("image"),
		box = ctor("box"),
		scroll = ctor("scroll"),
		spacer = ctor("spacer"),
		textInput = ctor("textInput"),
		slider = ctor("slider"),
		toggle = ctor("toggle"),
		icon = ctor("icon"),
		glyph = ctor("glyph"),
		progress = ctor("progress"),
		separator = ctor("separator"),
		markdown = ctor("markdown"),
		select = ctor("select"),
		input = ctor("input"),
	})
end

local function buildShortcut(priv: EnvPrivate): any
	return guardTable("shortcut", {
		setLabel = recorder(priv, "shortcut.setLabel"),
		setIcon = recorder(priv, "shortcut.setIcon"),
		setActive = recorder(priv, "shortcut.setActive"),
		setEnabled = recorder(priv, "shortcut.setEnabled"),
	})
end

local function buildLauncher(priv: EnvPrivate): any
	return guardTable("launcher", {
		setResults = recorder(priv, "launcher.setResults"),
		setQuery = recorder(priv, "launcher.setQuery"),
	})
end

local function copyMap(src: { [string]: any }?): { [string]: any }
	local out = {}
	if src then
		for k, v in src do
			out[k] = v
		end
	end
	return out
end

function Mock.new(opts: MockOpts?): any
	local o = opts or {}
	local fs = copyMap(o.fs)
	local fileInfo = copyMap(o.fileInfo)
	for path, content in fs do
		if typeof(content) == "string" and fileInfo[path] == nil then
			fileInfo[path] = { size = #content, mtime = 1, isDir = false }
		end
	end
	local priv: EnvPrivate = {
		calls = {},
		config = copyMap(o.config),
		async = copyMap(o.async :: any) :: any,
		colors = copyMap(o.colors),
		fs = fs,
		pluginDataDir = o.pluginDataDir or "/mock/plugin-data",
		state = {},
		watchers = {},
		now = o.now or 0,
		http = {},
		fileInfo = fileInfo,
		vertical = o.vertical == true,
		deferAsync = o.deferAsync == true,
		commands = copyMap(o.commands :: any) :: any,
		clipboard = o.clipboard,
		async_pending = {},
		sound_pending = {},
		download_pending = {},
	}

	local env = {
		noctalia = buildNoctalia(priv),
		barWidget = buildBarWidget(priv),
		panel = buildPanel(priv),
		ui = buildUi(priv),
		desktopWidget = buildDesktopWidget(priv),
		shortcut = buildShortcut(priv),
		launcher = buildLauncher(priv),
	}
	privateByEnv[env] = priv
	return env
end

-- Alias: plan named this install(); _G injection is impossible on this CLI.
function Mock.install(opts: MockOpts?): any
	return Mock.new(opts)
end

local function privOf(env: any): EnvPrivate
	local priv = privateByEnv[env]
	if priv == nil then
		error("mock: env was not created by mock.new/install", 3)
	end
	return priv
end

Mock.json = { encode = jsonEncode, decode = jsonDecode }
Mock.fakeTr = fakeTr

function Mock.pendingHttp(env: any): { any }
	return privOf(env).http
end

function Mock.respond(env: any, index: number, response: any)
	local call = privOf(env).http[index]
	if call == nil then
		error(string.format("mock.respond: no http call #%d", index), 2)
	end
	call.cb(response)
end

function Mock.resolveHttp(env: any, index: number, response: any)
	Mock.respond(env, index, response)
end

function Mock.pendingAsync(env: any): { any }
	return privOf(env).async_pending
end

function Mock.resolveAsync(env: any, index: number, result: any)
	local priv = privOf(env)
	local entry = priv.async_pending[index]
	if entry == nil then
		error(string.format("mock.resolveAsync: no pending call #%d", index), 2)
	end
	table.remove(priv.async_pending, index)
	local full: AsyncResult = {
		exitCode = result.exitCode,
		stdout = result.stdout or "",
		stderr = result.stderr or "",
		timedOut = if result.timedOut == nil then false else result.timedOut,
		stdoutTruncated = if result.stdoutTruncated == nil then false else result.stdoutTruncated,
		stderrTruncated = if result.stderrTruncated == nil then false else result.stderrTruncated,
	}
	if entry.cb then
		entry.cb(full)
	end
end

function Mock.resolveSound(env: any, index: number, ok: boolean)
	local priv = privOf(env)
	local entry = priv.sound_pending[index]
	if entry == nil then
		error(string.format("mock.resolveSound: no pending load #%d", index), 2)
	end
	table.remove(priv.sound_pending, index)
	if entry.cb then
		entry.cb(ok)
	end
end

function Mock.resolveDownload(env: any, index: number, ok: boolean)
	local priv = privOf(env)
	local entry = priv.download_pending[index]
	if entry == nil then
		error(string.format("mock.resolveDownload: no pending download #%d", index), 2)
	end
	table.remove(priv.download_pending, index)
	if ok then
		priv.fs[entry.dest] = "<bytes>"
		priv.fileInfo[entry.dest] = { size = 7, mtime = 1, isDir = false }
	end
	if entry.cb then
		entry.cb(ok)
	end
end

function Mock.setNow(env: any, ms: number)
	privOf(env).now = ms
end

function Mock.advance(env: any, ms: number)
	local priv = privOf(env)
	priv.now = priv.now + ms
end

function Mock.setFile(env: any, path: string, content: string, mtime: number)
	local priv = privOf(env)
	priv.fs[path] = content
	priv.fileInfo[path] = { size = #content, mtime = mtime, isDir = false }
end

function Mock.setConfig(env: any, key: string, value: any)
	privOf(env).config[key] = value
end

function Mock.setVertical(env: any, vertical: boolean)
	privOf(env).vertical = vertical
end

function Mock.calls(env: any, path: string): { { any } }
	local priv = privOf(env)
	local bucket = priv.calls[path]
	if bucket == nil then
		return {}
	end
	return bucket
end

return Mock
