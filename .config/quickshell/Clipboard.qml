import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The clipboard history (Super+V): what cliphist has stored, newest first; typing narrows it, Up and Down choose, Enter puts the chosen entry back on the clipboard, Delete forgets it, Esc closes
PanelWindow {
    id: clipboard
    visible: Panels.open === "clipboard"
    screen: Panels.screen
    // In the middle of the monitor, a quarter of the way down
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1080) / 4)
    exclusiveZone: 0
    implicitWidth: 720
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Every stored entry as { id, text, image }, asked from cliphist each time the panel opens; a picture is listed by its kind and size
    property var entries: []
    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                clipboard.entries = text.split("\n").filter(line => line.includes("\t")).map(line => {
                    const cut = line.indexOf("\t"), words = line.slice(cut + 1)
                    const picture = words.match(/^\[\[ binary data (\S+ \S+) (\w+) (\d+x\d+) \]\]$/)
                    return { id: line.slice(0, cut), text: picture ? "IMAGE  " + picture[2].toUpperCase() + " " + picture[3] + "  " + picture[1] : words, image: picture !== null }
                })
                clipboard.chosen = Math.max(0, Math.min(clipboard.chosen, clipboard.found.length - 1))
            }
        }
    }

    // What has been typed, the entries that contain it, which of them is chosen, and the ten on show (the window moves so the chosen one stays in it)
    property string query: ""
    property int chosen: 0
    property int first: 0
    readonly property int rows: 10
    readonly property var found: {
        const typed = query.trim().toLowerCase()
        return typed ? entries.filter(entry => entry.text.toLowerCase().includes(typed)) : entries
    }
    readonly property var shown: found.slice(first, first + rows)
    onChosenChanged: first = Math.min(chosen, Math.max(first, chosen - rows + 1))
    function move(by) { chosen = Math.max(0, Math.min(chosen + by, found.length - 1)) }
    onVisibleChanged: if (visible) { query = ""; chosen = 0; first = 0; input.clear(); input.forceActiveFocus(); list.running = true }

    // Copying and forgetting go through cliphist; the entry's number is handed to the shell as an argument, never written into the command text
    function copy(entry) {
        Panels.close()
        Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist decode | wl-copy", "sh", entry.id])
    }
    Process {
        id: remove
        property string target: ""
        command: ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", target]
        onExited: list.running = true
    }
    function forget(entry) { remove.target = entry.id; remove.running = true }

    Ui.Frame { anchors.fill: parent; focused: true }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: parent.width - 2 * Theme.thick

        Ui.Head {
            title: "CLIPBOARD / HISTORY"; kana: "クリップボード"
            note: clipboard.query.trim() === "" ? clipboard.entries.length + " ENTRIES" : Sys.two(clipboard.found.length) + (clipboard.found.length === 1 ? " MATCH" : " MATCHES")
        }
        Ui.Line { width: parent.width }

        // The search line: SEARCH: [ what is typed ]
        Item {
            width: parent.width; height: 44
            Ui.Label { id: ask; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "SEARCH:" }
            Ui.Value { id: opening; anchors { left: ask.right; leftMargin: 10; verticalCenter: parent.verticalCenter } text: "["; color: Theme.muted }
            Ui.Value { id: closing; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "]"; color: Theme.muted }
            TextInput {
                id: input
                anchors { left: opening.right; right: closing.left; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
                clip: true
                color: Theme.text
                font: Theme.valueFont
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentInk
                cursorDelegate: Rectangle { width: Theme.thick; color: Theme.accent }
                onTextEdited: { clipboard.query = text; clipboard.chosen = 0; clipboard.first = 0 }
                onAccepted: if (clipboard.found.length > 0) clipboard.copy(clipboard.found[clipboard.chosen])
                Keys.onDownPressed: clipboard.move(1)
                Keys.onUpPressed: clipboard.move(-1)
                Keys.onTabPressed: clipboard.move(1)
                Keys.onEscapePressed: Panels.close()
                // Delete forgets the chosen entry (Backspace edits the search), Page Up and Down move by a screenful
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Delete) { if (clipboard.found.length > 0) clipboard.forget(clipboard.found[clipboard.chosen]); event.accepted = true }
                    else if (event.key === Qt.Key_PageDown) { clipboard.move(clipboard.rows); event.accepted = true }
                    else if (event.key === Qt.Key_PageUp) { clipboard.move(-clipboard.rows); event.accepted = true }
                }
            }
            Ui.Value { anchors { left: input.left; leftMargin: 6; verticalCenter: parent.verticalCenter } visible: input.text === ""; text: "type to narrow the list..."; color: Theme.muted }
        }
        Ui.Line { width: parent.width }

        Repeater {
            model: clipboard.shown

            // One entry: its place in the list and its first line; the chosen row gets the accent frame; a click copies it
            Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property int place: clipboard.first + index
                readonly property bool chosen: place === clipboard.chosen
                width: body.width; height: 30
                color: chosen || over.hovered ? Theme.surface : "transparent"
                border { width: chosen ? Theme.thick : 0; color: Theme.accent }

                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: Sys.two(entry.place + 1); color: entry.chosen ? Theme.accent : Theme.muted }
                Ui.Value {
                    anchors { left: parent.left; leftMargin: 56; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: entry.modelData.text
                    color: entry.modelData.image ? Theme.text2 : Theme.text
                }
                HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: clipboard.copy(entry.modelData) }
            }
        }

        // What the list says while it is empty
        Item {
            visible: clipboard.found.length === 0
            width: parent.width; height: 34
            Ui.Label {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                elide: Text.ElideRight
                text: clipboard.entries.length === 0 ? "NOTHING COPIED YET" : "NO ENTRY CONTAINS \"" + clipboard.query.trim().toUpperCase() + "\""
                color: Theme.muted
            }
        }
        Ui.Line { width: parent.width }
        Ui.Foot { keys: "ENTER: COPY  /  ↑↓: SELECT  /  DEL: FORGET  /  ESC: CLOSE" }
    }
}
