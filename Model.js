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
