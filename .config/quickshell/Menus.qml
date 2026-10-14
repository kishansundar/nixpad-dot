import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

// The lists that drop from the right end of the bar: Wi-Fi networks, Bluetooth devices and sound outputs with the volume; and a tray icon's own menu, which opens over the dock, where the tray's icons are
PanelWindow {
    id: menus

    // Which of the four lists is showing, "" while another panel or none is open
    readonly property string kind: ["wifi", "bluetooth", "audio", "tray"].includes(Panels.open) ? Panels.open : ""
    visible: kind !== ""
    screen: Panels.screen
    readonly property bool low: kind === "tray"
    anchors { top: !low; bottom: low; right: true }
    margins { top: Theme.gap; bottom: low ? Panels.foot : 0; right: low ? Panels.edge : Theme.gap }
    exclusiveZone: 0
    implicitWidth: 380
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard goes to the panel only while it asks for something: a Wi-Fi password, or what a Bluetooth device wants while it is being paired
    readonly property bool asking: pending !== null || prompt !== null
    WlrLayershell.keyboardFocus: asking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Opening a list refreshes it: Wi-Fi and Bluetooth search only while their list is open
    readonly property var adapter: Bluetooth.defaultAdapter
    onKindChanged: {
        pending = null
        forgetting = null
        if (prompt && kind !== "bluetooth") stopPairing()
        traySub = ""
        leave.stop()
        if (kind === "audio") dump.running = true
        if (kind === "wifi") tailPeers.running = true
        if (Sys.wifiDevice) Sys.wifiDevice.scannerEnabled = kind === "wifi"
        if (adapter?.enabled) adapter.discovering = kind === "bluetooth"
    }

    // Each list is rows: a label, a value at the right, a square that is filled for the one in use (or lit for one that is up), and what a click does (a row without that only shows something; a row with only a section is a heading, a row with a rule has a line above it); a row that can be forgotten also carries what a right click does, and is drawn red while it asks
    readonly property var rows: kind === "wifi" ? wifiRows() : kind === "bluetooth" ? bluetoothRows() : kind === "audio" ? audioRows() : kind === "tray" ? trayRows() : []
    readonly property string title: kind === "wifi" ? "NETWORK / WI-FI" : kind === "bluetooth" ? "BLUETOOTH / DEVICES" : kind === "audio" ? "AUDIO / OUTPUT" : "TRAY / " + (Panels.trayItem?.title || Panels.trayItem?.id || "").toUpperCase()
    readonly property string note: pending ? pending.name.toUpperCase() : prompt ? (pairing?.name ?? "").toUpperCase() : kind === "wifi" ? (Sys.link === "OFF" ? "OFFLINE" : Sys.link + " UP") : kind === "bluetooth" ? (adapter?.enabled ? "ON" : "OFF") : kind === "audio" ? (Sys.muted ? "MUTED" : Sys.volume + "%") : ""

    // --- Wi-Fi: the switch, then the eight strongest networks, the connected one first; one that needs a password asks for it in the panel ---

    property var pending: null
    function wifiRows() {
        const power = { label: "WI-FI", value: Networking.wifiEnabled ? "ON" : "OFF", active: Networking.wifiEnabled, pick: () => { Networking.wifiEnabled = !Networking.wifiEnabled } }
        if (!Networking.wifiEnabled) return [power].concat(tailRows())
        const open = n => n.known || n.security === WifiSecurityType.Open
        return [power, { section: "NETWORKS" }].concat((Sys.wifiDevice?.networks.values ?? []).filter(n => n.name)
            .sort((a, b) => b.connected - a.connected || b.signalStrength - a.signalStrength).slice(0, 8).map(n => ({
                label: n.name,
                value: (open(n) ? "" : "LOCK  ") + Math.round(n.signalStrength * 100) + "%",
                active: n.connected,
                pick: () => { if (n.connected) return; if (open(n)) join(n); else pending = n }
            }))).concat(tailRows())
    }

    // --- Tailscale, under the Wi-Fi list and built like it: its switch, then while it runs the machines on the tailnet with their addresses (the second colour while online, grey and OFFLINE while away, the accent and EXIT for the exit node in use), read when the list opens and at each change of Tailscale's state ---

    property var machines: []
    Process {
        id: tailPeers
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s = {}
                try { s = JSON.parse(text) } catch (e) {}
                const one = (p, me) => ({ name: (p.DNSName || p.HostName || "").split(".")[0], address: p.TailscaleIPs?.[0] ?? "", online: me || p.Online, exit: p.ExitNode, me: me })
                menus.machines = (s.Self ? [one(s.Self, true)] : []).concat(Object.values(s.Peer ?? {}).map(p => one(p, false)).sort((a, b) => b.online - a.online || a.name.localeCompare(b.name)))
            }
        }
    }
    Connections { target: Sys; function onTailStateChanged() { if (menus.kind === "wifi") tailPeers.running = true } }
    function tailRows() {
        const running = Sys.tailState === "Running"
        const power = { label: "TAILSCALE", value: running ? "ON" : Sys.tailState === "Stopped" ? "OFF" : Sys.tailWord, active: running, rule: true, pick: ["Running", "Stopped"].includes(Sys.tailState) ? () => Sys.toggleTail() : undefined }
        return [power].concat(!running ? [] : [{ section: "MACHINES" }].concat(machines.map(m => ({
            label: m.name.toUpperCase(),
            value: m.online ? (m.me ? "THIS  " : m.exit ? "EXIT  " : "") + m.address : "OFFLINE",
            active: m.exit,
            lit: m.online,
            off: !m.online
        }))))
    }
    // The network being joined: a failure is reported, and a network joined with a typed password is forgotten again so the next click asks for it
    property var joining: null
    property bool joiningNew: false
    function join(network, password) {
        joining = network
        joiningNew = password !== undefined
        if (joiningNew) network.connectWithPsk(password); else network.connect()
        Panels.close()
    }
    Connections {
        target: menus.joining
        function onConnectedChanged() { if (menus.joining.connected) menus.joining = null }
        function onConnectionFailed(reason) {
            Sys.notify("Wi-Fi", "Could not join " + menus.joining.name + " (" + ConnectionFailReason.toString(reason) + ").")
            if (menus.joiningNew) menus.joining.forget()
            menus.joining = null
        }
    }

    // --- Bluetooth: the switch, then paired devices and new ones that give a name ---

    function bluetoothRows() {
        if (!adapter) return []
        const power = { label: "BLUETOOTH", value: adapter.enabled ? "ON" : "OFF", active: adapter.enabled, pick: () => { adapter.enabled = !adapter.enabled } }
        if (!adapter.enabled) return [power]
        return [power, { section: "DEVICES" }].concat(Bluetooth.devices.values.filter(d => d.paired || !/^([0-9A-F]{2}-){5}/.test(d.name))
            .sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name)).slice(0, 8).map(d => ({
                label: d.name,
                value: d === forgetting ? "FORGET?" : d === pairing ? "PAIRING" : d.batteryAvailable ? Math.round(d.battery * 100) + "%" : d.paired ? "" : "NEW",
                active: d.connected,
                alert: d === forgetting,
                pick: () => { if (d === forgetting) forgetting = null; else if (d.connected) d.disconnect(); else if (d.paired) d.connect(); else pair(d) },
                forget: d.paired ? () => forget(d) : null
            })))
    }
    // Forgetting a paired device is asked first: a right click turns its row red with FORGET? for three seconds, and a second right click in that time removes the pairing (a click on the red row, or waiting, leaves it)
    property var forgetting: null
    Timer { id: spare; interval: 3000; onTriggered: menus.forgetting = null }
    function forget(device) {
        if (forgetting !== device) { forgetting = device; spare.restart(); return }
        forgetting = null
        device.forget()
    }
    readonly property string hint: kind === "bluetooth" && rows.some(r => r.forget) ? "RIGHT CLICK: FORGET A DEVICE" : ""

    // --- Pairing: bluetoothctl runs while the Bluetooth list is open or a device is being paired. BlueZ refuses to bond with a new device unless such an agent is there, and the agent is who a device's questions (a PIN, a number to compare) go to ---

    // The device being paired, from the click until it is connected or has failed
    property var pairing: null
    // What the device asks: "pin" or "passkey" (type it), "confirm" (the code is on both sides: say yes), "accept" (say yes) or "show" (type the code on the device)
    property var prompt: null
    property bool agentReady: false
    Process {
        id: agent
        command: ["bluetoothctl"]
        stdinEnabled: true
        running: menus.kind === "bluetooth" || menus.pairing !== null
        stdout: SplitParser { splitMarker: ""; onRead: data => menus.hear(data) }
        onExited: { menus.agentReady = false; menus.heard = ""; menus.prompt = null; menus.pairing = null }
    }
    function say(line) { agent.write(line + "\n") }
    function pair(device) {
        if (pairing) return
        pairing = device
        if (agentReady) say("pair " + device.address)
    }
    function want(what, code) {
        if (prompt?.what === what && prompt.code === (code ?? "")) return
        prompt = { what: what, code: code ?? "" }
        if (kind !== "bluetooth") Panels.toggle("bluetooth", Panels.screen)
    }
    function answer(text) { prompt = null; say(text) }
    // Esc, or the panel going away while a device waits for an answer: with both cleared the agent ends, and BlueZ gives up on a pairing whose agent is gone
    function stopPairing() { prompt = null; pairing = null; if (kind === "bluetooth") Panels.close() }
    // A failed pairing says why and closes the list, so the message is not hidden behind it
    function failed(reason) {
        if (pairing) Sys.notify("Bluetooth", "Could not pair " + pairing.name + ": " + reason)
        stopPairing()
    }
    // BlueZ's error names in plain words
    function why(error) {
        const name = error.replace("org.bluez.Error.", "")
        return ({
            AuthenticationRejected: "the device refused. Put it in pairing mode and try again.",
            AuthenticationFailed: "the device refused, or the PIN was wrong.",
            AuthenticationCanceled: "it was cancelled.",
            AuthenticationTimeout: "the device did not answer in time.",
            ConnectionAttemptFailed: "the device could not be reached. Is it on and in pairing mode?"
        })[name] ?? name + "."
    }
    // bluetoothctl's output comes in pieces with colour codes in it; each phrase below is acted on once, in the order it came (a result needs its line end, so a half-arrived line waits)
    property string heard: ""
    readonly property var phrases: [
        [/Agent registered/, () => { agentReady = true; if (pairing) say("pair " + pairing.address) }],
        [/Request PIN code/, () => want("pin")],
        [/Request passkey/, () => want("passkey")],
        [/Request confirmation[^]*?Confirm passkey (\d+) \(/, found => want("confirm", found[1])],
        [/Request authorization|Authorize service[\r\n]/, () => want("accept")],
        [/\[agent\] (?:PIN code|Passkey): (\w+)\s/, found => want("show", found[1])],
        [/Request canceled/, () => { prompt = null }],
        [/Pairing successful/, () => { prompt = null; if (pairing) { pairing.trusted = true; say("connect " + pairing.address) } }],
        [/Failed to pair: (\S+)[\r\n]/, found => failed(why(found[1]))],
        [/Device \S+ not available/, () => failed("it is no longer in range.")],
        [/Connection successful/, () => { pairing = null }],
        [/Failed to connect: /, () => { if (pairing) Sys.notify("Bluetooth", pairing.name + " is paired but did not connect. Click it in the list to try again."); pairing = null }]
    ]
    function hear(data) {
        heard = (heard + data).replace(/\x1b\[[0-9;?]*[A-Za-z]|[\x01\x02]/g, "").slice(-400)
        for (;;) {
            let first = null
            for (const [phrase, act] of phrases) {
                const found = phrase.exec(heard)
                if (found && (!first || found.index < first.found.index)) first = { found: found, act: act }
            }
            if (!first) return
            heard = heard.slice(first.found.index + first.found[0].length)
            first.act(first.found)
        }
    }

    // --- Sound: mute, then the outputs with something plugged in; the volume line above the rows is drawn further down ---

    function audioRows() {
        return [{ label: "MUTE", value: Sys.muted ? "ON" : "OFF", active: Sys.muted, pick: () => Sys.toggleMute() }, { section: "OUTPUTS" }]
            .concat(Sys.sinks.filter(n => !plugged || plugged.includes(n.id)).map(n => ({
                label: n.name.startsWith("bluez") ? n.description : n.properties["device.profile.description"] ?? n.description,
                value: "",
                active: n === Sys.sink,
                pick: () => { Pipewire.preferredDefaultAudioSink = n; Panels.close() }
            })))
    }
    // pw-dump lists each sound card's routes, and a route marked "no" has nothing connected
    property var plugged: null
    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: {
                let all = []
                try { all = JSON.parse(text) } catch (e) { return }
                const routes = {}
                for (const o of all) if (o.info?.params?.EnumRoute) routes[o.id] = o.info.params.EnumRoute
                menus.plugged = all.filter(o => o.info?.props?.["media.class"] === "Audio/Sink").filter(o => {
                    const mine = (routes[o.info.props["device.id"]] ?? []).filter(r => r.direction === "Output" && r.devices.includes(o.info.props["card.profile.device"]))
                    return mine.length === 0 || mine.some(r => r.available !== "no")
                }).map(o => o.id)
            }
        }
    }

    // --- Tray: the app's own menu as rows; separators are left out, an entry with a sub-list opens it (one level deep), a greyed-out entry does nothing ---

    // The label of the entry whose sub-list is showing ("" for the top list); found again by its label each time, because some apps rebuild their whole menu while it is open
    property string traySub: ""
    QsMenuOpener { id: trayMenu; menu: menus.kind === "tray" ? Panels.trayItem?.menu ?? null : null }
    QsMenuOpener { id: traySubMenu; menu: menus.traySub ? trayMenu.children.values.find(e => e.text === menus.traySub) ?? null : null }
    function trayRows() {
        const back = traySub ? [{ label: "< BACK", value: "", pick: () => { traySub = "" } }] : []
        return back.concat((traySub ? traySubMenu : trayMenu).children.values.filter(e => !e.isSeparator).map(e => {
            const dead = !e.enabled || (e.hasChildren && traySub !== "")
            return {
                image: e.icon, label: e.text, value: e.hasChildren && !dead ? ">" : "", active: e.checkState === Qt.Checked, off: dead,
                pick: dead ? null : e.hasChildren ? () => { traySub = e.text } : () => { e.triggered(); Panels.close() }
            }
        }))
    }

    // --- The panel ---

    Item {
        anchors.fill: parent

        Ui.Frame { anchors.fill: parent; focused: menus.asking }
        // The panel closes shortly after the pointer leaves it, unless it is waiting for an answer
        HoverHandler { onHoveredChanged: hovered || menus.asking ? leave.stop() : leave.restart() }
        Timer { id: leave; interval: 600; onTriggered: if (menus.kind !== "") Panels.close() }

        Column {
            id: body
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: menus.title; kana: menus.kind === "wifi" ? "ネットワーク" : menus.kind === "bluetooth" ? "ブルートゥース" : menus.kind === "audio" ? "オーディオ" : ""; note: menus.note }
            Ui.Line { width: parent.width }

            // Volume: the level as a line; a click or a drag along it sets the volume and the wheel steps it
            Item {
                visible: menus.kind === "audio"
                width: parent.width; height: 46
                Ui.Label { x: 16; y: 10; text: "VOLUME" }
                Ui.Value { anchors { right: parent.right; rightMargin: 16 } y: 7; text: Sys.volume + "%"; color: Sys.muted ? Theme.muted : Theme.text }
                Rectangle {
                    id: track
                    x: 16; y: 32; width: parent.width - 32; height: 4
                    color: Theme.surface2
                    Rectangle { width: Math.round(parent.width * Math.min(1, Sys.volume / 100)); height: parent.height; color: Sys.muted ? Theme.muted : Theme.accent2 }
                }
                MouseArea {
                    anchors { fill: track; topMargin: -12; bottomMargin: -8 }
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => Sys.setVolume(mouse.x / width)
                    onPositionChanged: mouse => { if (pressed) Sys.setVolume(mouse.x / width) }
                    onWheel: wheel => Sys.scrollVolume(wheel)
                }
            }

            // The password line for a Wi-Fi network: Enter connects, Esc goes back to the list
            Item {
                visible: menus.pending !== null
                width: parent.width; height: 44
                Ui.Label { id: ask; x: 16; anchors.verticalCenter: parent.verticalCenter; text: "PASSWORD:" }
                TextInput {
                    id: secret
                    anchors { left: ask.right; right: parent.right; leftMargin: 10; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: Theme.text
                    font: Theme.valueFont
                    echoMode: TextInput.Password
                    passwordCharacter: "*"
                    cursorDelegate: Rectangle { width: Theme.thick; color: Theme.accent }
                    // A typed password never stays in the line once its question is gone
                    onVisibleChanged: { clear(); if (visible) forceActiveFocus() }
                    onAccepted: { const network = menus.pending, typed = text; menus.pending = null; menus.join(network, typed) }
                    Keys.onEscapePressed: menus.pending = null
                }
            }

            // What a Bluetooth device asks while it is being paired: a PIN or a number to type, a number to compare, a plain yes, or a number to type on the device itself; Enter answers, Esc stops the pairing
            Item {
                id: question
                readonly property bool typed: ["pin", "passkey"].includes(menus.prompt?.what)
                visible: menus.prompt !== null
                width: parent.width; height: 44
                Ui.Label {
                    id: asked
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    text: ({ pin: "PIN:", passkey: "PASSKEY:", confirm: "SAME NUMBER ON THE DEVICE?", accept: "PAIR WITH THIS DEVICE?", show: "TYPE ON THE DEVICE:" })[menus.prompt?.what] ?? ""
                }
                TextInput {
                    visible: question.typed
                    anchors { left: asked.right; right: parent.right; leftMargin: 10; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    clip: true
                    color: Theme.text
                    font: Theme.valueFont
                    // A passkey is up to six digits, a PIN up to sixteen characters
                    validator: RegularExpressionValidator { regularExpression: menus.prompt?.what === "passkey" ? /\d{0,6}/ : /.{0,16}/ }
                    cursorDelegate: Rectangle { width: Theme.thick; color: Theme.accent }
                    onVisibleChanged: { clear(); if (visible) forceActiveFocus() }
                    onAccepted: if (text) menus.answer(text)
                    Keys.onEscapePressed: menus.stopPairing()
                }
                Ui.Value {
                    visible: menus.prompt !== null && !question.typed
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: menus.prompt?.code ?? ""
                    color: Theme.accent
                    onVisibleChanged: if (visible) forceActiveFocus()
                    Keys.onReturnPressed: if (menus.prompt.what !== "show") menus.answer("yes")
                    Keys.onEnterPressed: if (menus.prompt.what !== "show") menus.answer("yes")
                    Keys.onEscapePressed: menus.stopPairing()
                }
            }

            Repeater {
                model: menus.asking ? [] : menus.rows

                Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool heading: modelData.section !== undefined
                    width: body.width; height: Theme.row
                    color: over.hovered && modelData.pick ? Theme.surface : "transparent"

                    Ui.Line { visible: row.heading || !!row.modelData.rule; width: parent.width }
                    Ui.Label { visible: row.heading; x: 16; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.section ?? ""; color: Theme.muted }
                    // The square is filled with the accent for the one in use and with the second colour for one that is up; a tray entry shows its own picture there when it has one
                    Rectangle {
                        visible: !row.heading && !row.modelData.image
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8
                        color: row.modelData.active ? Theme.accent : row.modelData.lit ? Theme.accent2 : "transparent"
                        border { width: Theme.thin; color: row.modelData.active ? Theme.accent : row.modelData.lit ? Theme.accent2 : Theme.border }
                    }
                    IconImage { visible: !!row.modelData.image; x: 12; anchors.verticalCenter: parent.verticalCenter; implicitSize: 16; source: row.modelData.image ?? "" }
                    Ui.Value {
                        visible: !row.heading
                        anchors { left: parent.left; leftMargin: 36; right: amount.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        elide: Text.ElideRight
                        text: row.modelData.label ?? ""
                        color: row.modelData.alert ? Theme.error : row.modelData.off ? Theme.muted : row.modelData.active ? Theme.accent : Theme.text
                    }
                    Ui.Label { id: amount; visible: !row.heading; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: row.modelData.value ?? ""; color: row.modelData.alert ? Theme.error : Theme.text2 }
                    HoverHandler { id: over; cursorShape: row.modelData.pick ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: if (row.modelData.pick) row.modelData.pick() }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (row.modelData.forget) row.modelData.forget() }
                }
            }

            // What a list says while it is still empty
            Item {
                visible: !menus.asking && menus.rows.length === 0
                width: parent.width; height: Theme.row
                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: menus.kind === "tray" ? "THIS ICON HAS NO MENU" : menus.kind === "bluetooth" ? "NO BLUETOOTH ADAPTER" : "SEARCHING..."; color: Theme.muted }
            }
            Item { visible: !menus.asking && menus.hint === ""; width: 1; height: 6 }
            Ui.Line { visible: menus.asking || menus.hint !== ""; width: parent.width }
            Ui.Foot { visible: menus.asking || menus.hint !== ""; keys: !menus.asking ? menus.hint : menus.pending ? "ENTER: CONNECT  /  ESC: BACK" : question.typed ? "ENTER: SEND  /  ESC: CANCEL" : menus.prompt?.what === "show" ? "ESC: CANCEL" : "ENTER: YES  /  ESC: NO" }
        }
    }
}
