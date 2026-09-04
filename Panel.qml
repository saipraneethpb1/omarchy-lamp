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
        root.draft = ""
        root.controller.show()
        Qt.callLater(function() { inputItem.forceActiveFocus() })
    }

    function close() {
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
            root.draft = ""
            root.close()
            return
        }
        if (!text.length)
            return
        lamp.light(text)
        root.draft = ""
        root.close()
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: inputItem
        contentWidth: panel.fittedContentWidth(Style.space(280))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            anchors.fill: parent
            blocked: true
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }

            Item {
                id: inputItem
                anchors.fill: parent
                focus: true

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.close()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submit()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Backspace) {
                        root.draft = root.draft.slice(0, Math.max(0, root.draft.length - 1))
                        event.accepted = true
                        return
                    }
                    if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                        root.draft += event.text
                        event.accepted = true
                    }
                }

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
                        text: root.intention + (root.elapsed.length ? ("  ·  " + root.elapsed) : "")
                        color: root.barForeground
                        opacity: 0.7
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        text: root.draft.length ? root.draft : (root.lit ? "What moved? (optional)" : "One sentence of intention")
                        color: root.barForeground
                        opacity: root.draft.length ? 1 : 0.45
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        text: root.lit ? "Enter to extinguish · Esc to leave it lit" : "Type, then Enter · Esc to close"
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
}
