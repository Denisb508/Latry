from pathlib import Path

MAIN = Path('android/Main.qml')
HOME = Path('android/HomePage.qml')
SETTINGS = Path('android/SettingsPage.qml')


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'{label}: marker not found')
    return text.replace(old, new, 1)


# Main.qml: persistent settings and wiring
s = MAIN.read_text()
s = replace_once(
    s,
    '        property bool tapToTalkButtonVisible: true\n        property bool liveTranscriptionEnabled: false\n',
    '        property bool tapToTalkButtonVisible: true\n        property bool showReflectorUsers: true\n        property bool showFrnUsers: false\n        property bool liveTranscriptionEnabled: false\n',
    'main settings')
s = replace_once(
    s,
    '    function updateTapToTalkButtonVisible(visible) {\n        saved.tapToTalkButtonVisible = !!visible\n    }\n',
    '    function updateTapToTalkButtonVisible(visible) {\n        saved.tapToTalkButtonVisible = !!visible\n    }\n\n    function updateShowReflectorUsers(visible) {\n        saved.showReflectorUsers = !!visible\n    }\n\n    function updateShowFrnUsers(visible) {\n        saved.showFrnUsers = !!visible\n    }\n',
    'main update funcs')
s = replace_once(
    s,
    '            tapToTalkButtonVisible: saved.tapToTalkButtonVisible\n',
    '            tapToTalkButtonVisible: saved.tapToTalkButtonVisible\n            showReflectorUsers: saved.showReflectorUsers\n            showFrnUsers: saved.showFrnUsers\n',
    'home props')
s = replace_once(
    s,
    '            tapToTalkButtonVisible: saved.tapToTalkButtonVisible\n\n            onBackRequested: stackView.pop()\n',
    '            tapToTalkButtonVisible: saved.tapToTalkButtonVisible\n            showReflectorUsers: saved.showReflectorUsers\n            showFrnUsers: saved.showFrnUsers\n\n            onBackRequested: stackView.pop()\n',
    'settings props')
s = replace_once(
    s,
    '            onTapToTalkButtonVisibleRequested: visible => window.updateTapToTalkButtonVisible(visible)\n',
    '            onTapToTalkButtonVisibleRequested: visible => window.updateTapToTalkButtonVisible(visible)\n            onShowReflectorUsersRequested: visible => window.updateShowReflectorUsers(visible)\n            onShowFrnUsersRequested: visible => window.updateShowFrnUsers(visible)\n',
    'settings signals')
MAIN.write_text(s)

# HomePage.qml: OB508 title + live reflector list model + activity card shell
s = HOME.read_text()
s = replace_once(
    s,
    '    required property bool tapToTalkButtonVisible\n',
    '    required property bool tapToTalkButtonVisible\n    required property bool showReflectorUsers\n    required property bool showFrnUsers\n\n    property var reflectorUsers: []\n    property var frnUsers: []\n',
    'home required props')
s = replace_once(
    s,
    '    function talkgroupLabel(talkgroup) {\n        return talkgroup === 0 ? qsTr("Monitor Mode") : qsTr("TG %1").arg(talkgroup)\n    }\n',
    '''    function talkgroupLabel(talkgroup) {\n        return talkgroup === 0 ? qsTr("Monitor Mode") : qsTr("TG %1").arg(talkgroup)\n    }\n\n    function filteredObUsers(nodes) {\n        const result = []\n        for (let i = 0; i < nodes.length; ++i) {\n            const cs = String(nodes[i]).trim().toUpperCase()\n            if (/^OB[0-9A-Z]+$/.test(cs) && result.indexOf(cs) < 0)\n                result.push(cs)\n        }\n        result.sort()\n        return result\n    }\n\n    function addReflectorUser(callsign) {\n        const next = reflectorUsers.slice()\n        const filtered = filteredObUsers([callsign])\n        if (filtered.length === 0 || next.indexOf(filtered[0]) >= 0)\n            return\n        next.push(filtered[0])\n        next.sort()\n        reflectorUsers = next\n    }\n\n    function removeReflectorUser(callsign) {\n        const cs = String(callsign).trim().toUpperCase()\n        const next = reflectorUsers.slice()\n        const idx = next.indexOf(cs)\n        if (idx >= 0) {\n            next.splice(idx, 1)\n            reflectorUsers = next\n        }\n    }\n\n    Connections {\n        target: page.reflectorClient\n\n        function onConnectedNodesChanged(nodes) {\n            page.reflectorUsers = page.filteredObUsers(nodes)\n        }\n\n        function onNodeJoined(callsign) {\n            page.addReflectorUser(callsign)\n        }\n\n        function onNodeLeft(callsign) {\n            page.removeReflectorUser(callsign)\n        }\n    }\n''',
    'home funcs')
