import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtLocation
import QtPositioning

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

    property string geoSourceCode: ""
    property string geoEndpoint: ""
    property var stations: []
    property bool loading: false
    property string statusText: ""

    signal backRequested()

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
        page.stations = data && data.stations
                ? data.stations
                : []

        page.statusText =
            page.stations.length === 0
            ? qsTr("Trenutno ni vidnih lokacij.")
            : qsTr("%1 lokacij").arg(page.stations.length)

        Qt.callLater(function() {
            if (page.stations.length > 0)
                map.fitViewportToMapItems()
        })
    }

    background: Rectangle {
        color: "#f4f7fb"
    }

    Plugin {
        id: osmPlugin
        name: "osm"
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

            ToolButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                font.pixelSize: 20
                enabled: !page.loading
                onClicked: page.refreshGeo()
            }
        }

        Map {
            id: map

            Layout.fillWidth: true
            Layout.fillHeight: true

            plugin: osmPlugin
            center: QtPositioning.coordinate(46.15, 14.99)
            zoomLevel: 7.5

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
        page.discoverGeoSource()
        page.refreshGeo()
    }
}
