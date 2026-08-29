from pathlib import Path

HOME = Path('android/HomePage.qml')

s = HOME.read_text()

if 'function refreshFrnUsers()' in s:
    print('FRN feed polling already present.')
    raise SystemExit(0)

s = s.replace(
    '    property var reflectorUsers: []\n    property var frnUsers: []\n',
    '    property var reflectorUsers: []\n    property var frnUsers: []\n    property string frnStatusMessage: ""\n    readonly property string frnStatusUrl: "https://svxportal.pmr446.si/frn_users.json"\n',
    1)

marker = '''    Connections {\n        target: page.reflectorClient\n'''

frn_logic = '''    function normalizedFrnUsers(items) {\n        const result = []\n        if (!items || !Array.isArray(items))\n            return result\n\n        for (let i = 0; i < items.length; ++i) {\n            let value = items[i]\n            if (value && typeof value === "object")\n                value = value.display || value.name || value.callsign || value.user || ""\n\n            const label = String(value).trim()\n            if (label.length > 0 && result.indexOf(label) < 0)\n                result.push(label)\n        }\n\n        result.sort(function(a, b) {\n            return a.localeCompare(b)\n        })\n        return result\n    }\n\n    function refreshFrnUsers() {\n        if (!page.showFrnUsers) {\n            page.frnUsers = []\n            page.frnStatusMessage = ""\n            return\n        }\n\n        const xhr = new XMLHttpRequest()\n        xhr.onreadystatechange = function() {\n            if (xhr.readyState !== XMLHttpRequest.DONE)\n                return\n\n            if (xhr.status < 200 || xhr.status >= 300) {\n                page.frnStatusMessage = qsTr("FRN seznam trenutno ni dosegljiv.")\n                return\n            }\n\n            try {\n                const parsed = JSON.parse(xhr.responseText)\n                const users = Array.isArray(parsed) ? parsed : parsed.users\n                page.frnUsers = page.normalizedFrnUsers(users)\n                page.frnStatusMessage = page.frnUsers.length === 0\n                        ? qsTr("Trenutno ni prijavljenih FRN uporabnikov.")\n                        : ""\n            } catch (error) {\n                console.warn("Invalid FRN users JSON", error)\n                page.frnStatusMessage = qsTr("FRN seznam ima napačen format.")\n            }\n        }\n        xhr.open("GET", page.frnStatusUrl + "?t=" + Date.now())\n        xhr.send()\n    }\n\n    onShowFrnUsersChanged: {\n        if (showFrnUsers)\n            refreshFrnUsers()\n        else {\n            frnUsers = []\n            frnStatusMessage = ""\n        }\n    }\n\n    Timer {\n        interval: 15000\n        repeat: true\n        running: page.showFrnUsers\n        triggeredOnStart: true\n        onTriggered: page.refreshFrnUsers()\n    }\n\n'''

if marker not in s:
    raise SystemExit('Reflector Connections marker not found')
s = s.replace(marker, frn_logic + marker, 1)

old = '''                        Label {\n                            visible: page.showFrnUsers\n                            Layout.fillWidth: true\n                            text: qsTr("FRN uporabniki")\n                            font.bold: true\n                            color: "#334155"\n                        }\n\n                        Label {\n                            visible: page.showFrnUsers && page.frnUsers.length === 0\n                            Layout.fillWidth: true\n                            text: qsTr("FRN seznam bo prikazan, ko je nastavljen FRN status vir.")\n                            wrapMode: Text.WordWrap\n                            color: "#64748b"\n                        }\n'''

new = '''                        Label {\n                            visible: page.showFrnUsers\n                            Layout.fillWidth: true\n                            text: qsTr("FRN uporabniki (%1)").arg(page.frnUsers.length)\n                            font.bold: true\n                            color: "#334155"\n                        }\n\n                        Flow {\n                            visible: page.showFrnUsers && page.frnUsers.length > 0\n                            Layout.fillWidth: true\n                            spacing: 6\n\n                            Repeater {\n                                model: page.frnUsers\n                                delegate: Rectangle {\n                                    required property string modelData\n                                    radius: 10\n                                    color: "#e0f2fe"\n                                    border.color: "#7dd3fc"\n                                    implicitWidth: frnUserLabel.implicitWidth + 18\n                                    implicitHeight: frnUserLabel.implicitHeight + 10\n\n                                    Label {\n                                        id: frnUserLabel\n                                        anchors.centerIn: parent\n                                        text: "● " + modelData\n                                        color: "#075985"\n                                        font.bold: true\n                                    }\n                                }\n                            }\n                        }\n\n                        Label {\n                            visible: page.showFrnUsers && page.frnStatusMessage.length > 0\n                            Layout.fillWidth: true\n                            text: page.frnStatusMessage\n                            wrapMode: Text.WordWrap\n                            color: "#64748b"\n                        }\n'''

if old not in s:
    raise SystemExit('FRN placeholder block not found')
s = s.replace(old, new, 1)

HOME.write_text(s)
print('FRN user feed polling patch applied.')
