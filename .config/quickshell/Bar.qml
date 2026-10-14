import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.WindowManager

// The bar on one monitor, drawn like the front panel of a tape deck: the name with its two strokes in the accent, the tags as keys and the focused window at the left, what is playing with its keys, the telemetry and the date and time at the right, over a 2px accent line
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData
    anchors { top: true; left: true; right: true }
    implicitHeight: Theme.bar
    WlrLayershell.namespace: "quickshell-bar"
    color: Qt.alpha(Theme.bg, Theme.solid)

    // A screen narrower than Theme.wide gets the short bar, without the CPU, memory and traffic numbers
    readonly property bool wide: width >= Theme.wide
    // The tags mango names for this monitor; while its overview is open (Super+Tab, Alt+Tab) it names a single one, "overview", in their place, so the number of real tags is kept for that block's width
    readonly property var sets: WindowManager.screenProjection(screen).windowsets
    property int tagCount: 1
    onSetsChanged: if (sets.length > 0 && !sets.some(s => s.name === "overview")) tagCount = sets.length
    // The focused window, when it is on this monitor: the one marked active, or, while a picker or a panel holds the keyboard and none is marked, the one mango still names
    readonly property var top: {
        const window = ToplevelManager.activeToplevel
        if (window) return window.screens.length === 0 || Array.from(window.screens).some(s => s.name === bar.screen.name) ? window : null
        try { const told = JSON.parse(Sys.focused); return told.monitor === bar.screen.name ? { appId: told.appid, title: told.title } : null } catch (e) { return null }
    }
    // Its app by the short name ("org.gnome.Nautilus" is shown as NAUTILUS), and its title in two parts: the status sign some programs put first (a terminal's spinner), and the words
    readonly property string appName: (top?.appId ?? "").split(".").pop().toUpperCase()
    readonly property string fullTitle: top?.title ?? ""
    readonly property string newSign: /^[\u2500-\u2BFF]\s/.test(fullTitle) ? fullTitle.charAt(0) : ""
    readonly property string appTitle: plain(newSign ? fullTitle.slice(1).replace(/^\s+/, "") : fullTitle, appName)
    // A title without the app's own name at its end ("page — Zen Browser" is shown as "page"): the short name already stands before it
    function plain(title, name) {
        const parts = title.match(/^(.*\S)\s+[-–—|]\s+(.+)$/)
        if (!parts) return title
        const bare = text => text.toLowerCase().replace(/[^a-z0-9]/g, "")
        const end = bare(parts[2]), own = bare(name)
        return own.length > 2 && end.length > 2 && (end.includes(own) || own.includes(end)) ? parts[1] : title
    }
    // The most room the title takes: 45 letters of the bar's font, so a long one leaves room for what is playing
    readonly property int titleRoom: Math.round(45 * capInk.advanceWidth)
    // The sign on show follows the title's at most once a second: a spinner changes several times a second and each change shown redraws the bar; a sign that comes or goes is shown at once
    property string sign: newSign
    onNewSignChanged: if (newSign === "" || sign === "" || !signWait.running) { sign = newSign; signWait.restart() }
    Timer { id: signWait; interval: 1000; onTriggered: if (bar.sign !== bar.newSign) { bar.sign = bar.newSign; restart() } }
    // How far the sign must move to sit level with the capitals beside it: the middle of a capital's ink less the middle of the sign's ink, whose measured box runs one row long at the foot (the bar's font lacks these signs and the stand-in font draws them low); braille spinners stay put, their dots are meant to move
    TextMetrics { id: capInk; font: Theme.valueFont; text: "H" }
    TextMetrics { id: signInk; font: Theme.valueFont; text: bar.sign }
    readonly property int signLift: sign === "" || (sign >= "\u2800" && sign <= "\u28FF") ? 0 : Math.round(capInk.tightBoundingRect.y + capInk.tightBoundingRect.height / 2 - signInk.tightBoundingRect.y - (signInk.tightBoundingRect.height - 1) / 2)
    // Caffeine (switched in the dashboard): while on, this bar holds mango's "screen in use" mark
    IdleInhibitor { window: bar; enabled: Sys.awake }

    // One cell of the strip: a small label and its value, with a thin line at its left; a cell that does something lights up under the pointer and stays lit while its panel is open
    component Cell: Rectangle {
        id: cell
        property string label
        property string value
        property color tint: Theme.text
        // live: a click does something
        property bool live: false
        // The panel this cell opens, and the tooltip shown when the pointer rests on it
        property string opens
        property string tip
        default property alias extras: content.data
        signal clicked(var mouse)
        signal scrolled(var wheel)
        width: content.width; height: parent.height
        color: opens !== "" && Panels.open === opens && Panels.screen === bar.screen ? Theme.surface2 : live && pointer.containsMouse ? Theme.surface : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion } }

        Ui.Line { height: parent.height }
        Row {
            id: content
            height: parent.height
            leftPadding: Theme.pad; rightPadding: Theme.pad
            spacing: 8
            Ui.Label { anchors.verticalCenter: parent.verticalCenter; visible: text !== ""; text: cell.label }
            Ui.Value { anchors.verticalCenter: parent.verticalCenter; visible: text !== ""; text: cell.value; color: cell.tint; textFormat: Text.PlainText }
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: cell.live ? Qt.PointingHandCursor : Qt.ArrowCursor
            onContainsMouseChanged: bar.rest(cell, containsMouse)
            onClicked: mouse => { bar.rest(cell, false); cell.clicked(mouse) }
            onWheel: wheel => cell.scrolled(wheel)
        }
    }

    // One media sign in the bar: it lights up under the pointer when the player can do it and is greyed out when it cannot; a right click on any sign opens the media panel under them
    component Sign: Rectangle {
        id: sign
        property int glyph
        property bool able: true
        property string tip
        signal used()
        width: 28; height: parent.height
        color: Panels.open === "media" && Panels.screen === bar.screen ? Theme.surface2 : able && pointer.containsMouse ? Theme.surface : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion } }
        Rectangle { anchors.centerIn: parent; width: 24; height: 22; color: "transparent"; border { width: Theme.thin; color: sign.able ? Theme.text2 : Theme.border } }
        Ui.Value { anchors.centerIn: parent; text: String.fromCodePoint(sign.glyph); color: sign.able ? Theme.text : Theme.muted }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: bar.rest(sign, containsMouse)
            onClicked: mouse => {
                bar.rest(sign, false)
                if (mouse.button === Qt.RightButton) { Panels.edge = bar.width - sign.parent.x - sign.parent.width; Panels.toggle("media", bar.screen) }
                else if (sign.able) sign.used()
            }
        }
    }

    // The tooltip: one small box for the whole bar, shown under the cell the pointer has rested on for a moment
    property Item tipCell: null
    function rest(cell, inside) {
        if (inside && cell.tip !== "") { tipCell = cell; tipWait.restart() }
        else if (tipCell === cell) { tipWait.stop(); tipBox.visible = false }
    }
    Timer { id: tipWait; interval: 600; onTriggered: tipBox.visible = true }
    PopupWindow {
        id: tipBox
        anchor.item: bar.tipCell
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.margins.top: Theme.gap + Theme.thick
        implicitWidth: tipText.implicitWidth + 2 * Theme.pad; implicitHeight: Theme.row
        color: Theme.surface
        Rectangle { anchors.fill: parent; color: "transparent"; border { width: Theme.thin; color: Theme.strong } }
        Ui.Label { id: tipText; anchors.centerIn: parent; text: bar.tipCell?.tip ?? ""; color: Theme.text }
    }

    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: Theme.thick; color: Theme.accent }

    Item {
        anchors { fill: parent; bottomMargin: Theme.thick }

        // --- Left: the name with the state square (opens the dashboard), then the tags ---

        Row {
            id: left
            height: parent.height

            // The name, its two strokes in the accent, and the state square as a lamp after it: one button, and a click on it opens the dashboard
            Rectangle {
                id: brand
                property string tip: Sys.stateText + "  /  CLICK: DASHBOARD"
                width: Theme.pad + brandName.width + 8 + 8 + Theme.pad; height: parent.height
                color: Panels.open === "dashboard" && Panels.screen === bar.screen ? Theme.surface2 : brandOver.containsMouse ? Theme.surface : "transparent"
                Ui.Value { id: brandName; x: Theme.pad; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.StyledText; text: "NIX<font color=\"" + Theme.accent + "\">//</font>OS"; font: Qt.font({ family: Theme.family, pixelSize: 15, weight: Font.ExtraBold }) }
                Rectangle { x: brandName.x + brandName.width + 8; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Sys.stateColor }
                MouseArea { id: brandOver; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onContainsMouseChanged: bar.rest(brand, containsMouse); onClicked: { bar.rest(brand, false); Panels.toggle("dashboard", bar.screen) } }
            }
            Row {
                height: parent.height
                leftPadding: 2; rightPadding: 10
                Repeater {
                    model: bar.sets

                    // One tag as a key: filled with the accent while it is shown, a bright frame and number while it holds windows, a dim one while empty, orange while a window on it wants attention; the overview is one key as wide as all of them; the key sits in a slot as high as the bar and 4px wider than itself, so a click at the screen's top edge or between two keys still lands on a tag
                    Item {
                        id: tag
                        required property var modelData
                        readonly property bool overview: modelData.name === "overview"
                        width: key.width + 4; height: parent.height
                        Rectangle {
                            id: key
                            anchors.centerIn: parent
                            width: tag.overview ? Math.max(28 * bar.tagCount - 4, word.implicitWidth + 2 * Theme.pad) : 24; height: 22
                            color: tag.modelData.active ? Theme.accent : over.containsMouse ? Theme.surface2 : "transparent"
                            border { width: Theme.thin; color: tag.modelData.active ? Theme.accent : tag.modelData.urgent ? Theme.warn : tag.modelData.shouldDisplay ? Theme.text2 : Theme.border }
                            Ui.Value {
                                id: word
                                anchors.centerIn: parent
                                text: tag.overview ? "OVERVIEW" : tag.modelData.name
                                color: tag.modelData.active ? Theme.accentInk : tag.modelData.urgent ? Theme.warn : tag.modelData.shouldDisplay ? Theme.text : Theme.muted
                            }
                        }
                        MouseArea { id: over; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tag.modelData.activate() }
                    }
                }
            }
            Ui.Line { height: parent.height }
        }

        // The focused window: its app in small capitals, the title's status sign if it has one, and the title, cut short after 45 letters or where what is playing, or the readings, begin
        Row {
            anchors { left: left.right; leftMargin: Theme.pad; right: nowCell.visible ? nowCell.left : readings.left; rightMargin: Theme.pad }
            height: parent.height
            spacing: 10
            clip: true
            Ui.Label { id: app; anchors.verticalCenter: parent.verticalCenter; text: bar.appName }
            Ui.Value {
                id: signText
                visible: bar.sign !== ""
                anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: bar.signLift }
                text: bar.sign; color: Theme.text2
            }
            Ui.Value {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, bar.titleRoom, parent.width - app.width - parent.spacing - (signText.visible ? signText.width + parent.spacing : 0)))
                elide: Text.ElideRight
                text: bar.appTitle; color: Theme.text2
            }
        }

        SystemClock { id: clock; precision: SystemClock.Minutes }

        // --- Now playing, left of the readings: previous, play or pause and next for the media player that plays, or for the one that played last; a sign the player cannot do is greyed out; a right click on any of them opens the media panel under them; where the window title leaves room, the artist and the track stand before the signs in a window of fixed width (a click on it opens the panel too); the bar's accent line is the track's timeline under them ---

        Row {
            id: nowCell
            anchors.right: readings.left
            height: parent.height
            // The room between the tags and the readings, and how much of it the window title wants: the signs need a little of it, the words take what the title leaves
            readonly property real free: readings.x - left.width
            readonly property real titleWant: app.implicitWidth + 10 + (signText.visible ? signText.implicitWidth + 10 : 0) + Math.min(titleText.implicitWidth, bar.titleRoom) + 2 * Theme.pad
            visible: Sys.track !== "" && free >= 3 * 28 + 10 + Theme.thin + 200
            readonly property string what: ((Sys.artist !== "" ? Sys.artist + "  /  " : "") + Sys.track).slice(0, 80).toUpperCase()
            readonly property real room: free - titleWant - 3 * 28 - 10 - Theme.thin
            Ui.Line { height: parent.height }
            // What is playing, in a window of fixed width (24 letters): a longer line moves through it a letter at a time, like a tape deck's display, rests a moment at its start, and stands still while paused, where it ends in … to show that more follows
            Rectangle {
                id: tape
                readonly property int letters: 24
                readonly property string line: (Sys.artist !== "" ? Sys.artist + "  /  " : "") + Sys.track
                readonly property bool runs: line.length > letters
                property int at: 0
                property int rest: 5
                onLineChanged: { at = 0; rest = 5 }
                visible: nowCell.room >= width
                width: Math.ceil(letters * capInk.advanceWidth) + 2 * Theme.pad; height: parent.height
                color: Panels.open === "media" && Panels.screen === bar.screen ? Theme.surface2 : overWords.containsMouse ? Theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.motion } }
                Ui.Value { x: Theme.pad; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: !tape.runs ? tape.line : Sys.playing ? (tape.line + "   /   " + tape.line).substr(tape.at, tape.letters) : (tape.line + "   /   " + tape.line).substr(tape.at, tape.letters - 1) + "…"; color: Sys.playing ? Theme.text2 : Theme.muted }
                Timer { interval: 400; repeat: true; running: tape.runs && tape.visible && Sys.playing; onTriggered: { if (tape.rest > 0) tape.rest -= 1; else { tape.at = (tape.at + 1) % (tape.line.length + 7); if (tape.at === 0) tape.rest = 5 } } }
                MouseArea { id: overWords; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Panels.edge = bar.width - nowCell.x - nowCell.width; Panels.toggle("media", bar.screen) } }
            }
            Sign { glyph: 0xF048; able: Sys.player?.canGoPrevious ?? false; tip: "PREVIOUS TRACK  /  RIGHT CLICK: PLAYER"; onUsed: Sys.player.previous() }
            Sign { glyph: Sys.playing ? 0xF04C : 0xF04B; able: Sys.player?.canTogglePlaying ?? false; tip: nowCell.what + "  /  CLICK: " + (Sys.playing ? "PAUSE" : "PLAY") + "  /  RIGHT CLICK: PLAYER"; onUsed: Sys.player.togglePlaying() }
            Sign { glyph: 0xF051; able: Sys.player?.canGoNext ?? false; tip: "NEXT TRACK  /  RIGHT CLICK: PLAYER"; onUsed: Sys.player.next() }
            Rectangle { width: 10; height: parent.height; color: Panels.open === "media" && Panels.screen === bar.screen ? Theme.surface2 : "transparent" }
        }
        // The timeline: under what is playing the bar's line is drawn in the second colour, as far as the track has played, and the rest is grey (the whole stretch for a live stream, which has no length)
        Rectangle {
            visible: nowCell.visible
            anchors { left: nowCell.left; right: nowCell.right; top: nowCell.bottom }
            height: Theme.thick
            color: Theme.border
            Rectangle { width: Sys.progress >= 0 ? Math.round(parent.width * Sys.progress) : parent.width; height: parent.height; color: Theme.accent2 }
        }

        // --- Right: one cell per reading; a cell is left out when the machine lacks its hardware ---

        Row {
            id: readings
            anchors.right: parent.right
            height: parent.height

            // The level meters of a tape deck, on the wide bar: processor over memory, sixteen segments each, cyan, then orange, then the accent for the top end; a click opens the dashboard
            Rectangle {
                id: levels
                property string tip: Sys.cpuModel.toUpperCase() + "  /  " + Sys.ramUsed.toFixed(1) + " OF " + Sys.ramTotal.toFixed(1) + " GIB IN USE  /  CLICK: DASHBOARD"
                visible: bar.wide
                width: levelRows.width + 2 * Theme.pad; height: parent.height
                color: Panels.open === "dashboard" && Panels.screen === bar.screen ? Theme.surface2 : levelsOver.containsMouse ? Theme.surface : "transparent"
                Ui.Line { height: parent.height }
                Column {
                    id: levelRows
                    x: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: [{ name: "CPU", figure: Sys.cpu }, { name: "MEM", figure: Sys.ram }]
                        Row {
                            id: level
                            required property var modelData
                            height: 13
                            spacing: 8
                            Ui.Label { anchors.verticalCenter: parent.verticalCenter; width: 28; text: level.modelData.name }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Repeater { model: 16; Rectangle { required property int index; width: 4; height: 8; color: index >= Math.round(16 * level.modelData.figure / 100) ? Theme.surface2 : index < 10 ? Theme.accent2 : index < 14 ? Theme.warn : Theme.accent } }
                            }
                            Ui.Label { anchors.verticalCenter: parent.verticalCenter; width: 20; horizontalAlignment: Text.AlignRight; text: Sys.two(level.modelData.figure); color: Theme.text }
                        }
                    }
                }
                MouseArea { id: levelsOver; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onContainsMouseChanged: bar.rest(levels, containsMouse); onClicked: { bar.rest(levels, false); Panels.toggle("dashboard", bar.screen) } }
            }
            Cell {
                visible: Sys.temp >= 0
                label: "TMP"; value: Sys.temp + "°C"; tint: Sys.tempColor
                live: true
                opens: "temperature"
                tip: "PROCESSOR TEMPERATURE  /  AMBER FROM 75, RED FROM 90  /  CLICK: ALL SENSORS"
                onClicked: Panels.toggle("temperature", bar.screen)
            }
            Cell {
                id: net
                // On the wide bar the traffic stands in place of the link's name: megabits per second down and up, each grey while nothing moves that way and white while data flows, with the unit as a small label
                readonly property bool flows: bar.wide && Sys.link !== "OFF"
                label: "NET"
                value: Sys.link === "OFF" ? "OFF" : flows ? "" : Sys.link
                tint: Sys.link === "OFF" ? Theme.muted : Theme.text
                live: true
                opens: "wifi"
                tip: (Sys.link === "OFF" ? "NO CONNECTION" : Sys.link + ": " + Sys.netName.toUpperCase()) + "  /  TAILSCALE: " + Sys.tailWord + "  /  CLICK: WI-FI NETWORKS"
                onClicked: Panels.toggle("wifi", bar.screen)
                Ui.Value { visible: net.flows; anchors.verticalCenter: parent.verticalCenter; text: "↓ " + Sys.rate(Sys.down).padEnd(4); color: Sys.rate(Sys.down) === "0.0" ? Theme.muted : Theme.text }
                Ui.Value { visible: net.flows; anchors.verticalCenter: parent.verticalCenter; text: "↑ " + Sys.rate(Sys.up).padEnd(4); color: Sys.rate(Sys.up) === "0.0" ? Theme.muted : Theme.text }
                Ui.Label { visible: net.flows; anchors.verticalCenter: parent.verticalCenter; text: "MBPS" }
                // Tailscale's lamp: filled with the accent while it runs, hollow and grey while it is stopped or its service is down, an orange frame while it waits for a login
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Sys.tailState === "Running" ? Theme.accent : "transparent"; border { width: Theme.thin; color: Sys.tailState === "Running" ? Theme.accent : Sys.tailState.startsWith("Needs") ? Theme.warn : Theme.strong } }
            }
            Cell {
                id: blue
                readonly property var adapter: Bluetooth.defaultAdapter
                readonly property var linked: Bluetooth.devices.values.filter(d => d.connected)
                visible: adapter !== null
                label: "BT"; value: !adapter?.enabled ? "OFF" : Sys.two(linked.length)
                tint: !adapter?.enabled || linked.length === 0 ? Theme.muted : Theme.text
                live: true
                opens: "bluetooth"
                tip: (!adapter?.enabled ? "BLUETOOTH IS OFF" : linked.length === 0 ? "NOTHING CONNECTED" : linked.map(d => d.name.toUpperCase()).join(", ")) + "  /  CLICK: DEVICES"
                onClicked: Panels.toggle("bluetooth", bar.screen)
            }
            Cell {
                visible: Sys.sink !== null
                label: "VOL"; value: Sys.muted ? "MUTE" : Sys.volume + "%"
                tint: Sys.muted ? Theme.muted : Theme.text
                live: true
                opens: "audio"
                tip: (Sys.sink?.description ?? "").toUpperCase() + "  /  SCROLL: VOLUME  /  CLICK: OUTPUTS  /  RIGHT CLICK: MUTE"
                onClicked: mouse => { if (mouse.button === Qt.RightButton) Sys.toggleMute(); else Panels.toggle("audio", bar.screen) }
                onScrolled: wheel => Sys.scrollVolume(wheel)
            }
            Cell {
                visible: Sys.hasBattery
                label: Sys.charging ? "BAT+" : "BAT"; value: Sys.charge + "%"; tint: Sys.chargeColor
                live: true
                opens: "battery"
                tip: (Sys.charging ? "CHARGING  /  FULL IN " + Sys.span(Sys.battery.timeToFull).slice(0, 5) : Sys.battery?.timeToEmpty > 0 ? "ON BATTERY  /  EMPTY IN " + Sys.span(Sys.battery.timeToEmpty).slice(0, 5) : "ON MAINS") + "  /  CLICK: BATTERY PANEL"
                onClicked: Panels.toggle("battery", bar.screen)
            }
            // The date as the small label and the time as the value, then a lamp: hollow and grey while nothing waits, filled while notifications wait, cyan while do not disturb is on; a click opens the calendar under it, where the notifications are listed, and a right click switches do not disturb
            Cell {
                id: clockCell
                live: true
                opens: "calendar"
                label: Qt.formatDateTime(clock.date, "ddd dd MMM").toUpperCase(); value: Qt.formatDateTime(clock.date, "HH:mm")
                tip: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy").toUpperCase() + "  /  " + Notify.count + " NOTIFICATIONS WAITING  /  CLICK: CALENDAR  /  RIGHT CLICK: DO NOT DISTURB " + (Notify.dnd ? "OFF" : "ON")
                onClicked: mouse => { if (mouse.button === Qt.RightButton) Notify.dnd = !Notify.dnd; else Panels.toggle("calendar", bar.screen) }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: Notify.count > 0 ? (Notify.dnd ? Theme.info : Theme.accent) : "transparent"; border { width: Theme.thin; color: Notify.dnd ? Theme.info : Notify.count > 0 ? Theme.accent : Theme.strong } }
            }
        }
    }
}
