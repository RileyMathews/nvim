local M = {}

--- All opencode-issued diagnostics live in this single namespace so we can
--- wipe the entire set in one call without having to iterate every buffer.
local ns = vim.api.nvim_create_namespace("opencode")

local SEVERITY_MAP = {
	error = vim.diagnostic.severity.ERROR,
	warn = vim.diagnostic.severity.WARN,
	warning = vim.diagnostic.severity.WARN,
	info = vim.diagnostic.severity.INFO,
	hint = vim.diagnostic.severity.HINT,
}

local function severity_from_string(s)
	if type(s) ~= "string" then
		return vim.diagnostic.severity.INFO
	end
	return SEVERITY_MAP[string.lower(s)] or vim.diagnostic.severity.INFO
end

--- Replace every diagnostic in the opencode namespace with the contents of
--- the JSON file at `path`.
---
--- Payload shape:
---   { diagnostics = {
---       { file=<path>, line=<1-indexed>, end_line?=<1-indexed>,
---         col?=<1-indexed>, end_col?=<1-indexed>,
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

	-- Wipe every existing opencode-namespaced diagnostic across all buffers.
	-- Replace semantics: each call is the complete picture.
	vim.diagnostic.reset(ns)

	local diagnostics = payload.diagnostics
	if type(diagnostics) ~= "table" or #diagnostics == 0 then
		return "ok"
	end

	-- Group by file so we can issue one vim.diagnostic.set per buffer.
	local by_file = {}
	for _, d in ipairs(diagnostics) do
		if
			type(d) == "table"
			and type(d.file) == "string"
			and type(d.line) == "number"
			and type(d.message) == "string"
		then
			by_file[d.file] = by_file[d.file] or {}
			table.insert(by_file[d.file], d)
		end
	end

	for file, diags in pairs(by_file) do
		local bufnr = vim.fn.bufadd(file)
		if bufnr > 0 then
			-- Ensure the buffer is loaded so the diagnostic UI renders the
			-- moment the user navigates to it. `bufadd` alone leaves the
			-- buffer unloaded.
			vim.fn.bufload(bufnr)

			local converted = {}
			for _, d in ipairs(diags) do
				local line = math.max(math.floor(d.line), 1)
				local end_line = math.max(math.floor(d.end_line or line), line)
				local col = math.max(math.floor(d.col or 1), 1)

				local end_col = d.end_col
				if type(end_col) ~= "number" then
					-- Default end_col to the end of end_line so the
					-- highlight covers the whole line range. We only do
					-- the buffer lookup when the model didn't specify.
					local lines = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)
					local len = (lines[1] and #lines[1]) or 0
					end_col = len + 1
				else
					end_col = math.max(math.floor(end_col), col)
				end

				table.insert(converted, {
					lnum = line - 1,
					col = col - 1,
					end_lnum = end_line - 1,
					end_col = end_col - 1,
					message = d.message,
					severity = severity_from_string(d.severity),
					source = (type(d.source) == "string" and d.source) or "opencode",
				})
			end

			vim.diagnostic.set(ns, bufnr, converted)
		end
	end

	return "ok"
end

--- Manually clear every opencode-issued diagnostic. Bind this to a keymap
--- or user command from your config when you want a quick "dismiss":
---
---   vim.keymap.set("n", "<leader>oc", function()
---     require("custom.opencode_diag").clear()
---   end, { desc = "Clear opencode diagnostics" })
function M.clear()
	vim.diagnostic.reset(ns)
end

--- Returns the namespace ID, in case you want to query/manipulate the
--- diagnostics yourself (e.g. `vim.diagnostic.get(nil, { namespace = ns })`).
---@return integer
function M.namespace()
	return ns
end

return M
