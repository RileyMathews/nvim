return {
  dir = vim.fn.expand("~/.local/share/vim-herdr-navigation"),
  lazy = false,
  config = function()
    dofile(
      vim.fn.expand(
        "~/.local/share/vim-herdr-navigation/editor/nvim.lua"
      )
    )
  end,
}
