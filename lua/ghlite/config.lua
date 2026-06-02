--- @alias GHLiteDiffTool 'auto'|'diffview'|'codediff'
--- @alias GHLiteSplitCommand ''|'split'|'vsplit'|'tabnew'|string

--- @class GHLiteConfig
--- @field debug boolean
--- @field view_split GHLiteSplitCommand|false
--- @field diff_tool GHLiteDiffTool
--- @field comment_split GHLiteSplitCommand|false Deprecated and ignored for comment editing
--- @field html_comments_command string[]|false

--- @class GHLiteUserConfig
--- @field debug? boolean
--- @field view_split? GHLiteSplitCommand|false
--- @field diff_tool? GHLiteDiffTool
--- @field comment_split? GHLiteSplitCommand|false Deprecated and ignored for comment editing
--- @field html_comments_command? string[]|false

--- @class GHLiteConfigModule
--- @field s GHLiteConfig
local M = {}

--- @type GHLiteConfig
M.s = {
  debug = false,
  view_split = 'vsplit',
  diff_tool = 'auto', -- 'diffview', 'codediff', or 'auto'
  comment_split = 'split',
  html_comments_command = { 'lynx', '-stdin', '-dump' },
}

--- @param config GHLiteUserConfig|nil
function M.setup(config)
  M.s = vim.tbl_deep_extend('force', {}, M.s, config or {})
end

--- @param key string
--- @param message any
function M.log(key, message)
  if M.s.debug then
    local home = os.getenv('HOME')
    local log_file_name = home .. '/.ghlite.log'
    local log_file = io.open(log_file_name, 'a')
    if log_file then
      log_file:write(os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. key .. ':\n')
      log_file:write(vim.inspect(message))
      log_file:write('\n\n')
      log_file:close()
    end
  end
end

return M
