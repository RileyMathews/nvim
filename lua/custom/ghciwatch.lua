local timer = vim.loop.new_timer()
local buf = -1
local ghciwatch_command =
	"echo there was an error determining the ghciwatch command to run. Please consult documentation"
local current_spinner_message = ""

local notify_info = function(content, icon)
	icon = icon or ""
	Snacks.notify.info(content, { icon = icon, id = "ghciwatch.nvim", title = "ghciwatch.nvim" })
end

local notify_error = function(content, icon)
	icon = icon or ""
	Snacks.notify.error(content, { icon = icon, id = "ghciwatch.nvim", title = "ghciwatch.nvim" })
end

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function start_spinner_notification()
	if timer == nil then
		Snacks.notify.error("Somehow the timer was nil. This should have never happened")
		return
	end
	if timer:is_active() then
		return
	end
	local spinner_index = 1
	local function update_spinner()
		local spinner = spinner_frames[spinner_index]
		spinner_index = (spinner_index % #spinner_frames) + 1
		notify_info(current_spinner_message, spinner)
	end

	update_spinner()
	timer:start(100, 100, vim.schedule_wrap(update_spinner))
end

local function stop_spinner_notification(message, error)
	error = error or false
	if timer then
		timer:stop()
	end
	if message then
		if error then
			notify_error(message)
		else
			notify_info(message)
		end
	end
end

local function get_window_config()
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local opts = {
		style = "minimal",
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		border = "rounded",
	}

	return opts
end

local function show_buffer()
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_open_win(buf, true, get_window_config())
	else
		notify_info("ghciwatch must be started first", "")
	end
end

local function extract_numbers_from_line(line)
	-- Pattern to capture the two numbers within the brackets
	local pattern = "%[%s*(%d+)%s*of%s*(%d+)%s*%]"

	-- Use string.match to find the pattern and capture the numbers starting from the beginning (index 1)
	local num1_str, num2_str = string.match(line, pattern, 1)

	-- Check if the match and capture were successful
	if num1_str and num2_str then
		-- Return the captured strings in a table
		return num1_str, num2_str
	else
		-- Return nil if the pattern doesn't match the start of the line
		return nil
	end
end

local function handle_output(_, buffer, _, firstline, lastline, _, _, _, _)
	local lines = vim.api.nvim_buf_get_lines(buffer, firstline, lastline, false)
	for _, line in ipairs(lines) do
		if line:match("All good!") then
			stop_spinner_notification("Ghciwatch done")
		end
		if line:match("Running") then
			start_spinner_notification()
			current_spinner_message = "Ghciwatch loading"
		end
		if line:match("Reloading failed") then
			stop_spinner_notification("Ghciwatch finished with errors", true)
		end
		if line:match("Compiling") then
			start_spinner_notification()
			local current, total = extract_numbers_from_line(line)
			if current and total then
				current_spinner_message = current .. "/" .. total .. " modules loaded"
			end
		end
	end
end

local function initialize()
	if vim.api.nvim_buf_is_valid(buf) then
		notify_error("Ghciwatch already running")
		return
	end
	notify_info("starting up")
	buf = vim.api.nvim_create_buf(false, true)
	show_buffer()
	vim.cmd.terminal(ghciwatch_command)
	vim.api.nvim_create_autocmd("TermClose", {
		group = vim.api.nvim_create_augroup("MyPluginTermHandling", { clear = true }),
		buffer = buf,
		callback = function(_)
			stop_spinner_notification("ghciwatch process quit")
		end,
	})
	vim.api.nvim_buf_attach(buf, false, { on_lines = handle_output })
end

local function deinitialize()
	if vim.api.nvim_buf_is_valid(buf) then
		notify_info("shutting down ghciwatch")
		vim.api.nvim_buf_delete(buf, { force = true })
		buf = -1
	end
end

vim.api.nvim_create_user_command("GhciwatchStart", initialize, { nargs = 0 })
vim.api.nvim_create_user_command("GhciwatchStop", deinitialize, { nargs = 0 })
vim.api.nvim_create_user_command("GhciwatchShow", show_buffer, { nargs = 0 })

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("ghciwatch.nvim", {}),
	callback = function()
		deinitialize()
	end,
})

local function file_exists(path)
	local root = vim.fn.getcwd()
	local file = root .. "/" .. path
	local ok, _ = vim.uv.fs_stat(file)
	return ok
end

local function setup()
	if file_exists("Justfile") then
		ghciwatch_command = "just ghciwatch"
	end
	if file_exists("Makefile") then
		ghciwatch_command = "make ghciwatch"
	end
	return {
		initialize = initialize,
		deinitialize = deinitialize,
		show_buffer = show_buffer,
	}
end

local M = {}
M.setup = setup

return M
