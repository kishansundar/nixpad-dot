#!/bin/sh
# screenshot.sh region|window|screen (mango's binds): Kratos's screenshot.sh, to the clipboard only; region drags a box, or a click takes a window's content or, on the bare desktop, the whole screen; Esc cancels
set -u
what=${1:-region}
mango=${XDG_CONFIG_HOME:-$HOME/.config}/mango

# The frame in the accent matugen takes from the wallpaper (mango's colors.conf, as the bar reads it), the rest under a veil of the bar's ground at 45 %
accent=$(sed -n 's/^focus_color=0x\([0-9a-fA-F]\{6\}\).*/\1/p' "$mango/colors.conf" 2> /dev/null | head -n 1)
rule="#${accent:-FF4FA3}ff" veil="#0B0D1A73"
border=$(sed -n 's/^border_px=\([0-9]*\).*/\1/p' "$mango/config.conf" 2> /dev/null | head -n 1)

# One read of mango: the focused monitor, the focused window, and a box for each window shown there (floating ones first, as they lie on top; the monitor last, for a click on the bare desktop), each inside its border
eval "$(perl -MJSON::PP - "$(mmsg get all-monitors)" "$(mmsg get all-clients)" "${border:-2}" <<'PERL'
use strict; use warnings;
my ($monitors, $clients, $border) = @ARGV;
sub out { my ($k, $v) = @_; $v =~ s/'/'\\''/g; print "$k='$v'\n" }
my $mons = eval { decode_json($monitors)->{monitors} } || [];
my ($mon) = ((grep { $_->{active} } @$mons), @$mons);
exit 0 unless $mon;
out("mongeo", "$mon->{x},$mon->{y} $mon->{width}x$mon->{height}");
my $cs = eval { decode_json($clients)->{clients} } || [];
sub inner { my $c = shift; my $b = $c->{is_fullscreen} ? 0 : $border; my ($w, $h) = ($c->{width} - 2 * $b, $c->{height} - 2 * $b); $w > 0 && $h > 0 ? sprintf("%d,%d %dx%d", $c->{x} + $b, $c->{y} + $b, $w, $h) : undef }
my @shown = sort { ($a->{is_floating} || $a->{is_fullscreen} ? 0 : 1) <=> ($b->{is_floating} || $b->{is_fullscreen} ? 0 : 1) } grep { $_->{monitor} eq $mon->{name} && $_->{is_visible} && !$_->{is_minimized} } @$cs;
out("boxes", join("\n", (map { my $g = inner($_); defined $g ? "$g " . ($_->{appid} || "window") : () } @shown), "$mon->{x},$mon->{y} $mon->{width}x$mon->{height} screen"));
my ($focus) = grep { $_->{is_focused} && $_->{is_visible} } @$cs;
out("wingeo", $focus ? inner($focus) // "" : "");
PERL
)" || exit 1
[ -n "${mongeo:-}" ] || exit 1

case $what in
    region) geo=$(printf '%s\n' "$boxes" | slurp -d -F "JetBrainsMono Nerd Font" -w 2 -c "$rule" -b "$veil" -s "#00000000" -B "$veil" 2> /dev/null) || exit 0 ;;
    window) geo=${wingeo:-$mongeo} ;;
    screen) geo=$mongeo ;;
    *) echo "usage: screenshot.sh region|window|screen" >&2; exit 2 ;;
esac

# Nothing is saved: the shot goes to the clipboard, and a copy in memory (the newest ten, gone at shutdown) only lets the notice show it
dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenshots
mkdir -p "$dir"
file="$dir/$(date +%Y%m%d-%H%M%S-%N).png"
grim -g "$geo" "$file" || exit 1
wl-copy -t image/png < "$file"
ls -1t "$dir"/*.png | tail -n +11 | xargs -r rm -f --

# The notice goes to the bar's notification service; the -- keeps busctl from reading the expiry -1 as an option
size=${geo#* }
busctl --user -- call org.freedesktop.Notifications /org/freedesktop/Notifications org.freedesktop.Notifications \
    Notify 'susssasa{sv}i' Screenshot 0 "" "Copied to the clipboard" "${size%x*} × ${size#*x}" 0 1 image-path s "$file" -1 > /dev/null 2>&1
exit 0
