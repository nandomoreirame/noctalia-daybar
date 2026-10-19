--!strict
-- Safe arithmetic evaluator. Shunting-yard over a whitelisted token set; never uses load.

local Calc = {}

local OPS: { [string]: { prec: number, right: boolean, unary: boolean } } = {
	["+"] = { prec = 1, right = false, unary = false },
	["-"] = { prec = 1, right = false, unary = false },
	["*"] = { prec = 2, right = false, unary = false },
	["/"] = { prec = 2, right = false, unary = false },
	["neg"] = { prec = 3, right = true, unary = true },
	["^"] = { prec = 4, right = true, unary = false },
}

local function isThousandsGrouped(raw: string): boolean
	-- JS: /^[1-9]\d{0,2}(\.\d{3})+$/  (Lua patterns have no group quantifier)
	local head, rest = string.match(raw, "^([1-9]%d?%d?)(%.%d%d%d.*)$")
	if head == nil then
		return false
	end
	local i = 1
	while i <= #rest do
		if string.sub(rest, i, i) ~= "." then
			return false
		end
		local digits = string.sub(rest, i + 1, i + 3)
		if not string.match(digits, "^%d%d%d$") then
			return false
		end
		i += 4
	end
	return i == #rest + 1
end

local function isNormalizedNumber(norm: string): boolean
	if string.match(norm, "^%d+%.%d+$") then
		return true
	end
	if string.match(norm, "^%d+$") then
		return true
	end
	if string.match(norm, "^%.%d+$") then
		return true
	end
	if string.match(norm, "^%d+%.$") then
		return true
	end
	return false
end

local function parseNumber(raw: string): number?
	local norm = raw
	if isThousandsGrouped(raw) then
		norm = (string.gsub(raw, "%.", ""))
	elseif string.find(raw, ",", 1, true) ~= nil then
		local _, commaCount = string.gsub(raw, ",", "")
		if commaCount > 1 then
			return nil
		end
		norm = (string.gsub((string.gsub(raw, "%.", "")), ",", "."))
	else
		local _, dotCount = string.gsub(raw, "%.", "")
		if dotCount > 1 then
			return nil
		end
	end
	if not isNormalizedNumber(norm) then
		return nil
	end
	return tonumber(norm)
end

local function isSpace(c: string): boolean
	return c == " " or c == "\t"
end

local function isNumChar(c: string): boolean
	return string.match(c, "[0-9.,]") ~= nil
end

local function isOpChar(c: string): boolean
	return string.find("+-*/^%()", c, 1, true) ~= nil
end

local function tokenize(src: string): { { t: string, v: number? } }?
	local tokens: { { t: string, v: number? } } = {}
	local i = 1
	local len = #src
	while i <= len do
		local c = string.sub(src, i, i)
		if isSpace(c) then
			i += 1
		elseif isNumChar(c) then
			local j = i
			while j <= len and isNumChar(string.sub(src, j, j)) do
				j += 1
			end
			local value = parseNumber(string.sub(src, i, j - 1))
			if value == nil then
				return nil
			end
			table.insert(tokens, { t = "num", v = value })
			i = j
		elseif isOpChar(c) then
			table.insert(tokens, { t = c })
			i += 1
		else
			return nil
		end
	end
	return tokens
end

local function isBinaryOpKey(prev: string?): boolean
	return prev ~= nil and OPS[prev] ~= nil
end

