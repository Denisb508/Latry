from pathlib import Path

HOME = Path('android/HomePage.qml')
s = HOME.read_text()
changed = False

# Add FRN room model.
old = '    property var frnUsers: []\n    property string frnStatusMessage: ""\n'
new = '    property var frnUsers: []\n    property var frnRooms: []\n    property string frnStatusMessage: ""\n'
if old in s:
    s = s.replace(old, new, 1)
    changed = True

# SvxReflector: keep every callsign and include own connected profile callsign.
start = s.find('    function normalizedReflectorUsers(nodes) {')
end = s.find('\n    function addReflectorUser(callsign)', start)
if start >= 0 and end > start:
    block = '''    function normalizedReflectorUsers(nodes) {
        const result = []
        if (nodes && Array.isArray(nodes)) {
            for (let i = 0; i < nodes.length; ++i) {
                const cs = String(nodes[i] || "").trim().toUpperCase()
                if (cs.length > 0 && result.indexOf(cs) < 0)
                    result.push(cs)
            }
        }

        const ownCallsign = String(page.selectedProfileCallsign || "").trim().toUpperCase()
        if (!page.reflectorClient.isDisconnected
                && ownCallsign.length > 0
                && result.indexOf(ownCallsign) < 0)
            result.push(ownCallsign)

        result.sort()
        return result
    }
'''
    if s[start:end] != block.rstrip('\n'):
        s = s[:start] + block + s[end+1:]
        changed = True

# Fix incremental joined/left handling now that normalizer also adds self.
start = s.find('    function addReflectorUser(callsign) {')
end = s.find('\n    function removeReflectorUser(callsign)', start)
if start >= 0 and end > start:
    block = '''    function addReflectorUser(callsign) {
        const cs = String(callsign || "").trim().toUpperCase()
        const next = reflectorUsers.slice()
        if (cs.length === 0 || next.indexOf(cs) >= 0)
            return
        next.push(cs)
        next.sort()
        reflectorUsers = next
    }
'''
    if s[start:end] != block.rstrip('\n'):
        s = s[:start] + block + s[end+1:]
        changed = True

start = s.find('    function removeReflectorUser(callsign) {')
end = s.find('\n    function normalizedFrnUsers(items)', start)
if start >= 0 and end > start:
    block = '''    function removeReflectorUser(callsign) {
        const cs = String(callsign || "").trim().toUpperCase()
        const ownCallsign = String(page.selectedProfileCallsign || "").trim().toUpperCase()
        if (cs === ownCallsign && !page.reflectorClient.isDisconnected)
            return

        const next = reflectorUsers.slice()
        const idx = next.indexOf(cs)
        if (idx >= 0) {
            next.splice(idx, 1)
            reflectorUsers = next
        }
    }
'''
    if s[start:end] != block.rstrip('\n'):
        s = s[:start] + block + s[end+1:]
        changed = True

# Preserve FRN room + portal status color instead of flattening to strings.
start = s.find('    function normalizedFrnUsers(items) {')
end = s.find('\n    function refreshFrnUsers()', start)
if start >= 0 and end > start:
    block = '''    function normalizedFrnUsers(items) {
        const result = []
        if (!items || !Array.isArray(items))
            return result

        for (let i = 0; i < items.length; ++i) {
            const value = items[i]
            if (!value || typeof value !== "object")
                continue

            const display = String(value.display || value.callsign || value.name || value.user || "").trim()
            if (display.length === 0)
                continue

            let statusColor = String(value.status_color || "gray").trim().toLowerCase()
            if (["green", "yellow", "gray"].indexOf(statusColor) < 0)
                statusColor = "gray"

            result.push({
                display: display,
                callsign: String(value.callsign || "").trim().toUpperCase(),
                name: String(value.name || "").trim(),
                room: String(value.room || "FRN").trim(),
                statusColor: statusColor,
                statusText: String(value.status_text || "").trim(),
                state: Number(value.state || 0)
            })
        }

        result.sort(function(a, b) {
            const roomCmp = a.room.localeCompare(b.room)
            return roomCmp !== 0 ? roomCmp : a.display.localeCompare(b.display)
        })
        return result
    }

    function normalizedFrnRooms(items, users) {
        const result = []
        const seen = []

        if (items && Array.isArray(items)) {
            for (let i = 0; i < items.length; ++i) {
                const value = items[i]
                if (!value || typeof value !== "object")
                    continue
                const name = String(value.name || "").trim()
                if (name.length === 0 || seen.indexOf(name) >= 0)
                    continue
                seen.push(name)
                result.push({
                    name: name,
                    online: value.online !== false,
                    count: Number(value.count || 0)
                })
            }
        }

        if (users && Array.isArray(users)) {
            for (let j = 0; j < users.length; ++j) {
                const room = String(users[j].room || "FRN").trim()
                if (seen.indexOf(room) < 0) {
                    seen.push(room)
                    result.push({name: room, online: true, count: 0})
                }
            }
        }

        return result
    }

    function frnUsersForRoom(roomName) {
        const result = []
        for (let i = 0; i < page.frnUsers.length; ++i) {
            if (page.frnUsers[i].room === roomName)
                result.push(page.frnUsers[i])
        }
        return result
    }
'''
    if s[start:end] != block.rstrip('\n'):
        s = s[:start] + block + s[end+1:]
        changed = True

