import QtQuick

// Building blocks for the bar and every panel; other files write them as Ui.Value, Ui.Label and so on
Item {
    // A value: the main text
    component Value: Text { color: Theme.text; font: Theme.valueFont }
    // A label: small grey capitals that name the value beside them
    component Label: Text { color: Theme.text2; font: Theme.labelFont }
    // A thin divider: give it a width to lie flat or a height to stand
    component Line: Rectangle { implicitWidth: Theme.thin; implicitHeight: Theme.thin; color: Theme.border }
    // The body of a panel: dark, square and framed; a panel that holds the keyboard gets the accent frame of a focused window
    component Frame: Rectangle {
        property bool focused: false
        color: Theme.bg
        border { width: Theme.thick; color: focused ? Theme.accent : Theme.strong }
    }
    // The strip at the top of a panel: its name on an accent plate, a short Japanese word, three tape stripes (accent, orange, second colour), and a short note at the right
    component Head: Rectangle {
        id: head
        property string title
        property string note
        // A short Japanese word for the panel, drawn small after its name
        property string kana
        width: parent.width; height: 30
        color: Theme.bg2
        Rectangle {
            id: plate
            width: headName.width + 32; height: parent.height
            color: Theme.accent
            Label { id: headName; x: 16; anchors.verticalCenter: parent.verticalCenter; text: head.title; color: Theme.accentInk }
        }
        Label { id: headKana; visible: head.kana !== "" && x + implicitWidth + 12 <= headNote.x; x: plate.width + 12; anchors.verticalCenter: parent.verticalCenter; text: head.kana; color: Theme.accent2; font: Theme.kanaFont }
        Column {
            x: (headKana.visible ? headKana.x + headKana.width : plate.width) + 14
            width: Math.max(0, headNote.x - x - 14)
            visible: width >= 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: [Theme.accent, Theme.warn, Theme.accent2]; Rectangle { required property var modelData; width: parent.width; height: 2; color: modelData } }
        }
        Label { id: headNote; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: head.note; color: Theme.text2 }
    }
    // The strip at the foot of a panel: which keys do what, each key drawn as a key cap
    component Foot: Rectangle {
        id: foot
        property string keys
        property color tint: Theme.muted
        width: parent.width; height: Theme.row
        color: Theme.bg2
        Row {
            x: 16; height: parent.height
            spacing: 14
            Repeater {
                model: foot.keys.split("  /  ")
                Row {
                    id: pair
                    required property string modelData
                    readonly property int cut: modelData.indexOf(": ")
                    height: parent.height
                    spacing: 6
                    Rectangle {
                        visible: pair.cut > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: cap.width + 10; height: 18
                        color: Theme.surface2
                        border { width: Theme.thin; color: Theme.strong }
                        Label { id: cap; anchors.centerIn: parent; text: pair.modelData.slice(0, Math.max(0, pair.cut)); color: Theme.text }
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: pair.cut > 0 ? pair.modelData.slice(pair.cut + 2) : pair.modelData; color: foot.tint }
                }
            }
        }
    }
    // The numbered title of a section inside a panel
    component Section: Item {
        property alias title: name.text
        width: parent.width; height: Theme.row
        Label { id: name; x: 16; anchors.verticalCenter: parent.verticalCenter; color: Theme.muted }
    }
    // One fact: its label at the left and its value at the right
    component Pair: Item {
        id: pair
        property string label
        property string value
        property color tint: Theme.text
        width: parent.width; height: 26
        Label { id: what; x: 16; anchors.verticalCenter: parent.verticalCenter; text: pair.label }
        Value {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            width: Math.min(implicitWidth, parent.width - what.width - 48)
            elide: Text.ElideRight
            text: pair.value; color: pair.tint
        }
    }
    // One on-off switch row: the square is filled while it is on, a short note says what it does, and a click flips it
    component Switch: Rectangle {
        id: flip
        property string label
        property string note
        property bool on: false
        signal flipped()
        width: parent.width; height: Theme.row
        color: over.hovered ? Theme.surface : "transparent"
        Rectangle {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8
            color: flip.on ? Theme.accent : "transparent"
            border { width: Theme.thin; color: flip.on ? Theme.accent : Theme.border }
        }
        Value { id: name; x: 36; anchors.verticalCenter: parent.verticalCenter; text: flip.label; color: flip.on ? Theme.accent : Theme.text }
        Label { anchors { left: name.right; leftMargin: 12; right: state.left; rightMargin: 12; verticalCenter: parent.verticalCenter } elide: Text.ElideRight; text: flip.note; color: Theme.muted }
        Label { id: state; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: flip.on ? "ON" : "OFF"; color: flip.on ? Theme.accent : Theme.text2 }
        HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: flip.flipped() }
    }
}
