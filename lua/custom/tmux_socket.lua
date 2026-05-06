local M = {}

--- Resolve the current tmux session name, or nil if not in tmux.
---@return string|nil
local function tmux_session_name()
	if vim.env.TMUX == nil or vim.env.TMUX == "" then
		return nil
	end

	local result = vim.system({ "tmux", "display-message", "-p", "#S" }, { text = true }):wait()
	if result.code ~= 0 then
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

	local mkdir_ok, mkdir_err = pcall(vim.fn.mkdir, socket_dir, "p")
	if not mkdir_ok then
		vim.notify(
			("Failed to create tmux socket dir %s: %s"):format(socket_dir, mkdir_err),
			vim.log.levels.WARN
		)
		return
	end

	if vim.uv.fs_stat(socket_path) then
		vim.notify(
			("Neovim socket already present at %s"):format(socket_path),
			vim.log.levels.INFO
		)
		return
	end

	local addr = vim.fn.serverstart(socket_path)
	if addr == "" then
		vim.notify(
			("Failed to start Neovim socket server at %s"):format(socket_path),
			vim.log.levels.WARN
		)
		return
	end

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
