require("custom.options")
require("custom.lazy_setup")
require("custom.keymaps")
require("custom.yank_highlight")
require("custom.hspec").setup()
require("custom.auto_commands")

local ghciwatch = require("custom.ghciwatch").setup()
local conform = require("conform")
local trouble = require("trouble")

-- PR Comments plugin setup
local pr_comments = require("custom.pr_comments").setup({
    use_fake_data = false, -- Use real GitHub API
})

local pr_review = require("custom.pr_review")


vim.keymap.set("n", "<leader>ro", pr_review.open, { desc = "Open Prs" })

vim.keymap.set("n", "<leader>prt", pr_comments.toggle, { desc = "Toggle" })
vim.keymap.set("n", "<leader>prr", pr_comments.toggle_resolved, { desc = "Toggle resolved" })
vim.keymap.set("n", "<leader>pro", pr_comments.toggle_outdated, { desc = "Toggle outdated" })
vim.keymap.set("n", "<leader>prf", pr_comments.refresh, { desc = "Refresh" })
vim.keymap.set("n", "<leader>prn", pr_comments.next, { desc = "Next" })
vim.keymap.set("n", "<leader>prp", pr_comments.prev, { desc = "Previous" })
vim.keymap.set("n", "<leader>prv", pr_comments.view, { desc = "Show" })

vim.keymap.set("n", "<leader>gs", ghciwatch.initialize)
vim.keymap.set("n", "<leader>gk", ghciwatch.deinitialize)
vim.keymap.set("n", "<leader>gw", ghciwatch.show_buffer)
vim.keymap.set("n", "<F1>", "<Nop>")
vim.keymap.set("i", "<F1>", "<Nop>")
vim.keymap.set("n", "<leader>cf", function()
	conform.format({ timeout_ms = 3000 })
end, { desc = "[F]ormat" })

vim.keymap.set("n", "<leader>dn", function()
	trouble.next(trouble.Window, {skip_groups = true, jump = true});
end)
vim.keymap.set("n", "<leader>dp", function()
	trouble.prev(trouble.Window, {skip_groups = true, jump = true});
end)
