return {
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		opts = {
			columns = { "icon" },
			view_options = {
				show_hidden = true,
			},
			skip_confirm_for_simple_edits = true,
		},
		keys = { { "<leader>-", "<cmd>Oil --float<CR>", desc = "Toggle oil" } },
	},
}
