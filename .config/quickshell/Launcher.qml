import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// The application index (Super+Space): typing searches the installed apps, Up and Down choose, Enter launches, Ctrl and a number launches that row, Esc closes
PanelWindow {
    id: launcher
    visible: Panels.open === "launcher"
    screen: Panels.screen
    // In the middle of the monitor, a third of the way down
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1080) / 3)
    exclusiveZone: 0
    implicitWidth: 560
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // What has been typed, and which of the shown apps is chosen
    property string query: ""
    property int chosen: 0
    readonly property var apps: DesktopEntries.applications.values.filter(app => !app.noDisplay)
    // Every app that fits: names that start with the typed text first, then names that contain it, then a match in the description or keywords
    readonly property var found: {
        const typed = query.trim().toLowerCase()
        if (!typed) return []
        const rank = app => {
            const name = app.name.toLowerCase()
            return name.startsWith(typed) ? 0 : name.includes(typed) ? 1 : (app.genericName + " " + app.comment + " " + app.keywords.join(" ")).toLowerCase().includes(typed) ? 2 : 3
        }
        return apps.map(app => ({ app: app, rank: rank(app) })).filter(m => m.rank < 3)
            .sort((a, b) => a.rank - b.rank || a.app.name.localeCompare(b.app.name)).map(m => m.app)
    }
    // The list shows the best eight; the count in the header says how many fit in all
    readonly property var shown: found.slice(0, 8)
    onVisibleChanged: if (visible) { query = ""; chosen = 0; input.clear(); input.forceActiveFocus() }

    // An app that needs a terminal is started inside kitty
    function launch(app) {
        Panels.close()
        if (app.runInTerminal) Quickshell.execDetached(["kitty", ...app.command]); else app.execute()
    }
    // A name in capitals with the typed letters in the accent, where the name holds them (the signs & and < are written out so a name cannot be read as markup)
    function marked(name) {
        const typed = query.trim().toLowerCase()
        const at = typed ? name.toLowerCase().indexOf(typed) : -1
        const plain = part => part.toUpperCase().replace(/&/g, "&amp;").replace(/</g, "&lt;")
        if (at < 0) return plain(name)
        return plain(name.slice(0, at)) + "<font color=\"" + Theme.accent + "\">" + plain(name.slice(at, at + typed.length)) + "</font>" + plain(name.slice(at + typed.length))
    }

    Ui.Frame { anchors.fill: parent; focused: true }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: parent.width - 2 * Theme.thick

        Ui.Head {
            title: "NIX / APP INDEX"; kana: "アプリ"
            note: launcher.query.trim() === "" ? launcher.apps.length + " ENTRIES" : Sys.two(launcher.found.length) + (launcher.found.length === 1 ? " MATCH" : " MATCHES")
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
                onTextEdited: { launcher.query = text; launcher.chosen = 0 }
                onAccepted: if (launcher.shown.length > 0) launcher.launch(launcher.shown[launcher.chosen])
                Keys.onDownPressed: launcher.chosen = Math.min(launcher.chosen + 1, launcher.shown.length - 1)
                Keys.onUpPressed: launcher.chosen = Math.max(launcher.chosen - 1, 0)
                Keys.onTabPressed: launcher.chosen = (launcher.chosen + 1) % Math.max(1, launcher.shown.length)
                Keys.onEscapePressed: Panels.close()
                Keys.onPressed: event => { if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_8) { event.accepted = true; if (event.key - Qt.Key_1 < launcher.shown.length) launcher.launch(launcher.shown[event.key - Qt.Key_1]) } }
            }
            Ui.Value { anchors { left: input.left; leftMargin: 6; verticalCenter: parent.verticalCenter } visible: input.text === ""; text: "type application name..."; color: Theme.muted }
        }
        Ui.Line { visible: launcher.query.trim() !== ""; width: parent.width }

        Repeater {
            model: launcher.shown

            // One app: its number, its icon when the icon theme has one, its name with the typed letters in the accent, and at the right what it is; the chosen row gets the accent frame
            Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property bool chosen: index === launcher.chosen
                readonly property string picture: Quickshell.iconPath(modelData.icon, true)
                width: body.width; height: 34
                color: chosen || over.hovered ? Theme.surface : "transparent"
                border { width: chosen ? Theme.thick : 0; color: Theme.accent }

                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: Sys.two(entry.index + 1); color: entry.chosen ? Theme.accent : Theme.muted }
                IconImage { x: 48; anchors.verticalCenter: parent.verticalCenter; visible: entry.picture !== ""; implicitSize: 18; source: entry.picture }
                Ui.Value {
                    anchors { left: parent.left; leftMargin: 80; right: what.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: launcher.marked(entry.modelData.name)
                }
                Ui.Label {
                    id: what
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    width: Math.min(implicitWidth, 220)
                    elide: Text.ElideRight
                    text: (entry.modelData.genericName || entry.modelData.comment || "").toUpperCase()
                    color: Theme.muted
                }
                HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: launcher.launch(entry.modelData) }
            }
        }

        // What the list says when nothing fits
        Item {
            visible: launcher.query.trim() !== "" && launcher.shown.length === 0
            width: parent.width; height: 34
            Ui.Label {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                elide: Text.ElideRight
                text: "NO APPLICATION MATCHES \"" + launcher.query.trim().toUpperCase() + "\""
                color: Theme.muted
            }
        }
        Ui.Line { width: parent.width }
        Ui.Foot { keys: "ENTER: LAUNCH  /  ↑↓: SELECT  /  CTRL+1-8: ROW  /  ESC: CLOSE" }
    }
}
