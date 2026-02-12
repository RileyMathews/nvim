-- PR Review Diff View - Side-by-side diff display

local M = {}

local pr_review = nil
local api = nil
local comments_mod = nil

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

local function get_comments()
  if not comments_mod then
    comments_mod = require("custom.pr_review.comments")
  end
  return comments_mod
end

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace("pr_review_diff")

-- Create a scratch buffer with content
---@param content string
---@param name string
---@param ft string?
---@return number bufnr
local function create_scratch_buffer(content, name, ft)
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer content
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Set buffer options
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false

  -- Detect and set filetype
  if ft then
    vim.bo[buf].filetype = ft
  else
    local detected_ft = vim.filetype.match({ filename = name, contents = lines })
    if detected_ft then
      vim.bo[buf].filetype = detected_ft
    end
  end

  return buf
end

local function set_diff_mode(win, enable)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.api.nvim_win_call(win, function()
    if enable then
      vim.cmd("diffthis")
    else
      vim.cmd("diffoff")
    end
  end)
end

local function set_diff_winbars(pr, file_path, base_sha, head_sha, left_win, right_win)
  if not base_sha or not head_sha then
    return
  end
  local base_title = string.format(" BASE: %s (%s @ %s)", file_path, pr.base_ref, base_sha:sub(1, 7))
  local head_title = string.format(" HEAD: %s (%s @ %s)", file_path, pr.head_ref, head_sha:sub(1, 7))

  if left_win and vim.api.nvim_win_is_valid(left_win) then
    vim.wo[left_win].winbar = "%#DiffDelete#" .. base_title .. "%*"
  end
  if right_win and vim.api.nvim_win_is_valid(right_win) then
    vim.wo[right_win].winbar = "%#DiffAdd#" .. head_title .. "%*"
  end
end

-- Close existing diff view
function M.close()
  local state = get_pr_review().get_state()

  -- Turn off diff mode and close windows
  for _, side in ipairs({ "left", "right" }) do
    local win = state.diff_wins[side]
    local buf = state.diff_buffers[side]

    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function()
        vim.cmd("diffoff")
      end)
      vim.api.nvim_win_close(win, true)
    end

    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  -- Clear state
  get_pr_review().update_state({
    diff_buffers = { left = nil, right = nil },
    diff_wins = { left = nil, right = nil },
    local_view_active = false,
    local_view_buf = nil,
  })

  -- Return to original window if it exists
  if state.original_win and vim.api.nvim_win_is_valid(state.original_win) then
    vim.api.nvim_set_current_win(state.original_win)
  end
end

-- Open diff view for a file
---@param file_path string
function M.open(file_path)
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.error("No PR loaded", { title = "PR Review" })
    return
  end

  -- Close existing diff view if open
  M.close()

  -- Get file contents at base and head commits (using exact SHAs to match GitHub's diff)
  local base_sha = pr.base_sha
  local head_sha = pr.head_sha

  if not base_sha then
    Snacks.notify.error("PR data missing base_sha - please reload the PR", { title = "PR Review" })
    return
  end
  if not head_sha then
    Snacks.notify.error("PR data missing head_sha - please reload the PR", { title = "PR Review" })
    return
  end

  local base_content, base_err = get_api().get_file_at_ref(file_path, base_sha)
  local head_content, head_err = get_api().get_file_at_ref(file_path, head_sha)

  -- Handle new/deleted files
  if base_err and head_err then
    Snacks.notify.error("Could not retrieve file content", { title = "PR Review" })
    return
  end

  -- For new files (added in PR): base doesn't exist, show empty left side
  -- For deleted files: head doesn't exist, show empty right side
  if base_err then
    base_content = ""
  end
  if head_err then
    head_content = ""
  end

  -- Determine filetype
  local ft = vim.filetype.match({ filename = file_path })

  -- Create buffers
  local left_name = string.format("pr://%d/base/%s", pr.number, file_path)
  local right_name = string.format("pr://%d/head/%s", pr.number, file_path)

  local left_buf = create_scratch_buffer(base_content, left_name, ft)
  local right_buf = create_scratch_buffer(head_content, right_name, ft)

  -- Store file path in buffer variable for comment actions
  vim.b[left_buf].pr_review_file = file_path
  vim.b[left_buf].pr_review_side = "left"
  vim.b[right_buf].pr_review_file = file_path
  vim.b[right_buf].pr_review_side = "right"

  -- Create the layout: vertical split
  -- Close all windows first to get a clean slate
  vim.cmd("tabnew")

  -- Left window (base)
  local left_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left_win, left_buf)

  -- Right window (head)
  vim.cmd("vsplit")
  local right_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right_win, right_buf)

  -- Enable diff mode on both windows
  set_diff_mode(left_win, true)
  set_diff_mode(right_win, true)

  -- Set window options
  for _, win in ipairs({ left_win, right_win }) do
    vim.wo[win].wrap = false
    vim.wo[win].signcolumn = "yes"
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
    vim.wo[win].cursorline = true
    -- Enable diff folding to collapse unchanged regions
    vim.wo[win].foldenable = true
    vim.wo[win].foldmethod = "diff"
    vim.wo[win].foldlevel = 0 -- Start with folds closed
    vim.wo[win].foldminlines = 5 -- Only fold regions >= 5 lines
    vim.wo[win].foldcolumn = "auto:3" -- Show fold indicators
  end

  -- Update state
  get_pr_review().update_state({
    diff_buffers = { left = left_buf, right = right_buf },
    diff_wins = { left = left_win, right = right_win },
    local_view_active = false,
    local_view_buf = nil,
  })

  -- Setup keymaps
  get_pr_review().setup_keymaps(left_buf)
  get_pr_review().setup_keymaps(right_buf)

  -- Render comments
  vim.schedule(function()
    get_comments().render()
  end)

  -- Focus on right window (head/new version)
  vim.api.nvim_set_current_win(right_win)

  -- Set window titles using winbar (show branch name @ short SHA)
  set_diff_winbars(pr, file_path, base_sha, head_sha, left_win, right_win)

  -- Show file position indicator
  local file_idx = state.current_file_index
  local total_files = #state.files
  Snacks.notify.info(
    string.format("File %d/%d: %s", file_idx, total_files, file_path),
    { title = "PR Review", id = "pr_review_file" }
  )
