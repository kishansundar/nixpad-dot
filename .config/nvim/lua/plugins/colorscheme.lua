-- Keep tokyonight's text colors but drop its blue background, so kitty's shows through.
return {
  {
    "folke/tokyonight.nvim",
    opts = {
      transparent = true,
      styles = { sidebars = "transparent", floats = "transparent" },
    },
  },
}
