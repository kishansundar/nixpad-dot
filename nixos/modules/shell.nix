{ pkgs, ... }:

# The shell (fish), its command-line tools, and the terminal (kitty).
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      fastfetch
    '';
  };

  users.users."kishan".shell = pkgs.fish;

  programs.starship.enable = true;

  programs.zoxide.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  environment.systemPackages = with pkgs; [
    kitty               # terminal (settings in ~/.config/kitty)
    eza
    bat
    fd
    ripgrep
    fzf
    tealdeer            # short example pages for commands (run as tldr)
    fastfetch
    fetch               # animated 3D version of fastfetch
    btop                # system monitor (colours from matugen, ~/.config/btop/themes)
    pciutils            # lspci: lists the parts inside (graphics, Wi-Fi, SSD)
    usbutils            # lsusb: lists what is plugged into USB

    fishPlugins.fzf-fish
    fishPlugins.autopair
  ];

  # kitty is the default terminal.
  environment.variables.TERMINAL = "kitty";
}
