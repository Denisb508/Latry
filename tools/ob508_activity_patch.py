from pathlib import Path

HOME = Path('android/HomePage.qml')
s = HOME.read_text()

if 'property string frnUpdated' in s and 'FRN state:' in s:
    print('Full FRN details already present.')
    raise SystemExit(0)

s = s.replace(
    '    property string frnStatusMessage: ""\n    readonly property string frnStatusUrl: "https://svxportal.pmr446.si/frn_users.json"\n',
    '    property string frnStatusMessage: ""\n    property string frnUpdated: ""\n    property int frnServerCount: 0\n    readonly property string frnStatusUrl: "https://svxportal.pmr446.si/frn_users.json"\n',
    1)

old_normalizer = '''    function normalizedFrnUsers(items) {
        const result = []
        if (!items || !Array.isArray(items))
            return result

        for (let i = 0; i < items.length; ++i) {
            let value = items[i]
            if (value && typeof value === "object")
                value = value.display || value.name || value.callsign || value.user || ""

            const label = String(value).trim()
            if (label.length > 0 && result.indexOf(label) < 0)
                result.push(label)
        }

        result.sort(function(a, b) {
            return a.localeCompare(b)
        })
        return result
    }
'''

new_normalizer = '''    function normalizedFrnUsers(items) {
        const result = []
        const seen = {}
        if (!items || !Array.isArray(items))
            return result

        for (let i = 0; i < items.length; ++i) {
            const value = items[i]
            let user

            if (value && typeof value === "object") {
                const callsign = String(value.callsign || value.user || "").trim()
                const name = String(value.name || "").trim()
                let display = String(value.display || "").trim()
                if (display.length === 0)
                    display = callsign + (name.length > 0 ? ", " + name : "")

                user = {
                    display: display,
                    callsign: callsign,
                    name: name,
                    city: String(value.city || "").trim(),
                    client: String(value.client || "").trim(),
                    state: value.state === undefined || value.state === null
                           ? ""
                           : String(value.state)
                }
            } else {
                const label = String(value || "").trim()
                user = {
                    display: label,
                    callsign: label,
                    name: "",
                    city: "",
                    client: "",
                    state: ""
                }
            }

            if (user.display.length === 0 && user.callsign.length === 0)
                continue

            const key = String(user.callsign || user.display).toUpperCase()
            if (seen[key])
                continue
            seen[key] = true
            result.push(user)
        }

        result.sort(function(a, b) {
            return String(a.callsign || a.display).localeCompare(String(b.callsign || b.display))
        })
        return result
    }
'''

if old_normalizer not in s:
    raise SystemExit('Old FRN normalizer not found')
s = s.replace(old_normalizer, new_normalizer, 1)

old_refresh = '''                const parsed = JSON.parse(xhr.responseText)
                const users = Array.isArray(parsed) ? parsed : parsed.users
                page.frnUsers = page.normalizedFrnUsers(users)
                page.frnStatusMessage = page.frnUsers.length === 0
                        ? qsTr("Trenutno ni prijavljenih FRN uporabnikov.")
                        : ""
'''

new_refresh = '''                const parsed = JSON.parse(xhr.responseText)
                const envelope = !Array.isArray(parsed) && parsed && typeof parsed === "object"
                const users = Array.isArray(parsed) ? parsed : parsed.users
                page.frnUsers = page.normalizedFrnUsers(users)
                page.frnServerCount = envelope && parsed.count !== undefined
                        ? Number(parsed.count)
                        : page.frnUsers.length
                page.frnUpdated = envelope && parsed.updated
                        ? String(parsed.updated)
                        : ""
                page.frnStatusMessage = page.frnUsers.length === 0
                        ? qsTr("Trenutno ni prijavljenih FRN uporabnikov.")
                        : ""
'''

if old_refresh not in s:
    raise SystemExit('FRN refresh block not found')
s = s.replace(old_refresh, new_refresh, 1)

s = s.replace(
    '''        page.frnUsers = []
        page.frnStatusMessage = ""
        return
''',
    '''        page.frnUsers = []
        page.frnStatusMessage = ""
        page.frnUpdated = ""
        page.frnServerCount = 0
        return
''',
    1)

s = s.replace(
    '''            frnUsers = []
            frnStatusMessage = ""
''',
    '''            frnUsers = []
            frnStatusMessage = ""
            frnUpdated = ""
            frnServerCount = 0
''',
    1)

old_ui = '''                        Flow {
                            visible: page.showFrnUsers && page.frnUsers.length > 0
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: page.frnUsers
                                delegate: Rectangle {
                                    required property string modelData
                                    radius: 10
                                    color: "#e0f2fe"
                                    border.color: "#7dd3fc"
                                    implicitWidth: frnUserLabel.implicitWidth + 18
                                    implicitHeight: frnUserLabel.implicitHeight + 10

                                    Label {
                                        id: frnUserLabel
                                        anchors.centerIn: parent
                                        text: "● " + modelData
                                        color: "#075985"
                                        font.bold: true
                                    }
                                }
                            }
                        }
'''

new_ui = '''                        Label {
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

if old_ui not in s:
    raise SystemExit('Old FRN chip UI not found')
s = s.replace(old_ui, new_ui, 1)

HOME.write_text(s)
print('Full FRN details patch applied.')