end

-- Toggle between diff view and local file view
function M.toggle_local_view()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  local left_win = state.diff_wins.left
  local right_win = state.diff_wins.right
  if not right_win or not vim.api.nvim_win_is_valid(right_win) then
    Snacks.notify.warn("No diff view open", { title = "PR Review" })
    return
  end

  local current_file = state.files[state.current_file_index]
  if not current_file then
    Snacks.notify.warn("No file selected", { title = "PR Review" })
    return
  end

  local file_path = current_file.path
  local base_sha = pr.base_sha
  local head_sha = pr.head_sha

  if state.local_view_active then
    local diff_buf = state.diff_buffers.right
    if not diff_buf or not vim.api.nvim_buf_is_valid(diff_buf) then
      M.open(file_path)
      return
    end

    vim.api.nvim_win_set_buf(right_win, diff_buf)
    set_diff_mode(left_win, true)
    set_diff_mode(right_win, true)
    set_diff_winbars(pr, file_path, base_sha, head_sha, left_win, right_win)

    get_pr_review().update_state({
      local_view_active = false,
      local_view_buf = nil,
    })

    Snacks.notify.info("Diff view restored", { title = "PR Review" })
    return
  end

  if vim.fn.filereadable(file_path) ~= 1 then
    Snacks.notify.warn("File not found in working tree", { title = "PR Review" })
    return
  end

  vim.api.nvim_win_call(right_win, function()
    vim.cmd("edit " .. vim.fn.fnameescape(file_path))
  end)

  local local_buf = vim.api.nvim_win_get_buf(right_win)
  vim.b[local_buf].pr_review_file = file_path
  vim.b[local_buf].pr_review_side = "right"
  get_pr_review().setup_keymaps(local_buf)

  set_diff_mode(left_win, false)
  set_diff_mode(right_win, false)

  if right_win and vim.api.nvim_win_is_valid(right_win) then
    vim.wo[right_win].winbar = " LOCAL: " .. file_path .. " (working tree) "
  end

  get_pr_review().update_state({
    local_view_active = true,
    local_view_buf = local_buf,
  })

  Snacks.notify.info("Local file view", { title = "PR Review" })
end

-- Get line mapping information for the current cursor position or visual selection
-- This helps determine which PR line(s) a buffer line corresponds to
---@param visual? boolean Whether to get visual selection range
---@return {file: string, line: number, start_line: number?, side: string}?
function M.get_line_info(visual)
  local state = get_pr_review().get_state()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local file = vim.b[buf].pr_review_file
  local side = vim.b[buf].pr_review_side

  if not file or not side then
    return nil
  end

  local line, start_line

  if visual then
    -- Get visual selection range
    -- Use '< and '> marks which are set after visual mode ends
    local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
    local end_pos = vim.api.nvim_buf_get_mark(buf, ">")

    local start_ln = start_pos[1]
    local end_ln = end_pos[1]

    -- Ensure start <= end
    if start_ln > end_ln then
      start_ln, end_ln = end_ln, start_ln
    end

    -- GitHub API: line is the end line, start_line is the beginning
    line = end_ln
    start_line = start_ln ~= end_ln and start_ln or nil
  else
    -- Single line from cursor
    local cursor = vim.api.nvim_win_get_cursor(win)
    line = cursor[1]
  end

  return {
    file = file,
    line = line,
    start_line = start_line,
    side = side == "left" and "LEFT" or "RIGHT",
  }
end

-- Jump to a specific line in the diff view
---@param file_path string
---@param line number
---@param side "left"|"right"
function M.jump_to_line(file_path, line, side)
  local state = get_pr_review().get_state()

  -- Find file index
  local file_idx = nil
  for i, f in ipairs(state.files) do
    if f.path == file_path then
      file_idx = i
      break
    end
  end

  if not file_idx then
    return
  end

  -- Open the file if not already open
  if state.current_file_index ~= file_idx then
    get_pr_review().open_file(file_idx)
  end

  -- Jump to line
  vim.schedule(function()
    local win = state.diff_wins[side]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      vim.cmd("normal! zz")
    end
  end)
end

return M
