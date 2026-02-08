-- PR Review Actions - Comment and review workflow

local M = {}

local pr_review = nil
local api = nil
local diff_mod = nil
local comments_mod = nil
local compose_mod = nil

local function get_pr_review()
  if not pr_review then
    pr_review = require("custom.pr_review")
  end
  return pr_review
end

local function get_api()
  if not api then
    api = require("custom.pr_review.api")
  end
  return api
end

local function get_diff()
  if not diff_mod then
    diff_mod = require("custom.pr_review.diff")
  end
  return diff_mod
end

local function get_comments()
  if not comments_mod then
    comments_mod = require("custom.pr_review.comments")
  end
  return comments_mod
end

local function get_compose()
  if not compose_mod then
    compose_mod = require("custom.pr_shared.reply")
  end
  return compose_mod
end

-- Smart comment: determines whether to add line comment or reply
---@param visual? boolean Whether this was called from visual mode
function M.smart_comment(visual)
  if visual then
    -- Visual mode always creates a new comment on the selection
    M.add_line_comment_visual()
    return
  end

  local thread, comment = get_comments().get_thread_at_cursor()

  if thread and comment then
    -- There's a thread at cursor - offer to reply
    M.reply_to_thread()
  else
    -- No thread - add a new line comment
    M.add_line_comment()
  end
end

-- Smart comment from visual selection
function M.smart_comment_visual()
  M.smart_comment(true)
end

-- Add a general comment on the PR (not line-specific)
function M.add_general_comment()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  get_compose().run({
    title = "Comment on PR #" .. pr.number,
    notify_title = "PR Review",
    posting_message = "Posting comment...",
    success_message = "Comment posted",
    submit = function(body)
      return get_api().post_comment(pr, body)
    end,
    map_error = function(err)
      return "Failed to post comment: " .. (err or "unknown error")
    end,
    on_success = function()
      get_pr_review().refresh()
    end,
  })
end

-- Add a line comment at cursor position or visual selection
---@param visual? boolean Whether this was called from visual mode
function M.add_line_comment(visual)
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  local line_info = get_diff().get_line_info(visual)
  if not line_info then
    Snacks.notify.warn("Not on a diff line", { title = "PR Review" })
    return
  end

  -- Build title based on single line or range
  local title
  if line_info.start_line then
    title = string.format("Comment on %s:%d-%d", line_info.file, line_info.start_line, line_info.line)
  else
    title = string.format("Comment on %s:%d", line_info.file, line_info.line)
  end

  get_compose().run({
    title = title,
    notify_title = "PR Review",
    posting_message = "Posting line comment...",
    success_message = function()
      return state.pending_review and "Comment added to pending review" or "Comment posted"
    end,
    submit = function(body)
      local opts = {
        path = line_info.file,
        line = line_info.line,
        side = line_info.side,
        body = body,
        start_line = line_info.start_line,
      }

      -- Check if we have a pending review (use GraphQL ID for GraphQL mutation)
      if state.pending_review then
        return get_api().add_review_comment(pr, state.pending_review.id, opts)
      else
        return get_api().post_line_comment(pr, opts)
      end
    end,
    map_error = function(err)
      if state.pending_review then
        return "Failed to add comment: " .. (err or "unknown error")
      end
      return "Failed to post comment: " .. (err or "unknown error")
    end,
    on_success = function()
      get_pr_review().refresh()
    end,
  })
end

-- Add a line comment from visual selection
function M.add_line_comment_visual()
  -- Exit visual mode first so marks are set
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  -- Small delay to ensure marks are updated
  vim.schedule(function()
    M.add_line_comment(true)
  end)
end

-- Reply to the thread at cursor position
function M.reply_to_thread()
  local thread, comment = get_comments().get_thread_at_cursor()

  if not thread or not comment then
    Snacks.notify.info("No comment thread at cursor", { title = "PR Review" })
    return
  end

  -- Pass thread ID for GraphQL mutation (works with pending reviews)
  M.reply_to_comment(comment.database_id, thread.id)
end

