local M = {}

---@class PRSharedReply.Opts
---@field title string
---@field notify_title? string
---@field posting_message? string
---@field success_message? string|fun(result: any): string
---@field empty_message? string
---@field template? string
---@field allow_empty? boolean
---@field submit fun(body: string): boolean, string?, any?
---@field on_success? fun(result: any, body: string)
---@field map_error? fun(err: string|nil, result: any): string

---@param opts PRSharedReply.Opts
function M.open_editor(opts)
  local submitted = false

  local function submit(win)
    if submitted then
      return
    end

    local body = win:text() or ""
    if not opts.allow_empty and not body:match("%S") then
      Snacks.notify.warn(opts.empty_message or "Comment cannot be empty", { title = opts.notify_title or "PR" })
      return
    end

    submitted = true
    win:close()
    vim.schedule(function()
      opts.on_submit(body)
    end)
  end

  local scratch = Snacks.scratch({
    ft = "markdown",
    name = opts.title,
    template = opts.template or "",
    autowrite = false,
    win = {
      width = 0.6,
      height = 15,
      border = "rounded",
      title = " " .. opts.title .. " ",
      title_pos = "center",
      footer = " :w Submit | <Esc> Cancel ",
      footer_pos = "center",
    },
  })

  if scratch and scratch.buf then
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = scratch.buf,
      callback = function()
        submit(scratch)
      end,
    })
  end
end

---@param opts PRSharedReply.Opts
function M.run(opts)
  local notify_title = opts.notify_title or "PR"

  M.open_editor({
    title = opts.title,
    notify_title = notify_title,
    empty_message = opts.empty_message or "Comment cannot be empty",
    template = opts.template or "",
    allow_empty = opts.allow_empty == true,
    on_submit = function(body)
      Snacks.notify.info(opts.posting_message or "Submitting comment...", { title = notify_title })

      local success, err, result = opts.submit(body)
      if success then
        local msg = opts.success_message or "Comment submitted"
        if type(msg) == "function" then
          msg = msg(result)
        end
        Snacks.notify.info(msg, { title = notify_title })
        if opts.on_success then
          opts.on_success(result, body)
        end
      else
        local msg = opts.map_error and opts.map_error(err, result) or ("Failed to post reply: " .. (err or "unknown error"))
        Snacks.notify.error(msg, { title = notify_title })
      end
    end,
  })
end

---@param opts PRSharedReply.Opts
function M.reply(opts)
  return M.run(opts)
end

return M
