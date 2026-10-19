{ lib, ... }:

# This machine: the files it is built from, and its own settings.
{
  imports = [
    ./hardware-configuration.nix # the hardware scan NixOS generated
    ./modules/boot.nix
    ./modules/hardware.nix
    ./modules/desktop.nix
    ./modules/theme.nix
    ./modules/fonts.nix
    ./modules/shell.nix
    ./modules/dev.nix
    ./modules/packages.nix
    ./modules/apps/1password.nix
    ./modules/apps/helium.nix
    ./modules/apps/syncthing.nix
    ./modules/apps/zen.nix
  ];

  networking.hostName = "NixPad";

  # Wi-Fi and Ethernet. Use nmtui or nmcli to connect.
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;
  # Lets kishan start and stop Tailscale without sudo (the dashboard's TAILSCALE switch)
  services.tailscale.extraSetFlags = [ "--operator=kishan" ];
  time.timeZone = "Asia/Kolkata";

  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
  };

  users.users."kishan" = {
    isNormalUser = true;
    description = "Kishan";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Identical files in the store are linked together as each package arrives, so a running program's file is never replaced later.
  nix.settings.auto-optimise-store = true;

  # Software that is not open source is blocked unless it is named here.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "1password" "1password-gui" "1password-cli"
      "claude-code"
      "unrar"
      "spotify"
      "obsidian"
    ];

  # The NixOS release first installed; it stays the same across upgrades.
  system.stateVersion = "26.05";
}
