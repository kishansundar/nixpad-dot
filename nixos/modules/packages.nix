{ pkgs, ... }:

{
  # General applications; packages that belong to one feature are in its file.
  environment.systemPackages = with pkgs; [
    wget
    celluloid           # video player
    spotify             # music
    unzip
    zip
    unrar               # not open source; allowed by name in configuration.nix
    qimgv
    obsidian
    smassh              # typing test in the terminal
    rustdesk-flutter    # remote desktop, same version as NixDesk
  ];
}
