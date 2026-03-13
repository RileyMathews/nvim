-- PR Review Picker - File selection using Snacks picker

local M = {}

local pr_review = nil

local function get_pr_review()
  if not pr_review then
    pr_review = require("custom.pr_review")
  end
  return pr_review
end

-- Open picker with open PRs in the current repo
---@param opts? {repo?: string}
function M.open_prs(opts)
  opts = opts or {}

  Snacks.picker.gh_pr({
    title = "  Select PR to Review",
    state = "open",
    repo = opts.repo,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      vim.schedule(function()
        get_pr_review().open({ pr = item.number, repo = item.repo })
      end)
    end,
  })
end

-- Format file item for display
---@param item table
---@return snacks.picker.Highlight[]
local function format_file(item)
  local ret = {} ---@type snacks.picker.Highlight[]

  -- Check if file is reviewed
  local is_reviewed = get_pr_review().is_file_reviewed(item.path)

  -- Use dimmed highlight for reviewed files
  local dim_hl = is_reviewed and "Comment" or nil

  -- Reviewed checkmark
  if is_reviewed then
    ret[#ret + 1] = { "[x] ", "DiagnosticOk" }
  else
    ret[#ret + 1] = { "[ ] ", "Comment" }
  end

  -- Status icon
  local status_icons = {
    added = "+",
    deleted = "-",
    modified = "~",
    renamed = "R",
  }
  local status_hl = {
    added = "DiffAdd",
    deleted = "DiffDelete",
    modified = "DiffChange",
    renamed = "DiffText",
  }

  local icon = status_icons[item.status] or "~"
  local hl = dim_hl or status_hl[item.status] or "DiffChange"

  ret[#ret + 1] = { icon .. " ", hl }

  -- File icon based on filetype
  local file_icon, file_hl
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local ext = item.path:match("%.([^%.]+)$")
    file_icon, file_hl = devicons.get_icon(item.path, ext, { default = true })
  end
  file_icon = file_icon or "*"
  file_hl = dim_hl or file_hl or "Normal"
  ret[#ret + 1] = { file_icon .. " ", file_hl }

  -- File path
  ret[#ret + 1] = { item.path, dim_hl }

  -- Change stats
  ret[#ret + 1] = { " " }
  if item.additions > 0 then
    ret[#ret + 1] = { "+" .. item.additions, dim_hl or "DiffAdd" }
  end
  if item.deletions > 0 then
    if item.additions > 0 then
      ret[#ret + 1] = { "/", dim_hl }
    end
    ret[#ret + 1] = { "-" .. item.deletions, dim_hl or "DiffDelete" }
  end

  -- Comment indicator
  local state = get_pr_review().get_state()
  local comment_count = 0
  local unresolved_count = 0
  for _, thread in ipairs(state.threads or {}) do
    if thread.path == item.path then
      comment_count = comment_count + 1
      if not thread.resolved then
        unresolved_count = unresolved_count + 1
      end
    end
  end

  if comment_count > 0 then
    ret[#ret + 1] = { "  " }
    local comment_hl = dim_hl or (unresolved_count > 0 and "DiagnosticWarn" or "DiagnosticHint")
    ret[#ret + 1] = { "[" .. comment_count .. "]", comment_hl }
    if unresolved_count > 0 and not is_reviewed then
      ret[#ret + 1] = { " (" .. unresolved_count .. " unresolved)", "DiagnosticWarn" }
    end
  end

  return ret
end

-- Build items list from state
local function build_items()
  local state = get_pr_review().get_state()
  local items = {}

  for i, file in ipairs(state.files or {}) do
    local is_reviewed = get_pr_review().is_file_reviewed(file.path)
    table.insert(items, {
      idx = i,
      text = file.path,
      path = file.path,
      status = file.status,
      additions = file.additions,
      deletions = file.deletions,
      file = file,
      reviewed = is_reviewed,
      -- Sort order: unreviewed (0) first, then reviewed (1), then by original index
      sort_order = is_reviewed and 1 or 0,
    })
  end

  return items
end

-- Open the file picker
function M.open()
  local state = get_pr_review().get_state()
  local pr = state.pr

  if not pr then
    Snacks.notify.warn("No PR loaded", { title = "PR Review" })
    return
  end

  Snacks.picker({
    title = string.format("  PR #%d: %s", pr.number, pr.title),
    items = build_items(),
    format = function(item)
      return format_file(item)
    end,
    preview = "none", -- No preview - we use full diff view
    layout = {
      preset = "select",
      layout = {
        width = 0.6,
        min_width = 80,
        height = 0.5,
      },
    },
    sort = { fields = { "sort_order", "idx" } }, -- Unreviewed first, then by original order
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          get_pr_review().open_file(item.idx)
        end)
      end
    end,
    win = {
      input = {
        keys = {
          ["<c-r>"] = {
            function(picker)
              picker:close()
              vim.schedule(function()
                get_pr_review().refresh()
                M.open()
              end)
            end,
            mode = { "n", "i" },
            desc = "Refresh",
          },
          ["<c-d>"] = {
            function(picker)
              local item = picker:current()
              if item then
                local state = get_pr_review().get_state()
                -- Toggle reviewed status
                if state.reviewed_files[item.path] then
                  state.reviewed_files[item.path] = nil
                else
                  state.reviewed_files[item.path] = true
                end
                -- Refresh the picker
                picker:close()
                vim.schedule(function()
                  M.open()
                end)
              end
            end,
            mode = { "n", "i" },
            desc = "Toggle reviewed",
          },
        },
      },
      list = {
        keys = {
          ["d"] = {
            function(picker)
              local item = picker:current()
              if item then
                local state = get_pr_review().get_state()
                -- Toggle reviewed status
                if state.reviewed_files[item.path] then
                  state.reviewed_files[item.path] = nil
                else
                  state.reviewed_files[item.path] = true
                end
                -- Refresh the picker
                picker:close()
                vim.schedule(function()
                  M.open()
                end)
              end
            end,
            desc = "Toggle reviewed",
          },
        },
      },
    },
  })
end

-- Open picker showing pending review comments
function M.open_pending_comments()
  local state = get_pr_review().get_state()

  if not state.pending_review or not state.pending_review.comments or #state.pending_review.comments == 0 then
    Snacks.notify.info("No pending review comments", { title = "PR Review" })
    return
  end

  -- Build items from pending review comments
  local items = {}
  for i, comment in ipairs(state.pending_review.comments) do
    local line = comment.line or 0
    local path = comment.path or "unknown"
    table.insert(items, {
      idx = i,
      text = path .. ":" .. line .. " " .. (comment.body or ""),
      comment = comment,
      path = path,
      line = line,
      start_line = comment.start_line,
      body = comment.body or "",
    })
  end

  local function handle_edit(picker)
    local item = picker:current()
    if not item then
      return
    end
    picker:close()
    vim.schedule(function()
      require("custom.pr_shared.reply").run({
        title = "Edit comment on " .. item.path .. ":" .. item.line,
        notify_title = "PR Review",
        template = item.body,
        posting_message = "Updating comment...",
        success_message = "Comment updated",
        submit = function(body)
          return require("custom.pr_review.api").update_review_comment(item.comment.id, body)
        end,
        map_error = function(err)
          return "Failed to update comment: " .. (err or "unknown error")
        end,
        on_success = function()
          get_pr_review().refresh()
        end,
      })
    end)
  end

  local function handle_delete(picker)
    local item = picker:current()
    if not item then
      return
    end
    picker:close()
    vim.schedule(function()
      vim.ui.select({ "Yes", "No" }, { prompt = "Delete this comment?" }, function(choice)
        if choice == "Yes" then
          local ok, err = require("custom.pr_review.api").delete_review_comment(item.comment.id)
          if ok then
            Snacks.notify.info("Comment deleted", { title = "PR Review" })
            get_pr_review().refresh()
            vim.schedule(function()
              M.open_pending_comments()
            end)
          else
            Snacks.notify.error("Failed to delete comment: " .. (err or "unknown error"), { title = "PR Review" })
          end
        end
      end)
    end)
  end

  Snacks.picker({
    title = "  Pending Review Comments",
    items = items,
    format = function(item)
      local ret = {} ---@type snacks.picker.Highlight[]

      -- File icon based on filetype
      local file_icon, file_hl
      local ok, devicons = pcall(require, "nvim-web-devicons")
      if ok then
        local ext = item.path:match("%.([^%.]+)$")
        file_icon, file_hl = devicons.get_icon(item.path, ext, { default = true })
      end
      file_icon = file_icon or "*"
      file_hl = file_hl or "Normal"
      ret[#ret + 1] = { file_icon .. " ", file_hl }

      -- File path with line number
      local location = item.path .. ":"
      if item.start_line then
        location = location .. item.start_line .. "-" .. item.line
      else
        location = location .. item.line
      end
      ret[#ret + 1] = { location }

      -- Separator
      ret[#ret + 1] = { " — " }

      -- Body preview: first 60 chars, single-lined
      local preview = item.body:gsub("\n", " "):sub(1, 60)
      ret[#ret + 1] = { preview, "Comment" }

      return ret
    end,
    preview = "none",
    layout = {
      preset = "select",
      layout = {
        width = 0.7,
        min_width = 90,
        height = 0.5,
      },
    },
    sort = { fields = { "idx" } },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          require("custom.pr_review.diff").jump_to_line(item.path, item.line, "right")
        end)
      end
    end,
    win = {
      input = {
        keys = {
          ["e"] = { handle_edit, mode = { "n", "i" }, desc = "Edit comment" },
          ["<c-d>"] = { handle_delete, mode = { "n", "i" }, desc = "Delete comment" },
        },
      },
      list = {
        keys = {
          ["e"] = { handle_edit, mode = { "n", "i" }, desc = "Edit comment" },
          ["d"] = { handle_delete, desc = "Delete comment" },
        },
      },
    },
  })
end

return M
