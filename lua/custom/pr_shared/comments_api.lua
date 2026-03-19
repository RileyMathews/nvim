local M = {}

local gh = require("custom.pr_shared.gh")

local function is_nil(val)
  return val == nil or val == vim.NIL
end

local function safe_get(tbl, key)
  if is_nil(tbl) then
    return nil
  end
  local val = tbl[key]
  if val == vim.NIL then
    return nil
  end
  return val
end

local QUERY_REVIEW_THREADS = [[
  query($owner: String!, $repo: String!, $prNumber: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $prNumber) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            originalLine
            startLine
            originalStartLine
            diffSide
            comments(first: 50) {
              nodes {
                id
                databaseId
                body
                author { login }
                createdAt
                replyTo { id databaseId }
                reactionGroups {
                  content
                  users { totalCount }
                }
              }
            }
          }
        }
      }
    }
  }
]]

---@param query string
---@param variables table
---@return table?, string?
local function execute_graphql(query, variables)
  return gh.graphql(query, variables)
end

local function map_comment(comment)
  local author = safe_get(comment, "author")
  local reply_to = safe_get(comment, "replyTo")

  return {
    id = tostring(safe_get(comment, "id") or ""),
    database_id = safe_get(comment, "databaseId"),
    author = author and author.login or "unknown",
    body = safe_get(comment, "body") or "",
    created_at = safe_get(comment, "createdAt") or "",
    reply_to_id = reply_to and reply_to.id or nil,
    reactions = safe_get(comment, "reactionGroups"),
  }
end

local function map_thread(thread)
  local comments = {}
  for _, comment in ipairs((safe_get(safe_get(thread, "comments"), "nodes")) or {}) do
    table.insert(comments, map_comment(comment))
  end

  return {
    id = tostring(safe_get(thread, "id") or ""),
    resolved = safe_get(thread, "isResolved") == true,
    outdated = safe_get(thread, "isOutdated") == true,
    path = safe_get(thread, "path") or "",
    line = safe_get(thread, "line") or safe_get(thread, "originalLine"),
    start_line = safe_get(thread, "startLine") or safe_get(thread, "originalStartLine"),
    diff_side = (safe_get(thread, "diffSide") or "RIGHT"):lower(),
    comments = comments,
  }
end

---@param threads table[]
---@return table<string, table<number, table[]>>
function M.group_threads_by_path_line(threads)
  local grouped = {}

  for _, thread in ipairs(threads or {}) do
    local path = thread.path
    local line = thread.line
    if path and path ~= "" and line then
      grouped[path] = grouped[path] or {}
      grouped[path][line] = grouped[path][line] or {}
      table.insert(grouped[path][line], thread)
    end
  end

  return grouped
end

---@param owner string
---@param repo string
---@param pr_number number
---@return table[], string?
function M.fetch_review_threads(owner, repo, pr_number)
  local data, err = execute_graphql(QUERY_REVIEW_THREADS, {
    owner = owner,
    repo = repo,
    prNumber = pr_number,
  })
  if err then
    return {}, err
  end

  local pr_data = data and data.repository and data.repository.pullRequest
  if not pr_data then
    return {}, "Could not access PR data"
  end

  local threads = {}
  for _, thread in ipairs((safe_get(safe_get(pr_data, "reviewThreads"), "nodes")) or {}) do
    table.insert(threads, map_thread(thread))
  end

  return threads, nil
end

---@param thread_id string
---@param body string
---@return boolean, string?
function M.add_thread_reply(thread_id, body)
  local query = [[
    mutation($threadId: ID!, $body: String!) {
      addPullRequestReviewThreadReply(input: {
        pullRequestReviewThreadId: $threadId
        body: $body
      }) {
        comment { id }
      }
    }
  ]]

  local _, err = execute_graphql(query, {
    threadId = thread_id,
    body = body,
  })
  if err then
    return false, err
  end

  return true, nil
end

return M
