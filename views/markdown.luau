--!strict
-- Maps MdView blocks to ui.* nodes for the note preview (REQ-031). Text is always
-- a label prop, never markup; links are ghost buttons whose click goes to
-- ctx.onLink(href) (the service re-checks the scheme before opening it).
-- ctx: { ui, onLink(href) }

local MarkdownView = {}

local HEADING_SIZES: { [number]: number } = { 22, 19, 17, 15, 14, 13 }
local BODY_SIZE = 14
local CODE_FONT = "monospace"

local function spansRow(ui: any, spans: { any }, ctx: any, prefix: string?, color: string?): any
	local children = {}
	if prefix ~= nil then
		table.insert(children, ui.label({ text = prefix, fontSize = BODY_SIZE, color = "on_surface_variant" }))
	end
	for _, span in ipairs(spans) do
		if span.href ~= nil then
			local href = span.href
			table.insert(children, ui.button({
				text = span.text,
				variant = "ghost",
				controlSize = "sm",
				tooltip = href,
				onClick = function()
					ctx.onLink(href)
				end,
			}))
		elseif span.text ~= "" then
			table.insert(children, ui.label({ text = span.text, fontSize = BODY_SIZE, color = color, maxWidth = 1000 }))
		end
	end
	return ui.row({ gap = 4, align = "center" }, children)
end

local function listMarker(block: any, item: any, index: number): string
	if item.task == true then
		return "☑"
	elseif item.task == false then
		return "☐"
	elseif block.ordered then
		return tostring(index) .. "."
	end
	return "•"
end

local function blockNode(ui: any, block: any, ctx: any): any?
	local kind = block.kind
	if kind == "heading" then
		return ui.label({
			text = block.text,
			fontSize = HEADING_SIZES[block.level] or BODY_SIZE,
			fontWeight = "bold",
		})
	elseif kind == "paragraph" then
		return spansRow(ui, block.spans, ctx)
	elseif kind == "quote" then
		return ui.column({ paddingH = 10, border = "outline_variant", borderWidth = 1, radius = 4 }, {
			spansRow(ui, block.spans, ctx, nil, "on_surface_variant"),
		})
	elseif kind == "code" then
		return ui.column({ fill = "surface_variant", radius = 6, padding = 10 }, {
			ui.label({ text = block.text, fontFamily = CODE_FONT, fontSize = 13, color = "tertiary" }),
		})
	elseif kind == "rule" then
		return ui.separator({})
	elseif kind == "image" then
		return ui.image({ path = block.path, fit = "contain", height = 240, tooltip = block.alt })
	elseif kind == "list" then
		local rows = {}
		for i, item in ipairs(block.items) do
			local row = spansRow(ui, item.spans, ctx, listMarker(block, item, i))
			table.insert(rows, ui.column({ paddingH = (item.depth or 0) * 16 }, { row }))
		end
		return ui.column({ gap = 4 }, rows)
	elseif kind == "table" then
		local rows = {}
		for r, cells in ipairs(block.rows) do
			local labels = {}
			for _, cell in ipairs(cells) do
				table.insert(labels, ui.label({ text = cell, fontSize = BODY_SIZE, fontWeight = if r == 1 then "bold" else "normal", flexGrow = 1 }))
			end
			table.insert(rows, ui.row({ gap = 12 }, labels))
		end
		return ui.column({ gap = 4 }, rows)
	end
	return nil
end

function MarkdownView.build(blocks: { any }, ctx: { [string]: any }): any
	local ui = ctx.ui
	local children = {}
	for _, block in ipairs(blocks) do
		local node = blockNode(ui, block, ctx)
		if node ~= nil then
			table.insert(children, node)
		end
	end
	-- ctx.height: containers do not stretch to the panel, so the caller sizes it.
	return ui.scroll({ gap = 10, flexGrow = 1, height = ctx.height }, children)
end

return MarkdownView
