import QtQuick
import Quickshell
import Quickshell.Io

// The shell: a bar on every monitor, and the panels the bar's cells and mango's keys open
// Theme.qml: colours, sizes, fonts.  Sys.qml: live numbers.  Notify.qml: the notifications.  Panels.qml: which panel is open.  Ui.qml: building blocks.  The rest is one file per thing on screen.
Scope {
    id: root

    Variants { model: Quickshell.screens; Bar {} }

    // A click anywhere below the bar closes the open panel; the bar itself stays clickable
    PanelWindow {
        visible: Panels.open !== ""
        screen: Panels.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: Panels.close() }
    }

    Launcher {}
    Clipboard {}
    Dashboard {}
    Power {}
    Displays {}
    Calendar {}
    Battery {}
    Temperature {}
    Media {}
    Menus {}
    Dock {}
    Notifications {}
    Auth {}
    WallpaperPicker { id: picker }

    // Keys in mango's bind.conf reach the shell here: Super+Space the launcher, Super+V the clipboard history, Super+D the dashboard, Super+Esc the power panel, Super+P the displays panel, Super+W the wallpaper picker, Ctrl+Alt+\ the calendar with the notifications (each opens on the monitor mango has focused), Ctrl+Alt+Backspace clears the notifications, Super+Alt+N switches the night light, and Super+Shift+R reloads the shell (it reads its files again)
    IpcHandler {
        target: "bar"
        function launcher(): void { Panels.focused(monitor => Panels.toggle("launcher", monitor)) }
        function clipboard(): void { Panels.focused(monitor => Panels.toggle("clipboard", monitor)) }
        function dashboard(): void { Panels.focused(monitor => Panels.toggle("dashboard", monitor)) }
        function power(): void { Panels.focused(monitor => Panels.toggle("power", monitor)) }
        function displays(): void { Panels.focused(monitor => Panels.toggle("displays", monitor)) }
        function media(): void { Panels.focused(monitor => Panels.toggle("media", monitor)) }
        function notifications(): void { Panels.focused(monitor => Panels.toggle("calendar", monitor)) }
        function wallpaper(): void { Panels.focused(monitor => { Panels.close(); picker.screen = monitor; picker.open = !picker.open }) }
        function clear(): void { Notify.clear() }
        function night(): void { Sys.toggleNight() }
        function reload(): void { Quickshell.reload(false) }
    }
}
