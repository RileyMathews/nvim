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
		dir ='~/code/ghlite',
		dependencies = { 'sindrets/diffview.nvim' },
		lazy = false,
		config = function()
			local ghlite = require('ghlite')

			ghlite.setup({
				debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
				view_split = '', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
				diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto' - which tool to use for ghlite.load_pr_diffview()
				comment_split = 'split', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
				open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
				html_comments_command = { 'lynx', '-stdin', '-dump' }, -- command to render HTML comments in PR view
			})

			vim.keymap.set('n', '<leader>uv', ghlite.load_pr_view, { silent = true, desc = 'PR View' })
			vim.keymap.set('n', '<leader>uu', ghlite.load_comments, { silent = true, desc = 'PR Load Comments' })
			vim.keymap.set('n', '<leader>ul', ghlite.load_pr_diffview, { silent = true, desc = 'PR Diffview' })
			vim.keymap.set('n', '<leader>up', function()
				local pr_number = tonumber(vim.fn.input('PR number: '))
				if pr_number ~= nil then
					ghlite.open_pr(pr_number)
				end
			end, { silent = true, desc = 'Open PR by number' })
			vim.keymap.set('n', '<leader>ua', ghlite.approve_pr, { silent = true, desc = 'PR Approve' })
			vim.keymap.set('n', '<leader>ur', ghlite.request_changes_pr, { silent = true, desc = 'PR Request changes' })
			vim.keymap.set('n', '<leader>uc', ghlite.comment_on_pr, { silent = true, desc = 'PR top-level comment' })
			vim.keymap.set('n', '<leader>um', ghlite.comment_on_line, { silent = true, desc = 'PR Add comment' })
			vim.keymap.set('x', '<leader>um', ghlite.comment_on_line, { silent = true, desc = 'PR Add comment' })
			vim.keymap.set('n', '<leader>ue', ghlite.update_comment, { silent = true, desc = 'PR Update comment' })
			vim.keymap.set('n', '<leader>ud', ghlite.delete_comment, { silent = true, desc = 'PR Delete comment' })
			vim.keymap.set('n', '<leader>ug', ghlite.open_comment, { silent = true, desc = 'PR Open comment' })
		end,
	},
	{ "tpope/vim-fugitive" }
}
