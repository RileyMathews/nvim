local config = require('ghlite.config')

--- @class GHLiteUtilsModule
local M = {}

--- @param cmd string
--- @param cb GHLiteSystemStrCallback|nil
function M.system_str_cb(cmd, cb)
  --- @type string[]
  local cmd_split = vim.split(cmd, ' ')
  vim.system(cmd_split, { text = true }, function(result)
    if type(cb) == 'function' then
      if #result.stderr > 0 then
        config.log('system_str_cb error', result.stderr)
        M.notify(result.stderr, vim.log.levels.ERROR)
      end

      cb(result.stdout, result.stderr)
    end
  end)
end

--- @param cmd string[]
--- @param cb GHLiteSystemCallback|nil
function M.system_cb(cmd, cb)
  vim.system(cmd, { text = true }, function(result)
    if type(cb) == 'function' then
      cb(result.stdout)
    end
  end)
end

--- @generic T
--- @param arr T[]
--- @param condition fun(value: T): boolean
--- @return T[]
function M.filter_array(arr, condition)
  --- @type T[]
  local result = {}
  for _, v in ipairs(arr) do
    if condition(v) then
      table.insert(result, v)
    end
  end
  return result
end

--- @param value any
--- @return boolean
function M.is_empty(value)
  if value == nil or vim.fn.empty(value) == 1 then
    return true
  end
  return false
end

--- @param cb GHLiteStringCallback
function M.get_git_root(cb)
  M.system_str_cb('git rev-parse --show-toplevel', function(result)
    cb(vim.split(result, '\n')[1])
  end)
end

--- @param baseCommitId string
--- @param headCommitId string
--- @param cb GHLiteStringCallback
function M.get_git_merge_base(baseCommitId, headCommitId, cb)
  M.system_str_cb('git merge-base ' .. baseCommitId .. ' ' .. headCommitId, function(result)
    cb(vim.split(result, '\n')[1])
  end)
end

--- @param cb GHLiteStringCallback
function M.get_current_git_branch_name(cb)
  M.system_str_cb('git branch --show-current', function(result)
    cb(vim.split(result, '\n')[1])
  end)
end

--- @param message string
--- @param level? integer
function M.notify(message, level)
  vim.schedule(function()
    vim.notify(message, level)
  end)
end

--- @param buf_name string
--- @param prompt string|nil
--- @param content string[]
--- @param callback GHLiteInputCallback
function M.get_comment(buf_name, prompt, content, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, buf_name)

  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'

  local width = math.max(60, math.floor(vim.o.columns * 0.7))
  local height = math.max(8, math.floor(vim.o.lines * 0.4))
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(0, row),
    col = math.max(0, col),
    style = 'minimal',
    border = 'rounded',
    title = ' GHLite Comment ',
    title_pos = 'center',
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_cursor(win, { math.min(2, math.max(1, #content)), 0 })

  local submitted = false

  local function close_comment_window()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  --- @return nil
  local function capture_input_and_close()
    if submitted then
      return
    end
    submitted = true

    --- @type string[]
    local input_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if prompt ~= nil and input_lines[1] == prompt then
      table.remove(input_lines, 1)
    end
    local input = table.concat(input_lines, '\n')

    close_comment_window()
    callback(input)
  end

  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = capture_input_and_close,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
    end,
  })

  vim.wo[win].wrap = true
  vim.wo[win].winblend = 0
  vim.cmd('startinsert')
end

return M
