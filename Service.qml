import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
    id: root

    // Injected by the shell when it mounts this as the plugin's service.
    property var shell: null
    property var manifest: null
    property string omarchyPath: Quickshell.env("OMARCHY_PATH")

    property bool lit: false
    property string intention: ""
    property string startedAt: ""
    property string lastError: ""
    property string journalPath: ""
    property string elapsed: Model.formatElapsed(startedAt)

    readonly property url helper: Qt.resolvedUrl("scripts/lamp.py")

    function helperPath() {
        return helper.toString().replace("file://", "")
    }

    Timer {
        interval: 1000
        running: root.lit
        repeat: true
        onTriggered: root.elapsed = Model.formatElapsed(root.startedAt)
    }

    Process {
        id: reader
        running: true
        command: ["python3", root.helperPath(), "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(this.text)
        }
    }

    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: root.applyPayload(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.length)
                    root.lastError = this.text.trim()
            }
        }
    }

    function applyPayload(text) {
        const data = Model.parseSession(text)
        if (data.error)
            root.lastError = data.error
        root.lit = data.lit === true
        root.intention = data.intention || ""
        root.startedAt = data.startedAt || ""
        root.journalPath = data.journal || root.journalPath
        root.elapsed = Model.formatElapsed(root.startedAt)
    }

    function refresh() {
        if (reader.running)
            return
        reader.command = ["python3", root.helperPath(), "status"]
        reader.running = true
    }

    function light(text) {
        const intention = (text || "").trim()
        if (!intention || writer.running)
            return
        root.lastError = ""
        writer.command = ["python3", root.helperPath(), "light", intention]
        writer.running = true
    }

    function extinguish(closeText) {
        if (writer.running)
            return
        root.lastError = ""
        writer.command = ["python3", root.helperPath(), "extinguish", closeText || ""]
        writer.running = true
    }

    function toggleOverlay() {
        if (typeof Quickshell !== "undefined")
            Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "lamp.session", "{}"])
    }
}
