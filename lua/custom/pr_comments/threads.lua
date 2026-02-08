local ctx = require("custom.pr_comments.state")

local M = {}

---@class PRComments.ThreadCounts
---@field total integer
---@field unresolved integer
---@field resolved integer
---@field files integer

---@param thread PRComments.Thread
---@return boolean
local function thread_is_visible(thread)
  local state = ctx.get_state()

  if not state.show_resolved and thread.resolved then
    return false
  end

  if not state.show_outdated and thread.outdated and not thread.resolved then
    return false
  end

  return true
end

---@param rel_path string
---@return table<number, PRComments.Thread[]>
function M.get_visible_threads_for_file(rel_path)
  local state = ctx.get_state()
  local file_threads = state.threads[rel_path]
  if not file_threads then
    return {}
  end

  local visible = {}
  for line_num, threads in pairs(file_threads) do
    local visible_threads = {}
    for _, thread in ipairs(threads) do
      if thread_is_visible(thread) then
        table.insert(visible_threads, thread)
      end
    end

    if #visible_threads > 0 then
      visible[line_num] = visible_threads
    end
  end

  return visible
end

---@return PRComments.ThreadCounts
function M.count_threads()
  local state = ctx.get_state()
  local total = 0
  local unresolved = 0
  local file_count = 0
  local files_seen = {}

  for filepath, lines in pairs(state.threads) do
    if not files_seen[filepath] then
      files_seen[filepath] = true
      file_count = file_count + 1
    end

    for _, threads in pairs(lines) do
      for _, thread in ipairs(threads) do
        total = total + 1
        if not thread.resolved then
          unresolved = unresolved + 1
        end
      end
    end
  end

  return {
    total = total,
    unresolved = unresolved,
    resolved = total - unresolved,
    files = file_count,
  }
end

---@return PRComments.Thread[]?, string?
function M.get_threads_at_cursor()
  local state = ctx.get_state()
  if not state.active then
    return nil, "No PR comments loaded. Run :PRCommentsShow first"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  local rel_path = ctx.get_buffer_relative_path(bufnr)
  if not rel_path then
    return nil, "Not in a tracked file"
  end

  local rendered_threads = vim.b[bufnr].pr_comments_extmarks
  if rendered_threads and rendered_threads[cursor_line] and #rendered_threads[cursor_line] > 0 then
    return rendered_threads[cursor_line], nil
  end

  local file_threads = M.get_visible_threads_for_file(rel_path)
  local threads_at_line = file_threads[cursor_line]
  if not threads_at_line or #threads_at_line == 0 then
    return nil, "No visible comment thread on line " .. cursor_line
  end

  return threads_at_line, nil
end

---@return PRComments.ThreadLocation[]
function M.get_all_threads_sorted()
  local state = ctx.get_state()
  if not state.active then
    return {}
  end

  local all_threads = {}

  for filepath, _ in pairs(state.threads) do
    local lines = M.get_visible_threads_for_file(filepath)
    for line_num, threads in pairs(lines) do
      for _, thread in ipairs(threads) do
        table.insert(all_threads, {
          path = filepath,
          line = line_num,
          thread = thread,
        })
      end
    end
  end

  table.sort(all_threads, function(a, b)
    if a.path == b.path then
      return a.line < b.line
    end
    return a.path < b.path
  end)

  return all_threads
end

return M
