return {
	"saghen/blink.cmp",
	version = "1.*",
	---@module 'blink.cmp'
	---@type blink.cmp.Config
	dependencies = {
		"saghen/blink.compat",
	},
	opts = {
		appearance = {
			nerd_font_variant = "mono",
		},

		signature = {
			enabled = true,
		},

		completion = { documentation = { auto_show = true, auto_show_delay = 250, } },
		fuzzy = { implementation = "rust" },
		sources = {
			default = { "lsp", "path", "buffer" },
		},
		cmdline = {
			completion = {
				menu = {
					auto_show = true,
				},
			},
		},

		keymap = {
			preset = "default",
			-- blink doesn't seem to bring up
			-- signature help by default when
			-- accepting a suggestion
			-- this override does that.
			["<C-y>"] = {
				function(cmp)
					return cmp.select_and_accept({
						callback = function()
							vim.schedule(function()
								cmp.show_signature()
							end)
						end,
					})
				end,
				"fallback",
			},
		}
	},
	opts_extend = { "sources.default" },
}
