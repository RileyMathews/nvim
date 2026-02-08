-- PR Review Comments - Virtual text and floating window display

local M = {}

local pr_review = nil
local shared_render = nil

local function get_pr_review()
  if not pr_review then
    pr_review = require("custom.pr_review")
  end
  return pr_review
end

local function get_shared_render()
  if not shared_render then
    shared_render = require("custom.pr_shared.comments_render")
  end
  return shared_render
end

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("pr_review_comments")

-- Display options
local display_opts = {
  show_resolved = true,
  show_outdated = true,
}

-- Toggle resolved visibility
function M.toggle_resolved()
  display_opts.show_resolved = not display_opts.show_resolved
  M.render()
  local status = display_opts.show_resolved and "shown" or "hidden"
  Snacks.notify.info("Resolved comments now " .. status, { title = "PR Review" })
end

-- Toggle outdated visibility
function M.toggle_outdated()
  display_opts.show_outdated = not display_opts.show_outdated
  M.render()
  local status = display_opts.show_outdated and "shown" or "hidden"
  Snacks.notify.info("Outdated comments now " .. status, { title = "PR Review" })
end

-- Get threads for a specific file
---@param file_path string
---@return PRReview.ReviewThread[]
local function get_file_threads(file_path)
  local state = get_pr_review().get_state()
  local threads = {}

  for _, thread in ipairs(state.threads or {}) do
    if thread.path == file_path then
      -- Apply visibility filters
      local show = true
      if not display_opts.show_resolved and thread.resolved then
        show = false
      end
      if not display_opts.show_outdated and thread.outdated and not thread.resolved then
        show = false
      end

      if show then
        table.insert(threads, thread)
      end
    end
  end

  return threads
end

-- Get threads at a specific line
---@param file_path string
---@param line number
---@param side string
---@return PRReview.ReviewThread[]
local function get_threads_at_line(file_path, line, side)
  local threads = get_file_threads(file_path)
  local result = {}

  for _, thread in ipairs(threads) do
    local thread_line = thread.line or thread.start_line
    local thread_side = thread.diff_side or "right"

    if thread_line == line and thread_side:lower() == side:lower() then
      table.insert(result, thread)
    end
  end

  return result
end

-- Render comment indicators as virtual text
function M.render()
  local state = get_pr_review().get_state()

  -- Clear existing marks
  for _, side in ipairs({ "left", "right" }) do
    local buf = state.diff_buffers[side]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    end
  end

  -- Get current file
  local right_buf = state.diff_buffers.right
  if not right_buf or not vim.api.nvim_buf_is_valid(right_buf) then
    return
  end

  local file_path = vim.b[right_buf].pr_review_file
  if not file_path then
    return
  end

  -- Get threads for this file
  local threads = get_file_threads(file_path)

  -- Group threads by line and side
  local by_line = {
    left = {},
    right = {},
  }

  for _, thread in ipairs(threads) do
    local line = thread.line or thread.start_line
    local side = (thread.diff_side or "right"):lower()

    if line and by_line[side] then
      by_line[side][line] = by_line[side][line] or {}
      table.insert(by_line[side][line], thread)
    end
  end

  -- Render for each side
  for side, lines in pairs(by_line) do
    local buf = state.diff_buffers[side]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local line_count = vim.api.nvim_buf_line_count(buf)

      for line, line_threads in pairs(lines) do
        if line <= line_count then
          M.render_line_indicator(buf, line, line_threads)
        end
      end
    end
  end
end

-- Render indicator for a single line
---@param buf number
---@param line number
---@param threads PRReview.ReviewThread[]
function M.render_line_indicator(buf, line, threads)
  get_shared_render().render_line_indicator({
    buf = buf,
    line = line,
    threads = threads,
    ns_id = ns_id,
    extmarks_key = "pr_review_extmarks",
    store_threads = true,
  })
end

-- Show floating window with full comment details
function M.show_floating()
  local state = get_pr_review().get_state()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = cursor[1]

  local file_path = vim.b[buf].pr_review_file
  local side = vim.b[buf].pr_review_side

  if not file_path or not side then
    Snacks.notify.info("Not in a PR review buffer", { title = "PR Review" })
    return
  end

  -- Get threads at this line
  local threads = get_threads_at_line(file_path, line, side)

  if #threads == 0 then
    Snacks.notify.info("No comments on this line", { title = "PR Review" })
    return
  end

  get_shared_render().show_floating({
    threads = threads,
    file_path = file_path,
    line = line,
    side = side,
    notify_title = "PR Review",
    on_reply = function(ctx)
      require("custom.pr_review.actions").reply_to_thread_at(ctx.file_path, ctx.line, ctx.side)
    end,
  })
end

-- Get comment thread at cursor position (for actions)
---@return PRReview.ReviewThread?, PRReview.Comment?
function M.get_thread_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = cursor[1]

  local file_path = vim.b[buf].pr_review_file
  local side = vim.b[buf].pr_review_side

  if not file_path or not side then
    return nil, nil
  end

  local threads = get_threads_at_line(file_path, line, side)
  if #threads == 0 then
    return nil, nil
  end

  -- Return the first thread and its first comment (for reply)
  local thread = threads[1]
  local comment = thread.comments[#thread.comments] -- last comment for reply

  return thread, comment
end

return M
