from pathlib import Path

HOME = Path('android/HomePage.qml')
s = HOME.read_text()

old = '''                        Label {
                            visible: page.showFrnUsers && page.frnUsers.length > 0
                            Layout.fillWidth: true
                            text: qsTr("Strežnik: %1 uporabnikov • Posodobljeno: %2")
                                  .arg(page.frnServerCount)
                                  .arg(page.frnUpdated.length > 0 ? page.frnUpdated : qsTr("ni podatka"))
                            color: "#64748b"
                            font.pixelSize: page.uiMetrics.captionFontSize
                            wrapMode: Text.WordWrap
                        }

                        ColumnLayout {
                            visible: page.showFrnUsers && page.frnUsers.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: page.frnUsers

                                delegate: Frame {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    padding: 9

                                    background: Rectangle {
                                        radius: 10
                                        color: "#e0f2fe"
                                        border.color: "#7dd3fc"
                                        border.width: 1
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: 2

                                        Label {
                                            Layout.fillWidth: true
                                            text: "● " + (modelData.display || modelData.callsign || qsTr("FRN uporabnik"))
                                            color: "#075985"
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Callsign: %1").arg(modelData.callsign || "—")
                                            color: "#334155"
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Ime: %1").arg(modelData.name || "—")
                                            color: "#334155"
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Lokacija: %1").arg(modelData.city || "—")
                                            color: "#334155"
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Klient: %1").arg(modelData.client || "—")
                                            color: "#334155"
                                            wrapMode: Text.WordWrap
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("FRN state: %1").arg(modelData.state !== "" ? modelData.state : "—")
                                            color: "#334155"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
'''

new = '''                        Flow {
                            visible: page.showFrnUsers && page.frnUsers.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: page.frnUsers

                                delegate: Rectangle {
                                    required property var modelData
                                    radius: 10
                                    color: "#e0f2fe"
                                    border.color: "#7dd3fc"
                                    border.width: 1
                                    implicitWidth: frnUserLabel.implicitWidth + 18
                                    implicitHeight: frnUserLabel.implicitHeight + 10

                                    Label {
                                        id: frnUserLabel
                                        anchors.centerIn: parent
                                        text: "● " + (modelData.display || modelData.callsign || qsTr("FRN uporabnik"))
                                        color: "#075985"
                                        font.bold: true
                                    }
                                }
                            }
                        }
'''

if old in s:
    s = s.replace(old, new, 1)
elif 'text: "● " + (modelData.display || modelData.callsign || qsTr("FRN uporabnik"))' in s and 'FRN state:' not in s:
    print('Simple FRN display already present.')
    raise SystemExit(0)
else:
    raise SystemExit('Detailed FRN UI block not found')

HOME.write_text(s)
print('Simple FRN display applied: count in header + display only.')
