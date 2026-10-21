#!/usr/bin/env bash
# Writes the newest Zen, Helium and Libron versions and hashes into modules; nrs then installs them.
set -euo pipefail

here=$(dirname "$0")

# update <name> <module file> <github repo> <url template, with @VERSION@> [--unpack, when the hash is of the unpacked archive]
update() {
  local name=$1 file=$here/modules/$2 repo=$3 url_template=$4 unpack=${5:-}
  local current latest hash

  current=$(sed -n 's/^ *version = "\(.*\)";$/\1/p' "$file")
  latest=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 || true)
  # Libron tags start with "v"; the version line in the file does not.
  latest=${latest#v}

  if [ -z "$latest" ]; then
    echo "$name: could not read the latest release of $repo" >&2
    return 1
  fi
  if [ "$current" = "$latest" ]; then
    echo "$name is up to date ($current)"
    return 0
  fi

  hash=$(nix store prefetch-file --json $unpack "${url_template//@VERSION@/$latest}" | grep -o 'sha256-[^"]*')
  # Each file has one version line and one hash line; anything else is left for a hand edit.
  if [ "$(grep -c '^ *version = "' "$file")" != 1 ] || [ "$(grep -c '^ *hash = "sha256-' "$file")" != 1 ]; then
    echo "$name: $file does not have exactly one version and one hash line; set $latest and $hash by hand" >&2
    return 1
  fi
  sed -i "s|^\( *version = \)\".*\";\$|\1\"$latest\";|; s|^\( *hash = \)\"sha256-.*\";\$|\1\"$hash\";|" "$file"
  echo "$name: $current -> $latest (written to $file)"
  changed=1
}

update Zen apps/zen.nix zen-browser/desktop \
  "https://github.com/zen-browser/desktop/releases/download/@VERSION@/zen.linux-x86_64.tar.xz"
update Helium apps/helium.nix imputnet/helium-linux \
  "https://github.com/imputnet/helium-linux/releases/download/@VERSION@/helium-@VERSION@-x86_64_linux.tar.xz"
update Libron fonts.nix nicoverbruggen/libron \
  "https://github.com/nicoverbruggen/libron/releases/download/v@VERSION@/Libron.zip" --unpack
[ -z "${changed:-}" ] || echo "Now run: sudo nixos-rebuild switch"
