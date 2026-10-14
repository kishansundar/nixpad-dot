import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland

// The password dialog for admin actions (adding a fingerprint, unlocking 1Password, anything else that asks polkit): the bar is the session's polkit agent and draws the question in the middle of the focused monitor. It shows what PAM sends, so it asks for a finger first wherever PAM does
PanelWindow {
    id: auth

    PolkitAgent { id: agent }
    readonly property var flow: agent.flow
    // A request closes whatever panel is open, and shows once mmsg has named the focused monitor
    property bool placed: false
    Connections {
        target: agent
        function onIsActiveChanged() {
            auth.placed = false
            if (agent.isActive) { Panels.close(); Panels.focused(monitor => { auth.screen = monitor; auth.placed = true }) }
        }
    }
    visible: agent.isActive && placed
    exclusiveZone: 0
    implicitWidth: 520
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    // Typing is wanted only while PAM waits for an answer; before that it may be waiting for a finger, after it for the check
    readonly property bool wanted: flow?.isResponseRequired ?? false
    // The keys go to the password line while it shows, to the panel otherwise; a typed password never stays in the line once its question is gone
    function aim() { secret.clear(); (wanted ? secret : keys).forceActiveFocus() }
    onVisibleChanged: aim()
    onWantedChanged: aim()

    Ui.Frame { anchors.fill: parent; focused: true }
    // Esc refuses the request, from the password line too
    Item {
        id: keys
        anchors.fill: parent
        Keys.onEscapePressed: auth.flow?.cancelAuthenticationRequest()

        Column {
            id: body
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: "SYSTEM / PASSWORD"; kana: "パスワード"; note: auth.flow?.actionId ?? "" }
            Ui.Line { width: parent.width }
            Item {
                width: parent.width; height: what.height + 28
                Ui.Value { id: what; x: 16; y: 14; width: parent.width - 32; wrapMode: Text.WordWrap; text: auth.flow?.message ?? "" }
            }
            // What PAM says on the side: to put a finger on the reader, or why the last try did not work
            Item {
                visible: aside.text !== ""
                width: parent.width; height: aside.height + 14
                Ui.Label {
                    id: aside
                    x: 16; width: parent.width - 32
                    wrapMode: Text.WordWrap
                    text: (auth.flow?.supplementaryMessage || (auth.flow?.failed ? "That did not work. Try again." : "")).toUpperCase()
                    color: auth.flow?.supplementaryIsError || (auth.flow?.failed && !auth.flow?.supplementaryMessage) ? Theme.error : Theme.text2
                }
            }
            Ui.Line { width: parent.width }
            Item {
                width: parent.width; height: 44
                Ui.Label { id: asked; x: 16; anchors.verticalCenter: parent.verticalCenter; text: auth.wanted ? (auth.flow?.inputPrompt ?? "").trim().toUpperCase() : "WAITING..."; color: auth.wanted ? Theme.text2 : Theme.muted }
                TextInput {
                    id: secret
                    visible: auth.wanted
                    anchors { left: asked.right; right: parent.right; leftMargin: 10; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: Theme.text
                    font: Theme.valueFont
                    echoMode: auth.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "*"
                    cursorDelegate: Rectangle { width: Theme.thick; color: Theme.accent }
                    onAccepted: { const typed = text; clear(); auth.flow.submit(typed) }
                }
            }
            Ui.Line { width: parent.width }
            // The foot also has a CANCEL to click, so the pointer can always close the dialog
            Ui.Foot {
                keys: auth.wanted ? "ENTER: SEND  /  ESC: CANCEL" : "ESC: CANCEL"
                Ui.Label {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: "CANCEL"
                    color: quit.hovered ? Theme.text : Theme.text2
                    HoverHandler { id: quit; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: auth.flow?.cancelAuthenticationRequest() }
                }
            }
        }
    }
}
