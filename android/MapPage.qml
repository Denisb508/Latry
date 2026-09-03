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

    property string geoSourceCode: ""
    property string geoEndpoint: ""
    property var stations: []
    property bool initialMapFitDone: false
    property bool loading: false
    property string statusText: ""
    property var localTrackPath: []

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
