import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The temperature panel (a click on the bar's TMP cell): the processor's temperature in large figures, the fan, and every other sensor the machine has
PanelWindow {
    id: heat
    visible: Panels.open === "temperature"
    screen: Panels.screen
    // Under the right end of the bar, where the TMP cell is
    anchors { top: true; right: true }
    margins { top: Theme.gap; right: Theme.gap }
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay

    // Every sensor the kernel lists, read every 3 seconds while the panel is open; each line is chip|label|value|limit, a temperature in thousandths of a degree or a fan in turns per minute; the files are read by the shell itself, so a reading starts one program, not one per file
    readonly property string script: 'get() { v=; [ -r "$1" ] && read -r v < "$1" 2>/dev/null; }; for d in /sys/class/hwmon/hwmon*; do get "$d/name"; n=$v; for f in "$d"/temp*_input; do [ -e "$f" ] || continue; b=${f%_input}; get "${b}_label"; l=$v; get "${b}_crit"; c=$v; get "$f"; echo "$n|$l|$v|$c"; done; for f in "$d"/fan*_input; do [ -e "$f" ] || continue; get "$f"; echo "$n|fan|$v|"; done; done'
    Process {
        id: read
        command: ["sh", "-c", heat.script]
        stdout: StdioCollector { onStreamFinished: heat.take(text) }
    }
    Timer { interval: 3000; running: heat.visible; repeat: true; triggeredOnStart: true; onTriggered: read.running = true }

    // One row per chip as { name, degrees, limit }, the processor first: the chip's main reading (a named one such as Composite, else its first above zero); the laptop's own controller repeats the processor under two names (thinkpad and acpitz), so only its fans are taken
    property var sensors: []
    // Turns per minute of the fastest fan, or -1 on a machine that reports none
    property int fan: -1
    function title(chip) {
        return /^(k10temp|coretemp|zenpower)$/.test(chip) ? "PROCESSOR" : /^(amdgpu|radeon|nouveau|i915|xe)$/.test(chip) ? "GRAPHICS" : chip === "nvme" ? "SSD"
            : /^(iwlwifi|mt7|ath|rtw|brcm)/.test(chip) ? "WI-FI" : /^BAT/.test(chip) ? "BATTERY" : chip.toUpperCase()
    }
    function take(text) {
        const chips = {}, order = []
        let fastest = -1
        for (const line of text.split("\n")) {
            const [chip, label, value, limit] = line.split("|")
            if (!chip || value === undefined || value === "") continue
            if (label === "fan") { fastest = Math.max(fastest, Number(value)); continue }
            if (chip === "thinkpad" || chip === "acpitz" || Number(value) <= 0) continue
            const main = /^(Composite|Tctl|Tdie|edge|Package id 0)$/.test(label)
            if (!chips[chip]) { chips[chip] = { name: title(chip), degrees: Math.round(Number(value) / 1000), limit: limit ? Math.round(Number(limit) / 1000) : 0, main: main }; order.push(chip) }
            else if (main && !chips[chip].main) chips[chip] = { name: title(chip), degrees: Math.round(Number(value) / 1000), limit: limit ? Math.round(Number(limit) / 1000) : 0, main: true }
        }
        const rows = order.map(chip => chips[chip])
        sensors = rows.filter(row => row.name === "PROCESSOR").concat(rows.filter(row => row.name !== "PROCESSOR"))
        fan = fastest
    }
    // A reading turns amber 10 degrees under the chip's own limit and red at it; a chip that names no limit uses the processor's 75 and 90
    function tint(degrees, limit) {
        return degrees >= (limit > 0 ? limit : 90) ? Theme.error : degrees >= (limit > 0 ? limit - 10 : 75) ? Theme.warn : Theme.text
    }

    Item {
        anchors.fill: parent

        Ui.Frame { anchors.fill: parent }
        // The panel closes shortly after the pointer leaves it
        HoverHandler { onHoveredChanged: hovered ? leave.stop() : leave.restart() }
        Timer { id: leave; interval: 600; onTriggered: if (heat.visible) Panels.close() }

        Column {
            id: body
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: "TEMP / SENSORS"; kana: "温度"; note: Sys.tempPeak >= 0 ? "PEAK " + Sys.tempPeak + "°C" : "" }
            Ui.Line { width: parent.width }

            // The processor in large figures, the fan beside it, and under both a line from 30 to 100 degrees
            Item {
                width: parent.width; height: 72
                Ui.Value { x: 16; anchors.verticalCenter: parent.verticalCenter; text: Sys.temp >= 0 ? Sys.temp + "°C" : "--"; font: Theme.displayFont; color: Sys.tempColor }
                Column {
                    visible: heat.fan >= 0
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Ui.Label { anchors.right: parent.right; text: "FAN" }
                    Ui.Value { anchors.right: parent.right; text: heat.fan > 0 ? heat.fan + " RPM" : "STOPPED"; color: heat.fan > 0 ? Theme.text : Theme.text2 }
                }
            }
            Rectangle {
                x: 16; width: parent.width - 32; height: 4
                color: Theme.surface2
                Rectangle { width: Math.round(parent.width * Math.max(0, Math.min(1, (Sys.temp - 30) / 70))); height: parent.height; color: Sys.temp >= 90 ? Theme.error : Sys.temp >= 75 ? Theme.warn : Theme.accent2 }
            }
            Item { width: 1; height: 12 }
            Ui.Line { width: parent.width }

            Ui.Section { title: "01 / SENSORS" }
            Repeater {
                model: heat.sensors
                // The processor's row shows the large figure's value, so the two never differ
                Ui.Pair { required property var modelData; readonly property int degrees: modelData.name === "PROCESSOR" && Sys.temp >= 0 ? Sys.temp : modelData.degrees; label: modelData.name; value: degrees + "°C"; tint: heat.tint(degrees, modelData.limit) }
            }
            Item {
                visible: heat.sensors.length === 0
                width: parent.width; height: Theme.row
                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "NO SENSOR FOUND"; color: Theme.muted }
            }
            Item { width: 1; height: 6 }
        }
    }
}
