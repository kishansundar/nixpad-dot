#!/bin/sh
# Lints the bar's QML with qmllint from Quickshell's own Qt, as Kratos's tests/lint.sh does; usage: sh lint.sh [--all] [File.qml ...] (default: every file; --all also shows the noise).
dir=$(dirname "$(readlink -f "$0")")
lint=$(nix-store -qR "$(readlink -f "$(command -v quickshell)")" 2>/dev/null | grep -E -- '-qtdeclarative-6[^/]*$' | head -1)/bin/qmllint
[ -x "$lint" ] || { echo "lint: no qmllint in Quickshell's qtdeclarative"; exit 2; }
all=0; [ "${1:-}" = --all ] && { all=1; shift; }
root=$(mktemp -d)
trap 'kill "$pid" 2>/dev/null; rm -rf "$root"' EXIT
# A scratch copy where Quickshell, started off screen on an empty ShellRoot, writes its .qmlls.ini (import paths and its type folder) for qmllint.
mkdir -p "$root/cfg" "$root/run" && chmod 700 "$root/run"
cp "$dir"/*.qml "$dir"/*.json "$root/cfg/" 2>/dev/null
mv "$root/cfg/shell.qml" "$root/cfg/main-shell.qml"
printf 'import Quickshell\nShellRoot {}\n' > "$root/cfg/shell.qml"
: > "$root/cfg/.qmlls.ini"
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$root/run" DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent \
    quickshell --no-duplicate -p "$root/cfg/shell.qml" > "$root/qs.log" 2>&1 &
pid=$!
i=0
while [ $i -lt 100 ] && ! grep -q '^buildDir=' "$root/cfg/.qmlls.ini"; do sleep 0.1; i=$((i + 1)); done
grep -q '^buildDir=' "$root/cfg/.qmlls.ini" || { echo "lint: Quickshell wrote no .qmlls.ini"; cat "$root/qs.log"; exit 2; }
build=$(sed -n 's/^buildDir="\(.*\)"$/\1/p' "$root/cfg/.qmlls.ini")
imports=$(sed -n 's/^importPaths="\(.*\)"$/\1/p' "$root/cfg/.qmlls.ini" | tr ':' '\n' | sed 's/^/-I /' | tr '\n' ' ')
cd "$root/cfg" || exit 2
if [ $# -eq 0 ]; then set -- $(ls *.qml | grep -v '^shell\.qml$'); else set -- $(for f in "$@"; do [ "$f" = shell.qml ] && echo main-shell.qml || basename "$f"; done); fi
# shellcheck disable=SC2086
"$lint" $imports -I "$build" "$@" > "$root/out.txt" 2>&1
sed -i -e "s|$root/cfg/||" -e 's|main-shell\.qml|shell.qml|' "$root/out.txt"
# Noise (checked 2026-10-21, qmllint 6.12.0, Quickshell 0.3.2): members of the bar's singletons and of Quickshell types its qmltypes leave out, outer ids in delegates, singletons without a qmldir, Connections to a singleton, Dock.qml's deliberate bare read, and optional chaining on screens (needed: a screen can go away, Bar.qml:26).
if [ $all = 1 ]; then grep -E '^(Warning|Error|Info):' "$root/out.txt" > "$root/found.txt"
else
    grep -E '^(Warning|Error):' "$root/out.txt" \
        | grep -v -E '\[(missing-property|unqualified|uncreatable-type|unresolved-type|import|redundant-optional-chaining|confusing-expression-statement)\]$' \
        | grep -v -E 'Cannot assign binding of type [A-Za-z]+ to QObject \[incompatible-type\]$' > "$root/found.txt"
fi
cat "$root/found.txt"
n=$(grep -c -v ': Note: ' "$root/found.txt")
[ "$n" -eq 0 ] && { echo "lint: clean"; exit 0; }
echo "lint: $n finding(s)"; exit 1
