import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.notification
import "rates.js" as Rates
import "secret.js" as Secret

PlasmoidItem {
    id: root

    property string rawBalance:    "0.00"
    property string rawHold:       "0.00"
    property string displayText:   "0"
    property string displaySymbol: "₽"
    property string displayHold:   "0"
    property bool   holdPositive:  false

    property string statusText:       ""
    property bool   hasError:         false
    property bool   hasFetchedOnce:   false
    property bool   hasCryptoFetchedOnce: false
    property bool   pendingFetch:     false
    property bool   pendingTransfer:  false
    property string transferStatus:   ""
    property bool   transferSuccess:  false

    property var    currencyRates: ({})

    // Track the single in-flight XHR and a generation counter so that stale
    // callbacks from a previously aborted or superseded request are ignored.
    // This prevents multiple overlapping requests from piling up when the
    // network is slow or the API is unreachable, which can leak memory and
    // eventually wedge or crash plasmashell.
    property int    fetchGeneration: 0
    property var    activeXhr: null

    property string transferAmount:         ""
    property string transferTargetCurrency: "RUB"
    property bool   transferUseId:          true
    property string transferUserId:         ""
    property string transferUsername:       ""
    property string transferComment:        ""

    // Decoded token; empty if stored value is empty OR if decoding failed.
    // tokenStoredButEmpty distinguishes "no token configured" from "stored
    // token is corrupt / decode failed" so the user gets the right status.
    readonly property string rawStoredKey:   Plasmoid.configuration.apiKey || ""
    readonly property string apiKey:         Secret.decode(rawStoredKey)
    readonly property bool   tokenStoredButEmpty: rawStoredKey.length > 0 && apiKey.length === 0
    readonly property int    refreshMs:      (Plasmoid.configuration.updateInterval || 30) * 1000
    readonly property string displayCurrency:Plasmoid.configuration.displayCurrency || "RUB"
    readonly property string primaryServer:  Plasmoid.configuration.apiServer || "https://prod-api.lzt.market"
    readonly property string cryptoProvider: Plasmoid.configuration.cryptoProvider || "lzt"
    readonly property string fallbackServer: primaryServer === "https://prod-api.lzt.market"
        ? "https://api.lzt.market" : "https://prod-api.lzt.market"

    readonly property var currencySymbols: ({
        "RUB": "₽", "USD": "$", "EUR": "€", "UAH": "₴",
        "BTC": "₿"
    })

    // Parsed from Plasmoid.configuration.cryptoList; drives the panel Repeater.
    property var cryptoEntries: []
    readonly property bool canFetchCryptoWithoutToken: apiKey.length === 0
        && cryptoProvider === "coingecko"
        && cryptoEntries.length > 0
        && !tokenStoredButEmpty
    readonly property bool showBalanceBlock: apiKey.length > 0
        || hasError
        || cryptoProvider !== "coingecko"
        || cryptoEntries.length === 0

    // Fixed crypto price color — a soft off-white (dimmer than pure white).
    readonly property color cryptoColor: "#D6D6D6"

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Transfer Money")
            icon.name: "document-send"
            onTriggered: root.openTransfer()
        },
        PlasmaCore.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: root.forceRefresh()
        },
        PlasmaCore.Action {
            text: i18n("Check for updates")
            icon.name: "update-none"
            onTriggered: updateChecker.check(true)
        }
    ]

    // Suppress the default Plasma tooltip (Name/Description from metadata.json).
    //
    // toolTipItem / toolTipMainText / toolTipSubText are properties of
    // PlasmoidItem itself — NOT of the `Plasmoid` attached object.
    //
    // The `Plasmoid` attached type maps to Plasma::Applet, which only exposes
    //   contextualActions, configuration, formFactor, status, busy,
    //   backgroundHints, metaData, etc. (verified in applet.h)
    // Using `Plasmoid.toolTipMainText:` triggers QML error
    //   "Cannot assign to non-existent property toolTipMainText"
    // because Applet has no such property. Always use these without prefix.
    //
    // A 0x0 Item can confuse Plasma's tooltip sizing / positioning code and has
    // been associated with instability in some Plasma 6 builds, so we leave the
    // item undefined and just blank the texts.
    toolTipMainText: ""
    toolTipSubText: ""

    // ── Desktop notification for balance changes ────────────────
    // QML name is `Notification` (not `KNotification`) — the module exports
    // org.kde.notification/Notification 1.0 with prototype KNotification.
    // Verified via /usr/lib/qt6/qml/org/kde/notification/*.qmltypes.
    Notification {
        id: balanceNotif
        componentName: "plasma_workspace"
        eventId: "notification"
        iconName: "lztbalance"
        title: "Lolzteam"
        flags: Notification.CloseOnTimeout
    }

    // Checks GitHub for newer releases (daily + on demand via context menu).
    UpdateChecker {
        id: updateChecker
        currentVersion: "3.6.0"
    }

    // Auto-hide the transfer status (success / error) after 2 seconds.
    // Restarted every time transferStatus changes to a non-empty value.
    Timer {
        id: statusHideTimer
        interval: 2000
        repeat: false
        onTriggered: root.transferStatus = ""
    }
    onTransferStatusChanged: {
        if (transferStatus.length > 0) statusHideTimer.restart()
        else                            statusHideTimer.stop()
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
        id: compactRoot

        readonly property bool horizontal: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
        readonly property bool vertical:   Plasmoid.formFactor === PlasmaCore.Types.Vertical

        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: root.openTransfer()

        states: [
            State {
                name: "horizontalPanel"
                when: compactRoot.horizontal
                PropertyChanges {
                    compactRoot.Layout.fillHeight: true
                    compactRoot.Layout.fillWidth: false
                    // +largeSpacing on both sides keeps a visible gap to the
                    // adjacent panel widget (BTC/ETH icons next door otherwise
                    // butt right up against the hold text).
                    compactRoot.Layout.minimumWidth: contentRow.implicitWidth + Kirigami.Units.largeSpacing
                    compactRoot.Layout.maximumWidth: compactRoot.Layout.minimumWidth
                }
            },
            State {
                name: "verticalPanel"
                when: compactRoot.vertical
                PropertyChanges {
                    compactRoot.Layout.fillHeight: false
                    compactRoot.Layout.fillWidth: true
                    compactRoot.Layout.minimumHeight: contentRow.implicitHeight
                    compactRoot.Layout.maximumHeight: compactRoot.Layout.minimumHeight
                }
            },
            State {
                name: "desktop"
                when: !compactRoot.horizontal && !compactRoot.vertical
                PropertyChanges {
                    compactRoot.Layout.fillHeight: false
                    compactRoot.Layout.fillWidth: false
                    compactRoot.Layout.minimumWidth:  Kirigami.Units.gridUnit * 4
                    compactRoot.Layout.minimumHeight: Kirigami.Units.gridUnit * 2
                }
            }
        ]

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignVCenter

            Image {
                visible: root.showBalanceBlock
                source: Qt.resolvedUrl("images/lolzteam.svg")
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.alignment: Qt.AlignVCenter
                smooth: true
                mipmap: true
            }

            Text {
                visible: root.showBalanceBlock
                text: {
                    if (root.hasError)        return root.statusText
                    if (!root.hasFetchedOnce) return "..."
                    return root.displayText + root.displaySymbol
                }
                color: root.hasError ? "#884444" : "#2BAD72"
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.showBalanceBlock && root.holdPositive && root.hasFetchedOnce && !root.hasError
                text: "/"
                color: "#404040"
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                visible: root.showBalanceBlock && root.holdPositive && root.hasFetchedOnce && !root.hasError
                text: root.displayHold + root.displaySymbol
                color: "#707070"
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                Layout.alignment: Qt.AlignVCenter
            }

            // ── Separator before crypto rates ───────────────────────
            Rectangle {
                visible: root.cryptoEntries.length > 0 && root.showBalanceBlock
                Layout.preferredWidth: 1
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignVCenter
                color: "#404040"
            }

            // ── Crypto rates ────────────────────────────────────────
            Repeater {
                model: root.cryptoEntries
                delegate: RowLayout {
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: Kirigami.Units.smallSpacing   // a little more air between coins

                    Image {
                        source: {
                            var f = (modelData.code === "MATIC") ? "pol" : String(modelData.code).toLowerCase()
                            return Qt.resolvedUrl("images/crypto/" + f + ".svg")
                        }
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        Layout.alignment: Qt.AlignVCenter
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: Kirigami.Units.iconSizes.smallMedium
                        sourceSize.height: Kirigami.Units.iconSizes.smallMedium
                        smooth: true; mipmap: true
                    }
                    Text {
                        text: root.cryptoText(modelData)
                        color: root.cryptoColor
                        font.bold: true
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────
    // Transfer dialog
    // ────────────────────────────────────────────────────────────────
    PlasmaCore.Dialog {
        id: transferDialog
        type: PlasmaCore.Dialog.Normal
        hideOnWindowDeactivate: true
        flags: Qt.Dialog
        backgroundHints: PlasmaCore.Dialog.NoBackground

        onVisibleChanged: {
            if (!visible) Qt.callLater(root.resetTransferForm)
        }

        mainItem: Rectangle {
            width: 340
            implicitHeight: dlgCol.implicitHeight + 32
            color: "#0d0d0d"
            radius: 12
            border.color: "#262626"
            border.width: 1

            ColumnLayout {
                id: dlgCol
                anchors {
                    top:    parent.top
                    left:   parent.left
                    right:  parent.right
                    margins: 16
                }
                spacing: 7

                // ── Header card with subtle glow ────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    radius: 6
                    border.color: "#262626"
                    border.width: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#161616" }
                        GradientStop { position: 0.5; color: "#171818" }
                        GradientStop { position: 1.0; color: "#1b2620" }
                    }

                    // Green accent bar
                    Rectangle {
                        x: 0; y: 12
                        width: 3; height: 36
                        radius: 2
                        color: "#2BAD72"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 16
                        spacing: 0

                        Image {
                            source: Qt.resolvedUrl("images/lolzteam.svg")
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                            smooth: true; mipmap: true
                        }

                        Text {
                            text: "Transfer"
                            color: "#2BAD72"
                            font.bold: true
                            font.pixelSize: 16
                            font.letterSpacing: 0.3
                            Layout.fillWidth: true
                            leftPadding: 11
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Column {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                text: root.displayText + root.displaySymbol
                                color: "#FFFFFF"
                                font.pixelSize: 14
                                font.bold: true
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                            }
                            Text {
                                visible: root.holdPositive
                                text: "hold " + root.displayHold + root.displaySymbol
                                color: "#707070"
                                font.pixelSize: 10
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }

                // ── Amount ──────────────────────────────────────
                // TextField fills the whole Rectangle so the entire 48px
                // tall area is clickable — not just the centered text.
                // Currency symbol overlays on the right inside the
                // TextField's right padding.
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    color: "#161616"
                    radius: 6
                    border.width: 1
                    border.color: amountField.activeFocus ? "#2BAD72" : "#262626"

                    QQC2.TextField {
                        id: amountField
                        anchors.fill: parent
                        leftPadding: 16
                        rightPadding: 40        // room for the currency symbol
                        topPadding: 0
                        bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "0"
                        validator: DoubleValidator {
                            bottom: 0.01
                            top: 10000000
                            decimals: 4
                            notation: DoubleValidator.StandardNotation
                        }
                        onTextChanged: root.transferAmount = text
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 17
                        background: Item {}
                        placeholderTextColor: "#3a3a3a"
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.currencySymbols[root.transferTargetCurrency] || root.transferTargetCurrency
                        color: "#2BAD72"
                        font.bold: true
                        font.pixelSize: 19
                    }
                }

                // ── Currency toggle: RUB / USD ──────────────────
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
                            height: 36
                            radius: 6
                            color:        root.transferTargetCurrency === modelData.code ? "#2BAD72" : "#161616"
                            border.color: root.transferTargetCurrency === modelData.code ? "#2BAD72" : "#262626"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "#FFFFFF"
                                opacity: root.transferTargetCurrency === modelData.code ? 1.0 : 0.5
                                font.bold: true
                                font.pixelSize: 12
                                font.letterSpacing: 0.3
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.transferTargetCurrency = modelData.code
                            }
                        }
                    }
                }

                // ── By ID / By Username ─────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color:        root.transferUseId ? "#2BAD72" : "#161616"
                        border.color: root.transferUseId ? "#2BAD72" : "#262626"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "By ID"
                            color: "#FFFFFF"
                            opacity: root.transferUseId ? 1.0 : 0.5
                            font.bold: true
                            font.pixelSize: 12
                            font.letterSpacing: 0.3
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.transferUseId = true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        radius: 6
                        color:        !root.transferUseId ? "#2BAD72" : "#161616"
                        border.color: !root.transferUseId ? "#2BAD72" : "#262626"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "By Username"
                            color: "#FFFFFF"
                            opacity: !root.transferUseId ? 1.0 : 0.5
                            font.bold: true
                            font.pixelSize: 12
                            font.letterSpacing: 0.3
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.transferUseId = false
                        }
                    }
                }

                // ── Recipient ───────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    color: "#161616"
                    radius: 6
                    border.width: 1
                    border.color: userField.activeFocus ? "#2BAD72" : "#262626"

                    QQC2.TextField {
                        id: userField
                        // Fill the whole Rectangle so the entire 48px area
                        // is clickable. Horizontal padding gives the visual
                        // text indent without creating a dead zone.
                        anchors.fill: parent
                        leftPadding: 16
                        rightPadding: 16
                        topPadding: 0
                        bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: root.transferUseId ? "User ID" : "Username"
                        onTextChanged: {
                            if (root.transferUseId) root.transferUserId   = text
                            else                    root.transferUsername = text
                        }
                        color: "#FFFFFF"
                        font.bold: true
                        font.pixelSize: 13
                        background: Item {}
                        placeholderTextColor: "#3a3a3a"
                    }
                }

                // ── Comment ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 48
                    color: "#161616"
                    radius: 6
                    border.width: 1
                    border.color: commentField.activeFocus ? "#2BAD72" : "#262626"

                    QQC2.TextField {
                        id: commentField
                        anchors.fill: parent
                        leftPadding: 16
                        rightPadding: 16
                        topPadding: 0
                        bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "Comment (optional)"
                        maximumLength: 255
                        onTextChanged: root.transferComment = text
                        color: "#FFFFFF"
                        font.pixelSize: 13
                        background: Item {}
                        placeholderTextColor: "#3a3a3a"
                    }
                }

                // ── Status (reserves a fixed slot so the dialog never
                //   resizes mid-flight, which would push the Send button
                //   off the bottom). Hidden via opacity (not `visible:`)
                //   because invisible items drop out of the column layout
                //   entirely. Slot is intentionally small — most status
                //   messages are short and fit comfortably.
                Rectangle {
                    Layout.fillWidth: true
                    height: 28
                    opacity: root.transferStatus.length > 0 ? 1 : 0
                    radius: 6
                    color:        root.transferSuccess ? "#0d2618" : "#2a1010"
                    border.color: root.transferSuccess ? "#2BAD72" : "#884444"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.margins: 10
                        text: root.transferStatus
                        color: root.transferSuccess ? "#2BAD72" : "#FFFFFF"
                        font.pixelSize: 11
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                // ── Send ────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 6
                    color: {
                        if (root.pendingTransfer) return "#1a3d2b"
                        if (amountField.text.length === 0 || userField.text.length === 0) return "#161616"
                        return "#2BAD72"
                    }
                    border.color: {
                        if (root.pendingTransfer) return "#2BAD72"
                        if (amountField.text.length === 0 || userField.text.length === 0) return "#262626"
                        return "#2BAD72"
                    }
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: root.pendingTransfer ? "Sending..." : "Send"
                        color: {
                            if (root.pendingTransfer) return "#2BAD72"
                            if (amountField.text.length === 0 || userField.text.length === 0) return "#404040"
                            return "#FFFFFF"
                        }
                        font.bold: true
                        font.pixelSize: 14
                        font.letterSpacing: 0.3
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
        // Do not pile up a new request while the previous one is still in
        // flight. The timer will resume ticking once the current fetch ends.
        running:  !root.pendingFetch && (root.apiKey.length > 0 || root.canFetchCryptoWithoutToken)
        repeat:   true
        onTriggered: root.fetchAll()
    }

    // Recovery timer: retry while we have a token or crypto-only mode but are
    // not in a good state. It pauses while a request is in flight, so it can't
    // spawn overlapping XHRs. Auto-stops as soon as a fetch succeeds.
    Timer {
        id: recoveryTimer
        interval: 8000
        repeat: true
        running: !root.pendingFetch && (
            (root.apiKey.length > 0 && (!root.hasFetchedOnce || root.hasError))
            || (root.canFetchCryptoWithoutToken && (!root.hasCryptoFetchedOnce || root.hasError)))
        onTriggered: {
            console.log("[lzt] recovery-tick - bad state, force-retrying")
            root.forceRefresh()
        }
    }

    // Watchdog: a hard backstop so pendingFetch can NEVER stay true forever.
    // Armed by startFetch, cleared by endFetch. If it ever fires it means a
    // fetch's callbacks silently never ran (Qt XHR edge case), so we unwedge
    // and mark the widget as offline. Aborts the active request as well.
    Timer {
        id: fetchWatchdog
        interval: 35000
        repeat: false
        onTriggered: {
            console.log("[lzt] watchdog fired - fetch wedged, force-resetting")
            root.endFetch()
            if (!root.hasFetchedOnce && !root.hasCryptoFetchedOnce) { root.statusText = "Offline"; root.hasError = true }
        }
    }

    Component.onCompleted: {
        // Migrate any legacy plain-text token to the obfuscated form on disk.
        var stored = Plasmoid.configuration.apiKey || ""
        if (Secret.isPlain(stored)) {
            console.log("[lzt] migrating plain token to obfuscated form")
            Plasmoid.configuration.apiKey = Secret.encode(stored)
        }

        console.log("[lzt] init — stored.len=" + stored.length
                  + " decoded.len=" + apiKey.length
                  + " crypto.provider=" + cryptoProvider
                  + " stored.prefix=" + (stored.length > 0 ? stored.substring(0, 4) : "<empty>"))

        // Drive the update checker from metadata (single source of truth).
        try {
            if (Plasmoid.metaData) {
                if (Plasmoid.metaData.version) updateChecker.currentVersion = Plasmoid.metaData.version
                var u = Plasmoid.metaData.value("X-LZT-UpdateChecker-Url", "")
                if (u && u.length) updateChecker.url = u
            }
        } catch (e) {}
        rebuildCryptoEntries()

        if (apiKey.length > 0) {
            fetchAll()
        } else if (tokenStoredButEmpty) {
            // Stored value isn't empty but decoded to "" — corrupt enc: blob.
            console.log("[lzt] stored token failed to decode — len=" + stored.length)
            statusText = "Decode Err"; hasError = true
        } else if (canFetchCryptoWithoutToken) {
            fetchAll()
        } else {
            statusText = "No API Key"; hasError = true
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onApiKeyChanged() {
            if (root.apiKey.length > 0) { root.hasFetchedOnce = false; root.forceRefresh() }
            else if (root.canFetchCryptoWithoutToken) { root.hasFetchedOnce = false; root.forceRefresh() }
            else { root.statusText = "No API Key"; root.hasError = true }
        }
        function onUpdateIntervalChanged() { refreshTimer.restart() }
        function onDisplayCurrencyChanged(){ root.recalcDisplay() }
        function onApiServerChanged()      { root.forceRefresh() }
        function onCryptoProviderChanged() { root.forceRefresh() }
        function onCryptoListChanged()     { root.rebuildCryptoEntries(); root.forceRefresh() }
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

    function rebuildCryptoEntries() {
        cryptoEntries = Rates.parseCryptoList(Plasmoid.configuration.cryptoList)
    }

    // Display string for one crypto entry, e.g. "73328$".
    function cryptoText(entry) {
        if (!hasCryptoFetchedOnce && !hasFetchedOnce) return "…"
        var v = Rates.convert(currencyRates, entry.code, entry.currency)
        var sym = currencySymbols[entry.currency] || entry.currency
        return Rates.formatRate(v) + sym
    }

    // Start a new request: abort any previous in-flight request and become the
    // current active XHR. The generation counter lets stale callbacks from an
    // aborted request identify themselves and bail out.
    function startFetch(xhr) {
        fetchGeneration++
        if (activeXhr) {
            try { activeXhr.abort() } catch (e) {}
        }
        activeXhr = xhr
        pendingFetch = true
        fetchWatchdog.restart()
    }

    // Single point that clears the in-flight flag, stops the watchdog, and
    // aborts the underlying request. Every code path that finishes a fetch must
    // call this so pendingFetch can never get permanently stuck.
    function endFetch() {
        var xhr = activeXhr
        activeXhr = null
        if (xhr) {
            try { xhr.abort() } catch (e) {}
        }
        pendingFetch = false
        fetchWatchdog.stop()
    }

    function isCurrentRequest(xhr) {
        return xhr === activeXhr
    }

    // User-initiated refresh. Unlike fetchAll(), it force-clears any stuck
    // in-flight state first, so pressing Refresh / changing the API server
    // ALWAYS triggers a real request even if a previous fetch wedged.
    function forceRefresh() {
        endFetch()
        fetchAll()
    }

    function fetchAll() {
        if (pendingFetch) return
        if (apiKey.length === 0) {
            if (canFetchCryptoWithoutToken) {
                pendingFetch = true
                fetchWatchdog.restart()
                hasError = false
                statusText = ""
                fetchCoinGeckoRates()
            } else {
                statusText = "No API Key"
                hasError = true
            }
            return
        }
        doFetchBatch(primaryServer, true)
    }

    function doFetchBatch(server, canFallback) {
        if (pendingFetch) return

        var jobs = [
            { method: "GET", uri: server + "/currency", id: "1" },
            { method: "GET", uri: server + "/me",       id: "2" }
        ]
        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        startFetch(xhr)

        xhr.onreadystatechange = function() {
            if (!isCurrentRequest(xhr)) return
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                var needCrypto = parseBatchResponse(xhr.responseText)
                if (needCrypto) fetchCoinGeckoRates()
                else endFetch()
            } else if (xhr.status === 401) {
                statusText = "Bad Token"; hasError = true; endFetch()
            } else if (canFallback) {
                doFetchBatch(fallbackServer, false)
            } else {
                if      (xhr.status === 429) statusText = "Rate Limit"
                else if (xhr.status === 0)   statusText = "Offline"
                else                         statusText = "Err " + xhr.status
                if (!hasFetchedOnce) hasError = true
                endFetch()
            }
        }
        xhr.ontimeout = function() {
            if (!isCurrentRequest(xhr)) return
            if (canFallback) doFetchBatch(fallbackServer, false)
            else {
                if (!hasFetchedOnce) { statusText = "Timeout"; hasError = true }
                endFetch()
            }
        }

        // open()/send() can THROW synchronously when the network stack isn't
        // ready (common at boot). Without this guard the throw would skip
        // every callback and leave pendingFetch stuck true forever.
        try {
            xhr.open("POST", server + "/batch")
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.setRequestHeader("Accept",       "application/json")
            xhr.setRequestHeader("Authorization","Bearer " + apiKey)
            xhr.send(JSON.stringify(jobs))
        } catch (e) {
            console.log("[lzt] fetch send threw: " + e)
            if (!isCurrentRequest(xhr)) return
            if (canFallback) {
                doFetchBatch(fallbackServer, false)
            } else {
                if (!hasFetchedOnce) { statusText = "Offline"; hasError = true }
                endFetch()
            }
        }
    }

    function parseBatchResponse(raw) {
        var shouldFetchCoinGecko = false
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
                shouldFetchCoinGecko = cryptoProvider === "coingecko" && cryptoEntries.length > 0
            }

            if (j2 && j2._job_result === "ok" && j2.user) {
                var u = j2.user
                var newBalStr = (u.balance !== undefined && u.balance !== null) ? String(u.balance) : "0.00"

                // Detect balance change and fire a desktop notification.
                // Skip the very first fetch — we don't want a popup showing
                // the entire initial balance on widget load / Plasma restart.
                if (hasFetchedOnce) {
                    var oldBal = parseFloat(rawBalance)
                    var newBal = parseFloat(newBalStr)
                    if (!isNaN(oldBal) && !isNaN(newBal) && Math.abs(newBal - oldBal) >= 0.01) {
                        sendBalanceNotification(newBal - oldBal)
                    }
                }

                rawBalance = newBalStr
                rawHold    = (u.hold !== undefined && u.hold !== null) ? String(u.hold) : "0.00"
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
        return shouldFetchCoinGecko
    }

    function fetchCoinGeckoRates() {
        var ids = Rates.coingeckoIdsForEntries(cryptoEntries, displayCurrency !== "RUB")
        var quotes = Rates.coingeckoQuotesForEntries(cryptoEntries, displayCurrency)
        if (ids.length === 0) { endFetch(); return }

        var url = "https://api.coingecko.com/api/v3/simple/price"
            + "?ids=" + encodeURIComponent(ids.join(","))
            + "&vs_currencies=" + encodeURIComponent(quotes.join(","))
            + "&include_last_updated_at=true"

        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        startFetch(xhr)
        xhr.onreadystatechange = function() {
            if (!isCurrentRequest(xhr)) return
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                parseCoinGeckoResponse(xhr.responseText)
            } else {
                console.log("[lzt] coingecko failed: " + xhr.status)
                if (!hasFetchedOnce && !hasCryptoFetchedOnce) {
                    statusText = xhr.status === 0 ? "Offline" : ("CG Err " + xhr.status)
                    hasError = true
                }
            }
            endFetch()
        }
        xhr.ontimeout = function() {
            if (!isCurrentRequest(xhr)) return
            console.log("[lzt] coingecko timed out")
            if (!hasFetchedOnce && !hasCryptoFetchedOnce) { statusText = "Timeout"; hasError = true }
            endFetch()
        }

        try {
            xhr.open("GET", url)
            xhr.setRequestHeader("Accept", "application/json")
            xhr.send()
        } catch (e) {
            console.log("[lzt] coingecko send threw: " + e)
            if (!isCurrentRequest(xhr)) return
            if (!hasFetchedOnce && !hasCryptoFetchedOnce) { statusText = "Offline"; hasError = true }
            endFetch()
        }
    }

    function parseCoinGeckoResponse(raw) {
        try {
            var data = JSON.parse(raw)
            var merged = {}
            for (var k in currencyRates)
                if (currencyRates.hasOwnProperty(k)) merged[k] = currencyRates[k]

            var touched = false
            var quotes = Rates.coingeckoQuotesForEntries(cryptoEntries, displayCurrency)
            for (var i = 0; i < cryptoEntries.length; i++) {
                var code = cryptoEntries[i].code
                var id = Rates.coingeckoId(code)
                if (id.length === 0 || !data[id] || !data[id].rub || data[id].rub <= 0) continue
                merged[code] = data[id].rub
                touched = true

                for (var q = 0; q < quotes.length; q++) {
                    var quoteKey = quotes[q]
                    var quoteCode = String(quoteKey).toUpperCase()
                    if (quoteCode === "RUB") continue
                    if (data[id][quoteKey] && data[id][quoteKey] > 0) {
                        merged[quoteCode] = data[id].rub / data[id][quoteKey]
                    }
                }
            }

            if (displayCurrency !== "RUB" && Rates.coingeckoSupportsQuote(displayCurrency)) {
                var btc = data[Rates.coingeckoId("BTC")]
                var quoteKey = String(displayCurrency).toLowerCase()
                if (btc && btc.rub > 0 && btc[quoteKey] > 0) {
                    merged[displayCurrency] = btc.rub / btc[quoteKey]
                }
            }

            if (!touched && !hasCryptoFetchedOnce) throw new Error("no coingecko rates")
            currencyRates = merged
            hasCryptoFetchedOnce = true
            if (apiKey.length === 0) {
                hasError = false
                statusText = ""
            }
            recalcDisplay()
        } catch (e) {
            console.log("[lzt] coingecko parse failed: " + e)
            if (!hasFetchedOnce && !hasCryptoFetchedOnce) {
                statusText = "CG Parse"
                hasError = true
            }
        }
    }

    function recalcDisplay() {
        var bal  = parseFloat(rawBalance)
        var hold = parseFloat(rawHold)
        if (isNaN(bal))  bal  = 0
        if (isNaN(hold) || hold < 0) hold = 0

        var symbol = "₽"
        if (displayCurrency === "RUB") {
            displayText = formatNumber(bal)
            displayHold = formatNumber(hold)
        } else {
            var rate = currencyRates[displayCurrency]
            if (!rate || rate <= 0) {
                displayText = formatNumber(bal)
                displayHold = formatNumber(hold)
            } else {
                displayText = formatNumber(bal  / rate)
                displayHold = formatNumber(hold / rate)
                symbol = currencySymbols[displayCurrency] || displayCurrency
            }
        }
        displaySymbol = symbol
        holdPositive = hold > 0.001
    }

    // Build a "+100₽" / "−50$" string and fire a desktop notification.
    // deltaRub is the change in raw API balance (always RUB).
    // We convert to the user-selected display currency so the notification
    // matches what they see in the panel.
    function sendBalanceNotification(deltaRub) {
        var symbol = "₽"
        var deltaDisplay = deltaRub

        if (displayCurrency !== "RUB") {
            var rate = currencyRates[displayCurrency]
            if (rate && rate > 0) {
                deltaDisplay = deltaRub / rate
                symbol = currencySymbols[displayCurrency] || displayCurrency
            }
        }

        // Unicode minus (−) reads better than ASCII hyphen for negative deltas
        var sign = deltaDisplay > 0 ? "+" : "−"
        var amount = formatNumber(Math.abs(deltaDisplay))
        balanceNotif.text = sign + amount + symbol
        balanceNotif.sendEvent()
    }

    // Smart number format:
    //   0      → "0"
    //   10.00  → "10"        (integer)
    //   10.05  → "10.1"      (one decimal)
    //   123.45 → "123.5"     (one decimal, rounded)
    //   0.005  → "0.005"     (small values keep precision)
    function formatNumber(v) {
        if (isNaN(v) || v <= 0) return "0"

        if (v < 1) {
            var s = v.toFixed(4)
            return s.replace(/\.?0+$/, "") || "0"
        }

        var r = Math.round(v * 10) / 10
        if (Math.abs(r - Math.round(r)) < 0.001) return Math.round(r).toString()
        return r.toFixed(1)
    }

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
        // Clear the status row during pending — the user wants only
        // success/fail to surface here. The Send button already shows
        // "Sending..." as visual feedback that the request is in flight.
        transferStatus  = ""
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
                        transferAmount = ""; transferUserId = ""; transferUsername = ""; transferComment = ""
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
                if (canFallback) {
                    // Silent fallback — no intermediate "Retrying..." status.
                    // Send button still shows "Sending..." while we retry.
                    doSendTransfer(fallbackServer, body, false)
                } else {
                    transferStatus = xhr.status === 0 ? "Offline" : ("Server Err " + xhr.status)
                    transferSuccess = false; pendingTransfer = false
                }
            } else {
                try {
                    var err = JSON.parse(xhr.responseText)
                    transferStatus = (err.errors && err.errors.length > 0)
                        ? err.errors[0] : (err.message || ("Err " + xhr.status))
                } catch (e) { transferStatus = "Err " + xhr.status }
                transferSuccess = false; pendingTransfer = false
            }
        }

        xhr.ontimeout = function() {
            if (canFallback) {
                // Silent fallback — see comment above.
                doSendTransfer(fallbackServer, body, false)
            } else {
                transferStatus = "Timeout"; transferSuccess = false; pendingTransfer = false
            }
        }

        xhr.open("POST", server + "/balance/transfer")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Accept",       "application/json")
        xhr.setRequestHeader("Authorization","Bearer " + apiKey)
        xhr.send(JSON.stringify(body))
    }
}
