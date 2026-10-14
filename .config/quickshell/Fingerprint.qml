import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The dashboard's fingerprint section: the ten fingers as boxes, filled for the ones the reader knows. A click on an empty box adds that finger, two clicks on a filled one remove it. Both ask for the password in the system's own dialog, so the dashboard closes first; a card at the top left then counts the touches
Column {
    id: fingers
    visible: reader
    bottomPadding: 6

    readonly property string user: Quickshell.env("USER") ?? ""
    // The boxes in the order of two hands lying side by side; the names are fprintd's
    readonly property var hands: [
        ["left-little-finger", "left-ring-finger", "left-middle-finger", "left-index-finger", "left-thumb"],
        ["right-thumb", "right-index-finger", "right-middle-finger", "right-ring-finger", "right-little-finger"]
    ]
    function label(finger) { return finger.replace("-finger", "").replace("-", " ").toUpperCase() }

    // Which fingers the reader knows and how many touches a new one takes, asked when the bar starts, each time the dashboard opens and after every change
    property bool reader: false
    property var enrolled: []
    property int stages: 0
    function check() { list.running = true }
    Component.onCompleted: check()
    Process {
        id: list
        command: ["sh", "-c", 'fprintd-list "$1"; busctl get-property net.reactivated.Fprint /net/reactivated/Fprint/Device/0 net.reactivated.Fprint.Device num-enroll-stages', "sh", fingers.user]
        stdout: StdioCollector {
            onStreamFinished: {
                fingers.reader = /Using device/.test(text)
                fingers.enrolled = (text.match(/#\d+: \S+/g) ?? []).map(found => found.replace(/^#\d+: /, ""))
                fingers.stages = Number(text.match(/^i (\d+)$/m)?.[1] ?? 0)
                if (fingers.removed) Sys.notify("Fingerprint", fingers.label(fingers.removed) + (fingers.enrolled.includes(fingers.removed) ? " was not removed." : " removed."))
                fingers.removed = ""
            }
        }
    }

    // A click on a box: an empty one starts adding; a filled one is armed by the first click and removed by a second within 3 seconds
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: fingers.armed = "" }
    function pick(finger) {
        if (adding || removing) return
        if (!enrolled.includes(finger)) { armed = ""; add(finger) }
        else if (armed !== finger) { armed = finger; disarm.restart() }
        else { armed = ""; removing = finger; Panels.close(); remove.running = true }
    }

    // Removing: fprintd-delete, then the list is asked again and says whether the finger is gone
    property string removing: ""
    property string removed: ""
    Process {
        id: remove
        command: ["fprintd-delete", fingers.user, "-f", fingers.removing]
        onExited: { fingers.removed = fingers.removing; fingers.removing = ""; fingers.check() }
    }

    // Adding: fprintd-enroll writes one line per touch; the card shows the count and what to do next, and stays a moment after the end
    property string adding: ""
    property int stage: 0
    property string status: ""
    property bool done: false
    property bool ended: false
    readonly property var words: ({
        "enroll-retry-scan": "NOT READ. TOUCH AGAIN",
        "enroll-swipe-too-short": "TOO SHORT. TOUCH AGAIN",
        "enroll-finger-not-centered": "PUT YOUR FINGER ON THE MIDDLE OF THE READER",
        "enroll-remove-and-retry": "LIFT YOUR FINGER, THEN TOUCH AGAIN",
        "enroll-duplicate": "THE READER ALREADY KNOWS THIS FINGER",
        "enroll-data-full": "THE READER HAS NO ROOM FOR ANOTHER FINGER",
        "enroll-disconnected": "THE READER WENT AWAY"
    })
    function add(finger) {
        adding = finger; stage = 0; done = false; ended = false
        status = "PASSWORD FIRST, THEN TOUCH THE READER"
        Panels.close()
        enroll.running = true
    }
    function cancel() { adding = ""; enroll.running = false }
    function hear(line) {
        const result = line.match(/^Enroll result: (\S+)/)?.[1]
        if (result === "enroll-stage-passed") { stage += 1; status = "LIFT YOUR FINGER, THEN TOUCH AGAIN" }
        else if (result === "enroll-completed") { stage = Math.max(stage, stages); done = true; status = "ADDED" }
        else if (result) status = words[result] ?? "FAILED"
        else if (/AlreadyInUse|already claimed/i.test(line)) status = "THE READER IS BUSY. TRY AGAIN IN A MOMENT"
        else if (/PermissionDenied|Not Authorized/i.test(line)) status = "NOT ADDED: THE PASSWORD WAS NOT GIVEN"
        else if (/failed/i.test(line)) status = "FAILED"
    }
    Process {
        id: enroll
        command: ["fprintd-enroll", "-f", fingers.adding]
        stdout: SplitParser { onRead: line => fingers.hear(line) }
        stderr: SplitParser { onRead: line => fingers.hear(line) }
        onExited: { fingers.check(); if (fingers.adding) { fingers.ended = true; hide.restart() } }
    }
    Timer { id: hide; interval: fingers.done ? 1500 : 4000; onTriggered: fingers.adding = "" }

    Ui.Section {
        title: "06 / FINGERPRINT"
        Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: fingers.enrolled.length + " ENROLLED"; color: Theme.muted }
    }
    Row {
        x: 16
        spacing: 24
        Repeater {
            model: fingers.hands

            Column {
                id: hand
                required property var modelData
                required property int index
                spacing: 6
                Ui.Label { text: hand.index === 0 ? "LEFT HAND" : "RIGHT HAND" }
                Row {
                    spacing: 6
                    Repeater {
                        model: hand.modelData

                        // One finger: filled when the reader knows it, red while it waits for the second click that removes it
                        Rectangle {
                            id: box
                            required property string modelData
                            readonly property bool known: fingers.enrolled.includes(modelData)
                            readonly property bool armed: fingers.armed === modelData
                            width: (fingers.width - 104) / 10; height: 30
                            color: armed ? Theme.error : known ? Theme.accent : over.hovered ? Theme.surface : "transparent"
                            border { width: Theme.thin; color: armed ? Theme.error : known ? Theme.accent : Theme.border }
                            Ui.Label { anchors.centerIn: parent; text: box.modelData.split("-")[1].toUpperCase(); color: box.armed ? Theme.bg : box.known ? Theme.accentInk : Theme.text2 }
                            HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: fingers.pick(box.modelData) }
                        }
                    }
                }
            }
        }
    }
    Item {
        width: parent.width; height: Theme.row
        Ui.Label {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: fingers.armed ? "CLICK " + fingers.label(fingers.armed) + " AGAIN TO REMOVE IT" : "CLICK AN EMPTY BOX TO ADD THAT FINGER, A FILLED ONE TO REMOVE IT  /  BOTH ASK FOR YOUR PASSWORD"
            color: fingers.armed ? Theme.error : Theme.muted
        }
    }

    // The card for a finger being added: top left under the bar, clear of the password dialog in the middle of the screen; it takes no keys, a click on its last line cancels
    PanelWindow {
        visible: fingers.adding !== ""
        screen: Panels.screen
        anchors { top: true; left: true }
        margins { top: Theme.gap; left: Theme.gap }
        exclusiveZone: 0
        implicitWidth: 380
        implicitHeight: card.height + 2 * Theme.thick
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        Ui.Frame { anchors.fill: parent }
        Column {
            id: card
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: "FINGERPRINT / ADD"; kana: "指紋"; note: fingers.label(fingers.adding) }
            Ui.Line { width: parent.width }
            Item {
                width: parent.width; height: 72
                Ui.Value { x: 16; anchors.verticalCenter: parent.verticalCenter; text: fingers.stages > 0 ? fingers.stage + " / " + fingers.stages : "" + fingers.stage; font: Theme.displayFont; color: fingers.done ? Theme.accent : Theme.text }
                Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: "TOUCHES" }
            }
            Rectangle {
                x: 16; width: parent.width - 32; height: 4
                color: Theme.surface2
                Rectangle { width: fingers.stages > 0 ? Math.round(parent.width * Math.min(1, fingers.stage / fingers.stages)) : 0; height: parent.height; color: Theme.accent }
            }
            Item {
                width: parent.width; height: 40
                Ui.Label { x: 16; width: parent.width - 32; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; text: fingers.status; color: fingers.ended && !fingers.done ? Theme.error : Theme.text }
            }
            Ui.Line { visible: !fingers.ended; width: parent.width }
            Rectangle {
                visible: !fingers.ended
                width: parent.width; height: Theme.row
                color: stop.hovered ? Theme.surface : Theme.bg2
                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "CLICK HERE TO CANCEL"; color: Theme.muted }
                HoverHandler { id: stop; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: fingers.cancel() }
            }
        }
    }
}
