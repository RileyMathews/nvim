-- PR Review - A GitHub PR reviewing tool for Neovim
-- Inspired by snacks.nvim gh module but with side-by-side diff views

local M = {}

---@class PRReview.State
---@field pr PRReview.PR?
---@field threads PRReview.ReviewThread[]
---@field reviews PRReview.Review[]
---@field pending_review PRReview.Review?
---@field diff_text string?
---@field files PRReview.DiffFile[]
---@field current_file_index number
---@field diff_buffers {left: number?, right: number?}
---@field diff_wins {left: number?, right: number?}
---@field original_win number?
---@field original_buf number?
---@field reviewed_files table<string, boolean>
---@field description_buf number?
---@field description_win number?

---@type PRReview.State
local state = {
  pr = nil,
  threads = {},
  reviews = {},
  pending_review = nil,
  diff_text = nil,
  files = {},
  current_file_index = 0,
  diff_buffers = { left = nil, right = nil },
  diff_wins = { left = nil, right = nil },
  original_win = nil,
  original_buf = nil,
  reviewed_files = {},
  description_buf = nil,
  description_win = nil,
}

-- Lazy load submodules
local api = nil
local picker = nil
local diff = nil
local comments = nil
local actions = nil
local loading = nil

local function get_api()
  if not api then
    api = require("custom.pr_review.api")
  end
  return api
end

local function get_picker()
  if not picker then
    picker = require("custom.pr_review.picker")
  end
  return picker
end

local function get_diff()
  if not diff then
    diff = require("custom.pr_review.diff")
  end
  return diff
end

local function get_comments()
  if not comments then
    comments = require("custom.pr_review.comments")
  end
  return comments
end

local function get_actions()
  if not actions then
    actions = require("custom.pr_review.actions")
  end
  return actions
end

local function get_loading()
  if not loading then
    loading = require("custom.pr_review.loading")
  end
  return loading
end

-- Get current state (for submodules)
function M.get_state()
  return state
end

-- Update state (for submodules)
---@param updates table
function M.update_state(updates)
  for k, v in pairs(updates) do
    state[k] = v
  end
end

-- Reset state
function M.reset_state()
  state = {
    pr = nil,
    threads = {},
    reviews = {},
    pending_review = nil,
    diff_text = nil,
    files = {},
    current_file_index = 0,
    diff_buffers = { left = nil, right = nil },
    diff_wins = { left = nil, right = nil },
    original_win = nil,
    original_buf = nil,
    reviewed_files = {},
    description_buf = nil,
    description_win = nil,
  }
end

-- Load PR data
---@param opts? {pr?: number, repo?: string}
---@param cb fun(success:boolean)
local function load_pr_data_async(opts, cb)
  opts = opts or {}
  local api_mod = get_api()
  local loader = get_loading().start({ stage = "Checking git status..." })
  local done = false

  local function finish(success)
    if done then
      return
    end
    done = true
    cb(success)
  end

  local function fail(message)
    loader.stop(false)
    if message then
      Snacks.notify.error(message, { title = "PR Review" })
    end
    finish(false)
  end

  -- Check git state first
  api_mod.is_git_clean_async(function(is_clean, clean_err)
    if clean_err then
      fail(clean_err)
      return
    end
    if not is_clean then
      fail("Git working directory is not clean.\nPlease commit or stash changes before reviewing a PR.")
      return
    end

    loader.update("Detecting PR...")

    local function on_pr(pr, err)
      if not pr then
        fail(err or "Failed to detect PR")
        return
      end

      state.pr = pr

      loader.update("Fetching PR refs...")
      local remaining = 2
      local function on_ref(ok, ref_name)
        if not ok then
          Snacks.notify.warn("Could not fetch " .. ref_name, { title = "PR Review" })
        end
        remaining = remaining - 1
        if remaining == 0 then
          loader.update("Fetching PR diff...")
          api_mod.fetch_diff_async(pr.number, pr.repo, function(diff_text, diff_err)
            if not diff_text then
              fail(diff_err or "Failed to fetch diff")
              return
            end

            state.diff_text = diff_text
            state.files = api_mod.parse_diff_files(diff_text)

            loader.update("Fetching comments...")
            api_mod.fetch_comments_async(pr, function(threads, reviews, pending)
              state.threads = threads or {}
              state.reviews = reviews or {}
              state.pending_review = pending
              loader.stop(true, "PR data loaded")
              finish(true)
            end)
          end)
        end
      end

      api_mod.fetch_ref_async(pr.base_ref, function(ok)
        on_ref(ok, "base ref: " .. pr.base_ref)
      end)
      api_mod.fetch_ref_async(pr.head_ref, function(ok)
        on_ref(ok, "head ref: " .. pr.head_ref)
      end)
    end

    if opts.pr then
      api_mod.get_pr_async(opts.pr, opts.repo, on_pr)
    else
      api_mod.get_current_pr_async(on_pr)
    end
  end)
