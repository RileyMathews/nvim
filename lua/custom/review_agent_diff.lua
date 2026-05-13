local M = {}

local ns = vim.api.nvim_create_namespace("review_agent_diff")
local comments = {}
local comments_by_key = {}
local next_id = 1
local setup_done = false

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "ReviewAgentDiff" })
end

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function normalize(path)
	if path == nil or path == "" then
		return ""
	end

	if vim.fs and vim.fs.normalize then
		return vim.fs.normalize(path)
	end

	return vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
end

local function git_root_for(path)
	local dir = path

	if dir == nil or dir == "" then
		dir = vim.fn.getcwd()
	elseif vim.fn.isdirectory(dir) == 0 then
		dir = vim.fn.fnamemodify(dir, ":h")
	end

	local output = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error ~= 0 or output[1] == nil or output[1] == "" then
		return nil
	end

	return normalize(output[1])
end

local function relative_path(root, path)
	root = normalize(root):gsub("/$", "")
	path = normalize(path)

	if path == root then
		return "."
	end

	local prefix = root .. "/"
	if starts_with(path, prefix) then
		return path:sub(#prefix + 1)
	end

	return path
end

local function comment_key(root, relpath, lnum)
	return table.concat({ root, relpath, tostring(lnum) }, "\0")
end

local function current_path()
	local name = vim.api.nvim_buf_get_name(0)
	if name ~= "" and not starts_with(name, "diffview://") then
		return name
	end

	return vim.fn.getcwd()
end

local function buffer_target(bufnr, lnum)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil, "No file is associated with this buffer"
	end

	if starts_with(name, "diffview://") then
		return nil, "Move to the working-tree side of the diff before adding a comment"
	end

	if vim.bo[bufnr].filetype == "DiffviewFiles" then
		return nil, "Move from the Diffview file panel into a diff buffer before adding a comment"
	end

	local path = normalize(name)
	local root = git_root_for(path)
	if root == nil then
		return nil, "Could not find a git repository for this buffer"
	end

	return {
		bufnr = bufnr,
		path = path,
		root = root,
		relpath = relative_path(root, path),
		lnum = lnum,
	}
end

local function current_target()
	if not vim.wo.diff then
		return nil, "Review comments can only be added from a diff window"
	end

	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	return buffer_target(vim.api.nvim_get_current_buf(), lnum)
end

local function trim_empty_edges(lines)
	while #lines > 0 and lines[1]:match("^%s*$") do
		table.remove(lines, 1)
	end

	while #lines > 0 and lines[#lines]:match("^%s*$") do
		table.remove(lines, #lines)
	end

	return lines
end

local function comment_lines(text)
	return vim.split(text, "\n", { plain = true })
end

local function render_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local target = buffer_target(bufnr, 1)
	if target == nil then
		return
	end

	local line_count = vim.api.nvim_buf_line_count(bufnr)
	for _, comment in ipairs(comments) do
		if comment.root == target.root and comment.relpath == target.relpath then
			local lnum = math.min(comment.lnum, line_count)
			if lnum > 0 then
				local virt_lines = {}
				for i, line in ipairs(comment_lines(comment.text)) do
					local prefix = i == 1 and "  Review: " or "          "
					table.insert(virt_lines, { { prefix .. line, "Comment" } })
				end

				vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
					virt_lines = virt_lines,
					virt_lines_above = false,
				})
			end
		end
	end
end

local function save_comment(target, text)
	local key = comment_key(target.root, target.relpath, target.lnum)
	local comment = comments_by_key[key]

	if comment == nil then
		comment = {
			id = next_id,
			root = target.root,
			relpath = target.relpath,
			path = target.path,
			lnum = target.lnum,
			text = text,
		}
		next_id = next_id + 1
		comments_by_key[key] = comment
		table.insert(comments, comment)
	else
		comment.text = text
	end

	render_buffer(target.bufnr)
end

local function close_popup(win, buf)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end

	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

