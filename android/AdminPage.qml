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
    required property color surfaceColor
    required property color borderColor
    required property color accentColor
    required property var portalCapabilities

    signal backRequested()
    signal usersRequested()
    signal groupsRequested()
    signal sourcesRequested()
    signal devicesRequested()

    function hasCapability(code) {
        return page.portalCapabilities
                && page.portalCapabilities.indexOf(code) >= 0
    }

    background: Rectangle {
        color: "#f4f7fb"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: page.contentPadding + page.safeAreaTop
        anchors.leftMargin: page.contentPadding + page.safeAreaLeft
        anchors.rightMargin: page.contentPadding + page.safeAreaRight
        anchors.bottomMargin: page.contentPadding + page.safeAreaBottom
        spacing: 14

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
                text: qsTr("Administracija")
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                font.bold: true
            }
        }

        Label {
            Layout.fillWidth: true
            text: qsTr("Latry by OB508")
            horizontalAlignment: Text.AlignHCenter
            color: "#64748b"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            QuickSwitchTile {
                Layout.fillWidth: true
                visible: page.hasCapability("APP_USER_MANAGE")
                labelText: qsTr("👤 Uporabniki")
                primaryText: qsTr("Upravljanje uporabnikov")
                secondaryText: qsTr("Dostop, skupine in pravice")
                accentColor: page.accentColor
                emphasized: true
                onClicked: page.usersRequested()
            }

            QuickSwitchTile {
                Layout.fillWidth: true
                visible: page.hasCapability("APP_GROUP_MANAGE")
                labelText: qsTr("👥 Skupine")
                primaryText: qsTr("Upravljanje skupin")
                secondaryText: qsTr("Viri in administrativne pravice")
                accentColor: page.accentColor
                onClicked: page.groupsRequested()
            }

            QuickSwitchTile {
                Layout.fillWidth: true
                visible: page.hasCapability("APP_SOURCE_MANAGE")
                labelText: qsTr("📡 Viri")
                primaryText: qsTr("Upravljanje virov")
                secondaryText: qsTr("SvxReflector, FRN in prihodnji viri")
                accentColor: page.accentColor
                onClicked: page.sourcesRequested()
            }

            QuickSwitchTile {
                Layout.fillWidth: true
                visible: page.hasCapability("APP_TOKEN_MANAGE")
                labelText: qsTr("📲 Naprave")
                primaryText: qsTr("Upravljanje naprav")
                secondaryText: qsTr("Dostopi in preklic naprav")
                accentColor: page.accentColor
                onClicked: page.devicesRequested()
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
