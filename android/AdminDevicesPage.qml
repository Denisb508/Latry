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

    property int pendingTokenId: 0
    property string pendingCallsign: ""
    property string statusText: ""

    background: Rectangle {
        color: "#f4f7fb"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: page.contentPadding + page.safeAreaTop
        anchors.leftMargin: page.contentPadding + page.safeAreaLeft
        anchors.rightMargin: page.contentPadding + page.safeAreaRight
        anchors.bottomMargin: page.contentPadding + page.safeAreaBottom
        spacing: 12

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(
                backButton.implicitHeight,
                titleLabel.implicitHeight,
                refreshButton.implicitHeight
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
                text: qsTr("Naprave")
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                font.bold: true
            }

            ToolButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                Accessible.name: qsTr("Osveži naprave")
                onClicked: page.reflectorClient.refreshPortalAdminTokens()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: page.statusText.length > 0
            text: page.statusText
            wrapMode: Text.WordWrap
            color: "#475569"
        }

        ListView {
            id: devicesList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8

            model: page.reflectorClient.portalAdminTokens

            delegate: Rectangle {
                required property var modelData

                width: devicesList.width
                height: deviceLayout.implicitHeight + 24
                radius: 14
                color: "#ffffff"
                border.color: modelData.current_token
                              ? "#60a5fa"
                              : "#d7deee"
                border.width: modelData.current_token ? 2 : 1

                ColumnLayout {
                    id: deviceLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            text: modelData.callsign
                            font.pixelSize: page.uiMetrics.sectionTitleFontSize
                            font.bold: true
                        }

                        Label {
                            visible: modelData.current_token
                            text: qsTr("TA NAPRAVA")
                            color: "#2563eb"
                            font.bold: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: "#475569"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: modelData.last_used_at
                              ? qsTr("Nazadnje uporabljena: %1")
                                    .arg(modelData.last_used_at)
                              : qsTr("Še ni uporabljena")
                        color: "#64748b"
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: modelData.device_id
                                 && modelData.device_id.length > 0
                        text: qsTr("ID naprave: %1").arg(modelData.device_id)
                        elide: Text.ElideMiddle
                        color: "#64748b"
                    }

                    Button {
                        Layout.alignment: Qt.AlignRight
                        visible: !modelData.current_token
                        text: qsTr("🗑 Prekliči dostop")

                        onClicked: {
                            page.pendingTokenId = modelData.id
                            page.pendingCallsign = modelData.callsign
                            revokeConfirmDialog.open()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: revokeConfirmDialog

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 40 : 380, 380)
        modal: true
        title: qsTr("Prekliči napravo?")

        ColumnLayout {
            width: parent.width
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: qsTr("Latry dostop za %1 bo trajno preklican.")
                      .arg(page.pendingCallsign)
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Preklicanega dostopa v aplikaciji ni mogoče obnoviti.")
                wrapMode: Text.WordWrap
                color: "#64748b"
            }

            RowLayout {
                Layout.fillWidth: true

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTr("Ne")
                    onClicked: revokeConfirmDialog.close()
                }

                Button {
                    text: qsTr("Da, prekliči")
                    onClicked: {
                        revokeConfirmDialog.close()
                        page.statusText = qsTr("Preklicujem...")
                        page.reflectorClient.revokePortalAdminToken(
                            page.pendingTokenId
                        )
                    }
                }
            }
        }
    }

    Connections {
        target: page.reflectorClient

        function onPortalAdminTokenRevokeFinished(success, message) {
            page.statusText = message
        }
    }

    Component.onCompleted:
        page.reflectorClient.refreshPortalAdminTokens()
}
