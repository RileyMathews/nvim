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

local QUERY_REVIEW_DATA = [[
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
        reviews(first: 100) {
          nodes {
            id
            databaseId
            author { login }
            state
            body
            submittedAt
            createdAt
            viewerDidAuthor
            comments(first: 50) {
              nodes {
                id
                databaseId
                body
                path
                diffHunk
                line
                startLine
                originalLine
                originalStartLine
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

local function execute_graphql_async(query, variables, cb)
  return gh.graphql_async(query, variables, cb)
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

---@param pr_data table
---@return table[], table[], table?, string?
local function parse_review_data(pr_data)
  if not pr_data then
    return {}, {}, nil, "Could not access PR data"
  end

  local threads = {}
  for _, thread in ipairs((safe_get(safe_get(pr_data, "reviewThreads"), "nodes")) or {}) do
    table.insert(threads, map_thread(thread))
  end

  local reviews = {}
  local pending_review = nil
  for _, review in ipairs((safe_get(safe_get(pr_data, "reviews"), "nodes")) or {}) do
    local comments = {}
    for _, c in ipairs((safe_get(safe_get(review, "comments"), "nodes")) or {}) do
      local mapped = map_comment(c)
      mapped.path = safe_get(c, "path")
      mapped.line = safe_get(c, "line") or safe_get(c, "originalLine")
      mapped.start_line = safe_get(c, "startLine") or safe_get(c, "originalStartLine")
      mapped.diff_hunk = safe_get(c, "diffHunk")
      table.insert(comments, mapped)
    end

    local review_author = safe_get(review, "author")
    local mapped_review = {
      id = tostring(safe_get(review, "id") or ""),
      database_id = safe_get(review, "databaseId"),
      author = review_author and review_author.login or "unknown",
      state = safe_get(review, "state") or "COMMENTED",
      body = safe_get(review, "body"),
      submitted_at = safe_get(review, "submittedAt") or safe_get(review, "createdAt"),
      comments = comments,
    }

    if mapped_review.state == "PENDING" and safe_get(review, "viewerDidAuthor") then
      pending_review = mapped_review
    else
      table.insert(reviews, mapped_review)
    end
  end

  return threads, reviews, pending_review, nil
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

---@param owner string
---@param repo string
---@param pr_number number
---@return table[], table[], table?, string?
function M.fetch_review_data(owner, repo, pr_number)
  local data, err = execute_graphql(QUERY_REVIEW_DATA, {
    owner = owner,
    repo = repo,
    prNumber = pr_number,
  })
  if err then
    return {}, {}, nil, err
  end

  local pr_data = data and data.repository and data.repository.pullRequest
  return parse_review_data(pr_data)
end

---@param owner string
---@param repo string
---@param pr_number number
---@param cb fun(threads:table[], reviews:table[], pending_review:table?, err:string?)
function M.fetch_review_data_async(owner, repo, pr_number, cb)
  execute_graphql_async(QUERY_REVIEW_DATA, {
    owner = owner,
    repo = repo,
    prNumber = pr_number,
  }, function(data, err)
    if err then
      cb({}, {}, nil, err)
      return
    end

    local pr_data = data and data.repository and data.repository.pullRequest
    local threads, reviews, pending_review, parse_err = parse_review_data(pr_data)
    cb(threads, reviews, pending_review, parse_err)
  end)
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
