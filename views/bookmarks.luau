--!strict
-- Bookmarks tab (REQ-029, REQ-030): add field, accent-insensitive search, rows
-- with thumbnail, title, description and "domain · date"; actions on hover.
-- st: { addRev, query, hovered = id, renaming = id, confirm = id }

local Bookmarks = require("../lib/bookmarks.luau")
local Url = require("../lib/url.luau")
local ConfirmView = require("./confirm.luau")

local BookmarksView = {}

local function shortDate(iso: any): string
	if typeof(iso) ~= "string" or #iso < 10 then
		return ""
	end
	return string.sub(iso, 9, 10) .. "/" .. string.sub(iso, 6, 7)
end

local function action(ctx: any, glyph: string, tip: string, onClick: () -> ()): any
	return ctx.ui.button({ glyph = glyph, variant = "ghost", controlSize = "sm", tooltip = ctx.tr(tip), onClick = onClick })
end

local function row(ctx: any, b: any): any
	local ui = ctx.ui
	local st = ctx.st
	if st.confirm == b.id then
		return ConfirmView.row(ctx, {
			key = "confirm-" .. b.id,
			question = ctx.tr("bookmarks.confirm-delete"),
			onConfirm = function()
				st.confirm = nil
				ctx.send("deleteBookmark", { id = b.id })
				ctx.render()
			end,
			onCancel = function()
				st.confirm = nil
				ctx.render()
			end,
		})
	end
	if st.renaming == b.id then
		return ui.row({ key = "row-" .. b.id, gap = 6, align = "center" }, {
			ui.input({
				key = "rename-" .. b.id,
				value = b.title,
				focus = true,
				flexGrow = 1,
				controlSize = "sm",
				onSubmit = function(value: string)
					st.renaming = nil
					ctx.send("renameBookmark", { id = b.id, title = value })
					ctx.render()
				end,
			}),
			ui.button({ text = ctx.tr("confirm.cancel"), variant = "ghost", controlSize = "sm", onClick = function()
				st.renaming = nil
				ctx.render()
			end }),
		})
	end
	local thumb = if b.thumbPath ~= nil
		then ui.image({ path = b.thumbPath, width = 64, height = 40, radius = 4, fit = "cover" })
		else ui.column({ width = 64, height = 40, align = "center", justify = "center", radius = 4, fill = "surface_variant" }, {
			ui.glyph({ name = "world", size = 18, color = "on_surface_variant" }),
		})
	local text = {
		ui.label({ text = tostring(b.title), fontWeight = "bold", maxLines = 1 }),
	}
	if b.description ~= nil and b.description ~= "" then
		table.insert(text, ui.label({ text = b.description, fontSize = 12, maxLines = 2, color = "on_surface_variant" }))
	end
	table.insert(text, ui.label({ text = Url.domainOf(b.url) .. " · " .. shortDate(b.savedAt), fontSize = 11, color = "on_surface_variant" }))
	local children = { thumb, ui.column({ gap = 2, flexGrow = 1 }, text) }
	if st.hovered == b.id then
		table.insert(children, ui.row({ gap = 2, align = "center" }, {
			action(ctx, "copy", "bookmarks.copy", function()
				ctx.send("copyText", { text = b.url })
			end),
			action(ctx, "refresh", "bookmarks.refresh", function()
				ctx.send("refreshBookmark", { id = b.id })
			end),
			action(ctx, "pencil", "bookmarks.rename", function()
				st.renaming = b.id
				ctx.render()
			end),
			action(ctx, "trash", "bookmarks.delete", function()
				st.confirm = b.id
				ctx.render()
			end),
		}))
	end
	return ui.row({
		key = "row-" .. b.id,
		gap = 8,
		align = "center",
		radius = 6,
		tooltip = b.url,
		onClick = function()
			ctx.send("openUrl", { url = b.url })
		end,
		onHover = function(state: string)
			st.hovered = if state == "true" then b.id elseif st.hovered == b.id then nil else st.hovered
			ctx.render()
		end,
	}, children)
end

function BookmarksView.build(ctx: any): any
	local ui = ctx.ui
	local st = ctx.st
	st.addRev = st.addRev or 0
	local list = Bookmarks.sorted(((ctx.view or {}).data or {}).bookmarks or {})
	if st.query ~= nil and st.query ~= "" then
		list = Bookmarks.search(list, st.query)
	end
	local rows = {}
	for _, b in ipairs(list) do
		table.insert(rows, row(ctx, b))
	end
	if #rows == 0 then
		local key = if st.query ~= nil and st.query ~= "" then "bookmarks.no-results" else "bookmarks.empty"
		table.insert(rows, ui.label({ text = ctx.tr(key), color = "on_surface_variant" }))
	end
	return ui.column({ gap = 8, flexGrow = 1 }, {
		ui.input({
			key = "search",
			placeholder = ctx.tr("bookmarks.search"),
			controlSize = "sm",
			onChange = function(value: string)
				st.query = value
				ctx.render()
			end,
		}),
		ui.scroll({ gap = 6, flexGrow = 1 }, rows),
		ui.input({
			key = "add-" .. st.addRev,
			placeholder = ctx.tr("bookmarks.add-placeholder"),
			controlSize = "sm",
			onSubmit = function(value: string)
				ctx.send("addBookmark", { url = value }, function(ack: any)
					if ack.ok then
						st.addRev += 1
						ctx.render()
					end
				end)
			end,
		}),
	})
end

return BookmarksView
