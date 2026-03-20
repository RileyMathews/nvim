return {
	-- Highlight, edit, and navigate code
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	dependencies = {
		{ "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
		"RRethy/nvim-treesitter-endwise",
		-- "windwp/nvim-ts-autotag",
		-- "windwp/nvim-autopairs",
	},
	build = ":TSUpdate",
	lazy = false,
	config = function()
		local filetypes = {
			'bash',
			'c',
			'diff',
			'html',
			'lua',
			'luadoc',
			'markdown',
			'markdown_inline',
			'query',
			'vim',
			'vimdoc',
			'python',
			'haskell',
			'zsh',
			'nix',
			'typescript',
			'javascript',
			'go',
			'nu',
		}
		require("nvim-treesitter").install(filetypes)
		vim.api.nvim_create_autocmd('FileType', {
			pattern = filetypes,
			callback = function(args)
				local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
				if lang then
					local ok, err = pcall(vim.treesitter.start, args.buf, lang)
					if not ok then
						vim.notify("Treesitter failed for " .. lang .. ": " .. tostring(err), vim.log.levels.ERROR)
					end
				end
			end,
		})
		require("nvim-treesitter-textobjects").setup({
			select = {
				-- Automatically jump forward to textobj, similar to targets.vim
				lookahead = true,
				-- You can choose the select mode (default is charwise 'v')
				--
				-- Can also be a function which gets passed a table with the keys
				-- * query_string: eg '@function.inner'
				-- * method: eg 'v' or 'o'
				-- and should return the mode ('v', 'V', or '<c-v>') or a table
				-- mapping query_strings to modes.
				selection_modes = {
					['@parameter.outer'] = 'v', -- charwise
					['@function.outer'] = 'V', -- linewise
					-- ['@class.outer'] = '<c-v>', -- blockwise
				},
				include_surrounding_whitespace = false,
			},

		})
	end,
}
