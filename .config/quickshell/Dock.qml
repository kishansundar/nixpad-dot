import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// The dock: the pinned apps, whatever else has a window, and at its right end the tray's apps, as a strip of square cells floating at the foot of every monitor; the line along its top is light over an app that runs and the accent over the one in use
Scope {
    id: dock

    // --- Settings ---

    // The side of a cell and of the picture in it
    readonly property int cell: 44
    readonly property int icon: 28
    // Where the dock sits along the bottom edge: "left", "center" or "right"
    readonly property string side: "center"
    // true: out of sight until the pointer rests on the bottom edge, except on a monitor that shows no window, where it stays out; false: always there, and windows keep clear of it
    readonly property bool hides: true
    // How long the pointer rests on the edge before the dock comes, how long after it has left the dock goes, and how long the dock waits for a pointer that rests on the edge and never moves onto it, in ms
    readonly property int comes: 150
    readonly property int goes: 500
    readonly property int waits: 3000
    // Whether the first cell opens the app index
    readonly property bool index: true
    // How solid the dock's body is, from 0 (clear) to 1 (solid); it has no frame, and the bar's own number is Theme.solid
    readonly property real solid: 0.70
    // How much the picture under the pointer grows (1 leaves it as it is)
    readonly property real grows: 1

    // Which monitors show no window on their current tag: mango says so by itself whenever a tag or its windows change, and a minimised window does not count
    property var bare: ({})
    Process {
        running: true
        command: ["mmsg", "watch", "all-tags"]
        stdout: SplitParser {
            onRead: line => {
                try { const seen = {}; for (const m of JSON.parse(line).all_tags) seen[m.monitor] = !m.tags.some(t => t.is_active && t.client_count > 0); dock.bare = seen } catch (e) {}
            }
        }
    }

    // The pinned apps by the name of their desktop entry, kept in dock.json beside this file: a right click on a cell pins or unpins, and the file can be edited by hand
    FileView {
        path: Quickshell.shellDir + "/dock.json"
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: writeAdapter()
        onAdapterUpdated: writeAdapter()
        JsonAdapter { id: saved; property list<string> pinned: ["zen", "kitty", "org.gnome.Nautilus", "spotify", "md.obsidian.Obsidian"] }
    }
    function pin(id) { saved.pinned = saved.pinned.includes(id) ? saved.pinned.filter(p => p !== id) : saved.pinned.concat([id]) }

    // --- The apps ---

    // One cell each: the pinned apps in their order, then the other apps that have a window; each with its desktop entry (none when no entry fits a window) and its windows
    readonly property var apps: {
        DesktopEntries.applications.values.length
        const list = saved.pinned.map(id => ({ id: id, entry: DesktopEntries.byId(id), pinned: true, windows: [] }))
        for (const window of ToplevelManager.toplevels.values) {
            const entry = DesktopEntries.heuristicLookup(window.appId)
            const id = entry?.id ?? window.appId
            let app = list.find(a => a.id === id)
            if (!app) { app = { id: id, entry: entry, pinned: false, windows: [] }; list.push(app) }
            app.windows.push(window)
        }
        return list.filter(a => a.entry || a.windows.length > 0)
    }
    // An app that needs a terminal is started inside kitty
    function launch(entry) { if (entry.runInTerminal) Quickshell.execDetached(["kitty", ...entry.command]); else entry.execute() }
    // A click starts an app that has no window; with windows it shows the next one after the one in use (the first when none of them is): mango is asked for its window list, because only mango can show a window that is on another tag
    property var wanted: []
    function use(app) {
        if (app.windows.length === 0) { if (app.entry) launch(app.entry); return }
        wanted = app.windows.map(w => w.appId)
        ask.running = true
    }
    Process {
        id: ask
        command: ["mmsg", "get", "all-clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let mine = []
                try { mine = JSON.parse(text).clients.filter(c => dock.wanted.includes(c.appid)) } catch (e) {}
                if (mine.length === 0) return
                const next = mine[(mine.findIndex(c => c.is_focused) + 1) % mine.length]
                Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + next.id])
            }
        }
    }
    // The rows of a cell's menu: a new window, what else the app offers by itself, pinning, and closing its windows
    function rows(app) {
        const list = []
        if (app.entry) {
            list.push({ label: "NEW WINDOW", pick: () => launch(app.entry) })
            for (const action of app.entry.actions) if (action.name.toUpperCase() !== "NEW WINDOW") list.push({ label: action.name.toUpperCase(), pick: () => action.execute() })
            list.push({ label: app.pinned ? "UNPIN" : "PIN TO DOCK", active: app.pinned, pick: () => pin(app.id) })
        }
        if (app.windows.length > 0) list.push({ label: app.windows.length === 1 ? "CLOSE WINDOW" : "CLOSE " + app.windows.length + " WINDOWS", pick: () => { for (const window of app.windows) window.close() } })
        return list
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: place
            required property var modelData
            // Whether the dock is out on this monitor, the cell whose menu is open, and whether that menu is showing
            property bool out: !dock.hides
            readonly property bool bare: dock.bare[modelData.name] === true
            property var menuCell: null
            readonly property bool menuOpen: Panels.open === "dock" && Panels.screen === modelData && menuCell !== null
            onMenuOpenChanged: if (menuOpen) { tipWait.stop(); tipBox.visible = false } else go.restart()
            // Whether the pointer has been on the dock since it came: mango says nothing about a pointer that rests still under a dock that has just appeared, so until then the dock waits longer
            property bool touched: false
            Timer { id: come; interval: dock.comes; onTriggered: { place.touched = false; place.out = true; go.restart() } }
            Timer { id: go; interval: place.touched ? dock.goes : dock.waits; onTriggered: if (dock.hides && !over.hovered && !place.menuOpen) place.out = false }

            // The bottom edge under a hidden dock: resting the pointer on it brings the dock (under its own layer name)
            PanelWindow {
                screen: place.modelData
                visible: dock.hides && !place.out && !place.bare
                anchors { bottom: true; left: dock.side === "left"; right: dock.side === "right" }
                margins { left: Theme.gap; right: Theme.gap }
                exclusiveZone: 0
                implicitWidth: strip.width; implicitHeight: Theme.gap
                color: "transparent"
                WlrLayershell.namespace: "quickshell-unseen"
                MouseArea { anchors.fill: parent; hoverEnabled: true; onContainsMouseChanged: containsMouse ? come.restart() : come.stop() }
            }

            // The dock itself, under the bar's layer name
            PanelWindow {
                id: strip
                screen: place.modelData
                visible: place.out || place.bare
                anchors { bottom: true; left: dock.side === "left"; right: dock.side === "right" }
                margins { left: Theme.gap; right: Theme.gap }
                exclusiveZone: dock.hides ? 0 : height
                implicitWidth: frame.width; implicitHeight: frame.height + Theme.gap
                color: "transparent"
                WlrLayershell.namespace: "quickshell-bar"

                HoverHandler { id: over; onHoveredChanged: if (hovered) { place.touched = true; go.stop() } else go.restart() }

                // The tooltip: one small box, shown over the cell the pointer has rested on for a moment
                property Item tipCell: null
                function rest(cell, inside) {
                    if (inside && cell.tip !== "") { tipCell = cell; tipWait.restart() }
                    else if (tipCell === cell) { tipWait.stop(); tipBox.visible = false }
                }
                Timer { id: tipWait; interval: 600; onTriggered: tipBox.visible = true }
                PopupWindow {
                    id: tipBox
                    anchor.item: strip.tipCell
                    anchor.edges: Edges.Top | Edges.Left
                    anchor.gravity: Edges.Top | Edges.Right
                    anchor.margins.bottom: Theme.gap + Theme.thick
                    implicitWidth: tipText.implicitWidth + 2 * Theme.pad; implicitHeight: Theme.row
                    color: Theme.surface
                    Rectangle { anchors.fill: parent; color: "transparent"; border { width: Theme.thin; color: Theme.strong } }
                    Ui.Label { id: tipText; anchors.centerIn: parent; text: strip.tipCell?.tip ?? ""; color: Theme.text }
                }

                // One cell: it lights up under the pointer, and stays lit while its menu is open
                component Cell: Rectangle {
                    id: cell
                    property string tip
                    property bool ruled: false
                    property bool lit: false
                    readonly property alias hovered: pointer.containsMouse
                    signal clicked(var mouse)
                    width: dock.cell; height: dock.cell
                    color: lit ? Theme.surface2 : pointer.containsMouse ? Theme.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.motion } }
                    Ui.Line { visible: cell.ruled; height: parent.height }
                    MouseArea {
                        id: pointer
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: strip.rest(cell, containsMouse)
                        onClicked: mouse => { strip.rest(cell, false); cell.clicked(mouse) }
                    }
                }

                Rectangle {
                    id: frame
                    width: cells.width + 2 * Theme.thick; height: dock.cell + 2 * Theme.thick
                    color: Qt.alpha(Theme.bg, dock.solid)

                    Row {
                        id: cells
                        x: Theme.thick; y: Theme.thick

                        // The app index: the brackets of its search line, with the cursor in the accent
                        Cell {
                            visible: dock.index
                            lit: Panels.open === "launcher" && Panels.screen === place.modelData
                            tip: "APP INDEX  /  SUPER+SPACE"
                            onClicked: Panels.toggle("launcher", place.modelData)
                            Ui.Value { anchors.centerIn: parent; textFormat: Text.StyledText; text: "<font color=\"" + Theme.muted + "\">[</font><font color=\"" + Theme.accent + "\">_</font><font color=\"" + Theme.muted + "\">]</font>" }
                        }
                        Repeater {
                            model: dock.apps

                            // One app: its picture (its first two letters when the icon theme has none); a click shows its next window or starts it, a middle click starts another, a right click opens its menu
                            Cell {
                                id: app
                                required property var modelData
                                required property int index
                                readonly property bool running: modelData.windows.length > 0
                                readonly property bool inUse: modelData.windows.some(w => w.activated)
                                readonly property string name: modelData.entry?.name ?? modelData.id
                                readonly property string picture: Quickshell.iconPath(modelData.entry?.icon ?? modelData.id, true)
                                ruled: index === 0 ? dock.index : !modelData.pinned && dock.apps[index - 1].pinned
                                lit: place.menuCell === app && place.menuOpen
                                tip: name.toUpperCase() + (modelData.windows.length > 1 ? "  /  " + modelData.windows.length + " WINDOWS" : "") + "  /  CLICK: " + (running ? "SHOW" : "START") + "  /  RIGHT CLICK: MENU"
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) { place.menuCell = app; if (!place.menuOpen) Panels.toggle("dock", place.modelData) }
                                    else if (mouse.button === Qt.MiddleButton) { if (modelData.entry) dock.launch(modelData.entry) }
                                    else dock.use(modelData)
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: app.picture !== ""
                                    implicitSize: dock.icon
                                    source: app.picture
                                    scale: app.hovered ? dock.grows : 1
                                    Behavior on scale { NumberAnimation { duration: Theme.motion } }
                                }
                                Ui.Value { anchors.centerIn: parent; visible: app.picture === ""; text: app.name.slice(0, 2).toUpperCase(); color: Theme.text2 }
                                // The piece of the dock's top line over this app: light while it runs, the accent while it is in use
                                Rectangle { visible: app.running; y: -Theme.thick; width: parent.width; height: Theme.thick; color: app.inUse ? Theme.accent : Theme.text2 }
                            }
                        }
                        Repeater {
                            model: SystemTray.items

                            // One tray app, the first after a thin line: its picture (a plain square when the icon theme has none); a click does what the app wants (usually shows its window), a right click lists its menu over the cell
                            Cell {
                                id: trayCell
                                required property var modelData
                                required property int index
                                readonly property bool found: !modelData.icon.startsWith("image://icon/") || Quickshell.iconPath(modelData.icon.slice(13).split("?")[0], true) !== ""
                                ruled: index === 0
                                lit: Panels.open === "tray" && Panels.trayItem === modelData
                                tip: (modelData.title || modelData.id || "").toUpperCase() + "  /  TRAY  /  RIGHT CLICK: MENU"
                                onClicked: mouse => {
                                    if (mouse.button !== Qt.RightButton && !modelData.onlyMenu) { modelData.activate(); return }
                                    // Its list (drawn by Menus.qml) is told where the cell is: how far its middle is from the right edge, and how high the dock stands
                                    const edge = dock.side === "left" ? Theme.gap : dock.side === "right" ? place.modelData.width - strip.width - Theme.gap : (place.modelData.width - strip.width) / 2
                                    Panels.edge = Math.round(Math.max(Theme.gap, place.modelData.width - (edge + Theme.thick + trayCell.x + dock.cell / 2) - 190))
                                    Panels.foot = (dock.hides ? strip.height : 0) + Theme.gap
                                    Panels.trayItem = modelData
                                    Panels.toggle("tray", place.modelData)
                                }
                                IconImage { anchors.centerIn: parent; visible: trayCell.found; implicitSize: dock.icon; source: trayCell.found ? trayCell.modelData.icon : "" }
                                Rectangle { anchors.centerIn: parent; visible: !trayCell.found; width: dock.icon; height: dock.icon; color: "transparent"; border { width: Theme.thick; color: Theme.text2 } }
                            }
                        }
                    }
                }
            }

            // A cell's menu, over the cell: it closes on a pick, on a click elsewhere, or shortly after the pointer leaves it
            PanelWindow {
                id: menu
                readonly property var app: place.menuCell?.modelData ?? null
                visible: place.menuOpen
                screen: place.modelData
                anchors { bottom: true; left: true }
                margins {
                    bottom: (dock.hides ? strip.height : 0) + Theme.gap
                    left: {
                        const edge = dock.side === "left" ? Theme.gap : dock.side === "right" ? place.modelData.width - strip.width - Theme.gap : (place.modelData.width - strip.width) / 2
                        const middle = edge + Theme.thick + (place.menuCell?.x ?? 0) + dock.cell / 2
                        return Math.round(Math.max(Theme.gap, Math.min(place.modelData.width - width - Theme.gap, middle - width / 2)))
                    }
                }
                exclusiveZone: 0
                implicitWidth: 260
                implicitHeight: body.height + 2 * Theme.thick
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Overlay

                Ui.Frame { anchors.fill: parent }
                HoverHandler { onHoveredChanged: hovered ? leave.stop() : leave.restart() }
                Timer { id: leave; interval: 600; onTriggered: if (place.menuOpen) Panels.close() }
                Column {
                    id: body
                    x: Theme.thick; y: Theme.thick
                    width: parent.width - 2 * Theme.thick

                    Ui.Head {
                        title: "DOCK / " + (place.menuCell?.name ?? "").toUpperCase()
                        note: !menu.app || menu.app.windows.length === 0 ? "NOT RUNNING" : menu.app.windows.length === 1 ? "1 WINDOW" : menu.app.windows.length + " WINDOWS"
                    }
                    Ui.Line { width: parent.width }
                    Repeater {
                        model: menu.app ? dock.rows(menu.app) : []

                        Rectangle {
                            id: row
                            required property var modelData
                            width: body.width; height: Theme.row
                            color: over.hovered ? Theme.surface : "transparent"
                            // The square stands only before the pin row: filled while the app is pinned
                            Rectangle {
                                visible: row.modelData.active !== undefined
                                x: 16; anchors.verticalCenter: parent.verticalCenter
                                width: 8; height: 8
                                color: row.modelData.active ? Theme.accent : "transparent"
                                border { width: Theme.thin; color: row.modelData.active ? Theme.accent : Theme.border }
                            }
                            Ui.Value {
                                anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                                elide: Text.ElideRight
                                text: row.modelData.label
                            }
                            HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { Panels.close(); row.modelData.pick() } }
                        }
                    }
                    Item { width: 1; height: 6 }
                }
            }
        }
    }
}
