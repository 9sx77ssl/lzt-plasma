import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property string rawBalance: "0.00"
    property string rawHold: "0.00"
    property string displayText: "0.00"
    property string displaySymbol: "₽"
    property string displayHold: "0.00"
    property bool holdPositive: false

    property string statusText: ""
    property bool hasError: false
    property bool hasFetchedOnce: false
    property bool pendingBalance: false
    property bool pendingCurrency: false
    property bool pendingTransfer: false
    property string transferStatus: ""
    property bool transferSuccess: false

    property var currencyRates: ({})

    property string transferAmount: ""
    property string transferTargetCurrency: "RUB"
    property bool transferUseId: true
    property string transferUserId: ""
    property string transferUsername: ""
    property string transferComment: ""

    readonly property string apiKey: Plasmoid.configuration.apiKey || ""
    readonly property int balanceRefreshMs: (Plasmoid.configuration.updateInterval || 30) * 1000
    readonly property int currencyRefreshMs: (Plasmoid.configuration.currencyRefreshInterval || 300) * 1000
    readonly property string displayCurrency: Plasmoid.configuration.displayCurrency || "RUB"
    readonly property string primaryServer: Plasmoid.configuration.apiServer || "https://prod-api.lzt.market"
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
            onTriggered: {
                if (transferDialog.visible) {
                    transferDialog.visible = false
                } else {
                    transferDialog.visualParent = root.compactRepresentationItem ?? root
                    transferDialog.visible = true
                }
            }
        },
        PlasmaCore.Action {
            text: i18n("Refresh Balance")
            icon.name: "view-refresh"
            onTriggered: root.manualRefresh()
        }
    ]

    toolTipMainText: "LZT Market Balance"
    toolTipSubText: {
        if (hasError) return statusText
        var tip = displayText + " " + displaySymbol
        if (holdPositive) tip += "   ·   Hold: " + displayHold + " ₽"
        return tip
    }

    preferredRepresentation: compactRepresentation

    compactRepresentation: Item {
        implicitWidth: panelRow.implicitWidth + 10
        implicitHeight: panelRow.implicitHeight

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
                    if (root.hasError) return root.statusText
                    if (!root.hasFetchedOnce) return "..."
                    return root.displayText + root.displaySymbol
                }
                color: root.hasError ? "#884444" : "#2BAD72"
                font.bold: true
                font.pixelSize: 14
                Layout.alignment: Qt.AlignVCenter
            }

            RowLayout {
                visible: root.holdPositive && root.hasFetchedOnce && !root.hasError
                spacing: 3
                Layout.alignment: Qt.AlignVCenter

                Text {
                    text: "·"
                    color: "#363636"
                    font.pixelSize: 13
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: root.displayHold + "₽"
                    color: "#505050"
                    font.pixelSize: 12
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    fullRepresentation: Item {}

    PlasmaCore.Dialog {
        id: transferDialog
        type: PlasmaCore.Dialog.Normal
        hideOnWindowDeactivate: true
        flags: Qt.Dialog | Qt.WindowCloseButtonHint

        mainItem: Item {
            width: 340
            height: dialogCol.implicitHeight + 44

            Rectangle {
                anchors.fill: parent
                color: "#080808"

                ColumnLayout {
                    id: dialogCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 18
                    }
                    spacing: 10

                    // ── Header ──────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 48
                        radius: 8
                        color: "#0f0f0f"
                        border.color: "#1e3a2a"
                        border.width: 1

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: "#2BAD72"
                            radius: 2
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            anchors.topMargin: 0
                            anchors.bottomMargin: 0
                            spacing: 10

                            Image {
                                source: Qt.resolvedUrl("images/lolzteam.svg")
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                Layout.alignment: Qt.AlignVCenter
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                text: "Transfer"
                                color: "#2BAD72"
                                font.bold: true
                                font.pixelSize: 15
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                spacing: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    text: root.displayText + root.displaySymbol
                                    color: "#e0e0e0"
                                    font.pixelSize: 13
                                    font.bold: true
                                    horizontalAlignment: Text.AlignRight
                                    Layout.alignment: Qt.AlignRight
                                }

                                Text {
                                    visible: root.holdPositive
                                    text: "hold " + root.displayHold + "₽"
                                    color: "#505050"
                                    font.pixelSize: 10
                                    horizontalAlignment: Text.AlignRight
                                    Layout.alignment: Qt.AlignRight
                                }
                            }
                        }
                    }

                    // ── Amount ─────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        color: "#0f0f0f"
                        radius: 7
                        border.color: amountField.activeFocus ? "#2BAD72" : "#1e1e1e"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 8

                            QQC2.TextField {
                                id: amountField
                                Layout.fillWidth: true
                                placeholderText: "Amount"
                                validator: DoubleValidator {
                                    bottom: 0.01
                                    decimals: 4
                                    notation: DoubleValidator.StandardNotation
                                }
                                onTextChanged: root.transferAmount = text
                                color: "#ffffff"
                                font.bold: true
                                font.pixelSize: 14
                                background: Item {}
                                placeholderTextColor: "#2d2d2d"
                            }

                            Text {
                                text: root.currencySymbols[root.transferTargetCurrency] || root.transferTargetCurrency
                                color: "#2BAD72"
                                font.bold: true
                                font.pixelSize: 15
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    // ── Currency picker ────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Repeater {
                            model: ["RUB", "USD", "EUR", "UAH"]

                            delegate: Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                height: 30
                                radius: 5
                                color: root.transferTargetCurrency === modelData ? "#2BAD72" : "#0f0f0f"
                                border.color: root.transferTargetCurrency === modelData ? "#2BAD72" : "#1e1e1e"
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: (root.currencySymbols[modelData] || "") + " " + modelData
                                    color: root.transferTargetCurrency === modelData ? "#080808" : "#505050"
                                    font.bold: true
                                    font.pixelSize: 11
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.transferTargetCurrency = modelData
                                }
                            }
                        }
                    }

                    // ── By ID / By Username ────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        Rectangle {
                            Layout.fillWidth: true
                            height: 34
                            radius: 6
                            color: root.transferUseId ? "#2BAD72" : "#0f0f0f"
                            border.color: root.transferUseId ? "#2BAD72" : "#1e1e1e"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "By ID"
                                color: root.transferUseId ? "#080808" : "#505050"
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
                            radius: 6
                            color: !root.transferUseId ? "#2BAD72" : "#0f0f0f"
                            border.color: !root.transferUseId ? "#2BAD72" : "#1e1e1e"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "By Username"
                                color: !root.transferUseId ? "#080808" : "#505050"
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

                    // ── Recipient ──────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        color: "#0f0f0f"
                        radius: 7
                        border.color: userField.activeFocus ? "#2BAD72" : "#1e1e1e"
                        border.width: 1

                        QQC2.TextField {
                            id: userField
                            anchors.fill: parent
                            anchors.margins: 12
                            placeholderText: root.transferUseId ? "User ID" : "Username"
                            onTextChanged: {
                                if (root.transferUseId) root.transferUserId = text
                                else root.transferUsername = text
                            }
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 13
                            background: Item {}
                            placeholderTextColor: "#2d2d2d"
                        }
                    }

                    // ── Comment ────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        color: "#0f0f0f"
                        radius: 7
                        border.color: commentField.activeFocus ? "#2BAD72" : "#1e1e1e"
                        border.width: 1

                        QQC2.TextField {
                            id: commentField
                            anchors.fill: parent
                            anchors.margins: 12
                            placeholderText: "Comment (optional)"
                            maximumLength: 255
                            onTextChanged: root.transferComment = text
                            color: "#ffffff"
                            font.pixelSize: 13
                            background: Item {}
                            placeholderTextColor: "#2d2d2d"
                        }
                    }

                    // ── Status ─────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: visible ? 34 : 0
                        visible: root.transferStatus.length > 0
                        radius: 6
                        color: root.transferSuccess ? "#0d2b1a" : "#1f0d0d"
                        border.color: root.transferSuccess ? "#2BAD72" : "#884444"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 10
                            text: root.transferStatus
                            color: root.transferSuccess ? "#2BAD72" : "#884444"
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }

                    // ── Buttons ────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 7
                            color: {
                                if (root.pendingTransfer) return "#0d2b1a"
                                if (amountField.text.length === 0 || userField.text.length === 0) return "#131313"
                                return "#2BAD72"
                            }
                            border.color: {
                                if (root.pendingTransfer) return "#2BAD72"
                                if (amountField.text.length === 0 || userField.text.length === 0) return "#1e1e1e"
                                return "#2BAD72"
                            }
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: root.pendingTransfer ? "Sending..." : "Send"
                                color: {
                                    if (root.pendingTransfer) return "#2BAD72"
                                    if (amountField.text.length === 0 || userField.text.length === 0) return "#363636"
                                    return "#080808"
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

                        Rectangle {
                            Layout.preferredWidth: 80
                            height: 42
                            radius: 7
                            color: "#0f0f0f"
                            border.color: "#1e1e1e"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Close"
                                color: "#505050"
                                font.bold: true
                                font.pixelSize: 13
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: transferDialog.visible = false
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 2 }
                }
            }
        }
    }

    Timer {
        id: balanceTimer
        interval: root.balanceRefreshMs
        running: root.apiKey.length > 0
        repeat: true
        onTriggered: root.silentFetchBalance()
    }

    Timer {
        id: currencyTimer
        interval: root.currencyRefreshMs
        running: root.apiKey.length > 0 && root.displayCurrency !== "RUB"
        repeat: true
        onTriggered: root.fetchCurrencyRates()
    }

    Component.onCompleted: {
        if (apiKey.length > 0) {
            if (displayCurrency !== "RUB") fetchCurrencyRates()
            silentFetchBalance()
        } else {
            statusText = "No API Key"
            hasError = true
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onApiKeyChanged() {
            if (root.apiKey.length > 0) {
                root.hasFetchedOnce = false
                if (root.displayCurrency !== "RUB") root.fetchCurrencyRates()
                root.silentFetchBalance()
            } else {
                root.statusText = "No API Key"
                root.hasError = true
            }
        }

        function onUpdateIntervalChanged() { balanceTimer.restart() }

        function onDisplayCurrencyChanged() {
            root.displaySymbol = root.currencySymbols[root.displayCurrency] || root.displayCurrency
            if (root.displayCurrency !== "RUB") root.fetchCurrencyRates()
            root.recalcDisplay()
        }

        function onCurrencyRefreshIntervalChanged() { currencyTimer.restart() }

        function onApiServerChanged() { root.silentFetchBalance() }
    }

    function manualRefresh() {
        if (pendingBalance) return
        if (displayCurrency !== "RUB") fetchCurrencyRates()
        silentFetchBalance()
    }

    function silentFetchBalance() {
        if (apiKey.length === 0) { statusText = "No API Key"; hasError = true; return }
        if (pendingBalance) return
        doFetchBalance(primaryServer, true)
    }

    function doFetchBalance(server, canFallback) {
        pendingBalance = true
        var xhr = new XMLHttpRequest()
        xhr.timeout = 8000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                parseBalanceResponse(xhr.responseText)
                pendingBalance = false
            } else if (xhr.status === 401) {
                statusText = "Bad Token"; hasError = true; pendingBalance = false
            } else if (canFallback) {
                doFetchBalance(fallbackServer, false)
            } else {
                if (xhr.status === 429) statusText = "Rate Limit"
                else if (xhr.status === 0) statusText = "Offline"
                else statusText = "Err " + xhr.status
                if (!hasFetchedOnce) hasError = true
                pendingBalance = false
            }
        }

        xhr.ontimeout = function() {
            if (canFallback) {
                doFetchBalance(fallbackServer, false)
            } else {
                if (!hasFetchedOnce) { statusText = "Timeout"; hasError = true }
                pendingBalance = false
            }
        }

        xhr.open("GET", server + "/me")
        xhr.setRequestHeader("Accept", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.send()
    }

    function parseBalanceResponse(raw) {
        try {
            var data = JSON.parse(raw)
            if (!data || !data.user) throw new Error("bad response")
            var u = data.user
            rawBalance = (u.balance !== undefined && u.balance !== null) ? String(u.balance) : "0.00"
            rawHold = (u.hold !== undefined && u.hold !== null) ? String(u.hold) : "0.00"
            hasFetchedOnce = true
            hasError = false
            statusText = ""
            recalcDisplay()
        } catch (e) {
            if (!hasFetchedOnce) { statusText = "Parse Err"; hasError = true }
        }
    }

    function recalcDisplay() {
        var bal = parseFloat(rawBalance)
        if (isNaN(bal)) bal = 0

        if (displayCurrency === "RUB") {
            displayText = formatNumber(bal)
            displaySymbol = "₽"
        } else {
            var rate = currencyRates[displayCurrency]
            if (!rate || rate <= 0) {
                displayText = formatNumber(bal)
                displaySymbol = "₽"
            } else {
                displayText = formatNumber(bal / rate)
                displaySymbol = currencySymbols[displayCurrency] || displayCurrency
            }
        }

        var hold = parseFloat(rawHold)
        if (isNaN(hold) || hold < 0) hold = 0
        holdPositive = hold > 0.001
        displayHold = formatNumber(hold)
    }

    function formatNumber(value) {
        if (isNaN(value)) return "0.00"
        if (value >= 1000) return value.toFixed(0)
        if (value >= 100) return value.toFixed(1)
        if (value >= 1) return value.toFixed(2)
        return value.toFixed(4)
    }

    function fetchCurrencyRates() {
        if (apiKey.length === 0 || pendingCurrency) return
        doFetchCurrency(primaryServer, true)
    }

    function doFetchCurrency(server, canFallback) {
        pendingCurrency = true
        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                parseCurrencyResponse(xhr.responseText)
                pendingCurrency = false
            } else if (canFallback) {
                doFetchCurrency(fallbackServer, false)
            } else {
                pendingCurrency = false
            }
        }

        xhr.ontimeout = function() {
            if (canFallback) doFetchCurrency(fallbackServer, false)
            else pendingCurrency = false
        }

        xhr.open("GET", server + "/currency")
        xhr.setRequestHeader("Accept", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.send()
    }

    function parseCurrencyResponse(raw) {
        try {
            var data = JSON.parse(raw)
            if (!data || !data.currencyList) throw new Error("bad response")
            var list = data.currencyList
            var rates = {}
            for (var key in list) {
                if (list.hasOwnProperty(key) && list[key].rate > 0) rates[key] = list[key].rate
            }
            currencyRates = rates
            recalcDisplay()
        } catch (e) {}
    }

    function sendTransfer() {
        if (pendingTransfer) return
        if (apiKey.length === 0) {
            transferStatus = "No API Key"; transferSuccess = false; return
        }

        var amount = parseFloat(transferAmount)
        if (isNaN(amount) || amount <= 0) {
            transferStatus = "Invalid amount"; transferSuccess = false; return
        }

        var target = transferUseId ? transferUserId : transferUsername
        if (target.trim().length === 0) {
            transferStatus = "Enter recipient"; transferSuccess = false; return
        }

        if (transferUseId) {
            var uid = parseInt(target, 10)
            if (isNaN(uid) || uid <= 0) {
                transferStatus = "Invalid User ID"; transferSuccess = false; return
            }
        }

        pendingTransfer = true
        transferStatus = "Sending..."
        transferSuccess = false

        var body = {
            currency: transferTargetCurrency.toLowerCase(),
            amount: amount,
            telegram_deal: false,
            transfer_hold: false,
            comment: transferComment.length > 0 ? transferComment : ""
        }

        if (transferUseId) {
            body.user_id = parseInt(target, 10)
        } else {
            body.username = target.trim()
        }

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
                        amountField.text = ""
                        userField.text = ""
                        commentField.text = ""
                        transferAmount = ""
                        transferUserId = ""
                        transferUsername = ""
                        transferComment = ""
                    } else if (resp.errors && resp.errors.length > 0) {
                        transferStatus = resp.errors[0] || "Failed"
                        transferSuccess = false
                    } else {
                        transferStatus = resp.message || "Failed"
                        transferSuccess = false
                    }
                } catch (e) {
                    transferStatus = "Parse error"; transferSuccess = false
                }
            } else if (xhr.status === 401) {
                transferStatus = "Bad Token"; transferSuccess = false
            } else if (xhr.status === 429) {
                transferStatus = "Rate Limited"; transferSuccess = false
            } else if (xhr.status === 0) {
                transferStatus = "Offline"; transferSuccess = false
            } else {
                try {
                    var err = JSON.parse(xhr.responseText)
                    if (err.errors && err.errors.length > 0) {
                        transferStatus = err.errors[0] || ("Err " + xhr.status)
                    } else {
                        transferStatus = err.message || ("Err " + xhr.status)
                    }
                } catch (e) {
                    transferStatus = "Err " + xhr.status
                }
                transferSuccess = false
            }
            pendingTransfer = false
            silentFetchBalance()
        }

        xhr.ontimeout = function() {
            transferStatus = "Timeout"; transferSuccess = false; pendingTransfer = false
        }

        xhr.open("POST", primaryServer + "/balance/transfer")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Accept", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.send(JSON.stringify(body))
    }
}
