require("custom.options")
require("custom.lazy_setup")
require("custom.keymaps")
require("custom.hspec").setup()
require("custom.auto_commands")

local ghlite_config = {
  debug = false,
  view_split = '',
  diff_split = 'vsplit',
  diff_tool = 'diffview',
  comment_split = 'split',
  open_command = 'open',
  merge = {
    approved = '--squash',
    nonapproved = '--auto --squash',
  },
  html_comments_command = { 'lynx', '-stdin', '-dump' },
  keymaps = {
    diff = {
      open_file = 'gf',
      open_file_tab = '',
      open_file_split = 'o',
      open_file_vsplit = 'O',
      approve = 'cA',
      request_changes = 'cR',
    },
    comment = {
      send_comment = 'c<CR>',
    },
    pr = {
      approve = 'cA',
      request_changes = 'cR',
      merge = 'cM',
      comment = 'ca',
      diff = 'cp',
    },
  },
}

local function reload_ghlite()
  for name, _ in pairs(package.loaded) do
    if name:match('^ghlite') then
      package.loaded[name] = nil
    end
  end

  require('ghlite').setup(ghlite_config)
  vim.notify('Reloaded ghlite')
end

vim.keymap.set('n', '<leader>rl', reload_ghlite, { desc = 'Reload GHLite' })

---@type table<number, {token:lsp.ProgressToken, msg:string, done:boolean}[]>
local progress = vim.defaulttable()
vim.api.nvim_create_autocmd("LspProgress", {
  ---@param ev {data: {client_id: integer, params: lsp.ProgressParams}}
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    local value = ev.data.params.value --[[@as {percentage?: number, title?: string, message?: string, kind: "begin" | "report" | "end"}]]
    if not client or type(value) ~= "table" then
      return
    end
    local p = progress[client.id]

    for i = 1, #p + 1 do
      if i == #p + 1 or p[i].token == ev.data.params.token then
        p[i] = {
          token = ev.data.params.token,
          msg = ("[%3d%%] %s%s"):format(
            value.kind == "end" and 100 or value.percentage or 100,
            value.title or "",
            value.message and (" **%s**"):format(value.message) or ""
          ),
          done = value.kind == "end",
        }
        break
      end
    end

    local msg = {} ---@type string[]
    progress[client.id] = vim.tbl_filter(function(v)
      return table.insert(msg, v.msg) or not v.done
    end, p)

    local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    vim.notify(table.concat(msg, "\n"), "info", {
      id = "lsp_progress",
      title = client.name,
      opts = function(notif)
        notif.icon = #progress[client.id] == 0 and " "
          or spinner[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #spinner + 1]
      end,
    })
  end,
})

require("vim._core.ui2").enable({
  enabled = true,
  msg = { targets = 'msg' }
})

vim.api.nvim_create_user_command('TSStatus', function(opts)
  local ft = vim.bo.filetype
  local lang = opts.args ~= '' and opts.args or vim.treesitter.language.get_lang(ft)

  if not lang then
    vim.notify('No Tree-sitter language for filetype: ' .. ft, vim.log.levels.WARN)
    return
  end

  local loaded, load_err = vim.treesitter.language.add(lang)
  local parser, parser_err = vim.treesitter.get_parser(0, lang)
  local query_files = vim.treesitter.query.get_files(lang, 'highlights')

  local inspect_ok, info = pcall(vim.treesitter.language.inspect, lang)

  vim.print({
    filetype = ft,
    lang = lang,
    language_loaded = loaded == true,
    load_error = load_err,
    parser_attached_to_buffer = parser ~= nil,
    parser_error = parser_err,
    has_highlights_query = #query_files > 0,
    highlight_query_files = query_files,
    abi_version = inspect_ok and info.abi_version or nil,
  })
end, { nargs = '?' })

vim.o.autocomplete = false
