import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "lamp.session"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var lamp: null

    readonly property bool lit: lamp ? lamp.lit === true : false
    readonly property string intention: lamp ? (lamp.intention || "") : ""
    readonly property string elapsed: lamp ? (lamp.elapsed || "") : ""

    property string draft: ""

    function open() {
        if (lamp && typeof lamp.refresh === "function")
            lamp.refresh()
        field.clear()
        root.draft = ""
        root.controller.show()
        Qt.callLater(function() { field.forceActiveFocus() })
        focusRetry.remaining = 30
        focusRetry.start()
    }

    function close() {
        focusRetry.stop()
        root.controller.hide()
    }

    function toggle() {
        if (root.opened)
            root.close()
        else
            root.open()
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.hostWidget || root, direction)
        return false
    }

    function submit() {
        if (!lamp)
            return
        const text = root.draft.trim()
        if (root.lit) {
            lamp.extinguish(text)
            field.clear()
            root.close()
            return
        }
        if (!text.length)
            return
        lamp.light(text)
        field.clear()
        root.close()
    }

    // KeyboardPanel forces focus once, on open. That fires before the
    // layer-shell surface finishes its keyboard-focus prime (~75ms), so the
    // field can come up without a caret. Keep asking until it takes.
    Timer {
        id: focusRetry
        interval: 50
        repeat: true
        property int remaining: 0
        onTriggered: {
            if (field.activeFocus || remaining <= 0) {
                stop()
                return
            }
            field.forceActiveFocus()
            remaining -= 1
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: field
        contentWidth: panel.fittedContentWidth(Style.space(280))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            anchors.fill: parent
            // The field owns the keys whenever it has focus, so it can carry a
            // real cursor, selection, and paste. Escape and Tab move onto it
            // below, since a blocked catcher emits no signals of its own.
            blocked: field.activeFocus
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            Column {
                id: content
                width: parent.width
                spacing: Style.space(8)

                Text {
                    width: parent.width
                    text: root.lit ? "Put the lamp out" : "Light a lamp"
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: root.lit
                    text: root.intention + (root.elapsed.length ? ("  \u00b7  " + root.elapsed) : "")
                    color: root.barForeground
                    opacity: 0.7
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                }

                TextField {
                    id: field
                    width: parent.width
                    placeholderText: root.lit ? "What moved? (optional)" : "One sentence of intention"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body

                    onTextChanged: root.draft = text
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.close()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
                            event.accepted = true
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: root.lit ? "Enter to extinguish \u00b7 Esc to leave it lit" : "Type, then Enter \u00b7 Esc to close"
                    color: root.barForeground
                    opacity: 0.4
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
