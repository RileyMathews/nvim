return {
  "christoomey/vim-tmux-navigator",
  lazy = false,

  init = function()
    -- Keep the :TmuxNavigate* commands, but don't let this plugin
    -- install <C-h/j/k/l> mappings.
    vim.g.tmux_navigator_no_mappings = 1
  end,

  config = function()
    -- This becomes the single owner of <C-h/j/k/l>.
    dofile(
      vim.fn.expand(
        "~/.local/share/vim-herdr-navigation/editor/nvim.lua"
      )
    )
  end,
}
