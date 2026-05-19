local comments = require('ghlite.comments')
local config = require('ghlite.config')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local utils = require('ghlite.utils')

--- @class GHLitePrCommandsModule
local M = {}

--- @param pr PullRequest
local function load_active_review(pr)
  if state.active_review ~= nil and state.active_review_pr_number == pr.number then
    return
  end

  state.active_review_loading_pr_number = pr.number
  gh.get_pending_review(pr.number, function(review)
    if state.active_review_loading_pr_number ~= pr.number then
      return
    end

    state.active_review_loading_pr_number = nil

    if state.active_review ~= nil and state.active_review_pr_number == pr.number then
      return
    end

    state.active_review = review
    state.active_review_pr_number = review ~= nil and pr.number or nil
    if review ~= nil then
      utils.notify(string.format('Loaded pending review #%d.', review.id))
    else
      utils.notify('No pending review found. Run create_review before commenting.', vim.log.levels.INFO)
    end
  end)
end

--- @param number integer
--- @return nil
function M.open_pr_by_number(number)
  vim.notify('checking out relevant commits...')
  gh.get_pr_by_number(number, function(pr)
    if pr ~= nil then
      state.selected_PR = pr
      load_active_review(pr)
      gh.checkout_pr(number, M.load_pr_view)
    end
  end)
end

