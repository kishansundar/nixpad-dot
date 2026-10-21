{
  # Hardware support that Plasma used to switch on by itself.
  hardware.bluetooth.enable = true;          # manage with bluetoothctl
  services.fprintd.enable = true;            # fingerprint reader
  services.upower.enable = true;             # battery information
  services.power-profiles-daemon.enable = true;
  services.udisks2.enable = true;            # USB drives and SD cards
  services.fwupd.enable = true;              # firmware updates

  # Wi-Fi rules of India, where the laptop is, instead of those the router announces (Germany's); applies after a restart, when the module loads.
  boot.extraModprobeConfig = "options cfg80211 ieee80211_regdom=IN";

  # Watch the SSD's health (SMART) and say so the moment it degrades: a desktop notice (systembus-notify, which any local user could use; kishan is the only one) and a terminal message.
  services.smartd = {
    enable = true;
    notifications.systembus-notify.enable = true;
  };

  # After sleep fprintd holds a dead copy of the reader; stopping it makes the next use start fresh (a lock screen asking for the reader at that moment cancels the stop, which is fine).
  powerManagement.resumeCommands = "systemctl stop fprintd.service || true";

  # Compressed swap kept in memory (there is none on disk): a cushion for the moment memory runs out.
  zramSwap.enable = true;

  # Sound.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
}