local function toRpn(tokens: { { t: string, v: number? } }): { { t: string, v: number? } }?
	local out: { { t: string, v: number? } } = {}
	local stack: { { t: string, v: number? } } = {}
	local prev: string? = nil
	for _, tok in ipairs(tokens) do
		if tok.t == "num" then
			if prev == "num" or prev == ")" or prev == "%" then
				return nil
			end
			table.insert(out, tok)
			prev = "num"
		elseif tok.t == "(" then
			if prev == "num" or prev == ")" or prev == "%" then
				return nil
			end
			table.insert(stack, tok)
			prev = "("
		elseif tok.t == ")" then
			while #stack > 0 and stack[#stack].t ~= "(" do
				table.insert(out, table.remove(stack) :: { t: string, v: number? })
			end
			if #stack == 0 or prev == "(" then
				return nil
			end
			table.remove(stack)
			prev = ")"
		elseif tok.t == "%" then
			if prev ~= "num" and prev ~= ")" and prev ~= "%" then
				return nil
			end
			table.insert(out, { t = "pct" })
			prev = "%"
		else
			local op = tok.t
			local unary = prev == nil or prev == "(" or isBinaryOpKey(prev)
			if unary then
				if op == "+" then
					continue
				end
				if op ~= "-" then
					return nil
				end
				op = "neg"
			end
			local o1 = OPS[op]
			while not o1.unary and #stack > 0 do
				local top = stack[#stack].t
				if top == "(" then
					break
				end
				local o2 = OPS[top]
				if o2.prec > o1.prec or (o2.prec == o1.prec and not o1.right) then
					table.insert(out, table.remove(stack) :: { t: string, v: number? })
				else
					break
				end
			end
			table.insert(stack, { t = op })
			prev = op
		end
	end
	while #stack > 0 do
		local tok = table.remove(stack) :: { t: string, v: number? }
		if tok.t == "(" then
			return nil
		end
		table.insert(out, tok)
	end
	return out
end

local function evalRpn(rpn: { { t: string, v: number? } }): { [string]: any }
	local st: { number } = {}
	for _, tok in ipairs(rpn) do
		if tok.t == "num" then
			table.insert(st, tok.v :: number)
		elseif tok.t == "pct" then
			local a = table.remove(st) :: number
			table.insert(st, a / 100)
		elseif tok.t == "neg" then
			if #st < 1 then
				return { ok = false, error = "syntax" }
			end
			local a = table.remove(st) :: number
			table.insert(st, -a)
		else
			if #st < 2 then
				return { ok = false, error = "syntax" }
			end
			local b = table.remove(st) :: number
			local a = table.remove(st) :: number
			if tok.t == "/" and b == 0 then
				return { ok = false, error = "division-by-zero" }
			end
			if tok.t == "+" then
				table.insert(st, a + b)
			elseif tok.t == "-" then
				table.insert(st, a - b)
			elseif tok.t == "*" then
				table.insert(st, a * b)
			elseif tok.t == "/" then
				table.insert(st, a / b)
			else
				table.insert(st, a ^ b)
			end
		end
	end
	if #st ~= 1 then
		return { ok = false, error = "syntax" }
	end
	local value = st[1]
	if value ~= value or value == math.huge or value == -math.huge then
		return { ok = false, error = "overflow" }
	end
	return { ok = true, value = value }
end

function Calc.evaluate(expr: any): { [string]: any }
	local src = string.match(tostring(expr or ""), "^%s*(.-)%s*$") or ""
	if src == "" then
		return { ok = false, error = "empty" }
	end
	local tokens = tokenize(src)
	if tokens == nil then
		return { ok = false, error = "syntax" }
	end
	local rpn = toRpn(tokens)
	if rpn == nil then
		return { ok = false, error = "syntax" }
	end
	return evalRpn(rpn)
end

local function roundSignificant(value: number, digits: number): number
	if value == 0 then
		return 0
	end
	local abs = math.abs(value)
	local exp = math.floor(math.log(abs) / math.log(10))
	local scale = 10 ^ (digits - 1 - exp)
	local rounded = math.floor(abs * scale + 0.5) / scale
	if value < 0 then
		return -rounded
	end
	return rounded
end

local function jsNumberString(n: number): string
	-- Match JS String(Number(...)): no trailing zeros, no scientific for these cases.
	if n ~= n then
		return "nan"
	end
	if n == math.huge then
		return "Infinity"
	end
	if n == -math.huge then
		return "-Infinity"
	end
	if n == 0 then
		return "0"
	end
	local s = string.format("%.15g", n)
	return s
end

function Calc.formatNumber(value: number): string
	local rounded = roundSignificant(value, 12)
	local s = jsNumberString(rounded)
	return (string.gsub(s, "%.", ","))
end

return Calc