--- @return string[]
local function format_review_comments_for_pr_view()
  --- @type string[]
  local review_section = {}

  if state.comments_list and next(state.comments_list) then
    table.insert(review_section, '')
    table.insert(review_section, '---')
    table.insert(review_section, '')
    table.insert(review_section, '## 👀 Review Comments')
    table.insert(review_section, '')

    local filenames = {}
    for filename in pairs(state.comments_list) do
      table.insert(filenames, filename)
    end
    table.sort(filenames)

    for _, filename in pairs(filenames) do
      local comments_in_file = state.comments_list[filename]

      table.sort(comments_in_file, function(a, b)
        return a.line < b.line
      end)

      local comment_group_count = 0
      for _ in pairs(comments_in_file) do
        comment_group_count = comment_group_count + 1
      end

      local processed_groups = 0
      for _, comment_group in pairs(comments_in_file) do
        if #comment_group.comments > 0 then
          processed_groups = processed_groups + 1
          local relative_filename = filename:match('^.*/(.*)$') or filename
          table.insert(review_section, string.format('### 📄 %s:%d', relative_filename, comment_group.line))
          table.insert(review_section, '')

          for i, comment in ipairs(comment_group.comments) do
            local comment_body = string.gsub(comment.body, '\r', '')
            local comment_lines = vim.split(comment_body, '\n')

            if i == 1 then
              table.insert(review_section, string.format('**👤 %s** · %s', comment.user, comment.updated_at))

              -- Show diff hunk for the first comment only
              if comment.diff_hunk and comment.diff_hunk ~= '' then
                table.insert(review_section, '')
                table.insert(review_section, '**💻 Code:**')
                table.insert(review_section, '```diff')
                for _, hunk_line in ipairs(vim.split(comment.diff_hunk, '\n')) do
                  table.insert(review_section, hunk_line)
                end
                table.insert(review_section, '```')
                table.insert(review_section, '')
              end
            else
              table.insert(review_section, string.format('↳ **👤 %s** · %s', comment.user, comment.updated_at))
            end

            for _, line in ipairs(comment_lines) do
              table.insert(review_section, '> ' .. line)
            end
            table.insert(review_section, '')
          end

          if processed_groups < comment_group_count or filename ~= filenames[#filenames] then
            table.insert(review_section, '---')
            table.insert(review_section, '')
          end
        end
      end
    end
  end

  return review_section
end

--- @param pr_info PullRequestInfo|nil
local function show_pr_info(pr_info)
  if pr_info == nil then
    utils.notify('PR view load failed', vim.log.levels.ERROR)
    return
  end

  vim.schedule(function()
    --- @type string[]
    local pr_view = {
      '## 📋 PR Info',
      string.format('🔢 **#%d** %s', pr_info.number, pr_info.title),
      string.format('👤 **Author:** %s', pr_info.author.login),
      string.format('🕐 **Created:** %s', pr_info.createdAt),
      string.format('🔗 **URL:** %s', pr_info.url),
      string.format('📁 **Changed files:** %d', pr_info.changedFiles),
    }

    if pr_info.isDraft then
      table.insert(pr_view, '📝 **Status:** Draft')
    end

    if #pr_info.labels > 0 then
      local labels = '🏷️ **Labels:** '
      for idx, label in pairs(pr_info.labels) do
        labels = labels .. (idx > 1 and ', ' or '') .. label.name
      end
      table.insert(pr_view, labels)
    end

    if #pr_info.reviews > 0 then
      -- Build map of reviewer to most recent review state
      -- Reviews are returned in chronological order, so later entries are more recent
      local reviewer_states = {}
      for _, review in ipairs(pr_info.reviews) do
        local reviewer = review.author.login
        -- Skip if it's the PR author
        if reviewer ~= pr_info.author.login then
          -- Map API state to human-readable format
          local state_label = review.state
          if review.state == 'APPROVED' then
            state_label = 'Approved'
          elseif review.state == 'CHANGES_REQUESTED' then
            state_label = 'Requested Changes'
          elseif review.state == 'COMMENTED' then
            state_label = 'Commented'
          end
          -- Simply store/overwrite - later entries in the array are more recent
          reviewer_states[reviewer] = state_label
        end
      end
      
      -- Build the activity summary line
      if next(reviewer_states) then
        local activity_parts = {}
        for reviewer, state in pairs(reviewer_states) do
          table.insert(activity_parts, string.format('%s (%s)', reviewer, state))
        end
        -- Sort alphabetically for consistent display
        table.sort(activity_parts)
        table.insert(pr_view, '📊 **Activity Summary:** ' .. table.concat(activity_parts, ', '))
      end
    end

    table.insert(pr_view, '')
    table.insert(pr_view, '---')
    table.insert(pr_view, '')
    table.insert(pr_view, '## 📝 Description')
    table.insert(pr_view, '')
    local body = string.gsub(pr_info.body, '\r', '')
    for _, line in ipairs(vim.split(body, '\n')) do
      table.insert(pr_view, line)
    end

    if #pr_info.comments > 0 then
      table.insert(pr_view, '')
      table.insert(pr_view, '---')
      table.insert(pr_view, '')
      table.insert(pr_view, '## 💬 Discussion')
      table.insert(pr_view, '')

      for i, comment in ipairs(pr_info.comments) do
        table.insert(pr_view, string.format('### 👤 %s · %s', comment.author.login, comment.createdAt))
        table.insert(pr_view, '')

        local comment_body = string.gsub(comment.body, '\r', '')

        -- NOTE: naive check if it is HTML comment
        if config.s.html_comments_command ~= false and comment.body:match('<%s*[%w%-]+.-%s*>') ~= nil then
          local success, result = pcall(function()
            return vim.system(config.s.html_comments_command, { stdin = comment.body }):wait()
          end)
          if success then
            comment_body = result.stdout
          end
        end

        for _, line in ipairs(vim.split(comment_body, '\n')) do
          table.insert(pr_view, line)
        end

        -- Add separator between comments, but not after the last one
        if i < #pr_info.comments then
          table.insert(pr_view, '')
          table.insert(pr_view, '---')
          table.insert(pr_view, '')
        end
      end
    end

    -- Load review comments and add them to the PR view
    comments.load_comments_only(pr_info.number, function()
      vim.schedule(function()
        local review_section = format_review_comments_for_pr_view()
        if #review_section > 0 then
          local buf = vim.api.nvim_get_current_buf()
          --- @type string[]
          local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

          local insert_position = #current_lines

          for i, line in ipairs(review_section) do
            table.insert(current_lines, insert_position + i, line)
          end

          -- Temporarily make buffer modifiable to update it
          vim.bo[buf].readonly = false
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, current_lines)
          vim.bo[buf].readonly = true
          vim.bo[buf].modifiable = false
        end
      end)
    end)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'PR View: ' .. pr_info.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')')

    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].filetype = 'markdown'

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, pr_view)

    if config.s.view_split then
      vim.api.nvim_command(config.s.view_split)
    end
    vim.api.nvim_set_current_buf(buf)

    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false

    utils.notify('PR view loaded.')
  end)
