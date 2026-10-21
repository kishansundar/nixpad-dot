pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Theme tokens: every colour, size and font of the bar and its panels is named once here (the other programs repeat the same hex values in their own files; the accent alone is taken from the wallpaper)
Singleton {
    id: theme
    // Surfaces, darkest first: the bar and panels; a header or footer strip; the row under the pointer; the cell whose panel is open
    readonly property color bg: "#0B0D1A"
    readonly property color bg2: "#101226"
    readonly property color surface: "#15162B"
    readonly property color surface2: "#292044"
    // Lines: thin dividers, and the frame of a panel
    readonly property color border: "#39344F"
    readonly property color strong: "#5B5580"
    // Text: values; the labels that name them; whatever is off or empty
    readonly property color text: "#F4E8D0"
    readonly property color text2: "#A6A0C8"
    readonly property color muted: "#827CA8"
    // The accent marks what is active or chosen; ~/.config/mango/wallpaper.sh takes its hue from the wallpaper, keeps it between cyan and magenta, and matugen writes it to mango's colors.conf, read here (magenta until then); the second colour, chosen below, is for what the machine reports (levels, meters, the Japanese word of a panel); orange, red and violet only ever report a state
    property color accent: "#FF4FA3"
    FileView {
        path: Quickshell.env("HOME") + "/.config/mango/colors.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { const found = text().match(/focus_color=0x([0-9a-fA-F]{6})/); if (found) theme.accent = "#" + found[1] }
    }
    // What is written on the accent, such as the number on the active tag: near-black on a light accent, white on a dark one
    readonly property color accentInk: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b > 0.4 ? bg : text
    readonly property color warn: "#FF9955"
    readonly property color error: "#FF5555"
    readonly property color info: "#54E7F2"
    // The second colour is the other signature colour of the theme: cyan beside an accent from the magenta half of the range (purple to pink), magenta beside one from the cyan half (cyan to blue)
    readonly property color accent2: accent.hslHue * 360 < 257 ? magenta : info
    // The theme's own magenta, and its violet, the night light's colour
    readonly property color magenta: "#FF4FA3"
    readonly property color night: "#B58CFF"

    // The bar's height, the space at each side of a cell, a thin line and a strong one, and the height of a row in a panel
    readonly property int bar: 36
    readonly property int pad: 12
    readonly property int thin: 1
    readonly property int thick: 2
    readonly property int row: 28
    // The gap between a panel and the bar (mango's gap between windows)
    readonly property int gap: 5
    // A bar on a screen narrower than this leaves out the CPU, memory and traffic numbers
    readonly property int wide: 2300
    // How long a colour takes to change under the pointer, in ms; 0 switches that motion off
    readonly property int motion: 80
    // How solid the bar's background is, from 0 (clear) to 1 (solid); its own number, lower than the windows' focused_opacity in mango's config.conf, so the wallpaper shows through the bar too
    readonly property real solid: 0.90

    // One typeface in four sizes: values, labels, the big figures in a panel, and the calendar's time
    readonly property string family: "JetBrainsMono Nerd Font"
    readonly property font valueFont: Qt.font({ family: family, pixelSize: 15, weight: Font.Medium })
    readonly property font labelFont: Qt.font({ family: family, pixelSize: 12, weight: Font.Medium, letterSpacing: 1 })
    readonly property font displayFont: Qt.font({ family: family, pixelSize: 36, weight: Font.ExtraBold, letterSpacing: -1 })
    readonly property font heroFont: Qt.font({ family: family, pixelSize: 64, weight: Font.ExtraBold, letterSpacing: -2 })
    // The Japanese word after a panel's name: named by its own face, because the fallback for the bar's font would pick the Korean shapes
    readonly property font kanaFont: Qt.font({ family: "Noto Sans Mono CJK JP", pixelSize: 12, weight: Font.Medium })
}
