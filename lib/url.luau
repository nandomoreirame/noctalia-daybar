--!strict
-- URL helpers without a URL class. Pure string scanning.

local Url = {}

local function trim(text: any): string
	return (string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1"))
end

-- True when the first character after "://" is not whitespace / $ . ? #
-- and the rest has no whitespace (mirrors /^https?:\/\/[^\s/$.?#][^\s]*$/i).
function Url.isHttpUrl(text: any): boolean
	local s = trim(text)
	local rest = string.match(s, "^[Hh][Tt][Tt][Pp][Ss]?://(.+)$")
	if rest == nil or rest == "" then
		return false
	end
	local first = string.sub(rest, 1, 1)
	if string.find(first, "[%s/$%.?#]", 1) ~= nil then
		return false
	end
	if string.find(rest, "%s") ~= nil then
		return false
	end
	return true
end

-- Lowercase only the origin (scheme + host), leave the path as-is.
local function lowerOrigin(base: string): string
	local origin, rest = string.match(base, "^(https?://[^/]+)(.*)$")
	if origin == nil then
		return string.lower(base)
	end
	return string.lower(origin) .. (rest or "")
end

local function stripTrailingSlashes(s: string): string
	return (string.gsub(s, "/+$", ""))
end

-- Identity used to detect duplicates: lowercase scheme and host, no #fragment,
-- no utm_* parameters, no trailing slash.
function Url.normalizeUrl(url: any): string
	local s = trim(url)
	if not Url.isHttpUrl(s) then
		return ""
	end
	local hashAt = string.find(s, "#", 1, true)
	if hashAt then
		s = string.sub(s, 1, hashAt - 1)
	end
	local q = string.find(s, "?", 1, true)
	local base = if q then string.sub(s, 1, q - 1) else s
	local query = if q then string.sub(s, q + 1) else ""
	local params = {}
	if query ~= "" then
		for p in string.gmatch(query, "[^&]+") do
			local key = string.match(p, "^([^=]*)") or p
			if not string.match(string.lower(key), "^utm_") then
				table.insert(params, p)
			end
		end
	end
	base = stripTrailingSlashes(lowerOrigin(base))
	if #params > 0 then
		return base .. "?" .. table.concat(params, "&")
	end
	return base
end

-- Host from an http(s) URL, ignoring userinfo (text before the last "@" in
-- the authority). Bracketed IPv6 stays intact; a trailing ":port" is dropped.
local function hostOf(url: string): string?
	local authority = string.match(url, "^[Hh][Tt][Tt][Pp][Ss]?://([^/?#]+)")
	if authority == nil or authority == "" then
		return nil
	end
	local at = string.find(authority, "@[^@]*$")
	if at then
		authority = string.sub(authority, at + 1)
	end
	if authority == "" then
		return nil
	end
	if string.sub(authority, 1, 1) == "[" then
		local close = string.find(authority, "]", 1, true)
		if close == nil then
			return nil
		end
		return string.sub(authority, 1, close)
	end
	local colon = string.find(authority, ":", 1, true)
	if colon then
		return string.sub(authority, 1, colon - 1)
	end
	return authority
end

function Url.domainOf(url: any): string
	local host = hostOf(trim(url))
	if host == nil then
		return ""
	end
	host = string.lower(host)
	host = (string.gsub(host, "^www%.", ""))
	return host
end

-- Resolves an href/src found in a page against the page URL. Only http(s)
-- results are returned; anything else (data:, javascript:, ...) gives "".
function Url.resolveUrl(ref: any, pageUrl: any): string
	local r = trim(ref)
	if r == "" then
		return ""
	end
	if Url.isHttpUrl(r) then
		return r
	end
	local scheme, host, path = string.match(
		trim(pageUrl),
		"^([Hh][Tt][Tt][Pp][Ss]?)://([^/?#]+)([^?#]*)"
	)
	if scheme == nil then
		return ""
	end
	scheme = string.lower(scheme)
	local out = ""
	if string.sub(r, 1, 2) == "//" then
		out = scheme .. ":" .. r
	elseif string.sub(r, 1, 1) == "/" then
		out = scheme .. "://" .. host .. r
	elseif string.match(r, "^[a-zA-Z][a-zA-Z0-9+.-]*:") then
		return ""
	else
		local dir = path or ""
		dir = (string.gsub(dir, "[^/]*$", ""))
		if dir == "" then
			dir = "/"
		end
		out = scheme .. "://" .. host .. dir .. r
	end
	return if Url.isHttpUrl(out) then out else ""
end

-- Canonical dotted-decimal only: four octets 0-255, no leading zeros.
local function ipv4Octets(host: string): { number }?
	local a, b, c, d = string.match(host, "^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
	if a == nil then
		return nil
	end
	local raw = { a, b, c, d }
	for _, o in ipairs(raw) do
		if #o > 1 and string.sub(o, 1, 1) == "0" then
			return nil
		end
	end
	local parts = {
		tonumber(a) :: number,
		tonumber(b) :: number,
		tonumber(c) :: number,
		tonumber(d) :: number,
	}
	for _, n in ipairs(parts) do
		if n > 255 then
			return nil
		end
	end
	return parts
end

local function isPrivateIpv4(ip: { number }): boolean
	if ip[1] == 127 or ip[1] == 0 then
		return true
	end
	if ip[1] == 10 then
		return true
	end
	if ip[1] == 192 and ip[2] == 168 then
		return true
	end
	if ip[1] == 169 and ip[2] == 254 then
		return true
	end
	if ip[1] == 172 and ip[2] >= 16 and ip[2] <= 31 then
		return true
	end
	-- CGNAT / Tailscale
	if ip[1] == 100 and ip[2] >= 64 and ip[2] <= 127 then
		return true
	end
	-- Benchmarking
	if ip[1] == 198 and (ip[2] == 18 or ip[2] == 19) then
		return true
	end
	-- Multicast and reserved (224.0.0.0/4 and above), including broadcast
	if ip[1] >= 224 then
		return true
	end
	return false
end

-- Expand ::ffff:XXXX:XXXX into four IPv4 octets, or nil when not that form.
local function ipv4MappedFromHex(a: string, b: string): { number }?
	if #a > 4 or #b > 4 then
		return nil
	end
	local hi = tonumber(a, 16)
	local lo = tonumber(b, 16)
	if hi == nil or lo == nil then
		return nil
	end
	return {
		math.floor(hi / 256) % 256,
		hi % 256,
		math.floor(lo / 256) % 256,
		lo % 256,
	}
end

-- True when an IPv6 literal is loopback, unspecified, or IPv4-mapped private.
local function isPrivateOrLocalIpv6(bare: string): boolean
	local lower = string.lower(bare)
	if lower == "::" or lower == "::1" then
		return true
	end
	-- Fully written loopback (and any zero-padded equivalent of ::1).
	-- Lua patterns have no {n} quantifier; spell the seven groups out.
	if string.match(lower, "^0+:0+:0+:0+:0+:0+:0+:1$") then
		return true
	end
	-- IPv4-mapped: ::ffff:a.b.c.d
	local dotted = string.match(lower, "^::ffff:(%d+%.%d+%.%d+%.%d+)$")
	if dotted then
		local ip = ipv4Octets(dotted)
		return ip == nil or isPrivateIpv4(ip)
	end
	-- IPv4-mapped: ::ffff:XXXX:XXXX
	local ha, hb = string.match(lower, "^::ffff:([0-9a-f]+):([0-9a-f]+)$")
	if ha then
		local ip = ipv4MappedFromHex(ha, hb)
		return ip == nil or isPrivateIpv4(ip)
	end
	if string.match(lower, "^f[cd][0-9a-f][0-9a-f]:") then
		return true
	end
	if string.match(lower, "^fe[89ab][0-9a-f]:") then
		return true
	end
	return false
end

local function isNumericLabel(label: string): boolean
	return string.match(label, "^0[xX][0-9a-fA-F]*$") ~= nil
		or string.match(label, "^[0-9]+$") ~= nil
end

local function isPrivateOrLocalHost(host: any): boolean
	local h = string.lower(tostring(host or ""))
	if h == "" then
		return true
	end
	-- Trailing dots are DNS root markers; strip before every check.
	while #h > 0 and string.sub(h, -1) == "." do
		h = string.sub(h, 1, -2)
	end
	if h == "" then
		return true
	end
	if h == "localhost" or string.match(h, "%.localhost$") then
		return true
	end
	if string.find(h, ":", 1, true) or (string.sub(h, 1, 1) == "[" and string.sub(h, -1) == "]") then
		local bare = if string.sub(h, 1, 1) == "[" then string.sub(h, 2, -2) else h
		return isPrivateOrLocalIpv6(bare)
	end
	local ip = ipv4Octets(h)
	if ip then
		return isPrivateIpv4(ip)
	end
	-- Every label numeric (decimal, octal or 0x-hex) but not canonical IPv4:
	-- curl still accepts it as an address (127.1, 0x7f.0.0.1, 0177.0.0.1,
	-- 2130706433). Real domains such as "cafe.de" have non-numeric labels.
	local allNumeric = true
	for label in string.gmatch(h, "[^.]+") do
		if not isNumericLabel(label) then
			allNumeric = false
			break
		end
	end
	if allNumeric then
		return true
	end
	-- Bare hostnames without a dot are local/LAN services.
	return string.find(h, ".", 1, true) == nil
end

-- True for http(s) URLs whose host is publicly routable. Used to refuse
-- downloading untrusted og:image URLs that point at private/link-local hosts.
function Url.isPublicHttpUrl(url: any): boolean
	local s = trim(url)
	if not Url.isHttpUrl(s) then
		return false
	end
	local host = hostOf(s)
	if host == nil then
		return false
	end
	return not isPrivateOrLocalHost(host)
end

return Url