end

-- Open PR review
---@param opts? {pr?: number, repo?: string}
local function open_loaded_pr(opts)
  opts = opts or {}

  -- Save original window/buffer
  state.original_win = vim.api.nvim_get_current_win()
  state.original_buf = vim.api.nvim_get_current_buf()

  -- Load PR data
  load_pr_data_async(opts, function(success)
    if not success then
      return
    end

    local pr = state.pr
    if not pr then
      return
    end

    -- Show success message
    local file_count = #state.files
    local thread_count = #state.threads
    local unresolved = 0
    for _, t in ipairs(state.threads) do
      if not t.resolved then
        unresolved = unresolved + 1
      end
    end

    Snacks.notify.info(
      string.format(
        "PR #%d: %s\n%d files changed, %d comment threads (%d unresolved)",
        pr.number,
        pr.title,
        file_count,
        thread_count,
        unresolved
      ),
      { title = "PR Review" }
    )

    -- Open PR description first
    M.open_description()
  end)
end

-- Open PR review by selecting from open PRs in repo
---@param opts? {repo?: string}
function M.open(opts)
  opts = opts or {}

  if opts.pr then
    open_loaded_pr(opts)
    return
  end

  get_picker().open_prs({ repo = opts.repo })
end

-- Open PR review for the current branch PR (legacy behavior)
---@param opts? {repo?: string}
function M.open_current(opts)
  open_loaded_pr(opts or {})
end

-- Refresh PR data (re-fetch comments)
function M.refresh()
  if not state.pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  local api_mod = get_api()
  local threads, reviews, pending = api_mod.fetch_comments(state.pr)
  state.threads = threads
  state.reviews = reviews
  state.pending_review = pending

  -- Re-render comments if diff view is open
  if state.diff_wins.right and vim.api.nvim_win_is_valid(state.diff_wins.right) then
    get_comments().render()
  end

  Snacks.notify.info("Comments refreshed", { title = "PR Review" })
end

-- Open file at index
---@param index number
function M.open_file(index)
  if index < 1 or index > #state.files then
    return
  end

  state.current_file_index = index
  local file = state.files[index]

  get_diff().open(file.path)
end

-- Go to next file
function M.next_file()
  local next_idx = state.current_file_index + 1
  if next_idx > #state.files then
    next_idx = 1 -- wrap around
  end
  M.open_file(next_idx)
end

-- Go to previous file
function M.prev_file()
  local prev_idx = state.current_file_index - 1
  if prev_idx < 1 then
    prev_idx = #state.files -- wrap around
  end
  M.open_file(prev_idx)
end

-- Check if a file is marked as reviewed
---@param path string
---@return boolean
function M.is_file_reviewed(path)
  return state.reviewed_files[path] == true
end