# Read rooms from the common backend envelope.
old = '''                const users = Array.isArray(parsed) ? parsed : parsed.users
                page.frnUsers = page.normalizedFrnUsers(users)
                page.frnServerCount = envelope && parsed.count !== undefined
                        ? Number(parsed.count)
                        : page.frnUsers.length
'''
new = '''                const users = Array.isArray(parsed) ? parsed : parsed.users
                page.frnUsers = page.normalizedFrnUsers(users)
                page.frnRooms = page.normalizedFrnRooms(
                            envelope ? parsed.rooms : [], page.frnUsers)
                page.frnServerCount = envelope && parsed.count !== undefined
                        ? Number(parsed.count)
                        : page.frnUsers.length
'''
if old in s:
    s = s.replace(old, new, 1)
    changed = True

# Clear room data when FRN display is disabled.
old = '''        else {
            frnUsers = []
            frnStatusMessage = ""
            frnUpdated = ""
            frnServerCount = 0
        }
'''
new = '''        else {
            frnUsers = []
            frnRooms = []
            frnStatusMessage = ""
            frnUpdated = ""
            frnServerCount = 0
        }
'''
if old in s:
    s = s.replace(old, new, 1)
    changed = True

# Compact headings.
s = s.replace('font.pixelSize: page.uiMetrics.sectionTitleFontSize\n                            font.bold: true\n                            color: "#0f172a"',
              'font.pixelSize: Math.max(13, page.uiMetrics.captionFontSize + 1)\n                            font.bold: true\n                            color: "#0f172a"', 1)

# Compact Svx chips and red current talker.
old = '''                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool isTalking:
                                        String(page.reflectorClient.currentTalker || "").trim().toUpperCase() === modelData
                                    radius: 10
                                    color: isTalking ? "#fee2e2" : "#e8f5e9"
                                    border.color: isTalking ? "#ef4444" : "#86c98a"
                                    border.width: 1
                                    implicitWidth: userLabel.implicitWidth + 18
                                    implicitHeight: userLabel.implicitHeight + 10
                                    Label {
                                        id: userLabel
                                        anchors.centerIn: parent
                                        text: "● " + modelData
                                        color: parent.isTalking ? "#b91c1c" : "#216e2d"
                                        font.bold: true
                                    }
                                }
'''
new = '''                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool isTalking:
                                        String(page.reflectorClient.currentTalker || "").trim().toUpperCase() === modelData
                                    radius: 10
                                    color: isTalking ? "#fee2e2" : "#e8f5e9"
                                    border.color: isTalking ? "#ef4444" : "#86c98a"
                                    border.width: 1
                                    implicitWidth: userLabel.implicitWidth + 16
                                    implicitHeight: userLabel.implicitHeight + 8
                                    Label {
                                        id: userLabel
                                        anchors.centerIn: parent
                                        text: "● " + modelData
                                        color: parent.isTalking ? "#b91c1c" : "#216e2d"
                                        font.pixelSize: page.uiMetrics.captionFontSize
                                        font.bold: true
                                    }
                                }
'''
if old in s:
    s = s.replace(old, new, 1)
    changed = True

# Replace simple FRN chip flow with room-aware sections and portal status colors.
frn_flow_start = s.find('                        Flow {\n                            visible: page.showFrnUsers && page.frnUsers.length > 0')
frn_status_marker = '                        Label {\n                            visible: page.showFrnUsers && page.frnStatusMessage.length > 0'
frn_flow_end = s.find(frn_status_marker, frn_flow_start)
if frn_flow_start >= 0 and frn_flow_end > frn_flow_start:
    room_ui = '''                        Repeater {
                            model: page.showFrnUsers ? page.frnRooms : []

                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("%1 (%2)").arg(modelData.name).arg(modelData.count)
                                    font.pixelSize: page.uiMetrics.captionFontSize
                                    font.bold: true
                                    color: modelData.online ? "#475569" : "#94a3b8"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: page.frnUsersForRoom(modelData.name)

                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property string statusColor: modelData.statusColor || "gray"
                                            radius: 10
                                            color: statusColor === "green" ? "#ecfdf5"
                                                   : statusColor === "yellow" ? "#fffbeb"
                                                   : "#ffffff"
                                            border.color: statusColor === "green" ? "#86c98a"
                                                          : statusColor === "yellow" ? "#facc15"
                                                          : "#cbd5e1"
                                            border.width: 1
                                            implicitWidth: frnUserLabel.implicitWidth + 16
                                            implicitHeight: frnUserLabel.implicitHeight + 8

                                            Label {
                                                id: frnUserLabel
                                                anchors.centerIn: parent
                                                text: "● " + modelData.display
                                                color: parent.statusColor === "green" ? "#216e2d"
                                                       : parent.statusColor === "yellow" ? "#a16207"
                                                       : "#64748b"
                                                font.pixelSize: page.uiMetrics.captionFontSize
                                                font.bold: true
                                            }
                                        }
                                    }
                                }
                            }
                        }

'''
    s = s[:frn_flow_start] + room_ui + s[frn_flow_end:]
    changed = True

# Ensure activity and section headings are compact even if already partially patched.
old = 'text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)\n                            font.bold: true'
new = 'text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)\n                            font.pixelSize: page.uiMetrics.captionFontSize\n                            font.bold: true'
if old in s:
    s = s.replace(old, new, 1)
    changed = True

old = 'text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)\n                            font.bold: true'
new = 'text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)\n                            font.pixelSize: page.uiMetrics.captionFontSize\n                            font.bold: true'
if old in s:
    s = s.replace(old, new, 1)
    changed = True

if not changed:
    print('Gateway activity UI already up to date.')
    raise SystemExit(0)

HOME.write_text(s)
print('Gateway activity updated: FRN rooms/status colors, compact fonts, own callsign, red talker.')
