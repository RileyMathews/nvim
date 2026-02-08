local ctx = require("custom.pr_comments.state")
local threads = require("custom.pr_comments.threads")

local M = {}

---@param bufnr? integer
function M.show_comments_for_buffer(bufnr)
  local state = ctx.get_state()
  local comments_render = ctx.get_comments_render()
  local ns_id = ctx.get_namespace_id()

  bufnr = bufnr or vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  vim.b[bufnr].pr_comments_extmarks = {}

  if not state.active then
    return
  end

  local rel_path = ctx.get_buffer_relative_path(bufnr)
  if not rel_path then
    return
  end

  local file_threads = threads.get_visible_threads_for_file(rel_path)
  if vim.tbl_isempty(file_threads) then
    return
  end

  local extmarks = {}
  for line_num, line_threads in pairs(file_threads) do
    local ok = comments_render.render_line_indicator({
      buf = bufnr,
      line = line_num,
      threads = line_threads,
      ns_id = ns_id,
      store_threads = false,
    })

    if ok then
      extmarks[line_num] = line_threads
    end
  end

  vim.b[bufnr].pr_comments_extmarks = extmarks
end

---@param bufnr? integer
local function clear_comments(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ctx.get_namespace_id(), 0, -1)
  vim.b[bufnr].pr_comments_extmarks = nil
end

local function rerender_loaded_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      M.show_comments_for_buffer(bufnr)
    end
  end
end

---@return boolean
local function load_comments()
  local state = ctx.get_state()
  local gh = ctx.get_gh()
  local comments_api = ctx.get_comments_api()

  ctx.notify_info("Loading PR comments...", "")

  local repo_info, err = gh.get_repo_info()
  if err then
    ctx.notify_error(err)
    return false
  end

  local pr_number, pr_err = gh.get_current_pr_number()
  if not pr_number then
    ctx.notify_error(pr_err or "No PR found for current branch")
    return false
  end

  local review_threads, fetch_err = comments_api.fetch_review_threads(repo_info.owner, repo_info.name, pr_number)
  if fetch_err then
    ctx.notify_error("Failed to fetch PR comments: " .. fetch_err)
    return false
  end

  state.threads = comments_api.group_threads_by_path_line(review_threads)
  state.pr_number = pr_number
  return true
end

function M.show_pr_comments()
  ctx.ensure_setup()
  local state = ctx.get_state()

  if state.active then
    ctx.notify_info("PR comments already active")
    return
  end

  if not load_comments() then
    return
  end

  state.active = true
  M.show_comments_for_buffer(vim.api.nvim_get_current_buf())

  local existing_group = ctx.get_augroup_id()
  if existing_group then
    vim.api.nvim_del_augroup_by_id(existing_group)
  end

  local augroup_id = vim.api.nvim_create_augroup("PRComments", { clear = true })
  ctx.set_augroup_id(augroup_id)

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup_id,
    callback = function()
      if ctx.get_state().active then
        M.show_comments_for_buffer(vim.api.nvim_get_current_buf())
      end
    end,
  })

  local counts = threads.count_threads()
  if counts.total == 0 then
    ctx.notify_info("No review comments found on PR #" .. state.pr_number, "✓")
    return
  end

  ctx.notify_info(
    string.format(
      "Loaded %d thread%s (%d unresolved) across %d file%s",
      counts.total,
      counts.total == 1 and "" or "s",
      counts.unresolved,
      counts.files,
      counts.files == 1 and "" or "s"
    ),
    "✓"
  )
end

function M.hide_pr_comments()
  ctx.ensure_setup()
  local state = ctx.get_state()

  if not state.active then
    ctx.notify_info("No PR comments currently shown")
    return
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      clear_comments(bufnr)
    end
  end

  local augroup_id = ctx.get_augroup_id()
  if augroup_id then
    vim.api.nvim_del_augroup_by_id(augroup_id)
    ctx.set_augroup_id(nil)
  end

  state.active = false
  state.threads = {}
  state.pr_number = nil
  ctx.reset_thread_cursor()

  ctx.notify_info("PR comments hidden", "✓")
