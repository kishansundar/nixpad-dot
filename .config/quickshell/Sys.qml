pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Live numbers: read once here and shown by every bar and panel
Singleton {
    id: sys

    // --- Processor, memory, disk, temperature ---

    // CPU: the share of time the processor was busy since the last reading
    property int cpu: 0
    property var cpuLast: ({ idle: 0, total: 0 })
    FileView {
        id: cpuFile
        path: "/proc/stat"
        onLoaded: {
            const t = text().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number)
            const idle = t[3] + t[4], total = t.reduce((a, b) => a + b, 0)
            if (total > sys.cpuLast.total) sys.cpu = Math.round(100 * (1 - (idle - sys.cpuLast.idle) / (total - sys.cpuLast.total)))
            sys.cpuLast = { idle: idle, total: total }
        }
    }

    // Memory that is not free for new programs: as a percentage, and in GiB out of the GiB fitted
    property int ram: 0
    property real ramUsed: 0
    property real ramTotal: 0
    FileView {
        id: ramFile
        path: "/proc/meminfo"
        onLoaded: {
            const kb = key => Number(text().match(key + ":\\s+(\\d+)")[1])
            sys.ramTotal = kb("MemTotal") / 1048576
            sys.ramUsed = (kb("MemTotal") - kb("MemAvailable")) / 1048576
            sys.ram = Math.round(100 * sys.ramUsed / sys.ramTotal)
        }
    }

    // Disk: how much of / is used, how much is free and how big it is, in GiB, and the used share in percent; asked from df once at the start and each time the dashboard opens (nothing else shows it)
    property int disk: 0
    property real diskUsed: 0
    property real diskFree: 0
    property real diskTotal: 0
    Process {
        id: diskCheck
        running: true
        command: ["df", "-B1", "--output=used,avail,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = text.split("\n")[1]
                if (!answer) return
                const [used, free, size] = answer.trim().split(/\s+/).map(Number)
                sys.diskUsed = used / 1073741824
                sys.diskFree = free / 1073741824
                sys.diskTotal = size / 1073741824
                sys.disk = Math.round(100 * used / (used + free))
            }
        }
    }
    function checkDisk() { diskCheck.running = true }

    // Processor temperature in °C, or -1 on a machine without a k10temp (AMD) or coretemp (Intel) sensor; found by name once because its folder number can change between boots
    property int temp: -1
    // The highest it has been since the bar started
    property int tempPeak: -1
    Process {
        running: true
        command: ["sh", "-c", "grep -lxE 'k10temp|coretemp' /sys/class/hwmon/hwmon*/name | head -n1"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) tempFile.path = text.trim().replace("/name", "/temp1_input") }
    }
    FileView { id: tempFile; onLoaded: { sys.temp = Math.round(Number(text()) / 1000); sys.tempPeak = Math.max(sys.tempPeak, sys.temp) } }

    // --- Network ---

    // The connected device, the cable first when both are up; none means offline
    readonly property var netUp: Networking.devices.values.filter(d => d.connected)
    readonly property var netDevice: netUp.find(d => d.type === DeviceType.Wired) ?? netUp[0] ?? null
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    // "ETH", "WIFI" or "OFF", and the name of the Wi-Fi network or of the cable's port
    readonly property string link: !netDevice ? "OFF" : netDevice.type === DeviceType.Wifi ? "WIFI" : "ETH"
    readonly property string netName: link === "WIFI" ? (wifiDevice?.networks.values.find(n => n.connected)?.name ?? "") : (netDevice?.name ?? "")

    // Traffic: bytes per second in and out over the cable and Wi-Fi ports, from the kernel's counters and the time since the last reading
    property real down: 0
    property real up: 0
    property var netLast: null
    FileView {
        id: netFile
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0
            for (const line of text().split("\n")) {
                const port = line.match(/^\s*(?:en|wl)\w+:\s*(.*)$/)
                if (!port) continue
                const count = port[1].trim().split(/\s+/).map(Number)
                rx += count[0]; tx += count[8]
            }
            const now = Date.now()
            if (sys.netLast) { const seconds = Math.max(1, (now - sys.netLast.at) / 1000); sys.down = Math.max(0, rx - sys.netLast.rx) / seconds; sys.up = Math.max(0, tx - sys.netLast.tx) / seconds }
            sys.netLast = { rx: rx, tx: tx, at: now }
        }
    }

    // Tailscale: tailscaled announces each change of its state on its own socket and the bar reads it as it comes, without asking again and again ("Running", "Stopped", "NeedsLogin" and so on; empty while tailscaled does not answer, tried again every 10 seconds); the address is asked once at each change
    readonly property var tailNames: ["NoState", "InUseOtherUser", "NeedsLogin", "NeedsMachineAuth", "Stopped", "Starting", "Running"]
    property string tailState: ""
    property string tailAddress: ""
    readonly property string tailWord: tailState === "" ? "SERVICE NOT RUNNING" : tailState.replace(/([a-z])([A-Z])/g, "$1 $2").toUpperCase()
    Socket {
        id: tailBus
        path: "/run/tailscale/tailscaled.sock"
        Component.onCompleted: connected = true
        onConnectionStateChanged: { if (connected) { write("GET /localapi/v0/watch-ipn-bus?mask=2 HTTP/1.0\r\nHost: local-tailscaled.sock\r\n\r\n"); flush() } else sys.tailState = "" }
        parser: SplitParser { onRead: line => { const n = line.startsWith("{") ? JSON.parse(line) : null; if (Number.isInteger(n?.State)) { sys.tailState = sys.tailNames[n.State] ?? ""; tailIp.running = true } } }
    }
    Timer { interval: 10000; running: !tailBus.connected; repeat: true; onTriggered: tailBus.connected = true }
    Process { id: tailIp; command: ["tailscale", "ip", "-4"]; stdout: StdioCollector { onStreamFinished: sys.tailAddress = text.trim() } }
    // Starts or stops Tailscale (the dashboard's switch and its T key) without a password, as its operator (set in the NixOS config); only between running and stopped, a login or a service that is down is left to a terminal
    function toggleTail() {
        if (tailState === "Running" || tailState === "Stopped") Quickshell.execDetached(["tailscale", tailState === "Running" ? "down" : "up"])
    }

    // --- Sound ---

    // The default output; the tracker keeps volume, mute state and names current for every output
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    PwObjectTracker { objects: sys.sinks }
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int volume: Math.round((sink?.audio?.volume ?? 0) * 100)
    function setVolume(part) { if (sink?.audio) sink.audio.volume = Math.max(0, Math.min(1, part)) }
    function toggleMute() { if (sink?.audio) sink.audio.muted = !sink.audio.muted }

    // Scrolling over volume or brightness: one wheel notch (120 units) is one 5% step, and a touchpad adds up until it reaches a notch
    property real scrolled: 0
    function steps(wheel) {
        scrolled += wheel.angleDelta.y
        const n = Math.trunc(scrolled / 120)
        scrolled -= n * 120
        return n
    }
    function scrollVolume(wheel) {
        const n = steps(wheel)
        if (n) setVolume((sink?.audio?.volume ?? 0) + n * 0.05)
    }
    function scrollBrightness(wheel) { stepBrightness(steps(wheel)) }
    // Brightness by steps of 5% (the wheel, and Up and Down in the dashboard), or straight to a share of full from 0 to 1 (a click or drag on the dashboard's line); -n2 is a floor, so the screen cannot go black
    function stepBrightness(n) {
        if (n) Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set", Math.abs(n) * 5 + "%" + (n > 0 ? "+" : "-")])
    }
    function setBrightness(part) {
        const percent = Math.round(100 * Math.max(0, Math.min(1, part)))
        if (percent !== brightness) Quickshell.execDetached(["brightnessctl", "-e4", "-n2", "set", percent + "%"])
    }

    // --- Now playing: what media players announce about themselves (MPRIS); shown is the one that started playing most recently; playerctld only repeats another player, so it is left out ---

    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.endsWith(".playerctld"))
    // A player that starts playing takes over; when the one shown stops or goes away, another that still plays takes over; with nothing playing the one shown stays, or else one that has a track loaded
    property var player: null
    function choose(started) {
        const here = players.includes(player)
        if (started) player = started
        else if (!here || !player.isPlaying) player = players.find(p => p.isPlaying) ?? (here && titleOf(player) !== "" ? player : players.find(p => titleOf(p) !== "") ?? (here ? player : players[0] ?? null))
    }
    onPlayersChanged: choose(null)
    // One watcher per player says when it starts or stops, or gets its first track, and keeps the track's length: a browser names a video's length only now and then while it plays, so the last one named for the track it still has is used (an absurd one, as a live stream gives, counts as none)
    Variants {
        id: watchers
        model: sys.players
        QtObject {
            required property var modelData
            readonly property bool playing: modelData.isPlaying
            readonly property bool loaded: sys.titleOf(modelData) !== ""
            readonly property real told: modelData.lengthSupported && modelData.length < 360000 ? modelData.length : 0
            property real kept: 0
            property int keptFor: -1
            readonly property real length: told > 0 ? told : keptFor === modelData.uniqueId ? kept : 0
            onPlayingChanged: sys.choose(playing ? modelData : null)
            onLoadedChanged: sys.choose(null)
            onToldChanged: if (told > 0) { kept = told; keptFor = modelData.uniqueId }
        }
    }
    readonly property bool playing: player?.isPlaying ?? false
    // A track's title; a local file that carries none goes by its file name, taken from its address
    function titleOf(p) { const file = p && p.trackTitle === "" ? String(p.metadata["xesam:url"] ?? "").match(/^file:.*\/([^\/]+)$/) : null; try { return file ? decodeURIComponent(file[1]) : p?.trackTitle ?? "" } catch (e) { return file[1] } }
    readonly property string track: titleOf(player)
    readonly property string artist: player?.trackArtist ?? ""
    // A track's length in seconds, as its watcher holds it; 0 when the player has named none
    function lengthOf(p) { return watchers.instances.find(w => w.modelData === p)?.length ?? 0 }
    // How far the bar's player is through its track, 0 to 1 (-1 when that cannot be known)
    readonly property real progress: lengthOf(player) > 0 && player.positionSupported ? Math.max(0, Math.min(1, player.position / lengthOf(player))) : -1
    // A player's position only moves when it is asked: only while a playing player has a timeline to move, every second with the media panel open and every 5 seconds for the bar's line alone
    readonly property bool ticking: players.some(p => p.isPlaying && p.positionSupported && lengthOf(p) > 0)
    Timer { interval: Panels.open === "media" ? 1000 : 5000; running: sys.ticking; repeat: true; onTriggered: { for (const p of sys.players) if (p.isPlaying) p.positionChanged() } }

    // --- Screen ---

    // Brightness in percent on the curve of the brightness keys (brightnessctl -e4), or -1 on a machine without a backlight
    property int brightness: -1
    property string backlight: ""
    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/backlight/* 2>/dev/null | head -n1"]
        stdout: StdioCollector { onStreamFinished: sys.backlight = text.trim() }
    }
    FileView { id: backlightMax; path: sys.backlight ? sys.backlight + "/max_brightness" : ""; blockLoading: true }
    FileView {
        path: sys.backlight ? sys.backlight + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: sys.brightness = Math.round(100 * Math.pow(Number(text()) / Number(backlightMax.text()), 1 / 4))
    }

    // Night light: on while wlsunset runs; Super+Alt+N and the dashboard both switch it here, so the bar knows; asked once at the start and again while the dashboard is open, in case something else stopped it
    property bool night: false
    Process { id: nightCheck; running: true; command: ["pgrep", "-x", "wlsunset"]; onExited: code => sys.night = code === 0 }
    function checkNight() { nightCheck.running = true }
    function toggleNight() {
        night = !night
        Quickshell.execDetached(["sh", "-c", "pkill -x wlsunset || wlsunset -t 4000 -T 4001 -S 06:00 -s 18:00"])
    }

    // Caffeine: while on, each bar tells mango the screen is in use, so the screensaver, the lock and the idle sleep do not start; off again at every login
    property bool awake: false

    // --- Focused window: mango's own word on it, one line each time it changes; mango keeps naming the window while a picker or a panel holds the keyboard, when no window is marked active, and the bar takes the title from here then ---

    property string focused: ""
    Process {
        running: true
        command: ["mmsg", "watch", "focusing-client"]
        stdout: SplitParser { onRead: line => sys.focused = line }
    }

    // --- Battery ---

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery?.isPresent ?? false
    readonly property int charge: Math.round((battery?.percentage ?? 0) * 100)
    readonly property bool charging: battery?.state === UPowerDeviceState.Charging
    // Amber from 30% down and red from 15% down, unless it is charging
    readonly property color chargeColor: charging ? Theme.text : charge <= 15 ? Theme.error : charge <= 30 ? Theme.warn : Theme.text
    // Amber from 75°C, red from 90°C
    readonly property color tempColor: temp >= 90 ? Theme.error : temp >= 75 ? Theme.warn : Theme.text

    // The machine's state in one colour and one line, for the square beside the bar's name
    readonly property bool hot: temp >= 75
    readonly property bool low: hasBattery && !charging && charge <= 30
    readonly property color stateColor: temp >= 90 || (low && charge <= 15) ? Theme.error : hot || low ? Theme.warn : awake ? Theme.info : night ? Theme.night : Theme.accent
    readonly property string stateText: [hot ? "CPU AT " + temp + "°C" : "", low ? "BATTERY AT " + charge + "%" : "", awake ? "CAFFEINE ON" : "", night ? "NIGHT LIGHT ON" : ""].filter(s => s).join("  /  ") || "ALL NOMINAL"

    // --- Notifications ---

    // The shell's own messages (a failed Wi-Fi join or Bluetooth pairing) go out as desktop notifications over D-Bus like any app's; Notify.qml receives and shows them
    function notify(title, body) {
        Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "Notify", "susssasa{sv}i", "bar", "0", "", title, body, "0", "0", "6000"])
    }

    // --- Facts that do not change while the machine runs ---

    property string host: ""
    property string os: ""
    property string kernel: ""
    property string cpuModel: ""
    property int cpuCores: 0
    property int cpuThreads: 0
    // When the machine started, in seconds since 1970; the dashboard counts the uptime from it
    property real bootedAt: 0
    FileView { path: "/proc/sys/kernel/hostname"; onLoaded: sys.host = text().trim() }
    FileView { path: "/proc/sys/kernel/osrelease"; onLoaded: sys.kernel = text().trim() }
    FileView { path: "/etc/os-release"; onLoaded: sys.os = text().match(/PRETTY_NAME="([^"]*)"/)?.[1] ?? "" }
    // The processor's name without the maker's extras ("(R)", "with Radeon Graphics", "CPU @ 2.80GHz", "8-Core Processor"), and how many cores and threads it has
    FileView {
        path: "/proc/cpuinfo"
        onLoaded: {
            sys.cpuModel = (text().match(/model name\s*:\s*(.*)/)?.[1] ?? "").replace(/\((R|TM|tm)\)/g, "").replace(/ with .*$| CPU.*$| @ .*$| \d+-Core Processor$| Processor$/, "").replace(/\s+/g, " ").trim()
            sys.cpuCores = Number(text().match(/cpu cores\s*:\s*(\d+)/)?.[1] ?? 0)
            sys.cpuThreads = (text().match(/^processor\s*:/gm) ?? []).length
        }
    }
    // The desktop with the version mango reports ("mango 0.17.5"), and before that answer arrives just its name
    property string desktop: Quickshell.env("XDG_CURRENT_DESKTOP") ?? ""
    Process {
        running: true
        command: ["mmsg", "get", "version"]
        stdout: StdioCollector { onStreamFinished: { try { sys.desktop = "mango " + JSON.parse(text).version.replace(/\(.*\)/, "") } catch (e) {} } }
    }
    FileView { path: "/proc/uptime"; onLoaded: sys.bootedAt = Date.now() / 1000 - Number(text().split(" ")[0]) }

    // --- Timing and number formats ---

    // Every 3 seconds: the temperature always (every bar shows it); processor, memory and traffic only while something shows them, which is a bar wide enough for their cells or the open dashboard
    readonly property bool watched: Panels.open === "dashboard" || Quickshell.screens.some(s => s.width >= Theme.wide)
    function read() { cpuFile.reload(); ramFile.reload(); netFile.reload() }
    onWatchedChanged: if (watched) read()
    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: { if (tempFile.path) tempFile.reload(); if (sys.watched) sys.read() }
    }

    // 7 as "07"; bytes per second as megabits per second in three digits, "4.8", "19.0" or "332" (the unit is written once, after both numbers); seconds as "07:05:19"; KiB as "512 MiB" or "2.1 GiB"
    function two(n) { return String(n).padStart(2, "0") }
    function rate(bytes) { const m = bytes * 8 / 1000000; return m < 99.95 ? m.toFixed(1) : String(Math.round(m)) }
    function span(seconds) { return two(Math.floor(seconds / 3600)) + ":" + two(Math.floor(seconds % 3600 / 60)) + ":" + two(Math.floor(seconds % 60)) }
    function size(kib) { return kib >= 1048576 ? (kib / 1048576).toFixed(1) + " GiB" : Math.round(kib / 1024) + " MiB" }
    // The ISO week number of a date (weeks start on Monday, week 1 holds the year's first Thursday); its day number in the year; how many days its year has
    function week(d) { const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())); t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7)); return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7) }
    function dayOfYear(d) { return Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(d.getFullYear(), 0, 0)) / 86400000) }
    function daysInYear(d) { const y = d.getFullYear(); return y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0) ? 366 : 365 }
}
