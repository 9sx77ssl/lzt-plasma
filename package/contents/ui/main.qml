import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property string rawBalance: "0.00"
    property string rawHold:    "0.00"
    property string displayText:   "0.00"
    property string displaySymbol: "₽"
    property string displayHold:   "0.00"
    property bool   holdPositive:  false

    property string statusText:       ""
    property bool   hasError:         false
    property bool   hasFetchedOnce:   false
    property bool   pendingFetch:     false
    property bool   pendingTransfer:  false
    property string transferStatus:   ""
    property bool   transferSuccess:  false

    property var    currencyRates: ({})

    property string transferAmount:         ""
    property string transferTargetCurrency: "RUB"
    property bool   transferUseId:          true
    property string transferUserId:         ""
    property string transferUsername:       ""
    property string transferComment:        ""

    readonly property string apiKey:         Plasmoid.configuration.apiKey || ""
    readonly property int    refreshMs:      (Plasmoid.configuration.updateInterval || 30) * 1000
    readonly property string displayCurrency:Plasmoid.configuration.displayCurrency || "RUB"
    readonly property string primaryServer:  Plasmoid.configuration.apiServer || "https://prod-api.lzt.market"
    readonly property string fallbackServer: primaryServer === "https://prod-api.lzt.market"
        ? "https://api.lzt.market" : "https://prod-api.lzt.market"

    readonly property var currencySymbols: ({
        "RUB": "₽", "USD": "$", "EUR": "€", "UAH": "₴",
        "GBP": "£", "BYN": "Br", "KZT": "₸", "BTC": "₿"
    })

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Transfer Money")
            icon.name: "document-send"
            onTriggered: root.openTransfer()
        },
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.fetchAll()
        }
    ]

    toolTipMainText: "LZT Market Balance"
    toolTipSubText: {
        if (hasError) return statusText
        var t = displayText + " " + displaySymbol
        if (holdPositive) t += "  ·  hold " + displayHold + " ₽"
        return t
    }

    preferredRepresentation: compactRepresentation

    function openTransfer() {
        if (transferDialog.visible) {
            transferDialog.visible = false
        } else {
            transferDialog.visualParent = root.compactRepresentationItem ?? root
            transferDialog.visible = true
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Panel widget
    // ────────────────────────────────────────────────────────────────
    compactRepresentation: MouseArea {
        id: panelArea
        implicitWidth: panelRow.implicitWidth + 6

        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openTransfer()

        RowLayout {
            id: panelRow
            anchors.centerIn: parent
            spacing: 5

            Image {
                source: Qt.resolvedUrl("images/lolzteam.svg")
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                smooth: true
                mipmap: true
            }

            Text {
                text: {
                    if (root.hasError)        return root.statusText
                    if (!root.hasFetchedOnce) return "..."
                    return root.displayText + root.displaySymbol
                }
                color: root.hasError ? "#884444" : "#2BAD72"
                font.bold: true
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.holdPositive && root.hasFetchedOnce && !root.hasError
                text: "· " + root.displayHold + "₽"
                color: "#707070"
                font.pixelSize: 12
                font.bold: true
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    fullRepresentation: Item {}

    // ────────────────────────────────────────────────────────────────
    // Transfer dialog
    // ────────────────────────────────────────────────────────────────
    PlasmaCore.Dialog {
        id: transferDialog
        type: PlasmaCore.Dialog.Normal
        hideOnWindowDeactivate: true
        flags: Qt.Dialog

        onVisibleChanged: {
            if (!visible) Qt.callLater(root.resetTransferForm)
        }

        mainItem: Rectangle {
            width: 300
            implicitHeight: dlgCol.implicitHeight + 28
            color: "#080808"

            ColumnLayout {
                id: dlgCol
                anchors {
                    top:    parent.top
                    left:   parent.left
                    right:  parent.right
                    margins: 12
                }
                spacing: 8

                // ── Header ──────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    color: "#272727"
                    radius: 8
                    border.color: "#363636"
                    border.width: 1

                    Rectangle {
                        x: 0; y: 10
                        width: 3; height: 32
                        radius: 2
                        color: "#2BAD72"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14

                        Image {
                            source: Qt.resolvedUrl("images/lolzteam.svg")
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            Layout.alignment: Qt.AlignVCenter
                            smooth: true; mipmap: true
                        }

                        Text {
                            text: "Transfer"
                            color: "#2BAD72"
                            font.bold: true
                            font.pixelSize: 15
                            Layout.fillWidth: true
                            leftPadding: 10
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Column {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                text: root.displayText + root.displaySymbol
                                color: "#FFFFFF"
                                font.pixelSize: 13
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                anchors.right: parent.right
                            }
                            Text {
                                visible: root.holdPositive
                                text: "hold " + root.displayHold + "₽"
                                color: "#505050"
                                font.pixelSize: 10
                                horizontalAlignment: Text.AlignRight
                                anchors.right: parent.right
                            }
                        }
                    }
                }

                // ── Amount ──────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    color: "#272727"
                    radius: 8
                    border.width: 1
                    border.color: amountField.activeFocus ? "#2BAD72" : "#363636"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        QQC2.TextField {
                            id: amountField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: "0.00"
                            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                            validator: DoubleValidator {
                                bottom: 0.01
                                top: 10000000
                                decimals: 4
                                notation: DoubleValidator.StandardNotation
                            }
                            onTextChanged: root.transferAmount = text
                            color: "#FFFFFF"
                            font.bold: true
                            font.pixelSize: 15
                            background: Item {}
                            placeholderTextColor: "#505050"
                        }

                        Text {
                            text: root.currencySymbols[root.transferTargetCurrency] || root.transferTargetCurrency
                            color: "#2BAD72"
                            font.bold: true
                            font.pixelSize: 17
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                // ── Currency toggle: RUB / USD ───────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { code: "RUB", label: "₽  RUB" },
                            { code: "USD", label: "$  USD" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 34
                            radius: 7
                            color:        root.transferTargetCurrency === modelData.code ? "#2BAD72" : "#272727"
                            border.color: root.transferTargetCurrency === modelData.code ? "#2BAD72" : "#363636"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text:  modelData.label
                                color: root.transferTargetCurrency === modelData.code ? "#FFFFFF" : "#FFFFFF"
                                opacity: root.transferTargetCurrency === modelData.code ? 1.0 : 0.55
                                font.bold: true
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.transferTargetCurrency = modelData.code
                            }
                        }
                    }
                }

                // ── By ID / By Username ──────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 7
                        color:        root.transferUseId ? "#2BAD72" : "#272727"
                        border.color: root.transferUseId ? "#2BAD72" : "#363636"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text:  "By ID"
                            color: "#FFFFFF"
                            opacity: root.transferUseId ? 1.0 : 0.55
                            font.bold: true
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.transferUseId = true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: 7
                        color:        !root.transferUseId ? "#2BAD72" : "#272727"
                        border.color: !root.transferUseId ? "#2BAD72" : "#363636"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text:  "By Username"
                            color: "#FFFFFF"
                            opacity: !root.transferUseId ? 1.0 : 0.55
                            font.bold: true
                            font.pixelSize: 12
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.transferUseId = false
                        }
                    }
                }

                // ── Recipient ────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    color: "#272727"
                    radius: 8
                    border.width: 1
                    border.color: userField.activeFocus ? "#2BAD72" : "#363636"

                    QQC2.TextField {
                        id: userField
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.leftMargin:  14
                        anchors.rightMargin: 14
                        leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                        placeholderText: root.transferUseId ? "User ID" : "Username"
                        onTextChanged: {
                            if (root.transferUseId) root.transferUserId   = text
                            else                    root.transferUsername = text
                        }
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 13
                        background: Item {}
                        placeholderTextColor: "#505050"
                    }
                }

                // ── Comment ──────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 46
                    color: "#272727"
                    radius: 8
                    border.width: 1
                    border.color: commentField.activeFocus ? "#2BAD72" : "#363636"

                    QQC2.TextField {
                        id: commentField
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.leftMargin:  14
                        anchors.rightMargin: 14
                        leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                        placeholderText: "Comment (optional)"
                        maximumLength: 255
                        onTextChanged: root.transferComment = text
                        color: "#FFFFFF"
                        font.pixelSize: 13
                        background: Item {}
                        placeholderTextColor: "#505050"
                    }
                }

                // ── Status ───────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    visible: root.transferStatus.length > 0
                    radius: 7
                    color:        root.transferSuccess ? "#0d2618" : "#2a1010"
                    border.color: root.transferSuccess ? "#2BAD72" : "#884444"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.margins: 12
                        text:  root.transferStatus
                        color: root.transferSuccess ? "#2BAD72" : "#FFFFFF"
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                // ── Send ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 42
                    radius: 8
                    color: {
                        if (root.pendingTransfer) return "#1a3d2b"
                        if (amountField.text.length === 0 || userField.text.length === 0) return "#272727"
                        return "#2BAD72"
                    }
                    border.color: {
                        if (root.pendingTransfer) return "#2BAD72"
                        if (amountField.text.length === 0 || userField.text.length === 0) return "#363636"
                        return "#2BAD72"
                    }
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text:  root.pendingTransfer ? "Sending..." : "Send"
                        color: {
                            if (root.pendingTransfer) return "#2BAD72"
                            if (amountField.text.length === 0 || userField.text.length === 0) return "#505050"
                            return "#FFFFFF"
                        }
                        font.bold: true
                        font.pixelSize: 13
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.pendingTransfer ? Qt.WaitCursor : Qt.PointingHandCursor
                        enabled: !root.pendingTransfer
                            && amountField.text.length > 0
                            && userField.text.length > 0
                        onClicked: root.sendTransfer()
                    }
                }

                Item { Layout.preferredHeight: 2 }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Timer & init
    // ────────────────────────────────────────────────────────────────
    Timer {
        id: refreshTimer
        interval: root.refreshMs
        running:  root.apiKey.length > 0
        repeat:   true
        onTriggered: root.fetchAll()
    }

    Component.onCompleted: {
        if (apiKey.length > 0) fetchAll()
        else { statusText = "No API Key"; hasError = true }
    }

    Connections {
        target: Plasmoid.configuration
        function onApiKeyChanged() {
            if (root.apiKey.length > 0) { root.hasFetchedOnce = false; root.fetchAll() }
            else { root.statusText = "No API Key"; root.hasError = true }
        }
        function onUpdateIntervalChanged() { refreshTimer.restart() }
        function onDisplayCurrencyChanged(){ root.recalcDisplay() }
        function onApiServerChanged()      { root.fetchAll() }
    }

    // ────────────────────────────────────────────────────────────────
    // Logic
    // ────────────────────────────────────────────────────────────────
    function resetTransferForm() {
        amountField.text  = ""
        userField.text    = ""
        commentField.text = ""
        transferAmount    = ""
        transferUserId    = ""
        transferUsername  = ""
        transferComment   = ""
        transferStatus    = ""
        transferSuccess   = false
        transferUseId     = true
        transferTargetCurrency = "RUB"
    }

    function fetchAll() {
        if (apiKey.length === 0) { statusText = "No API Key"; hasError = true; return }
        if (pendingFetch) return
        doFetchBatch(primaryServer, true)
    }

    function doFetchBatch(server, canFallback) {
        pendingFetch = true
        var jobs = [
            { method: "GET", uri: server + "/currency", id: "1" },
            { method: "GET", uri: server + "/me",       id: "2" }
        ]
        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                parseBatchResponse(xhr.responseText)
                pendingFetch = false
            } else if (xhr.status === 401) {
                statusText = "Bad Token"; hasError = true; pendingFetch = false
            } else if (canFallback) {
                doFetchBatch(fallbackServer, false)
            } else {
                if      (xhr.status === 429) statusText = "Rate Limit"
                else if (xhr.status === 0)   statusText = "Offline"
                else                         statusText = "Err " + xhr.status
                if (!hasFetchedOnce) hasError = true
                pendingFetch = false
            }
        }
        xhr.ontimeout = function() {
            if (canFallback) doFetchBatch(fallbackServer, false)
            else {
                if (!hasFetchedOnce) { statusText = "Timeout"; hasError = true }
                pendingFetch = false
            }
        }
        xhr.open("POST", server + "/batch")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Accept",       "application/json")
        xhr.setRequestHeader("Authorization","Bearer " + apiKey)
        xhr.send(JSON.stringify(jobs))
    }

    function parseBatchResponse(raw) {
        try {
            var data = JSON.parse(raw)
            if (!data || !data.jobs) throw new Error("no jobs")

            var j1 = data.jobs["1"]
            var j2 = data.jobs["2"]

            if (j1 && j1._job_result === "ok" && j1.currencyList) {
                var list = j1.currencyList
                var rates = {}
                for (var key in list)
                    if (list.hasOwnProperty(key) && list[key].rate > 0) rates[key] = list[key].rate
                currencyRates = rates
            }

            if (j2 && j2._job_result === "ok" && j2.user) {
                var u = j2.user
                rawBalance = (u.balance !== undefined && u.balance !== null) ? String(u.balance) : "0.00"
                rawHold    = (u.hold    !== undefined && u.hold    !== null) ? String(u.hold)    : "0.00"
                hasFetchedOnce = true
                hasError = false
                statusText = ""
            } else if (!hasFetchedOnce) {
                statusText = "Parse Err"; hasError = true
            }

            recalcDisplay()
        } catch (e) {
            if (!hasFetchedOnce) { statusText = "Parse Err"; hasError = true }
        }
    }

    function recalcDisplay() {
        var bal = parseFloat(rawBalance)
        if (isNaN(bal)) bal = 0

        if (displayCurrency === "RUB") {
            displayText   = formatNumber(bal)
            displaySymbol = "₽"
        } else {
            var rate = currencyRates[displayCurrency]
            if (!rate || rate <= 0) {
                displayText   = formatNumber(bal)
                displaySymbol = "₽"
            } else {
                displayText   = formatNumber(bal / rate)
                displaySymbol = currencySymbols[displayCurrency] || displayCurrency
            }
        }

        var hold = parseFloat(rawHold)
        if (isNaN(hold) || hold < 0) hold = 0
        holdPositive = hold > 0.001
        displayHold  = formatNumber(hold)
    }

    function formatNumber(v) {
        if (isNaN(v))  return "0.00"
        if (v >= 1000) return v.toFixed(0)
        if (v >= 100)  return v.toFixed(1)
        if (v >= 1)    return v.toFixed(2)
        return v.toFixed(4)
    }

    // ── Transfer with fallback ───────────────────────────────────────
    function sendTransfer() {
        if (pendingTransfer) return
        if (apiKey.length === 0) { transferStatus = "No API Key"; transferSuccess = false; return }

        var amount = parseFloat(transferAmount)
        if (isNaN(amount) || amount <= 0) { transferStatus = "Invalid amount"; transferSuccess = false; return }
        if (amount > 10000000)            { transferStatus = "Max 10 000 000"; transferSuccess = false; return }

        var target = transferUseId ? transferUserId : transferUsername
        if (target.trim().length === 0) { transferStatus = "Enter recipient"; transferSuccess = false; return }

        if (transferUseId) {
            var uid = parseInt(target, 10)
            if (isNaN(uid) || uid <= 0) { transferStatus = "Invalid User ID"; transferSuccess = false; return }
        }

        pendingTransfer = true
        transferStatus  = "Sending..."
        transferSuccess = false

        var body = {
            currency:      transferTargetCurrency.toLowerCase(),
            amount:        amount,
            telegram_deal: false,
            transfer_hold: false,
            comment:       transferComment.length > 0 ? transferComment : ""
        }
        if (transferUseId) body.user_id  = parseInt(target, 10)
        else               body.username = target.trim()

        doSendTransfer(primaryServer, body, true)
    }

    function doSendTransfer(server, body, canFallback) {
        var xhr = new XMLHttpRequest()
        xhr.timeout = 15000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.status === "ok") {
                        transferStatus = resp.message || "Transfer successful!"
                        transferSuccess = true
                        amountField.text  = ""
                        userField.text    = ""
                        commentField.text = ""
                        transferAmount   = ""; transferUserId = ""; transferUsername = ""; transferComment = ""
                    } else if (resp.errors && resp.errors.length > 0) {
                        transferStatus = resp.errors[0] || "Failed"; transferSuccess = false
                    } else {
                        transferStatus = resp.message || "Failed";   transferSuccess = false
                    }
                } catch (e) { transferStatus = "Parse error"; transferSuccess = false }
                pendingTransfer = false
                fetchAll()
            } else if (xhr.status === 401) {
                transferStatus = "Bad Token"; transferSuccess = false; pendingTransfer = false
            } else if (xhr.status === 429) {
                transferStatus = "Rate Limited"; transferSuccess = false; pendingTransfer = false
            } else if ((xhr.status >= 500 && xhr.status < 600) || xhr.status === 0) {
                // 5xx server errors or network failure → fallback
                if (canFallback) {
                    transferStatus = "Retrying on backup..."
                    doSendTransfer(fallbackServer, body, false)
                } else {
                    if (xhr.status === 0) transferStatus = "Offline"
                    else transferStatus = "Server Err " + xhr.status
                    transferSuccess = false
                    pendingTransfer = false
                }
            } else {
                // 4xx other than 401/429 → app-level error, don't fallback
                try {
                    var err = JSON.parse(xhr.responseText)
                    transferStatus = (err.errors && err.errors.length > 0)
                        ? err.errors[0] : (err.message || ("Err " + xhr.status))
                } catch (e) { transferStatus = "Err " + xhr.status }
                transferSuccess = false
                pendingTransfer = false
            }
        }

        xhr.ontimeout = function() {
            if (canFallback) {
                transferStatus = "Retrying on backup..."
                doSendTransfer(fallbackServer, body, false)
            } else {
                transferStatus = "Timeout"
                transferSuccess = false
                pendingTransfer = false
            }
        }

        xhr.open("POST", server + "/balance/transfer")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Accept",       "application/json")
        xhr.setRequestHeader("Authorization","Bearer " + apiKey)
        xhr.send(JSON.stringify(body))
    }
}