end

function M.refresh_pr_comments()
  ctx.ensure_setup()

  if not ctx.get_state().active then
    ctx.notify_info("No PR comments to refresh. Use :PRCommentsShow first")
    return
  end

  M.hide_pr_comments()
  M.show_pr_comments()
end

function M.toggle_pr_comments()
  ctx.ensure_setup()

  if ctx.get_state().active then
    M.hide_pr_comments()
  else
    M.show_pr_comments()
  end
end

function M.toggle_resolved()
  ctx.ensure_setup()
  local state = ctx.get_state()

  if not state.active then
    ctx.notify_info("No PR comments currently shown")
    return
  end

  state.show_resolved = not state.show_resolved
  ctx.reset_thread_cursor()
  rerender_loaded_buffers()

  local status = state.show_resolved and "shown" or "hidden"
  ctx.notify_info("Resolved threads now " .. status, "✓")
end

function M.toggle_outdated()
  ctx.ensure_setup()
  local state = ctx.get_state()

  if not state.active then
    ctx.notify_info("No PR comments currently shown")
    return
  end

  state.show_outdated = not state.show_outdated
  ctx.reset_thread_cursor()
  rerender_loaded_buffers()

  local status = state.show_outdated and "shown" or "hidden"
  ctx.notify_info("Outdated threads now " .. status, "✓")
end

---@param thread_id string
---@param body string
---@return boolean, string?
local function post_thread_reply(thread_id, body)
  return ctx.get_comments_api().add_thread_reply(thread_id, body)
end

---@param thread PRComments.Thread
local function reply_to_thread(thread)
  if not thread or not thread.id then
    ctx.notify_error("Could not find thread id to reply")
    return
  end

  ctx.get_reply().reply({
    title = string.format("Reply on %s:%d", thread.path, thread.line),
    notify_title = "PR Comments",
    posting_message = "Posting reply...",
    success_message = "Reply posted",
    submit = function(body)
      return post_thread_reply(thread.id, body)
    end,
    map_error = function(err)
      if err and err:find("pending review") then
        return "Cannot reply: you have a pending review. Submit it from PR Review first"
      end
      return "Failed to post reply: " .. (err or "unknown error")
    end,
    on_success = function()
      M.refresh_pr_comments()
    end,
  })
end

---@param selected_threads PRComments.Thread[]
local function reply_to_threads(selected_threads)
  if #selected_threads == 1 then
    reply_to_thread(selected_threads[1])
    return
  end

  local options = {}
  local comments_render = ctx.get_comments_render()

  for i, thread in ipairs(selected_threads) do
    local first_comment = thread.comments and thread.comments[1] or nil
    local preview = first_comment and comments_render.truncate(first_comment.body, 50) or "thread"
    local status = thread.resolved and "resolved" or thread.outdated and "outdated" or "active"
    options[i] = string.format(
      "%d. (%s) @%s: %s",
      i,
      status,
      first_comment and first_comment.author or "unknown",
      preview
    )
  end

  Snacks.picker.select(options, { title = "Select thread to reply" }, function(_, idx)
    if idx and selected_threads[idx] then
      reply_to_thread(selected_threads[idx])
    end
  end)
end

function M.reply_thread_at_cursor()
  ctx.ensure_setup()

  local selected_threads, err = threads.get_threads_at_cursor()
  if err then
    ctx.notify_info(err)
    return
  end

  reply_to_threads(selected_threads)
end

function M.view_thread_at_cursor()
  ctx.ensure_setup()

  local selected_threads, err = threads.get_threads_at_cursor()
  if err then
    ctx.notify_info(err)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local file_path = ctx.get_buffer_relative_path(bufnr) or ""

  ctx.get_comments_render().show_floating({
    threads = selected_threads,
    file_path = file_path,
    line = line,
    side = "right",
    notify_title = "PR Comments",
    on_reply = function()
      reply_to_threads(selected_threads)
    end,
  })
end

return M
