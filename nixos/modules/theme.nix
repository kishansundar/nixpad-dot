{ pkgs, ... }:

# How the desktop looks: wallpaper, colors, GTK theme, icons and pointer.
let
  # Mouse pointer for GTK apps (mango's own is cursor_theme in its config).
  cursorTheme = "Bibata-Modern-Ice";

  # Only the one cursor look in use; the full Bibata set is 320 MB.
  cursorPackage = pkgs.runCommand "bibata-modern-ice" { } ''
    mkdir -p $out/share/icons
    cp -r ${pkgs.bibata-cursors}/share/icons/${cursorTheme} $out/share/icons/
  '';
in
{
  environment.systemPackages = with pkgs; [
    swaybg              # draws the wallpaper
    matugen             # Material You colors from the wallpaper or a seed color
    adw-gtk3            # GTK3 theme that takes the generated colors
    papirus-icon-theme  # icons for GTK apps
    cursorPackage
  ];

  # The text console (boot messages, the ly login screen, Ctrl+Alt+F2) in the desktop's palette, the same sixteen as ~/.config/kitty/colors.conf: deep indigo, red, mint, orange, periwinkle, magenta, cyan, lavender, then the bright row.
  console.colors = [
    "0B0D1A" "FF5555" "7CE3A1" "FF9955" "8C9BFF" "FF4FA3" "54E7F2" "A6A0C8"
    "6E6893" "FF8585" "A8F0C2" "FFC08A" "B3BDFF" "FF8AC2" "9AF2F8" "F4E8D0"
  ];

  # GTK apps and file dialogs: default theme, icons, pointer and fonts.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/desktop/interface" = {
      gtk-theme = "adw-gtk3-dark";
      icon-theme = "Papirus-Dark";
      color-scheme = "prefer-dark";
      cursor-theme = cursorTheme;
      font-name = "IBM Plex Sans 11";
      document-font-name = "Libron 11";
      monospace-font-name = "JetBrainsMono Nerd Font 11";
    };
    # No window buttons inside apps: mango has no title bars.
    settings."org/gnome/desktop/wm/preferences".button-layout = ":";
  }];
}
