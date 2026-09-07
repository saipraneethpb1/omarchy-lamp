import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
    id: root
    moduleName: "saipraneethpb1.lamp"

    // Inline settings from this widget's shell.json entry. Bar.qml assigns
    // this on load and re-assigns it when the user edits the settings, so a
    // changed journal directory takes effect without a restart.
    property var settings: ({})
    readonly property string journalDir: {
        const value = settings ? settings.journalDir : ""
        return (value === undefined || value === null) ? "" : String(value).trim()
    }

    // The one Service.qml instance the shell mounts for this plugin, shared
    // with the overlay so both surfaces show the same flame. serviceFor() is a
    // plain function, so the binding also reads shell._services — that property
    // is reassigned wholesale when a service loads (shell.qml), which is what
    // makes this re-evaluate once the service is ready. If that internal name
    // ever goes away, lamp stays null and the widget renders its unlit state.
    readonly property var lamp: (bar && bar.shell && bar.shell._services)
        ? bar.shell.serviceFor("saipraneethpb1.lamp") : null
    readonly property bool lit: lamp ? lamp.lit === true : false
    readonly property string intention: lamp ? (lamp.intention || "") : ""
    readonly property string elapsed: lamp ? (lamp.elapsed || "") : ""
    readonly property int targetSeconds: lamp ? (lamp.targetSeconds || 0) : 0
    readonly property bool overtime: lamp ? lamp.overtime === true : false

    // Warm lamplight for the lit state, matching the overlay's accent. Held as
    // a literal rather than a theme role because it stands for the flame, not
    // for the bar's foreground.
    readonly property color lampColor: "#e8c36a"

    // Past the time you gave yourself. Deliberately not the theme's urgent
    // role: this is the same flame, burning longer than planned.
    readonly property color overtimeColor: "#e0563f"

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function open() {
        if (panelLoader.item)
            panelLoader.item.open()
    }

    function close() {
        if (panelLoader.item)
            panelLoader.item.close()
    }

    function toggle() {
        if (panelLoader.item)
            panelLoader.item.toggle()
    }

    function togglePanel() {
        root.toggle()
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item && panelLoader.item.closeForPopoutSwitch)
            panelLoader.item.closeForPopoutSwitch()
        else
            root.close()
    }

    function injectPanel() {
        var target = panelLoader.item
        if (!target)
            return
        if ("bar" in target) target.bar = root.bar
        if ("anchorItem" in target) target.anchorItem = button
        if ("hostWidget" in target) target.hostWidget = root
        if ("lamp" in target) target.lamp = root.lamp
    }

    // The service is shared with the overlay, so pushing the setting onto it
    // is what makes both surfaces write to the same place.
    function pushSettings() {
        if (root.lamp && "journalDir" in root.lamp)
            root.lamp.journalDir = root.journalDir
    }

    onJournalDirChanged: pushSettings()

    onBarChanged: injectPanel()
    // The service can resolve after the panel loads; without this the panel
    // holds a null lamp forever and submit() silently does nothing.
    onLampChanged: {
        injectPanel()
        pushSettings()
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }

    IpcHandler {
        target: "saipraneethpb1.lamp"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.togglePanel() }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        active: root.opened
        foreground: root.lit
            ? (root.overtime ? root.overtimeColor : root.lampColor)
            : (root.bar ? root.bar.barForeground : Color.foreground)
        // One space after the glyph, two between intention and clock: the gap
        // separating a mark from its label should read tighter than the gap
        // separating two fields.
        text: root.lit ? "◉ " + Model.shorten(root.intention, 28) + "  " + root.elapsed : "○ Lamp"
        tooltipText: root.lit
            ? (root.overtime
                ? "Over the " + Model.formatTarget(root.targetSeconds) + " you planned \u00b7 click to put it out"
                : "Click to put the lamp out")
            : "Click to light a session"
        horizontalMargin: 8.75
        verticalPadding: 8.75
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton)
                root.togglePanel()
        }
    }
}
