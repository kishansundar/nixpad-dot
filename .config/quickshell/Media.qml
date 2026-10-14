import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets

// The media panel (a click on the bar's now-playing cell), from the top: where the sound comes from and a way to its window or tab, what plays, the timeline, and the controls the player really offers
PanelWindow {
    id: media
    visible: Panels.open === "media"
    screen: Panels.screen
    // Under the cell that opened it, as far as the monitor's edges allow
    anchors { top: true; right: true }
    margins { top: Theme.gap; right: Math.max(Theme.gap, Math.min(Panels.edge, (screen?.width ?? 1920) - implicitWidth - Theme.gap)) }
    exclusiveZone: 0
    implicitWidth: 460
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // How many seconds the two seek controls move
    readonly property int step: 10

    // The player shown: the one picked in the panel while it is open, else the one the bar shows
    property var pick: null
    readonly property var player: pick && Sys.players.includes(pick) ? pick : Sys.player
    onVisibleChanged: { scrub = -1; if (visible) { pick = null; keys.forceActiveFocus(); player?.positionChanged() } }
    onPlayerChanged: if (visible && !player) Panels.close()

    // The timeline needs a real length; a live stream has none and gets the word LIVE, and nothing is made up
    readonly property real length: Sys.lengthOf(player)
    readonly property bool timed: length > 0 && player.positionSupported
    readonly property bool live: !!player && player.lengthSupported && player.length >= 360000
    // Where the pointer holds the timeline while it is dragged, 0 to 1 (-1: not dragged), and the part of the track shown as played
    property real scrub: -1
    readonly property real part: scrub >= 0 ? scrub : timed ? Math.max(0, Math.min(1, player.position / length)) : 0
    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds)), h = Math.floor(s / 3600)
        return (h > 0 ? Sys.two(h) + ":" : "") + Sys.two(Math.floor(s % 3600 / 60)) + ":" + Sys.two(s % 60)
    }
    // Seeking stays inside the track when its length is known (a seek past the end would count as "next")
    function jump(seconds) {
        if (!player?.canSeek) return
        if (timed) player.position = Math.max(0, Math.min(length - 1, player.position + seconds)); else player.seek(seconds)
    }

    // The app behind a player: its desktop entry gives the name and the icon, the player's own name is the fallback
    function entryOf(p) { return p?.desktopEntry ? DesktopEntries.byId(p.desktopEntry) : null }
    function nameOf(p) { return (entryOf(p)?.name || p?.identity || "").toUpperCase() }
    function iconOf(p) { const icon = entryOf(p)?.icon ?? ""; return icon ? Quickshell.iconPath(icon, true) : "" }
    // Pictures are taken only from a file or over https
    readonly property string art: /^(file|https):\/\//.test(player?.trackArtUrl ?? "") ? player.trackArtUrl : ""

    // Open: first the app is asked to raise its own media (a browser then selects the tab that plays), then mango is told to show that app's window: the bus names the process that owns the player, mango's window list is matched by it, and of several windows the one whose title holds the track's title wins. An app that cannot raise itself and has no window is started from its desktop entry; nothing from the track's data is ever run
    property var wanted: null
    Process {
        id: find
        command: ["sh", "-c", 'busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s "$1"; echo; sleep 0.3; mmsg get all-clients', "sh", media.wanted?.dbusName ?? ""]
        stdout: StdioCollector { onStreamFinished: media.show(text) }
    }
    function open() {
        if (!player) return
        wanted = player
        Panels.close()
        if (wanted.canRaise) wanted.raise()
        find.running = true
    }
    function show(answer) {
        const p = wanted
        wanted = null
        if (!p) return
        const pid = Number(answer.match(/^u (\d+)/m)?.[1] ?? 0)
        let clients = []
        try { clients = JSON.parse(answer.slice(answer.indexOf("{"))).clients ?? [] } catch (e) {}
        const own = clients.filter(c => c.pid === pid)
        const client = own.find(c => p.trackTitle !== "" && c.title.includes(p.trackTitle)) ?? own[0] ?? clients.find(c => p.desktopEntry !== "" && c.appid === p.desktopEntry)
        if (client) Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + client.id]); else if (!p.canRaise) entryOf(p)?.execute()
    }

    // One control: a square button like the dashboard's; the play button has the accent frame, and a control the player cannot do is greyed out and dead
    component Control: Rectangle {
        id: control
        property string sign
        property bool able: true
        property bool main: false
        signal used()
        width: (parent.width - 4 * parent.spacing) / 5; height: 40
        color: able && over.hovered ? Theme.surface : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion } }
        border { width: main ? Theme.thick : Theme.thin; color: !able ? Theme.surface2 : main ? Theme.accent : Theme.border }
        Ui.Value { anchors.centerIn: parent; text: control.sign; color: !control.able ? Theme.border : control.main ? Theme.accent : Theme.text }
        HoverHandler { id: over; cursorShape: control.able ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { onTapped: if (control.able) control.used() }
    }

    Ui.Frame { anchors.fill: parent; focused: true }
    // Space plays or pauses, Left and Right seek, P and N change the track, Tab the player, O or Enter opens the app, Esc closes
    Item {
        id: keys
        Keys.onPressed: event => {
            const p = media.player
            if (event.key === Qt.Key_Escape) Panels.close()
            else if (!p) return
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_K) { if (p.canTogglePlaying) p.togglePlaying() }
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) media.jump(-media.step)
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) media.jump(media.step)
            else if (event.key === Qt.Key_P) { if (p.canGoPrevious) p.previous() }
            else if (event.key === Qt.Key_N) { if (p.canGoNext) p.next() }
            else if (event.key === Qt.Key_Tab) media.pick = Sys.players[(Sys.players.indexOf(p) + 1) % Sys.players.length]
            else if (event.key === Qt.Key_O || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) media.open()
        }
    }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: parent.width - 2 * Theme.thick

        Ui.Head { title: "MEDIA / NOW PLAYING"; kana: "再生中"; note: media.player ? MprisPlaybackState.toString(media.player.playbackState).toUpperCase() : "" }
        Ui.Line { width: parent.width }

        // Where the sound comes from: each player's app (with several, the square marks the one shown and a click changes it), and OPEN, which goes to that app's window, in a browser to the tab that plays
        Item {
            width: parent.width; height: 36
            Row {
                x: 16; width: parent.width - 100; height: parent.height
                spacing: 18
                clip: true
                Repeater {
                    model: Sys.players

                    Item {
                        id: tab
                        required property var modelData
                        required property int index
                        readonly property bool several: Sys.players.length > 1
                        readonly property bool shown: index === Sys.players.indexOf(media.player)
                        readonly property string picture: media.iconOf(modelData)
                        width: name.x + name.width; height: parent.height
                        Rectangle { visible: tab.several; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; color: tab.shown ? Theme.accent : "transparent"; border { width: Theme.thin; color: tab.shown ? Theme.accent : Theme.border } }
                        IconImage { id: icon; visible: tab.picture !== ""; x: tab.several ? 16 : 0; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; source: tab.picture }
                        Ui.Label { id: name; x: icon.x + (icon.visible ? 24 : 0); anchors.verticalCenter: parent.verticalCenter; text: media.nameOf(tab.modelData); color: tab.shown ? Theme.text : Theme.text2 }
                        HoverHandler { cursorShape: tab.several ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler { onTapped: media.pick = Sys.players[tab.index] }
                    }
                }
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                width: go.width + 20; height: 22
                color: over.hovered ? Theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.motion } }
                border { width: Theme.thin; color: Theme.border }
                Ui.Label { id: go; anchors.centerIn: parent; text: "OPEN"; color: Theme.text }
                HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: media.open() }
            }
        }
        Ui.Line { width: parent.width }

        // What plays: the picture if the player gives one (wider for a video still), the title on two lines at most, who made it, and the time in the corner
        Item {
            width: parent.width; height: 120
            Image {
                id: cover
                visible: media.art !== ""
                x: 16; y: 12; width: implicitWidth > implicitHeight * 1.3 ? 150 : 96; height: 96
                clip: true
                // Loaded only while the panel is open: a track change with the panel closed fetches and decodes nothing
                source: media.visible ? media.art : ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize.height: 192
            }
            Rectangle { visible: cover.visible; anchors.fill: cover; color: "transparent"; border { width: Theme.thin; color: Theme.border } }
            Column {
                anchors { left: parent.left; leftMargin: cover.visible ? cover.width + 30 : 16; right: parent.right; rightMargin: 16; top: parent.top; topMargin: 12 }
                spacing: 6
                Ui.Value { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; text: Sys.titleOf(media.player) || "NOTHING LOADED" }
                Ui.Label { visible: text !== ""; width: parent.width; elide: Text.ElideRight; text: (media.player?.trackArtist ?? "").toUpperCase() }
            }
            Ui.Label {
                anchors { left: parent.left; leftMargin: cover.visible ? cover.width + 30 : 16; bottom: parent.bottom; bottomMargin: 12 }
                text: media.timed ? media.clock(media.scrub >= 0 ? media.scrub * media.length : media.player.position) + " / " + media.clock(media.length) : media.live ? "LIVE" : ""
                color: media.timed ? Theme.text : Theme.accent
            }
        }

        // The timeline is the line under the picture, as the bar's own line is under its cell: the part played in the second colour; a click or a drag along it moves through the track when the player can seek. Without a known length it is a plain divider
        Item {
            width: parent.width; height: media.timed ? 4 : Theme.thin
            Rectangle { anchors.fill: parent; color: media.timed ? Theme.surface2 : Theme.border }
            Rectangle { visible: media.timed; width: Math.round(parent.width * media.part); height: parent.height; color: Theme.accent2 }
            MouseArea {
                enabled: media.timed && media.player.canSeek
                anchors { fill: parent; topMargin: -10; bottomMargin: -10 }
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: mouse => media.scrub = Math.max(0, Math.min(1, mouse.x / width))
                onPositionChanged: mouse => { if (pressed) media.scrub = Math.max(0, Math.min(1, mouse.x / width)) }
                onReleased: { if (media.scrub >= 0) media.player.position = Math.min(media.length - 1, media.scrub * media.length); media.scrub = -1 }
                onCanceled: media.scrub = -1
            }
        }

        // Previous track, back 10 seconds, play or pause, on 10 seconds, next track
        Item {
            width: parent.width; height: 64
            Row {
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Control { sign: String.fromCodePoint(0xF048); able: media.player?.canGoPrevious ?? false; onUsed: media.player.previous() }
                Control { sign: "-" + media.step; able: media.player?.canSeek ?? false; onUsed: media.jump(-media.step) }
                Control { sign: String.fromCodePoint(media.player?.isPlaying ? 0xF04C : 0xF04B); main: true; able: media.player?.canTogglePlaying ?? false; onUsed: media.player.togglePlaying() }
                Control { sign: "+" + media.step; able: media.player?.canSeek ?? false; onUsed: media.jump(media.step) }
                Control { sign: String.fromCodePoint(0xF051); able: media.player?.canGoNext ?? false; onUsed: media.player.next() }
            }
        }
        Ui.Line { width: parent.width }
        Ui.Foot { keys: Sys.players.length > 1 ? "SPACE: PLAY  /  ←→: SEEK  /  TAB: PLAYER  /  O: OPEN" : "SPACE: PLAY  /  ←→: SEEK  /  P N: TRACK  /  O: OPEN" }
    }
}
