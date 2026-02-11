local M = {}

local frames = { "|", "/", "-", "\\" }

---@param opts? {title?:string, id?:string, interval?:number, stage?:string}
---@return {update:fun(stage?:string), stop:fun(ok?:boolean, msg?:string)}
function M.start(opts)
  opts = opts or {}
  local title = opts.title or "PR Review"
  local id = opts.id or "pr_review_loading"
  local interval = opts.interval or 120
  local state = {
    running = true,
    stage = opts.stage or "Loading...",
    frame = 1,
  }

  local timer = vim.loop.new_timer()

  local function render(message, timeout)
    Snacks.notify.info(message, { title = title, id = id, timeout = timeout })
  end

  local function tick()
    if not state.running then
      return
    end
    local frame = frames[state.frame]
    state.frame = (state.frame % #frames) + 1
    vim.schedule(function()
      render(frame .. " " .. state.stage, false)
    end)
  end

  timer:start(0, interval, tick)

  local function update(stage)
    if stage then
      state.stage = stage
    end
    tick()
  end

  local function stop(ok, msg)
    if not state.running then
      return
    end
    state.running = false
    timer:stop()
    timer:close()

    vim.schedule(function()
      if msg then
        render(msg, 1200)
        return
      end
      if ok then
        render("Loaded", 800)
      else
        render("Canceled", 800)
      end
    end)
  end

  return {
    update = update,
    stop = stop,
  }
end

return M
