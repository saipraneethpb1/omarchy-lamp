.pragma library

function formatElapsed(startedAt) {
    if (!startedAt)
        return "0m"
    var start = Date.parse(startedAt)
    if (isNaN(start))
        return "0m"
    var seconds = Math.max(0, Math.floor((Date.now() - start) / 1000))
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    if (hours > 0)
        return hours + "h " + minutes + "m"
    if (minutes > 0)
        return minutes + "m"
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

var MAX_TARGET_MINUTES = 24 * 60

function clampMinutes(value) {
    var n = parseInt(value, 10)
    if (isNaN(n))
        return 0
    return Math.max(0, Math.min(MAX_TARGET_MINUTES, n))
}

// Accepts "45", "45m", "2h", "1h30", "1h30m". Anything else means no target,
// so a typo quietly lights an untimed session rather than inventing a deadline.
function parseDuration(text) {
    var value = (text || "").trim().toLowerCase().replace(/\s+/g, "")
    if (!value)
        return 0
    var hm = value.match(/^(\d+)h(\d+)m?$/)
    if (hm)
        return clampMinutes(parseInt(hm[1], 10) * 60 + parseInt(hm[2], 10))
    var h = value.match(/^(\d+)h$/)
    if (h)
        return clampMinutes(parseInt(h[1], 10) * 60)
    var m = value.match(/^(\d+)m?$/)
    if (m)
        return clampMinutes(parseInt(m[1], 10))
    return 0
}

function formatTarget(minutes) {
    var total = clampMinutes(minutes)
    if (!total)
        return ""
    var hours = Math.floor(total / 60)
    var mins = total % 60
    if (hours && mins)
        return hours + "h " + mins + "m"
    if (hours)
        return hours + "h"
    return mins + "m"
}

function isOvertime(startedAt, targetMinutes) {
    var target = clampMinutes(targetMinutes)
    if (!target || !startedAt)
        return false
    var start = Date.parse(startedAt)
    if (isNaN(start))
        return false
    return (Date.now() - start) / 60000 >= target
}
