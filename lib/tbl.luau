--!strict
-- Shallow table helpers replacing Object.assign and Array.prototype.*.

local Tbl = {}

function Tbl.merge(a: { [any]: any }?, b: { [any]: any }?): { [any]: any }
	local out: { [any]: any } = {}
	if a ~= nil then
		for key, value in a do
			out[key] = value
		end
	end
	if b ~= nil then
		for key, value in b do
			out[key] = value
		end
	end
	return out
end

function Tbl.copyList(list: { any }): { any }
	local out = {}
	for i, value in ipairs(list) do
		out[i] = value
	end
	return out
end

function Tbl.map(list: { any }, fn: (any, number) -> any): { any }
	local out = {}
	for i, value in ipairs(list) do
		out[i] = fn(value, i)
	end
	return out
end

function Tbl.filter(list: { any }, fn: (any, number) -> boolean): { any }
	local out = {}
	for i, value in ipairs(list) do
		if fn(value, i) then
			table.insert(out, value)
		end
	end
	return out
end

function Tbl.find(list: { any }, fn: (any, number) -> boolean): any
	for i, value in ipairs(list) do
		if fn(value, i) then
			return value
		end
	end
	return nil
end

function Tbl.indexOf(list: { any }, needle: any): number?
	for i, value in ipairs(list) do
		if value == needle then
			return i
		end
	end
	return nil
end

function Tbl.contains(list: { any }, needle: any): boolean
	return Tbl.indexOf(list, needle) ~= nil
end

function Tbl.isArray(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local n = 0
	for key in value :: { [any]: any } do
		if typeof(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			return false
		end
		n += 1
	end
	return n == #(value :: { any })
end

return Tbl
