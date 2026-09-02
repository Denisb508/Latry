import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page

    required property var uiMetrics
    required property real contentPadding
    required property real safeAreaTop
    required property real safeAreaLeft
    required property real safeAreaRight
    required property real safeAreaBottom
    required property var reflectorClient

    signal backRequested()

    background: Rectangle { color: "#f4f7fb" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: page.contentPadding
        anchors.topMargin: page.contentPadding + page.safeAreaTop

        ToolButton {
            text: "←"
            onClicked: page.backRequested()
        }

        Label {
            text: qsTr("🗺 GEO uporabniki")
            font.pixelSize: page.uiMetrics.pageTitleFontSize
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            clip: true

            model: page.reflectorClient.portalAdminGeoUsers

            delegate: Rectangle {
                required property var modelData

                TapHandler {
                    onTapped: {
                        geoDialog.userId = modelData.id
                        geoDialog.callsign = modelData.callsign
                        geoDialog.shareEnabled = modelData.share_enabled
                        geoDialog.locationMode = modelData.location_mode
                        geoDialog.visibleGroups = modelData.visible_groups || []
                        geoDialog.open()
                    }
                }

                TapHandler {
                    onTapped: {
                        geoDialog.userId = modelData.id
                        geoDialog.callsign = modelData.callsign
                        geoDialog.shareEnabled = modelData.share_enabled
                        geoDialog.locationMode = modelData.location_mode
                        geoDialog.visibleGroups = modelData.visible_groups || []
                        geoDialog.open()
                    }
                }

                width: ListView.view.width
                height: 72
                radius: 12
                color: "#ffffff"
                border.color: "#d7deee"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 4

                    Label {
                        text: modelData.callsign
                        font.bold: true
                    }

                    Label {
                        text: modelData.share_enabled
                              ? qsTr("GPS: VKLOPLJEN • %1")
                                    .arg(modelData.location_mode)
                              : qsTr("GPS: IZKLOPLJEN")
                        color: modelData.share_enabled
                               ? "#15803d"
                               : "#64748b"
                    }
                }
            }
        }
    }
    Dialog {
        id: geoDialog

        property int userId: 0
        property string callsign: ""
        property bool shareEnabled: false
        property string locationMode: "off"
        property var visibleGroups: []

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 32 : 420, 420)
        modal: true
        title: callsign

        ColumnLayout {
            width: parent.width
            spacing: 10

            Switch {
                id: shareSwitch
                text: qsTr("GPS deljenje")
                checked: geoDialog.shareEnabled
            }

            ComboBox {
                id: modeBox
                Layout.fillWidth: true
                model: ["off", "city", "precise"]
                currentIndex: Math.max(0, model.indexOf(geoDialog.locationMode))
            }

            Label {
                text: qsTr("Vidijo skupine")
                font.bold: true
            }

            Repeater {
                id: geoGroupRepeater
                model: page.reflectorClient.portalAdminGroups

                delegate: CheckBox {
                    required property var modelData
                    property string groupCode: modelData.code

                    text: modelData.name
                    checked: geoDialog.visibleGroups.indexOf(groupCode) >= 0
                }
            }

            Button {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Shrani")

                onClicked: {
                    const groups = []

                    for (let i = 0; i < geoGroupRepeater.count; ++i) {
                        const item = geoGroupRepeater.itemAt(i)
                        if (item && item.checked)
                            groups.push(item.groupCode)
                    }

                    page.reflectorClient.savePortalAdminGeo(
                        geoDialog.userId,
                        shareSwitch.checked,
                        modeBox.currentText,
                        groups)

                    geoDialog.close()
                }
            }
        }
    }

    Component.onCompleted: {
        page.reflectorClient.refreshPortalAdminGroups()
        page.reflectorClient.refreshPortalAdminGeo()
    }
}
