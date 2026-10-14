-- Extra syntax parsers on top of the ones LazyVim installs.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "nix", "fish", "qmljs", "hyprlang" } },
  },
}