end

--- @param selected_pr PullRequest|nil
local function load_pr_view_for_pr(selected_pr)
  if selected_pr == nil then
    utils.notify('No PR selected/checked out', vim.log.levels.WARN)
    return
  end

  utils.notify('PR view loading started...')

  gh.get_pr_info(selected_pr.number, show_pr_info)
end

--- @return nil
function M.load_pr_view()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr ~= nil and (state.active_review == nil or state.selected_PR == nil or state.selected_PR.number ~= selected_pr.number) then
      load_active_review(selected_pr)
    end
    load_pr_view_for_pr(selected_pr)
  end)
end

--- @return nil
function M.create_review()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    if state.active_review ~= nil then
      if state.active_review_pr_number == selected_pr.number then
        utils.notify(string.format('Pending review #%d is already active.', state.active_review.id))
        return
      end

      state.active_review = nil
      state.active_review_pr_number = nil
    end

    utils.notify('Creating pending review...')
    gh.create_pending_review(selected_pr.number, function(resp)
      if resp['errors'] == nil then
        --- @cast resp GHLiteReview
        state.active_review = resp
        state.active_review_pr_number = selected_pr.number
        state.active_review_loading_pr_number = nil
        utils.notify(string.format('Pending review #%d created.', resp.id))
      else
        utils.notify('Failed to create pending review.', vim.log.levels.ERROR)
      end
    end)
  end)
end

--- @param on_success fun()|nil
M.comment_on_pr = function(on_success)
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    vim.schedule(function()
      local prompt = '<!-- Type your PR comment and :w to comment. Use :q to close. -->'

      utils.get_comment(
        'PR Comment: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
        prompt,
        { prompt, '' },
        function(input)
          utils.notify('Sending comment...')

          gh.new_pr_comment(selected_pr, input, function(resp)
            if resp ~= nil then
              utils.notify('Comment sent.')
              if type(on_success) == 'function' then
                on_success()
              end
            else
              utils.notify('Failed to send comment.', vim.log.levels.WARN)
            end
          end)
        end
      )
    end)
  end)
end

--- @return nil
function M.submit_review()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected to submit review', vim.log.levels.ERROR)
      return
    end

    vim.schedule(function()
      local review_actions = {
        { label = 'Approve', action = 'approve', prompt = nil },
        {
          label = 'Request changes',
          action = 'request_changes',
          prompt = '<!-- Type your comment and :w to request changes. Use :q to close. -->',
        },
        {
          label = 'Submit review comment',
          action = 'comment',
          prompt = '<!-- Type your comment and :w to submit a review comment. Use :q to close. -->',
        },
      }

      vim.ui.select(review_actions, {
        prompt = 'Submit PR review:',
        format_item = function(item)
          return item.label
        end,
      }, function(selected_action)
        if selected_action == nil then
          return
        end

        local function submit(body)
          utils.notify('PR review submit started...')
          if state.active_review ~= nil and state.active_review_pr_number == selected_pr.number then
            gh.submit_pending_review(selected_pr.number, state.active_review.id, selected_action.action, body, function()
              state.active_review = nil
              state.active_review_pr_number = nil
              utils.notify('Pending PR review submitted.')
            end)
          else
            gh.submit_review(selected_pr.number, selected_action.action, body, function()
              utils.notify('PR review submit finished.')
            end)
          end
        end

        if selected_action.prompt == nil then
          submit(nil)
          return
        end

        utils.get_comment(
          'PR Review: ' .. selected_pr.number .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
          selected_action.prompt,
          { selected_action.prompt, '' },
          submit
        )
      end)
    end)
  end)
end

return M
