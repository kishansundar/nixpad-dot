#!/bin/sh
# launch.sh ID NAME COMMAND [ARGS...]: starts an app from the launcher or the dock with its output in the journal (journalctl -t ID), and says so in a notice when it quits with an error within 5 s, where it would otherwise vanish without a word (Kratos's scripts/launch).
[ "$#" -ge 3 ] || { echo "usage: launch.sh ID NAME COMMAND [ARGS...]" >&2; exit 2; }
id=$1 name=$2; shift 2
since=$(date +%s)
systemd-cat -t "$id" --stderr-priority=warning -- "$@" &
pid=$!

i=0
while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -ge 50 ] && exit 0
    sleep 0.1; i=$((i + 1))
done
wait "$pid"; code=$?
# Quitting cleanly at once is normal: the app handed over to a copy already running, or went to the tray.
[ "$code" -eq 0 ] && exit 0

# Its lines reach the journal a moment after it quits; the first that names a failure is shown, else the last, without Chromium's "[pid:tid:time:ERROR:file.cc:365] " prefix.
out="" i=0
while [ -z "$out" ] && [ "$i" -lt 10 ]; do
    out=$(journalctl -q -t "$id" --since "@$since" -o cat --no-pager 2>/dev/null)
    [ -n "$out" ] || { sleep 0.1; i=$((i + 1)); }
done
line=$(printf '%s\n' "$out" | grep -i -m1 -E 'error|fatal|cannot|can.t|failed|denied|not found|no such')
[ -n "$line" ] || line=$(printf '%s\n' "$out" | grep . | tail -n 1)
line=$(printf '%s' "$line" | sed 's/^\[[^]]*\] *//' | cut -c1-300)
if [ "$code" -gt 128 ]; then how="killed by signal $((code - 128))"; else how="exit $code"; fi

# The notice goes to the bar's notification service; the -- keeps busctl from reading the expiry -1 as an option.
busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications \
    Notify 'susssasa{sv}i' "$name" 0 "" "$name did not start" "${line:+$line
}$how / journalctl -t $id" 0 0 -1 > /dev/null 2>&1
exit 0
