--!strict
-- Search helpers. Accents are folded with an explicit UTF-8 lookup table.

local Text = {}

-- Upper and lower Portuguese accented letters -> ASCII (Luau has no NFD normalize).
local FOLD: { [string]: string } = {
	["á"] = "a",
	["à"] = "a",
	["â"] = "a",
	["ã"] = "a",
	["ä"] = "a",
	["Á"] = "a",
	["À"] = "a",
	["Â"] = "a",
	["Ã"] = "a",
	["Ä"] = "a",
	["é"] = "e",
	["è"] = "e",
	["ê"] = "e",
	["ë"] = "e",
	["É"] = "e",
	["È"] = "e",
	["Ê"] = "e",
	["Ë"] = "e",
	["í"] = "i",
	["ì"] = "i",
	["î"] = "i",
	["ï"] = "i",
	["Í"] = "i",
	["Ì"] = "i",
	["Î"] = "i",
	["Ï"] = "i",
	["ó"] = "o",
	["ò"] = "o",
	["ô"] = "o",
	["õ"] = "o",
	["ö"] = "o",
	["Ó"] = "o",
	["Ò"] = "o",
	["Ô"] = "o",
	["Õ"] = "o",
	["Ö"] = "o",
	["ú"] = "u",
	["ù"] = "u",
	["û"] = "u",
	["ü"] = "u",
	["Ú"] = "u",
	["Ù"] = "u",
	["Û"] = "u",
	["Ü"] = "u",
	["ç"] = "c",
	["Ç"] = "c",
	["ñ"] = "n",
	["Ñ"] = "n",
}

function Text.fold(value: any): string
	if value == nil then
		return ""
	end
	local s = tostring(value)
	local out = {}
	local i = 1
	local len = #s
	while i <= len do
		local b = string.byte(s, i) :: number
		if b >= 0xC0 and b <= 0xDF and i + 1 <= len then
			local two = string.sub(s, i, i + 1)
			table.insert(out, FOLD[two] or two)
			i += 2
		elseif b >= 0xE0 and b <= 0xEF and i + 2 <= len then
			table.insert(out, string.sub(s, i, i + 2))
			i += 3
		elseif b >= 0xF0 and b <= 0xF7 and i + 3 <= len then
			table.insert(out, string.sub(s, i, i + 3))
			i += 4
		else
			table.insert(out, string.lower(string.sub(s, i, i)))
			i += 1
		end
	end
	return table.concat(out)
end

function Text.matches(fields: { any }, query: any): boolean
	local foldedQuery = Text.fold(query)
	local words = {}
	for word in string.gmatch(foldedQuery, "%S+") do
		table.insert(words, word)
	end
	if #words == 0 then
		return true
	end
	local parts = {}
	for _, field in fields do
		if field ~= nil then
			table.insert(parts, Text.fold(field))
		end
	end
	local haystack = table.concat(parts, "\n")
	for _, word in ipairs(words) do
		if string.find(haystack, word, 1, true) == nil then
			return false
		end
	end
	return true
end

return Text
