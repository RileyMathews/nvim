return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		"nvim-neotest/neotest-jest",
	},
	keys = {
		{ "<leader>tn", "<cmd>lua require('neotest').run.run()<CR>", desc = "[T]est [N]earest" },
		{ "<leader>to", "<cmd>lua require('neotest').output.open()<CR>", desc = "[T]est [O]pen output" },
		{ "<leader>tf", "<cmd>lua require('neotest').run.run(vim.fn.expand('%'))<CR>", desc = "[T]est [F]ile" },
		{ "<leader>td", "<cmd>lua require('neotest').run.run({ strategy = 'dap' })<CR>", desc = "[T]est [D]ebug" },
		{ "<leader>ts", "<cmd>lua require('neotest').run.run({ suite = true })<CR>", desc = "[T]est [A]ll" },
		{ "<leader>tl", "<cmd>lua require('neotest').run.run_last()<CR>", desc = "[T]est [L]ast" },
		{ "<leader>tb", "<cmd>lua require('neotest').summary.toggle()<CR>", desc = "[T]est [B]reakdown" },
	},
	config = function()
		local neotest = require("neotest")
		neotest.setup({
			adapters = {
				require("neotest-jest")({
					jest_test_discovery = false,
					env = {
						NODE_ENV = "test",
					},
				}),
			},
		})
	end,
}
