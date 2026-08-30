from pathlib import Path

HOME = Path('android/HomePage.qml')
s = HOME.read_text()
changed = False

# SvxReflector: show every non-empty connected callsign, not only OB*.
old_filter = '''    function filteredObUsers(nodes) {
        const result = []
        for (let i = 0; i < nodes.length; ++i) {
            const cs = String(nodes[i]).trim().toUpperCase()
            if (/^OB[0-9A-Z]+$/.test(cs) && result.indexOf(cs) < 0)
                result.push(cs)
        }
        result.sort()
        return result
    }
'''
base_filter = '''    function normalizedReflectorUsers(nodes) {
        const result = []
        if (!nodes || !Array.isArray(nodes))
            return result

        for (let i = 0; i < nodes.length; ++i) {
            const cs = String(nodes[i] || "").trim().toUpperCase()
            if (cs.length > 0 && result.indexOf(cs) < 0)
                result.push(cs)
        }
        result.sort()
        return result
    }
'''
self_filter = '''    function normalizedReflectorUsers(nodes) {
        const result = []
        if (nodes && Array.isArray(nodes)) {
            for (let i = 0; i < nodes.length; ++i) {
                const cs = String(nodes[i] || "").trim().toUpperCase()
                if (cs.length > 0 && result.indexOf(cs) < 0)
                    result.push(cs)
            }
        }

        const ownCallsign = String(page.selectedProfileCallsign || "").trim().toUpperCase()
        if (ownCallsign.length > 0 && result.indexOf(ownCallsign) < 0)
            result.push(ownCallsign)

        result.sort()
        return result
    }
'''

if old_filter in s:
    s = s.replace(old_filter, self_filter, 1)
    changed = True
elif base_filter in s:
    s = s.replace(base_filter, self_filter, 1)
    changed = True

s2 = s.replace('const filtered = filteredObUsers([callsign])',
               'const filtered = normalizedReflectorUsers([callsign])')
if s2 != s:
    s = s2
    changed = True

s2 = s.replace('page.reflectorUsers = page.filteredObUsers(nodes)',
               'page.reflectorUsers = page.normalizedReflectorUsers(nodes)')
if s2 != s:
    s = s2
    changed = True

s2 = s.replace('qsTr("Trenutno ni prijavljenih OB uporabnikov.")',
               'qsTr("Trenutno ni prijavljenih uporabnikov.")')
if s2 != s:
    s = s2
    changed = True

# FRN: normalize to display strings only for current simple view.
start = s.find('    function normalizedFrnUsers(items) {')
end = s.find('\n    function refreshFrnUsers()', start)
if start >= 0 and end > start:
    simple_normalizer = '''    function normalizedFrnUsers(items) {
        const result = []
        if (!items || !Array.isArray(items))
            return result

        for (let i = 0; i < items.length; ++i) {
            const value = items[i]
            let label = ""
            if (value && typeof value === "object")
                label = String(value.display || value.callsign || value.name || value.user || "").trim()
            else
                label = String(value || "").trim()

            if (label.length > 0 && result.indexOf(label) < 0)
                result.push(label)
        }

        result.sort(function(a, b) { return a.localeCompare(b) })
        return result
    }
'''
    if s[start:end] != simple_normalizer.rstrip('\n'):
        s = s[:start] + simple_normalizer + s[end+1:]
        changed = True

s2 = s.replace('text: qsTr("FRN uporabniki (%1)").arg(page.frnUsers.length)',
               'text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)')
if s2 != s:
    s = s2
    changed = True

# Compact gateway headings.
old_title = '''                        Label {
                            text: qsTr("Aktivnosti na prehodih")
                            font.pixelSize: page.uiMetrics.sectionTitleFontSize
                            font.bold: true
                            color: "#0f172a"
                        }
'''
new_title = '''                        Label {
                            text: qsTr("Aktivnosti na prehodih")
                            font.pixelSize: Math.max(13, page.uiMetrics.captionFontSize + 1)
                            font.bold: true
                            color: "#0f172a"
                        }
'''
if old_title in s:
    s = s.replace(old_title, new_title, 1)
    changed = True

old_svx_heading = '''                        Label {
                            visible: page.showReflectorUsers
                            Layout.fillWidth: true
                            text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)
                            font.bold: true
                            color: "#334155"
                        }
'''
new_svx_heading = '''                        Label {
                            visible: page.showReflectorUsers
                            Layout.fillWidth: true
                            text: qsTr("Prijavljeni na SvxReflector (%1)").arg(page.reflectorUsers.length)
                            font.pixelSize: page.uiMetrics.captionFontSize
                            font.bold: true
                            color: "#334155"
                        }
'''
if old_svx_heading in s:
    s = s.replace(old_svx_heading, new_svx_heading, 1)
    changed = True

old_frn_heading = '''                        Label {
                            visible: page.showFrnUsers
                            Layout.fillWidth: true
                            text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)
                            font.bold: true
                            color: "#334155"
                        }
'''
new_frn_heading = '''                        Label {
                            visible: page.showFrnUsers
                            Layout.fillWidth: true
                            text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)
                            font.pixelSize: page.uiMetrics.captionFontSize
                            font.bold: true
                            color: "#334155"
                        }
'''
if old_frn_heading in s:
    s = s.replace(old_frn_heading, new_frn_heading, 1)
    changed = True

# Highlight current SvxReflector talker in red.
old_svx_delegate = '''                                delegate: Rectangle {
                                    required property string modelData
                                    radius: 10
                                    color: "#e8f5e9"
                                    border.color: "#86c98a"
                                    implicitWidth: userLabel.implicitWidth + 18
                                    implicitHeight: userLabel.implicitHeight + 10
                                    Label {
                                        id: userLabel
                                        anchors.centerIn: parent
                                        text: "● " + modelData
                                        color: "#216e2d"
                                        font.bold: true
                                    }
                                }
'''
new_svx_delegate = '''                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property bool isTalking:
                                        String(page.reflectorClient.currentTalker || "").trim().toUpperCase() === modelData
                                    radius: 10
                                    color: isTalking ? "#fee2e2" : "#e8f5e9"
                                    border.color: isTalking ? "#ef4444" : "#86c98a"
                                    border.width: 1
                                    implicitWidth: userLabel.implicitWidth + 18
                                    implicitHeight: userLabel.implicitHeight + 10
                                    Label {
                                        id: userLabel
                                        anchors.centerIn: parent
                                        text: "● " + modelData
                                        color: parent.isTalking ? "#b91c1c" : "#216e2d"
                                        font.bold: true
                                    }
                                }
'''
if old_svx_delegate in s:
    s = s.replace(old_svx_delegate, new_svx_delegate, 1)
    changed = True

# Simple one-line FRN chips, if an older detailed UI is still present.
detailed_start = s.find('                        Label {\n                            visible: page.showFrnUsers && page.frnUsers.length > 0\n                            Layout.fillWidth: true\n                            text: qsTr("Strežnik:')
status_marker = '                        Label {\n                            visible: page.showFrnUsers && page.frnStatusMessage.length > 0'
status_pos = s.find(status_marker)
if detailed_start >= 0 and status_pos > detailed_start:
    simple_ui = '''                        Flow {
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
                                    border.width: 1
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
    s = s[:detailed_start] + simple_ui + s[status_pos:]
    changed = True

if not changed:
    print('Gateway activity UI already up to date.')
    raise SystemExit(0)

HOME.write_text(s)
print('Gateway activity updated: compact fonts, own callsign, red current talker.')