local function popup_size()
	local max_width = math.max(20, vim.o.columns - 4)
	local max_height = math.max(4, vim.o.lines - 6)
	local width = math.min(80, math.max(40, math.floor(vim.o.columns * 0.6)), max_width)
	local height = math.min(12, math.max(6, math.floor(vim.o.lines * 0.3)), max_height)

	return width, height
end

local function existing_comment_for(target)
	return comments_by_key[comment_key(target.root, target.relpath, target.lnum)]
end

local function open_comment_popup(target)
	local width, height = popup_size()
	local buf = vim.api.nvim_create_buf(false, true)
	local title = (" Review comment: %s:%d "):format(target.relpath, target.lnum)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
	})

	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_name(buf, ("review-agent://comment/%d/%d"):format(buf, target.lnum))

	local existing = existing_comment_for(target)
	if existing ~= nil then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, comment_lines(existing.text))
	else
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	end
	vim.bo[buf].modified = false

	local group = vim.api.nvim_create_augroup("review_agent_diff_popup_" .. buf, { clear = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		group = group,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			trim_empty_edges(lines)

			if #lines == 0 then
				notify("Comment was empty; nothing saved", vim.log.levels.WARN)
			else
				save_comment(target, table.concat(lines, "\n"))
				notify(("Saved comment for %s:%d"):format(target.relpath, target.lnum))
			end

			vim.bo[buf].modified = false
			vim.schedule(function()
				close_popup(win, buf)
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		group = group,
		callback = function()
			-- Keep :q as an explicit cancel path, even after editing the scratch buffer.
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modified = false
			end
		end,
	})

	vim.keymap.set("n", "<Esc>", function()
		close_popup(win, buf)
	end, { buffer = buf, silent = true, desc = "Cancel review comment" })

	vim.keymap.set("n", "<C-c>", function()
		close_popup(win, buf)
	end, { buffer = buf, silent = true, desc = "Cancel review comment" })

	vim.api.nvim_win_set_option(win, "wrap", true)
	vim.cmd("startinsert")
end

local function sorted_comments()
	local sorted = vim.list_extend({}, comments)
	table.sort(sorted, function(a, b)
		if a.root ~= b.root then
			return a.root < b.root
		end

		if a.relpath ~= b.relpath then
			return a.relpath < b.relpath
		end

		return a.lnum < b.lnum
	end)

	return sorted
end

local function formatted_review()
	local sorted = sorted_comments()
	if #sorted == 0 then
		return nil
	end

	local lines = {
		"Please address these review comments:",
		"",
	}

	for i, comment in ipairs(sorted) do
		table.insert(lines, ("%d. %s:%d"):format(i, comment.relpath, comment.lnum))
		for _, line in ipairs(comment_lines(comment.text)) do
			table.insert(lines, line)
		end
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

function M.open_diff()
	local root = git_root_for(current_path())
	if root == nil then
		notify("Could not find a git repository", vim.log.levels.ERROR)
		return
	end

	vim.cmd("DiffviewOpen -C" .. vim.fn.fnameescape(root))
end

function M.comment_line()
	local target, err = current_target()
	if target == nil then
		notify(err, vim.log.levels.WARN)
		return
	end

	open_comment_popup(target)
end

function M.copy_review()
	local review = formatted_review()
	if review == nil then
		notify("No review comments to copy", vim.log.levels.WARN)
		return
	end

	local ok = pcall(vim.fn.setreg, "+", review)
	pcall(vim.fn.setreg, "*", review)

	if ok then
		notify(("Copied %d review comment(s) to the clipboard"):format(#comments))
	else
		vim.fn.setreg('"', review)
		notify("Clipboard provider failed; copied review to the unnamed register", vim.log.levels.WARN)
	end
end

function M.attach_diff_buffer(bufnr)
	vim.schedule(function()
		render_buffer(bufnr)
	end)
end

function M.setup()
	if setup_done then
		return
	end
	setup_done = true

	vim.api.nvim_create_user_command("ReviewAgentDiff", M.open_diff, {})
	vim.keymap.set("n", "<leader>ra", M.comment_line, { desc = "ReviewAgent add comment" })
	vim.keymap.set("n", "<leader>rc", M.copy_review, { desc = "ReviewAgent copy review" })
end

return M