-- Mark the current file as reviewed and go to next unreviewed file
function M.mark_reviewed()
  if state.current_file_index < 1 or state.current_file_index > #state.files then
    Snacks.notify.warn("No file open", { title = "PR Review" })
    return
  end

  local current_file = state.files[state.current_file_index]
  state.reviewed_files[current_file.path] = true

  Snacks.notify.info("Marked as reviewed: " .. current_file.path, { title = "PR Review" })

  -- Find the next unreviewed file
  local next_idx = nil
  for i = 1, #state.files do
    -- Start from the file after current, wrapping around
    local idx = ((state.current_file_index - 1 + i) % #state.files) + 1
    local file = state.files[idx]
    if not state.reviewed_files[file.path] then
      next_idx = idx
      break
    end
  end

  if next_idx then
    M.open_file(next_idx)
  else
    Snacks.notify.info("All files have been reviewed!", { title = "PR Review" })
  end
end

-- Unmark the current file as reviewed
function M.unmark_reviewed()
  if state.current_file_index < 1 or state.current_file_index > #state.files then
    Snacks.notify.warn("No file open", { title = "PR Review" })
    return
  end

  local current_file = state.files[state.current_file_index]
  state.reviewed_files[current_file.path] = nil

  Snacks.notify.info("Unmarked: " .. current_file.path, { title = "PR Review" })
end

-- Toggle reviewed status of current file
function M.toggle_reviewed()
  if state.current_file_index < 1 or state.current_file_index > #state.files then
    Snacks.notify.warn("No file open", { title = "PR Review" })
    return
  end

  local current_file = state.files[state.current_file_index]
  if state.reviewed_files[current_file.path] then
    M.unmark_reviewed()
  else
    M.mark_reviewed()
  end
end

-- Show file picker
function M.show_picker()
  get_picker().open()
end

-- Open PR description buffer
function M.open_description()
  local pr = state.pr
  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  -- Close any existing description buffer
  if state.description_buf and vim.api.nvim_buf_is_valid(state.description_buf) then
    vim.api.nvim_buf_delete(state.description_buf, { force = true })
  end

  local content = pr.body
  if not content or content == "" then
    content = "_No PR description provided._"
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_set_name(buf, string.format("pr://%d/description", pr.number))
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"

  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = false
  vim.wo[win].winbar = string.format(" PR #%d: %s ", pr.number, pr.title)

  state.description_buf = buf
  state.description_win = win

  local opts = { buffer = buf, silent = true }
  vim.keymap.set("n", "<leader>rp", M.show_picker, vim.tbl_extend("force", opts, { desc = "File picker" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close review" }))
  vim.keymap.set("n", "<leader>rq", M.close, vim.tbl_extend("force", opts, { desc = "Close review" }))
end

-- Close the review session
function M.close()
  get_diff().close()

  if state.description_buf and vim.api.nvim_buf_is_valid(state.description_buf) then
    vim.api.nvim_buf_delete(state.description_buf, { force = true })
  end

  if state.original_win and vim.api.nvim_win_is_valid(state.original_win) then
    if state.original_buf and vim.api.nvim_buf_is_valid(state.original_buf) then
      vim.api.nvim_win_set_buf(state.original_win, state.original_buf)
    end
    vim.api.nvim_set_current_win(state.original_win)
  end

  M.reset_state()
  get_api().clear_cache()
end

-- Comment actions (delegated to actions module)
function M.comment()
  get_actions().smart_comment()
end

function M.comment_visual()
  get_actions().smart_comment_visual()
end

function M.add_line_comment()
  get_actions().add_line_comment()
end

function M.add_line_comment_visual()
  get_actions().add_line_comment_visual()
end

function M.add_general_comment()
  get_actions().add_general_comment()
end

function M.reply()
  get_actions().reply_to_thread()
end

-- Review workflow
function M.start_review()
  get_actions().start_review()
end

function M.submit_review()
  get_actions().submit_review()
end

-- Show comment details at cursor
function M.show_comment_details()
  get_comments().show_floating()
end

-- Toggle comment visibility
function M.toggle_resolved()
  get_comments().toggle_resolved()
end

-- Show current review status
function M.show_status()
  local pr = state.pr
  if not pr then
    Snacks.notify.info("No PR loaded", { title = "PR Review" })
    return
  end

  local status_lines = {
    string.format("PR #%d: %s", pr.number, pr.title),
    string.format("Files: %d changed", #state.files),
    string.format("Threads: %d total", #state.threads),
  }

  if state.pending_review then
    local comment_count = #state.pending_review.comments
    table.insert(status_lines, "")
    table.insert(status_lines, string.format("PENDING REVIEW: %d comments", comment_count))
    table.insert(status_lines, "Submit with <leader>rS")
  else
    table.insert(status_lines, "")
    table.insert(status_lines, "No pending review")
    table.insert(status_lines, "Start one with <leader>rs")
  end

  Snacks.notify.info(table.concat(status_lines, "\n"), { title = "PR Review Status" })
end

-- Setup keymaps for diff view
function M.setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true }

  -- Navigation
  vim.keymap.set("n", "]f", M.next_file, vim.tbl_extend("force", opts, { desc = "Next file" }))
  vim.keymap.set("n", "[f", M.prev_file, vim.tbl_extend("force", opts, { desc = "Previous file" }))
  vim.keymap.set("n", "<leader>rp", M.show_picker, vim.tbl_extend("force", opts, { desc = "File picker" }))

  -- Comments (normal mode)
  vim.keymap.set("n", "<leader>rc", M.comment, vim.tbl_extend("force", opts, { desc = "Add comment (smart)" }))
  vim.keymap.set("n", "<leader>rl", M.add_line_comment, vim.tbl_extend("force", opts, { desc = "Add line comment" }))
  vim.keymap.set("n", "<leader>rg", M.add_general_comment, vim.tbl_extend("force", opts, { desc = "Add general comment" }))
  vim.keymap.set("n", "<leader>rr", M.reply, vim.tbl_extend("force", opts, { desc = "Reply to thread" }))
  vim.keymap.set("n", "K", M.show_comment_details, vim.tbl_extend("force", opts, { desc = "Show comment details" }))

  -- Comments (visual mode - for multi-line comments)
  vim.keymap.set("v", "<leader>rc", M.comment_visual, vim.tbl_extend("force", opts, { desc = "Comment on selection" }))
  vim.keymap.set("v", "<leader>rl", M.add_line_comment_visual, vim.tbl_extend("force", opts, { desc = "Comment on selection" }))

  -- Review workflow
  vim.keymap.set("n", "<leader>rs", M.start_review, vim.tbl_extend("force", opts, { desc = "Start review" }))
  vim.keymap.set("n", "<leader>rS", M.submit_review, vim.tbl_extend("force", opts, { desc = "Submit review" }))

  -- Refresh and close
  vim.keymap.set("n", "<leader>rR", M.refresh, vim.tbl_extend("force", opts, { desc = "Refresh comments" }))
  vim.keymap.set("n", "<leader>rq", M.close, vim.tbl_extend("force", opts, { desc = "Close review" }))
  vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close review" }))

  -- Toggle resolved comments
  vim.keymap.set("n", "<leader>rt", M.toggle_resolved, vim.tbl_extend("force", opts, { desc = "Toggle resolved" }))

  -- Show status
  vim.keymap.set("n", "<leader>ri", M.show_status, vim.tbl_extend("force", opts, { desc = "Show review status" }))

  -- Mark files as reviewed
  vim.keymap.set("n", "<leader>rd", M.mark_reviewed, vim.tbl_extend("force", opts, { desc = "Mark file as reviewed (done)" }))
  vim.keymap.set("n", "<leader>rD", M.unmark_reviewed, vim.tbl_extend("force", opts, { desc = "Unmark file as reviewed" }))

  -- Fold controls
  vim.keymap.set("n", "<leader>rf", function()
    -- Toggle all folds: if any are closed, open all; otherwise close all
    local foldclosed = vim.fn.foldclosed(1)
    if foldclosed == -1 then
      -- Check if there are any folds in the buffer
      local has_closed_fold = false
      for lnum = 1, vim.api.nvim_buf_line_count(0) do
        if vim.fn.foldclosed(lnum) ~= -1 then
          has_closed_fold = true
          break
        end
      end
      if has_closed_fold then
        vim.cmd("normal! zR") -- Open all folds
      else
        vim.cmd("normal! zM") -- Close all folds
      end
    else
      vim.cmd("normal! zR") -- Open all folds
    end
  end, vim.tbl_extend("force", opts, { desc = "Toggle all folds" }))
end

return M
