local M = {}

local SEPARATOR_WIDTH = 60
local FLOAT_WIDTH = 70
local FLOAT_MAX_HEIGHT = 20

local function format_relative_time(timestamp)
  timestamp = timestamp or ""
  local year, month, day, hour, min, sec = timestamp:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return timestamp
  end

  local ts = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  local diff = os.time() - ts
  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h ago"
  elseif diff < 604800 then
    return math.floor(diff / 86400) .. "d ago"
  else
    return string.format("%s-%s-%s", year, month, day)
  end
end

local function truncate(text, max_len)
  text = (text or ""):gsub("\n", " "):gsub("%s+", " ")
  if #text > max_len then
    return text:sub(1, max_len - 3) .. "..."
  end
  return text
end

---@param comment table
---@return table
local function normalize_comment(comment)
  comment = comment or {}
  return {
    author = comment.author or "unknown",
    body = comment.body or "",
    created_at = comment.created_at or "",
  }
end

---@param thread table
---@return table
local function normalize_thread(thread)
  thread = thread or {}

  local comments = {}
  for _, comment in ipairs(thread.comments or {}) do
    table.insert(comments, normalize_comment(comment))
  end

  return {
    resolved = thread.resolved == true,
    outdated = thread.outdated == true,
    comments = comments,
  }
end

---@param thread table
---@return string
---@return string
local function thread_status(thread)
  if thread.resolved then
    return "[x] Resolved", "DiagnosticHint"
  end
  if thread.outdated then
    return "[~] Outdated", "Comment"
  end
  return "[!] Active", "DiagnosticWarn"
end

M.truncate = truncate
M.format_relative_time = format_relative_time

---@param opts {buf:number,line:number,threads:table[],ns_id:number,extmarks_key?:string,store_threads?:boolean}
---@return boolean
function M.render_line_indicator(opts)
  local input_threads = opts.threads or {}
  if #input_threads == 0 then
    return false
  end

  local threads = {}
  for _, thread in ipairs(input_threads) do
    table.insert(threads, normalize_thread(thread))
  end

  local total_comments = 0
  local has_unresolved = false
  local has_outdated = false

  for _, thread in ipairs(threads) do
    total_comments = total_comments + #(thread.comments or {})
    if not thread.resolved then
      has_unresolved = true
    end
    if thread.outdated then
      has_outdated = true
    end
  end

  local first_thread = threads[1]
  local first_comment = first_thread.comments and first_thread.comments[1] or nil
  local preview = first_comment and truncate(first_comment.body, 50) or ""

  local hl = "DiagnosticHint"
  if has_unresolved then
    hl = "DiagnosticWarn"
  end
  if has_outdated and not has_unresolved then
    hl = "Comment"
  end

  local icon = has_unresolved and "● " or "○ "

  local virt_text = {}
  table.insert(virt_text, { "  ", "Normal" })
  table.insert(virt_text, { icon, hl })

  if #threads > 1 or total_comments > 1 then
    table.insert(virt_text, { string.format("[%d] ", total_comments), hl })
  end

  if first_comment then
    table.insert(virt_text, { "@" .. (first_comment.author or "unknown") .. ": ", "Special" })
    table.insert(virt_text, { preview, hl })
  end

  local ok = pcall(vim.api.nvim_buf_set_extmark, opts.buf, opts.ns_id, opts.line - 1, 0, {
    virt_text = virt_text,
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = 100,
  })

  if not ok then
    return false
  end

  if opts.store_threads ~= false and opts.extmarks_key then
    local extmarks = vim.b[opts.buf][opts.extmarks_key] or {}
    extmarks[opts.line] = input_threads
    vim.b[opts.buf][opts.extmarks_key] = extmarks
  end

  return true
end

---@param opts {threads:table[], file_path:string, line:number, side:string, notify_title:string, on_reply?:fun(ctx:table)}
function M.show_floating(opts)
  local raw_threads = opts.threads or {}
  if #raw_threads == 0 then
    Snacks.notify.info("No comments on this line", { title = opts.notify_title or "PR" })
    return
  end

  local threads = {}
  for _, thread in ipairs(raw_threads) do
    table.insert(threads, normalize_thread(thread))
  end

  local lines = {}
  local highlights = {}

  for i, thread in ipairs(threads) do
    if i > 1 then
      table.insert(lines, "")
      table.insert(lines, string.rep("─", SEPARATOR_WIDTH))
      table.insert(lines, "")
    end

    local status, status_hl = thread_status(thread)
    local status_line = string.format("Thread: %s", status)
    table.insert(lines, status_line)
    table.insert(highlights, {
      line = #lines - 1,
      col_start = 0,
      col_end = #status_line,
      hl = status_hl,
    })

    table.insert(lines, "")

    for j, comment in ipairs(thread.comments or {}) do
      local icon = j == 1 and ">" or "  >"
      local header = string.format("%s @%s  %s", icon, comment.author, format_relative_time(comment.created_at))
      table.insert(lines, header)
      table.insert(highlights, {
        line = #lines - 1,
        col_start = #icon + 1,
        col_end = #icon + 2 + #comment.author,
        hl = "Function",
      })

      for _, body_line in ipairs(vim.split(comment.body, "\n")) do
        table.insert(lines, "  " .. body_line)
      end

      if j < #thread.comments then
        table.insert(lines, "")
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", SEPARATOR_WIDTH))
  table.insert(lines, "Press 'q' to close | 'r' to reply")
  table.insert(highlights, {
    line = #lines - 1,
    col_start = 0,
    col_end = -1,
    hl = "Comment",
  })

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].bufhidden = "wipe"
  vim.bo[float_buf].filetype = "markdown"

  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = FLOAT_WIDTH,
    height = math.min(#lines, FLOAT_MAX_HEIGHT),
    style = "minimal",
    border = "rounded",
    title = " Comment Thread ",
    title_pos = "center",
  })

  local ns_float = vim.api.nvim_create_namespace("pr_shared_comments_float")
  for _, hl in ipairs(highlights) do
    if hl.col_start and hl.col_end then
      vim.api.nvim_buf_add_highlight(float_buf, ns_float, hl.hl, hl.line, hl.col_start, hl.col_end)
    else
      vim.api.nvim_buf_add_highlight(float_buf, ns_float, hl.hl, hl.line, 0, -1)
    end
  end

  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true
  vim.wo[float_win].cursorline = false

  local close_float = function()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
  end

  local reply = function()
    close_float()
    if opts.on_reply then
      vim.schedule(function()
        opts.on_reply({
          file_path = opts.file_path,
          line = opts.line,
          side = opts.side,
          threads = raw_threads,
        })
      end)
    end
  end

  vim.keymap.set("n", "q", close_float, { buffer = float_buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_float, { buffer = float_buf, nowait = true })
  vim.keymap.set("n", "r", reply, { buffer = float_buf, nowait = true })
end

return M
