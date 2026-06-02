local comments = require('ghlite.comments')
local config = require('ghlite.config')
local diff = require('ghlite.diff')
local pr_commands = require('ghlite.pr_commands')

--- @class GHLiteModule
local M = {}

local augroup = vim.api.nvim_create_augroup('GHLite', { clear = true })

M.open_pr = pr_commands.open_pr_by_number
M.load_pr_view = pr_commands.load_pr_view
M.submit_review = pr_commands.submit_review
M.create_review = pr_commands.create_review
M.comment_on_pr = pr_commands.comment_on_pr
M.load_comments = comments.load_comments
M.load_pr_diffview = diff.load_pr_diffview
M.comment_on_line = comments.comment_on_line
M.update_comment = comments.update_comment
M.open_comment = comments.open_comment
M.delete_comment = comments.delete_comment

--- @param user_config GHLiteUserConfig|nil
M.setup = function(user_config)
  config.setup(user_config)

  -- clear old autocmds each time before recreating them
  vim.api.nvim_clear_autocmds({ group = augroup })

  vim.api.nvim_create_autocmd('BufReadPost', {
    group = augroup,
    pattern = '*',
    callback = function(args)
      comments.load_comments_on_buffer(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = augroup,
    pattern = '*',
    callback = function(args)
      comments.load_comments_on_buffer(args.buf)
    end,
  })
end

return M
