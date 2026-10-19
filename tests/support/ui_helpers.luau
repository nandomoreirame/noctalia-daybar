-- Tree helpers for view and entry tests: find nodes in the plain trees the mock
-- ui.* constructors return.

local U = {}

function U.findAll(node: any, pred: (any) -> boolean, out: { any }?): { any }
	local acc = out or {}
	if node == nil then
		return acc
	end
	if pred(node) then
		table.insert(acc, node)
	end
	for _, child in node.children or {} do
		U.findAll(child, pred, acc)
	end
	return acc
end

function U.ofType(node: any, kind: string): { any }
	return U.findAll(node, function(n)
		return n.type == kind
	end)
end

function U.button(node: any, prop: string, value: any): any
	return U.findAll(node, function(n)
		return n.type == "button" and n.props[prop] == value
	end)[1]
end

function U.hasLabel(node: any, text: string): boolean
	return #U.findAll(node, function(n)
		return n.type == "label" and typeof(n.props.text) == "string" and string.find(n.props.text, text, 1, true) ~= nil
	end) > 0
end

function U.byKey(node: any, key: string): any
	return U.findAll(node, function(n)
		return n.props ~= nil and n.props.key == key
	end)[1]
end

return U
