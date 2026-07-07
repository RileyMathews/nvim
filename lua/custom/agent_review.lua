-- agent_review: leave line-anchored review comments on agent generated code,
-- then export them as a single prompt to the clipboard.

local ns = vim.api.nvim_create_namespace("agent-review")

-- ── Comment types ────────────────────────────────────────────────────────
-- Edit the text here to tune the exported prompt wording per type:
--   * `heading` opens that type's section in the exported prompt.
--   * `prompt` tells the agent how to treat comments of that type.
--   * `label` is shown in the comment box title and the virtual text.
--   * `hl` / `default_hl` control the virtual text highlight.
local types = {
	issue = {
		label = "Issue",
		hl = "AgentReviewIssue",
		default_hl = "DiagnosticVirtualTextWarn",
		heading = "## Issues",
		prompt = "These are problems I want fixed. Make the code changes needed to address each one.",
	},
	question = {
		label = "Question",
		hl = "AgentReviewQuestion",
		default_hl = "DiagnosticVirtualTextHint",
		heading = "## Questions",
		prompt = "These are questions, not change requests. Answer each one in your reply,"
			.. " but do not make any code changes for them yet.",
	},
}

-- Order in which type sections appear in the exported prompt.
local type_order = { "issue", "question" }
-- ─────────────────────────────────────────────────────────────────────────

---@class agent_review.Comment
---@field bufnr number source buffer the comment is anchored in
---@field path string path of the source file, relative to cwd at comment time
---@field mark_id number extmark id in the `agent-review` namespace
---@field lines string[] comment text
---@field type string key into `types` ("issue", "question", ...)

---@type agent_review.Comment[]
local comments = {}

local box = nil ---@type snacks.win?
local box_counter = 0

local notify_info = function(content)
	Snacks.notify.info(content, { title = "agent review" })
end

local notify_warn = function(content)
	Snacks.notify.warn(content, { title = "agent review" })
end

local function buf_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return "[No Name]"
	end
	return vim.fn.fnamemodify(name, ":.")
end

local function range_label(lstart, lend)
	if lstart == lend then
		return ("line %d"):format(lstart)
	end
	return ("lines %d-%d"):format(lstart, lend)
end

local function comment_virt_lines(type_name, lines)
	local tdef = types[type_name]
	local virt = {}
	for i, line in ipairs(lines) do
		local prefix = i == 1 and ("┃ %s: "):format(tdef.label) or "┃ "
		virt[#virt + 1] = { { prefix .. line, tdef.hl } }
	end
	return virt
end

-- Current 1-based (start, end) lines of a comment's extmark, or nil when the
-- buffer is gone/unloaded or the anchored range was deleted.
local function mark_range(comment)
	if not (vim.api.nvim_buf_is_valid(comment.bufnr) and vim.api.nvim_buf_is_loaded(comment.bufnr)) then
		return nil
	end
	local mark = vim.api.nvim_buf_get_extmark_by_id(comment.bufnr, ns, comment.mark_id, { details = true })
	if not mark or #mark == 0 then
		return nil
	end
	local details = mark[3]
	if details and details.invalid then
		return nil
	end
	local last = vim.api.nvim_buf_line_count(comment.bufnr) - 1
	local srow = math.min(mark[1], last)
	local erow = math.min(math.max(details and details.end_row or srow, srow), last)
	return srow + 1, erow + 1
end

local function prune()
	local kept = {}
	for _, comment in ipairs(comments) do
		if mark_range(comment) then
			kept[#kept + 1] = comment
		elseif vim.api.nvim_buf_is_valid(comment.bufnr) then
			pcall(vim.api.nvim_buf_del_extmark, comment.bufnr, ns, comment.mark_id)
		end
	end
	comments = kept
end

local function add_comment(bufnr, lstart, lend, lines, type_name)
	local last = vim.api.nvim_buf_line_count(bufnr)
	lstart = math.max(1, math.min(lstart, last))
	lend = math.max(lstart, math.min(lend, last))
	local mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns, lstart - 1, 0, {
		end_row = lend - 1,
		invalidate = true,
		virt_lines = comment_virt_lines(type_name, lines),
	})
	comments[#comments + 1] = {
		bufnr = bufnr,
		path = buf_path(bufnr),
		mark_id = mark_id,
		lines = lines,
		type = type_name,
	}
end

local function close_box()
	local current = box
	box = nil
	if current then
		current:close()
	end
end

local function open_box(bufnr, lstart, lend, type_name)
	local tdef = types[type_name]
	box_counter = box_counter + 1
	local cbuf = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(cbuf, ("agentreview://comment/%d"):format(box_counter))
	vim.bo[cbuf].buftype = "acwrite"
	vim.bo[cbuf].bufhidden = "wipe"
	vim.bo[cbuf].swapfile = false
	vim.bo[cbuf].filetype = "markdown"

	-- Keep the buffer permanently unmodified so a plain :q cancels without E37.
	-- Buffer-local autocmds are wiped together with the buffer.
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
		buffer = cbuf,
		callback = function()
			vim.bo[cbuf].modified = false
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = cbuf,
		callback = function()
			vim.bo[cbuf].modified = false
			local lines = vim.api.nvim_buf_get_lines(cbuf, 0, -1, false)
			while #lines > 0 and lines[#lines]:match("^%s*$") do
				table.remove(lines)
			end
			-- Close on the next tick: with :wq the quit closes the window
			-- itself first and this then no-ops instead of hitting another window.
			vim.schedule(close_box)
			if #lines == 0 then
				notify_warn("Empty comment discarded")
				return
			end
			if not vim.api.nvim_buf_is_valid(bufnr) then
				notify_warn("Reviewed buffer no longer exists, comment discarded")
				return
			end
			add_comment(bufnr, lstart, lend, lines, type_name)
			notify_info(("%s saved for %s %s"):format(tdef.label, buf_path(bufnr), range_label(lstart, lend)))
		end,
	})

	box = Snacks.win({
		buf = cbuf,
		enter = true,
		relative = "editor",
		position = "float",
		backdrop = false,
		border = "rounded",
		width = 0.6,
		min_width = 40,
		max_width = 100,
		height = 8,
		title = (" %s · %s · %s "):format(tdef.label, buf_path(bufnr), range_label(lstart, lend)),
		title_pos = "center",
		footer = " :w save · :q cancel ",
		footer_pos = "center",
		wo = { wrap = true, linebreak = true },
		b = { agent_review_box = true },
		keys = { q = false },
		on_close = function(self)
			if box == self then
				box = nil
			end
		end,
	})
	vim.cmd.startinsert()
