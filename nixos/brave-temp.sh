#!/bin/sh
# Starts Brave Origin in a throwaway profile with uBlock Origin and NordVPN, and deletes it all when Brave closes; extra arguments go to Brave (a link, for example).
set -e
d=$(mktemp -d)
# Brave can still be shutting down after this script ends (a closed terminal), so wait up to 20 s for its processes before deleting.
cleanup() { for i in $(seq 40); do pgrep -f "$d/" >/dev/null || break; sleep 0.5; done; pkill -KILL -f "$d/" || true; rm -rf "$d"; }
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
echo "fetching uBlock Origin and NordVPN"
ubo=$(curl -fsSL https://api.github.com/repos/gorhill/uBlock/releases/latest | grep -o 'https://[^"]*chromium\.zip')
curl -fsSLo "$d/ubo.zip" "$ubo"
curl -fsSLo "$d/nord.crx" "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=155.0&acceptformat=crx3&x=id%3Dfjoaledfpmneenckfbpdfhkmimnjocfa%26uc"
unzip -q "$d/ubo.zip" -d "$d"
unzip -q "$d/nord.crx" -d "$d/nord" 2>/dev/null || true
rm -rf "$d/nord/_metadata"
echo "starting Brave Origin; closing it deletes $d"
nix run nixpkgs#brave-origin -- --user-data-dir="$d/profile" --load-extension="$d/uBlock0.chromium,$d/nord" "$@"
