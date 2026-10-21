import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

// The battery panel (a click on the bar's BAT cell): the charge and how long it lasts, the battery's condition, and the power profile switch
PanelWindow {
    id: battery
    visible: Panels.open === "battery"
    screen: Panels.screen
    // Under the right end of the bar, where the BAT cell is
    anchors { top: true; right: true }
    margins { top: Theme.gap; right: Theme.gap }
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay

    // Two views of the same battery: the summary UPower gives every laptop (charge, state, time left), and the battery itself for what the summary leaves out (health, model)
    readonly property var summary: Sys.battery
    readonly property var cell: UPower.devices.values.find(d => d.isLaptopBattery) ?? null
    // What it is doing, in words
    readonly property int phase: summary?.state ?? UPowerDeviceState.Unknown
    readonly property string phaseText: phase === UPowerDeviceState.Charging ? "CHARGING" : phase === UPowerDeviceState.Discharging ? "ON BATTERY" : phase === UPowerDeviceState.FullyCharged ? "FULL" : phase === UPowerDeviceState.PendingCharge ? "ON MAINS" : UPowerDeviceState.toString(phase).toUpperCase()
    // Seconds until it is full (while charging) or empty; 0 while UPower cannot tell yet
    readonly property real remaining: Sys.charging ? (summary?.timeToFull ?? 0) : (summary?.timeToEmpty ?? 0)
    // The level's colour: the second colour, then amber from 30% down and red from 15% down, the same steps as the bar
    readonly property color levelColor: Sys.charging ? Theme.accent2 : Sys.charge <= 15 ? Theme.error : Sys.charge <= 30 ? Theme.warn : Theme.accent2

    // Charge cycles: UPower does not report them but the kernel does, so its file is read each time the panel opens
    property int cycles: 0
    FileView {
        id: cycleFile
        path: battery.cell?.nativePath ? "/sys/class/power_supply/" + battery.cell.nativePath + "/cycle_count" : ""
        printErrors: false
        onLoaded: battery.cycles = parseInt(text()) || 0
    }
    onVisibleChanged: if (visible && cycleFile.path) cycleFile.reload()

    // The power profiles of power-profiles-daemon; PERFORMANCE is listed only on a machine that has it
    readonly property var profiles: [
        { label: "POWER SAVER", profile: PowerProfile.PowerSaver },
        { label: "BALANCED", profile: PowerProfile.Balanced },
        { label: "PERFORMANCE", profile: PowerProfile.Performance }
    ].filter(p => p.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile)

    Item {
        anchors.fill: parent

        Ui.Frame { anchors.fill: parent }
        // The panel closes shortly after the pointer leaves it
        HoverHandler { onHoveredChanged: hovered ? leave.stop() : leave.restart() }
        Timer { id: leave; interval: 600; onTriggered: if (battery.visible) Panels.close() }

        Column {
            id: body
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: "POWER / BATTERY"; kana: "バッテリー"; note: battery.phaseText }
            Ui.Line { width: parent.width }

            // The charge in large figures, the time left beside it, and the level as a line under both
            Item {
                width: parent.width; height: 72
                Ui.Value { x: 16; anchors.verticalCenter: parent.verticalCenter; text: Sys.charge + "%"; font: Theme.displayFont; color: Sys.chargeColor }
                Column {
                    visible: battery.remaining > 0
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Ui.Label { anchors.right: parent.right; text: Sys.charging ? "FULL IN" : "EMPTY IN" }
                    Ui.Value { anchors.right: parent.right; text: Sys.span(battery.remaining).slice(0, 5) }
                }
            }
            Rectangle {
                x: 16; width: parent.width - 32; height: 4
                color: Theme.surface2
                Rectangle { width: Math.round(parent.width * Sys.charge / 100); height: parent.height; color: battery.levelColor }
            }
            Item { width: 1; height: 12 }
            Ui.Line { width: parent.width }

            Ui.Section { title: "01 / CONDITION" }
            Ui.Pair { label: Sys.charging ? "CHARGING AT" : "DRAW"; value: (battery.summary?.changeRate ?? 0).toFixed(1) + " W" }
            Ui.Pair { label: "ENERGY"; value: (battery.summary?.energy ?? 0).toFixed(1) + " / " + (battery.summary?.energyCapacity ?? 0).toFixed(1) + " Wh" }
            Ui.Pair { visible: battery.cell?.healthSupported ?? false; label: "HEALTH"; value: Math.round(battery.cell?.healthPercentage ?? 0) + "% OF NEW" }
            Ui.Pair { visible: battery.cycles > 0; label: "CYCLES"; value: String(battery.cycles) }
            Ui.Pair { visible: (battery.cell?.model ?? "") !== ""; label: "MODEL"; value: battery.cell?.model ?? "" }
            Item { width: 1; height: 6 }
            Ui.Line { width: parent.width }

            Ui.Section { title: "02 / PROFILE" }
            Repeater {
                model: battery.profiles

                // One profile: the square is filled for the one in use, and a click switches to it
                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool active: PowerProfiles.profile === modelData.profile
                    width: body.width; height: Theme.row
                    color: over.hovered ? Theme.surface : "transparent"

                    Rectangle {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8
                        color: row.active ? Theme.accent : "transparent"
                        border { width: Theme.thin; color: row.active ? Theme.accent : Theme.border }
                    }
                    Ui.Value { x: 36; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.label; color: row.active ? Theme.accent : Theme.text }
                    HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: PowerProfiles.profile = row.modelData.profile }
                }
            }
            Item { width: 1; height: 6 }
        }
    }
}
