return {
	"folke/which-key.nvim",
	opts = {},
	event = "BufWinEnter",
	config = function()
		local wk = require("which-key")
		wk.add({
			{ "<leader>d", group = "[D]iagnostics" },
			{ "<leader>h", group = "[H]arpoon" },
			{ "<leader>s", group = "[S]earch" },
			{ "<leader>t", group = "[T]est" },
			{ "<leader>n", group = "[N]otifications" },
			{ "<leader>j", group = "[J]ump (flash)" },
			{ "<leader>o", group = "[O]pencode" },
			{ "<leader>r", group = "[R]eview" },
			{ "<leader>u", group = "ghlite.nvim" },
			{ "<leader>g", group = "[G]it" },
			{ "<leader>pr", group = "[P][R] comments" },
			{ "<leader>9", group = "[9]9" },
		})

		for i = 1, 5 do
			wk.add({
				{ "<leader>" .. i, hidden = true },
			})
		end
	end,
}
