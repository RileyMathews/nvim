-- GitHub PR Comments Plugin

local M = {}

local state = require("custom.pr_comments.state")
local actions = require("custom.pr_comments.actions")
local navigation = require("custom.pr_comments.navigation")

---@class PRComments.API
---@field show fun()
---@field hide fun()
---@field refresh fun()
---@field toggle fun()
---@field toggle_resolved fun()
---@field toggle_outdated fun()
---@field view fun()
---@field reply fun()
---@field next fun()
---@field prev fun()

---@param user_config? table
---@return PRComments.API
M.setup = function(user_config)
  state.init(user_config)

  vim.api.nvim_create_user_command("PRCommentsShow", actions.show_pr_comments, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsHide", actions.hide_pr_comments, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsRefresh", actions.refresh_pr_comments, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsToggle", actions.toggle_pr_comments, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsToggleResolved", actions.toggle_resolved, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsToggleOutdated", actions.toggle_outdated, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsView", actions.view_thread_at_cursor, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsReply", actions.reply_thread_at_cursor, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsNext", navigation.jump_to_next_thread, { nargs = 0 })
  vim.api.nvim_create_user_command("PRCommentsPrev", navigation.jump_to_prev_thread, { nargs = 0 })

  return {
    show = actions.show_pr_comments,
    hide = actions.hide_pr_comments,
    refresh = actions.refresh_pr_comments,
    toggle = actions.toggle_pr_comments,
    toggle_resolved = actions.toggle_resolved,
    toggle_outdated = actions.toggle_outdated,
    view = actions.view_thread_at_cursor,
    reply = actions.reply_thread_at_cursor,
    next = navigation.jump_to_next_thread,
    prev = navigation.jump_to_prev_thread,
  }
end

return M
