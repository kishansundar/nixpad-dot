#!/bin/sh
# Sets the wallpaper and takes the accent colour from it; run with no file to pick one in yazi.

file=$1
if [ -z "$file" ]; then
    pick=$XDG_RUNTIME_DIR/wallpaper-pick
    rm -f "$pick"
    kitty yazi --chooser-file="$pick" ~/Pictures/Backgrounds
    file=$(cat "$pick" 2>/dev/null)
fi
[ -f "$file" ] || exit 0

# The picture in use is copied into wallpaper/ here, so the config carries it; current-wallpaper points to the copy, and wallpaper-source keeps where it came from for the bar's picker.
src=$(realpath "$file")
mkdir -p ~/.config/mango/wallpaper && cp "$src" ~/.config/mango/.wallpaper-new && rm -f ~/.config/mango/wallpaper/* && mv ~/.config/mango/.wallpaper-new ~/.config/mango/wallpaper/"${src##*/}"
ln -sfn wallpaper/"${src##*/}" ~/.config/mango/current-wallpaper
case $src in "$HOME"/.config/mango/*) ;; *) echo "$src" > ~/.config/mango/wallpaper-source ;; esac
pkill swaybg
swaybg -m fill -i ~/.config/mango/current-wallpaper >/dev/null 2>&1 &
# The accent: the hue of the colour matugen finds in the picture, kept inside the City Pop stretch from cyan through blue and purple to magenta, always at full strength.
accent=$(matugen image "$file" --dry-run -j rgb --fallback-color "#FF4FA3" 2>/dev/null | tr -d ' \n' | sed 's/.*"source_color":{"dark":{"color":"rgb(\([0-9]*\),\([0-9]*\),\([0-9]*\))".*/\1 \2 \3/' | awk '
    NF == 3 { r = $1 / 255; g = $2 / 255; b = $3 / 255; max = r > g ? (r > b ? r : b) : (g > b ? g : b); min = r < g ? (r < b ? r : b) : (g < b ? g : b); d = max - min
        # its hue, 0 to 360 (magenta when it has none); cyan is 184 and magenta 331, and a hue outside that stretch goes to the nearer end
        h = d == 0 ? 331 : max == r ? 60 * ((g - b) / d) : max == g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4); if (h < 0) h += 360
        if (h > 331 || h < 77.5) h = 331; else if (h < 184) h = 184
        # that hue at full saturation and 65% lightness, as red, green and blue
        t = (h / 60) % 2; x = 0.7 * (1 - (t > 1 ? t - 1 : 1 - t))
        if (h < 240) { r = 0; g = x; b = 0.7 } else if (h < 300) { r = x; g = 0; b = 0.7 } else { r = 0.7; g = 0; b = x }
        printf "#%02x%02x%02x", (r + 0.3) * 255 + 0.5, (g + 0.3) * 255 + 0.5, (b + 0.3) * 255 + 0.5 }')
# matugen writes it into mango (where the bar reads it), kitty, the lock screen, GTK, yazi and btop (~/.config/matugen); should the step above ever fail, it takes the colour from the picture by itself.
case $accent in "#"??????) matugen color hex "$accent" -m dark -t scheme-vibrant -q ;; *) matugen image "$file" -m dark -t scheme-vibrant -q ;; esac
