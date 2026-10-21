import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// The wallpaper picker: one folder's pictures as a row of slanted cards across the middle of the screen, the marked one large and the rest as slices beside it
Scope {
    id: root

    // Set by shell.qml: the monitor to open on, and whether the picker is showing
    property var screen: null
    property bool open: false

    readonly property string home: Quickshell.env("HOME")
    // Small copies of the pictures are kept here, because decoding a large wallpaper takes up to a second
    readonly property string thumbDir: home + "/.cache/wallpaper/thumbs"
    readonly property url topFolder: "file://" + home + "/Pictures"
    readonly property int thumbWidth: 640
    // The folder on show; kept while the bar runs, so the picker reopens where it was left
    property url folder: ""
    // The wallpaper in use, by the path it was picked from (~/.config/mango/wallpaper-source; current-wallpaper points to a copy kept in the config)
    property string current: ""
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", thumbDir])

    // Measures of the row: the marked card, the others before they shrink with distance, and how far a card leans per pixel of height
    readonly property int cardHeight: 300
    readonly property int bigWidth: 500
    readonly property int sliceWidth: 120
    readonly property real slant: -0.3

    // The same script as before sets the wallpaper and recolours the desktop from it
    function apply(path) {
        Quickshell.execDetached([home + "/.config/mango/wallpaper.sh", path])
        open = false
    }

    // Each opening first finds the wallpaper in use, so the row can start on it
    property bool located: false
    onOpenChanged: if (open) { located = false; locate.running = true }
    Process {
        id: locate
        command: ["sh", "-c", "f=$(cat \"$HOME/.config/mango/wallpaper-source\" 2>/dev/null); [ -f \"$f\" ] && echo \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: {
                root.current = text.trim()
                if (String(root.folder) === "")
                    root.folder = root.current !== "" ? "file://" + root.current.replace(/\/[^\/]*$/, "") : root.topFolder
                root.located = true
            }
        }
    }

    LazyLoader {
        active: root.open && root.located

        // The window covers the whole monitor so that a click anywhere outside the cards closes the picker
        PanelWindow {
            screen: root.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:wallpapers"

            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            // Left and Right or the wheel move along the row, Page Up and Down by ten, Home and End to the ends; Enter or a click on the marked card applies it; folders are cards too (Enter goes in, Backspace back up); Esc closes
            Item {
                id: view
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                // 12, a label box, 16, the cards, 16, a label box, 12
                height: root.cardHeight + 116
                focus: true
                Component.onCompleted: forceActiveFocus()

                readonly property bool atTop: String(root.folder) === String(root.topFolder)
                function goUp() { if (!atTop) root.folder = pictures.parentFolder }
                function enterOrApply(cell) {
                    if (cell.fileIsDir) root.folder = cell.fileUrl
                    else root.apply(cell.filePath)
                }
                function step(count) {
                    row.currentIndex = Math.max(0, Math.min(row.count - 1, row.currentIndex + count))
                }

                Keys.onEscapePressed: root.open = false
                Keys.onLeftPressed: step(-1)
                Keys.onRightPressed: step(1)
                Keys.onReturnPressed: if (row.currentItem) enterOrApply(row.currentItem)
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Backspace: goUp(); break
                    case Qt.Key_PageUp: step(-10); break
                    case Qt.Key_PageDown: step(10); break
                    case Qt.Key_Home: step(-row.count); break
                    case Qt.Key_End: step(row.count); break
                    default: return
                    }
                    event.accepted = true
                }

                // A small copy is named after the file's path and modification time, so a replaced wallpaper gets a new one
                function thumbName(path, modified) {
                    return Qt.md5(path) + "-" + Math.floor(modified.getTime() / 1000) + ".jpg"
                }

                // Names of the small copies that exist; null until that folder has been read (the row waits for it)
                property var cached: null
                FolderListModel {
                    id: thumbs
                    folder: "file://" + root.thumbDir
                    nameFilters: ["*.jpg"]
                    showDirs: false
                    onStatusChanged: {
                        if (status !== FolderListModel.Ready || view.cached !== null) return
                        const names = {}
                        for (let i = 0; i < count; i++) names[get(i, "fileName")] = true
                        view.cached = names
                    }
                }
                FolderListModel {
                    id: pictures
                    folder: root.folder
                    nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
                    showDirs: true
                    showDirsFirst: true
                    showDotAndDotDot: false
                }

                // Once a folder has been read: start on the wallpaper in use if it is here, and queue the pictures that have no small copy yet, nearest first
                readonly property bool ready: cached !== null && pictures.status === FolderListModel.Ready
                property url shownFolder: ""
                onReadyChanged: enter()
                Connections {
                    target: pictures
                    function onStatusChanged() { view.enter() }
                }
                function enter() {
                    if (!ready || String(shownFolder) === String(pictures.folder)) return
                    shownFolder = pictures.folder
                    const at = Math.max(0, root.current !== "" ? pictures.indexOf("file://" + root.current) : -1)
                    // Jump to the starting card without sliding there from the first one
                    row.highlightMoveDuration = 0
                    Qt.callLater(() => {
                        row.positionViewAtIndex(at, ListView.Center)
                        row.currentIndex = at
                        row.highlightMoveDuration = 260
                    })

                    // The cards on show make their own copy, so those are left out
                    const jobs = []
                    for (let i = 0; i < pictures.count; i++) {
                        if (pictures.get(i, "fileIsDir") || Math.abs(i - at) <= 8) continue
                        const path = pictures.get(i, "filePath")
                        const name = thumbName(path, pictures.get(i, "fileModified"))
                        if (!cached[name]) jobs.push({ url: pictures.get(i, "fileUrl"), name: name, far: Math.abs(i - at) })
                    }
                    jobs.sort((a, b) => a.far - b.far)
                    queue = jobs
                    queued = jobs.length
                }

                // Missing small copies are made two at a time, out of sight, while the picker is open
                property var queue: []
                property int queued: 0
                function nextJob() { return queue.length > 0 ? queue.shift() : null }
                Item {
                    width: 1; height: 1
                    clip: true

                    Repeater {
                        model: 2
                        Image {
                            id: copier
                            property var job: null
                            function take() {
                                job = view.nextJob()
                                source = job ? job.url : ""
                            }
                            Connections {
                                target: view
                                function onQueuedChanged() { if (!copier.job) copier.take() }
                            }
                            width: root.thumbWidth
                            height: implicitWidth > 0 ? Math.round(root.thumbWidth * implicitHeight / implicitWidth) : 1
                            sourceSize.width: root.thumbWidth
                            asynchronous: true
                            cache: false
                            onStatusChanged: {
                                if (!job) return
                                if (status === Image.Error) { take(); return }
                                if (status !== Image.Ready) return
                                const done = job
                                grabToImage(result => {
                                    result.saveToFile(root.thumbDir + "/" + done.name)
                                    view.cached[done.name] = true
                                    copier.take()
                                }, Qt.size(width, height))
                            }
                        }
                    }
                }

                // A label box drawn like the bar's menus; the two sit on the cards' lean, the upper one right of the middle and the lower one left
                component Plate: Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: root.slant * (y + height / 2 - parent.height / 2)
                    height: 30
                    color: Theme.bg
                    border { width: 2; color: Theme.accent }
                    // Clicks on a label box stay with it and do not close the picker
                    MouseArea { anchors.fill: parent }
                }

                // Where we are: the folder, and which picture of how many
                Plate {
                    y: 12
                    width: where.width + 28

                    Row {
                        id: where
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !view.atTop
                            text: String.fromCodePoint(0xF004D)
                            color: Theme.accent
                            font: Theme.valueFont
                            MouseArea { anchors { fill: parent; margins: -6 } cursorShape: Qt.PointingHandCursor; onClicked: view.goUp() }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: decodeURIComponent(String(root.folder)).replace("file://" + root.home, "~") + (row.count > 0 ? "  /  " + (row.currentIndex + 1) + " OF " + row.count : "")
                            color: Theme.text
                            font: Theme.valueFont
                        }
                    }
                }

                // The row of cards; the marked card stays in the middle
                ListView {
                    id: row
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: root.cardHeight
                    orientation: ListView.Horizontal
                    model: view.ready ? pictures : null
                    cacheBuffer: 600
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - root.bigWidth) / 2
                    preferredHighlightEnd: (width + root.bigWidth) / 2
                    highlightMoveDuration: 260
                    header: Item { width: (row.width - root.bigWidth) / 2 }
                    footer: Item { width: (row.width - root.bigWidth) / 2 }

                    delegate: Item {
                        id: cell
                        required property string filePath
                        required property url fileUrl
                        required property string fileName
                        required property bool fileIsDir
                        required property var fileModified
                        required property int index

                        readonly property bool marked: ListView.isCurrentItem
                        readonly property int far: Math.abs(index - row.currentIndex)
                        // Cards get smaller the further they are from the marked one
                        readonly property real shrink: Math.max(0.6, Math.pow(0.9, Math.max(0, far - 1)))
                        // The small copy that existed when this card was made (fixed then, so a picture already on show is not loaded again)
                        property string thumb: ""
                        Component.onCompleted: {
                            const name = view.thumbName(filePath, fileModified)
                            if (!fileIsDir && view.cached[name]) thumb = name
                        }

                        width: marked ? root.bigWidth : root.sliceWidth * shrink
                        height: marked ? root.cardHeight : root.cardHeight * 0.84 * shrink
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        z: marked ? 100 : 50 - far
                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        // The slanted frame: leaning is a shear, kept centred
                        Item {
                            id: frame
                            anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                            transform: Matrix4x4 {
                                matrix: Qt.matrix4x4(1, root.slant, 0, -root.slant * frame.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                            }

                            ClippingRectangle {
                                anchors.fill: parent
                                color: Theme.surface
                                border.width: cell.marked ? 2 : cardMouse.containsMouse ? 1 : 0
                                border.color: Theme.accent

                                // A folder: its icon, and its name while marked, leaned back so they stand upright
                                Column {
                                    anchors.centerIn: parent
                                    visible: cell.fileIsDir
                                    spacing: 6
                                    transform: Matrix4x4 {
                                        matrix: Qt.matrix4x4(1, -root.slant, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: String.fromCodePoint(0xF024B)
                                        color: Theme.accent
                                        font { family: Theme.family; pixelSize: 44 }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: cell.marked
                                        text: cell.fileName
                                        color: Theme.text
                                        font: Theme.valueFont
                                    }
                                }
                                // A picture: leaned back the other way so it stands upright inside the slanted frame, and wide enough to still fill it
                                Image {
                                    id: picture
                                    visible: !cell.fileIsDir
                                    anchors.centerIn: parent
                                    width: parent.width + Math.abs(root.slant) * parent.height + 2
                                    height: parent.height
                                    transform: Matrix4x4 {
                                        matrix: Qt.matrix4x4(1, -root.slant, 0, root.slant * picture.height / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                    }
                                    source: cell.fileIsDir ? "" : cell.thumb !== "" ? "file://" + root.thumbDir + "/" + cell.thumb : cell.fileUrl
                                    sourceSize.width: root.thumbWidth
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 160 } }

                                    // Shown from the original: keep a small copy for next time
                                    property bool saved: false
                                    onStatusChanged: {
                                        if (saved || cell.fileIsDir || cell.thumb !== "" || status !== Image.Ready) return
                                        saved = true
                                        saver.name = view.thumbName(cell.filePath, cell.fileModified)
                                        saver.source = cell.fileUrl
                                    }
                                }
                            }
                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (cell.marked) view.enterOrApply(cell)
                                    else row.currentIndex = cell.index
                                }
                            }
                        }

                        // The copy is taken from an unslanted picture of its own (already decoded, so this costs no second read)
                        Item {
                            width: 1; height: 1
                            clip: true
                            Image {
                                id: saver
                                property string name: ""
                                width: root.thumbWidth
                                height: implicitWidth > 0 ? Math.round(root.thumbWidth * implicitHeight / implicitWidth) : 1
                                sourceSize.width: root.thumbWidth
                                asynchronous: true
                                onStatusChanged: {
                                    if (status !== Image.Ready || name === "") return
                                    const file = name
                                    grabToImage(result => {
                                        result.saveToFile(root.thumbDir + "/" + file)
                                        view.cached[file] = true
                                    }, Qt.size(width, height))
                                }
                            }
                        }
                    }
                }
                // The wheel moves along the row, a card per notch
                MouseArea {
                    anchors.fill: row
                    acceptedButtons: Qt.NoButton
                    onWheel: wheel => view.step(wheel.angleDelta.y > 0 || wheel.angleDelta.x > 0 ? -1 : 1)
                }

                // The marked picture's name, and whether it is the one in use
                Plate {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    visible: caption.text !== ""
                    width: caption.width + 28

                    Text {
                        id: caption
                        anchors.centerIn: parent
                        text: row.currentItem ? row.currentItem.fileName + (row.currentItem.filePath === root.current ? "  /  IN USE" : "") : ""
                        color: Theme.text
                        font: Theme.valueFont
                    }
                }
            }
        }
    }
}
