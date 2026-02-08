local M = {}

local spec_comment_lines = { "-- $> hspec spec", "" }
local spec_web_comment_lines = { "-- $> :import-spec-web", "", "-- $> hspecWithEnv spec", "" }

local function hspec_comment_exists()
	local search_result = vim.fn.search(spec_comment_lines[1])

	if search_result > 0 then
		return true
	end

	search_result = vim.fn.search(spec_web_comment_lines[1])

	if search_result > 0 then
		return true
	end

	return false
end

local function add_hspec_comments()
	local function add_hspec_comment(search_string, comment_lines)
		local search_result = vim.fn.search(search_string)

		if search_result > 0 then
			local existing_comments_result = vim.fn.search(comment_lines[1], "n")

			if existing_comments_result > 0 then
				return true
			end

			vim.api.nvim_buf_set_lines(0, search_result - 1, search_result - 1, true, comment_lines)
			vim.cmd.write()
			return true
		end
		return false
	end

	local has_spec_comment = add_hspec_comment(":: Spec$", spec_comment_lines)

	if not has_spec_comment then
		add_hspec_comment(":: SpecWeb$", spec_web_comment_lines)
	end
end

local function delete_hspec_comments()
	local function table_length(T)
		local count = 0
		for _ in pairs(T) do
			count = count + 1
		end
		return count
	end

	local function delete_hspec_comment(comment_lines)
		local num_lines = table_length(comment_lines)
		local search_result = vim.fn.search(comment_lines[1])

		if search_result > 0 then
			vim.api.nvim_buf_set_lines(0, search_result - 1, search_result + (num_lines - 1), true, {})
			vim.cmd.write()
		end
	end

	delete_hspec_comment(spec_comment_lines)
	delete_hspec_comment(spec_web_comment_lines)
end

M.toggle_hspec_comments = function()
	print("searching...")
	if hspec_comment_exists() then
		print("deleting...")
		delete_hspec_comments()
	else
		print("adding...")
		add_hspec_comments()
	end
end

M.setup = function(_)
	vim.keymap.set("n", "<leader>th", M.toggle_hspec_comments, { desc = "Toggle [H]spec comments" })
end

return M
