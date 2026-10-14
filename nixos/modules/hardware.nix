{
  # Hardware support that Plasma used to switch on by itself.
  hardware.bluetooth.enable = true;          # manage with bluetoothctl
  services.fprintd.enable = true;            # fingerprint reader
  services.upower.enable = true;             # battery information
  services.power-profiles-daemon.enable = true;
  services.udisks2.enable = true;            # USB drives and SD cards
  services.fwupd.enable = true;              # firmware updates

  # After sleep fprintd holds a dead copy of the reader; stopping it makes the next use start fresh.
  powerManagement.resumeCommands = "systemctl stop fprintd.service";

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
