#!/bin/sh
# Updates this machine: the NixOS channel, Zen, Helium and the Libron font (update-packages.sh), then builds, switches and cleans up. The clean-up keeps the newest 3 generations, so you can still boot back.
set -eu
before=$(nixos-version)

echo "== NixOS channel"
sudo nix-channel --update

echo "== Zen, Helium and Libron"
# Not fatal: a GitHub hiccup (60 requests an hour without a token) would otherwise stop the whole update here.
bash /etc/nixos/update-packages.sh || echo "== Zen, Helium and Libron not updated (see above); the system update goes on"

echo "== Build and switch"
sudo nixos-rebuild switch

# Clean-up after the update; it also removes the archives update-packages.sh put into the Nix store, which only the build needed.
sysclean go

echo "== Done: $before -> $(nixos-version)"
[ "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)" ] || echo "The kernel changed: restart to use it."

echo "== Firmware (only listed here; install with: fwupdmgr update)"
firmware=$(fwupdmgr get-updates 2>&1 || true)
case "$firmware" in *"No updates available"*) echo "No updates available" ;; *) echo "$firmware" ;; esac
