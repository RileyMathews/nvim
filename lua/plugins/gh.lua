return {
    {
        "ldelossa/gh.nvim",
        dependencies = {
            {
                "ldelossa/litee.nvim",
                config = function()
                    require("litee.lib").setup()
                end,
            },
        },
        config = function()
            require("litee.gh").setup()
        end,
    },
    { "gh-tui-tools/gh-review.nvim" },
    {
        "pwntester/octo.nvim",
        cmd = "Octo",
        opts = {
            -- or "fzf-lua" or "snacks" or "default"
            picker = "snacks",
            -- bare Octo command opens picker of commands
            enable_builtin = true,
        },
        keys = {
            {
                "<leader>oi",
                "<CMD>Octo issue list<CR>",
                desc = "List GitHub Issues",
            },
            {
                "<leader>op",
                "<CMD>Octo pr list<CR>",
                desc = "List GitHub PullRequests",
            },
            {
                "<leader>od",
                "<CMD>Octo discussion list<CR>",
                desc = "List GitHub Discussions",
            },
            {
                "<leader>on",
                "<CMD>Octo notification list<CR>",
                desc = "List GitHub Notifications",
            },
            {
                "<leader>os",
                function()
                    require("octo.utils").create_base_search_command { include_current_repo = true }
                end,
                desc = "Search GitHub",
            },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            -- "nvim-telescope/telescope.nvim",
            -- OR "ibhagwan/fzf-lua",
            "folke/snacks.nvim",
            "nvim-tree/nvim-web-devicons",
        },
    },
    {
        dir ='~/code/ghlite',
        dependencies = { 'sindrets/diffview.nvim' },
        lazy = false,
        config = function()
            local ghlite = require('ghlite')

            ghlite.setup({
                debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
                view_split = '', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
                diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto' - which tool to use for ghlite.load_pr_diffview()
                comment_split = 'split', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
                open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
                html_comments_command = { 'lynx', '-stdin', '-dump' }, -- command to render HTML comments in PR view
            })

            vim.keymap.set('n', '<leader>uv', ghlite.load_pr_view, { silent = true, desc = 'PR View' })
            vim.keymap.set('n', '<leader>uu', ghlite.load_comments, { silent = true, desc = 'PR Load Comments' })
            vim.keymap.set('n', '<leader>ul', ghlite.load_pr_diffview, { silent = true, desc = 'PR Diffview' })
            vim.keymap.set('n', '<leader>up', function()
                local pr_number = tonumber(vim.fn.input('PR number: '))
                if pr_number ~= nil then
                    ghlite.open_pr(pr_number)
                end
            end, { silent = true, desc = 'Open PR by number' })
            vim.keymap.set('n', '<leader>ua', ghlite.approve_pr, { silent = true, desc = 'PR Approve' })
            vim.keymap.set('n', '<leader>ur', ghlite.request_changes_pr, { silent = true, desc = 'PR Request changes' })
            vim.keymap.set('n', '<leader>uc', ghlite.comment_on_pr, { silent = true, desc = 'PR top-level comment' })
            vim.keymap.set('n', '<leader>um', ghlite.comment_on_line, { silent = true, desc = 'PR Add comment' })
            vim.keymap.set('x', '<leader>um', ghlite.comment_on_line, { silent = true, desc = 'PR Add comment' })
            vim.keymap.set('n', '<leader>ue', ghlite.update_comment, { silent = true, desc = 'PR Update comment' })
            vim.keymap.set('n', '<leader>ud', ghlite.delete_comment, { silent = true, desc = 'PR Delete comment' })
            vim.keymap.set('n', '<leader>ug', ghlite.open_comment, { silent = true, desc = 'PR Open comment' })
        end,
    }
}

