local ctx = require("custom.pr_comments.state")
local threads = require("custom.pr_comments.threads")

local M = {}

---@param item PRComments.ThreadLocation
---@param direction "next"|"prev"
---@return boolean
local function jump_to_thread(item, direction)
  local repo_root = ctx.get_repo_root()
  if not repo_root then
    ctx.notify_error("Failed to get repository root")
    return false
  end

  local abs_path = repo_root .. "/" .. item.path
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = vim.api.nvim_buf_get_name(current_buf)

  if current_path ~= abs_path then
    vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
  end

  vim.api.nvim_win_set_cursor(0, { item.line, 0 })
  vim.cmd("normal! zz")

  local thread = item.thread
  local first_comment = thread.comments[1]
  local preview = first_comment.body:gsub("\n", " ")
  if #preview > 50 then
    preview = preview:sub(1, 50) .. "..."
  end

  local status_icon = thread.resolved and "✓" or "❗"
  ctx.notify_info(
    string.format("%s @%s: %s", status_icon, first_comment.author, preview),
    direction == "next" and "→" or "←"
  )

  return true
end

function M.jump_to_next_thread()
  ctx.ensure_setup()

  if not ctx.get_state().active then
    ctx.notify_info("No PR comments loaded. Run :PRCommentsShow first")
    return
  end

  local sorted_threads = threads.get_all_threads_sorted()
  if #sorted_threads == 0 then
    ctx.notify_info("No comment threads found")
    return
  end

  local index = ctx.get_current_thread_index()
  if not index then
    index = 1
  else
    index = index + 1
    if index > #sorted_threads then
      index = 1
    end
  end

  ctx.set_current_thread_index(index)
  jump_to_thread(sorted_threads[index], "next")
end

function M.jump_to_prev_thread()
  ctx.ensure_setup()

  if not ctx.get_state().active then
    ctx.notify_info("No PR comments loaded. Run :PRCommentsShow first")
    return
  end

  local sorted_threads = threads.get_all_threads_sorted()
  if #sorted_threads == 0 then
    ctx.notify_info("No comment threads found")
    return
  end

  local index = ctx.get_current_thread_index()
  if not index then
    index = #sorted_threads
  else
    index = index - 1
    if index < 1 then
      index = #sorted_threads
    end
  end

  ctx.set_current_thread_index(index)
  jump_to_thread(sorted_threads[index], "prev")
end

return M
