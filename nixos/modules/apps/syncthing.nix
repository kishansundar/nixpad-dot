{
  services.syncthing = {
    enable = true;
    user = "kishan";
    dataDir = "/home/kishan";
    configDir = "/home/kishan/.config/syncthing";

    openDefaultPorts = true;
  };
}
