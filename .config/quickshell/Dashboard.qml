import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The system dashboard (Super+D, or a click on the bar's name): the machine's name and uptime, its load as large readings over steps, what uses its memory, the network, the screen switches (brightness, night light, caffeine), four actions, and the fingers the fingerprint reader knows
PanelWindow {
    id: dash
    visible: Panels.open === "dashboard"
    screen: Panels.screen
    // In the middle of the monitor, a sixth of the way down
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1080) / 6)
    exclusiveZone: 0
    implicitWidth: 880
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The actions along the bottom, and which one the keyboard has chosen; DISPLAYS and POWER hand over to their panels (locking is in the power panel, which asks before it restarts or switches off)
    property int chosen: 0
    readonly property var actions: [
        { label: "TERMINAL", run: () => Quickshell.execDetached(["kitty"]) },
        { label: "FILES", run: () => Quickshell.execDetached(["nautilus"]) },
        { label: "DISPLAYS", run: () => Panels.toggle("displays", dash.screen) },
        { label: "POWER", run: () => Panels.toggle("power", dash.screen) }
    ]
    function run(action) { Panels.close(); action.run() }
    onVisibleChanged: if (visible) { chosen = 0; keys.forceActiveFocus(); Sys.checkDisk(); fingers.check() }

    // The eight programs holding the most memory, read from /proc every 3 seconds while the dashboard is open: for each process the memory that is its own in KiB (resident less shared, from its statm file; what it shares with others, such as libraries, is left out so that nothing is counted twice) and the command it was started by; all of a program's processes are added up under that name, so a browser's many tab processes are one row; the names are only shown, never run; the night light is asked in the same beat
    property var procs: []
    Process {
        id: procCheck
        command: ["sh", "-c", "k=$(($(getconf PAGESIZE) / 1024)); for d in /proc/[0-9]*; do read -r _ res shr _ < $d/statm || continue; read -r -d '' arg < $d/cmdline; echo \"$(((res - shr) * k)) $arg\"; done 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const sums = {}
                for (const m of text.split("\n").map(line => line.match(/^(\d+)\s+(\S+)/)).filter(m => m)) {
                    const name = m[2].replace(/^.*\//, "").replace(/^[-.]/, "").replace(/-wrapped$/, "")
                    sums[name] = (sums[name] ?? 0) + Number(m[1])
                }
                dash.procs = Object.keys(sums).map(name => ({ name: name, kib: sums[name] })).sort((a, b) => b.kib - a.kib).slice(0, 8)
            }
        }
    }
    Timer { interval: 3000; running: dash.visible; repeat: true; triggeredOnStart: true; onTriggered: { procCheck.running = true; Sys.checkNight() } }
    // The uptime counts by the second, and only while the dashboard is open
    SystemClock { id: clock; enabled: dash.visible; precision: SystemClock.Seconds }

    // A level drawn like a tape deck's meter: a row of thin segments, the first `lit` of them lit; cyan for the first three fifths, orange above and the accent for the last few, unless one warning colour takes the whole row
    component Steps: Row {
        id: steps
        property int total: 20
        property int lit: 0
        property int wide: 4
        property int high: 12
        property color tint: Theme.accent2
        readonly property bool ramp: Qt.colorEqual(tint, Theme.accent2)
        spacing: 2
        Repeater {
            model: steps.total
            Rectangle { required property int index; width: steps.wide; height: steps.high; color: index >= steps.lit ? Theme.surface2 : !steps.ramp ? steps.tint : index < steps.total * 0.6 ? Theme.accent2 : index < steps.total * 0.85 ? Theme.warn : Theme.accent }
        }
    }
    // One reading of the load: its name, a large figure with its unit, ten steps for how full it is, and a line of detail; a figure in a warning colour takes its steps with it
    component Reading: Item {
        id: reading
        property string name
        property int figure
        property string unit: "%"
        property real part: figure / 100
        property string detail
        property color tint: Theme.text
        property bool ruled: true
        height: 122

        Ui.Line { visible: reading.ruled; height: parent.height }
        Ui.Label { x: 16; y: 10; text: reading.name }
        Row {
            x: 16; y: 26
            spacing: 4
            Ui.Value { id: big; text: String(reading.figure); font: Theme.displayFont; color: reading.tint }
            Ui.Label { anchors.baseline: big.baseline; text: reading.unit; color: Theme.text2 }
        }
        Steps { x: 16; y: 78; lit: Math.round(20 * Math.max(0, Math.min(1, reading.part))); tint: Qt.colorEqual(reading.tint, Theme.text) ? Theme.accent2 : reading.tint }
        Ui.Label { x: 16; y: 98; width: parent.width - 24; elide: Text.ElideRight; text: reading.detail; color: Theme.muted }
    }

    Ui.Frame { anchors.fill: parent; focused: true }
    // Left and Right (or H and L) choose an action and Enter runs it; Up and Down (or K and J) step the brightness, N switches the night light, C the caffeine, T Tailscale; Esc closes
    Item {
        id: keys
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) dash.chosen = (dash.chosen + 1) % dash.actions.length
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) dash.chosen = (dash.chosen + dash.actions.length - 1) % dash.actions.length
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) dash.run(dash.actions[dash.chosen])
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) Sys.stepBrightness(1)
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) Sys.stepBrightness(-1)
            else if (event.key === Qt.Key_N) Sys.toggleNight()
            else if (event.key === Qt.Key_C) Sys.awake = !Sys.awake
            else if (event.key === Qt.Key_T) Sys.toggleTail()
            else if (event.key === Qt.Key_Escape) Panels.close()
        }
    }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: parent.width - 2 * Theme.thick

        Ui.Head { title: "NIX / DASHBOARD"; kana: "システム"; note: "SUPER+D" }
        Ui.Line { width: parent.width }

        // The machine: its name in large figures over one line of what it runs, and how long it has been up
        Item {
            width: parent.width; height: 118
            Ui.Value { id: hostName; x: 16; y: 4; text: Sys.host.toUpperCase(); font: Theme.heroFont }
            Ui.Label {
                x: 16; y: 90
                width: parent.width - 32
                elide: Text.ElideRight
                text: [Sys.os, "LINUX " + Sys.kernel, Sys.desktop + " / " + (Quickshell.env("XDG_SESSION_TYPE") ?? ""), Sys.cpuModel].join("  /  ").toUpperCase()
                color: Theme.muted
            }
            Column {
                anchors { right: parent.right; rightMargin: 16 }
                y: 18
                spacing: 2
                Ui.Label { anchors.right: parent.right; text: "UPTIME" }
                Ui.Value { anchors.right: parent.right; text: Sys.span(Math.max(0, clock.date.getTime() / 1000 - Sys.bootedAt)); font: Theme.displayFont }
            }
        }
        Ui.Line { width: parent.width }

        Ui.Section { title: "01 / LOAD" }
        Row {
            id: load
            // How many readings this machine has: the temperature and the battery are left out where there is none
            readonly property int count: 3 + (Sys.temp >= 0 ? 1 : 0) + (Sys.hasBattery ? 1 : 0)
            readonly property real each: parent.width / count
            Reading { width: load.each; ruled: false; name: "CPU"; figure: Sys.cpu; detail: Sys.cpuCores > 0 ? Sys.cpuCores + " / " + Sys.cpuThreads + " THREADS" : "" }
            Reading { width: load.each; name: "MEMORY"; figure: Sys.ram; detail: Sys.ramUsed.toFixed(1) + " OF " + Sys.ramTotal.toFixed(1) + " GiB" }
            Reading { width: load.each; name: "DISK /"; figure: Math.round(Sys.diskUsed); unit: "GiB"; part: Sys.disk / 100; detail: Sys.diskFree.toFixed(0) + " FREE OF " + Sys.diskTotal.toFixed(0) }
            Reading { visible: Sys.temp >= 0; width: load.each; name: "TEMPERATURE"; figure: Sys.temp; unit: "°C"; part: (Sys.temp - 30) / 70; detail: "PEAK " + Sys.tempPeak + "°C"; tint: Sys.tempColor }
            Reading { visible: Sys.hasBattery; width: load.each; name: "BATTERY"; figure: Sys.charge; detail: Sys.charging ? "CHARGING" : "ON BATTERY"; tint: Sys.chargeColor }
        }
        Ui.Line { width: parent.width }

        Row {
            width: parent.width
            Column {
                id: processes
                width: (parent.width - Theme.thin) / 2
                bottomPadding: 6
                Ui.Section { title: "02 / PROGRAMS BY MEMORY" }
                Repeater {
                    model: dash.procs

                    // One program: its place and name (cut short before the steps), grey steps for its size against the largest, and the size
                    Item {
                        id: proc
                        required property var modelData
                        required property int index
                        width: parent.width; height: 26
                        Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 210; elide: Text.ElideRight; text: Sys.two(proc.index + 1) + "  " + proc.modelData.name.toUpperCase() }
                        Steps { anchors { right: parent.right; rightMargin: 104; verticalCenter: parent.verticalCenter } total: 10; wide: 6; high: 6; lit: Math.max(1, Math.round(10 * proc.modelData.kib / dash.procs[0].kib)); tint: Theme.strong }
                        Ui.Value { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: Sys.size(proc.modelData.kib) }
                    }
                }
            }
            Ui.Line { height: Math.max(processes.height, controls.height) }
            Column {
                id: controls
                width: (parent.width - Theme.thin) / 2
                bottomPadding: 6
                Ui.Section { title: "03 / NETWORK" }
                Ui.Pair { label: "LINK"; value: Sys.link === "OFF" ? "OFFLINE" : Sys.link + " / " + Sys.netName; tint: Sys.link === "OFF" ? Theme.muted : Theme.text }
                Ui.Pair { label: "TRAFFIC"; value: "↓ " + Sys.rate(Sys.down) + "   ↑ " + Sys.rate(Sys.up) + "   Mbps" }
                Ui.Switch { label: "TAILSCALE"; on: Sys.tailState === "Running"; note: Sys.tailState === "Running" ? Sys.tailAddress : Sys.tailState === "Stopped" ? "" : Sys.tailWord; onFlipped: Sys.toggleTail() }
                Item { width: 1; height: 8 }
                Ui.Section { title: "04 / SCREEN" }

                // Brightness of the laptop screen as twenty steps: a click or a drag along them sets it, the wheel steps it; left out on a machine without a backlight
                Item {
                    visible: Sys.brightness >= 0
                    width: parent.width; height: 48
                    Ui.Label { x: 16; y: 6; text: "BRIGHTNESS" }
                    Ui.Value { anchors { right: parent.right; rightMargin: 16 } y: 3; text: Sys.brightness + "%" }
                    Steps { id: level; x: 16; y: 28; total: 20; wide: Math.floor((parent.width - 32 - 38) / 20); high: 8; lit: Math.round(Sys.brightness / 5) }
                    MouseArea {
                        anchors { fill: level; topMargin: -12; bottomMargin: -8 }
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => Sys.setBrightness(mouse.x / width)
                        onPositionChanged: mouse => { if (pressed) Sys.setBrightness(mouse.x / width) }
                        onWheel: wheel => Sys.scrollBrightness(wheel)
                    }
                }
                Ui.Switch { label: "NIGHT LIGHT"; on: Sys.night; note: "4000 K"; onFlipped: Sys.toggleNight() }
                Ui.Switch { label: "CAFFEINE"; on: Sys.awake; note: "NO IDLE LOCK OR SLEEP"; onFlipped: Sys.awake = !Sys.awake }
            }
        }
        Ui.Line { width: parent.width }

        Ui.Section { title: "05 / ACTIONS" }
        Row {
            x: 16
            spacing: 8
            Repeater {
                model: dash.actions

                // One action: a square-cornered button; the chosen one gets the accent frame
                Rectangle {
                    id: button
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === dash.chosen
                    width: (body.width - 32 - 24) / 4; height: 44
                    color: chosen || over.hovered ? Theme.surface : "transparent"
                    border { width: chosen ? Theme.thick : Theme.thin; color: chosen ? Theme.accent : Theme.border }
                    Ui.Value { anchors.centerIn: parent; text: button.modelData.label; color: button.chosen ? Theme.accent : Theme.text }
                    HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: dash.run(button.modelData) }
                }
            }
        }
        Item { width: 1; height: 14 }
        Ui.Line { visible: fingers.visible; width: parent.width }
        Fingerprint { id: fingers; width: parent.width }
        Ui.Line { width: parent.width }
        Ui.Foot { keys: "←→: ACTION  /  ENTER: RUN  /  ↑↓: BRIGHTNESS  /  N: NIGHT LIGHT  /  C: CAFFEINE  /  T: TAILSCALE  /  ESC: CLOSE" }
    }
}
