.pragma library

function formatElapsed(startedAt) {
    if (!startedAt)
        return "0s"
    var start = Date.parse(startedAt)
    if (isNaN(start))
        return "0s"
    return formatClock(Math.max(0, Math.floor((Date.now() - start) / 1000)))
}

function pad2(value) {
    return value < 10 ? "0" + value : String(value)
}

// Always carries seconds, so the label changes every tick rather than resting
// on a whole minute for 60 seconds.
function formatClock(totalSeconds) {
    var total = Math.max(0, Math.floor(totalSeconds))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var seconds = total % 60
    if (hours > 0)
        return hours + "h " + pad2(minutes) + "m " + pad2(seconds) + "s"
    if (minutes > 0)
        return minutes + "m " + pad2(seconds) + "s"
    return seconds + "s"
}

function shorten(text, limit) {
    var value = (text || "").trim()
    if (value.length <= limit)
        return value
    return value.slice(0, Math.max(0, limit - 1)).trim() + "…"
}

function parseSession(text) {
    try {
        var data = JSON.parse(text)
        if (data && typeof data === "object")
            return data
    } catch (e) {
    }
    return { lit: false }
}

var MAX_TARGET_SECONDS = 24 * 60 * 60

function toInt(text) {
    var n = parseInt(String(text || "").trim(), 10)
    return isNaN(n) || n < 0 ? 0 : n
}

function clampSeconds(value) {
    var n = parseInt(value, 10)
    if (isNaN(n))
        return 0
    return Math.max(0, Math.min(MAX_TARGET_SECONDS, n))
}

function targetFrom(hours, minutes, seconds) {
    return clampSeconds(toInt(hours) * 3600 + toInt(minutes) * 60 + toInt(seconds))
}

function formatTarget(totalSeconds) {
    var total = clampSeconds(totalSeconds)
    if (!total)
        return ""
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var seconds = total % 60
    var parts = []
    if (hours)
        parts.push(hours + "h")
    if (minutes)
        parts.push(minutes + "m")
    if (seconds)
        parts.push(seconds + "s")
    return parts.join(" ")
}

function isOvertime(startedAt, targetSeconds) {
    var target = clampSeconds(targetSeconds)
    if (!target || !startedAt)
        return false
    var start = Date.parse(startedAt)
    if (isNaN(start))
        return false
    return (Date.now() - start) / 1000 >= target
}
