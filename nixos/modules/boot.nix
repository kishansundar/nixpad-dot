{ pkgs, ... }:

{
  # Limine EFI boot loader. The newest 3 generations stay selectable in its menu.
  boot.loader.limine.enable = true;
  boot.loader.limine.maxGenerations = 3;
  boot.loader.efi.canTouchEfiVariables = true;

  # Plain boot menu, shown for 2s: no picture, limine's own text in magenta on the theme's deep indigo; press any key to stop the countdown and pick an older generation.
  boot.loader.timeout = 2;
  boot.loader.limine.style = {
    wallpapers = [ ];
    interface = {
      resolution = "1920x1080";
      branding = "";
      helpColor = "FF4FA3";
      helpColorBright = "F4E8D0";
      helpHidden = true;
    };
    # Text at twice the size; the eight colours are the theme's indigo, red, the magenta the menu is written in, orange, periwinkle, violet, a dim magenta (the description line) and lavender.
    graphicalTerminal = {
      font.scale = "2x2";
      palette = "0B0D1A;FF5555;FF4FA3;FF9955;8C9BFF;B9A2E8;993062;A6A0C8";
      brightPalette = "6E6893;FF5555;FF4FA3;FFC08A;B3BDFF;D2C2F5;9AF2F8;F4E8D0";
      foreground = "FF4FA3";
      background = "0B0D1A";
    };
  };

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Console (boot text, ly) runs at 1920x1080 on every screen; mango still uses each screen's own mode.
  boot.kernelParams = [ "video=1920x1080" ];

  # Weekly: keep only the newest 3 system generations.
  systemd.services.prune-generations = {
    description = "Keep only the newest 3 NixOS generations";
    startAt = "weekly";
    path = [ pkgs.nix ];
    script = ''
      nix-env --profile /nix/var/nix/profiles/system --delete-generations +3
      nix-collect-garbage
    '';
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.prune-generations.timerConfig.Persistent = true;

  # Two commands from the scripts one folder up: "sysclean" shows what a clean-up would remove and "sysclean go" does it; "sysupdate" updates the channel, the browsers and the system.
  environment.systemPackages = [
    (pkgs.writeScriptBin "sysclean" (builtins.readFile ../sysclean.sh))
    (pkgs.writeScriptBin "sysupdate" (builtins.readFile ../sysupdate.sh))
  ];
}
