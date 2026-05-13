local M = {}

local function notify(message, level)
	vim.notify(('[tmux-socket] %s'):format(message), level)
end

--- Resolve the current tmux session name, or nil if not in tmux.
---@return string|nil
local function tmux_session_name()
	if vim.env.TMUX == nil or vim.env.TMUX == "" then
		return nil
	end

	local result = vim.system({ "tmux", "display-message", "-p", "#S" }, { text = true }):wait()
	if result.code ~= 0 then
		notify(
			("Could not resolve tmux session name: %s"):format(vim.trim(result.stderr or "unknown error")),
			vim.log.levels.WARN
		)
		return nil
	end

	local name = vim.trim(result.stdout or "")
	if name == "" then
		return nil
	end

	return name
end

--- Start a Neovim server socket scoped to the current tmux session.
---
--- Creates a socket at /tmp/<tmux session name>/neovim.sock so other tools
--- inside the same tmux session can drive this Neovim instance via
--- `nvim --server <path> --remote-...`.
---
--- Silently no-ops when not running inside tmux.
function M.setup()
	local session = tmux_session_name()
	if not session then
		return
	end

	local socket_dir = "/tmp/" .. session
	local socket_path = socket_dir .. "/neovim.sock"

	local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, socket_dir, "p")
	if not mkdir_ok or mkdir_result == 0 then
		local reason = mkdir_ok and "mkdir returned 0" or mkdir_result
		notify(
			("Failed to create socket dir %s: %s"):format(socket_dir, reason),
			vim.log.levels.WARN
		)
		return
	end

	if vim.uv.fs_stat(socket_path) then
		notify(
			("Socket already exists at %s; leaving it untouched. If this is stale, remove it and restart Neovim.")
				:format(socket_path),
			vim.log.levels.INFO
		)
		return
	end

	local start_ok, addr_or_err = pcall(vim.fn.serverstart, socket_path)
	if not start_ok then
		local servers = vim.fn.serverlist()
		local server_context = #servers > 0 and table.concat(servers, ", ") or "none"
		notify(
			("Failed to start server at %s: %s. Active Neovim servers: %s")
				:format(socket_path, addr_or_err, server_context),
			vim.log.levels.WARN
		)
		return
	end

	local addr = addr_or_err
	if addr == "" then
		notify(
			("Failed to start server at %s: serverstart returned an empty address"):format(socket_path),
			vim.log.levels.WARN
		)
		return
	end

	notify(("Started server at %s"):format(addr), vim.log.levels.DEBUG)

	-- Clean up the socket on exit so a stale file doesn't block the next
	-- Neovim instance launched in this tmux session.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("custom_tmux_socket", { clear = true }),
		callback = function()
			pcall(vim.fn.serverstop, socket_path)
			pcall(vim.uv.fs_unlink, socket_path)
		end,
	})
end

return M
