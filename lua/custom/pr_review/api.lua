-- PR Review API - GitHub CLI interactions
-- Handles fetching PR data, diffs, comments, and posting comments

local M = {}
local gh = require("custom.pr_shared.gh")

local comments_api_mod = nil

local function get_comments_api()
  if not comments_api_mod then
    comments_api_mod = require("custom.pr_shared.comments_api")
  end
  return comments_api_mod
end

-- Cache for PR data
local cache = {
  current_pr = nil,
  repo_info = nil,
}

---@class PRReview.RepoInfo
---@field owner string
---@field name string
---@field full_name string

---@class PRReview.PR
---@field number number
---@field title string
---@field state string
---@field author string
---@field head_ref string
---@field base_ref string
---@field head_sha string
---@field base_sha string
---@field url string
---@field repo string
---@field pending_review_id string?

---@class PRReview.Comment
---@field id string
---@field database_id number
---@field author string
---@field body string
---@field created_at string
---@field path string?
---@field line number?
---@field start_line number?
---@field side string?
---@field diff_hunk string?
---@field reply_to_id string?
---@field reactions table[]?

---@class PRReview.ReviewThread
---@field id string
---@field resolved boolean
---@field outdated boolean
---@field path string
---@field line number?
---@field start_line number?
---@field diff_side string
---@field comments PRReview.Comment[]

---@class PRReview.Review
---@field id string
---@field database_id number
---@field author string
---@field state string
---@field body string?
---@field submitted_at string?
---@field comments PRReview.Comment[]

---@class PRReview.PRData
---@field pr PRReview.PR
---@field threads PRReview.ReviewThread[]
---@field reviews PRReview.Review[]
---@field pending_review PRReview.Review?
---@field diff_text string
---@field files PRReview.DiffFile[]

---@class PRReview.DiffFile
---@field path string
---@field additions number
---@field deletions number
---@field status string

-- Get repository info
---@return PRReview.RepoInfo?, string?
function M.get_repo_info()
  if cache.repo_info then
    return cache.repo_info, nil
  end

  local result, err = gh.get_repo_info()
  if err then
    return nil, "Not in a GitHub repository or gh not authenticated"
  end

  cache.repo_info = {
    owner = result.owner,
    name = result.name,
    full_name = result.full_name,
  }

  return cache.repo_info, nil
end

-- Detect the current PR from the branch
---@return PRReview.PR?, string?
function M.get_current_pr()
  local result, err = gh.json({
    "pr",
    "view",
    "--json",
    "number,title,state,author,headRefName,baseRefName,headRefOid,baseRefOid,url",
  })

  if err then
    return nil, "No PR found for current branch"
  end

  local repo_info = M.get_repo_info()

  ---@type PRReview.PR
  local pr = {
    number = result.number,
    title = result.title,
    state = result.state:lower(),
    author = result.author.login,
    head_ref = result.headRefName,
    base_ref = result.baseRefName,
    head_sha = result.headRefOid,
    base_sha = result.baseRefOid,
    url = result.url,
    repo = repo_info and repo_info.full_name or "",
  }

  cache.current_pr = pr
  return pr, nil
end

-- Get PR by number
---@param pr_number number
---@param repo? string
---@return PRReview.PR?, string?
function M.get_pr(pr_number, repo)
  local result, err = gh.json({
    "pr",
    "view",
    tostring(pr_number),
    "--json",
    "number,title,state,author,headRefName,baseRefName,headRefOid,baseRefOid,url",
  }, { repo = repo })

  if err then
    return nil, "Failed to fetch PR #" .. pr_number
  end

  ---@type PRReview.PR
  local pr = {
    number = result.number,
    title = result.title,
    state = result.state:lower(),
    author = result.author.login,
    head_ref = result.headRefName,
    base_ref = result.baseRefName,
    head_sha = result.headRefOid,
    base_sha = result.baseRefOid,
    url = result.url,
    repo = repo or (M.get_repo_info() or {}).full_name or "",
  }

  return pr, nil
