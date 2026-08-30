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
    readonly property string frnStatusUrl: "https://svxportal.pmr446.si/frn_users.json"

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
        interval: 15000
        repeat: true
        running: page.showFrnUsers
        triggeredOnStart: true
        onTriggered: page.refreshFrnUsers()
    }

    Connections {
        target: page.reflectorClient

        function onConnectedNodesChanged(nodes) {
            page.reflectorUsers = page.normalizedReflectorUsers(nodes)
        }

        function onNodeJoined(callsign) {
            page.addReflectorUser(callsign)
        }

        function onNodeLeft(callsign) {
            page.removeReflectorUser(callsign)
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
                font.pixelSize: page.compactMode ? 18 : 21
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
                text: page.compactMode ? qsTr("Admin") : qsTr("Administracija")
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

                        Label {
                            visible: page.showReflectorUsers
                            Layout.fillWidth: true
                            text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)
                            font.pixelSize: page.compactMode ? 11 : page.uiMetrics.captionFontSize
                            font.bold: true
                            color: "#334155"
                        }

                        Flickable {
                            id: reflectorUsersFlick

                            visible: page.showReflectorUsers
                                     && page.reflectorUsers.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight:
                                reflectorUsersRow.implicitHeight
                                + (contentWidth > width ? 8 : 0)

                            clip: true
                            contentWidth: reflectorUsersRow.implicitWidth
                            contentHeight: reflectorUsersRow.implicitHeight
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.horizontal: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            Row {
                                id: reflectorUsersRow
                                spacing: 6

                                Repeater {
                                    model: page.reflectorUsers
                                delegate: Rectangle {
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
                            }
                            }
                        }

                        Label {
                            visible: page.showReflectorUsers && page.reflectorUsers.length === 0
                            text: page.reflectorClient.isDisconnected
                                  ? qsTr("SvxReflector ni povezan.")
                                  : qsTr("Trenutno ni prijavljenih uporabnikov.")
                            color: "#64748b"
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            visible: page.showReflectorUsers && page.showFrnUsers
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: "#e2e8f0"
                        }

                        Label {
                            visible: page.showFrnUsers
                            Layout.fillWidth: true
                            text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)
                            font.pixelSize: page.uiMetrics.captionFontSize
                            font.bold: true
                            color: "#334155"
                        }

                        Repeater {
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

                                Flickable {
                                    id: frnUsersFlick

                                    Layout.fillWidth: true
                                    Layout.preferredHeight:
                                        frnUsersRow.implicitHeight
                                        + (contentWidth > width ? 8 : 0)

                                    clip: true
                                    contentWidth: frnUsersRow.implicitWidth
                                    contentHeight: frnUsersRow.implicitHeight
                                    flickableDirection: Flickable.HorizontalFlick
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.horizontal: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                    Row {
                                        id: frnUsersRow
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
                        }

                        Label {
                            visible: page.showFrnUsers && page.frnStatusMessage.length > 0
                            Layout.fillWidth: true
                            text: page.frnStatusMessage
                            wrapMode: Text.WordWrap
                            color: "#64748b"
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
