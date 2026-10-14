pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which panel is open ("" for none) and on which monitor; only one shows at a time
Singleton {
    id: panels

    property string open: ""
    property var screen: null
    // The tray icon whose menu the "tray" panel lists
    property var trayItem: null
    // How far the cell that opened the media panel ends from the monitor's right edge (the panel hangs under it), or how far the tray list stands from that edge; and how high above the bottom edge the tray list sits, over the dock
    property real edge: 0
    property real foot: 0

    // Opens a panel, or closes it when it is already open on that monitor
    function toggle(name, monitor) {
        open = open === name && screen === monitor ? "" : name
        screen = monitor
    }
    function close() { open = "" }

    // The monitor mango has focused, asked from mmsg; the answer comes a moment later, so the caller hands over what to do with it (the first monitor if mmsg gives no usable answer)
    property var waiting: []
    function focused(then) { waiting = waiting.concat([then]); ask.running = true }
    Process {
        id: ask
        command: ["mmsg", "get", "all-monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = ""
                try { name = JSON.parse(text).monitors.find(m => m.active)?.name ?? "" } catch (e) {}
                const monitor = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0]
                const jobs = panels.waiting
                panels.waiting = []
                for (const job of jobs) job(monitor)
            }
        }
    }
}
