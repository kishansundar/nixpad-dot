#!/bin/sh
# Updates this machine: the NixOS channel, Zen, Helium and the Libron font (update-browsers.sh), then builds, switches and cleans up. The clean-up keeps the newest 3 generations, so you can still boot back.
set -eu
before=$(nixos-version)

echo "== NixOS channel"
sudo nix-channel --update

echo "== Zen, Helium and Libron"
bash /etc/nixos/update-browsers.sh

echo "== Build and switch"
sudo nixos-rebuild switch

# Clean-up after the update; it also removes the browser archives update-browsers.sh put into the Nix store, which only the build needed.
sysclean go

echo "== Done: $before -> $(nixos-version)"
[ "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)" ] || echo "The kernel changed: restart to use it."

echo "== Firmware (only listed here; install with: fwupdmgr update)"
firmware=$(fwupdmgr get-updates 2>&1 || true)
case "$firmware" in *"No updates available"*) echo "No updates available" ;; *) echo "$firmware" ;; esac
