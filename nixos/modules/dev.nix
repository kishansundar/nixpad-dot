{ pkgs, ... }:

{
  programs.nix-ld.enable = true;
  virtualisation.docker.enable = true;
  # Docker starts the first time it is used, not at boot (there it made the start wait for the network).
  virtualisation.docker.enableOnBoot = false;

  users.users."kishan".extraGroups = [ "docker" "dialout" ];

  environment.systemPackages = with pkgs; [
    lua5_4
    nil
    nixd
    exercism
    git
    zed-editor

    # Claude Code (not open source; allowed by name in configuration.nix).
    claude-code

    # Programs the LazyVim setup of Neovim needs (its config is in ~/.config/nvim).
    neovim
    gcc                 # C compiler; builds the syntax parsers LazyVim installs
    tree-sitter         # parser generator those builds go through
    lazygit             # git screen LazyVim opens with <leader>gg
    trash-cli           # trash command; makes deleting in the file tree recoverable
  ];
}
