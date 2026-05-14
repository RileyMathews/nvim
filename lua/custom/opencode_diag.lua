local M = {}

--- All opencode-issued shadow text lives in this namespace so we can clear it
--- without touching other virtual text/extmarks.
local ns = vim.api.nvim_create_namespace("opencode")

local SEVERITY_MAP = {
	error = "error",
	warn = "warn",
	warning = "warn",
	info = "info",
	hint = "hint",
	ERROR = "error",
	WARN = "warn",
	WARNING = "warn",
	INFO = "info",
	HINT = "hint",
}

local SEVERITY_HL = {
	error = "DiagnosticVirtualTextError",
	warn = "DiagnosticVirtualTextWarn",
	info = "DiagnosticVirtualTextInfo",
	hint = "DiagnosticVirtualTextHint",
}

local chunks = {}

local function severity_from_string(s)
	if type(s) ~= "string" then
		return "info"
	end
	return SEVERITY_MAP[s] or SEVERITY_MAP[string.lower(s)] or "info"
end

local function normalize_path(path)
	return vim.fn.fnamemodify(path, ":p")
end

local function shadow_lines(chunk)
	local message_lines = vim.split(chunk.message, "\n", { plain = true })
	local source = chunk.source ~= "" and chunk.source or "opencode"
	local prefix = "  " .. source .. ": "
	local continuation = string.rep(" ", #prefix)
	local hl = SEVERITY_HL[chunk.severity] or SEVERITY_HL.info
	local lines = {}

	for i, line in ipairs(message_lines) do
		local text = (i == 1 and prefix or continuation) .. line
		table.insert(lines, { { text, hl } })
	end

	return lines
end

local function clear_rendered_buffers()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
		end
	end
end

local function render_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return
	end

	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return
	end

	local file = normalize_path(name)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for _, chunk in ipairs(chunks) do
		if chunk.file == file then
			local render_line = math.min(chunk.line, line_count)
			chunk.bufnr = bufnr
			chunk.render_line = render_line

			vim.api.nvim_buf_set_extmark(bufnr, ns, render_line - 1, 0, {
				virt_lines = shadow_lines(chunk),
				virt_lines_above = false,
			})
		end
	end
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
	group = vim.api.nvim_create_augroup("opencode_shadow_text", { clear = true }),
	callback = function(args)
		render_buffer(args.buf)
	end,
})

--- Replace every opencode shadow-text chunk with the contents of the JSON file
--- at `path`.
---
--- Payload shape:
---   { diagnostics = {
---       { file=<path>, line=<1-indexed>, col?=<1-indexed>,
---         message=<string>, severity?="error|warn|info|hint",
---         source?=<string> },
---       ...
---     } }
---
--- Returns the string "ok" on success, or a human-readable error string.
--- We return strings (not booleans) so the opencode plugin can surface
--- failure reasons via `nvim --remote-expr` stdout.
---@param path string
---@return string
function M.set_from_file(path)
	local f, open_err = io.open(path, "r")
	if not f then
		return "failed to open payload: " .. tostring(open_err)
	end
	local content = f:read("*a")
	f:close()

	local ok, payload = pcall(vim.json.decode, content)
	if not ok then
		return "invalid JSON: " .. tostring(payload)
	end
	if type(payload) ~= "table" then
		return "payload is not a JSON object"
	end

	clear_rendered_buffers()
	chunks = {}

	local diagnostics = payload.diagnostics
	if type(diagnostics) ~= "table" or #diagnostics == 0 then
		return "ok"
	end

	local by_file = {}
	for _, d in ipairs(diagnostics) do
		if
			type(d) == "table"
			and type(d.file) == "string"
			and type(d.line) == "number"
			and type(d.message) == "string"
		then
			local line = math.max(math.floor(d.line), 1)
			local col = math.max(math.floor(d.col or 1), 1)

			local file = normalize_path(d.file)
			local chunk = {
				id = #chunks + 1,
				file = file,
				line = line,
				col = col,
				message = d.message,
				severity = severity_from_string(d.severity),
				source = (type(d.source) == "string" and d.source) or "opencode",
			}

			table.insert(chunks, chunk)
			by_file[file] = true
		end
	end

	for file in pairs(by_file) do
		local bufnr = vim.fn.bufadd(file)
		if bufnr > 0 then
			-- Ensure the buffer is loaded so shadow text appears when the user
			-- navigates to it. `bufadd` alone leaves the buffer unloaded.
			vim.fn.bufload(bufnr)
			render_buffer(bufnr)
		end
	end

	return "ok"
end

function M.pick()
	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks.picker then
		vim.notify("opencode: snacks.nvim picker is required", vim.log.levels.ERROR)
		return
	end

	local items = {}
	for _, chunk in ipairs(chunks) do
		local first_line = vim.split(chunk.message, "\n", { plain = true })[1] or ""
		local search_text = chunk.message:gsub("\n", " ")
		local bufnr = chunk.bufnr
		local line = chunk.render_line or chunk.line

		table.insert(items, {
			text = table.concat({ chunk.source, chunk.file, tostring(chunk.line), search_text }, " "),
			file = chunk.file,
			buf = bufnr and vim.api.nvim_buf_is_valid(bufnr) and bufnr or nil,
			pos = { line, chunk.col - 1 },
			severity = chunk.severity,
			comment = first_line,
			item = {
				message = first_line,
				source = chunk.source,
			},
		})
	end

	snacks.picker.pick({
		source = "opencode",
		title = "Opencode Chunks",
		items = items,
		format = "file",
		preview = "file",
		confirm = "jump",
		show_empty = true,
		matcher = { sort_empty = true },
	})
end

function M.chunks()
	return vim.deepcopy(chunks)
end

--- Manually clear every opencode-issued chunk and shadow line.
function M.clear()
	clear_rendered_buffers()
	chunks = {}
end

--- Returns the namespace ID, in case you want to query/manipulate the extmarks.
---@return integer
function M.namespace()
	return ns
end

return M
