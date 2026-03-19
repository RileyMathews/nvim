local spinner_timer = vim.uv.new_timer()
local poll_timer = nil
local fs_watcher = nil

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local current_spinner_message = ""
local spinner_index = 1

local log_path = ".devel-logs/output.txt"
local absolute_log_path = ""
local watched_dir = nil

local read_offset = 0
local partial_line = ""
local is_polling = false

local notify_info = function(content, icon)
	icon = icon or ""
	Snacks.notify.info(content, { icon = icon, id = "ghciwatch.nvim", title = "ghciwatch.nvim" })
end

local notify_error = function(content, icon)
	icon = icon or ""
	Snacks.notify.error(content, { icon = icon, id = "ghciwatch.nvim", title = "ghciwatch.nvim" })
end

local function start_spinner_notification()
	if spinner_timer:is_active() then
		return
	end

	local function update_spinner()
		local spinner = spinner_frames[spinner_index]
		spinner_index = (spinner_index % #spinner_frames) + 1
		notify_info(current_spinner_message, spinner)
	end

	update_spinner()
	spinner_timer:start(100, 100, vim.schedule_wrap(update_spinner))
end

local function stop_spinner_notification(message, is_error)
	is_error = is_error or false
	spinner_timer:stop()
	if message then
		if is_error then
			notify_error(message)
		else
			notify_info(message)
		end
	end
end

local function extract_numbers_from_line(line)
	local pattern = "%[%s*(%d+)%s*of%s*(%d+)%s*%]"
	local num1_str, num2_str = string.match(line, pattern, 1)
	if num1_str and num2_str then
		return num1_str, num2_str
	end
	return nil
end

local function handle_line(line)
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

local function file_stat(path)
	local ok, stat = pcall(vim.uv.fs_stat, path)
	if not ok then
		return nil
	end
	return stat
end

local function stop_polling()
	if poll_timer and poll_timer:is_active() then
		poll_timer:stop()
	end
	is_polling = false
end

local function feed_chunk(chunk)
	if not chunk or chunk == "" then
		return
	end

	local data = partial_line .. chunk
	local start_index = 1

	while true do
		local newline_index = data:find("\n", start_index, true)
		if not newline_index then
			break
		end

		local line = data:sub(start_index, newline_index - 1)
		if line:sub(-1) == "\r" then
			line = line:sub(1, -2)
		end
		handle_line(line)
		start_index = newline_index + 1
	end

	partial_line = data:sub(start_index)
end

local function read_new_bytes()
	local stat = file_stat(absolute_log_path)
	if not stat or stat.type ~= "file" then
		stop_polling()
		stop_spinner_notification("Waiting for ghciwatch log")
		return
	end

	if stat.size < read_offset then
		read_offset = 0
		partial_line = ""
	end

	if stat.size == read_offset then
		return
	end

	local fd = vim.uv.fs_open(absolute_log_path, "r", 438)
	if not fd then
		return
	end

	local bytes_to_read = stat.size - read_offset
	local chunk = vim.uv.fs_read(fd, bytes_to_read, read_offset)
	vim.uv.fs_close(fd)

	if not chunk then
		return
	end

	read_offset = read_offset + #chunk
	feed_chunk(chunk)
end

local function start_polling()
	if is_polling then
		return
	end

	if not poll_timer then
		poll_timer = vim.uv.new_timer()
	end

	poll_timer:start(0, 200, vim.schedule_wrap(read_new_bytes))
	is_polling = true
end

local function find_existing_dir(path)
	local cursor = path
	while cursor and cursor ~= "" do
		local stat = file_stat(cursor)
		if stat and stat.type == "directory" then
			return cursor
		end
		local parent = vim.fs.dirname(cursor)
		if parent == cursor then
			return nil
		end
		cursor = parent
	end
	return nil
end

local function stop_fs_watcher()
	if fs_watcher then
		fs_watcher:stop()
		fs_watcher:close()
		fs_watcher = nil
	end
	watched_dir = nil
end

local function ensure_fs_watcher()
	local parent_dir = vim.fs.dirname(absolute_log_path)
	local desired_dir = find_existing_dir(parent_dir)
	if not desired_dir or desired_dir == watched_dir then
		return
	end

	stop_fs_watcher()
	fs_watcher = vim.uv.new_fs_event()
	if not fs_watcher then
		return
	end

	local ok = fs_watcher:start(desired_dir, {}, function()
		vim.schedule(function()
			ensure_fs_watcher()
			local stat = file_stat(absolute_log_path)
			if stat and stat.type == "file" and not is_polling then
				read_offset = 0
				partial_line = ""
				notify_info("Watching ghciwatch log")
				start_polling()
			end
		end)
	end)

	if ok then
		watched_dir = desired_dir
	else
		stop_fs_watcher()
	end
end

local function initialize()
	absolute_log_path = vim.fs.normalize(vim.fn.fnamemodify(log_path, ":p"))

	ensure_fs_watcher()

	local stat = file_stat(absolute_log_path)
	if stat and stat.type == "file" then
		read_offset = 0
		partial_line = ""
		notify_info("Watching ghciwatch log")
		start_polling()
	end
end

local function deinitialize()
	stop_polling()
	stop_fs_watcher()
	stop_spinner_notification()
	partial_line = ""
	read_offset = 0
end

vim.api.nvim_create_autocmd("VimLeavePre", {
	group = vim.api.nvim_create_augroup("ghciwatch.nvim", { clear = true }),
	callback = function()
		deinitialize()
	end,
})

local function setup(opts)
	opts = opts or {}
	if type(opts.log_path) == "string" and opts.log_path ~= "" then
		log_path = opts.log_path
	end

	initialize()

	return {
		log_path = log_path,
	}
end

local M = {}
M.setup = setup

return M
