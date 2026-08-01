return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{
			"folke/lazydev.nvim",
			ft = "lua",
			opts = {
				library = {
					-- See the configuration section for more details
					-- Load luvit types when the `vim.uv` word is found
					{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
					{ path = "snacks.nvim", words = { "Snacks" } },
				},
			},
		},
	},
	-- event = "BufReadPre",
	config = function()
		local manual_servers = {
			-- overriding hls to start static-ls instead
			hls = {
				cmd = { "static-ls", "--lsp" },
			},
			-- gdscript lsp is started by the godot editor itself
			-- this just lets neovim know its there when I want
			-- to edit files in neovim
			gdscript = {},
			djlsp = {},
			gopls = {},
			zls = {},
			lua_ls = {},
			pyright = {},
			clangd = {},
			rust_analyzer = {},
			ty = {},
			ols = {},
			tsc = {
				cmd = { "tsc", "--lsp", "--stdio" },
				filetypes = {
					"javascript",
					"javascriptreact",
					"typescript",
					"typescriptreact",
				},
				root_markers = {
					"package.json",
					"tsconfig.json",
					"jsconfig.json",
					".git",
				},
			},
			svelte = {},
			qmlls = {},
		}

		for server_name, server_settings in pairs(manual_servers) do
			server_settings.capabilities = require('blink.cmp').get_lsp_capabilities( {
				textDocument = {
					completion = {
						completionItem = {
							snippetSupport = false,
						},
					},
				},
			})
			vim.lsp.config(server_name, server_settings)
			vim.lsp.enable(server_name)
		end
	end,
}
