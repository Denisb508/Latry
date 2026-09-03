import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning
import SvxlinkReflector.Client 1.0

Page {
    id: page

    required property var uiMetrics
    required property real contentPadding
    required property real safeAreaTop
    required property real safeAreaLeft
    required property real safeAreaRight
    required property real safeAreaBottom
    required property color surfaceColor
    required property color borderColor
    required property color accentColor
    required property var reflectorClient
    required property bool trackingEnabled
    required property string trackingMode
    required property string movementIcon
    required property string movementWatchJson

    property string geoSourceCode: ""
    property string geoEndpoint: ""
    property var stations: []
    property bool initialMapFitDone: false
    property bool loading: false
    property string statusText: ""
    property var localTrackPath: []

    // Movement Watch - zadnje znano stanje spremljanih uporabnikov
    property var movementWatchStates: ({})

    readonly property var portalCapabilities:
        page.reflectorClient.portalCapabilities || []

    readonly property bool canPrecise:
        page.portalCapabilities.indexOf("APP_GEO_PRECISE") >= 0

    readonly property bool canTracking:
        page.portalCapabilities.indexOf("APP_GEO_TRACKING") >= 0

    readonly property bool canBackgroundTracking:
        page.portalCapabilities.indexOf("APP_GEO_BACKGROUND") >= 0

    readonly property bool canHistory:
        page.portalCapabilities.indexOf("APP_GEO_HISTORY") >= 0

    signal backRequested()
    signal trackingRequested(bool enabled)
    signal trackingModeRequested(string mode)
    signal movementWatchSettingsChanged(string watchJson)

    function movementWatchCallsigns() {
        try {
            const parsed =
                JSON.parse(page.movementWatchJson || "[]")

            if (!parsed || !Array.isArray(parsed))
                return []

            const result = []

            for (let i = 0; i < parsed.length; ++i) {
                const callsign =
                    String(parsed[i] || "")
                        .trim().toUpperCase()

                if (callsign
                        && result.indexOf(callsign) < 0)
                    result.push(callsign)
            }

            return result
        } catch (error) {
            console.warn(
                "Invalid Movement Watch JSON",
                error)
            return []
        }
    }

    function isMovementWatched(callsign) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        return page.movementWatchCallsigns()
            .indexOf(wanted) >= 0
    }

    function setMovementWatched(callsign, enabled) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        if (!wanted)
            return

        const watch =
            page.movementWatchCallsigns()

        const index =
            watch.indexOf(wanted)

        const changed =
            (enabled && index < 0)
            || (!enabled && index >= 0)

        if (!changed)
            return

        if (enabled)
            watch.push(wanted)
        else
            watch.splice(index, 1)

        watch.sort()

        page.movementWatchSettingsChanged(
            JSON.stringify(watch))

        if (enabled)
            page.seedMovementWatchState(wanted)
        else
            page.clearMovementWatchState(wanted)
    }

    function seedMovementWatchState(callsign) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        if (!wanted)
            return

        const next =
            Object.assign(
                {},
                page.movementWatchStates || ({}))

        for (let i = 0; i < page.stations.length; ++i) {
            const station = page.stations[i] || {}

            const stationCallsign =
                String(station.callsign || "")
                    .trim().toUpperCase()

            if (stationCallsign !== wanted)
                continue

            const lat = Number(station.lat)
            const lon = Number(station.lon)

            if (!Number.isFinite(lat)
                    || !Number.isFinite(lon))
                return

            let accuracy =
                Number(station.accuracy_m)

            if (!Number.isFinite(accuracy))
                accuracy = Number(station.accuracy)

            if (!Number.isFinite(accuracy)
                    || accuracy < 0)
                accuracy = 0

            let speedKmh =
                Number(station.speed_kmh)

            if (!Number.isFinite(speedKmh)
                    || speedKmh < 0)
                speedKmh = 0

            next[wanted] = {
                lat: lat,
                lon: lon,
                accuracy: accuracy,
                totalMeters: 0,
                lastMoveMs: 0,
                moving: speedKmh >= 1,
                speedKmh: speedKmh
            }

            page.movementWatchStates = next
            return
        }
    }

    function clearMovementWatchState(callsign) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        const next =
            Object.assign(
                {},
                page.movementWatchStates || ({}))

        delete next[wanted]
        page.movementWatchStates = next
    }

    function geoDistanceMeters(lat1, lon1, lat2, lon2) {
        const earthRadius = 6371000
        const toRad = Math.PI / 180

        const dLat = (lat2 - lat1) * toRad
        const dLon = (lon2 - lon1) * toRad

        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(lat1 * toRad)
            * Math.cos(lat2 * toRad)
            * Math.sin(dLon / 2)
            * Math.sin(dLon / 2)

        return earthRadius
            * 2
            * Math.atan2(
                Math.sqrt(a),
                Math.sqrt(1 - a))
    }

    function updateMovementWatchStates(stations) {
        const watched = page.movementWatchCallsigns()
        const previous = page.movementWatchStates || ({})
        const next = Object.assign({}, previous)
        const nowMs = Date.now()

        for (let i = 0; i < stations.length; ++i) {
            const station = stations[i] || {}

            const callsign =
                String(station.callsign || "")
                    .trim().toUpperCase()

            if (!callsign
                    || watched.indexOf(callsign) < 0)
                continue

            const lat = Number(station.lat)
            const lon = Number(station.lon)

            if (!Number.isFinite(lat)
                    || !Number.isFinite(lon))
                continue

            let accuracy =
                Number(station.accuracy_m)

            if (!Number.isFinite(accuracy))
                accuracy = Number(station.accuracy)

            if (!Number.isFinite(accuracy)
                    || accuracy < 0)
                accuracy = 0

            let speedKmh =
                Number(station.speed_kmh)

            if (!Number.isFinite(speedKmh)
                    || speedKmh < 0)
                speedKmh = 0

            const old = previous[callsign]

            if (!old) {
                next[callsign] = {
                    lat: lat,
                    lon: lon,
                    accuracy: accuracy,
                    totalMeters: 0,
                    lastMoveMs: 0,
                    moving: speedKmh >= 1,
                    speedKmh: speedKmh
                }
                continue
            }

            const distance =
                page.geoDistanceMeters(
                    Number(old.lat),
                    Number(old.lon),
                    lat,
                    lon)

            const threshold =
                Math.max(
                    30,
                    accuracy * 2,
                    Number(old.accuracy || 0) * 2)

            const moved =
                Number.isFinite(distance)
                && distance >= threshold

            if (moved) {
                next[callsign] = {
                    lat: lat,
                    lon: lon,
                    accuracy: accuracy,
                    totalMeters:
                        Number(old.totalMeters || 0)
                        + distance,
                    lastMoveMs: nowMs,
                    moving: true,
                    speedKmh: speedKmh
                }
            } else {
                next[callsign] =
                    Object.assign({}, old, {
                        accuracy: accuracy,
                        moving: speedKmh >= 1,
                        speedKmh: speedKmh
                    })
            }
        }

        page.movementWatchStates = next
    }

    function nearestGeoStationStatus(callsign) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        if (!wanted)
            return ""

        let source = null

        for (let i = 0; i < page.stations.length; ++i) {
            const station = page.stations[i] || {}

            if (String(station.callsign || "")
                    .trim().toUpperCase() === wanted) {
                source = station
                break
            }
        }

        if (!source)
            return ""

        const sourceLat = Number(source.lat)
        const sourceLon = Number(source.lon)

        if (!Number.isFinite(sourceLat)
                || !Number.isFinite(sourceLon))
            return ""

        const nearby = []

        for (let i = 0; i < page.stations.length; ++i) {
            const station = page.stations[i] || {}

            const otherCallsign =
                String(station.callsign || "")
                    .trim().toUpperCase()

            if (!otherCallsign || otherCallsign === wanted)
                continue

            const lat = Number(station.lat)
            const lon = Number(station.lon)

            if (!Number.isFinite(lat)
                    || !Number.isFinite(lon))
                continue

            const distance =
                page.geoDistanceMeters(
                    sourceLat,
                    sourceLon,
                    lat,
                    lon)

            if (!Number.isFinite(distance))
                continue

            nearby.push({
                callsign: otherCallsign,
                meters: distance
            })
        }

        nearby.sort(function(a, b) {
            return a.meters - b.meters
        })

        if (nearby.length === 0)
            return ""

        const lines = [
            "📏 " + qsTr("Nearest GEO") + ":"
        ]

        const count =
            Math.min(3, nearby.length)

        for (let i = 0; i < count; ++i) {
            const item = nearby[i]

            const distanceText =
                item.meters >= 1000
                ? (item.meters / 1000).toFixed(1) + " km"
                : Math.round(item.meters) + " m"

            lines.push(
                (i + 1)
                + ". "
                + item.callsign
                + "   • "
                + distanceText)
        }

        return lines.join("\n")
    }

    function movementWatchStatus(callsign) {
        const wanted =
            String(callsign || "")
                .trim().toUpperCase()

        if (!wanted || !page.isMovementWatched(wanted))
            return ""

        const state =
            (page.movementWatchStates || ({}))[wanted]

        if (!state)
            return qsTr("📍 Waiting for GEO update")

        const totalMeters =
            Number(state.totalMeters || 0)

        if (state.moving
                && Number(state.speedKmh || 0) >= 1) {
            return "🚗 " + qsTr("MOVING")
                + "   "
                + Math.round(Number(state.speedKmh))
                + " km/h"
        }

        if (totalMeters <= 0)
            return qsTr("📍 No movement detected yet")

        const distanceText =
            totalMeters >= 1000
            ? (totalMeters / 1000).toFixed(1) + " km"
            : Math.round(totalMeters) + " m"

        let timeText = ""

        const lastMoveMs =
            Number(state.lastMoveMs || 0)

        if (lastMoveMs > 0) {
            const d = new Date(lastMoveMs)

            const hh =
                String(d.getHours()).padStart(2, "0")

            const mm =
                String(d.getMinutes()).padStart(2, "0")

            timeText = hh + ":" + mm
        }

        return "🚗 "
            + qsTr("Moved")
            + " "
            + distanceText
            + (timeText
               ? "   • "
                 + qsTr("Last move")
                 + ": "
                 + timeText
               : "")
    }

    function refreshLocalTrack() {
        const rawPoints = TrackStore.currentTrack()
        const path = []

        for (let i = 0; i < rawPoints.length; ++i) {
            const point = rawPoints[i]
            const lat = Number(point.lat)
            const lon = Number(point.lon)

            if (!Number.isFinite(lat)
                    || !Number.isFinite(lon)
                    || lat < -90 || lat > 90
                    || lon < -180 || lon > 180)
                continue

            path.push(
                QtPositioning.coordinate(lat, lon))
        }

        page.localTrackPath = path
    }

    function discoverGeoSource() {
        const sources = page.reflectorClient.portalSources || []

        page.geoSourceCode = ""
        page.geoEndpoint = ""

        for (let i = 0; i < sources.length; ++i) {
            const source = sources[i]

            if (String(source.dataMode || "")
                    .trim().toLowerCase() !== "geo")
                continue

            page.geoSourceCode =
                String(source.code || "").trim().toUpperCase()

            page.geoEndpoint =
                String(source.endpoint || "").trim()

            break
        }
    }

    function refreshGeo() {
        if (!page.geoSourceCode || !page.geoEndpoint) {
            page.statusText = qsTr("GEO vir ni na voljo.")
            return
        }

        page.loading = true
        page.statusText = qsTr("Osvežujem lokacije…")

        page.reflectorClient.refreshPortalSource(
            page.geoSourceCode,
            page.geoEndpoint)
    }

    function applyStations(data) {
        const rawStations =
            data && data.stations
            ? data.stations
            : []

        page.stations = rawStations.filter(function(station) {
            if (!station)
                return false

            if (station.lat === null || station.lat === undefined
                    || station.lon === null || station.lon === undefined)
                return false

            const lat = Number(station.lat)
            const lon = Number(station.lon)

            return Number.isFinite(lat)
                    && Number.isFinite(lon)
                    && lat >= -90 && lat <= 90
                    && lon >= -180 && lon <= 180
        })

        page.updateMovementWatchStates(
            page.stations)

        page.statusText =
            page.stations.length === 0
            ? qsTr("Trenutno ni vidnih lokacij.")
            : qsTr("%1 lokacij").arg(page.stations.length)

        Qt.callLater(function() {
            if (!page.initialMapFitDone && page.stations.length > 0) {
                map.fitViewportToMapItems()
                page.initialMapFitDone = true
            }
        })
    }

    background: Rectangle {
        color: "#f4f7fb"
    }

    Plugin {
        id: osmPlugin
        name: "osm"

        PluginParameter {
            name: "osm.useragent"
            value: "Latry-by-OB508/0.0.19"
        }

        PluginParameter {
            name: "osm.mapping.providersrepository.disabled"
            value: true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: page.contentPadding + page.safeAreaTop
        anchors.leftMargin: page.contentPadding + page.safeAreaLeft
        anchors.rightMargin: page.contentPadding + page.safeAreaRight
        anchors.bottomMargin: page.contentPadding + page.safeAreaBottom
        spacing: 8

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(
                backButton.implicitHeight,
                titleLabel.implicitHeight
            )

            ToolButton {
                id: backButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "←"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                onClicked: page.backRequested()
            }

            Label {
                id: titleLabel
                anchors.centerIn: parent
                text: qsTr("🗺 Latry zemljevid")
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                font.bold: true
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                ToolButton {
                    visible: page.canTracking
                    text: page.trackingEnabled ? "🟢" : "🚗"
                    font.pixelSize: 19
                    enabled: true

                    onClicked:
                        page.trackingRequested(!page.trackingEnabled)

                    ToolTip.visible: hovered
                    ToolTip.text:
                        page.trackingEnabled
                        ? qsTr("Live Tracking je vklopljen")
                        : qsTr("Vklopi Live Tracking")
                }

                ToolButton {
                    text: "↻"
                    font.pixelSize: 20
                    enabled: !page.loading
                    onClicked: page.refreshGeo()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: page.canTracking
            spacing: 8

            Label {
                text: "🚗 " + qsTr("Tracking:")
                font.bold: true
            }

            ComboBox {
                id: trackingModeBox
                Layout.fillWidth: true

                model: [
                    { text: "🧠 Smart", value: "smart" },
                    { text: "⚡ 10 s", value: "10" },
                    { text: "🚗 15 s", value: "15" },
                    { text: "🕒 30 s", value: "30" },
                    { text: "🔋 60 s", value: "60" }
                ]

                textRole: "text"
                valueRole: "value"

                Component.onCompleted: {
                    const index =
                        indexOfValue(page.trackingMode || "smart")

                    currentIndex = index >= 0 ? index : 0
                }

                onActivated: {
                    page.trackingModeRequested(
                        String(currentValue || "smart"))
                }
            }
        }

        Map {
            id: map

            Layout.fillWidth: true
            Layout.fillHeight: true

            plugin: osmPlugin
            center: QtPositioning.coordinate(46.15, 14.99)
            zoomLevel: 7.5

            property geoCoordinate startCentroid

            // Live movement status.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 10

                width: 46
                height: 46
                radius: 23

                color: "#f8fafcee"
                border.color: page.borderColor
                border.width: 1

                z: 100
                visible: page.trackingEnabled

                Label {
                    anchors.centerIn: parent
                    text: page.movementIcon || "📍"
                    font.pixelSize: 25
                }

                ToolTip.visible: movementMouse.containsMouse
                ToolTip.text: qsTr("Smart Tracking status")

                MouseArea {
                    id: movementMouse
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }

            PinchHandler {
                id: pinch
                target: null

                onActiveChanged: if (active) {
                    map.startCentroid =
                        map.toCoordinate(pinch.centroid.position, false)
                }

                onScaleChanged: (delta) => {
                    map.zoomLevel += Math.log2(delta)
                    map.alignCoordinateToPoint(
                        map.startCentroid,
                        pinch.centroid.position)
                }

                grabPermissions: PointerHandler.TakeOverForbidden
            }

            DragHandler {
                target: null
                onTranslationChanged: (delta) =>
                    map.pan(-delta.x, -delta.y)
            }

            MapPolyline {
                id: localTrackLine

                visible: page.localTrackPath.length >= 2
                path: page.localTrackPath

                line.width: 5
                line.color: page.accentColor
            }

            MapItemView {
                model: page.stations

                delegate: MapQuickItem {
                    required property var modelData

                    coordinate: QtPositioning.coordinate(
                                    Number(modelData.lat),
                                    Number(modelData.lon))

                    anchorPoint.x: marker.width / 2
                    anchorPoint.y: marker.height

                    sourceItem: Rectangle {
                        id: marker

                        width: 46
                        height: 46
                        radius: 23
                        color: page.accentColor
                        border.color: "#ffffff"
                        border.width: 3

                        Label {
                            anchors.centerIn: parent
                            text: "📍"
                            font.pixelSize: 22
                        }

                        ToolTip.visible: markerMouse.containsMouse
                        ToolTip.text:
                            String(modelData.callsign || "") +
                            (modelData.city
                             ? "\n" + String(modelData.city)
                             : "")

                        MouseArea {
                            id: markerMouse
                            anchors.fill: parent
                            hoverEnabled: true

                            onClicked: {
                                detailsCallsign.text =
                                    String(modelData.callsign || "")

                                detailsLocation.text =
                                    [modelData.city, modelData.country]
                                    .filter(function(v) {
                                        return String(v || "").length > 0
                                    })
                                    .join(", ")

                                detailsPopup.open()
                            }
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: page.stations.length === 0 && !page.loading
                text: page.statusText
                color: "#475569"
                font.pixelSize: 14
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: page.loading
                visible: running
            }
        }

        Label {
            Layout.fillWidth: true
            text: page.statusText
            horizontalAlignment: Text.AlignHCenter
            color: "#64748b"
            font.pixelSize: 11
        }
    }

    Popup {
        id: detailsPopup
        anchors.centerIn: Overlay.overlay
        width: Math.min(page.width - 40, 340)
        modal: true
        focus: true
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 14
            color: "#ffffff"
            border.color: page.borderColor
        }

        contentItem: ColumnLayout {
            spacing: 8

            Label {
                id: detailsCallsign
                Layout.fillWidth: true
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                id: detailsLocation
                Layout.fillWidth: true
                color: "#475569"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true

                text:
                    page.nearestGeoStationStatus(
                        detailsCallsign.text)

                visible:
                    text.length > 0

                horizontalAlignment:
                    Text.AlignHCenter

                wrapMode:
                    Text.WordWrap

                color: "#475569"
            }

            CheckBox {
                id: movementWatchCheck
                Layout.alignment: Qt.AlignHCenter

                text: qsTr("Movement Watch")

                checked:
                    page.isMovementWatched(
                        detailsCallsign.text)

                enabled:
                    String(detailsCallsign.text || "")
                        .length > 0

                onToggled: {
                    page.setMovementWatched(
                        detailsCallsign.text,
                        checked)
                }
            }

            Label {
                Layout.fillWidth: true

                visible:
                    page.isMovementWatched(
                        detailsCallsign.text)

                text:
                    page.movementWatchStatus(
                        detailsCallsign.text)

                font.bold: true
                font.pixelSize: 14

                horizontalAlignment:
                    Text.AlignHCenter

                wrapMode:
                    Text.WordWrap

                color:
                    page.accentColor
            }
        }
    }

    Connections {
        target: TrackStore

        function onPointsChanged() {
            page.refreshLocalTrack()
        }

        function onSessionChanged() {
            page.refreshLocalTrack()
        }
    }

    Connections {
        target: page.reflectorClient

        function onPortalSourceFetchFinished(
            code, success, data, error) {

            if (String(code || "").trim().toUpperCase()
                    !== page.geoSourceCode)
                return

            page.loading = false

            if (!success) {
                page.statusText =
                    String(error || qsTr("Napaka GEO vira"))
                return
            }

            page.applyStations(data)
        }

        function onPortalAccessChanged() {
            if (page.reflectorClient.portalAccessLoading)
                return

            page.discoverGeoSource()
            page.refreshGeo()
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: page.visible && page.geoSourceCode.length > 0
        onTriggered: page.refreshGeo()
    }

    Component.onCompleted: {
        page.refreshLocalTrack()
        page.discoverGeoSource()
        page.refreshGeo()
    }
}
