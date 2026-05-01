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
    property string displayText: "0.00"
    property string displaySymbol: "₽"
    property string statusText: ""
    property bool hasError: false
    property bool hasFetchedOnce: false
    property bool pendingBalance: false
    property bool pendingCurrency: false
    property bool pendingTransfer: false
    property string transferStatus: ""
    property bool transferSuccess: false

    property var currencyRates: ({})

    // Transfer form properties
    property string transferAmount: ""
    property string transferCurrency: displayCurrency
    property bool transferUseId: true
    property string transferUserId: ""
    property string transferUsername: ""
    property string transferComment: ""

    readonly property string apiKey: Plasmoid.configuration.apiKey || ""
    readonly property int balanceRefreshMs: (Plasmoid.configuration.updateInterval || 30) * 1000
    readonly property int currencyRefreshMs: (Plasmoid.configuration.currencyRefreshInterval || 300) * 1000
    readonly property string displayCurrency: Plasmoid.configuration.displayCurrency || "RUB"
    readonly property string primaryServer: Plasmoid.configuration.apiServer || "https://prod-api.lzt.market"
    readonly property string fallbackServer: primaryServer === "https://prod-api.lzt.market" ? "https://api.lzt.market" : "https://prod-api.lzt.market"

    readonly property var currencySymbols: ({
        "RUB": "₽", "USD": "$", "EUR": "€", "UAH": "₴",
        "GBP": "£", "BYN": "Br", "KZT": "₸", "BTC": "₿"
    })

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Transfer Money")
            icon.name: "document-send"
            onTriggered: transferWindow.show()
        },
        PlasmaCore.Action {
            text: i18n("Refresh Balance")
            icon.name: "view-refresh"
            onTriggered: root.manualRefresh()
        }
    ]

    toolTipMainText: "LZT Market Balance"
    toolTipSubText: hasError ? statusText : (displayText + " " + displaySymbol)

    preferredRepresentation: compactRepresentation

    compactRepresentation: RowLayout {
        id: panelRow
        spacing: 5

        Image {
            source: Qt.resolvedUrl("images/lolzteam.png")
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter
            smooth: true
            mipmap: true
        }

        PlasmaComponents.Label {
            id: balanceLabel
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
    }

    fullRepresentation: Item {}

    Window {
        id: transferWindow
        title: "Transfer Money"
        width: 320
        height: 400
        visible: false
        flags: Qt.Dialog | Qt.WindowCloseButtonHint

        Rectangle {
            anchors.fill: parent
            color: "#1a1a1a"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: "#252525"
                    radius: 6

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 4

                        QQC2.TextField {
                            id: amountField
                            Layout.fillWidth: true
                            placeholderText: "Amount"
                            validator: DoubleValidator { bottom: 1; decimals: 4 }
                            onTextChanged: root.transferAmount = text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 13
                            background: Item {}
                        }

                        PlasmaComponents.Label {
                            text: currencySymbols[displayCurrency] || displayCurrency
                            color: "#2BAD72"
                            font.bold: true
                            font.pixelSize: 14
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        color: transferUseId ? "#2BAD72" : "#252525"
                        radius: 6

                        QQC2.Button {
                            anchors.fill: parent
                            text: "By ID"
                            flat: true
                            onClicked: root.transferUseId = true
                            font.bold: true
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Item {}
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        color: !transferUseId ? "#2BAD72" : "#252525"
                        radius: 6

                        QQC2.Button {
                            anchors.fill: parent
                            text: "By Username"
                            flat: true
                            onClicked: root.transferUseId = false
                            font.bold: true
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Item {}
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: "#252525"
                    radius: 6

                    QQC2.TextField {
                        id: userField
                        anchors.fill: parent
                        anchors.margins: 6
                        placeholderText: root.transferUseId ? "User ID" : "Username"
                        onTextChanged: {
                            if (root.transferUseId) root.transferUserId = text
                            else root.transferUsername = text
                        }
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 13
                        background: Item {}
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color: "#252525"
                    radius: 6

                    QQC2.TextField {
                        id: commentField
                        anchors.fill: parent
                        anchors.margins: 6
                        placeholderText: "Comment (optional, max 255)"
                        onTextChanged: {
                            if (text.length > 255) {
                                text = text.substring(0, 255)
                            }
                            root.transferComment = text
                        }
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 13
                        background: Item {}
                    }
                }

                PlasmaComponents.Label {
                    text: root.transferStatus
                    color: root.transferSuccess ? "#2BAD72" : "#884444"
                    visible: root.transferStatus.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: 12
                    font.bold: true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 40
                        color: "#2BAD72"
                        radius: 6

                        QQC2.Button {
                            anchors.fill: parent
                            text: "Send"
                            enabled: !root.pendingTransfer && amountField.text.length > 0 && userField.text.length > 0
                            onClicked: root.sendTransfer()
                            flat: true
                            font.bold: true
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Item {}
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 40
                        color: "#252525"
                        radius: 6

                        QQC2.Button {
                            anchors.fill: parent
                            text: "Close"
                            onClicked: transferWindow.close()
                            flat: true
                            font.bold: true
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Item {}
                        }
                    }
                }

                Item { Layout.fillHeight: true }
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

        function onUpdateIntervalChanged() {
            balanceTimer.restart()
        }

        function onDisplayCurrencyChanged() {
            root.displaySymbol = root.currencySymbols[root.displayCurrency] || root.displayCurrency
            if (root.displayCurrency !== "RUB") {
                root.fetchCurrencyRates()
            }
            root.recalcDisplay()
        }

        function onCurrencyRefreshIntervalChanged() {
            currencyTimer.restart()
        }

        function onApiServerChanged() {
            root.silentFetchBalance()
        }
    }

    function manualRefresh() {
        if (pendingBalance) return
        if (displayCurrency !== "RUB") fetchCurrencyRates()
        silentFetchBalance()
    }

    function silentFetchBalance() {
        if (apiKey.length === 0) {
            statusText = "No API Key"
            hasError = true
            return
        }
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
                statusText = "Bad Token"
                hasError = true
                pendingBalance = false
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
                if (!hasFetchedOnce) {
                    statusText = "Timeout"
                    hasError = true
                }
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
            var bal = data.user.balance
            rawBalance = (bal !== undefined && bal !== null) ? String(bal) : "0.00"
            hasFetchedOnce = true
            hasError = false
            statusText = ""
            recalcDisplay()
        } catch (e) {
            if (!hasFetchedOnce) {
                statusText = "Parse Err"
                hasError = true
            }
        }
    }

    function recalcDisplay() {
        displaySymbol = currencySymbols[displayCurrency] || displayCurrency

        var bal = parseFloat(rawBalance)
        if (isNaN(bal)) bal = 0

        if (displayCurrency === "RUB") {
            displayText = formatNumber(bal)
            return
        }

        var rate = currencyRates[displayCurrency]
        if (!rate || rate <= 0) {
            displayText = formatNumber(bal)
            displaySymbol = "₽"
            return
        }

        displayText = formatNumber(bal / rate)
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
            if (canFallback) {
                doFetchCurrency(fallbackServer, false)
            } else {
                pendingCurrency = false
            }
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
                if (list.hasOwnProperty(key) && list[key].rate > 0) {
                    rates[key] = list[key].rate
                }
            }
            currencyRates = rates
            recalcDisplay()
        } catch (e) {}
    }

    function sendTransfer() {
        if (pendingTransfer) return
        if (apiKey.length === 0) {
            transferStatus = "No API Key"
            transferSuccess = false
            return
        }

        var amount = parseFloat(transferAmount)
        if (isNaN(amount) || amount <= 0) {
            transferStatus = "Invalid amount"
            transferSuccess = false
            return
        }

        var target = transferUseId ? transferUserId : transferUsername
        if (target.length === 0) {
            transferStatus = "Enter recipient"
            transferSuccess = false
            return
        }

        pendingTransfer = true
        transferStatus = "Sending..."
        transferSuccess = false

        var body = {
            currency: transferCurrency.toLowerCase(),
            amount: amount,
            telegram_deal: false,
            transfer_hold: false,
            comment: transferComment.length > 0 ? transferComment : ""
        }

        if (transferUseId) {
            body.user_id = parseInt(target) || 0
        } else {
            body.username = target
        }

        var xhr = new XMLHttpRequest()
        xhr.timeout = 15000

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return

            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.status === "ok") {
                        transferStatus = resp.message || "Success"
                        transferSuccess = true
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
                    transferStatus = "Parse error"
                    transferSuccess = false
                }
            } else if (xhr.status === 401) {
                transferStatus = "Bad Token"
                transferSuccess = false
            } else if (xhr.status === 429) {
                transferStatus = "Rate Limited"
                transferSuccess = false
            } else if (xhr.status === 0) {
                transferStatus = "Offline"
                transferSuccess = false
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
            transferStatus = "Timeout"
            transferSuccess = false
            pendingTransfer = false
        }

        xhr.open("POST", primaryServer + "/balance/transfer")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Accept", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        xhr.send(JSON.stringify(body))
    }
}
