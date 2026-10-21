{ config, lib, pkgs, ... }:

# What the desktop runs: mango, the login screen, locking and the keyring.
{
  # --- Session ---

  # mango is the desktop (~/.config/mango); its autostart.sh starts the rest of the session.
  programs.mango.enable = true;

  # Screen-saver blocking: nixpkgs' mango module hands it to the gtk portal, which cannot do it without GNOME ("Inhibiting other than idle not supported", 42 times in a week); none, as in mango's own portals.conf, so apps use hypridle's org.freedesktop.ScreenSaver or Wayland's idle inhibit.
  xdg.portal.config.mango."org.freedesktop.impl.portal.Inhibit" = lib.mkForce [ "none" ];

  # RustDesk background service as its own Linux packages install it: runs as root for mouse and keys, starts RustDesk in the mango session.
  systemd.services.rustdesk = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-user-sessions.service" ];
    # A switch does not restart it: its ExecStop kills every "rustdesk --" process, so a rebuild run over RustDesk would cut itself off.
    restartIfChanged = false;
    path = [ pkgs.procps pkgs.gawk pkgs.which pkgs.getent "/run/wrappers" ];
    serviceConfig = {
      ExecStart = "${pkgs.rustdesk-flutter}/bin/rustdesk --service";
      ExecStop = "${pkgs.procps}/bin/pkill -f \"rustdesk --\"";
      User = "root";
      KillMode = "mixed";
      TimeoutStopSec = 30;
      LimitNOFILE = 100000;
    };
  };
  # mango's Xwayland has no XAUTHORITY, so RustDesk's service keeps searching for one and burns CPU; $HOME/.Xauthority is also X11's own default.
  environment.sessionVariables.XAUTHORITY = "$HOME/.Xauthority";
  nixpkgs.overlays = [
    (final: prev: {
      # RustDesk with its Wayland shortcut capture: nixpkgs builds it without the two Wayland tools the feature needs.
      rustdesk-flutter = prev.rustdesk-flutter.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [ prev.wayland-scanner prev.removeReferencesTo ];
        buildInputs = old.buildInputs ++ [ prev.wayland prev.wayland-protocols prev.wayland-scanner ];
        # The root service re-checks the session every 0.5 s (half a core); 30 s is enough, a login or logout is noticed within 30 s.
        postPatch = old.postPatch + ''
          substituteInPlace ../src/platform/linux.rs --replace-fail 'sleep_millis(500);' 'sleep_millis(30_000);'
          # A failed screen capture (screen off) no longer leaves the "already set up" mark on, so the next connection tries again.
          substituteInPlace ../src/server/wayland.rs --replace-fail 'Capturer::new(display).with_context(|| {' 'Capturer::new(display).map_err(|e| { *PIPEWIRE_INITIALIZED.write().unwrap() = false; e }).with_context(|| {'
        '';
        # librustdesk.so names rustc's folder without loading anything from it, which kept rustc and LLVM (1.7 GB) installed; drop it.
        postFixup = (old.postFixup or "") + ''
          find $out -type f -exec remove-references-to -t ${prev.rustc.unwrapped} {} +
        '';
        disallowedReferences = (old.disallowedReferences or [ ]) ++ [ prev.rustc.unwrapped ];
      });
      # Screen-sharing portal with the upstream fix for its crash when RustDesk starts a stream (xdg-desktop-portal-wlr PR #405), only up to 0.8.4: a newer release carries it.
      xdg-desktop-portal-wlr = prev.xdg-desktop-portal-wlr.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ prev.lib.optionals (prev.lib.versionOlder old.version "0.8.5") [ ./xdpw-stale-frame.patch ];
      });
    })
  ];

  # Login screen: ly, a text login on the console.
  services.displayManager.ly.enable = true;
  services.displayManager.ly.settings = {
    animation = "matrix";
    clock = "%c";
    # The rain in the console's magenta (ly's own default is green).
    cmatrix_fg = "0x00FF00FF";
  };

  environment.systemPackages = with pkgs; [
    hypridle            # locks and suspends when idle
    hyprlock            # screen locker
    wlopm               # turns the screens off and on (used by hypridle)
    wlr-randr           # lists what each screen offers: sizes, refresh rates, scale (the bar's displays panel asks it)
    cmatrix             # screensaver: matrix rain (started by hypridle)
    wlsunset            # night light (Super+Alt+N in mango's bind.conf)
    # quickshell: bar, panels and notifications (~/.config/quickshell); wrapped so its Qt also finds the WebP reader the package leaves out
    (symlinkJoin {
      name = "quickshell";
      paths = [ quickshell ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = "wrapProgram $out/bin/quickshell --prefix QT_PLUGIN_PATH : ${qt6.qtimageformats}/lib/qt-6/plugins";
    })
    wl-clipboard        # clipboard for terminal, Neovim and screenshots
    cliphist            # clipboard history
    grim                # screenshots
    slurp               # screenshot region picker
    yazi                # terminal file manager
    nautilus            # graphical file manager
    brightnessctl       # screen brightness keys
    playerctl           # media keys
  ];

  # Chromium and Electron apps run on Wayland directly, not through XWayland.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Text-to-speech is on by default and brings 650 MB of voices.
  services.speechd.enable = false;

  # Nautilus needs this to show its trash, phones and network folders.
  services.gvfs.enable = true;

  # --- Locking, fingerprint and passwords ---

  # hyprlock asks for the fingerprint itself, so PAM must not ask for it too.
  security.pam.services.hyprlock.fprintAuth = false;

  # Login: check a typed password before asking for a fingerprint.
  security.pam.services.login.rules.auth.fprintd.order =
    config.security.pam.services.login.rules.auth.unix.order + 50;

  # sudo: wait 10 s for a finger (the minimum) before asking for the password.
  security.pam.services.sudo.rules.auth.fprintd.settings.timeout = 10;

  # sudo and the password prompt: with the lid closed the reader is out of reach, so skip the fingerprint and ask for the password at once.
  security.pam.services.sudo.rules.auth.lid = {
    order = config.security.pam.services.sudo.rules.auth.fprintd.order - 10;
    control = "[success=1 default=ignore]";
    modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
    args = [ "quiet" "quiet_log" "${pkgs.gnugrep}/bin/grep" "-q" "closed" "/proc/acpi/button/lid/LID/state" ];
  };
  security.pam.services.polkit-1.rules.auth.lid = {
    inherit (config.security.pam.services.sudo.rules.auth.lid) order control modulePath args;
  };

  # sudo: ask again after 30 minutes instead of 5.
  security.sudo.extraConfig = "Defaults timestamp_timeout=30";

  # Keyring for app sign-ins such as Zed's; the typed login password unlocks it.
  services.gnome.gnome-keyring.enable = true;
}
