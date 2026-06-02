local comments = require('ghlite.comments')
local config = require('ghlite.config')
local pr_utils = require('ghlite.pr_utils')
local utils = require('ghlite.utils')

--- @class FileNameAndLinePair
--- @field [1] string filename
--- @field [2] integer line

--- @class GHLiteDiffModule
local M = {}

--- @param cmd string
--- @return boolean
local function is_command_available(cmd)
  return vim.fn.exists(':' .. cmd) == 2
end

--- @return string|nil
local function get_diff_tool()
  local configured = config.s.diff_tool

  if configured == 'diffview' then
    return 'diffview'
  elseif configured == 'codediff' then
    return 'codediff'
  else -- 'auto'
    if is_command_available('DiffviewOpen') then
      return 'diffview'
    elseif is_command_available('CodeDiff') then
      return 'codediff'
    end
    return nil
  end
end

--- @return nil
function M.load_pr_diffview()
  --- @type GHLiteDiffTool|nil
  local diff_tool = get_diff_tool()

  if diff_tool == nil then
    local configured = config.s.diff_tool
    if configured == 'auto' then
      utils.notify('No diff tool available. Install diffview.nvim or codediff.nvim', vim.log.levels.ERROR)
    elseif configured == 'diffview' then
      utils.notify('diffview.nvim is not installed', vim.log.levels.ERROR)
    elseif configured == 'codediff' then
      utils.notify('codediff.nvim is not installed', vim.log.levels.ERROR)
    end
    return
  end

  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR to work with.', vim.log.levels.WARN)
      return
    end

    utils.notify('Comments load started...')
    comments.load_comments_only(selected_pr.number, function()
      utils.notify('Comments loaded.')
      utils.get_git_merge_base(
        selected_pr.baseRefOid and selected_pr.baseRefOid or selected_pr.baseRefName,
        selected_pr.headRefOid,
        function(mergeBaseOid)
          pr_utils.is_pr_checked_out(function(is_checked_out)
            vim.schedule(function()
              if diff_tool == 'diffview' then
                vim.cmd(string.format('DiffviewOpen %s..%s', mergeBaseOid, selected_pr.headRefOid))
              elseif diff_tool == 'codediff' then
                if is_checked_out then
                  vim.cmd(string.format('CodeDiff %s', mergeBaseOid))
                else
                  vim.cmd(string.format('CodeDiff %s %s', mergeBaseOid, selected_pr.headRefOid))
                end
              end
            end)
          end)
        end
      )
    end)
  end)
end

return M
