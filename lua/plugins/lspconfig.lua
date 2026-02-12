return {
	"neovim/nvim-lspconfig",
	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
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
		require("mason").setup()
		require("mason-lspconfig").setup({
			ensure_installed = {},
			automatic_enable = true,
		})

		-- This bit is for servers not managed via mason
		local manual_servers = {
			-- overriding hls to start static-ls instead
			hls = {
				cmd = { "static-ls", "--lsp" },
			},
			-- gdscript lsp is started by the godot editor itself
			-- this just lets neovim know its there when I want
			-- to edit files in neovim
			gdscript = {},
			-- I install djlsp via mason but have had trouble figuring out
			-- how to get it running automatically without also adding it here :(
			djlsp = {},
			gopls = {},
			zls = {},
			lua_ls = { cmd = { "lua-lsp" } },
			pyright = {},
			vtsls = {},
		}

		for server_name, server_settings in pairs(manual_servers) do
			vim.lsp.config(server_name, server_settings)
			vim.lsp.enable(server_name)
		end
	end,
}
