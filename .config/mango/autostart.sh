#!/bin/sh
# Run once by mango at login (exec_once in config.conf); starts the rest of the session.

# Idle steps: screensaver, lock, screens off and sleep; the times are in ~/.config/hypr/hypridle.conf.
hypridle >/dev/null 2>&1 &

# Wallpaper: the image wallpaper.sh chose last (Super+W picks another).
swaybg -m fill -i ~/.config/mango/current-wallpaper >/dev/null 2>&1 &

# Bar: tags, clock and system status; it also draws the notifications and the password prompt for admin actions (~/.config/quickshell/shell.qml).
quickshell >/dev/null 2>&1 &

# Password manager in the background, for the browser extension and SSH agent; it waits up to 10 seconds for the bar's tray, because it only shows its icon if a tray exists when it starts.
(for _ in $(seq 50); do busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && break; sleep 0.2; done; exec 1password --silent) >/dev/null 2>&1 &

# Clipboard history (text and images), except what a password manager marks secret; Super+V opens it.
wl-paste --type text --watch sh -c 'wl-paste --list-types | grep -q x-kde-passwordManagerHint || cliphist store' >/dev/null 2>&1 &
wl-paste --type image --watch sh -c 'wl-paste --list-types | grep -q x-kde-passwordManagerHint || cliphist store' >/dev/null 2>&1 &
