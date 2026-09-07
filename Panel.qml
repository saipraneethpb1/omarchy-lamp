import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "saipraneethpb1.lamp"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var lamp: null

    readonly property bool lit: lamp ? lamp.lit === true : false
    readonly property string intention: lamp ? (lamp.intention || "") : ""
    readonly property string elapsed: lamp ? (lamp.elapsed || "") : ""

    property string draft: ""

    readonly property int targetSeconds: Model.targetFrom(hoursField.text, minutesField.text, secondsField.text)
    readonly property int lampTargetSeconds: lamp ? (lamp.targetSeconds || 0) : 0
    readonly property bool overtime: lamp ? lamp.overtime === true : false

    function setTarget(hours, minutes, seconds) {
        hoursField.text = hours > 0 ? String(hours) : ""
        minutesField.text = minutes > 0 ? String(minutes) : ""
        secondsField.text = seconds > 0 ? String(seconds) : ""
    }

    function clearTarget() { root.setTarget(0, 0, 0) }

    function open() {
        if (lamp && typeof lamp.refresh === "function")
            lamp.refresh()
        field.clear()
        root.clearTarget()
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

    // The form's fields in tab order. Only the intention field is on screen
    // once the lamp is lit, so the chain shrinks to match what you can see.
    readonly property var focusChain: root.lit
        ? [field]
        : [field, preset25, preset50, preset90, hoursField, minutesField, secondsField]

    // Tab belongs to the bar: it walks between panels. Inside the form we
    // borrow it for field-to-field movement and hand it back at both edges,
    // so tabbing through Lamp still lands you in the next panel rather than
    // trapping focus here.
    function moveFocus(direction) {
        const chain = root.focusChain
        let index = -1
        for (let i = 0; i < chain.length; i++) {
            if (chain[i] && chain[i].activeFocus) {
                index = i
                break
            }
        }
        const next = index + direction
        if (index < 0 || next < 0 || next >= chain.length || !chain[next])
            return root.switchPanel(direction)
        chain[next].forceActiveFocus()
        return true
    }

    // PanelKeyCatcher sets focus: true on itself and swallows keys whenever it
    // is unblocked, so it has to stand down for every control in the form, not
    // just the sentence field — otherwise tabbing onto a preset hands the keys
    // straight back to the catcher.
    readonly property bool formHasFocus: {
        const chain = root.focusChain
        for (let i = 0; i < chain.length; i++) {
            if (chain[i] && chain[i].activeFocus)
                return true
        }
        return false
    }

    function handleTab(event) {
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return
        const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
        root.moveFocus(back ? -1 : 1)
        event.accepted = true
    }

    function submit() {
        if (!lamp)
            return
        const text = root.draft.trim()
        if (root.lit) {
            lamp.extinguish(text)
            field.clear()
            root.clearTarget()
            root.close()
            return
        }
        if (!text.length)
            return
        lamp.light(text, root.targetSeconds)
        field.clear()
        root.clearTarget()
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
            // The form owns the keys whenever any of its controls has focus,
            // so the field can carry a real cursor, selection, and paste, and
            // the presets can answer Return. Escape and Tab are handled on the
            // controls below, since a blocked catcher emits no signals.
            blocked: root.formHasFocus
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
                    text: root.intention
                          + (root.elapsed.length ? ("  \u00b7  " + root.elapsed) : "")
                          + (root.lampTargetSeconds > 0 ? (" of " + Model.formatTarget(root.lampTargetSeconds)) : "")
                    color: root.overtime ? "#e0563f" : root.barForeground
                    opacity: root.overtime ? 1 : 0.7
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                }

                TextField {
                    id: field
                    width: parent.width
                    focus: true
                    placeholderText: root.lit ? "What moved? (optional)" : "One sentence of intention"
                    foreground: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body

                    onTextChanged: root.draft = text
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.close()
                    Keys.onDownPressed: if (!root.lit) hoursField.forceActiveFocus()
                    Keys.onPressed: function(event) { root.handleTab(event) }
                }

                Row {
                    width: parent.width
                    visible: !root.lit
                    spacing: Style.space(6)

                    // Named rather than repeated, so the focus chain above can
                    // address each one. Button already paints a focus ring and
                    // fires clicked() on Return or Space once focusable is set.
                    component PresetButton: Button {
                        id: chip
                        property int minutes: 0
                        readonly property bool picked: root.targetSeconds === chip.minutes * 60
                        text: Model.formatTarget(chip.minutes * 60)
                        bordered: true
                        focusable: true
                        selected: chip.picked
                        foreground: root.barForeground
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        onClicked: {
                            if (chip.picked) root.clearTarget()
                            else root.setTarget(0, chip.minutes, 0)
                            // A mouse click leaves focus nowhere useful, so send
                            // it back to the sentence. A keyboard press should
                            // stay put, or Tab would throw you to the top again.
                            if (!chip.activeFocus)
                                field.forceActiveFocus()
                        }
                        Keys.onUpPressed: field.forceActiveFocus()
                        Keys.onDownPressed: hoursField.forceActiveFocus()
                        Keys.onEscapePressed: root.close()
                        Keys.onPressed: function(event) { root.handleTab(event) }
                    }

                    PresetButton { id: preset25; minutes: 25 }
                    PresetButton { id: preset50; minutes: 50 }
                    PresetButton { id: preset90; minutes: 90 }
                }

                Row {
                    id: customRow
                    width: parent.width
                    visible: !root.lit
                    spacing: Style.space(6)

                    readonly property real cellWidth: (width - spacing * 2) / 3

                    component UnitField: TextField {
                        width: customRow.cellWidth
                        foreground: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 0; top: 999 }

                        onAccepted: root.submit()
                        Keys.onEscapePressed: root.close()
                        // Arrows still walk the form; Tab does too, and steps
                        // out to the neighbouring panel at either end.
                        Keys.onPressed: function(event) { root.handleTab(event) }
                    }

                    UnitField {
                        id: hoursField
                        placeholderText: "hours"
                        Keys.onUpPressed: field.forceActiveFocus()
                        Keys.onDownPressed: minutesField.forceActiveFocus()
                    }

                    UnitField {
                        id: minutesField
                        placeholderText: "min"
                        Keys.onUpPressed: hoursField.forceActiveFocus()
                        Keys.onDownPressed: secondsField.forceActiveFocus()
                    }

                    UnitField {
                        id: secondsField
                        placeholderText: "sec"
                        Keys.onUpPressed: minutesField.forceActiveFocus()
                    }
                }

                Text {
                    width: parent.width
                    text: root.lit
                          ? "Enter to extinguish \u00b7 Esc to leave it lit"
                          : "Enter to light \u00b7 Tab walks presets and h / m / s \u00b7 Esc to close"
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
