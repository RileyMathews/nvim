local comments_utils = require('ghlite.comments_utils')
local config = require('ghlite.config')
local gh = require('ghlite.gh')
local pr_utils = require('ghlite.pr_utils')
local state = require('ghlite.state')
local utils = require('ghlite.utils')

--- @class GHLiteQfEntry
--- @field filename string
--- @field lnum integer
--- @field text string

--- @class GHLiteDiagnostic
--- @field lnum integer
--- @field col integer
--- @field message string
--- @field severity integer
--- @field source string

--- @class GHLiteCommentsModule
local M = {}

--- @param resp table
--- @return boolean
local function is_comment_response(resp)
  return resp ~= nil
    and resp['errors'] == nil
    and resp['message'] == nil
    and resp.id ~= nil
    and resp.html_url ~= nil
    and resp.path ~= nil
    and resp.line ~= nil
    and resp.user ~= nil
    and resp.body ~= nil
    and resp.updated_at ~= nil
    and resp.diff_hunk ~= nil
end

--- @param resp table
--- @return string
local function response_error_message(resp)
  if resp ~= nil and resp['message'] ~= nil then
    return resp['message']
  end
  if resp ~= nil and resp['errors'] ~= nil and resp['errors'][1] ~= nil and resp['errors'][1]['message'] ~= nil then
    return resp['errors'][1]['message']
  end
  return 'Unknown GitHub API response.'
end

--- @return nil
local function load_comments_to_quickfix_list()
  --- @type GHLiteQfEntry[]
  local qf_entries = {}

  --- @type string[]
  local filenames = {}
  for fn in pairs(state.comments_list) do
    table.insert(filenames, fn)
  end
  table.sort(filenames)

  for _, filename in pairs(filenames) do
    local comments_in_file = state.comments_list[filename]

    table.sort(comments_in_file, function(a, b)
      return a.line < b.line
    end)

    for _, comment in pairs(comments_in_file) do
      if #comment.comments > 0 then
        table.insert(qf_entries, {
          filename = filename,
          lnum = comment.line,
          text = comment.content,
        })
      end
    end
  end

  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries, 'r')
    vim.cmd('cfirst')
  else
    utils.notify('No GH comments loaded.')
  end
end

--- @return nil
M.load_comments = function()
  pr_utils.get_checked_out_pr(function(checked_out_pr)
    if checked_out_pr == nil then
      utils.notify('No PR to work with.', vim.log.levels.WARN)
      return
    end

    utils.notify('Comment loading started...')
    gh.load_comments(checked_out_pr.number, function(comments_list)
      state.comments_list = comments_list
      vim.schedule(function()
        load_comments_to_quickfix_list()

        M.load_comments_on_current_buffer()
        utils.notify('Comments loaded.')
      end)
    end)
  end)
end

--- @param pr_to_load integer
--- @param cb GHLiteVoidCallback
M.load_comments_only = function(pr_to_load, cb)
  gh.load_comments(pr_to_load, function(comments_list)
    state.comments_list = comments_list
    cb()
  end)
end

--- @return nil
M.load_comments_on_current_buffer = function()
  vim.schedule(function()
    local current_buffer = vim.api.nvim_get_current_buf()
    M.load_comments_on_buffer(current_buffer)
  end)
end

--- @param bufnr integer
M.load_comments_on_buffer = function(bufnr)
  if bufnr == state.diff_buffer_id then
    M.load_comments_on_diff_buffer(bufnr)
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(bufnr)

  if M.is_in_diffview(buf_name) then
    if state.selected_PR == nil then
      return
    end

    M.get_diffview_filename(buf_name, function(filename)
      M.load_comments_on_buffer_by_filename(bufnr, filename)
    end)
    return
  end

  -- Handle CodeDiff buffers
  if M.is_in_codediff(buf_name) then
    if state.selected_PR == nil then
      return
    end

    M.get_codediff_filename(buf_name, function(filename)
      if filename then
        M.load_comments_on_buffer_by_filename(bufnr, filename)
      end
    end)
    return
  end

  pr_utils.is_pr_checked_out(function(is_pr_checked_out)
    if not is_pr_checked_out then
      return
    end

    M.load_comments_on_buffer_by_filename(bufnr, buf_name)
  end)
end

