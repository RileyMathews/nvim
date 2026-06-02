return {
	{ -- Adds git related signs to the gutter, as well as utilities for managing changes
		'lewis6991/gitsigns.nvim',
		---@module 'gitsigns'
		---@type Gitsigns.Config
		---@diagnostic disable-next-line: missing-fields
		opts = {
			attach_to_untracked = true,
			signs = {
				add = { text = '+' }, ---@diagnostic disable-line: missing-fields
				change = { text = '~' }, ---@diagnostic disable-line: missing-fields
				delete = { text = '_' }, ---@diagnostic disable-line: missing-fields
				topdelete = { text = '‾' }, ---@diagnostic disable-line: missing-fields
				changedelete = { text = '~' }, ---@diagnostic disable-line: missing-fields
			},
			on_attach = function()
				local gitsigns = require("gitsigns")
				vim.keymap.set("n", "<leader>gs", gitsigns.stage_hunk, { desc = "[S]tage"})
				local function map(mode, l, r, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, l, r, opts)
				end
				map('n', ']c', function()
					if vim.wo.diff then
						vim.cmd.normal({']c', bang = true})
					else
						gitsigns.nav_hunk('next')
					end
				end, { desc = "Next change" })

				map('n', '[c', function()
					if vim.wo.diff then
						vim.cmd.normal({'[c', bang = true})
					else
						gitsigns.nav_hunk('prev')
					end
				end, { desc = "Previosu change" })
			end
		},
	},
	{
		'sindrets/diffview.nvim',
		cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFocusFiles', 'DiffviewToggleFiles' },
	},

	{ "tpope/vim-fugitive" }
}
