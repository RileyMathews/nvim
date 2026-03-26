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
