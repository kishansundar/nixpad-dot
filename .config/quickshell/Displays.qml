import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The displays panel (Super+P): where the screens stand (the larger one is the stage and stands still, the other is moved round it to one of twelve places) and how each one runs (resolution, refresh rate, scale, rotation, VRR); what the screens offer is asked from wlr-randr, and Enter writes the choices into mango's monitors.conf, which mango applies as soon as that file is saved
PanelWindow {
    id: displays
    visible: Panels.open === "displays"
    screen: Panels.screen
    // In the middle of the monitor, an eighth of the way down
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1080) / 8)
    exclusiveZone: 0
    implicitWidth: 760
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Every connected screen as wlr-randr reports it (the modes it offers; for one that is on also its mode, scale, rotation, position and whether VRR runs now), asked on opening and every 2 s while the panel is open
    property string heard: ""
    property var outputs: []
    Process {
        id: ask
        command: ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text !== displays.heard) { try { displays.outputs = JSON.parse(text); displays.heard = text } catch (e) {} }
                if (displays.settling && !settle.running) { displays.settling = false; displays.edits = ({}); displays.chosen = displays.live }
                if (!displays.piece && displays.row === 0) displays.row = 1
            }
        }
    }
    Timer { interval: 2000; running: displays.visible; repeat: true; triggeredOnStart: true; onTriggered: ask.running = true }
    // After a write mango needs a moment to reload and move the screens; until the next answer the choices stay on show as they were made
    property bool settling: false
    Timer { id: settle; interval: 900; onTriggered: ask.running = true }

    // mango's monitor rules, one line per screen; this panel changes nothing in them but the keys it sets, which it puts at the end of a screen's line
    property string conf: ""
    FileView {
        id: rules
        path: Quickshell.env("HOME") + "/.config/mango/monitors.conf"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: displays.conf = text()
    }
    function fits(line, name) { const rule = line.match(/^monitor_rule=.*\bname:([^,]+)/); try { return rule !== null && new RegExp(rule[1].trim()).test(name) } catch (e) { return false } }
    // A screen's rule line as its keys (width, refresh, scale, x and so on); empty when no line names the screen
    function ruleOf(name) {
        const line = conf.split("\n").find(one => fits(one, name)), keys = {}
        if (line) for (const part of line.slice(13).split(",")) { const cut = part.indexOf(":"); if (cut > 0) keys[part.slice(0, cut).trim()] = part.slice(cut + 1).trim() }
        return keys
    }
    // The rules with one screen's line rewritten: each given key replaced (null takes a key out, which leaves mango's default), all else on the line kept; a new line for a screen no line names
    function written(text, name, keys) {
        const lines = text.replace(/\n+$/, "").split("\n")
        let found = lines.findIndex(line => fits(line, name))
        if (found < 0) found = lines.push("monitor_rule=name:^" + name + "$") - 1
        let line = lines[found].replace(/\s+$/, "")
        for (const key in keys) line = line.replace(new RegExp(",\\s*" + key + "\\s*:[^,]*", "g"), "")
        for (const key of ["width", "height", "refresh", "scale", "rr", "vrr", "x", "y"]) if (keys[key] !== undefined && keys[key] !== null) line += "," + key + ":" + keys[key]
        lines[found] = line
        return lines.join("\n") + "\n"
    }

    // The connected screens, an external one before the laptop's own and a larger before a smaller, each with how it runs now; one that is off (the laptop under a closed lid) is read from its rule line instead; refresh is "max" when the rule asks for more than the screen offers, turn counts quarter turns, vrr says whether the rule keeps VRR on always
    readonly property var screens: outputs.map(o => {
        const rule = ruleOf(o.name), modes = o.modes ?? [], on = o.enabled === true
        const mode = modes.find(m => m.current) ?? modes.find(m => m.width === Number(rule.width) && m.height === Number(rule.height)) ?? modes.find(m => m.preferred) ?? modes[0] ?? { width: 1920, height: 1080, refresh: 60 }
        const top = Math.max(0, ...modes.filter(m => m.width === mode.width && m.height === mode.height).map(m => m.refresh))
        return {
            name: o.name, on: on, laptop: /^eDP/.test(o.name), modes: modes,
            label: (/^eDP/.test(o.name) ? "LAPTOP" : (o.model ?? "").toUpperCase()) + (o.physical_size?.width ? " " + Math.round(Math.hypot(o.physical_size.width, o.physical_size.height) / 25.4) + "″" : ""),
            width: mode.width, height: mode.height, refresh: Number(rule.refresh ?? 0) > top + 0.5 ? "max" : Math.round(mode.refresh),
            scale: on ? o.scale : Number(rule.scale ?? 1), turn: on ? Math.max(0, ["normal", "90", "180", "270"].indexOf(o.transform)) : Number(rule.rr ?? 0) % 4,
            vrr: rule.vrr === "1", vrrNow: o.adaptive_sync === true,
            x: on ? o.position.x : rule.x !== undefined ? Number(rule.x) : null, y: on ? o.position.y : rule.y !== undefined ? Number(rule.y) : null
        }
    }).sort((a, b) => a.laptop - b.laptop || b.width * b.height - a.width * a.height)
    readonly property var stage: screens[0] ?? null
    readonly property var piece: screens.length === 2 ? screens[1] : null
    // The screen whose settings are listed
    property int shown: 0
    readonly property var sel: screens[Math.min(shown, screens.length - 1)] ?? null

    // What has been chosen here and is not applied yet, per screen name: any of width, height, refresh, scale, turn, vrr
    property var edits: ({})
    function want(s) { return Object.assign({ width: s.width, height: s.height, refresh: s.refresh, scale: s.scale, turn: s.turn, vrr: s.vrr }, edits[s.name] ?? {}) }
    function set(s, values) { const next = Object.assign({}, edits); next[s.name] = Object.assign({}, next[s.name] ?? {}, values); edits = next }
    function dirty(s) { const w = want(s), out = {}; for (const key of ["width", "height", "refresh", "scale", "turn", "vrr"]) if (w[key] !== s[key]) out[key] = w[key]; return out }
    // The room a screen takes in mango's layout: its pixels divided by the scale, and stood on its side by a quarter turn
    function room(v) { const wide = Math.floor(v.width / v.scale), high = Math.floor(v.height / v.scale); return v.turn % 2 ? Qt.size(high, wide) : Qt.size(wide, high) }
    // What a screen offers: sizes of its own shape (that of its preferred mode) plus the one in use, largest first, five at most; the refresh rates of a size, in whole Hz; the scales that divide a size evenly
    function sizes(s) {
        const best = s.modes.find(m => m.preferred) ?? s.modes[0], used = s.width + "x" + s.height, all = [used]
        for (const m of s.modes) if (best && m.width * best.height === m.height * best.width && !all.includes(m.width + "x" + m.height)) all.push(m.width + "x" + m.height)
        const area = id => id.split("x")[0] * id.split("x")[1], top = all.slice().sort((a, b) => area(b) - area(a)).slice(0, 5)
        return top.includes(used) ? top : top.slice(0, 4).concat([used])
    }
    function rates(s, width, height) { const seen = {}; for (const m of s.modes) if (m.width === width && m.height === height) seen[Math.round(m.refresh)] = true; return Object.keys(seen).map(Number).sort((a, b) => b - a).slice(0, 5) }
    function scales(width, height) { return [1, 1.25, 1.5, 1.75, 2].filter(k => Number.isInteger(width / k) && Number.isInteger(height / k)) }

    // A place is a number from 0 to 11, clockwise from the top left: three above the stage, three at its right, three below, three at its left; within a side they run left to right or top to bottom (edges level, centred, edges level)
    readonly property var sides: ["ABOVE", "RIGHT OF", "BELOW", "LEFT OF"]
    readonly property var levels: [["LEFT EDGES LEVEL", "CENTRED", "RIGHT EDGES LEVEL"], ["TOP EDGES LEVEL", "CENTRED", "BOTTOM EDGES LEVEL"]]
    // Where the piece's top left corner lies from the stage's in that place, for a stage of room a and a piece of room b
    function offset(place, a, b) {
        const side = Math.floor(place / 3), slide = Math.round((side % 2 ? a.height - b.height : a.width - b.width) * (place % 3) / 2)
        return side === 0 ? Qt.point(slide, -b.height) : side === 1 ? Qt.point(a.width, slide) : side === 2 ? Qt.point(slide, a.height) : Qt.point(-b.width, slide)
    }
    // The place the screens are in now (-1 when the piece stands somewhere else, such as a position written by hand; a piece with no position yet goes where mango puts it, at the right with top edges level), and the place chosen here
    readonly property int live: {
        if (!piece || !stage) return -1
        if (piece.x === null || stage.x === null) return 3
        const a = room(stage), b = room(piece)
        for (let place = 0; place < 12; place++) { const at = offset(place, a, b); if (at.x === piece.x - stage.x && at.y === piece.y - stage.y) return place }
        return -1
    }
    property int chosen: -1
    onLiveChanged: if (!settling) chosen = live
    readonly property bool moved: piece !== null && chosen >= 0 && chosen !== live
    readonly property bool changed: !settling && !keeping && (moved || screens.some(s => Object.keys(dirty(s)).length > 0))
    // The corner of the piece as drawn (chosen, or where it really is), and both positions as they would be written: whichever screen lies further up or left stands at 0, so no position is negative (XWayland apps misplace clicks on negative ones)
    readonly property point shift: !piece || !stage ? Qt.point(0, 0) : chosen >= 0 ? offset(chosen, room(want(stage)), room(want(piece))) : Qt.point((piece.x ?? 0) - (stage.x ?? 0), (piece.y ?? 0) - (stage.y ?? 0))
    readonly property point stageAt: Qt.point(Math.max(0, -shift.x), Math.max(0, -shift.y))
    readonly property point pieceAt: Qt.point(stageAt.x + shift.x, stageAt.y + shift.y)

    // An arrow pushes the piece that way: along its side, round the corner at the side's end, or straight across the stage to the opposite side; pushing it away from the stage does nothing
    function push(dx, dy) {
        if (!piece) return
        if (chosen < 0) { chosen = dx > 0 ? 3 : dx < 0 ? 9 : dy > 0 ? 6 : 0; return }
        const side = Math.floor(chosen / 3), along = chosen % 3, upright = side % 2 === 1
        const step = upright ? dy : dx, across = upright ? dx : dy
        if (step !== 0) chosen = along + step >= 0 && along + step <= 2 ? chosen + step : upright ? (step < 0 ? 0 : 6) + (side === 1 ? 2 : 0) : (step < 0 ? 9 : 3) + (side === 2 ? 2 : 0)
        else if (across === (side === 0 || side === 3 ? 1 : -1)) chosen = (side + 2) % 4 * 3 + along
    }

    // The settings of the shown screen, one row each: the choices, the one in force (now) and the one chosen (want)
    readonly property var rows: {
        if (!sel) return []
        const w = want(sel)
        return [
            { key: "screen", label: "SCREEN", options: screens.map((s, index) => ({ text: s.name + "  " + s.label + (s.on ? "" : "  OFF"), value: index })), now: Math.min(shown, screens.length - 1), want: Math.min(shown, screens.length - 1), note: "" },
            { key: "size", label: "RESOLUTION", options: sizes(sel).map(id => ({ text: id.replace("x", " × "), value: id })), now: sel.width + "x" + sel.height, want: w.width + "x" + w.height, note: "" },
            { key: "refresh", label: "REFRESH", options: [{ text: "MAX", value: "max" }].concat(rates(sel, w.width, w.height).map(hz => ({ text: hz + " HZ", value: hz }))), now: sel.refresh, want: w.refresh, note: "" },
            { key: "scale", label: "SCALE", options: scales(w.width, w.height).map(k => ({ text: k + "×", value: k })), now: sel.scale, want: w.scale, note: w.scale === 1 ? "" : "AS " + Math.floor(w.width / w.scale) + " × " + Math.floor(w.height / w.scale) },
            { key: "turn", label: "ROTATION", options: ["0°", "90°", "180°", "270°"].map((text, index) => ({ text: text, value: index })), now: sel.turn, want: w.turn, note: "" },
            { key: "vrr", label: "VRR", options: [{ text: "FULL SCREEN ONLY", value: false }, { text: "ALWAYS", value: true }], now: sel.vrr, want: w.vrr, note: !sel.on ? "" : sel.vrrNow ? "RUNNING NOW" : "NOT RUNNING NOW" }
        ]
    }
    // A new size starts at its highest refresh rate and keeps the scale only if it still divides evenly
    function pick(key, value) {
        if (keeping || settling) return
        if (key === "screen") { shown = value; return }
        const one = {}, part = String(value).split("x").map(Number)
        if (key === "size") set(sel, { width: part[0], height: part[1], refresh: "max", scale: scales(part[0], part[1]).includes(want(sel).scale) ? want(sel).scale : 1 })
        else { one[key] = value; set(sel, one) }
    }
    function step(by) {
        const at = rows[row - 1], index = at.options.findIndex(option => option.value === at.want)
        pick(at.key, at.options[Math.max(0, Math.min(at.options.length - 1, Math.max(0, index) + by))].value)
    }
    // Where the keyboard is: 0 the map (arrows push the piece), 1 and up a settings row (Left and Right change it, Up and Down go to the next row); Tab goes on to the next of them all
    property int row: 0
    function hop(by) { const next = (row + by + rows.length + 1) % (rows.length + 1); row = next === 0 && !piece ? (by > 0 ? 1 : rows.length) : next }

    // Enter: every changed key and both positions go into monitors.conf; a change that could leave a screen unreadable (size, refresh rate, scale, rotation of a screen that is on) must be kept with a second Enter within 15 s, or the file goes back to what it was
    property bool keeping: false
    property int left: 0
    property string before: ""
    function apply() {
        if (!changed || !rules.loaded) return
        const risky = screens.some(s => s.on && Object.keys(dirty(s)).some(key => key !== "vrr"))
        let text = rules.text()
        before = text
        for (const s of screens) {
            const d = dirty(s), w = want(s), keys = {}
            if ("width" in d || "height" in d || "refresh" in d) { keys.width = w.width; keys.height = w.height; keys.refresh = w.refresh === "max" ? 1000 : w.refresh }
            if ("scale" in d) keys.scale = w.scale === 1 ? null : w.scale
            if ("turn" in d) keys.rr = w.turn === 0 ? null : w.turn
            if ("vrr" in d) keys.vrr = w.vrr ? 1 : null
            if (piece && chosen >= 0) { keys.x = s.name === stage.name ? stageAt.x : pieceAt.x; keys.y = s.name === stage.name ? stageAt.y : pieceAt.y }
            if (Object.keys(keys).length > 0) text = written(text, s.name, keys)
        }
        write(text)
        if (risky) { left = 15; keeping = true }
    }
    function write(text) { settling = true; rules.setText(text); conf = text; settle.restart() }
    function back() { keeping = false; write(before) }
    Timer { interval: 1000; repeat: true; running: displays.keeping; onTriggered: { displays.left -= 1; if (displays.left <= 0) displays.back() } }
    onVisibleChanged: {
        if (visible) { edits = ({}); chosen = live; shown = 0; row = 0; keys.forceActiveFocus() }
        else if (keeping) back()
    }

    // One setting: its name, then its choices as keys; the one in force is filled, a choice not applied yet is framed in orange, and the row the keyboard is on carries the accent block
    component Choice: Item {
        id: choice
        property string label
        property var options: []
        property var now
        property var want
        property string note
        property bool held: false
        signal picked(var value)
        width: parent.width; height: 32
        Rectangle { visible: choice.held; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 18; color: Theme.accent }
        Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: choice.label; color: choice.held ? Theme.text : Theme.text2 }
        Row {
            x: 132; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
                model: choice.options
                Rectangle {
                    id: key
                    required property var modelData
                    readonly property bool now: modelData.value === choice.now
                    readonly property bool want: modelData.value === choice.want && !now
                    width: word.implicitWidth + 20; height: 24
                    color: now ? Theme.accent : over.hovered ? Theme.surface : "transparent"
                    border { width: want ? Theme.thick : Theme.thin; color: want ? Theme.warn : now ? Theme.accent : Theme.border }
                    Ui.Label { id: word; anchors.centerIn: parent; text: key.modelData.text; color: key.now ? Theme.accentInk : key.want ? Theme.warn : Theme.text }
                    HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: choice.picked(key.modelData.value) }
                }
            }
        }
        Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: choice.note; color: Theme.muted }
    }

    Ui.Frame { anchors.fill: parent; focused: true }
    // Tab goes from the map through the settings rows; on the map arrows (or H J K L) move the piece, on a row Left and Right change it and Up and Down change row; Enter applies, or keeps what was applied; Esc goes back, takes back what is not applied yet, or closes
    Item {
        id: keys
        Keys.onPressed: event => {
            const dx = event.key === Qt.Key_Right || event.key === Qt.Key_L ? 1 : event.key === Qt.Key_Left || event.key === Qt.Key_H ? -1 : 0
            const dy = event.key === Qt.Key_Down || event.key === Qt.Key_J ? 1 : event.key === Qt.Key_Up || event.key === Qt.Key_K ? -1 : 0
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (displays.keeping) displays.keeping = false; else displays.apply() }
            else if (event.key === Qt.Key_Escape) { if (displays.keeping) displays.back(); else if (displays.changed) { displays.edits = ({}); displays.chosen = displays.live } else Panels.close() }
            else if (displays.keeping || displays.settling) return
            else if (event.key === Qt.Key_Tab) displays.hop(1)
            else if (event.key === Qt.Key_Backtab) displays.hop(-1)
            else if (displays.row === 0) displays.push(dx, dy)
            else if (dx !== 0) displays.step(dx)
            else if (dy !== 0) displays.row = Math.max(displays.piece ? 0 : 1, Math.min(displays.rows.length, displays.row + dy))
        }
    }
    Column {
        id: body
        x: Theme.thick; y: Theme.thick
        width: parent.width - 2 * Theme.thick

        Ui.Head { title: "NIX / DISPLAYS"; kana: "ディスプレイ"; note: !rules.loaded ? "NO MONITORS.CONF" : displays.heard === "" ? "NO WLR-RANDR" : "SUPER+P" }
        Ui.Line { width: parent.width }

        Item {
            width: parent.width; height: Theme.row
            Rectangle { visible: displays.row === 0 && displays.piece !== null; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 18; color: Theme.accent }
            Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "01 / ARRANGEMENT"; color: displays.row === 0 && displays.piece !== null ? Theme.text : Theme.muted }
        }
        // The map: both screens to one scale, small enough that the piece fits on any side of the stage, so the stage never moves
        Item {
            id: map
            width: parent.width; height: 250
            clip: true
            readonly property size a: displays.stage ? displays.room(displays.want(displays.stage)) : Qt.size(0, 0)
            readonly property size b: displays.piece ? displays.room(displays.want(displays.piece)) : Qt.size(0, 0)
            readonly property real ratio: a.width <= 0 ? 0 : Math.min((width - 32) / (a.width + 2 * b.width), (height - 24) / (a.height + 2 * b.height))
            // The middle of the piece in a place, on the map: a press or a drag outside the stage picks the place whose middle is nearest
            function middle(place) { const at = displays.offset(place, a, b); return Qt.point(stageBox.x + (at.x + b.width / 2) * ratio, stageBox.y + (at.y + b.height / 2) * ratio) }
            function nearest(x, y) {
                if (x >= stageBox.x && x < stageBox.x + stageBox.width && y >= stageBox.y && y < stageBox.y + stageBox.height) return displays.chosen
                let best = 0
                for (let place = 1; place < 12; place++) if (Math.hypot(middle(place).x - x, middle(place).y - y) < Math.hypot(middle(best).x - x, middle(best).y - y)) best = place
                return best
            }
            MouseArea {
                anchors.fill: parent
                enabled: displays.piece !== null && !displays.keeping && !displays.settling
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: mouse => { displays.row = 0; displays.chosen = map.nearest(mouse.x, mouse.y) }
                onPositionChanged: mouse => { if (pressed) displays.chosen = map.nearest(mouse.x, mouse.y) }
            }

            // The stage: the screen that stands still; the screen whose settings are listed carries a stripe in the second colour
            Rectangle {
                id: stageBox
                visible: displays.stage !== null
                width: Math.round(map.a.width * map.ratio); height: Math.round(map.a.height * map.ratio)
                x: Math.round((map.width - width) / 2); y: Math.round((map.height - height) / 2)
                color: Theme.surface
                border { width: Theme.thick; color: Theme.strong }
                Rectangle { visible: displays.sel?.name === displays.stage?.name && displays.screens.length > 1; x: Theme.thick; y: Theme.thick; width: parent.width - 2 * Theme.thick; height: 3; color: Theme.accent2 }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Ui.Value { anchors.horizontalCenter: parent.horizontalCenter; text: displays.stage?.name ?? ""; font: Theme.displayFont }
                    Ui.Label { anchors.horizontalCenter: parent.horizontalCenter; visible: implicitWidth + 12 <= stageBox.width; text: displays.stage ? map.a.width + " × " + map.a.height : "" }
                }
            }
            // Where the piece is now, as an empty outline, while another place is chosen
            Rectangle {
                visible: displays.moved && displays.live >= 0 && displays.piece.x !== null
                x: stageBox.x + Math.round(((displays.piece?.x ?? 0) - (displays.stage?.x ?? 0)) * map.ratio); y: stageBox.y + Math.round(((displays.piece?.y ?? 0) - (displays.stage?.y ?? 0)) * map.ratio)
                width: pieceBox.width; height: pieceBox.height
                color: "transparent"
                border { width: Theme.thin; color: Theme.strong }
                Ui.Label { anchors.centerIn: parent; text: "NOW"; color: Theme.muted }
            }
            // The piece: the accent frame of what the keyboard moves, orange until the move is applied, grey while that screen is off
            Rectangle {
                id: pieceBox
                readonly property color tint: displays.moved ? Theme.warn : displays.piece?.on ? Theme.accent : Theme.text2
                visible: displays.piece !== null
                x: stageBox.x + Math.round(displays.shift.x * map.ratio); y: stageBox.y + Math.round(displays.shift.y * map.ratio)
                width: Math.round(map.b.width * map.ratio); height: Math.round(map.b.height * map.ratio)
                color: Theme.surface2
                border { width: Theme.thick; color: tint }
                Rectangle { visible: displays.sel?.name === displays.piece?.name; x: Theme.thick; y: Theme.thick; width: parent.width - 2 * Theme.thick; height: 3; color: Theme.accent2 }
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Ui.Value { anchors.horizontalCenter: parent.horizontalCenter; text: displays.piece?.name ?? ""; color: pieceBox.tint }
                    Ui.Label { anchors.horizontalCenter: parent.horizontalCenter; visible: implicitWidth + 12 <= pieceBox.width; text: !displays.piece ? "" : displays.piece.on ? map.b.width + " × " + map.b.height : "OFF" }
                }
            }
            // The twelve places as sockets on the stage's edge, each at the middle of the stretch the piece would touch: filled for the chosen one
            Repeater {
                model: displays.piece ? 12 : 0
                Rectangle {
                    id: socket
                    required property int index
                    readonly property point at: displays.offset(index, map.a, map.b)
                    readonly property int side: Math.floor(index / 3)
                    x: stageBox.x - 4 + Math.round((side === 1 ? map.a.width : side === 3 ? 0 : at.x + map.b.width / 2) * map.ratio)
                    y: stageBox.y - 4 + Math.round((side === 2 ? map.a.height : side === 0 ? 0 : at.y + map.b.height / 2) * map.ratio)
                    width: 8; height: 8
                    color: index === displays.chosen ? pieceBox.tint : Theme.bg
                    border { width: Theme.thin; color: index === displays.chosen ? socket.color : Theme.strong }
                }
            }
        }
        Ui.Pair {
            label: "PLACE"
            value: !displays.stage ? "NO SCREEN" : displays.screens.length === 1 ? "ONE SCREEN, NOTHING TO ARRANGE" : !displays.piece ? "MORE THAN TWO SCREENS, ARRANGE THEM IN MONITORS.CONF" : displays.chosen < 0 ? "SET BY HAND" : displays.piece.name + " " + displays.sides[Math.floor(displays.chosen / 3)] + " " + displays.stage.name + ", " + displays.levels[Math.floor(displays.chosen / 3) % 2][displays.chosen % 3]
            tint: displays.moved ? Theme.warn : displays.piece && displays.chosen >= 0 ? Theme.text : Theme.muted
        }
        Item { width: 1; height: 6 }
        Ui.Line { width: parent.width }

        Ui.Section { title: "02 / SETTINGS" }
        Repeater {
            model: displays.rows
            Choice {
                required property var modelData
                required property int index
                label: modelData.label; options: modelData.options; now: modelData.now; want: modelData.want; note: modelData.note
                held: displays.row === index + 1
                onPicked: value => { displays.row = index + 1; displays.pick(modelData.key, value) }
            }
        }
        Item { width: 1; height: 8 }
        Ui.Line { width: parent.width }
        // The foot also has an APPLY (or KEEP) to click, so a change made with the pointer can be finished with it; while a change waits to be kept, a line along its top runs out with the seconds
        Ui.Foot {
            keys: displays.keeping ? "ENTER: KEEP  /  ESC: GO BACK NOW" : displays.settling ? "APPLYING" : (displays.row === 0 ? "←↑↓→: MOVE  /  TAB: SETTINGS" : "←→: CHANGE  /  ↑↓ TAB: ROW") + (displays.changed ? "  /  ENTER: APPLY  /  ESC: UNDO" : "  /  ESC: CLOSE")
            tint: displays.keeping || displays.changed ? Theme.warn : Theme.muted
            Rectangle { visible: displays.keeping; width: Math.round(parent.width * displays.left / 15); height: 3; color: Theme.warn }
            Ui.Label {
                visible: displays.keeping || displays.changed
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                text: displays.keeping ? "KEEP   GOES BACK IN " + displays.left + " S" : "APPLY"
                color: go.hovered ? Theme.text : Theme.warn
                HoverHandler { id: go; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { if (displays.keeping) displays.keeping = false; else displays.apply() } }
            }
        }
    }
}
