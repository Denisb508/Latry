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
new_filter = '''    function normalizedReflectorUsers(nodes) {
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
if old_filter in s:
    s = s.replace(old_filter, new_filter, 1)
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

# FRN: normalize to display strings only. Backend may keep all other fields.
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

# FRN header count should follow server count when provided.
s2 = s.replace('text: qsTr("FRN uporabniki (%1)").arg(page.frnUsers.length)',
               'text: qsTr("FRN uporabniki (%1)").arg(page.frnServerCount)')
if s2 != s:
    s = s2
    changed = True

# Simple one-line FRN chips. Handle both detailed and already-simple delegates.
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
else:
    s2 = s.replace('required property var modelData\n                                    radius: 10',
                   'required property string modelData\n                                    radius: 10', 1)
    s2 = s2.replace('text: "● " + (modelData.display || modelData.callsign || qsTr("FRN uporabnik"))',
                    'text: "● " + modelData', 1)
    if s2 != s:
        s = s2
        changed = True

if not changed:
    print('Reflector/FRN activity display already up to date.')
    raise SystemExit(0)

HOME.write_text(s)
print('Activity display updated: all reflector callsigns + FRN count/display only.')
