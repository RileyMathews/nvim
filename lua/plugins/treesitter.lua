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
				-- If you set this to `true` (default is `false`) then any textobject is
				-- extended to include preceding or succeeding whitespace. Succeeding
				-- whitespace has priority in order to act similarly to eg the built-in
				-- `ap`.
				--
				-- Can also be a function which gets passed a table with the keys
				-- * query_string: eg '@function.inner'
				-- * selection_mode: eg 'v'
				-- and should return true of false
				include_surrounding_whitespace = false,
			},

		})
		-- require("nvim-treesitter").setup({
			-- 	sync_install = false,
			-- 	ignore_install = {},
			-- 	ensure_installed = {},
			-- 	modules = {},
			-- 	auto_install = true,
			-- 	highlight = {
				-- 		enable = true,
				-- 		disable = function(_, buf)
					-- 			local max_filesize = 100 * 1024 -- 100 KB
					-- 			local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
					-- 			if ok and stats and stats.size > max_filesize then
					-- 				return true
					-- 			end
					-- 		end,
					-- 	},
					-- 	indent = { enable = true },
					-- 	endwise = { enable = true },
					-- 	textobjects = {
						-- 		select = {
							-- 			enable = true,
							--
							-- 			-- Automatically jump forward to textobj, similar to targets.vim
							-- 			lookahead = true,
							--
							-- 			keymaps = {
								-- 				-- You can use the capture groups defined in textobjects.scm
								-- 				["af"] = "@function.outer",
								-- 				["if"] = "@function.inner",
								-- 				["ac"] = "@class.outer",
								-- 				-- You can optionally set descriptions to the mappings (used in the desc parameter of
								-- 				-- nvim_buf_set_keymap) which plugins like which-key display
								-- 				["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
								-- 				-- You can also use captures from other query groups like `locals.scm`
								-- 				["as"] = { query = "@local.scope", query_group = "locals", desc = "Select language scope" },
								-- 			},
								-- 			-- You can choose the select mode (default is charwise 'v')
								-- 			--
								-- 			-- Can also be a function which gets passed a table with the keys
								-- 			-- * query_string: eg '@function.inner'
								-- 			-- * method: eg 'v' or 'o'
								-- 			-- and should return the mode ('v', 'V', or '<c-v>') or a table
								-- 			-- mapping query_strings to modes.
								-- 			selection_modes = {
									-- 				["@parameter.outer"] = "v", -- charwise
									-- 				["@function.outer"] = "V", -- linewise
									-- 				["@class.outer"] = "<c-v>", -- blockwise
									-- 			},
									-- 			-- If you set this to `true` (default is `false`) then any textobject is
									-- 			-- extended to include preceding or succeeding whitespace. Succeeding
									-- 			-- whitespace has priority in order to act similarly to eg the built-in
									-- 			-- `ap`.
									-- 			--
									-- 			-- Can also be a function which gets passed a table with the keys
									-- 			-- * query_string: eg '@function.inner'
									-- 			-- * selection_mode: eg 'v'
									-- 			-- and should return true or false
									-- 			include_surrounding_whitespace = true,
									-- 		},
									-- 	},
									-- })
									-- -- require("nvim-ts-autotag").setup()
									-- -- require("nvim-autopairs").setup()
								end,
							}
