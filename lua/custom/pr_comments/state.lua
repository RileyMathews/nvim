local M = {}

---@class PRComments.Comment
---@field id string
---@field database_id? number
---@field author string
---@field body string
---@field created_at string
---@field reply_to_id? string
---@field reactions? table[]

---@class PRComments.Thread
---@field id string
---@field path string
---@field line number
---@field start_line? number
---@field diff_side? string
---@field resolved boolean
---@field outdated boolean
---@field comments PRComments.Comment[]

---@alias PRComments.ThreadMap table<string, table<number, PRComments.Thread[]>>

---@class PRComments.State
---@field active boolean
---@field pr_number number?
---@field show_resolved boolean
---@field show_outdated boolean
---@field threads PRComments.ThreadMap

---@class PRComments.ThreadLocation
---@field path string
---@field line number
---@field thread PRComments.Thread

---@class PRComments.ReplyModule
---@field reply fun(opts: table)

---@class PRComments.CommentsRenderModule
---@field render_line_indicator fun(opts: table): boolean
---@field show_floating fun(opts: table)
---@field truncate fun(text: string, max_len: number): string

---@class PRComments.CommentsApiModule
---@field fetch_review_threads fun(owner: string, repo: string, pr_number: number): PRComments.Thread[], string?
---@field group_threads_by_path_line fun(threads: PRComments.Thread[]): PRComments.ThreadMap
---@field add_thread_reply fun(thread_id: string, body: string): boolean, string?

---@class PRComments.GhModule
---@field repo_root fun(): string?
---@field get_repo_info fun(): {owner: string, name: string, full_name: string}?, string?
---@field get_current_pr_number fun(): number?, string?

local state = nil
local augroup_id = nil
local current_thread_index = nil

local namespace_id = vim.api.nvim_create_namespace("pr_comments")

local reply_mod = nil
local comments_render_mod = nil
local comments_api_mod = nil
local gh_mod = nil

---@param user_config table?
local function validate_setup_config(user_config)
  if user_config ~= nil and type(user_config) ~= "table" then
    error("pr_comments.setup(): config must be a table")
  end
end

---@param user_config table?
function M.init(user_config)
  validate_setup_config(user_config)

  state = {
    active = false,
    pr_number = nil,
    show_resolved = true,
    show_outdated = true,
    threads = {},
  }

  augroup_id = nil
  current_thread_index = nil
end

function M.ensure_setup()
  if not state then
    error("pr_comments: setup() must be called before using this module")
  end
end

---@return PRComments.State
function M.get_state()
  M.ensure_setup()
  return state
end

---@return integer
function M.get_namespace_id()
  return namespace_id
end

---@return integer?
function M.get_augroup_id()
  return augroup_id
end

---@param id integer?
function M.set_augroup_id(id)
  augroup_id = id
end

---@return integer?
function M.get_current_thread_index()
  return current_thread_index
end

---@param index integer?
function M.set_current_thread_index(index)
  current_thread_index = index
end

function M.reset_thread_cursor()
  current_thread_index = nil
end

---@param content string
---@param icon? string
function M.notify_info(content, icon)
  Snacks.notify.info(content, {
    icon = icon or "",
    id = "pr_comments",
    title = "PR Comments",
  })
end

---@param content string
---@param icon? string
function M.notify_error(content, icon)
  Snacks.notify.error(content, {
    icon = icon or "",
    id = "pr_comments",
    title = "PR Comments",
  })
end

---@return {reply: fun(opts: table)}
---@return PRComments.ReplyModule
function M.get_reply()
  if not reply_mod then
    reply_mod = require("custom.pr_shared.reply")
  end
  return reply_mod
end

---@return PRComments.CommentsRenderModule
function M.get_comments_render()
  if not comments_render_mod then
    comments_render_mod = require("custom.pr_shared.comments_render")
  end
  return comments_render_mod
end

---@return PRComments.CommentsApiModule
function M.get_comments_api()
  if not comments_api_mod then
    comments_api_mod = require("custom.pr_shared.comments_api")
  end
  return comments_api_mod
end

---@return PRComments.GhModule
function M.get_gh()
  if not gh_mod then
    gh_mod = require("custom.pr_shared.gh")
  end
  return gh_mod
end

---@return string?
function M.get_repo_root()
  return M.get_gh().repo_root()
end

---@param bufnr integer
---@return string?
function M.get_buffer_relative_path(bufnr)
  local abs_path = vim.api.nvim_buf_get_name(bufnr)
  if abs_path == "" then
    return nil
  end

  local repo_root = M.get_repo_root()
  if not repo_root then
    return nil
  end

  if abs_path:sub(1, #repo_root) == repo_root then
    return abs_path:sub(#repo_root + 2)
  end

  return nil
end

return M
