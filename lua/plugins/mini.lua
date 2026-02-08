return {
	"echasnovski/mini.nvim",
	config = function()
		require("mini.statusline").setup({
			use_icons = true,
		})
		-- require("mini.pairs").setup()
		require("mini.diff").setup({
			view = {
				style = "sign",
			},
		})
		require("mini.move").setup({
			mappings = {
				line_left = "",
				line_right = "",
				line_up = "",
				line_down = "",
				right = "L",
				left = "H",
				up = "K",
				down = "J",
			},
		})
	end,
}
