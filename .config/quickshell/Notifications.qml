import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications

// Notifications on screen: pop-ups under the right end of the bar; everything not yet dismissed is listed in the calendar panel (Calendar.qml), which draws each one with the Note below
Scope {
    id: root

    // One notification, drawn the same in a pop-up and in the calendar panel's list: the urgency bar at the left (the accent, grey for low, red for critical), its picture, the app and how long ago, the title, the text, and the app's own buttons
    // A click goes to the app (its own action first, then its window is shown), a right click or the X dismisses it
    component Note: Rectangle {
        id: card
        property var note
        property real now: Date.now()
        readonly property bool hovered: over.hovered
        readonly property string picture: Notify.picture(note)
        readonly property color mark: note.urgency === NotificationUrgency.Critical ? Theme.error : note.urgency === NotificationUrgency.Low ? Theme.strong : Theme.accent
        implicitHeight: words.height + 20
        color: hovered ? Theme.surface : "transparent"

        HoverHandler { id: over }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => { if (mouse.button === Qt.RightButton) Notify.dismiss(card.note); else Notify.open(card.note) }
        }
        Rectangle { width: 3; height: parent.height; color: card.mark }
        IconImage { id: image; visible: card.picture !== ""; x: 16; y: 12; implicitSize: 32; source: card.picture }
        Column {
            id: words
            anchors { left: parent.left; leftMargin: image.visible ? 60 : 16; right: parent.right; rightMargin: 16 }
            y: 10
            spacing: 4

            Item {
                width: parent.width; height: who.height
                Ui.Label { id: who; width: parent.width - when.width - 40; elide: Text.ElideRight; text: (card.note.appName || "NOTICE").toUpperCase() }
                Ui.Label { id: when; anchors { right: parent.right; rightMargin: 24 } text: Notify.age(card.note, card.now); color: Theme.muted }
                Ui.Label {
                    anchors.right: parent.right
                    text: "X"; color: shut.containsMouse ? Theme.accent : Theme.muted
                    MouseArea { id: shut; anchors { fill: parent; margins: -6 } hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notify.dismiss(card.note) }
                }
            }
            Ui.Value { width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText; text: card.note.summary.toUpperCase() }
            Ui.Value {
                width: parent.width
                visible: text !== ""
                wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight
                textFormat: Text.PlainText
                text: card.note.body.replace(/<[^>]*>/g, "")
                color: Theme.text2
            }
            Row {
                visible: Notify.buttons(card.note).length > 0
                topPadding: 4
                spacing: 8
                Repeater {
                    model: Notify.buttons(card.note)
                    Rectangle {
                        id: button
                        required property var modelData
                        width: caption.implicitWidth + 24; height: Theme.row
                        color: press.containsMouse ? Theme.surface2 : Theme.bg2
                        border { width: Theme.thin; color: press.containsMouse ? Theme.accent : Theme.border }
                        Ui.Label { id: caption; anchors.centerIn: parent; text: button.modelData.text.toUpperCase(); color: Theme.text }
                        MouseArea { id: press; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notify.act(card.note, button.modelData) }
                    }
                }
            }
        }
    }

    // --- Pop-ups: framed cards in a column, on the monitor that was focused when the newest arrived; hidden while the calendar panel is open ---

    PanelWindow {
        visible: Notify.popups.length > 0 && Panels.open !== "calendar"
        screen: Notify.screen
        anchors { top: true; right: true }
        margins { top: Theme.gap; right: Theme.gap }
        exclusiveZone: 0
        implicitWidth: 380
        implicitHeight: stack.height
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay

        Column {
            id: stack
            width: parent.width
            spacing: Theme.gap

            Repeater {
                model: Notify.popups

                Rectangle {
                    id: popup
                    required property var modelData
                    width: stack.width; height: card.implicitHeight + 2 * Theme.thick
                    color: Theme.bg
                    border { width: Theme.thick; color: modelData.urgency === NotificationUrgency.Critical ? Theme.error : Theme.strong }
                    Note { id: card; x: Theme.thick; y: Theme.thick; width: parent.width - 2 * Theme.thick; height: implicitHeight; note: popup.modelData }
                    // It leaves by itself when its time since it arrived is up (see Notify.lasts; the cards are drawn anew whenever the list changes, so the time left is worked out from the arrival), not while the pointer is on it; the notification stays in the centre
                    Timer { interval: Math.max(1, (Notify.arrived[popup.modelData.id] ?? Date.now()) + Notify.lasts(popup.modelData) - Date.now()); running: Notify.lasts(popup.modelData) > 0 && !card.hovered; onTriggered: Notify.hide(popup.modelData) }
                }
            }
        }
    }
}
