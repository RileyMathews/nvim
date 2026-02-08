vim.g.mapleader = " "

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

vim.opt.signcolumn = "yes"

vim.opt.wrap = false

vim.opt.hlsearch = true
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")
vim.opt.incsearch = true

vim.opt.smartcase = true
vim.opt.ignorecase = true

vim.opt.termguicolors = true

vim.opt.swapfile = false

vim.opt.scrolloff = 8

vim.opt.foldlevelstart = 99
vim.opt.foldlevel = 99
vim.opt.foldmethod = "manual"

vim.opt.showmode = false

vim.diagnostic.config({
	virtual_text = true,
	float = {
		focusable = false,
		style = "minimal",
		border = "rounded",
		header = "",
		prefix = "",
	},
})
vim.api.nvim_create_autocmd("FileType", {
	pattern = "*",
	desc = "Disable formatoptions for certain file types",
	group = vim.api.nvim_create_augroup("format-options-group", { clear = true }),
	callback = function()
		vim.opt_local.formatoptions:remove({ "r", "o", "c" })
	end,
})

vim.opt.linebreak = true

vim.opt.undofile = true

vim.g.db_ui_execute_on_save = 0

vim.g.copilot_filetypes = {
	["odin"] = false,
}

vim.api.nvim_create_autocmd("FileType", {
	pattern = "sql",
	group = vim.api.nvim_create_augroup("DBUI_Keymaps", {}),
	callback = function(ev)
		local opts = { buffer = ev.buf, silent = true }
		vim.keymap.set({ "n", "v" }, "<leader>r", "<Plug>(DBUI_ExecuteQuery)", opts)
	end,
})
