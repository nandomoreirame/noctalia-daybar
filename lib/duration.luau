--!strict
-- Free-form countdown durations: "90s", "10m", "1h30", "1:30", bare minutes.

local Duration = {}

Duration.MAX_SECONDS = 24 * 3600

local function matchUnit(token: string): number?
	local h, rest = string.match(token, "^(%d+)h(.*)$")
	if h ~= nil then
		if rest == "" then
			return (tonumber(h) :: number) * 3600
		end
		local m = string.match(rest, "^(%d%d?)m$")
			or string.match(rest, "^(%d%d?)min$")
			or string.match(rest, "^(%d%d?)$")
		if m ~= nil then
			local minutes = tonumber(m) :: number
			if minutes > 59 then
				return -1
			end
			return (tonumber(h) :: number) * 3600 + minutes * 60
		end
		return nil
	end
	local mins = string.match(token, "^(%d+)m$") or string.match(token, "^(%d+)min$")
	if mins ~= nil then
		return (tonumber(mins) :: number) * 60
	end
	local secs = string.match(token, "^(%d+)s$")
	if secs ~= nil then
		return tonumber(secs) :: number
	end
	return nil
end

local function matchClock(token: string): number?
	local h, m, s = string.match(token, "^(%d+):(%d%d):(%d%d)$")
	if h ~= nil then
		local minutes = tonumber(m) :: number
		local seconds = tonumber(s) :: number
		if minutes > 59 or seconds > 59 then
			return -1
		end
		return (tonumber(h) :: number) * 3600 + minutes * 60 + seconds
	end
	local mh, mm = string.match(token, "^(%d+):(%d%d)$")
	if mh ~= nil then
		local minutes = tonumber(mm) :: number
		if minutes > 59 then
			return -1
		end
		return (tonumber(mh) :: number) * 60 + minutes
	end
	return nil
end

local function result(seconds: number, words: { string }, from: number, toInclusive: number): { [string]: any }
	if seconds <= 0 or seconds > Duration.MAX_SECONDS then
		return { ok = false, error = "invalid-duration" }
	end
	local labelParts = {}
	for i = 1, from - 1 do
		table.insert(labelParts, words[i])
	end
	for i = toInclusive + 1, #words do
		table.insert(labelParts, words[i])
	end
	return { ok = true, seconds = seconds, label = table.concat(labelParts, " ") }
end

function Duration.parseDuration(text: any): { [string]: any }
	local raw = if text == nil then "" else tostring(text)
	local trimmed = string.match(raw, "^%s*(.-)%s*$") or ""
	local words: { string } = {}
	for w in string.gmatch(trimmed, "%S+") do
		table.insert(words, w)
	end
	local lower: { string } = {}
	for i, w in ipairs(words) do
		lower[i] = string.lower(w)
	end

	local first: number? = nil
	for i, w in ipairs(lower) do
		if matchUnit(w) ~= nil then
			first = i
			break
		end
	end
	if first ~= nil then
		local total = 0
		local ending = first :: number
		while ending <= #lower do
			local s = matchUnit(lower[ending])
			if s == nil then
				break
			end
			if s < 0 then
				return { ok = false, error = "invalid-duration" }
			end
			total += s
			ending += 1
		end
		return result(total, words, first :: number, ending - 1)
	end

	for i, w in ipairs(lower) do
		local s = matchClock(w)
		if s ~= nil then
			return result(s, words, i, i)
		end
	end

	if #lower > 0 then
		local bare = string.match(lower[1], "^(%d+)$")
		if bare ~= nil then
			return result((tonumber(bare) :: number) * 60, words, 1, 1)
		end
	end
	return { ok = false, error = "needs-duration" }
end

return Duration
