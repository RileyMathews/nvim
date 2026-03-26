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
            require('ghlite').setup({
                debug = false, -- if set to true debugging information is written to ~/.ghlite.log file
                view_split = '', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
                diff_split = 'diffview', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
                diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto' - which tool to use for GHLitePRDiffview
                comment_split = 'split', -- set to empty string '' to open in active buffer, use 'tabnew' to open in tab
                open_command = 'open', -- open command to use, e.g. on Linux you might want to use xdg-open
                merge = {
                    approved = '--squash',
                    nonapproved = '--auto --squash',
                },
                html_comments_command = { 'lynx', '-stdin', '-dump' }, -- command to render HTML comments in PR view
                -- override default keymaps with the ones you prefer
                -- set keymap to false or '' to disable it
                keymaps = {
                    diff = {
                        open_file = 'gf',
                        open_file_tab = '',
                        open_file_split = 'o',
                        open_file_vsplit = 'O',
                        approve = 'cA',
                        request_changes = 'cR',
                    },
                    comment = {
                        send_comment = 'c<CR>' -- this one cannot be disabled
                    },
                    pr = {
                        approve = 'cA',
                        request_changes = 'cR',
                        merge = 'cM',
                        comment = 'ca',
                        diff = 'cp',
                    },
                },
            })
        end,
        keys = {
            { '<leader>us', ':GHLitePRSelect<cr>',        silent = true, desc = 'PR Select' },
            { '<leader>uo', ':GHLitePRCheckout<cr>',      silent = true, desc = 'PR Checkout' },
            { '<leader>uv', ':GHLitePRView<cr>',          silent = true, desc = 'PR View' },
            { '<leader>uu', ':GHLitePRLoadComments<cr>',  silent = true, desc = 'PR Load Comments' },
            { '<leader>up', ':GHLitePRDiff<cr>',          silent = true, desc = 'PR Diff' },
            { '<leader>ul', ':GHLitePRDiffview<cr>',      silent = true, desc = 'PR Diffview' },
            { '<leader>ua', ':GHLitePRAddComment<cr>',    silent = true, desc = 'PR Add comment' },
            { '<leader>ua', ':GHLitePRAddComment<cr>',    mode = 'x',    silent = true,             desc = 'PR Add comment' },
            { '<leader>uc', ':GHLitePRUpdateComment<cr>', silent = true, desc = 'PR Update comment' },
            { '<leader>ud', ':GHLitePRDeleteComment<cr>', silent = true, desc = 'PR Delete comment' },
            { '<leader>ug', ':GHLitePROpenComment<cr>',   silent = true, desc = 'PR Open comment' },
        }
    }
}

