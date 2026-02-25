-- half page jumping
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- keep cursor in middle when searching
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- optional paste that does not put replaced text into buffer
-- vim.keymap.set("x", "<leader>p", '"_dP', { desc = "[P]aste without replacing buffer" })
-- vim.keymap.set("x", "<leader>p", '"_dP', { desc = "[P]aste without replacing buffer" })

-- optional yank into system clipboard
vim.keymap.set("v", "<leader>y", '"+y', { desc = "[Y]ank into system clipboard" })
vim.keymap.set("n", "<leader>Y", '"+Y', { desc = "[Y]ank into system clipboard" })

-- disable Q
vim.keymap.set("n", "Q", "<nop>")

-- These mappings control the size of splits (height/width)
vim.keymap.set("n", "<M-,>", "<c-w>5<")
vim.keymap.set("n", "<M-.>", "<c-w>5>")
vim.keymap.set("n", "<M-t>", "<C-W>+")
vim.keymap.set("n", "<M-s>", "<C-W>-")

vim.keymap.set("t", "<esc><esc>", "<c-\\><c-n>")

vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end)
vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end)

-- Copy filepath to clipboard with optional line range
local function copy_filepath()
	local filepath = vim.fn.expand("%:.")
	local text_to_copy = filepath

	-- Check if in visual mode and append line range
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local line_start = vim.fn.line("v")
		local line_end = vim.fn.line(".")
		-- Ensure start is always less than end
		if line_start > line_end then
			line_start, line_end = line_end, line_start
		end
		text_to_copy = filepath .. ":" .. line_start .. "-" .. line_end
	end

	vim.fn.system("wl-copy", text_to_copy)
	vim.notify("Copied to clipboard: " .. text_to_copy, vim.log.levels.INFO)
end

vim.keymap.set({ "n", "v" }, "<leader>cp", copy_filepath, { desc = "[C]opy file[p]ath to clipboard" })

vim.keymap.set("i", "<M-y>", 'copilot#Accept("\\<CR>")', {
	expr = true,
	replace_keycodes = false,
})
vim.g.copilot_no_tab_map = true

