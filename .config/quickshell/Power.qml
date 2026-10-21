import QtQuick
import Quickshell
import Quickshell.Wayland

// The power panel (Super+Esc, or POWER in the dashboard): five numbered tiles in the lower middle of the monitor; every tile but Lock asks once more before it acts
PanelWindow {
    id: power
    visible: Panels.open === "power"
    screen: Panels.screen
    anchors.bottom: true
    margins.bottom: Math.round((screen?.height ?? 1080) / 6)
    exclusiveZone: 0
    implicitWidth: body.width + 2 * Theme.thick
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Lock comes first, so an Enter by mistake does no harm; asks: the tile closes every app or puts the laptop to sleep, so it must be picked twice
    readonly property var tiles: [
        { label: "LOCK", asks: false, command: ["loginctl", "lock-session"] },
        { label: "LOG OUT", asks: true, command: ["mmsg", "dispatch", "quit"] },
        { label: "SLEEP", asks: true, command: ["systemctl", "suspend"] },
        { label: "RESTART", asks: true, command: ["systemctl", "reboot"] },
        { label: "POWER OFF", asks: true, command: ["systemctl", "poweroff"] }
    ]
    // The tile the keyboard has chosen, the tile waiting for its second pick (-1 for none), and how far that tile is armed, from 0 to 1 (the second pick counts only at 1, so two quick Enters cannot restart by mistake)
    property int chosen: 0
    property int asked: -1
    property real armed: 0
    function pick(index) {
        if (tiles[index].asks && asked !== index) { chosen = index; asked = index; return }
        if (tiles[index].asks && armed < 1) return
        Panels.close()
        Quickshell.execDetached(tiles[index].command)
    }
    onAskedChanged: { arming.stop(); armed = 0; if (asked >= 0) arming.start() }
    NumberAnimation { id: arming; target: power; property: "armed"; from: 0; to: 1; duration: 700 }
    onVisibleChanged: if (visible) { chosen = 0; asked = -1; keys.forceActiveFocus() }

    Ui.Frame { anchors.fill: parent; focused: true }
    // Left and Right (or H and L) move, 1 to 5 jump to a tile, Enter picks, Esc takes back a question or closes; every other key does nothing, so a stray letter cannot switch the laptop off
    Item {
        id: keys
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Right || event.key === Qt.Key_L) { power.asked = -1; power.chosen = Math.min(power.chosen + 1, power.tiles.length - 1) }
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) { power.asked = -1; power.chosen = Math.max(power.chosen - 1, 0) }
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) { power.asked = -1; power.chosen = event.key - Qt.Key_1 }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) power.pick(power.chosen)
            else if (event.key === Qt.Key_Escape) { if (power.asked >= 0) power.asked = -1; else Panels.close() }
        }
    }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: row.width + 16

        Ui.Head { title: "NIX / POWER"; kana: "電源"; note: Sys.rebootDue ? "REBOOT DUE: " + Sys.rebootWhy : "SUPER+ESC" }
        Ui.Line { width: parent.width }
        Item { width: 1; height: 8 }
        Row {
            id: row
            x: 8
            spacing: 8

            Repeater {
                model: power.tiles

                // One tile: its number over its name; the chosen one gets the accent frame, and one waiting for its second pick turns red while a line along its foot fills as it arms
                Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === power.chosen
                    readonly property bool asked: index === power.asked
                    width: 112; height: 104
                    color: chosen || over.hovered ? Theme.surface : "transparent"
                    border { width: chosen || asked ? Theme.thick : Theme.thin; color: asked ? Theme.error : chosen ? Theme.accent : Theme.border }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Ui.Value { anchors.horizontalCenter: parent.horizontalCenter; text: Sys.two(tile.index + 1); font: Theme.displayFont; color: tile.asked ? Theme.error : tile.chosen ? Theme.accent : Theme.text }
                        Ui.Label { anchors.horizontalCenter: parent.horizontalCenter; text: tile.asked ? "CONFIRM?" : tile.modelData.label; color: tile.asked ? Theme.error : tile.chosen ? Theme.text : Theme.text2 }
                    }
                    Rectangle { visible: tile.asked; anchors.bottom: parent.bottom; width: Math.round(parent.width * power.armed); height: 4; color: Theme.error }
                    // The bar's reboot lamp, repeated on the RESTART tile while a reboot is due
                    Rectangle { visible: Sys.rebootDue && tile.modelData.label === "RESTART"; x: parent.width - 16; y: 8; width: 8; height: 8; color: Theme.warn }
                    HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: power.pick(tile.index) }
                }
            }
        }
        Item { width: 1; height: 8 }
        Ui.Line { width: parent.width }
        Ui.Foot {
            keys: power.asked >= 0 ? "ENTER: " + power.tiles[power.asked].label + " NOW  /  ESC: CANCEL" : "1-5 ←→: SELECT  /  ENTER: RUN  /  ESC: CLOSE"
            tint: power.asked >= 0 ? Theme.warn : Theme.muted
        }
    }
}