end

-- Fetch PR diff as text
---@param pr_number number
---@param repo? string
---@return string?, string?
function M.fetch_diff(pr_number, repo)
  local args = { "pr", "diff", tostring(pr_number) }
  return gh.text(args, { repo = repo })
end

-- Parse diff to extract file list
---@param diff_text string
---@return PRReview.DiffFile[]
function M.parse_diff_files(diff_text)
  local files = {}
  local current_file = nil
  local additions = 0
  local deletions = 0

  for line in diff_text:gmatch("[^\n]+") do
    -- New file header
    local file = line:match("^diff %-%-git a/(.-) b/")
    if file then
      -- Save previous file
      if current_file then
        table.insert(files, {
          path = current_file,
          additions = additions,
          deletions = deletions,
          status = additions > 0 and deletions > 0 and "modified"
            or additions > 0 and "added"
            or deletions > 0 and "deleted"
            or "modified",
        })
      end
      current_file = file
      additions = 0
      deletions = 0
    elseif current_file then
      -- Count additions/deletions
      if line:match("^%+[^%+]") then
        additions = additions + 1
      elseif line:match("^%-[^%-]") then
        deletions = deletions + 1
      end
    end
  end

  -- Don't forget the last file
  if current_file then
    table.insert(files, {
      path = current_file,
      additions = additions,
      deletions = deletions,
      status = additions > 0 and deletions > 0 and "modified"
        or additions > 0 and "added"
        or deletions > 0 and "deleted"
        or "modified",
    })
  end

  return files
end

-- Fetch review threads and comments via GraphQL
---@param pr PRReview.PR
---@return PRReview.ReviewThread[], PRReview.Review[], PRReview.Review?
function M.fetch_comments(pr)
  local owner, name = pr.repo:match("^(.-)/(.-)$")
  if not owner or not name then
    Snacks.notify.error("Invalid repo format", { title = "PR Review" })
    return {}, {}, nil
  end

  local threads, reviews, pending_review, err = get_comments_api().fetch_review_data(owner, name, pr.number)
  if err then
    -- Check for rate limiting
    if err:match("429") or err:match("throttled") or err:match("rate limit") then
      Snacks.notify.warn(
        "GitHub API rate limit hit. Comments may be incomplete.\nWait a moment and use <leader>rR to refresh.",
        { title = "PR Review" }
      )
      return {}, {}, nil
    end
    Snacks.notify.error("Failed to fetch comments: " .. err, { title = "PR Review" })
    return {}, {}, nil
  end

  return threads, reviews, pending_review
end

-- Get file content at a specific ref
---@param file_path string
---@param ref string
---@return string?, string?
function M.get_file_at_ref(file_path, ref)
  -- Use vim.fn.system with proper error checking via v:shell_error
  -- First check if the file exists at this ref
  vim.fn.system(string.format("git cat-file -e '%s:%s'", ref, file_path))
  if vim.v.shell_error ~= 0 then
    return nil, "File does not exist at " .. ref
  end

  -- File exists, get its content
  local output = vim.fn.system(string.format("git show '%s:%s'", ref, file_path))
  if vim.v.shell_error ~= 0 then
    return nil, "Failed to get file content"
  end

  return output, nil
end

-- Post a general comment on the PR (issue comment, not review comment)
---@param pr PRReview.PR
---@param body string
---@return boolean, string?
function M.post_comment(pr, body)
  local endpoint = string.format("/repos/%s/issues/%d/comments", pr.repo, pr.number)
  local result, err = gh.api(endpoint, { body = body })

  if err then
    return false, err
  end

  return true, nil
end

-- Start a new review
---@param pr PRReview.PR
---@return string?, string? -- review_id, error
function M.start_review(pr)
  local endpoint = string.format("/repos/%s/pulls/%d/reviews", pr.repo, pr.number)
  local result, err = gh.api(endpoint, { commit_id = pr.head_sha })

  if err then
    return nil, err
  end

  return tostring(result.id), nil
