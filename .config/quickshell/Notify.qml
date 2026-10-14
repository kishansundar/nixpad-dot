pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notifications: the shell is the desktop's notification service; it keeps each notification until it is dismissed, and says which ones are showing as pop-ups
Singleton {
    id: notify

    // Everything not yet dismissed, newest first, and how many
    readonly property var all: server.trackedNotifications.values.slice().reverse()
    readonly property int count: all.length
    // Do not disturb: a new notification goes straight to the list without a pop-up, unless it is critical
    property bool dnd: false
    // The ones showing as pop-ups, newest first (five at most), and the monitor they show on: the one mango had focused when the newest arrived
    property var popups: []
    property var screen: null
    // When each arrived (ms since 1970) by its id, for "3 MIN AGO"
    property var arrived: ({})

    NotificationServer {
        id: server
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: note => {
            note.tracked = true
            // When it is closed, by whoever, it leaves the pop-ups and its arrival time is forgotten
            const id = note.id
            note.closed.connect(() => { notify.hide(note); const left = notify.arrived; delete left[id]; notify.arrived = left })
            // An app that sends the same notification again with new words (a chat's "3 new messages") is shown again
            note.summaryChanged.connect(() => notify.show(note))
            note.bodyChanged.connect(() => notify.show(note))
            notify.show(note)
        }
    }
    // show: its time starts now and it pops up, unless do not disturb holds it back
    function show(note) {
        const times = arrived
        times[note.id] = Date.now()
        arrived = times
        if (dnd && note.urgency !== NotificationUrgency.Critical) return
        Panels.focused(monitor => notify.screen = monitor)
        popups = [note].concat(popups.filter(p => p !== note)).slice(0, 5)
    }
    // Opening the calendar panel takes the pop-ups away: everything is in its list
    Connections { target: Panels; function onOpenChanged() { if (Panels.open === "calendar") notify.popups = [] } }

    // hide: the pop-up goes, the notification stays in the list; dismiss: it is gone for good; clear: all of them are
    function hide(note) { popups = popups.filter(p => p !== note) }
    function dismiss(note) { hide(note); note.dismiss() }
    function clear() { popups = []; for (const note of server.trackedNotifications.values.slice()) note.dismiss() }

    // An app may offer actions with a notification: the one named "default" is what a click on the notification does (usually: show the app's window), the others are drawn as buttons
    function main(note) { for (let i = 0; i < note.actions.length; i++) if (note.actions[i].identifier === "default") return note.actions[i]; return null }
    function buttons(note) { const list = []; for (let i = 0; i < note.actions.length; i++) if (note.actions[i].identifier !== "default") list.push(note.actions[i]); return list }
    // Doing an action also dismisses the notification (the service does that itself unless the app marked it to stay)
    function act(note, action) { hide(note); action.invoke() }
    // Who sent what: the service is told an app's name but not its process, so the bus is listened to as well, and the sender of each of the last 40 notifications is kept by app name, title and text (with several terminals open, this is what tells them apart)
    property var heard: []
    Process {
        running: true
        command: ["busctl", "--user", "--json=short", "monitor", "--match", "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const call = JSON.parse(line), sent = call.payload.data
                    notify.heard = [{ sender: call.sender, key: sent[0] + "\n" + sent[3] + "\n" + sent[4] }].concat(notify.heard).slice(0, 40)
                } catch (e) {}
            }
        }
    }
    // A click on a notification goes to its app: the app's "default" action first if it offers one, then mango is told to show the app's window unless the app has brought it up itself. The window is the one of the process that sent it; failing that it is found by app id: the desktop entry the app names, else its name. The calendar panel closes; a notification whose app has no window is only dismissed
    property var going: null
    Process {
        id: look
        command: ["sh", "-c", "sleep 0.3; busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s \"$1\" 2>/dev/null || echo; mmsg get all-clients", "sh", notify.going?.sender ?? ""]
        stdout: StdioCollector { onStreamFinished: notify.front(text) }
    }
    function open(note) {
        const key = note.appName + "\n" + note.summary + "\n" + note.body
        going = { entry: (note.desktopEntry ?? "").toLowerCase(), name: (note.appName ?? "").toLowerCase().replace(/\s+/g, ""), sender: heard.find(h => h.key === key)?.sender ?? "" }
        const action = main(note)
        if (action) act(note, action); else dismiss(note)
        if (Panels.open === "calendar") Panels.close()
        look.running = true
    }
    function front(answer) {
        const app = going
        going = null
        if (!app) return
        const lines = answer.split("\n")
        const pid = Number(/^u (\d+)/.exec(lines[0])?.[1] ?? 0)
        let clients = []
        try { clients = JSON.parse(lines.slice(1).join("\n")).clients ?? [] } catch (e) {}
        const own = pid ? clients.filter(c => c.pid === pid) : []
        const mine = c => { const id = c.appid.toLowerCase(); return id.length > 2 && (id === app.entry || (app.entry !== "" && id.split(".").pop() === app.entry.split(".").pop()) || app.name.startsWith(id)) }
        if (own.length ? own.some(c => c.is_focused) : clients.some(c => c.is_focused && mine(c))) return
        const client = own[0] ?? clients.find(mine)
        if (client) Quickshell.execDetached(["mmsg", "dispatch", "focusid", "client," + client.id])
    }

    // How long a pop-up stays, in ms: what the app asks for (Quickshell hands on the app's milliseconds as they are, though its docs say seconds), else 10 seconds, 5 for low urgency, and 0 (until dismissed) for critical
    function lasts(note) {
        return note.expireTimeout > 0 ? note.expireTimeout : note.urgency === NotificationUrgency.Critical ? 0 : note.urgency === NotificationUrgency.Low ? 5000 : 10000
    }
    // Its picture: the image the app sent, else the app's icon by file or by name ("" when there is none)
    function picture(note) {
        if (note.image) return note.image
        const icon = note.appIcon
        return !icon ? "" : icon.startsWith("/") ? "file://" + icon : icon.includes("://") ? icon : Quickshell.iconPath(icon, true)
    }
    // How long ago it arrived, in words, at the time given
    function age(note, now) {
        const seconds = Math.max(0, (now - (arrived[note.id] ?? now)) / 1000)
        return seconds < 60 ? "NOW" : seconds < 3600 ? Math.floor(seconds / 60) + " MIN AGO" : seconds < 86400 ? Math.floor(seconds / 3600) + " H AGO" : Math.floor(seconds / 86400) + " D AGO"
    }
}
