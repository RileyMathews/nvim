local pickers_util = require("99.extensions.pickers")
local M = {}

--- @param list string[]
--- @param value string
--- @return number
local function index_of(list, value)
  for i, item in ipairs(list) do
    if item == value then
      return i
    end
  end
  return 1
end

--- @param provider _99.Providers.BaseProvider?
function M.select_model(provider)
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.notify(
      "99: snacks.nvim (picker) is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  pickers_util.get_models(provider, function(models, current)
    local items = {}
    for _, model in ipairs(models) do
      table.insert(items, { text = model })
    end

    snacks.picker.pick({
      title = "99: Select Model (current: " .. current .. ")",
      items = items,
      format = "text",
      preview = false,
      layout = { preset = "select" },
      on_show = function(self)
        -- move cursor to current model
        local idx = index_of(models, current)
        self.list:move(idx)
      end,
      confirm = function(self, item)
        self:close()
        if item then
          pickers_util.on_model_selected(item.text)
        end
      end,
    })
  end)
end

function M.select_provider()
  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.picker then
    vim.notify(
      "99: snacks.nvim (picker) is required for this extension",
      vim.log.levels.ERROR
    )
    return
  end

  local info = pickers_util.get_providers()

  local items = {}
  for _, name in ipairs(info.names) do
    table.insert(items, { text = name })
  end

  snacks.picker.pick({
    title = "99: Select Provider (current: " .. info.current .. ")",
    items = items,
    format = "text",
    preview = false,
    layout = { preset = "select" },
    on_show = function(self)
      local idx = index_of(info.names, info.current)
      self.list:move(idx)
    end,
    confirm = function(self, item)
      self:close()
      if item then
        pickers_util.on_provider_selected(item.text, info.lookup)
      end
    end,
  })
end

return M
