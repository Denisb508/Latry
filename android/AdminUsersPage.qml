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
    required property color accentColor
    required property var reflectorClient

    signal backRequested()

    function groupsText(groups) {
        if (!groups)
            return qsTr("Brez skupine")

        if (groups.join)
            return groups.length > 0
                    ? groups.join(", ")
                    : qsTr("Brez skupine")

        return String(groups)
    }

    function openUserDialog(user) {
        userDialog.editMode = user !== null
        userDialog.selectedGroups = user ? user.groups : []
        callsignField.text = user ? user.callsign : ""
        enabledSwitch.checked = user ? user.enabled : true
        userDialog.statusText = ""
        userDialog.open()

        Qt.callLater(function() {
            for (let i = 0; i < groupRepeater.count; ++i) {
                const item = groupRepeater.itemAt(i)
                if (item)
                    item.checked =
                        userDialog.selectedGroups.indexOf(item.groupCode) >= 0
            }
        })
    }

    function saveUser() {
        const groups = []

        for (let i = 0; i < groupRepeater.count; ++i) {
            const item = groupRepeater.itemAt(i)
            if (item && item.checked)
                groups.push(item.groupCode)
        }

        userDialog.statusText = qsTr("Shranjujem...")

        page.reflectorClient.savePortalAdminUser(
            callsignField.text,
            enabledSwitch.checked,
            groups
        )
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
                text: qsTr("Uporabniki")
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                font.bold: true
            }

            ToolButton {
                id: addButton
                anchors.right: refreshButton.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                Accessible.name: qsTr("Dodaj uporabnika")
                onClicked: page.openUserDialog(null)
            }

            ToolButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                Accessible.name: qsTr("Osveži uporabnike")
                onClicked: page.reflectorClient.refreshPortalAdminUsers()
            }
        }

        Label {
            Layout.fillWidth: true
            visible: usersList.count === 0
            text: qsTr("Ni uporabnikov za prikaz.")
            horizontalAlignment: Text.AlignHCenter
            color: "#64748b"
        }

        ListView {
            id: usersList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8

            model: page.reflectorClient.portalAdminUsers

            delegate: Rectangle {
                required property var modelData

                width: usersList.width
                height: userLayout.implicitHeight + 24
                radius: 14
                color: "#ffffff"
                border.color: "#d7deee"
                border.width: 1

                TapHandler {
                    onTapped: page.openUserDialog(modelData)
                }

                ColumnLayout {
                    id: userLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true

                        Label {
                            Layout.fillWidth: true
                            text: modelData.callsign
                            font.pixelSize: page.uiMetrics.sectionTitleFontSize
                            font.bold: true
                        }

                        Label {
                            text: modelData.enabled
                                  ? qsTr("Aktiven")
                                  : qsTr("Onemogočen")
                            color: modelData.enabled
                                   ? "#15803d"
                                   : "#b91c1c"
                            font.bold: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Skupine: %1")
                              .arg(page.groupsText(modelData.groups))
                        color: "#475569"
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Aktivne naprave: %1")
                              .arg(modelData.active_tokens)
                        color: "#64748b"
                    }
                }
            }
        }
    }

    Dialog {
        id: userDialog

        property bool editMode: false
        property var selectedGroups: []
        property string statusText: ""

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 32 : 420, 420)
        modal: true
        title: editMode
               ? qsTr("Uredi uporabnika")
               : qsTr("Dodaj uporabnika")

        ColumnLayout {
            width: parent.width
            spacing: 10

            TextField {
                id: callsignField
                Layout.fillWidth: true
                placeholderText: qsTr("Callsign")
                readOnly: userDialog.editMode
                inputMethodHints: Qt.ImhUppercaseOnly
            }

            Switch {
                id: enabledSwitch
                text: qsTr("Aktiven")
            }

            Label {
                text: qsTr("Skupine")
                font.bold: true
            }

            Repeater {
                id: groupRepeater
                model: page.reflectorClient.portalAdminGroups

                delegate: CheckBox {
                    required property var modelData
                    property string groupCode: modelData.code

                    text: modelData.name + " (" + modelData.code + ")"
                }
            }

            Label {
                Layout.fillWidth: true
                visible: userDialog.statusText.length > 0
                text: userDialog.statusText
                wrapMode: Text.WordWrap
                color: "#475569"
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    visible: userDialog.editMode
                    text: qsTr("🗑 Prekliči dostop")

                    contentItem: Label {
                        text: parent.text
                        color: "#b91c1c"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: deleteConfirmDialog.open()
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTr("Zapri")
                    onClicked: userDialog.close()
                }

                Button {
                    text: qsTr("Shrani")
                    enabled: callsignField.text.trim().length >= 2
                    onClicked: page.saveUser()
                }
            }
        }
    }

    Dialog {
        id: deleteConfirmDialog

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 40 : 380, 380)
        modal: true
        title: qsTr("Prekliči dostop?")

        ColumnLayout {
            width: parent.width
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: qsTr("Uporabnik %1 bo onemogočen in prestavljen v koš portala.")
                      .arg(callsignField.text)
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: qsTr("Njegovi obstoječi Latry dostopi ne bodo več veljavni.")
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
                    onClicked: deleteConfirmDialog.close()
                }

                Button {
                    text: qsTr("Da, prekliči")
                    onClicked: {
                        deleteConfirmDialog.close()
                        userDialog.statusText = qsTr("Preklicujem...")
                        page.reflectorClient.deletePortalAdminUser(
                            callsignField.text
                        )
                    }
                }
            }
        }
    }

    Connections {
        target: page.reflectorClient

        function onPortalAdminUserSaveFinished(success, message) {
            userDialog.statusText = message

            if (success)
                userDialog.close()
        }

        function onPortalAdminUserDeleteFinished(success, message) {
            userDialog.statusText = message

            if (success)
                userDialog.close()
        }
    }

    Component.onCompleted: {
        page.reflectorClient.refreshPortalAdminGroups()
        page.reflectorClient.refreshPortalAdminUsers()
    }
}
