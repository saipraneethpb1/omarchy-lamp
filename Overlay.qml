import QtQuick
import Quickshell
import Quickshell.Wayland
import "Model.js" as Model

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
        ? shell.serviceFor("saipraneethpb1.lamp") : null
    readonly property bool lit: lamp ? lamp.lit === true : false
    readonly property string intention: lamp ? (lamp.intention || "") : ""
    readonly property string elapsed: lamp ? (lamp.elapsed || "") : ""
    readonly property int lampTargetSeconds: lamp ? (lamp.targetSeconds || 0) : 0
    readonly property bool overtime: lamp ? lamp.overtime === true : false

    readonly property int targetSeconds: Model.targetFrom(hoursField.text, minutesField.text, secondsField.text)

    function setTarget(hours, minutes, seconds) {
        hoursField.text = hours > 0 ? String(hours) : ""
        minutesField.text = minutes > 0 ? String(minutes) : ""
        secondsField.text = seconds > 0 ? String(seconds) : ""
    }

    function clearTarget() { root.setTarget(0, 0, 0) }

    // The card's fields in tab order. The duration row is hidden while a lamp
    // is lit, so the chain shrinks with it.
    readonly property var focusChain: root.lit
        ? [field, writeChip, codeChip, readChip, submitButton]
        : [field, writeChip, codeChip, readChip,
           chip25, chip50, chip90,
           hoursField.input, minutesField.input, secondsField.input,
           submitButton]

    // Unlike the bar panel there is no neighbouring surface to step out to, so
    // Tab wraps around the card instead of handing focus back to the shell.
    function moveFocus(direction) {
        const chain = root.focusChain
        let index = -1
        for (let i = 0; i < chain.length; i++) {
            if (chain[i] && chain[i].activeFocus) {
                index = i
                break
            }
        }
        if (index < 0) {
            if (chain[0])
                chain[0].forceActiveFocus()
            return
        }
        const target = chain[(index + direction + chain.length) % chain.length]
        if (target)
            target.forceActiveFocus()
    }

    function handleTab(event) {
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
        root.moveFocus(back ? -1 : 1)
        event.accepted = true
    }

    function open(payloadJson) {
        field.clear()
        root.clearTarget()
        if (lamp)
            lamp.refresh()
        root.opened = true
        Qt.callLater(function() { field.forceActiveFocus() })
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
            root.shell.hide("saipraneethpb1.lamp")
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
            field.clear()
            root.clearTarget()
            root.dismiss()
            return
        }
        if (!text.length)
            return
        lamp.light(text, root.targetSeconds)
        field.clear()
        root.clearTarget()
        root.dismiss()
    }

    function lightPreset(name) {
        field.text = name
        submit()
    }

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
                    onClicked: field.forceActiveFocus()
                }

                Item {
                    id: keyCatcher
                    anchors.fill: parent
                    Keys.onEscapePressed: root.dismiss()

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
                            color: root.overtime ? "#e0563f" : Qt.rgba(1, 1, 1, 0.65)
                            font.pixelSize: 14
                            text: root.lit
                                  ? (root.intention
                                     + (root.elapsed.length ? ("  ·  " + root.elapsed) : "")
                                     + (root.lampTargetSeconds > 0 ? (" of " + Model.formatTarget(root.lampTargetSeconds)) : ""))
                                  : "Type a sentence, then press Enter \u00b7 Tab moves between fields."
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
                                visible: field.text.length === 0
                                text: root.lit ? "What moved? (optional)" : "Your intention…"
                                color: "white"
                                opacity: 0.35
                                font.pixelSize: 16
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            TextInput {
                                id: field
                                anchors.fill: parent
                                anchors.margins: 12
                                focus: true
                                color: "white"
                                font.pixelSize: 16
                                verticalAlignment: Text.AlignVCenter
                                clip: true
                                selectByMouse: true
                                selectionColor: "#e8c36a"
                                selectedTextColor: "#111111"

                                onTextChanged: root.draft = text
                                onAccepted: root.submit()
                                Keys.onEscapePressed: root.dismiss()
                                Keys.onDownPressed: root.moveFocus(1)
                                Keys.onUpPressed: root.moveFocus(-1)
                                Keys.onPressed: function(event) { root.handleTab(event) }
                            }
                        }

                        Row {
                            spacing: 8

                            // A plain Rectangle takes no focus of its own, so
                            // these opt in and answer Return/Space themselves.
                            // The white ring is the only cue for where you are.
                            component ActionChip: Rectangle {
                                id: action
                                property string label: ""
                                width: 72
                                height: 30
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.12)
                                border.width: action.activeFocus ? 2 : 0
                                border.color: "white"
                                z: 8
                                activeFocusOnTab: true

                                Text {
                                    anchors.centerIn: parent
                                    text: action.label
                                    color: "white"
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    z: 9
                                    onClicked: root.lightPreset(action.label)
                                }

                                Keys.onReturnPressed: root.lightPreset(action.label)
                                Keys.onEnterPressed: root.lightPreset(action.label)
                                Keys.onSpacePressed: root.lightPreset(action.label)
                                Keys.onEscapePressed: root.dismiss()
                                Keys.onDownPressed: root.moveFocus(1)
                                Keys.onUpPressed: root.moveFocus(-1)
                                Keys.onPressed: function(event) { root.handleTab(event) }
                            }

                            ActionChip { id: writeChip; label: "Write" }
                            ActionChip { id: codeChip; label: "Code" }
                            ActionChip { id: readChip; label: "Read" }
                        }

                        Row {
                            id: durationRow
                            spacing: 8
                            visible: !root.lit

                            component DurationChip: Rectangle {
                                id: chip
                                property int minutes: 0
                                readonly property bool picked: root.targetSeconds === chip.minutes * 60
                                width: 72
                                height: 30
                                radius: 6
                                color: chip.picked ? "#e8c36a" : Qt.rgba(1, 1, 1, 0.12)
                                // White, not the accent: the ring has to read
                                // against the amber fill of a picked chip too.
                                border.width: chip.activeFocus ? 2 : 0
                                border.color: "white"
                                z: 8
                                activeFocusOnTab: true

                                function activate() {
                                    if (chip.picked) root.clearTarget()
                                    else root.setTarget(0, chip.minutes, 0)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: Model.formatTarget(chip.minutes * 60)
                                    color: chip.picked ? "#111111" : "white"
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    z: 9
                                    onClicked: {
                                        chip.activate()
                                        field.forceActiveFocus()
                                    }
                                }

                                Keys.onReturnPressed: chip.activate()
                                Keys.onEnterPressed: chip.activate()
                                Keys.onSpacePressed: chip.activate()
                                Keys.onEscapePressed: root.dismiss()
                                Keys.onDownPressed: root.moveFocus(1)
                                Keys.onUpPressed: root.moveFocus(-1)
                                Keys.onPressed: function(event) { root.handleTab(event) }
                            }

                            DurationChip { id: chip25; minutes: 25 }
                            DurationChip { id: chip50; minutes: 50 }
                            DurationChip { id: chip90; minutes: 90 }
                        }

                        Row {
                            spacing: 8
                            visible: !root.lit

                            component UnitBox: Rectangle {
                                property alias text: entry.text
                                property alias input: entry
                                property string label: ""
                                width: 88
                                height: 30
                                radius: 6
                                color: Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: entry.activeFocus ? "white" : Qt.rgba(1, 1, 1, 0.18)

                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    visible: entry.text.length === 0
                                    text: parent.label
                                    color: "white"
                                    opacity: 0.35
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }

                                TextInput {
                                    id: entry
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    color: "white"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    selectionColor: "#e8c36a"
                                    selectedTextColor: "#111111"
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    validator: IntValidator { bottom: 0; top: 999 }

                                    onAccepted: root.submit()
                                    Keys.onEscapePressed: root.dismiss()
                                    Keys.onDownPressed: root.moveFocus(1)
                                    Keys.onUpPressed: root.moveFocus(-1)
                                    Keys.onPressed: function(event) { root.handleTab(event) }
                                }
                            }

                            UnitBox { id: hoursField; label: "hours" }
                            UnitBox { id: minutesField; label: "min" }
                            UnitBox { id: secondsField; label: "sec" }
                        }

                        Rectangle {
                            id: submitButton
                            width: parent.width
                            height: 40
                            radius: 8
                            color: root.lit ? "#b85a3a" : "#e8c36a"
                            border.width: submitButton.activeFocus ? 2 : 0
                            border.color: "white"
                            z: 8
                            activeFocusOnTab: true

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

                            Keys.onReturnPressed: root.submit()
                            Keys.onEnterPressed: root.submit()
                            Keys.onSpacePressed: root.submit()
                            Keys.onEscapePressed: root.dismiss()
                            Keys.onUpPressed: root.moveFocus(-1)
                            Keys.onPressed: function(event) { root.handleTab(event) }
                        }
                    }
                }
            }
        }
    }
}
