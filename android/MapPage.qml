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
    property var remoteTracks: []
    property bool showRemoteTracks: true
    property int remoteTrackTailMinutes: 1440
    property string remoteTrackCallsign: ""

    property string historyCallsign: ""
    property var historyDates: []
    property string historyDate: ""
    property var historyTrack: []
    property bool historyLoading: false
    property string historyError: ""

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

    function geoEndpointWithParam(name, value) {
        const endpoint = String(page.geoEndpoint || "")

        if (!endpoint)
            return ""

        const separator =
            endpoint.indexOf("?") >= 0 ? "&" : "?"

        return endpoint
            + separator
            + encodeURIComponent(name)
            + "="
            + encodeURIComponent(String(value || ""))
    }

    function loadHistoryDates(callsign) {
        const cs =
            String(callsign || "").trim().toUpperCase()

        if (!cs || !page.geoEndpoint)
            return

        page.historyCallsign = cs
        page.historyDates = []
        page.historyDate = ""
        page.historyTrack = []
        page.historyError = ""
        page.historyLoading = true

        page.reflectorClient.refreshPortalSource(
            "LATRY_GEO_HISTORY_DATES",
            page.geoEndpointWithParam(
                "history_dates",
                cs))
    }

    function loadHistory(callsign, date) {
        const cs =
            String(callsign || "").trim().toUpperCase()

        const day =
            String(date || "").trim()

        if (!cs || !day || !page.geoEndpoint)
            return

        let endpoint =
            page.geoEndpointWithParam(
                "history_callsign",
                cs)

        endpoint +=
            "&history_date="
            + encodeURIComponent(day)

        page.historyCallsign = cs
        page.historyDate = day
        page.historyTrack = []
        page.historyError = ""
        page.historyLoading = true

        page.reflectorClient.refreshPortalSource(
            "LATRY_GEO_HISTORY",
            endpoint)
    }

    function applyHistoryDates(data) {
        page.historyDates =
            data && data.dates
            ? data.dates
            : []

        page.historyLoading = false

        if (page.historyDates.length === 0) {
            page.historyDate = ""
            page.historyError =
                qsTr("Za uporabnika ni shranjene zgodovine.")
        } else {
            page.historyDate =
                String(page.historyDates[0].date || "")
            page.historyError = ""

            Qt.callLater(function() {
                if (historyDateBox.count > 0)
                    historyDateBox.currentIndex = 0
            })
        }
    }

    function applyHistory(data) {
        const history =
            data && data.history
            ? data.history
            : null

        const rawPoints =
            history && history.points
            ? history.points
            : []

        const path = []

        for (let i = 0; i < rawPoints.length; ++i) {
            const point = rawPoints[i]

            if (!point)
                continue

            const lat = Number(point.lat)
            const lon = Number(point.lon)

            if (!Number.isFinite(lat)
                    || !Number.isFinite(lon)
                    || lat < -90 || lat > 90
                    || lon < -180 || lon > 180)
                continue

            path.push({
                lat: lat,
                lon: lon,
                recordedAt:
                    String(point.recorded_at || ""),
                speedKmh:
                    point.speed_kmh === null
                    || point.speed_kmh === undefined
                    ? null
                    : Number(point.speed_kmh),
                accuracyM:
                    point.accuracy_m === null
                    || point.accuracy_m === undefined
                    ? null
                    : Number(point.accuracy_m)
            })
        }

        page.historyTrack = path
        page.historyLoading = false

        if (path.length === 0)
            page.historyError =
                qsTr("Za izbrani datum ni točk.")
    }

    function historyUserModel() {
        const result = []

        for (let i = 0; i < page.stations.length; ++i) {
            const station = page.stations[i]
            const callsign =
                String(station.callsign || "").trim().toUpperCase()

            if (!callsign)
                continue

            result.push({
                text: callsign,
                value: callsign
            })
        }

        return result
    }

    function historyDateLabel(date) {
        const value = String(date || "")
        const parts = value.split("-")

        if (parts.length !== 3)
            return value

        return parts[2] + "." + parts[1] + "." + parts[0]
    }

    function historyDateModel() {
        const result = []

        for (let i = 0; i < page.historyDates.length; ++i) {
            const item = page.historyDates[i]
            const date = String(item.date || "")

            if (!date)
                continue

            result.push({
                text:
                    page.historyDateLabel(date)
                    + " • "
                    + Number(item.count || 0)
                    + " "
                    + qsTr("točk"),
                value: date
            })
        }

        return result
    }

    function trackTimestampMs(value) {
        let text = String(value || "").trim()

        if (text.length >= 19 && text.charAt(10) === " ")
            text = text.substring(0, 10) + "T" + text.substring(11)

        return Date.parse(text)
    }

    function shouldBreakTrack(previousPoint, currentPoint) {
        if (!previousPoint || !currentPoint)
            return false

        const previousTime =
            page.trackTimestampMs(previousPoint.recordedAt)

        const currentTime =
            page.trackTimestampMs(currentPoint.recordedAt)

        if (!Number.isFinite(previousTime)
                || !Number.isFinite(currentTime))
            return false

        const gapSeconds =
            (currentTime - previousTime) / 1000

        const previousCoordinate =
            QtPositioning.coordinate(
                Number(previousPoint.lat),
                Number(previousPoint.lon)
            )

        const currentCoordinate =
            QtPositioning.coordinate(
                Number(currentPoint.lat),
                Number(currentPoint.lon)
            )

        const distanceMeters =
            previousCoordinate.distanceTo(currentCoordinate)

        return gapSeconds > 600
                && distanceMeters > 500
    }

    function historySegmentModel() {
        const result = []

        let path = []
        let previousPoint = null

        for (let i = 0; i < page.historyTrack.length; ++i) {
            const point = page.historyTrack[i]

            if (previousPoint
                    && page.shouldBreakTrack(previousPoint, point)) {

                if (path.length >= 2)
                    result.push({ path: path })

                path = []
            }

            path.push(
                QtPositioning.coordinate(
                    Number(point.lat),
                    Number(point.lon)
                )
            )

            previousPoint = point
        }

        if (path.length >= 2)
            result.push({ path: path })

        return result
    }

    function historyStartCoordinate() {
        if (page.historyTrack.length === 0)
            return QtPositioning.coordinate(0, 0)

        const point = page.historyTrack[0]

        return QtPositioning.coordinate(
            Number(point.lat),
            Number(point.lon)
        )
    }

    function historyEndCoordinate() {
        if (page.historyTrack.length === 0)
            return QtPositioning.coordinate(0, 0)

        const point =
            page.historyTrack[page.historyTrack.length - 1]

        return QtPositioning.coordinate(
            Number(point.lat),
            Number(point.lon)
        )
    }

    function applyTracks(data) {
        const rawTracks =
            data && data.tracks
            ? data.tracks
            : []

        const normalized = []

        for (let i = 0; i < rawTracks.length; ++i) {
            const track = rawTracks[i]

            if (!track || !track.points)
                continue

            const callsign =
                String(track.callsign || "")
                    .trim()
                    .toUpperCase()

            if (!callsign)
                continue

            const points = []

            for (let j = 0; j < track.points.length; ++j) {
                const point = track.points[j]

                if (!point)
                    continue

                const lat = Number(point.lat)
                const lon = Number(point.lon)

                if (!Number.isFinite(lat)
                        || !Number.isFinite(lon)
                        || lat < -90 || lat > 90
                        || lon < -180 || lon > 180)
                    continue

                points.push({
                    lat: lat,
                    lon: lon,
                    recordedAt:
                        String(point.recorded_at || ""),
                    speedKmh:
                        point.speed_kmh === null
                        || point.speed_kmh === undefined
                        ? null
                        : Number(point.speed_kmh)
                })
            }

            if (points.length === 0)
                continue

            normalized.push({
                callsign: callsign,
                points: points
            })
        }

        page.remoteTracks = normalized
    }

    function remoteTrackDisplayModel() {
        if (!page.showRemoteTracks)
            return []

        const result = []
        const cutoff =
            Date.now() - page.remoteTrackTailMinutes * 60 * 1000

        for (let i = 0; i < page.remoteTracks.length; ++i) {
            const track = page.remoteTracks[i]

            if (page.remoteTrackCallsign.length > 0
                    && String(track.callsign || "").toUpperCase()
                        !== page.remoteTrackCallsign)
                continue

            let path = []
            let previousPoint = null

            for (let j = 0; j < track.points.length; ++j) {
                const point = track.points[j]
                const timestamp =
                    page.trackTimestampMs(point.recordedAt)

                if (Number.isFinite(timestamp)
                        && timestamp < cutoff)
                    continue

                if (previousPoint
                        && page.shouldBreakTrack(
                            previousPoint,
                            point)) {

                    if (path.length >= 2) {
                        result.push({
                            callsign: track.callsign,
                            path: path
                        })
                    }

                    path = []
                }

                path.push(
                    QtPositioning.coordinate(
                        Number(point.lat),
                        Number(point.lon)
                    )
                )

                previousPoint = point
            }

            if (path.length >= 2) {
                result.push({
                    callsign: track.callsign,
                    path: path
                })
            }
        }

        return result
    }

    function hasRemoteTrack(callsign) {
        const wanted =
            String(callsign || "").trim().toUpperCase()

        if (!wanted)
            return false

        for (let i = 0; i < page.remoteTracks.length; ++i) {
            const track = page.remoteTracks[i]

            if (String(track.callsign || "").trim().toUpperCase()
                    === wanted
                    && track.points
                    && track.points.length >= 2)
                return true
        }

        return false
    }

    function trackLineColor(callsign) {
        const colors = [
            "#1565c0",
            "#2e7d32",
            "#c62828",
            "#6a1b9a",
            "#ef6c00",
            "#00838f",
            "#ad1457",
            "#4527a0"
        ]

        const text = String(callsign || "")
        let hash = 0

        for (let i = 0; i < text.length; ++i)
            hash = ((hash * 31) + text.charCodeAt(i)) >>> 0

        return colors[hash % colors.length]
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

        RowLayout {
            Layout.fillWidth: true
            visible: page.canHistory
            spacing: 8

            CheckBox {
                id: tracksLayerCheck
                text: "🛣 " + qsTr("Tracks")
                checked: true
                enabled: false

                onToggled: {
                    page.showRemoteTracks = checked

                    if (checked)
                        page.refreshGeo()
                }
            }

            Button {
                text: "📅 " + qsTr("History")

                onClicked: {
                    historyPopup.open()
                }
            }

            Label {
                visible:
                    page.showRemoteTracks
                    && page.remoteTrackCallsign.length > 0

                text: "🎯 " + page.remoteTrackCallsign
                font.bold: true
                color: page.accentColor
            }

            Button {
                visible:
                    page.showRemoteTracks
                    && page.remoteTrackCallsign.length > 0

                text: "🌍 " + qsTr("Show all")

                onClicked: {
                    page.remoteTrackCallsign = ""
                }
            }

            Label {
                text: qsTr("Tail:")
                visible: page.showRemoteTracks
            }

            ComboBox {
                id: tracksTailBox
                Layout.fillWidth: true
                visible: page.showRemoteTracks

                model: [
                    { text: "15 min", value: 15 },
                    { text: "1 h", value: 60 },
                    { text: "6 h", value: 360 },
                    { text: "24 h", value: 1440 }
                ]

                textRole: "text"
                valueRole: "value"

                Component.onCompleted: {
                    const index =
                        indexOfValue(page.remoteTrackTailMinutes)

                    currentIndex = index >= 0 ? index : 3
                }

                onActivated: {
                    page.remoteTrackTailMinutes =
                        Number(currentValue || 1440)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible:
                page.historyTrack.length > 0
                || page.historyLoading
            spacing: 8

            Label {
                Layout.fillWidth: true

                text:
                    page.historyLoading
                    ? "📅 " + qsTr("Nalagam zgodovino…")
                    : "📅 "
                      + page.historyCallsign
                      + " • "
                      + page.historyDateLabel(page.historyDate)
                      + " • "
                      + page.historyTrack.length
                      + " "
                      + qsTr("točk")

                font.bold: true
                color: page.accentColor
                elide: Text.ElideRight
            }

            Button {
                visible: page.historyTrack.length > 0
                text: "✕"

                ToolTip.visible: hovered
                ToolTip.text: qsTr("Zapri zgodovino")

                onClicked: {
                    page.historyTrack = []
                    page.historyDate = ""
                    page.historyError = ""
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

            MapItemView {
                model: page.historySegmentModel()

                delegate: MapPolyline {
                    required property var modelData

                    path: modelData.path
                    line.width: 6
                    line.color:
                        page.trackLineColor(page.historyCallsign)

                    z: 4
                }
            }

            MapQuickItem {
                visible: page.historyTrack.length > 0

                coordinate:
                    page.historyStartCoordinate()

                anchorPoint.x: historyStartMarker.width / 2
                anchorPoint.y: historyStartMarker.height / 2

                z: 5

                sourceItem: Rectangle {
                    id: historyStartMarker

                    width: 34
                    height: 34
                    radius: 17
                    color: "#16a34a"
                    border.color: "#ffffff"
                    border.width: 2

                    Label {
                        anchors.centerIn: parent
                        text: "S"
                        color: "#ffffff"
                        font.bold: true
                    }
                }
            }

            MapQuickItem {
                visible: page.historyTrack.length > 0

                coordinate:
                    page.historyEndCoordinate()

                anchorPoint.x: historyEndMarker.width / 2
                anchorPoint.y: historyEndMarker.height / 2

                z: 5

                sourceItem: Rectangle {
                    id: historyEndMarker

                    width: 34
                    height: 34
                    radius: 17
                    color: "#dc2626"
                    border.color: "#ffffff"
                    border.width: 2

                    Label {
                        anchors.centerIn: parent
                        text: "E"
                        color: "#ffffff"
                        font.bold: true
                    }
                }
            }

            MapItemView {
                model: page.remoteTrackDisplayModel()

                delegate: MapPolyline {
                    required property var modelData

                    path: modelData.path
                    line.width: 4
                    line.color:
                        page.trackLineColor(modelData.callsign)

                    z: 1
                }
            }

            MapPolyline {
                id: localTrackLine

                visible: page.localTrackPath.length >= 2
                path: page.localTrackPath

                line.width: 5
                line.color: page.accentColor
                z: 2
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
        id: historyPopup

        anchors.centerIn: Overlay.overlay
        width: Math.min(page.width - 32, 390)
        modal: true
        focus: true
        padding: 16

        closePolicy:
            Popup.CloseOnEscape
            | Popup.CloseOnPressOutside

        onOpened: {
            page.historyError = ""

            const preferred =
                page.remoteTrackCallsign.length > 0
                ? page.remoteTrackCallsign
                : page.historyCallsign

            if (preferred.length > 0) {
                const index =
                    historyUserBox.indexOfValue(preferred)

                if (index >= 0)
                    historyUserBox.currentIndex = index
            }

            if (historyUserBox.count > 0) {
                page.loadHistoryDates(
                    String(historyUserBox.currentValue || ""))
            }
        }

        background: Rectangle {
            radius: 14
            color: "#ffffff"
            border.color: page.borderColor
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "📅 " + qsTr("GEO History")
                font.pixelSize: 18
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                text: qsTr("Uporabnik")
                font.bold: true
            }

            ComboBox {
                id: historyUserBox
                Layout.fillWidth: true

                model: page.historyUserModel()
                textRole: "text"
                valueRole: "value"

                onActivated: {
                    page.loadHistoryDates(
                        String(currentValue || ""))
                }
            }

            Label {
                text: qsTr("Datum")
                font.bold: true
            }

            ComboBox {
                id: historyDateBox
                Layout.fillWidth: true

                enabled:
                    !page.historyLoading
                    && page.historyDates.length > 0

                model: page.historyDateModel()
                textRole: "text"
                valueRole: "value"

                onActivated: {
                    page.historyDate =
                        String(currentValue || "")
                }
            }

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: page.historyLoading
                visible: running
            }

            Label {
                Layout.fillWidth: true
                visible: page.historyError.length > 0
                text: page.historyError
                color: "#b91c1c"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    Layout.fillWidth: true
                    text: qsTr("Prekliči")
                    onClicked: historyPopup.close()
                }

                Button {
                    Layout.fillWidth: true

                    text: "📍 " + qsTr("Prikaži")

                    enabled:
                        !page.historyLoading
                        && page.historyCallsign.length > 0
                        && page.historyDate.length > 0

                    onClicked: {
                        page.loadHistory(
                            page.historyCallsign,
                            page.historyDate)

                        historyPopup.close()
                    }
                }
            }
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


            Button {
                Layout.alignment: Qt.AlignHCenter

                visible:
                    page.canHistory
                    && (
                        page.hasRemoteTrack(detailsCallsign.text)
                        || page.remoteTrackCallsign
                            === String(detailsCallsign.text || "")
                                .trim().toUpperCase()
                    )

                text:
                    page.remoteTrackCallsign
                        === String(detailsCallsign.text || "")
                            .trim().toUpperCase()
                    ? "🌍 " + qsTr("Show all tracks")
                    : "🛣 " + qsTr("Track %1")
                        .arg(detailsCallsign.text)

                onClicked: {
                    const callsign =
                        String(detailsCallsign.text || "")
                            .trim().toUpperCase()

                    if (page.remoteTrackCallsign === callsign) {
                        page.remoteTrackCallsign = ""
                    } else {
                        page.remoteTrackCallsign = callsign
                        page.showRemoteTracks = true
                    }

                    detailsPopup.close()
                }
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

            const key =
                String(code || "").trim().toUpperCase()

            if (key === "LATRY_GEO_HISTORY_DATES") {
                if (!success) {
                    page.historyLoading = false
                    page.historyError =
                        String(error || qsTr("Napaka GEO History"))
                    return
                }

                page.applyHistoryDates(data)
                return
            }

            if (key === "LATRY_GEO_HISTORY") {
                if (!success) {
                    page.historyLoading = false
                    page.historyError =
                        String(error || qsTr("Napaka GEO History"))
                    return
                }

                page.applyHistory(data)
                return
            }

            if (key !== page.geoSourceCode)
                return

            page.loading = false

            if (!success) {
                page.statusText =
                    String(error || qsTr("Napaka GEO vira"))
                return
            }

            page.applyTracks(data)
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
