{
  # 1Password is not open source; it is allowed by name in configuration.nix.

  # The app and the `op` tool; polkitPolicyOwners lets it unlock with the system prompt.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "kishan" ];
  };

  # Browsers the extension may talk to; Helium also needs the helper file copied by hand.
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      zen
      .zen-wrapped
      helium
    '';
    mode = "0755";
  };

  # 1Password writes a helper file for every browser it knows at each start; this removes the folders of the ones not installed.
  systemd.user.paths.onepassword-browser-cleanup = {
    wantedBy = [ "default.target" ];
    pathConfig.PathChanged = "%h/.config";
  };
  systemd.user.services.onepassword-browser-cleanup = {
    serviceConfig.Type = "oneshot";
    script = ''
      sleep 1
      cd "$HOME/.config"
      for dir in google-chrome google-chrome-beta google-chrome-unstable chromium microsoft-edge-dev BraveSoftware vivaldi vivaldi-snapshot; do
        # A folder is removed only when the 1Password file is all it holds, so a real browser profile is never touched.
        if [ -d "$dir" ] && [ -z "$(find "$dir" -type f ! -name com.1password.1password.json -print -quit)" ]; then
          rm -rf "$dir"
        fi
      done
    '';
  };
}
