return { -- Autoformat
	"stevearc/conform.nvim",
	opts = {
		notify_on_error = true,
		formatters_by_ft = {
			lua = { "stylua" },
			-- Conform can also run multiple formatters sequentially
			python = { "ruff_format", "ruff_fix" },
			--
			-- You can use a sub-list to tell conform to run *until* a formatter
			-- is found.
			javascript = { "prettier" },
			typescript = { "prettier" },
			javascriptreact = { "prettier" },
			css = { "prettier" },
			typescriptreact = { "prettier" },
			scss = { "prettier" },
			haskell = { "fourmolu" },
			sql = { "sleek" },
		},
	},
}