--- @param bufnr integer
M.load_comments_on_diff_buffer = function(bufnr)
  config.log('load_comments_on_diff_buffer')
  --- @type GHLiteDiagnostic[]
  local diagnostics = {}

  for filename, comments in pairs(state.comments_list) do
    if state.filename_line_to_diff_line[filename] then
      for _, comment in pairs(comments) do
        local diff_line = state.filename_line_to_diff_line[filename][comment.line]
        if diff_line and #comment.comments > 0 then
          table.insert(diagnostics, {
            lnum = diff_line - 1,
            col = 0,
            message = comment.content,
            severity = vim.diagnostic.severity.INFO,
            source = 'GHLite',
          })
        end
      end
    end
  end

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      config.log('load_comments_on_diff_buffer: buffer no longer valid', bufnr)
      return
    end
    vim.diagnostic.set(vim.api.nvim_create_namespace('GHLiteDiffNamespace'), bufnr, diagnostics, {})
  end)
end

--- @param current_filename string
--- @param current_line integer
--- @return GroupedComment[]
M.get_conversations = function(current_filename, current_line)
  --- @type GroupedComment[]
  local conversations = {}
  if state.comments_list[current_filename] ~= nil then
    for _, comment in pairs(state.comments_list[current_filename]) do
      if current_line == comment.line then
        table.insert(conversations, comment)
      end
    end
  end
  return conversations
end

--- @param cb GHLiteFileLineCallback
local function get_current_filename_and_line(cb)
  vim.schedule(function()
    local current_buf = vim.api.nvim_get_current_buf()
    local current_start_line = vim.fn.line("'<")
    local current_line = vim.fn.line("'>")

    if current_line == 0 then
      current_start_line = vim.api.nvim_win_get_cursor(0)[1]
      current_line = current_start_line
    end

    local current_filename = vim.api.nvim_buf_get_name(current_buf)

    if current_buf == state.diff_buffer_id then
      --- @type FileNameAndLinePair
      local info = state.diff_line_to_filename_line[current_start_line]
      current_filename = info[1]
      current_start_line = info[2]
      info = state.diff_line_to_filename_line[current_line]
      current_line = info[2]
    elseif M.is_in_diffview(current_filename) then
      M.get_diffview_filename(current_filename, function(filename)
        cb(filename, current_start_line, current_line)
      end)
      return
    elseif M.is_in_codediff(current_filename) then
      M.get_codediff_filename(current_filename, function(filename)
        if filename then
          cb(filename, current_start_line, current_line)
        else
          cb(nil, nil, nil)
        end
      end)
      return
    else
      pr_utils.is_pr_checked_out(function(is_pr_checked_out)
        pr_utils.get_checked_out_pr(function(checked_out_pr)
          if not is_pr_checked_out then
            if checked_out_pr then
              utils.notify('Command canceled because of PR check out.', vim.log.levels.WARN)
            end
            cb(nil, nil, nil)
            return
          end
          cb(current_filename, current_start_line, current_line)
        end)
      end)
      return
    end

    cb(current_filename, current_start_line, current_line)
  end)
end

