import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: page
    Layout.fillWidth: true
    Layout.fillHeight: true

    // KConfig binding — the hidden Text below holds the serialized JSON.
    property alias cfg_cryptoList: serialized.text

    // Coins that have BOTH an icon and a /currency rate.
    readonly property var supportedCoins: [
        "BTC","ETH","BNB","XMR","BCH","SOL","LTC","DASH",
        "AVAX","TON","USDC","DAI","USDT","TRX","POL","MATIC","SHIB"
    ]
    // Same shortlist as the balance display currency.
    readonly property var currencyModel: [
        { text: "RUB  ₽",  value: "RUB" },
        { text: "USD  $",  value: "USD" },
        { text: "EUR  €",  value: "EUR" },
        { text: "UAH  ₴",  value: "UAH" },
        { text: "GBP  £",  value: "GBP" },
        { text: "BYN  Br", value: "BYN" },
        { text: "KZT  ₸",  value: "KZT" },
        { text: "BTC  ₿",  value: "BTC" }
    ]

    function iconSource(code) {
        var f = (code === "MATIC") ? "pol" : code.toLowerCase()
        return Qt.resolvedUrl("../images/crypto/" + f + ".svg")
    }

    // True while saveCoins() is writing serialized.text — prevents the
    // onTextChanged handler from rebuilding the model (which would reset the
    // ListView selection). We only rebuild on external loads (initial config).
    property bool suppressReload: false

    // Serialized JSON <-> ListModel mirror.
    Text {
        id: serialized
        visible: false
        onTextChanged: {
            if (page.suppressReload) return
            coinsModel.clear()
            var arr = []
            try { arr = JSON.parse(serialized.text) } catch (e) { arr = [] }
            if (!Array.isArray(arr)) arr = []
            for (var i = 0; i < arr.length; i++) {
                coinsModel.append({
                    code:     arr[i].code     || "BTC",
                    currency: arr[i].currency || "USD"
                })
            }
        }
    }

    ListModel { id: coinsModel }

    function saveCoins() {
        var out = []
        for (var i = 0; i < coinsModel.count; i++) {
            var it = coinsModel.get(i)
            out.push({ code: it.code, currency: it.currency })
        }
        suppressReload = true
        serialized.text = JSON.stringify(out)
        suppressReload = false
    }

    function currencyLabel(value) {
        for (var i = 0; i < currencyModel.length; i++)
            if (currencyModel[i].value === value) return currencyModel[i].text
        return value
    }

    // ── Sort by USD price ───────────────────────────────────────────
    // The config page has no live rates, so the sort button fetches /currency
    // once (using the token from the LZT tab) and orders coins by their price
    // in USD. First click = expensive→cheap, next click = cheap→expensive.
    property bool   sortDesc:   true
    property string sortStatus: ""
    property bool   sortBusy:   false

    Timer { id: statusClear; interval: 2600; onTriggered: page.sortStatus = "" }

    function setStatus(msg, busy) {
        sortStatus = msg
        sortBusy = busy === true
        if (!sortBusy && msg.length > 0) statusClear.restart()
        else statusClear.stop()
    }

    // Read a config value from the config page (plasmoid context property).
    function cfgGet(name, dflt) {
        try {
            if (typeof plasmoid !== 'undefined' && plasmoid && plasmoid.configuration) {
                var v = plasmoid.configuration[name]
                if (v !== undefined && v !== null) return v
            }
        } catch (e) {}
        return dflt
    }

    function requestSort() {
        if (coinsModel.count < 2) return
        var key = cfgGet("apiKey", "")
        if (!key || String(key).length === 0) { setStatus(i18n("Add API key in the LZT tab to sort")); return }
        var server = cfgGet("apiServer", "https://prod-api.lzt.market")
        setStatus(i18n("Sorting…"), true)
        doFetchRates(String(server), String(key), true)
    }

    function doFetchRates(server, key, canFallback) {
        var fallback = (server === "https://prod-api.lzt.market")
            ? "https://api.lzt.market" : "https://prod-api.lzt.market"
        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    var j = (data && data.jobs) ? data.jobs["1"] : null
                    if (j && j._job_result === "ok" && j.currencyList) {
                        var rates = {}
                        for (var k in j.currencyList)
                            if (j.currencyList.hasOwnProperty(k) && j.currencyList[k].rate > 0)
                                rates[k] = j.currencyList[k].rate
                        applySort(rates)
                        return
                    }
                } catch (e) {}
                setStatus(i18n("Sort failed"))
            } else if (xhr.status === 401) {
                setStatus(i18n("Bad API token"))
            } else if (canFallback) {
                doFetchRates(fallback, key, false)
            } else {
                setStatus(i18n("Sort failed"))
            }
        }
        xhr.ontimeout = function() {
            if (canFallback) doFetchRates(fallback, key, false)
            else setStatus(i18n("Sort timed out"))
        }
        xhr.open("POST", server + "/batch")
        xhr.setRequestHeader("Content-Type",  "application/json")
        xhr.setRequestHeader("Accept",        "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + key)
        xhr.send(JSON.stringify([{ method: "GET", uri: server + "/currency", id: "1" }]))
    }

    // Coin price in USD (rates are RUB-per-unit). Missing rate -> -1 (sinks).
    function priceUSD(rates, code) {
        var b = rates[code], q = rates["USD"]
        if (!b || !q || q <= 0) return -1
        return b / q
    }

    function applySort(rates) {
        var arr = []
        for (var i = 0; i < coinsModel.count; i++) {
            var it = coinsModel.get(i)
            arr.push({ code: it.code, currency: it.currency, p: priceUSD(rates, it.code) })
        }
        arr.sort(function(a, b) { return page.sortDesc ? (b.p - a.p) : (a.p - b.p) })
        coinsModel.clear()
        for (var j = 0; j < arr.length; j++)
            coinsModel.append({ code: arr[j].code, currency: arr[j].currency })
        saveCoins()
        page.sortDesc = !page.sortDesc
        setStatus("")
    }

    // ── Edit dialog state ───────────────────────────────────────────
    property int editIndex: -1

    function openAdd() {
        editIndex = -1
        coinCombo.currentIndex = 0
        currencyCombo.currentIndex = 1   // USD
        editDialog.open()
    }
    function openEdit(idx) {
        if (idx < 0 || idx >= coinsModel.count) return
        var it = coinsModel.get(idx)
        editIndex = idx
        coinCombo.currentIndex = Math.max(0, supportedCoins.indexOf(it.code))
        var ci = 1
        for (var i = 0; i < currencyModel.length; i++)
            if (currencyModel[i].value === it.currency) { ci = i; break }
        currencyCombo.currentIndex = ci
        editDialog.open()
    }

    // ── Layout: list on top, action toolbar underneath ──────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1
            radius: 3

            ListView {
                id: coinsList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: coinsModel
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds   // no jerky overscroll

                delegate: Rectangle {
                    width: coinsList.width
                    height: 40
                    color: ListView.isCurrentItem ? Kirigami.Theme.highlightColor
                         : (index % 2 === 0 ? Kirigami.Theme.backgroundColor : Kirigami.Theme.alternateBackgroundColor)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Image {
                            source: page.iconSource(model.code)
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            smooth: true; mipmap: true
                        }
                        PlasmaComponents.Label {
                            text: model.code
                            font.bold: true
                            Layout.preferredWidth: 70
                            color: coinsList.currentIndex === index ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                        PlasmaComponents.Label {
                            text: page.currencyLabel(model.currency)
                            Layout.fillWidth: true
                            color: coinsList.currentIndex === index ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: coinsList.currentIndex = index
                        onDoubleClicked: { coinsList.currentIndex = index; page.openEdit(index) }
                    }
                }

                PlasmaComponents.ScrollBar.vertical: PlasmaComponents.ScrollBar { }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: coinsModel.count === 0
                    text: i18n("No coins yet — click Add")
                    opacity: 0.6
                }
            }
        }

        // ── Action toolbar ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Button {
                text: i18n("Add"); icon.name: "list-add"
                onClicked: page.openAdd()
            }
            PlasmaComponents.Button {
                text: i18n("Edit"); icon.name: "edit-entry"
                enabled: coinsList.currentIndex >= 0 && coinsList.currentIndex < coinsModel.count
                onClicked: page.openEdit(coinsList.currentIndex)
            }
            PlasmaComponents.Button {
                text: i18n("Remove"); icon.name: "list-remove"
                enabled: coinsList.currentIndex >= 0 && coinsList.currentIndex < coinsModel.count
                onClicked: { coinsModel.remove(coinsList.currentIndex); page.saveCoins() }
            }

            PlasmaComponents.Label {
                text: page.sortStatus
                visible: text.length > 0
                opacity: 0.7
                Layout.leftMargin: Kirigami.Units.smallSpacing
                elide: Text.ElideRight
                Layout.maximumWidth: Kirigami.Units.gridUnit * 12
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents.ToolButton {
                icon.name: page.sortDesc ? "view-sort-descending" : "view-sort-ascending"
                display: QQC2.AbstractButton.IconOnly
                enabled: coinsModel.count > 1 && !page.sortBusy
                QQC2.ToolTip.text: i18n("Sort by price (USD)")
                QQC2.ToolTip.visible: hovered
                onClicked: page.requestSort()
            }

            PlasmaComponents.ToolButton {
                icon.name: "arrow-up"
                display: QQC2.AbstractButton.IconOnly
                enabled: coinsList.currentIndex > 0 && coinsList.currentIndex < coinsModel.count
                QQC2.ToolTip.text: i18n("Move up")
                QQC2.ToolTip.visible: hovered
                onClicked: {
                    var from = coinsList.currentIndex
                    coinsModel.move(from, from - 1, 1)
                    coinsList.currentIndex = from - 1
                    page.saveCoins()
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "arrow-down"
                display: QQC2.AbstractButton.IconOnly
                enabled: coinsList.currentIndex >= 0 && (coinsList.currentIndex + 1) < coinsModel.count
                QQC2.ToolTip.text: i18n("Move down")
                QQC2.ToolTip.visible: hovered
                onClicked: {
                    var from = coinsList.currentIndex
                    coinsModel.move(from, from + 1, 1)
                    coinsList.currentIndex = from + 1
                    page.saveCoins()
                }
            }
        }
    }

    // ── Add/Edit dialog ─────────────────────────────────────────────
    QQC2.Dialog {
        id: editDialog
        title: page.editIndex === -1 ? i18n("Add coin") : i18n("Edit coin")
        modal: true
        anchors.centerIn: QQC2.Overlay.overlay
        standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel

        onAccepted: {
            var obj = {
                code:     page.supportedCoins[coinCombo.currentIndex],
                currency: page.currencyModel[currencyCombo.currentIndex].value
            }
            if (page.editIndex === -1) coinsModel.append(obj)
            else                       coinsModel.set(page.editIndex, obj)
            page.saveCoins()
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: coinCombo
                Layout.fillWidth: true
                model: page.supportedCoins
            }
            QQC2.ComboBox {
                id: currencyCombo
                Layout.fillWidth: true
                model: page.currencyModel
                textRole: "text"
            }
        }
    }
}
