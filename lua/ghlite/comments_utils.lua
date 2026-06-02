local utils = require('ghlite.utils')

--- @class Comment
--- @field id integer
--- @field node_id string|nil
--- @field url string
--- @field path string
--- @field line integer
--- @field start_line integer|userdata
--- @field user string
--- @field body string
--- @field updated_at string
--- @field diff_hunk string

--- @class GroupedComment
--- @field id integer
--- @field line integer
--- @field start_line integer|userdata
--- @field url string
--- @field content string
--- @field comments Comment[]

--- @class GHLiteCommentsUtilsModule
local M = {}

--- @param comment GHLiteRawComment
--- @return Comment
function M.convert_comment(comment)
  return {
    id = comment.id,
    node_id = comment.node_id,
    url = comment.html_url,
    path = comment.path,
    line = comment.line,
    start_line = comment.start_line,
    user = comment.user.login,
    body = comment.body,
    updated_at = comment.updated_at,
    diff_hunk = comment.diff_hunk,
  }
end

--- @param comment Comment
--- @return string
local function format_comment(comment)
  return string.format(
    '✍️ %s at %s:\n%s\n\n',
    comment.user,
    comment.updated_at,
    string.gsub(comment.body, '\r', '')
  )
end

--- @param comments Comment[]
--- @return string
function M.prepare_content(comments)
  local content = ''
  if #comments > 0 and comments[1].start_line ~= vim.NIL and comments[1].start_line ~= comments[1].line then
    content = string.format('📓 Comment on lines %d to %d\n\n', comments[1].start_line, comments[1].line)
  end

  for _, comment in pairs(comments) do
    content = content .. format_comment(comment)
  end

  if #comments > 0 then
    content = content .. '\n🪓 Diff hunk:\n' .. comments[1].diff_hunk .. '\n'
  end

  return content
end

--- @param gh_comments GHLiteRawComment[]
--- @param cb GHLiteGroupedCommentsCallback
function M.group_comments(gh_comments, cb)
  utils.get_git_root(function(git_root)
    --- @type table<number, Comment[]>
    local comment_groups = {}
    --- @type table<number, number>
    local base = {}

    for _, comment in pairs(gh_comments) do
      if comment.in_reply_to_id == nil then
        comment_groups[comment.id] = { M.convert_comment(comment) }
        base[comment.id] = comment.id
      else
        table.insert(comment_groups[base[comment.in_reply_to_id]], M.convert_comment(comment))
        base[comment.id] = base[comment.in_reply_to_id]
      end
    end

    --- @type table<string, GroupedComment[]>
    local result = {}
    for _, comments in pairs(comment_groups) do
      --- @type GroupedComment
      local grouped_comments = {
        id = comments[1].id,
        line = comments[1].line,
        start_line = comments[1].start_line,
        url = comments[#comments].url,
        content = M.prepare_content(comments),
        comments = comments,
      }

      local full_path = git_root .. '/' .. comments[1].path
      if result[full_path] == nil then
        result[full_path] = { grouped_comments }
      else
        table.insert(result[full_path], grouped_comments)
      end
    end

    cb(result)
  end)
end

return M