end

---@param type_name? string key into `types`, defaults to "issue"
local function comment(type_name)
	type_name = type_name or "issue"
	if not types[type_name] then
		notify_warn(("Unknown comment type %q"):format(type_name))
		return
	end
	if box and box:valid() then
		box:focus()
		notify_info("A comment is already in progress (:w save, :q cancel)")
		return
	end
	box = nil

	local bufnr = vim.api.nvim_get_current_buf()
	if vim.b[bufnr].agent_review_box then
		return
	end

	local mode = vim.fn.mode()
	local lstart, lend
	if mode == "v" or mode == "V" or mode == "\22" then
		lstart = vim.fn.line("v")
		lend = vim.fn.line(".")
		if lstart > lend then
			lstart, lend = lend, lstart
		end
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	else
		lstart = vim.fn.line(".")
		lend = lstart
	end

	open_box(bufnr, lstart, lend, type_name)
end

local function export()
	prune()
	if #comments == 0 then
		notify_warn("No review comments to export")
		return
	end

	local out = {
		"I reviewed the code and left line-anchored feedback below, grouped by type."
			.. " Each item shows the file, the line range, the current code at"
			.. " that location, and my comment.",
		"",
	}
	local count = 0
	for _, type_name in ipairs(type_order) do
		local tdef = types[type_name]
		local section = {}
		for _, c in ipairs(comments) do
			if c.type == type_name then
				local lstart, lend = mark_range(c)
				if lstart then
					section[#section + 1] = ("### %s %s"):format(c.path, range_label(lstart, lend))
					section[#section + 1] = ""
					section[#section + 1] = "```" .. (vim.bo[c.bufnr].filetype or "")
					vim.list_extend(section, vim.api.nvim_buf_get_lines(c.bufnr, lstart - 1, lend, false))
					section[#section + 1] = "```"
					section[#section + 1] = ""
					vim.list_extend(section, c.lines)
					section[#section + 1] = ""
					count = count + 1
				end
			end
		end
		if #section > 0 then
			out[#out + 1] = tdef.heading
			out[#out + 1] = ""
			out[#out + 1] = tdef.prompt
			out[#out + 1] = ""
			vim.list_extend(out, section)
		end
	end

	vim.fn.setreg("+", table.concat(out, "\n"))
	notify_info(("Copied %d comment(s) to clipboard"):format(count))
end

local function clear()
	local bufs = {}
	for _, c in ipairs(comments) do
		if vim.api.nvim_buf_is_valid(c.bufnr) then
			bufs[c.bufnr] = true
		end
	end
	for bufnr in pairs(bufs) do
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	end
	local count = #comments
	comments = {}
	notify_info(("Cleared %d comment(s)"):format(count))
end

local function set_highlights()
	for _, tdef in pairs(types) do
		vim.api.nvim_set_hl(0, tdef.hl, { link = tdef.default_hl, default = true })
	end
end

local function setup(opts)
	opts = opts or {}
	set_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("agent-review", { clear = true }),
		callback = set_highlights,
	})
end

local M = {}
M.setup = setup
M.comment = comment
M.export = export
M.clear = clear

-- Read-only view of the stored comments (pruned first). Mainly for tests
-- and future UI (e.g. a picker over open comments).
M.comments = function()
	prune()
	return comments
end

return M
