import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page

    required property real contentPadding
    required property real safeAreaTop
    required property real safeAreaLeft
    required property real safeAreaRight
    required property real safeAreaBottom
    required property var uiMetrics
    required property color surfaceColor
    required property color borderColor
    required property var selectedProfile
    required property int profilesCount
    required property string selectedProfileEndpoint
    required property string selectedProfileMeta
    required property bool canConnect
    required property int currentTalkgroup
    required property bool canSwitchProfile
    required property bool canSwitchTalkgroup
    required property bool profileSwitchInProgress
    required property string pendingProfileName
    required property real rxMeterLevel
    required property real rxMeterPeakLevel
    required property real txMeterLevel
    required property real txMeterPeakLevel
    required property var reflectorClient
    required property bool tapToTalkButtonVisible
    required property bool showReflectorUsers
    required property bool showFrnUsers

    property var reflectorUsers: []
    property var frnUsers: []
    property var frnRooms: []
    property string frnStatusMessage: ""
    property string frnUpdated: ""
    property int frnServerCount: 0
    property var activeTalker: ({})
    property var talkerHistory: []
    property var selectedTalkerDetails: ({})
    property var frnTalkers: ({})
    property string activityUsersTitle: ""
    property string activityUsersSource: ""
    property string activityUsersRoom: ""
    property int activityUsersTalkgroup: 0
    readonly property string frnStatusUrl: "https://svxportal.pmr446.si/frn_users.json"
    readonly property string frnSlovenijaTalkerUrl: "https://svxportal.pmr446.si/frn_slovenija_proxy.php"
    readonly property string frnObalaTalkerUrl: "https://svxportal.pmr446.si/frn_obala_public_proxy.php"

    signal openSettingsRequested()
    signal openAdminRequested()
    signal openProfileSwitcherRequested()
    signal openTalkgroupSwitcherRequested()
    signal connectRequested()
    signal disconnectRequested()
    signal shutdownRequested()
    signal pttRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Home")

    readonly property bool compactMode: page.uiMetrics.isSinglePaneScreen
    readonly property int compactPttButtonHeight: page.compactMode ? 56 : page.uiMetrics.pttButtonHeight
    readonly property bool androidRangeAccessibilityWorkaround: Qt.platform.os === "android"
    readonly property string selectedProfileName: page.selectedProfile && page.selectedProfile.name
                                                  ? page.selectedProfile.name
                                                  : qsTr("No saved server profile")
    readonly property string selectedProfileCallsign: page.selectedProfile && page.selectedProfile.callsign
                                                      ? page.selectedProfile.callsign
                                                      : ""
    readonly property bool liveTranscriptionVisible: page.uiMetrics.liveTranscriptionAllowed
                                                    && page.reflectorClient.liveTranscriptionEnabled
                                                    && page.reflectorClient.transcriptionText.length > 0

    function frnTalkgroupForRoom(roomName) {
        const room = String(roomName || "").toLowerCase()

        if (room.indexOf("obala") >= 0)
            return 3276

        if (room.indexOf("slovenija") >= 0)
            return 327

        return 0
    }

    function isActivityUserTalking(source, room, callsign) {
        if (!page.activeTalker || !page.activeTalker.callsign)
            return false

        if (String(page.activeTalker.source || "") !== String(source || ""))
            return false

        if (String(source || "") === "FRN"
                && String(page.activeTalker.room || "") !== String(room || ""))
            return false

        return String(page.activeTalker.callsign || "").toUpperCase()
                === String(callsign || "").toUpperCase()
    }

    function activityUsers() {
        const result = []

        if (page.activityUsersSource === "SvxReflector") {
            for (let i = 0; i < page.reflectorUsers.length; ++i) {
                const callsign = String(page.reflectorUsers[i] || "").trim()

                result.push({
                    source: "SvxReflector",
                    room: "SvxReflector",
                    talkgroup: page.activityUsersTalkgroup,
                    callsign: callsign,
                    display: callsign,
                    name: "",
                    location: "",
                    active: page.isActivityUserTalking(
                                "SvxReflector",
                                "SvxReflector",
                                callsign)
                })
            }
        } else if (page.activityUsersSource === "FRN") {
            const users = page.frnUsersForRoom(page.activityUsersRoom)

            for (let j = 0; j < users.length; ++j) {
                const user = users[j]

                result.push({
                    source: "FRN",
                    room: page.activityUsersRoom,
                    talkgroup: page.activityUsersTalkgroup,
                    callsign: user.callsign,
                    display: user.display,
                    name: user.name,
                    location: user.location || "",
                    client: user.client || "",
                    active: page.isActivityUserTalking(
                                "FRN",
                                page.activityUsersRoom,
                                user.callsign)
                })
            }
        }

        // GOVOREC vedno prvi, ostali pod njim.
        result.sort(function(a, b) {
            if (a.active && !b.active)
                return -1
            if (!a.active && b.active)
                return 1

            return String(a.display || "").localeCompare(
                        String(b.display || ""))
        })

        return result
    }

    function openActivityUsers(title, source, room, talkgroup) {
        page.activityUsersTitle = title
        page.activityUsersSource = source
        page.activityUsersRoom = room
        page.activityUsersTalkgroup = talkgroup
        activityUsersPopup.open()
    }

    function talkerPath(item) {
        if (!item)
            return ""

        const tg = Number(item.talkgroup || 0)
        const tgText = tg > 0 ? "TG " + tg : "TG"

        if (String(item.source || "") === "FRN") {
            return String(item.room || "FRN")
                    + " → " + tgText
                    + " → SvxReflector → Latry"
        }

        if (String(item.source || "") === "SvxReflector") {
            return "SvxReflector → " + tgText + " → Latry"
        }

        return String(item.source || "")
                + (tg > 0 ? " → " + tgText : "")
                + " → Latry"
    }

    function openTalkerDetails(item) {
        if (!item || !item.callsign)
            return

        page.selectedTalkerDetails = item
        talkerDetailsPopup.open()
    }

    function talkerKey(item) {
        if (!item)
            return ""
        return String(item.source || "") + "|" +
               String(item.room || "") + "|" +
               String(item.callsign || "")
    }

    function rememberTalker(item) {
        if (!item || !item.callsign)
            return

        const key = page.talkerKey(item)
        const next = []

        for (let i = 0; i < page.talkerHistory.length; ++i) {
            if (page.talkerKey(page.talkerHistory[i]) !== key)
                next.push(page.talkerHistory[i])
        }

        next.push(item)

        while (next.length > 30)
            next.shift()

        page.talkerHistory = next
    }

    function setActiveTalker(item) {
        if (!item || !item.callsign) {
            if (page.activeTalker && page.activeTalker.callsign)
                page.rememberTalker(page.activeTalker)

            page.activeTalker = ({})
            return
        }

        if (page.talkerKey(page.activeTalker) !== page.talkerKey(item)
                && page.activeTalker
                && page.activeTalker.callsign)
            page.rememberTalker(page.activeTalker)

        page.activeTalker = item
    }

    function syncSvxTalker() {
        const callsign =
                String(page.reflectorClient.currentTalker || "")
                    .trim().toUpperCase()

        if (callsign.length === 0) {
            if (page.activeTalker
                    && page.activeTalker.source === "SvxReflector")
                page.setActiveTalker({})
            return
        }

        // FRN bridge callsigna ne kažemo kot govorca.
        // Pravega FRN uporabnika dobimo iz FRN proxy-ja.
        if (page.isHiddenGatewayCallsign(callsign))
            return

        const name =
                String(page.reflectorClient.currentTalkerName || "").trim()

        page.setActiveTalker({
            active: true,
            source: "SvxReflector",
            room: "SvxReflector",
            talkgroup: page.currentTalkgroup,
            callsign: callsign,
            name: name,
            location: "",
            display: name.length > 0
                     ? callsign + ", " + name
                     : callsign
        })
    }

    function syncActiveFrnTalker() {
        const keys = ["slovenija", "obala"]
        let current = null

        for (let i = 0; i < keys.length; ++i) {
            const item = page.frnTalkers[keys[i]]
            if (item && item.active && item.callsign) {
                current = item
                break
            }
        }

        if (current) {
            page.setActiveTalker(current)
            return
        }

        if (page.activeTalker
                && page.activeTalker.source === "FRN")
            page.setActiveTalker({})
    }

    function refreshFrnTalker(key, url, fallbackRoom, talkgroup) {
        const xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            const next = Object.assign({}, page.frnTalkers)

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = JSON.parse(xhr.responseText)
                    const talker = data.talker || {}
                    const callsign =
                            String(talker.callsign || "").trim().toUpperCase()

                    if (talker.active && callsign.length > 0) {
                        const name = String(talker.name || "").trim()
                        const room =
                                String(data.gateway || fallbackRoom).trim()

                        next[key] = {
                            active: true,
                            source: "FRN",
                            room: room,
                            talkgroup: talkgroup,
                            callsign: callsign,
                            name: name,
                            location: String(talker.location || "").trim(),
                            display: name.length > 0
                                     ? callsign + ", " + name
                                     : callsign
                        }
                    } else {
                        next[key] = { active: false }
                    }
                } catch (error) {
                    console.warn("Invalid FRN talker JSON", key, error)
                    next[key] = { active: false }
                }
            } else {
                next[key] = { active: false }
            }

            page.frnTalkers = next
            page.syncActiveFrnTalker()
        }

        xhr.open("GET", url + "?t=" + Date.now())
        xhr.send()
    }

    function talkgroupLabel(talkgroup) {
        return talkgroup === 0 ? qsTr("Monitor Mode") : qsTr("TG %1").arg(talkgroup)
    }

    function isHiddenGatewayCallsign(callsign) {
        const cs = String(callsign || "").trim().toUpperCase()

        return cs === "327FRSSLO"
                || cs === "327FRSOBALA"
    }

    function normalizedReflectorUsers(nodes) {
        const result = []
        if (nodes && Array.isArray(nodes)) {
            for (let i = 0; i < nodes.length; ++i) {
                const cs = String(nodes[i] || "").trim().toUpperCase()
                if (cs.length > 0
                        && !page.isHiddenGatewayCallsign(cs)
                        && result.indexOf(cs) < 0)
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
    function syncReflectorUsers() {
        if (page.reflectorClient.isDisconnected) {
            page.reflectorUsers = []
            return
        }

        page.reflectorUsers =
            page.normalizedReflectorUsers(page.reflectorClient.connectedNodes)
    }

    function addReflectorUser(callsign) {
        const cs = String(callsign || "").trim().toUpperCase()
        const next = reflectorUsers.slice()
        if (cs.length === 0
                || page.isHiddenGatewayCallsign(cs)
                || next.indexOf(cs) >= 0)
            return
        next.push(cs)
        next.sort()
        reflectorUsers = next
    }
    function removeReflectorUser(callsign) {
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
    function normalizedFrnUsers(items) {
        const result = []
        if (!items || !Array.isArray(items))
            return result

        for (let i = 0; i < items.length; ++i) {
            const value = items[i]
            if (!value || typeof value !== "object")
                continue

            const display = String(value.display || value.callsign || value.name || value.user || "").trim()
            const callsign = String(value.callsign || display).trim().toUpperCase()

            if (display.length === 0
                    || page.isHiddenGatewayCallsign(callsign))
                continue

            let statusColor = String(value.status_color || "gray").trim().toLowerCase()
            if (["green", "yellow", "gray"].indexOf(statusColor) < 0)
                statusColor = "gray"

            result.push({
                display: display,
                callsign: String(value.callsign || "").trim().toUpperCase(),
                name: String(value.name || "").trim(),
                room: String(value.room || "FRN").trim(),
                location: String(value.city || value.location || "").trim(),
                client: String(value.client || value.type || "").trim(),
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
    function refreshFrnUsers() {
        if (!page.showFrnUsers) {
            page.frnUsers = []
            page.frnStatusMessage = ""
            return
        }

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                page.frnStatusMessage = qsTr("FRN seznam trenutno ni dosegljiv.")
                return
            }

            try {
                const parsed = JSON.parse(xhr.responseText)
                const envelope = !Array.isArray(parsed) && parsed && typeof parsed === "object"
                const users = Array.isArray(parsed) ? parsed : parsed.users
                page.frnUsers = page.normalizedFrnUsers(users)
                page.frnRooms = page.normalizedFrnRooms(
                            envelope ? parsed.rooms : [], page.frnUsers)
                page.frnServerCount = envelope && parsed.count !== undefined
                        ? Number(parsed.count)
                        : page.frnUsers.length
                page.frnUpdated = envelope && parsed.updated
                        ? String(parsed.updated)
                        : ""
                page.frnStatusMessage = page.frnUsers.length === 0
                        ? qsTr("Trenutno ni prijavljenih FRN uporabnikov.")
                        : ""
            } catch (error) {
                console.warn("Invalid FRN users JSON", error)
                page.frnStatusMessage = qsTr("FRN seznam ima napačen format.")
            }
        }
        xhr.open("GET", page.frnStatusUrl + "?t=" + Date.now())
        xhr.send()
    }

    onShowFrnUsersChanged: {
        if (showFrnUsers)
            refreshFrnUsers()
        else {
            frnUsers = []
            frnRooms = []
            frnStatusMessage = ""
            frnUpdated = ""
            frnServerCount = 0
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: Qt.platform.os === "android"

        onTriggered: {
            if (!page.reflectorClient.consumeTalkerDetailsRequest())
                return

            if (page.activeTalker && page.activeTalker.callsign) {
                page.openTalkerDetails(page.activeTalker)
                return
            }

            if (page.talkerHistory.length > 0) {
                page.openTalkerDetails(
                            page.talkerHistory[page.talkerHistory.length - 1])
            }
        }
    }

    Timer {
        interval: 1
        repeat: false
        running: true
        onTriggered: page.syncReflectorUsers()
    }

    Timer {
        interval: 500
        repeat: true
        running: !page.reflectorClient.isDisconnected
        triggeredOnStart: true

        onTriggered: {
            page.refreshFrnTalker(
                        "slovenija",
                        page.frnSlovenijaTalkerUrl,
                        "FRN Slovenija",
                        327)

            page.refreshFrnTalker(
                        "obala",
                        page.frnObalaTalkerUrl,
                        "FRN Obala",
                        3276)
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: page.showFrnUsers
        triggeredOnStart: true
        onTriggered: page.refreshFrnUsers()
    }

    Connections {
        target: page.reflectorClient

        function onCurrentTalkerChanged() {
            page.syncSvxTalker()
        }

        function onCurrentTalkerNameChanged() {
            page.syncSvxTalker()
        }

        function onConnectedNodesChanged(nodes) {
            page.reflectorUsers = page.normalizedReflectorUsers(nodes)
        }

        function onNodeJoined(callsign) {
            page.addReflectorUser(callsign)
        }

        function onNodeLeft(callsign) {
            page.removeReflectorUser(callsign)
        }

        function onIsDisconnectedChanged() {
            page.syncReflectorUsers()
        }
    }

    Popup {
        id: activityUsersPopup

        anchors.centerIn: Overlay.overlay
        width: Math.min(page.width - 28, 390)
        height: Math.min(page.height - 80, 520)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 12

        background: Rectangle {
            radius: 14
            color: "#ffffff"
            border.color: "#cbd5e1"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Label {
                        Layout.fillWidth: true
                        text: page.activityUsersTitle
                        font.pixelSize: 15
                        font.bold: true
                        color: "#0f172a"
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("%1 uporabnikov")
                              .arg(page.activityUsers().length)
                        font.pixelSize: 10
                        color: "#64748b"
                    }
                }

                Button {
                    text: "✕"
                    flat: true
                    onClicked: activityUsersPopup.close()
                }
            }

            ListView {
                id: activityUsersList

                Layout.fillWidth: true
                Layout.fillHeight: true
                model: page.activityUsers()
                spacing: 7
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData

                    width: activityUsersList.width
                    height: modelData.active ? 64 : 58
                    radius: 10

                    color: modelData.active
                           ? "#fee2e2"
                           : "#f8fafc"

                    border.color: modelData.active
                                  ? "#ef4444"
                                  : "#cbd5e1"

                    border.width: modelData.active ? 2 : 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Label {
                            width: parent.width
                            visible: modelData.active
                            text: qsTr("● GOVORI")
                            font.pixelSize: 9
                            font.bold: true
                            color: "#b91c1c"
                        }

                        Label {
                            width: parent.width
                            text: String(modelData.display
                                         || modelData.callsign
                                         || "")
                            font.pixelSize: 12
                            font.bold: true
                            color: modelData.active
                                   ? "#b91c1c"
                                   : "#334155"
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            width: parent.width
                            text: String(modelData.room
                                         || modelData.source
                                         || "")
                                  + (modelData.talkgroup
                                     ? " • TG " + modelData.talkgroup
                                     : "")
                            font.pixelSize: 9
                            color: "#64748b"
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent

                        onClicked: {
                            activityUsersPopup.close()
                            page.openTalkerDetails(modelData)
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }

            Label {
                visible: page.activityUsers().length === 0
                Layout.fillWidth: true
                text: qsTr("Trenutno ni uporabnikov.")
                horizontalAlignment: Text.AlignHCenter
                color: "#64748b"
            }
        }
    }

    Popup {
        id: talkerDetailsPopup

        anchors.centerIn: Overlay.overlay
        width: Math.min(page.width - 32, 380)
        height: Math.min(page.height - 100, 390)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 14

        readonly property bool talkerActive:
            page.selectedTalkerDetails
            && page.selectedTalkerDetails.callsign
            && page.talkerKey(page.selectedTalkerDetails)
               === page.talkerKey(page.activeTalker)

        background: Rectangle {
            radius: 14
            color: "#ffffff"
            border.color: talkerDetailsPopup.talkerActive
                          ? "#ef4444"
                          : "#cbd5e1"
            border.width: talkerDetailsPopup.talkerActive ? 2 : 1
        }

        contentItem: ColumnLayout {
            spacing: 10

            RowLayout {
                Layout.fillWidth: true

                Label {
                    text: qsTr("Talker Details")
                    font.bold: true
                    font.pixelSize: 15
                    color: "#0f172a"
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "✕"
                    flat: true
                    onClicked: talkerDetailsPopup.close()
                }
            }

            Label {
                Layout.fillWidth: true
                text: talkerDetailsPopup.talkerActive
                      ? qsTr("● GOVORI")
                      : qsTr("ZADNJI GOVOREC")
                font.bold: true
                color: talkerDetailsPopup.talkerActive
                       ? "#b91c1c"
                       : "#64748b"
            }

            Label {
                Layout.fillWidth: true
                text: String(page.selectedTalkerDetails.display
                             || page.selectedTalkerDetails.callsign
                             || "")
                font.pixelSize: 17
                font.bold: true
                color: "#0f172a"
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: "#e2e8f0"
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Vir: %1")
                      .arg(String(page.selectedTalkerDetails.source || ""))
                wrapMode: Text.WordWrap
                color: "#334155"
            }

            Label {
                Layout.fillWidth: true
                visible: String(page.selectedTalkerDetails.room || "").length > 0
                text: qsTr("Soba: %1")
                      .arg(String(page.selectedTalkerDetails.room || ""))
                wrapMode: Text.WordWrap
                color: "#334155"
            }

            Label {
                Layout.fillWidth: true
                visible: Number(page.selectedTalkerDetails.talkgroup || 0) > 0
                text: "TG: " + Number(page.selectedTalkerDetails.talkgroup || 0)
                color: "#334155"
            }

            Label {
                Layout.fillWidth: true
                visible: String(page.selectedTalkerDetails.location || "").length > 0
                text: qsTr("Lokacija: %1")
                      .arg(String(page.selectedTalkerDetails.location || ""))
                wrapMode: Text.WordWrap
                color: "#334155"
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Pot signala:")
                font.bold: true
                color: "#334155"
            }

            Label {
                Layout.fillWidth: true
                text: page.talkerPath(page.selectedTalkerDetails)
                wrapMode: Text.WordWrap
                font.bold: true
                color: "#1d4ed8"
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    Popup {
        id: lastTalkerPopup

        anchors.centerIn: Overlay.overlay
        width: Math.min(page.width - 32, 360)
        height: Math.min(page.height - 80, 480)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: 12

        background: Rectangle {
            radius: 14
            color: "#ffffff"
            border.color: "#cbd5e1"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Label {
                    text: qsTr("Last Talkers")
                    font.bold: true
                    font.pixelSize: 15
                    color: "#0f172a"
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "✕"
                    flat: true
                    onClicked: lastTalkerPopup.close()
                }
            }

            // Trenutni govorec je vedno prvi in rdeč
            Rectangle {
                visible: page.activeTalker
                         && page.activeTalker.callsign
                Layout.fillWidth: true
                implicitHeight: 58
                radius: 10
                color: "#fee2e2"
                border.color: "#ef4444"

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Label {
                        width: parent.width
                        text: "● " + String(page.activeTalker.display || page.activeTalker.callsign || "")
                        font.bold: true
                        color: "#b91c1c"
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: String(page.activeTalker.room || page.activeTalker.source || "")
                              + (page.activeTalker.talkgroup
                                 ? " • TG " + page.activeTalker.talkgroup
                                 : "")
                        color: "#7f1d1d"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.openTalkerDetails(page.activeTalker)
                }
            }

            ListView {
                id: talkerHistoryList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: page.talkerHistory
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData

                    width: talkerHistoryList.width
                    height: 54
                    radius: 9
                    color: "#f8fafc"
                    border.color: "#cbd5e1"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Label {
                            width: parent.width
                            text: String(modelData.display || modelData.callsign || "")
                            font.bold: true
                            color: "#334155"
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            text: String(modelData.room || modelData.source || "")
                                  + (modelData.talkgroup
                                     ? " • TG " + modelData.talkgroup
                                     : "")
                            font.pixelSize: 11
                            color: "#64748b"
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.openTalkerDetails(modelData)
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }

            Label {
                visible: (!page.activeTalker || !page.activeTalker.callsign)
                         && page.talkerHistory.length === 0
                Layout.fillWidth: true
                text: qsTr("Še ni zabeleženih govorcev.")
                horizontalAlignment: Text.AlignHCenter
                color: "#64748b"
            }
        }
    }

    background: Rectangle {
        Accessible.ignored: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f7f9fd" }
            GradientStop { position: 1.0; color: "#eef3fb" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: page.contentPadding + page.safeAreaTop
        anchors.leftMargin: page.contentPadding + page.safeAreaLeft
        anchors.rightMargin: page.contentPadding + page.safeAreaRight
        anchors.bottomMargin: page.contentPadding + page.safeAreaBottom
        spacing: page.uiMetrics.pageSpacing

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(titleLabel.implicitHeight,
                                     shutdownButton.implicitHeight,
                                     settingsButton.implicitHeight)

            Label {
                id: titleLabel

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Latry by OB508")
                font.pixelSize: page.compactMode ? 14 : 16
                font.bold: true
            }

            Button {
                id: shutdownButton

                objectName: "shutdownButton"
                anchors.centerIn: parent
                flat: true
                display: AbstractButton.IconOnly
                implicitWidth: page.compactMode ? 36 : 40
                implicitHeight: page.compactMode ? 36 : 40
                leftPadding: page.compactMode ? 8 : 9
                rightPadding: page.compactMode ? 8 : 9
                topPadding: page.compactMode ? 8 : 9
                bottomPadding: page.compactMode ? 8 : 9
                icon.source: "assets/power_settings_new.svg"
                icon.width: page.compactMode ? 18 : 20
                icon.height: page.compactMode ? 18 : 20
                icon.color: shutdownButton.enabled ? "#b91c1c" : "#d19a9a"
                Accessible.name: qsTr("Disconnect and shut down app")
                Accessible.description: qsTr("Disconnect the current session and terminate Latry")

                background: Rectangle {
                    Accessible.ignored: true
                    radius: width / 2
                    color: shutdownButton.down ? "#fee2e2" : "#fff1f2"
                    border.color: shutdownButton.enabled ? "#fca5a5" : "#fecaca"
                    border.width: 1
                }
                onClicked: page.shutdownRequested()
            }

            Button {
                id: adminButton

                visible: page.reflectorClient.hasAdminAccess
                anchors.right: settingsButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "A"
                implicitWidth: page.compactMode ? 32 : 36
                leftPadding: 6
                rightPadding: 6
                Accessible.name: qsTr("Open Latry administration")
                onClicked: page.openAdminRequested()
            }

            Button {
                id: settingsButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: page.compactMode ? qsTr("Menu") : qsTr("Settings")
                Accessible.name: qsTr("Open settings")
                onClicked: page.openSettingsRequested()
            }
        }

        ScrollView {
            id: contentScroll

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical: ScrollBar {
                objectName: "homeVerticalScrollBar"
                Accessible.ignored: page.androidRangeAccessibilityWorkaround
            }

            contentWidth: availableWidth

            Column {
                id: contentColumn

                width: contentScroll.availableWidth
                spacing: page.compactMode ? 8 : 10

                Label {
                    width: parent.width
                    text: page.reflectorClient.connectionStatus
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: page.uiMetrics.statusFontSize
                }


                Frame {
                    width: parent.width
                    visible: page.showReflectorUsers || page.showFrnUsers
                    padding: page.uiMetrics.sectionPadding
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Gateway activity")

                    background: Rectangle {
                        Accessible.ignored: true
                        radius: page.uiMetrics.frameRadius
                        color: page.surfaceColor
                        border.color: page.borderColor
                    }

                    contentItem: ColumnLayout {
                        spacing: 8

                        Label {
                            text: qsTr("Aktivnosti na prehodih")
                            font.pixelSize: page.compactMode ? 12 : 13
                            font.bold: true
                            color: "#0f172a"
                        }

                        RowLayout {
                            id: activityColumns
                            Layout.fillWidth: true
                            spacing: 8

                            // LEVO
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 6

                                // LAST TALKER
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 60
                                    radius: 10

                                    color: page.activeTalker
                                           && page.activeTalker.callsign
                                           ? "#fee2e2"
                                           : "#f8fafc"

                                    border.color: page.activeTalker
                                                  && page.activeTalker.callsign
                                                  ? "#ef4444"
                                                  : "#cbd5e1"

                                    readonly property var shownTalker:
                                        page.activeTalker
                                        && page.activeTalker.callsign
                                        ? page.activeTalker
                                        : (page.talkerHistory.length > 0
                                           ? page.talkerHistory[
                                                 page.talkerHistory.length - 1]
                                           : ({}))

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 2

                                        Label {
                                            width: parent.width
                                            text: qsTr("LAST TALKER")
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: "#64748b"
                                        }

                                        Label {
                                            width: parent.width

                                            text: parent.parent.shownTalker.callsign
                                                  ? ((page.activeTalker
                                                      && page.activeTalker.callsign
                                                      ? "● "
                                                      : "")
                                                     + String(
                                                         parent.parent.shownTalker.display
                                                         || parent.parent.shownTalker.callsign))
                                                  : qsTr("—")

                                            font.pixelSize: 10
                                            font.bold: true

                                            color: page.activeTalker
                                                   && page.activeTalker.callsign
                                                   ? "#b91c1c"
                                                   : "#334155"

                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            width: parent.width
                                            visible: parent.parent.shownTalker.callsign

                                            text: String(
                                                      parent.parent.shownTalker.room
                                                      || parent.parent.shownTalker.source
                                                      || "")
                                                  + (parent.parent.shownTalker.talkgroup
                                                     ? " • TG "
                                                       + parent.parent.shownTalker.talkgroup
                                                     : "")

                                            font.pixelSize: 9
                                            color: "#64748b"
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: lastTalkerPopup.open()
                                    }
                                }

                                // SVXREFLECTOR
                                Rectangle {
                                    visible: page.showReflectorUsers
                                    Layout.fillWidth: true
                                    implicitHeight: 58
                                    radius: 10

                                    readonly property bool talking:
                                        page.activeTalker
                                        && page.activeTalker.source
                                           === "SvxReflector"

                                    color: talking
                                           ? "#fee2e2"
                                           : "#ecfdf5"

                                    border.color: talking
                                                  ? "#ef4444"
                                                  : "#86c98a"

                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 3

                                        Label {
                                            width: parent.width

                                            text: qsTr("SvxReflector (%1)")
                                                  .arg(page.reflectorUsers.length)

                                            font.pixelSize: 10
                                            font.bold: true
                                            color: "#334155"
                                        }

                                        Label {
                                            width: parent.width

                                            text: parent.parent.talking
                                                  ? "● "
                                                    + String(
                                                        page.activeTalker.display
                                                        || page.activeTalker.callsign)
                                                  : qsTr("Tap → uporabniki ↑↓")

                                            font.pixelSize: 9
                                            font.bold: parent.parent.talking

                                            color: parent.parent.talking
                                                   ? "#b91c1c"
                                                   : "#216e2d"

                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent

                                        onClicked:
                                            page.openActivityUsers(
                                                "SvxReflector",
                                                "SvxReflector",
                                                "SvxReflector",
                                                page.currentTalkgroup)
                                    }
                                }
                            }

                            Rectangle {
                                visible: page.showReflectorUsers
                                         && page.showFrnUsers

                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                color: "#e2e8f0"
                            }

                            // DESNO - FRN
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 6

                                Label {
                                    visible: page.showFrnUsers
                                    Layout.fillWidth: true

                                    text: qsTr("FRN (%1)")
                                          .arg(page.frnServerCount)

                                    font.pixelSize: 10
                                    font.bold: true
                                    color: "#334155"
                                }

                                Repeater {
                                    model: page.showFrnUsers
                                           ? page.frnRooms
                                           : []

                                    delegate: Rectangle {
                                        required property var modelData

                                        Layout.fillWidth: true
                                        implicitHeight: 58
                                        radius: 10

                                        readonly property bool talking:
                                            page.activeTalker
                                            && page.activeTalker.source === "FRN"
                                            && page.activeTalker.room
                                               === modelData.name

                                        readonly property int roomTg:
                                            page.frnTalkgroupForRoom(
                                                modelData.name)

                                        color: talking
                                               ? "#fee2e2"
                                               : (modelData.online
                                                  ? "#ecfdf5"
                                                  : "#f8fafc")

                                        border.color: talking
                                                      ? "#ef4444"
                                                      : (modelData.online
                                                         ? "#86c98a"
                                                         : "#cbd5e1")

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 7
                                            spacing: 3

                                            Label {
                                                width: parent.width

                                                text: qsTr("%1 (%2)")
                                                      .arg(modelData.name)
                                                      .arg(modelData.count)

                                                font.pixelSize: 10
                                                font.bold: true
                                                color: "#334155"
                                                elide: Text.ElideRight
                                            }

                                            Label {
                                                width: parent.width

                                                text: parent.parent.talking
                                                      ? "● "
                                                        + String(
                                                            page.activeTalker.display
                                                            || page.activeTalker.callsign)
                                                      : qsTr("Tap → uporabniki ↑↓")

                                                font.pixelSize: 9
                                                font.bold: parent.parent.talking

                                                color: parent.parent.talking
                                                       ? "#b91c1c"
                                                       : "#216e2d"

                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent

                                            onClicked:
                                                page.openActivityUsers(
                                                    modelData.name,
                                                    "FRN",
                                                    modelData.name,
                                                    parent.roomTg)
                                        }
                                    }
                                }

                                Label {
                                    visible: page.showFrnUsers
                                             && page.frnStatusMessage.length > 0

                                    Layout.fillWidth: true
                                    text: page.frnStatusMessage
                                    wrapMode: Text.WordWrap
                                    color: "#64748b"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }

                Frame {
                    width: parent.width
                    padding: page.uiMetrics.sectionPadding
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Live session")

                    background: Rectangle {
                        Accessible.ignored: true
                        radius: page.uiMetrics.frameRadius
                        color: page.surfaceColor
                        border.color: page.borderColor
                    }

                    contentItem: ColumnLayout {
                        spacing: page.compactMode ? 4 : 6

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: qsTr("Live Session")
                                font.pixelSize: page.uiMetrics.captionFontSize
                                color: "#556070"
                            }

                            Item {
                                Layout.fillWidth: true
                                Accessible.ignored: true
                            }

                            Button {
                                id: disconnectButton
                                visible: !page.reflectorClient.isDisconnected
                                enabled: !page.profileSwitchInProgress
                                text: qsTr("Disconnect")
                                flat: true
                                leftPadding: 10
                                rightPadding: 10
                                topPadding: page.compactMode ? 4 : 5
                                bottomPadding: page.compactMode ? 4 : 5
                                Accessible.name: qsTr("Disconnect")
                                Accessible.description: qsTr("Disconnect the current session")

                                background: Rectangle {
                                    Accessible.ignored: true
                                    radius: 12
                                    color: disconnectButton.down ? "#fee2e2" : "transparent"
                                    border.color: disconnectButton.enabled ? "#ef4444" : "#f3b6b6"
                                    border.width: 1
                                }

                                contentItem: Label {
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: disconnectButton.text
                                    font.pixelSize: page.uiMetrics.captionFontSize
                                    font.bold: true
                                    color: disconnectButton.enabled ? "#b91c1c" : "#d19a9a"
                                }

                                onClicked: page.disconnectRequested()
                            }
                        }

                        Flow {
                            id: liveSessionProfileTitle

                            Layout.fillWidth: true
                            spacing: page.compactMode ? 6 : 8
                            Accessible.role: Accessible.StaticText
                            Accessible.name: page.selectedProfileCallsign.length > 0
                                             ? qsTr("%1 %2").arg(page.selectedProfileName).arg(page.selectedProfileCallsign)
                                             : page.selectedProfileName

                            Label {
                                objectName: "liveSessionProfileNameLabel"
                                text: page.selectedProfileName
                                font.pixelSize: page.uiMetrics.sectionTitleFontSize
                                font.bold: true
                                Accessible.ignored: true
                            }

                            Label {
                                objectName: "liveSessionProfileCallsignLabel"
                                visible: page.selectedProfileCallsign.length > 0
                                text: page.selectedProfileCallsign
                                font.pixelSize: page.uiMetrics.sectionTitleFontSize
                                font.bold: true
                                color: "#dc2626"
                                Accessible.ignored: true
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: page.selectedProfile
                                  ? page.selectedProfileEndpoint
                                  : qsTr("Add a server profile in Settings before connecting.")
                            wrapMode: Text.NoWrap
                            elide: Text.ElideMiddle
                            font.pixelSize: page.uiMetrics.bodyFontSize
                            color: "#334155"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: !!page.selectedProfile
                            radius: page.uiMetrics.nestedFrameRadius
                            color: "#f8fafc"
                            border.color: "#d7deee"
                            implicitHeight: meterLayout.implicitHeight + (page.compactMode ? 16 : 20)
                            Accessible.role: Accessible.Grouping
                            Accessible.name: qsTr("Audio meters")

                            ColumnLayout {
                                id: meterLayout

                                anchors.fill: parent
                                anchors.margins: page.uiMetrics.nestedSectionPadding
                                spacing: page.compactMode ? 6 : 8

                                RowLayout {
                                    Layout.fillWidth: true

                                    Label {
                                        text: qsTr("Audio")
                                        font.bold: true
                                        color: "#334155"
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: page.reflectorClient.pttActive
                                              ? qsTr("TX live")
                                              : (page.reflectorClient.isReceivingAudio
                                                 ? qsTr("RX live")
                                                 : qsTr("Idle"))
                                        color: "#556070"
                                        font.pixelSize: page.uiMetrics.captionFontSize
                                    }
                                }

                                AudioLevelMeter {
                                    Layout.fillWidth: true
                                    compact: page.compactMode
                                    labelText: qsTr("RX")
                                    level: page.rxMeterLevel
                                    peakLevel: page.rxMeterPeakLevel
                                    active: page.reflectorClient.isReceivingAudio
                                    accentColor: "#2563eb"
                                }

                                AudioLevelMeter {
                                    Layout.fillWidth: true
                                    compact: page.compactMode
                                    labelText: qsTr("TX")
                                    level: page.txMeterLevel
                                    peakLevel: page.txMeterPeakLevel
                                    active: page.reflectorClient.pttActive
                                    accentColor: "#dc2626"
                                }
                            }
                        }

                        Frame {
                            visible: page.liveTranscriptionVisible
                            Layout.fillWidth: true
                            padding: page.uiMetrics.nestedSectionPadding
                            Accessible.role: Accessible.Grouping
                            Accessible.name: qsTr("Live transcription")

                            background: Rectangle {
                                Accessible.ignored: true
                                radius: page.uiMetrics.nestedFrameRadius
                                color: "#e0f2fe"
                                border.color: "#7dd3fc"
                            }

                            contentItem: ColumnLayout {
                                spacing: 6

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Live Transcription")
                                    font.bold: true
                                    color: "#0f172a"
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: page.reflectorClient.transcriptionText
                                    wrapMode: Text.WordWrap
                                    color: "#0f172a"
                                    Accessible.role: Accessible.StaticText
                                    Accessible.name: text
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: width > (page.compactMode ? 260 : 320) ? 2 : 1
                            columnSpacing: page.compactMode ? 4 : 6
                            rowSpacing: page.compactMode ? 4 : 6
                            visible: !!page.selectedProfile

                            QuickSwitchTile {
                                Layout.fillWidth: true
                                compact: page.uiMetrics.isCompactScreen
                                labelText: qsTr("Profile")
                                primaryText: page.selectedProfile ? page.selectedProfile.name : qsTr("No profile")
                                secondaryText: page.canSwitchProfile
                                               ? (page.reflectorClient.isDisconnected
                                                  ? qsTr("Switch server")
                                                  : qsTr("Reconnect with another"))
                                               : (page.profilesCount > 1
                                                  ? qsTr("Switch unavailable now")
                                                  : qsTr("Add another profile"))
                                accentColor: "#2c5cff"
                                emphasized: true
                                enabled: page.canSwitchProfile
                                onClicked: page.openProfileSwitcherRequested()
                            }

                            QuickSwitchTile {
                                Layout.fillWidth: true
                                compact: page.uiMetrics.isCompactScreen
                                labelText: qsTr("Talkgroup")
                                primaryText: page.selectedProfile ? page.talkgroupLabel(page.currentTalkgroup) : qsTr("No TG")
                                secondaryText: page.selectedProfile
                                               ? (page.currentTalkgroup !== page.selectedProfile.talkgroup
                                                  ? qsTr("Default: %1").arg(page.talkgroupLabel(page.selectedProfile.talkgroup))
                                                  : (page.currentTalkgroup === 0 && !page.reflectorClient.isDisconnected
                                                     ? qsTr("Monitoring profile TGs")
                                                     : (page.reflectorClient.isDisconnected
                                                        ? qsTr("Change before connect")
                                                        : qsTr("Switch live TG"))))
                                               : ""
                                accentColor: "#2c5cff"
                                emphasized: page.currentTalkgroup !== (page.selectedProfile ? page.selectedProfile.talkgroup : page.currentTalkgroup)
                                enabled: page.canSwitchTalkgroup
                                onClicked: page.openTalkgroupSwitcherRequested()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: page.profileSwitchInProgress
                            radius: page.uiMetrics.nestedFrameRadius
                            color: "#edf2ff"
                            border.color: "#c5d5ff"
                            implicitHeight: switchBannerLayout.implicitHeight + (page.compactMode ? 16 : 20)

                            RowLayout {
                                id: switchBannerLayout

                                anchors.fill: parent
                                anchors.margins: page.uiMetrics.nestedSectionPadding
                                spacing: 10

                                BusyIndicator {
                                    running: visible
                                    visible: page.profileSwitchInProgress
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Switching to %1...").arg(page.pendingProfileName)
                                    wrapMode: Text.WordWrap
                                    color: "#173b8f"
                                    font.bold: true
                                }
                            }
                        }
                    }
                }
            }
        }

        Frame {
            Layout.fillWidth: true
            padding: page.uiMetrics.sectionPadding
            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Connection controls")

            background: Rectangle {
                Accessible.ignored: true
                radius: page.uiMetrics.frameRadius
                color: "#ffffff"
                border.color: page.borderColor
            }

            contentItem: ColumnLayout {
                spacing: page.compactMode ? 8 : 10

                Button {
                    visible: page.reflectorClient.isDisconnected
                    Layout.fillWidth: true
                    text: qsTr("Connect")
                    enabled: !page.profileSwitchInProgress
                             && page.canConnect
                    Accessible.name: text

                    onClicked: page.connectRequested()
                }

                Label {
                    id: txStatusLabel
                    objectName: "txStatusLabel"

                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: page.reflectorClient.pttActive
                          ? qsTr("TX Time: %1").arg(page.reflectorClient.txTimeString)
                          : (page.reflectorClient.currentTalker.length > 0
                             ? qsTr("RX: %1").arg(page.reflectorClient.currentTalker)
                               + (page.reflectorClient.currentTalkerName.length > 0
                                  ? qsTr(" (%1)").arg(page.reflectorClient.currentTalkerName)
                                  : "")
                             : (page.reflectorClient.isReceivingAudio ? qsTr("RX: Unknown") : ""))
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: page.uiMetrics.statusFontSize
                    color: page.reflectorClient.pttActive
                           ? (page.reflectorClient.txTimeoutWarning ? "#dc2626" : "#8b0000")
                           : "#334155"

                    SequentialAnimation {
                        id: txTimeoutPulse

                        running: txStatusLabel.visible && page.reflectorClient.txTimeoutWarning
                        loops: Animation.Infinite
                        alwaysRunToEnd: false

                        NumberAnimation {
                            target: txStatusLabel
                            property: "opacity"
                            to: 0.4
                            duration: 420
                            easing.type: Easing.InOutQuad
                        }

                        NumberAnimation {
                            target: txStatusLabel
                            property: "opacity"
                            to: 1.0
                            duration: 420
                            easing.type: Easing.InOutQuad
                        }

                        onStopped: txStatusLabel.opacity = 1.0
                    }
                }

                Button {
                    id: pttButton
                    objectName: "pttButton"

                    visible: page.tapToTalkButtonVisible
                    Layout.fillWidth: true
                    Layout.preferredHeight: page.compactPttButtonHeight
                    Layout.maximumHeight: page.compactMode
                                          ? page.compactPttButtonHeight + 8
                                          : page.compactPttButtonHeight + 16
                    text: page.reflectorClient.pttActive
                          ? (page.compactMode ? qsTr("TX - TAP TO STOP") : qsTr("TRANSMITTING - TAP TO STOP"))
                          : qsTr("TAP TO TALK")
                    enabled: !page.profileSwitchInProgress
                             && page.reflectorClient.connectionStatus.startsWith("Connected")
                             && page.reflectorClient.currentTalker.length === 0
                             && !page.reflectorClient.isReceivingAudio
                             && page.reflectorClient.audioReady
                    Accessible.name: text

                    background: Rectangle {
                        Accessible.ignored: true
                        color: page.reflectorClient.pttActive ? "#991b1b" : (pttButton.down ? "#b9d4ff" : "#e7ebf2")
                        radius: page.uiMetrics.nestedFrameRadius
                        border.color: page.reflectorClient.pttActive ? "#ef4444" : "#a6b2c8"
                        border.width: 2
                    }

                    contentItem: Label {
                        text: pttButton.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: page.uiMetrics.sectionTitleFontSize
                        font.bold: true
                        color: !pttButton.enabled
                               ? "#94a3b8"
                               : (page.reflectorClient.pttActive ? "#fffaf9" : "#0f172a")
                    }

                    onClicked: page.pttRequested()
                }
            }
        }

        RowLayout {
            visible: !page.compactMode
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: qsTr("Made by Silviu YO6SAY")
                font.pixelSize: page.uiMetrics.footerFontSize
                Layout.alignment: Qt.AlignLeft
            }

            Item {
                Layout.fillWidth: true
                Accessible.ignored: true
            }

            Text {
                text: "v" + page.reflectorClient.softwareVersion
                font.pixelSize: page.uiMetrics.footerFontSize
            }

            Item {
                Layout.fillWidth: true
                Accessible.ignored: true
            }

            Text {
                textFormat: Text.RichText
                text: "<a href='https://latry.app/#support'>Buy me a coffee</a>"
                font.pixelSize: page.uiMetrics.footerFontSize
                color: "#1d4ed8"
                onLinkActivated: function(link) {
                    Qt.openUrlExternally(link)
                }
            }
        }
    }
}
