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

    function openSourceDialog(source) {
        sourceDialog.editMode = source !== null
        sourceDialog.statusText = ""

        codeField.text = source ? source.code : ""
        nameField.text = source ? source.name : ""
        typeField.text = source ? source.type : ""
        endpointField.text = source ? source.endpoint : ""
        enabledSwitch.checked = source ? source.enabled : true
        sortOrderSpin.value = source ? source.sort_order : 100

        sourceDialog.open()
    }

    function saveSource() {
        sourceDialog.statusText = qsTr("Shranjujem...")

        page.reflectorClient.savePortalAdminSource(
            codeField.text,
            nameField.text,
            typeField.text,
            endpointField.text,
            enabledSwitch.checked,
            sortOrderSpin.value
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
                text: qsTr("Viri")
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
                Accessible.name: qsTr("Dodaj vir")
                onClicked: page.openSourceDialog(null)
            }

            ToolButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                Accessible.name: qsTr("Osveži vire")
                onClicked: page.reflectorClient.refreshPortalAdminSources()
            }
        }

        ListView {
            id: sourcesList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8

            model: page.reflectorClient.portalAdminSources

            delegate: Rectangle {
                required property var modelData

                width: sourcesList.width
                height: sourceLayout.implicitHeight + 24
                radius: 14
                color: "#ffffff"
                border.color: "#d7deee"
                border.width: 1

                TapHandler {
                    onTapped: page.openSourceDialog(modelData)
                }

                ColumnLayout {
                    id: sourceLayout

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
                            text: modelData.name + " (" + modelData.code + ")"
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
                        text: qsTr("Tip: %1").arg(modelData.type)
                        color: "#475569"
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: modelData.endpoint.length > 0
                        text: qsTr("Endpoint: %1").arg(modelData.endpoint)
                        wrapMode: Text.WordWrap
                        color: "#475569"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Skupine: %1   •   Vrstni red: %2")
                              .arg(modelData.group_count)
                              .arg(modelData.sort_order)
                        color: "#64748b"
                    }
                }
            }
        }
    }

    Dialog {
        id: sourceDialog

        property bool editMode: false
        property string statusText: ""

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 32 : 440, 440)
        modal: true
        title: editMode
               ? qsTr("Uredi vir")
               : qsTr("Dodaj vir")

        ColumnLayout {
            width: parent.width
            spacing: 9

            TextField {
                id: codeField
                Layout.fillWidth: true
                placeholderText: qsTr("Koda, npr. FRN_TEST")
                readOnly: sourceDialog.editMode
                inputMethodHints: Qt.ImhUppercaseOnly
            }

            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("Ime vira")
            }

            TextField {
                id: typeField
                Layout.fillWidth: true
                placeholderText: qsTr("Tip, npr. frn ali svxreflector")
            }

            TextField {
                id: endpointField
                Layout.fillWidth: true
                placeholderText: qsTr("Endpoint, npr. /frn_test_proxy.php")
            }

            Switch {
                id: enabledSwitch
                text: qsTr("Aktiven")
            }

            RowLayout {
                Layout.fillWidth: true

                Label {
                    text: qsTr("Vrstni red")
                }

                Item {
                    Layout.fillWidth: true
                }

                SpinBox {
                    id: sortOrderSpin
                    from: 0
                    to: 10000
                    value: 100
                }
            }

            Label {
                Layout.fillWidth: true
                visible: sourceDialog.statusText.length > 0
                text: sourceDialog.statusText
                wrapMode: Text.WordWrap
                color: "#475569"
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    visible: sourceDialog.editMode
                    text: qsTr("🗑 Prekliči vir")
                    onClicked: deleteConfirmDialog.open()
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTr("Zapri")
                    onClicked: sourceDialog.close()
                }

                Button {
                    text: qsTr("Shrani")
                    enabled: codeField.text.trim().length >= 2
                             && nameField.text.trim().length > 0
                             && typeField.text.trim().length >= 2
                    onClicked: page.saveSource()
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
        title: qsTr("Prekliči vir?")

        ColumnLayout {
            width: parent.width
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: qsTr("Vir %1 bo onemogočen in prestavljen v koš portala.")
                      .arg(codeField.text)
                wrapMode: Text.WordWrap
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
                        sourceDialog.statusText = qsTr("Preklicujem...")
                        page.reflectorClient.deletePortalAdminSource(
                            codeField.text
                        )
                    }
                }
            }
        }
    }

    Connections {
        target: page.reflectorClient

        function onPortalAdminSourceSaveFinished(success, message) {
            sourceDialog.statusText = message

            if (success)
                sourceDialog.close()
        }

        function onPortalAdminSourceDeleteFinished(success, message) {
            sourceDialog.statusText = message

            if (success)
                sourceDialog.close()
        }
    }

    Component.onCompleted:
        page.reflectorClient.refreshPortalAdminSources()
}
