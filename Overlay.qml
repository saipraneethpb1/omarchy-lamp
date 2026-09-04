import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root

    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var shell: null
    property var manifest: null

    property bool opened: false
    property string draft: ""

    // Same Service.qml instance the bar widget reads, so lighting or
    // extinguishing here moves the bar too. Reading shell._services keeps the
    // binding live until the service actually loads — see BarWidget.qml.
    readonly property var lamp: (shell && shell._services)
        ? shell.serviceFor("lamp.session") : null
    readonly property bool lit: lamp ? lamp.lit === true : false
    readonly property string intention: lamp ? (lamp.intention || "") : ""
    readonly property string elapsed: lamp ? (lamp.elapsed || "") : ""

    function open(payloadJson) {
        root.draft = ""
        if (lamp)
            lamp.refresh()
        root.opened = true
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        focusRetry.remaining = 30
        focusRetry.start()
    }

    function close() {
        focusRetry.stop()
        root.opened = false
    }

    function dismiss() {
        root.close()
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide("lamp.session")
    }

    function toggle(payloadJson) {
        if (root.opened)
            root.dismiss()
        else
            root.open(payloadJson || "{}")
    }

    function submit() {
        if (!lamp)
            return
        const text = root.draft.trim()
        if (root.lit) {
            lamp.extinguish(text)
            root.draft = ""
            root.dismiss()
            return
        }
        if (!text.length)
            return
        lamp.light(text)
        root.draft = ""
        root.dismiss()
    }

    function lightPreset(name) {
        root.draft = name
        submit()
    }

    Timer {
        id: focusRetry
        interval: 50
        repeat: true
        property int remaining: 0
        onTriggered: {
            if (keyCatcher.activeFocus || remaining <= 0) {
                stop()
                return
            }
            keyCatcher.forceActiveFocus()
            remaining -= 1
        }
    }

    PanelWindow {
        id: panel
        visible: root.opened
        focusable: true
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "lamp-session"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.62)

            MouseArea {
                anchors.fill: parent
                onClicked: root.dismiss()
            }

            Rectangle {
                id: card
                width: Math.min(parent.width - 48, 560)
                height: cardBody.implicitHeight + 48
                anchors.centerIn: parent
                radius: 16
                color: "#161616"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                MouseArea {
                    anchors.fill: parent
                    onClicked: keyCatcher.forceActiveFocus()
                }

                Item {
                    id: keyCatcher
                    anchors.fill: parent
                    focus: true
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Escape) {
                            root.dismiss()
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
                        id: cardBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 24
                        spacing: 12

                        Text {
                            width: parent.width
                            text: root.lit ? "Put the lamp out" : "Light a lamp"
                            color: "white"
                            font.pixelSize: 20
                            font.bold: true
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Qt.rgba(1, 1, 1, 0.65)
                            font.pixelSize: 14
                            text: root.lit
                                  ? (root.intention + (root.elapsed.length ? ("  ·  " + root.elapsed) : ""))
                                  : "Type a sentence, then press Enter or click Light."
                        }

                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: "#e8c36a"

                            Text {
                                anchors.fill: parent
                                anchors.margins: 12
                                text: root.draft.length ? root.draft : "Your intention…"
                                color: "white"
                                opacity: root.draft.length ? 1 : 0.35
                                font.pixelSize: 16
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Row {
                            spacing: 8
                            Repeater {
                                model: ["Write", "Code", "Read"]
                                Rectangle {
                                    width: 72
                                    height: 30
                                    radius: 6
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                    z: 8
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: "white"
                                        font.pixelSize: 13
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        z: 9
                                        onClicked: root.lightPreset(modelData)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 40
                            radius: 8
                            color: root.lit ? "#b85a3a" : "#e8c36a"
                            z: 8
                            Text {
                                anchors.centerIn: parent
                                text: root.lit ? "Extinguish" : "Light"
                                color: "#111111"
                                font.pixelSize: 15
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: 9
                                onClicked: root.submit()
                            }
                        }
                    }
                }
            }
        }
    }
}
