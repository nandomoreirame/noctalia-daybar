--!strict
-- Minimal assert helpers for plugin unit tests (Luau stdlib only).

local Assert = {}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end

	local seenA: { [any]: boolean } = {}
	for key, value in a :: { [any]: any } do
		seenA[key] = true
		if not deepEqual(value, (b :: { [any]: any })[key]) then
			return false
		end
	end
	for key, _ in b :: { [any]: any } do
		if not seenA[key] then
			return false
		end
	end
	return true
end

function Assert.equal(actual: any, expected: any)
	if actual ~= expected then
		error(
			string.format(
				"assert.equal failed: expected %s, got %s",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function Assert.deepEqual(actual: any, expected: any)
	if not deepEqual(actual, expected) then
		error(
			string.format(
				"assert.deepEqual failed: expected %s, got %s",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

Assert.same = Assert.deepEqual

function Assert.throws(fn: () -> (), messageSubstring: string?)
	local ok, err = pcall(fn)
	if ok then
		error("assert.throws failed: function did not throw", 2)
	end
	if messageSubstring ~= nil then
		local message = tostring(err)
		if string.find(message, messageSubstring, 1, true) == nil then
			error(
				string.format(
					"assert.throws failed: error %q does not contain %q",
					message,
					messageSubstring
				),
				2
			)
		end
	end
end

return Assert