s = replace_once(s, '                text: qsTr("Latry")\n', '                text: qsTr("Latry by OB508")\n', 'home title')
activity_card = '''\n                Frame {\n                    width: parent.width\n                    visible: page.showReflectorUsers || page.showFrnUsers\n                    padding: page.uiMetrics.sectionPadding\n                    Accessible.role: Accessible.Grouping\n                    Accessible.name: qsTr("Gateway activity")\n\n                    background: Rectangle {\n                        Accessible.ignored: true\n                        radius: page.uiMetrics.frameRadius\n                        color: page.surfaceColor\n                        border.color: page.borderColor\n                    }\n\n                    contentItem: ColumnLayout {\n                        spacing: 8\n\n                        Label {\n                            text: qsTr("Aktivnosti na prehodih")\n                            font.pixelSize: page.uiMetrics.sectionTitleFontSize\n                            font.bold: true\n                            color: "#0f172a"\n                        }\n\n                        Label {\n                            visible: page.showReflectorUsers\n                            Layout.fillWidth: true\n                            text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)\n                            font.bold: true\n                            color: "#334155"\n                        }\n\n                        Flow {\n                            visible: page.showReflectorUsers\n                            Layout.fillWidth: true\n                            spacing: 6\n\n                            Repeater {\n                                model: page.reflectorUsers\n                                delegate: Rectangle {\n                                    required property string modelData\n                                    radius: 10\n                                    color: "#e8f5e9"\n                                    border.color: "#86c98a"\n                                    implicitWidth: userLabel.implicitWidth + 18\n                                    implicitHeight: userLabel.implicitHeight + 10\n                                    Label {\n                                        id: userLabel\n                                        anchors.centerIn: parent\n                                        text: "● " + modelData\n                                        color: "#216e2d"\n                                        font.bold: true\n                                    }\n                                }\n                            }\n                        }\n\n                        Label {\n                            visible: page.showReflectorUsers && page.reflectorUsers.length === 0\n                            text: page.reflectorClient.isDisconnected\n                                  ? qsTr("SvxReflector ni povezan.")\n                                  : qsTr("Trenutno ni prijavljenih OB uporabnikov.")\n                            color: "#64748b"\n                            wrapMode: Text.WordWrap\n                        }\n\n                        Rectangle {\n                            visible: page.showReflectorUsers && page.showFrnUsers\n                            Layout.fillWidth: true\n                            implicitHeight: 1\n                            color: "#e2e8f0"\n                        }\n\n                        Label {\n                            visible: page.showFrnUsers\n                            Layout.fillWidth: true\n                            text: qsTr("FRN uporabniki")\n                            font.bold: true\n                            color: "#334155"\n                        }\n\n                        Label {\n                            visible: page.showFrnUsers && page.frnUsers.length === 0\n                            Layout.fillWidth: true\n                            text: qsTr("FRN seznam bo prikazan, ko je nastavljen FRN status vir.")\n                            wrapMode: Text.WordWrap\n                            color: "#64748b"\n                        }\n                    }\n                }\n'''
marker = '''                Frame {\n                    width: parent.width\n                    padding: page.uiMetrics.sectionPadding\n                    Accessible.role: Accessible.Grouping\n                    Accessible.name: qsTr("Live session")\n'''
s = replace_once(s, marker, activity_card + '\n' + marker, 'activity card')
HOME.write_text(s)

# SettingsPage.qml: two toggles in Radio section
s = SETTINGS.read_text()
s = replace_once(
    s,
    '    required property bool tapToTalkButtonVisible\n',
    '    required property bool tapToTalkButtonVisible\n    required property bool showReflectorUsers\n    required property bool showFrnUsers\n',
    'settings required props')
s = replace_once(
    s,
    '    signal tapToTalkButtonVisibleRequested(bool visible)\n',
    '    signal tapToTalkButtonVisibleRequested(bool visible)\n    signal showReflectorUsersRequested(bool visible)\n    signal showFrnUsersRequested(bool visible)\n',
    'settings signals')
settings_card = '''\n                Frame {\n                    visible: !page.compactSettingsMode || page.compactSection === "radio"\n                    width: parent.width\n                    padding: page.uiMetrics.sectionPadding\n                    implicitHeight: implicitContentHeight + topPadding + bottomPadding\n                    Accessible.role: Accessible.Grouping\n                    Accessible.name: qsTr("Gateway activity")\n\n                    background: Rectangle {\n                        Accessible.ignored: true\n                        radius: page.uiMetrics.frameRadius\n                        color: page.surfaceColor\n                        border.color: page.borderColor\n                    }\n\n                    contentItem: ColumnLayout {\n                        spacing: 12\n\n                        Label {\n                            text: qsTr("Aktivnosti na prehodih")\n                            font.pixelSize: page.uiMetrics.sectionTitleFontSize\n                            font.bold: true\n                        }\n\n                        Label {\n                            Layout.fillWidth: true\n                            text: qsTr("Izberi, katere sezname uporabnikov želiš prikazovati na začetnem zaslonu.")\n                            wrapMode: Text.WordWrap\n                            color: "#556070"\n                        }\n\n                        RowLayout {\n                            Layout.fillWidth: true\n                            Label {\n                                Layout.fillWidth: true\n                                text: qsTr("Prikaži SvxReflector uporabnike")\n                                font.bold: true\n                                wrapMode: Text.WordWrap\n                            }\n                            Switch {\n                                checked: page.showReflectorUsers\n                                onClicked: page.showReflectorUsersRequested(checked)\n                            }\n                        }\n\n                        RowLayout {\n                            Layout.fillWidth: true\n                            Label {\n                                Layout.fillWidth: true\n                                text: qsTr("Prikaži FRN uporabnike")\n                                font.bold: true\n                                wrapMode: Text.WordWrap\n                            }\n                            Switch {\n                                checked: page.showFrnUsers\n                                onClicked: page.showFrnUsersRequested(checked)\n                            }\n                        }\n                    }\n                }\n'''
marker = '''                Frame {\n                    visible: !page.compactSettingsMode || page.compactSection === "radio"\n                    width: parent.width\n                    padding: page.uiMetrics.sectionPadding\n                    implicitHeight: implicitContentHeight + topPadding + bottomPadding\n                    Accessible.role: Accessible.Grouping\n                    Accessible.name: qsTr("On-screen PTT")\n'''
s = replace_once(s, marker, settings_card + '\n' + marker, 'settings activity card')
SETTINGS.write_text(s)

print('OB508 activity UI patch applied.')