end

-- Add a comment to a pending review using GraphQL
---@param pr PRReview.PR
---@param review_id string
---@param opts {path: string, line: number, side: string, body: string, start_line?: number}
---@return boolean, string?
function M.add_review_comment(pr, review_id, opts)
  local query = [[
    mutation($reviewId: ID!, $body: String!, $path: String!, $line: Int!, $side: DiffSide!, $startLine: Int, $startSide: DiffSide) {
      addPullRequestReviewThread(input: {
        pullRequestReviewId: $reviewId
        body: $body
        path: $path
        line: $line
        side: $side
        startLine: $startLine
        startSide: $startSide
      }) {
        thread { id }
      }
    }
  ]]

  local variables = {
    reviewId = review_id,
    body = opts.body,
    path = opts.path,
    line = opts.line,
    side = opts.side:upper(),
    startLine = opts.start_line,
    startSide = opts.start_line and opts.side:upper() or nil,
  }

  local _, err = gh.graphql(query, variables)
  if err then
    return false, err
  end

  return true, nil
end

-- Post an immediate line comment (not part of a review)
---@param pr PRReview.PR
---@param opts {path: string, line: number, side: string, body: string, start_line?: number}
---@return boolean, string?
function M.post_line_comment(pr, opts)
  local endpoint = string.format("/repos/%s/pulls/%d/comments", pr.repo, pr.number)

  local input = {
    commit_id = pr.head_sha,
    path = opts.path,
    line = opts.line,
    side = opts.side:upper(),
    body = opts.body,
  }

  if opts.start_line then
    input.start_line = opts.start_line
    input.start_side = opts.side:upper()
  end

  local _, err = gh.api(endpoint, input)
  if err then
    return false, err
  end

  return true, nil
end

-- Reply to a comment thread
---@param pr PRReview.PR
---@param comment_id number -- database ID of the comment to reply to
---@param body string
---@param thread_id string? -- GraphQL node ID of the thread (for pending review replies)
---@return boolean, string?
function M.reply_to_comment(pr, comment_id, body, thread_id)
  -- If we have the thread ID, use GraphQL mutation (works with pending reviews)
  if thread_id then
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

    local _, err = gh.graphql(query, {
      threadId = thread_id,
      body = body,
    })

    if err then
      return false, err
    end
    return true, nil
  end

  -- Fallback: No thread ID - use REST API direct reply endpoint
  local endpoint = string.format("/repos/%s/pulls/%d/comments/%d/replies", pr.repo, pr.number, comment_id)

  local _, err = gh.api(endpoint, { body = body })
  if err then
    return false, err
  end

  return true, nil
end

-- Submit a pending review
---@param pr PRReview.PR
---@param review_id string
---@param event "APPROVE"|"REQUEST_CHANGES"|"COMMENT"
---@param body? string
---@return boolean, string?
function M.submit_review(pr, review_id, event, body)
  local endpoint = string.format("/repos/%s/pulls/%d/reviews/%s/events", pr.repo, pr.number, review_id)

  local input = { event = event }
  if body and body ~= "" then
    input.body = body
  end

  local _, err = gh.api(endpoint, input)
  if err then
    return false, err
  end

  return true, nil
end

-- Check if git working directory is clean
---@return boolean is_clean
---@return string? error
function M.is_git_clean()
  local output, err = gh.exec("git status --porcelain")
  if err then
    return false, "Failed to check git status"
  end
  -- Empty output means clean
  return output == nil or output == "" or output:match("^%s*$") ~= nil, nil
end

-- Fetch a remote ref
---@param ref string
---@return boolean success
---@return string? error
function M.fetch_ref(ref)
  local _, err = gh.exec("git fetch origin " .. ref .. " 2>&1")
  if err then
    return false, "Failed to fetch " .. ref
  end
  return true, nil
end

-- Clear cache
function M.clear_cache()
  cache.current_pr = nil
  cache.repo_info = nil
end

return M