-- Reply to a thread at a specific location
---@param file_path string
---@param line number
---@param side string
function M.reply_to_thread_at(file_path, line, side)
  local state = get_pr_review().get_state()

  -- Find the thread
  for _, thread in ipairs(state.threads) do
    if thread.path == file_path then
      local thread_line = thread.line or thread.start_line
      local thread_side = (thread.diff_side or "right"):lower()

      if thread_line == line and thread_side == side:lower() then
        local last_comment = thread.comments[#thread.comments]
        if last_comment then
          -- Pass thread ID for GraphQL mutation (works with pending reviews)
          M.reply_to_comment(last_comment.database_id, thread.id)
          return
        end
      end
    end
  end

  Snacks.notify.warn("Could not find thread to reply to", { title = "PR Review" })
end

-- Reply to a specific comment
---@param comment_id number -- database ID of comment
---@param thread_id string? -- GraphQL node ID of the thread
function M.reply_to_comment(comment_id, thread_id)
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  -- Check if we have a pending review - the GraphQL mutation works with pending reviews
  local has_pending = state.pending_review ~= nil
  local title = "Reply to comment"
  if has_pending then
    title = "Reply to comment (will be added to pending review)"
  end

  get_compose().run({
    title = title,
    notify_title = "PR Review",
    posting_message = "Posting reply...",
    success_message = has_pending and "Reply added to pending review" or "Reply posted",
    submit = function(body)
      return get_api().reply_to_comment(pr, comment_id, body, thread_id)
    end,
    map_error = function(err)
      if err and err:find("pending review") then
        return "Cannot reply: you have a pending review. Submit it first with <leader>rS"
      end
      return "Failed to post reply: " .. (err or "unknown error")
    end,
    on_success = function()
      get_pr_review().refresh()
    end,
  })
end

-- Start a new pending review
function M.start_review()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  if state.pending_review then
    -- Offer to submit or view the existing review
    Snacks.picker.select(
      { "Submit existing review", "Continue adding comments", "Cancel" },
      { title = "You already have a pending review" },
      function(choice, idx)
        if idx == 1 then
          M.submit_review()
        elseif idx == 2 then
          Snacks.notify.info("Add line comments with <leader>rl, then submit with <leader>rS", { title = "PR Review" })
        end
      end
    )
    return
  end

  Snacks.notify.info("Starting review...", { title = "PR Review" })

  local review_id, err = get_api().start_review(pr)
  if review_id then
    -- Refresh to get the pending review
    get_pr_review().refresh()
    Snacks.notify.info("Review started. Add comments, then submit when ready.", { title = "PR Review" })
  else
    -- Check if error is about existing review
    if err and err:find("pending review") then
      Snacks.notify.warn("You already have a pending review. Refreshing...", { title = "PR Review" })
      get_pr_review().refresh()
    else
      Snacks.notify.error("Failed to start review: " .. (err or "unknown error"), { title = "PR Review" })
    end
  end
end

-- Submit the pending review
function M.submit_review()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  if not state.pending_review then
    Snacks.notify.warn("No pending review to submit", { title = "PR Review" })
    return
  end

  -- Ask user for review type
  Snacks.picker.select(
    { "Approve", "Request Changes", "Comment" },
    {
      title = "Submit Review",
      format = function(item)
        local icons = {
          Approve = " ",
          ["Request Changes"] = " ",
          Comment = " ",
        }
        return { { icons[item] or "", "Special" }, { item } }
      end,
    },
    function(choice, idx)
      if not choice then
        return
      end

      local events = { "APPROVE", "REQUEST_CHANGES", "COMMENT" }
      local event = events[idx]

      -- Optionally add a review summary
      get_compose().run({
        title = "Review Summary (optional)",
        notify_title = "PR Review",
        template = "",
        allow_empty = true,
        posting_message = "Submitting review...",
        success_message = "Review submitted: " .. choice,
        submit = function(body)
          return get_api().submit_review(pr, tostring(state.pending_review.database_id), event, body)
        end,
        map_error = function(err)
          return "Failed to submit review: " .. (err or "unknown error")
        end,
        on_success = function()
          get_pr_review().refresh()
        end,
      })
    end
  )
end

-- Show available actions menu
function M.show_actions_menu()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  local actions = {
    { name = "Add Line Comment", action = M.add_line_comment, icon = " " },
    { name = "Add General Comment", action = M.add_general_comment, icon = " " },
    { name = "Reply to Thread", action = M.reply_to_thread, icon = " " },
  }

  -- Review workflow actions
  if state.pending_review then
    table.insert(actions, { name = "Submit Review", action = M.submit_review, icon = " " })
  else
    table.insert(actions, { name = "Start Review", action = M.start_review, icon = " " })
  end

  -- Navigation
  table.insert(actions, { name = "File Picker", action = get_pr_review().show_picker, icon = " " })
  table.insert(actions, { name = "Refresh Comments", action = get_pr_review().refresh, icon = " " })
  table.insert(actions, { name = "Close Review", action = get_pr_review().close, icon = " " })

  Snacks.picker.select(actions, {
    title = "PR Review Actions",
    format = function(item)
      return { { item.icon, "Special" }, { " " }, { item.name } }
    end,
  }, function(item)
    if item then
      item.action()
    end
  end)
end

return M
