import QtQuick
import QtCore
import org.kde.notification

// Checks GitHub for a newer release by fetching the raw metadata.json from main
// and comparing its KPlugin.Version with ours. Throttled to once per day; a
// manual "Check for updates" action forces a check and always reports a result.
Item {
    id: checker

    property string url: "https://raw.githubusercontent.com/9sx77ssl/lzt-plasma/main/package/metadata.json"
    property string currentVersion: ""
    property bool   checking: false
    property var    activeXhr: null

    Settings { id: store; category: "LztUpdateChecker"; property string lastCheck: "" }

    Notification {
        id: notif
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "lztbalance"
        title: "LZT Plasmoid"
        flags: Notification.CloseOnTimeout
    }

    // Re-arms every 6h once the checker is configured; the per-day guard
    // inside check() does the real throttling. triggeredOnStart is false so
    // we don't fire before currentVersion has been read from metadata.
    Timer {
        interval: 6 * 60 * 60 * 1000
        running: checker.currentVersion.length > 0 && checker.url.length > 0
        repeat: true
        onTriggered: checker.check(false)
    }

    function today() {
        var d = new Date()
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function check(force) {
        if (checking) return
        if (!force && store.lastCheck === today()) return
        if (url.length === 0 || currentVersion.length === 0) return

        if (activeXhr) {
            try { activeXhr.abort() } catch (e) {}
        }
        checking = true

        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        activeXhr = xhr
        xhr.onreadystatechange = function() {
            if (xhr !== activeXhr) return
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            checking = false
            activeXhr = null
            if (xhr.status !== 200) { if (force) notify(i18n("Update check failed")); return }
            store.lastCheck = today()
            try {
                var remote = JSON.parse(xhr.responseText).KPlugin.Version || ""
                if (isNewer(remote, currentVersion))
                    notify(i18n("New version v%1 available — re-run install.sh", remote))
                else if (force)
                    notify(i18n("You're on the latest version (v%1)", currentVersion))
            } catch (e) {
                if (force) notify(i18n("Update check failed"))
            }
        }
        xhr.ontimeout = function() {
            if (xhr !== activeXhr) return
            checking = false
            activeXhr = null
            if (force) notify(i18n("Update check timed out"))
        }
        xhr.onerror = function() {
            if (xhr !== activeXhr) return
            checking = false
            activeXhr = null
            if (force) notify(i18n("Update check failed"))
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function notify(msg) { notif.text = msg; notif.sendEvent() }

    // semver-ish: true when a > b (compares the first three numeric parts)
    function isNewer(a, b) {
        var pa = String(a).split("."), pb = String(b).split(".")
        for (var i = 0; i < 3; i++) {
            var x = parseInt(pa[i] || "0", 10), y = parseInt(pb[i] || "0", 10)
            if (x > y) return true
            if (x < y) return false
        }
        return false
    }
}