--- @return nil
M.comment_on_line = function()
  pr_utils.get_selected_pr(function(selected_pr)
    if selected_pr == nil then
      utils.notify('No PR selected/checked out', vim.log.levels.WARN)
      return
    end

    if state.active_review == nil or state.active_review_pr_number ~= selected_pr.number then
      utils.notify('No active pending review. Run create_review before commenting.', vim.log.levels.WARN)
      return
    end

    get_current_filename_and_line(function(current_filename, current_start_line, current_line)
      if current_filename == nil or current_start_line == nil or current_line == nil then
        utils.notify('You are on a branch without PR.', vim.log.levels.WARN)
        return
      end

      utils.get_git_root(function(git_root)
        if current_filename:sub(1, #git_root) ~= git_root then
          utils.notify('File is not under git folder.', vim.log.levels.ERROR)
          return
        end

        vim.schedule(function()
          --- @type GroupedComment[]
          local conversations = {}
          if current_start_line == current_line then
            conversations = M.get_conversations(current_filename, current_line)
          end

          local prompt = '<!-- Type your '
            .. (#conversations > 0 and 'reply' or 'comment')
            .. ' and :w to submit. Use :q to close. -->'

          utils.get_comment(
            (#conversations > 0 and 'PR reply' or 'PR comment') .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
            prompt,
            { prompt, '' },
            function(input)
              --- @param grouped_comment GroupedComment
              local function reply(grouped_comment)
                local reply_to = grouped_comment.comments[#grouped_comment.comments].node_id
                if reply_to == nil then
                  utils.notify('Cannot reply to this thread because the GitHub node_id is missing.', vim.log.levels.WARN)
                  return
                end

                utils.notify('Sending reply...')
                gh.add_pending_review_comment(
                  selected_pr.number,
                  state.active_review,
                  input,
                  nil,
                  nil,
                  nil,
                  reply_to,
                  function(resp)
                    if is_comment_response(resp) then
                      --- @cast resp GHLiteRawComment
                      utils.notify('Reply sent.')
                      local new_comment = comments_utils.convert_comment(resp)
                      table.insert(grouped_comment.comments, new_comment)
                      grouped_comment.content = comments_utils.prepare_content(grouped_comment.comments)
                      M.load_comments_on_current_buffer()
                    else
                      utils.notify('Failed to reply to comment: ' .. response_error_message(resp), vim.log.levels.WARN)
                    end
                  end
                )
              end

              if #conversations == 1 then
                reply(conversations[1])
              elseif #conversations > 1 then
                vim.ui.select(conversations, {
                  prompt = 'Select comment to reply to:',
                  format_item = function(comment)
                    return string.format('%s', vim.split(comment.content, '\n')[1])
                  end,
                }, function(comment)
                  if comment ~= nil then
                    reply(comment)
                  end
                end)
              else
                if current_filename:sub(1, #git_root) == git_root then
                  utils.notify('Sending comment...')
                  gh.add_pending_review_comment(
                    selected_pr.number,
                    state.active_review,
                    input,
                    current_filename:sub(#git_root + 2),
                    current_start_line,
                    current_line,
                    nil,
                    function(resp)
                      if is_comment_response(resp) then
                        --- @cast resp GHLiteRawComment
                        local new_comment = comments_utils.convert_comment(resp)
                        --- @type GroupedComment
                        local new_comment_group = {
                          id = resp.id,
                          line = current_line,
                          start_line = current_start_line,
                          url = resp.html_url,
                          comments = { new_comment },
                          content = comments_utils.prepare_content({ new_comment }),
                        }
                        if state.comments_list[current_filename] == nil then
                          state.comments_list[current_filename] = { new_comment_group }
                        else
                          table.insert(state.comments_list[current_filename], new_comment_group)
                        end

                        utils.notify('Comment sent.')
                        M.load_comments_on_current_buffer()
                      else
                        utils.notify('Failed to send comment: ' .. response_error_message(resp), vim.log.levels.WARN)
                      end
                    end
                  )
                end
              end
            end
          )
        end)
      end)
    end)
  end)
end

--- @param conversation GroupedComment
--- @return string[]
local function format_comment_float_lines(conversation)
  --- @type string[]
  local lines = {}

  if #conversation.comments > 0 then
    table.insert(lines, '🪓 Diff hunk:')
    for _, line in ipairs(vim.split(conversation.comments[1].diff_hunk, '\n')) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end

  table.insert(lines, 'URL: ' .. conversation.url)
  table.insert(lines, '')

  if
    #conversation.comments > 0
    and conversation.comments[1].start_line ~= vim.NIL
    and conversation.comments[1].start_line ~= conversation.comments[1].line
  then
    table.insert(
      lines,
      string.format('📓 Comment on lines %d to %d', conversation.comments[1].start_line, conversation.comments[1].line)
    )
    table.insert(lines, '')
  end

  for i, comment in ipairs(conversation.comments) do
    if i > 1 then
      table.insert(lines, '---')
      table.insert(lines, '')
    end

    table.insert(lines, string.format('✍️ %s at %s:', comment.user, comment.updated_at))
    for _, line in ipairs(vim.split(string.gsub(comment.body, '\r', ''), '\n')) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
  end

  return lines
end

--- @param conversation GroupedComment
local function open_comment_float(conversation)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'wipe'

  local lines = format_comment_float_lines(conversation)

  local width = math.max(60, math.floor(vim.o.columns * 0.7))
  local height = math.min(math.max(8, math.floor(vim.o.lines * 0.6)), math.max(1, #lines))
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
    title = ' GHLite Comment Thread ',
    title_pos = 'center',
  })

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.wo[win].wrap = true
  vim.wo[win].winblend = 0

  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true })
end

--- @return nil
M.open_comment = function()
  get_current_filename_and_line(function(current_filename, _, current_line)
    if current_filename == nil then
      utils.notify('You are on a branch without PR.', vim.log.levels.WARN)
      return
    end

    local conversations = M.get_conversations(current_filename, current_line)

    vim.schedule(function()
      if #conversations == 1 then
        open_comment_float(conversations[1])
      elseif #conversations > 1 then
        vim.ui.select(conversations, {
          prompt = 'Select conversation to open:',
          format_item = function(comment)
            return string.format('%s', vim.split(comment.content, '\n')[1])
          end,
        }, function(comment)
          if comment ~= nil then
            open_comment_float(comment)
          end
        end)
      else
        utils.notify('No comments found on this line.', vim.log.levels.WARN)
      end
    end)
  end)
end

--- @param current_filename string
--- @param current_line integer
--- @param cb GHLiteCommentListsCallback
local function get_own_comments(current_filename, current_line, cb)
  local conversations = M.get_conversations(current_filename, current_line)
  gh.get_user(function(user)
    --- @type Comment[]
    local comments_list = {}
    --- @type GroupedComment[]
    local conversations_list = {}

    for _, convo in pairs(conversations) do
      for _, comment in pairs(convo.comments) do
        if comment.user == user then
          table.insert(comments_list, comment)
          table.insert(conversations_list, convo)
        end
      end
    end

    cb(comments_list, conversations_list)
  end)
end

--- @param comment Comment
--- @param conversation GroupedComment
--- @return nil
local function edit_comment_body(comment, conversation)
  local prompt = '<!-- Change your comment and :w to submit. Use :q to close. -->'

  utils.get_comment(
    'PR edit comment' .. ' (' .. os.date('%Y-%m-%d %H:%M:%S') .. ')',
    prompt,
    vim.split(prompt .. '\n' .. comment.body, '\n'),
    function(input)
      utils.notify('Updating comment...')
      gh.update_comment(comment.id, input, function(resp)
        if resp['errors'] == nil then
          --- @cast resp GHLiteRawComment
          utils.notify('Comment updated.')
          comment.body = resp.body
          conversation.content = comments_utils.prepare_content(conversation.comments)

          M.load_comments_on_current_buffer()
        else
          utils.notify('Failed to update the comment.', vim.log.levels.ERROR)
        end
      end)
    end
  )
end

--- @return nil
M.update_comment = function()
  get_current_filename_and_line(function(current_filename, _, current_line)
    if current_filename == nil then
      utils.notify('You are on a branch without PR.', vim.log.levels.WARN)
      return
    end

    get_own_comments(current_filename, current_line, function(comments_list, conversations_list)
      if #comments_list == 0 then
        utils.notify('No comments found that could be updated.', vim.log.levels.WARN)
        return
      end

      vim.schedule(function()
        vim.ui.select(comments_list, {
          prompt = 'Select comment to update:',
          format_item = function(comment)
            return string.format('%s: %s', comment.updated_at, vim.split(comment.body, '\n')[1])
          end,
        }, function(comment, idx)
          if comment ~= nil then
            edit_comment_body(comment, conversations_list[idx])
          end
        end)
      end)
    end)
  end)
end

--- @return nil
M.delete_comment = function()
  get_current_filename_and_line(function(current_filename, _, current_line)
    if current_filename == nil then
      utils.notify('You are on a branch without PR.', vim.log.levels.WARN)
      return
    end

    get_own_comments(current_filename, current_line, function(comments_list, conversations_list)
      if #comments_list == 0 then
        utils.notify('No comments found that could be deleted.', vim.log.levels.WARN)
        return
      end

      vim.schedule(function()
        vim.ui.select(comments_list, {
          prompt = 'Select comment to delete:',
          format_item = function(comment)
            return string.format('%s: %s', comment.updated_at, vim.split(comment.body, '\n')[1])
          end,
        }, function(comment, idx)
          if comment ~= nil then
            utils.notify('Deleting comment...')
            gh.delete_comment(comment.id, function()
              local function is_non_deleted_comment(c)
                return c.id ~= comment.id
              end

              local convo = conversations_list[idx]
              convo.comments = utils.filter_array(convo.comments, is_non_deleted_comment)
              convo.content = comments_utils.prepare_content(convo.comments)

              utils.notify('Comment deleted.')
              M.load_comments_on_current_buffer()
            end)
          end
        end)
      end)
    end)
  end)
end

--- @param buf_name string
--- @return boolean
M.is_in_diffview = function(buf_name)
  return string.sub(buf_name, 1, 11) == 'diffview://'
end

--- @param buf_name string
--- @return boolean
M.is_in_codediff = function(buf_name)
  return string.sub(buf_name, 1, 12) == 'codediff:///'
end

--- @param buf_name string
--- @param cb GHLiteStringCallback
M.get_diffview_filename = function(buf_name, cb)
  local view = require('diffview.lib').get_current_view()
  local file = view:infer_cur_file()
  if file then
    pr_utils.get_selected_pr(function(selected_pr)
      if selected_pr == nil then
        utils.notify('No PR selected/checked out', vim.log.levels.WARN)
        return
      end

      local full_name = file.absolute_path

      config.log('get_diffview_filename. buf_name', buf_name)
      config.log('get_diffview_filename. full_name', full_name)
      config.log('get_diffview_filename. selected_pr.headRefOid', selected_pr.headRefOid)

      local commit_abbrev = selected_pr.headRefOid:sub(1, 11)

      local found = string.find(buf_name, commit_abbrev, 1, true)
      if found then
        cb(full_name)
      end
    end)
  end
end

--- @param buf_name string
--- @param cb GHLiteStringNilCallback
M.get_codediff_filename = function(buf_name, cb)
  -- Try using CodeDiff API first (Option C)
  local has_codediff, virtual_file = pcall(require, 'codediff.core.virtual_file')

  if has_codediff and virtual_file.parse_url then
    local git_root, commit, filepath = virtual_file.parse_url(buf_name)

    if not git_root or not commit or not filepath then
      config.log('get_codediff_filename: failed to parse URL', buf_name)
      cb(nil)
      return
    end

    -- Verify commit hash matches PR's headRefOid
    pr_utils.get_selected_pr(function(selected_pr)
      if selected_pr == nil then
        utils.notify('No PR selected/checked out', vim.log.levels.WARN)
        cb(nil)
        return
      end

      config.log('get_codediff_filename. buf_name', buf_name)
      config.log('get_codediff_filename. git_root', git_root)
      config.log('get_codediff_filename. commit', commit)
      config.log('get_codediff_filename. filepath', filepath)
      config.log('get_codediff_filename. selected_pr.headRefOid', selected_pr.headRefOid)

      -- Check if commit matches PR (support both full and abbreviated hash)
      local commit_abbrev = selected_pr.headRefOid:sub(1, #commit)

      if commit == selected_pr.headRefOid or commit_abbrev == commit then
        -- Construct full absolute path
        local full_path = git_root .. '/' .. filepath
        cb(full_path)
      else
        config.log('get_codediff_filename: commit mismatch', commit, selected_pr.headRefOid)
        cb(nil)
      end
    end)
  else
    -- Fallback: manual parsing (Option A)
    config.log('get_codediff_filename: CodeDiff API not available, using manual parsing')

    -- Pattern: codediff:///<git-root>///<commit>/<filepath>
    local pattern = '^codediff:///(.-)///([a-fA-F0-9]+)/(.+)$'
    local git_root, commit, filepath = buf_name:match(pattern)

    if git_root and commit and filepath then
      pr_utils.get_selected_pr(function(selected_pr)
        if selected_pr == nil then
          utils.notify('No PR selected/checked out', vim.log.levels.WARN)
          cb(nil)
          return
        end

        local commit_abbrev = selected_pr.headRefOid:sub(1, #commit)

        if commit == selected_pr.headRefOid or commit_abbrev == commit then
          local full_path = git_root .. '/' .. filepath
          cb(full_path)
        else
          cb(nil)
        end
      end)
    else
      config.log('get_codediff_filename: failed to parse buffer name', buf_name)
      cb(nil)
    end
  end
end

--- @param bufnr integer
--- @param filename string
M.load_comments_on_buffer_by_filename = function(bufnr, filename)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      config.log('load_comments_on_buffer_by_filename: buffer no longer valid', bufnr)
      return
    end

    config.log('load_comments_on_buffer filename', filename)
    if state.comments_list[filename] ~= nil then
      --- @type GHLiteDiagnostic[]
      local diagnostics = {}
      for _, comment in pairs(state.comments_list[filename]) do
        if #comment.comments > 0 then
          config.log('comment to diagnostics', comment)
          table.insert(diagnostics, {
            lnum = comment.line - 1,
            col = 0,
            message = comment.content,
            severity = vim.diagnostic.severity.INFO,
            source = 'GHLite',
          })
        end
      end

      vim.diagnostic.set(vim.api.nvim_create_namespace('GHLiteNamespace'), bufnr, diagnostics, {})
    end
  end)
end

return M
