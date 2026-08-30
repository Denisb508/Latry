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

    function listText(values) {
        if (!values || values.length === 0)
            return qsTr("Ni")

        if (values.join)
            return values.join(", ")

        return String(values)
    }

    function openGroupDialog(group) {
        groupDialog.editMode = group !== null
        groupDialog.isAdminGroup = group !== null && group.code === "ADMIN"
        groupDialog.selectedSources = group ? group.sources : []
        groupDialog.selectedCapabilities = group ? group.capabilities : []
        groupDialog.selectedMembers = group ? group.members : 0
        groupDialog.statusText = ""

        codeField.text = group ? group.code : ""
        nameField.text = group ? group.name : ""
        enabledSwitch.checked = group ? group.enabled : true

        groupDialog.open()

        Qt.callLater(function() {
            for (let i = 0; i < sourceRepeater.count; ++i) {
                const item = sourceRepeater.itemAt(i)
                if (item) {
                    item.checked = groupDialog.isAdminGroup
                            || groupDialog.selectedSources.indexOf(item.optionCode) >= 0
                }
            }

            for (let i = 0; i < capabilityRepeater.count; ++i) {
                const item = capabilityRepeater.itemAt(i)
                if (item) {
                    item.checked = groupDialog.isAdminGroup
                            || groupDialog.selectedCapabilities.indexOf(item.optionCode) >= 0
                }
            }
        })
    }

    function saveGroup() {
        const sources = []
        const capabilities = []

        for (let i = 0; i < sourceRepeater.count; ++i) {
            const item = sourceRepeater.itemAt(i)
            if (item && item.checked)
                sources.push(item.optionCode)
        }

        for (let i = 0; i < capabilityRepeater.count; ++i) {
            const item = capabilityRepeater.itemAt(i)
            if (item && item.checked)
                capabilities.push(item.optionCode)
        }

        groupDialog.statusText = qsTr("Shranjujem...")

        page.reflectorClient.savePortalAdminGroup(
            codeField.text,
            nameField.text,
            enabledSwitch.checked,
            sources,
            capabilities
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
                text: qsTr("Skupine")
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
                Accessible.name: qsTr("Dodaj skupino")
                onClicked: page.openGroupDialog(null)
            }

            ToolButton {
                id: refreshButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↻"
                font.pixelSize: page.uiMetrics.pageTitleFontSize
                Accessible.name: qsTr("Osveži skupine")

                onClicked: {
                    page.reflectorClient.refreshPortalAdminGroups()
                    page.reflectorClient.refreshPortalAdminGroupOptions()
                }
            }
        }

        ListView {
            id: groupsList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8

            model: page.reflectorClient.portalAdminGroups

            delegate: Rectangle {
                required property var modelData

                width: groupsList.width
                height: groupLayout.implicitHeight + 24
                radius: 14
                color: "#ffffff"
                border.color: modelData.code === "ADMIN"
                              ? "#94a3b8"
                              : "#d7deee"
                border.width: 1

                TapHandler {
                    onTapped: page.openGroupDialog(modelData)
                }

                ColumnLayout {
                    id: groupLayout

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
                                  ? qsTr("Aktivna")
                                  : qsTr("Onemogočena")
                            color: modelData.enabled
                                   ? "#15803d"
                                   : "#b91c1c"
                            font.bold: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Člani: %1").arg(modelData.members)
                        color: "#475569"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Viri: %1")
                              .arg(page.listText(modelData.sources))
                        wrapMode: Text.WordWrap
                        color: "#475569"
                    }

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Pravice: %1")
                              .arg(page.listText(modelData.capabilities))
                        wrapMode: Text.WordWrap
                        color: "#64748b"
                    }
                }
            }
        }
    }

    Dialog {
        id: groupDialog

        property bool editMode: false
        property bool isAdminGroup: false
        property int selectedMembers: 0
        property var selectedSources: []
        property var selectedCapabilities: []
        property string statusText: ""

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 32 : 440, 440)
        modal: true
        title: editMode
               ? qsTr("Uredi skupino")
               : qsTr("Dodaj skupino")

        ColumnLayout {
            width: parent.width
            spacing: 8

            TextField {
                id: codeField
                Layout.fillWidth: true
                placeholderText: qsTr("Koda skupine")
                readOnly: groupDialog.editMode
                inputMethodHints: Qt.ImhUppercaseOnly
            }

            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("Ime skupine")
            }

            Switch {
                id: enabledSwitch
                text: qsTr("Aktivna")
                enabled: !groupDialog.isAdminGroup
            }

            Label {
                text: qsTr("📡 Viri")
                font.bold: true
            }

            Repeater {
                id: sourceRepeater
                model: page.reflectorClient.portalAdminGroupSources

                delegate: CheckBox {
                    required property var modelData
                    property string optionCode: modelData.code

                    text: modelData.name + " (" + modelData.code + ")"
                    enabled: !groupDialog.isAdminGroup
                }
            }

            Label {
                text: qsTr("🔐 Administrativne pravice")
                font.bold: true
            }

            Repeater {
                id: capabilityRepeater
                model: page.reflectorClient.portalAdminGroupCapabilities

                delegate: CheckBox {
                    required property var modelData
                    property string optionCode: modelData.code

                    text: modelData.name
                    enabled: !groupDialog.isAdminGroup
                }
            }

            Label {
                Layout.fillWidth: true
                visible: groupDialog.isAdminGroup
                text: qsTr("ADMIN je zaščitena skupina. Vedno ima vse vire in vse administrativne pravice.")
                wrapMode: Text.WordWrap
                color: "#64748b"
            }

            Label {
                Layout.fillWidth: true
                visible: groupDialog.statusText.length > 0
                text: groupDialog.statusText
                wrapMode: Text.WordWrap
                color: "#475569"
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    visible: groupDialog.editMode
                             && !groupDialog.isAdminGroup
                    enabled: groupDialog.selectedMembers === 0
                    text: qsTr("🗑 Prekliči skupino")
                    onClicked: deleteConfirmDialog.open()
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    text: qsTr("Zapri")
                    onClicked: groupDialog.close()
                }

                Button {
                    text: qsTr("Shrani")
                    enabled: codeField.text.trim().length >= 2
                             && nameField.text.trim().length > 0
                    onClicked: page.saveGroup()
                }
            }

            Label {
                Layout.fillWidth: true
                visible: groupDialog.editMode
                         && !groupDialog.isAdminGroup
                         && groupDialog.selectedMembers > 0
                text: qsTr("Skupine z uporabniki ni mogoče preklicati.")
                color: "#b45309"
                wrapMode: Text.WordWrap
            }
        }
    }

    Dialog {
        id: deleteConfirmDialog

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 40 : 380, 380)
        modal: true
        title: qsTr("Prekliči skupino?")

        ColumnLayout {
            width: parent.width
            spacing: 14

            Label {
                Layout.fillWidth: true
                text: qsTr("Skupina %1 bo onemogočena in prestavljena v koš portala.")
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
                        groupDialog.statusText = qsTr("Preklicujem...")
                        page.reflectorClient.deletePortalAdminGroup(
                            codeField.text
                        )
                    }
                }
            }
        }
    }

    Connections {
        target: page.reflectorClient

        function onPortalAdminGroupSaveFinished(success, message) {
            groupDialog.statusText = message

            if (success)
                groupDialog.close()
        }

        function onPortalAdminGroupDeleteFinished(success, message) {
            groupDialog.statusText = message

            if (success)
                groupDialog.close()
        }
    }

    Component.onCompleted: {
        page.reflectorClient.refreshPortalAdminGroups()
        page.reflectorClient.refreshPortalAdminGroupOptions()
    }
}
