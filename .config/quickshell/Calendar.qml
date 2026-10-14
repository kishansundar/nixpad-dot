import QtQuick
import Quickshell
import Quickshell.Wayland

// The calendar (a click on the bar's clock): the time in large figures, then the day, the month and the year, each drawn as steps with what has gone in grey and now in the accent; the arrows, the wheel or a click on a month move through the months; under them the notifications not yet dismissed, which Ctrl+Alt+\ opens too
PanelWindow {
    id: calendar
    visible: Panels.open === "calendar"
    screen: Panels.screen
    // Under the clock at the right end of the bar, one gap below it
    anchors { top: true; right: true }
    margins { top: Theme.gap; right: Theme.gap }
    exclusiveZone: 0
    implicitWidth: 30 + 7 * 44 + 32 + 2 * Theme.thick
    implicitHeight: body.height + 2 * Theme.thick
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    // It holds the keyboard while it is open, for the keys of the notifications
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // How many months the page is away from this month
    property int shift: 0
    SystemClock { id: clock; enabled: calendar.visible; precision: SystemClock.Minutes }
    readonly property date first: new Date(clock.date.getFullYear(), clock.date.getMonth() + shift, 1)
    // The start of today, which parts the days that have gone from those to come
    readonly property date midnight: new Date(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate())
    // The weekday the week starts on here (0 is Sunday), and how many days of the month before fill the first row
    readonly property int weekStart: Qt.locale().firstDayOfWeek
    readonly property int lead: (first.getDay() - weekStart + 7) % 7
    onVisibleChanged: if (visible) { shift = 0; keys.forceActiveFocus() }
    // When the notifications last changed: the panel then changes its height under the pointer
    property real resized: 0
    Connections { target: Notify; function onCountChanged() { calendar.resized = Date.now() } }

    Item {
        anchors.fill: parent

        Ui.Frame { anchors.fill: parent; focused: true }
        // C clears the notifications, D switches do not disturb, Esc closes
        Item {
            id: keys
            Keys.onPressed: event => {
                if (event.key === Qt.Key_C) Notify.clear()
                else if (event.key === Qt.Key_D) Notify.dnd = !Notify.dnd
                else if (event.key === Qt.Key_Escape) Panels.close()
            }
        }
        // The panel closes shortly after the pointer leaves it; a leave that comes because a removed notification made the panel shorter does not count
        HoverHandler { onHoveredChanged: if (hovered) leave.stop(); else if (Date.now() - calendar.resized > 300) leave.restart() }
        Timer { id: leave; interval: 600; onTriggered: if (calendar.visible) Panels.close() }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: wheel => calendar.shift += wheel.angleDelta.y > 0 ? -1 : 1 }

        Column {
            id: body
            x: Theme.thick; y: Theme.thick
            width: parent.width - 2 * Theme.thick

            Ui.Head { title: "TIME / CALENDAR"; kana: "カレンダー"; note: Qt.formatDateTime(clock.date, "t") + "  /  UTC " + clock.date.toISOString().slice(11, 16) }
            Ui.Line { width: parent.width }
            Item {
                width: parent.width; height: 96
                Ui.Value { x: 16; anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDateTime(clock.date, "HH:mm"); font: Theme.heroFont }
                Column {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    Ui.Label { anchors.right: parent.right; text: Qt.formatDateTime(clock.date, "dddd").toUpperCase() }
                    Ui.Value { anchors.right: parent.right; text: Qt.formatDateTime(clock.date, "dd MMM yyyy").toUpperCase() }
                    Ui.Label { anchors.right: parent.right; text: "WEEK " + Sys.week(clock.date); color: Theme.muted }
                }
            }
            Ui.Line { width: parent.width }

            Ui.Section {
                title: "01 / DAY"
                Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: Math.round((clock.date.getHours() * 60 + clock.date.getMinutes()) / 14.4) + "% GONE"; color: Theme.muted }
            }
            // The day as 24 hours in four groups of six, each named by its first hour: hours gone are grey, this hour is in the accent, hours to come are dark
            Row {
                x: 16
                spacing: 11
                Repeater {
                    model: 4
                    Column {
                        id: quarter
                        required property int index
                        spacing: 5
                        Row {
                            spacing: 2
                            Repeater {
                                model: 6
                                Rectangle {
                                    required property int index
                                    readonly property int hour: quarter.index * 6 + index
                                    width: 11; height: 11
                                    color: hour === clock.date.getHours() ? Theme.accent : hour < clock.date.getHours() ? Theme.strong : Theme.surface2
                                }
                            }
                        }
                        Ui.Label { text: Sys.two(quarter.index * 6); color: Theme.muted }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Ui.Line { width: parent.width }

            // The month on show between two arrows; a click on its name returns to this month
            Item {
                width: parent.width; height: 36
                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "02 / MONTH"; color: Theme.muted }
                Row {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Ui.Value { text: "<"; color: back.hovered ? Theme.accent : Theme.text2; HoverHandler { id: back; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: calendar.shift -= 1 } }
                    Ui.Value { text: Qt.formatDateTime(calendar.first, "MMMM yyyy").toUpperCase(); color: calendar.shift === 0 ? Theme.text : Theme.accent; HoverHandler { cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: calendar.shift = 0 } }
                    Ui.Value { text: ">"; color: next.hovered ? Theme.accent : Theme.text2; HoverHandler { id: next; cursorShape: Qt.PointingHandCursor } TapHandler { onTapped: calendar.shift += 1 } }
                }
            }
            Row {
                x: 16

                // The week number of each row (taken from the row's fourth day); this week's is white
                Column {
                    Ui.Label { width: 30; height: 24; verticalAlignment: Text.AlignVCenter; text: "WK"; color: Theme.muted }
                    Repeater {
                        model: 6
                        Ui.Label {
                            required property int index
                            readonly property int week: Sys.week(new Date(calendar.first.getFullYear(), calendar.first.getMonth(), 1 - calendar.lead + index * 7 + 3))
                            width: 30; height: 30
                            verticalAlignment: Text.AlignVCenter
                            text: Sys.two(week)
                            color: calendar.shift === 0 && week === Sys.week(clock.date) ? Theme.text : Theme.muted
                        }
                    }
                }
                Grid {
                    columns: 7

                    Repeater {
                        model: 7
                        Ui.Label {
                            required property int index
                            width: 44; height: 24
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: Qt.locale().dayName((index + calendar.weekStart) % 7, Locale.ShortFormat).toUpperCase()
                            color: Theme.muted
                        }
                    }
                    Repeater {
                        model: 42

                        // One day: today is the accent block, days gone are grey, days to come white, days of the months before and after dark
                        Rectangle {
                            id: cell
                            required property int index
                            readonly property date day: new Date(calendar.first.getFullYear(), calendar.first.getMonth(), 1 - calendar.lead + index)
                            readonly property bool today: day.getTime() === calendar.midnight.getTime()
                            width: 44; height: 30
                            color: today ? Theme.accent : "transparent"
                            Ui.Value { anchors.centerIn: parent; text: Sys.two(cell.day.getDate()); color: cell.today ? Theme.accentInk : cell.day.getMonth() !== calendar.first.getMonth() ? Theme.muted : cell.day < calendar.midnight ? Theme.text2 : Theme.text }
                        }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Ui.Line { width: parent.width }

            Ui.Section {
                title: "03 / YEAR"
                Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: calendar.first.getFullYear() === clock.date.getFullYear() ? "DAY " + Sys.dayOfYear(clock.date) + " OF " + Sys.daysInYear(clock.date) : String(calendar.first.getFullYear()); color: Theme.muted }
            }
            Row {
                x: 16
                spacing: 2
                Repeater {
                    model: 12

                    // One month of the year on show: this month is the accent block, the month on show has the accent frame, months gone are grey; a click shows it
                    Rectangle {
                        id: month
                        required property int index
                        readonly property bool now: calendar.first.getFullYear() === clock.date.getFullYear() && index === clock.date.getMonth()
                        readonly property bool shown: index === calendar.first.getMonth()
                        readonly property bool gone: new Date(calendar.first.getFullYear(), index + 1, 1) <= calendar.midnight
                        width: 26; height: 26
                        color: now ? Theme.accent : over.hovered ? Theme.surface : "transparent"
                        border { width: shown && !now ? Theme.thick : Theme.thin; color: shown || now ? Theme.accent : Theme.border }
                        Ui.Label { anchors.centerIn: parent; text: Sys.two(month.index + 1); color: month.now ? Theme.accentInk : month.gone ? Theme.text2 : Theme.text }
                        HoverHandler { id: over; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: calendar.shift += month.index - calendar.first.getMonth() }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Ui.Line { width: parent.width }

            // The notifications not yet dismissed: the do not disturb switch, clear all, then the list, newest first, which scrolls once it would run off the screen
            Ui.Section {
                title: "04 / NOTIFICATIONS"
                Ui.Label { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: Notify.count === 0 ? "NONE" : Sys.two(Notify.count) + " WAITING"; color: Theme.muted }
            }
            Ui.Switch { label: "DO NOT DISTURB"; note: "NO POP-UPS"; on: Notify.dnd; onFlipped: Notify.dnd = !Notify.dnd }
            Rectangle {
                visible: Notify.count > 0
                width: parent.width; height: Theme.row
                color: wipe.containsMouse ? Theme.surface : "transparent"
                Ui.Label { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "X"; color: Theme.muted }
                Ui.Value { x: 36; anchors.verticalCenter: parent.verticalCenter; text: "CLEAR ALL" }
                MouseArea { id: wipe; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Notify.clear() }
            }
            Item {
                visible: Notify.count > 0
                width: parent.width; height: flick.height
                // A turn of the wheel over the list never turns the month
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: wheel => wheel.accepted = true }
                Flickable {
                    id: flick
                    width: parent.width
                    height: Math.min(list.height, Math.max(90, (calendar.screen?.height ?? 1080) - 720))
                    contentHeight: list.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: list
                        width: parent.width
                        Repeater {
                            model: Notify.all
                            Column {
                                id: entry
                                required property var modelData
                                width: list.width
                                Ui.Line { width: parent.width }
                                Notifications.Note { width: parent.width; height: implicitHeight; note: entry.modelData; now: clock.date.getTime() }
                            }
                        }
                    }
                }
            }
            Ui.Line { width: parent.width }
            Ui.Foot { keys: "C: CLEAR ALL  /  D: QUIET  /  ESC: CLOSE" }
        }
    }
}
