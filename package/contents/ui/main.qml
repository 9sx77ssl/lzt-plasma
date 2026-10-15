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

    // Minimum spacing between balance-change notifications (ms).
    property double lastBalanceNotifyMs: 0
    readonly property int balanceNotifyCooldownMs: 15000

    property var    currencyRates: ({})

    // Track the in-flight XHRs of the current fetch cycle and a generation
    // counter so that stale callbacks from a previously aborted or superseded
    // request are ignored. A cycle can have more than one parallel request
    // (/me + /currency, or a crypto ticker + its fiat anchor), so we keep an
    // array rather than a single handle.
    property int    fetchGeneration: 0
    property var    activeXhrs: []

    // One mutable object per cycle. endFetch() flips `closed` to true so that
    // any callback still queued by an aborted request (e.g. the sibling of a
    // 401, or a request killed by the watchdog) is ignored instead of running
    // after the cycle already ended — which used to schedule a retry on top of
    // a bad token and cause a slow retry ping-pong.
    property var    fetchCycle: null

    // Retry/backoff state. On a failed fetch we schedule ONE retry after an
    // exponentially growing delay (with jitter), and honor the server's
    // Retry-After header when present (needed for HTTP 429). This replaces the
    // old fixed 8s "recovery" loop that hammered the API every 8 seconds and
    // got the IP rate-limited (429) / blocked (403).
    property int    failureStreak:  0
    property bool   retryScheduled: false
    property int    retryDelayMs:   0
    readonly property int retryBaseMs:     3000
    readonly property int maxRetryDelayMs: 5 * 60 * 1000

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

    // Optional CoinGecko Demo API key (stored obfuscated like the LZT token).
    // Keyless CoinGecko is IP-rate-limited and shared across everyone behind the
    // same NAT, which is unreliable; a free Demo key raises the limit to
    // 100 calls/min and is sent as the x-cg-demo-api-key header.
    readonly property string rawStoredCgKey: Plasmoid.configuration.coingeckoApiKey || ""
    readonly property string coingeckoApiKey: Secret.decode(rawStoredCgKey)
    readonly property int    refreshMs:      (Plasmoid.configuration.updateInterval || 30) * 1000
    readonly property string displayCurrency:Plasmoid.configuration.displayCurrency || "RUB"
    readonly property string primaryServer:  Plasmoid.configuration.apiServer || "https://api.lzt.market"
    readonly property string cryptoProvider: Plasmoid.configuration.cryptoProvider || "lzt"
    // Single supported endpoint now; kept as a property so transfer/fetch code
    // paths that expect a backup have somewhere to go.
    readonly property string fallbackServer: primaryServer

    readonly property var currencySymbols: ({
        "RUB": "₽", "USD": "$", "EUR": "€", "UAH": "₴",
        "BTC": "₿"
    })

    // Parsed from Plasmoid.configuration.cryptoList; drives the panel Repeater.
    property var cryptoEntries: []
    // Only the coins the selected provider can actually price; the panel hides
    // the rest (the icon set is fixed, we never add new coins).
    readonly property var visibleCryptoEntries: Rates.providerVisibleEntries(cryptoProvider, cryptoEntries)
    // Any non-LZT provider is self-contained, so it can run without a token.
    readonly property bool canFetchCryptoWithoutToken: apiKey.length === 0
        && cryptoProvider !== "lzt"
        && visibleCryptoEntries.length > 0
        && !tokenStoredButEmpty
    readonly property bool showBalanceBlock: apiKey.length > 0
        || hasError
        || cryptoProvider === "lzt"
        || visibleCryptoEntries.length === 0

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
    toolTipItem: Item {
        implicitWidth: 0
        implicitHeight: 0
    }
    toolTipMainText: " "
    toolTipSubText: " "

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
        currentVersion: "3.8.0"
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
                visible: root.visibleCryptoEntries.length > 0 && root.showBalanceBlock
                Layout.preferredWidth: 1
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignVCenter
                color: "#404040"
            }

            // ── Crypto rates ────────────────────────────────────────
            Repeater {
                model: root.visibleCryptoEntries
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

    fullRepresentation: Item {}

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
            width: 336
            implicitHeight: dlgCol.implicitHeight + 28
            color: brand.bg
            radius: 10
            border.color: brand.border
            border.width: 1

            // LOLZ brand palette — lolz.team/pages/brand
            QtObject {
                id: brand
                readonly property color green:   "#2BAD72"
                readonly property color red:     "#884444"
                readonly property color bg:      "#0c0f0e"
                readonly property color surface: "#111615"
                readonly property color raised:  "#181e1c"
                readonly property color border:  "#1e2725"
                readonly property color text:    "#ffffff"
                readonly property color subtext: "#9aa39f"
                readonly property color muted:   "#4a5450"
            }

            ColumnLayout {
                id: dlgCol
                anchors {
                    top:    parent.top
                    left:   parent.left
                    right:  parent.right
                    margins: 14
                }
                spacing: 9

                // ── Header: logo · title · balance · close ──────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 10

                    Image {
                        source: Qt.resolvedUrl("images/lolzteam.svg")
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        smooth: true; mipmap: true
                    }

                    Text {
                        text: i18n("Transfer")
                        color: brand.text
                        font.bold: true
                        font.pixelSize: 14
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Column {
                        spacing: 0
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.right: parent.right
                            text: root.displayText + root.displaySymbol
                            color: brand.green
                            font.bold: true
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            anchors.right: parent.right
                            visible: root.holdPositive
                            text: i18n("hold") + " " + root.displayHold + root.displaySymbol
                            color: brand.muted
                            font.pixelSize: 9
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Rectangle {
                        width: 22; height: 22
                        radius: 6
                        color: closeMa.containsMouse ? brand.raised : "transparent"
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent
                            text: "\u2715"
                            color: closeMa.containsMouse ? brand.text : brand.subtext
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: transferDialog.visible = false
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: brand.border }

                // ── Amount ──────────────────────────────────────
                Text {
                    text: i18n("Amount")
                    color: brand.subtext
                    font.pixelSize: 11
                    Layout.leftMargin: 2
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 42
                    color: brand.surface
                    radius: 8
                    border.width: 1
                    border.color: amountField.activeFocus ? brand.green : brand.border

                    QQC2.TextField {
                        id: amountField
                        anchors.fill: parent
                        leftPadding: 14
                        rightPadding: 38        // room for the currency symbol
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
                        color: brand.text
                        font.bold: true
                        font.pixelSize: 16
                        background: Item {}
                        placeholderTextColor: brand.muted
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.currencySymbols[root.transferTargetCurrency] || root.transferTargetCurrency
                        color: brand.green
                        font.bold: true
                        font.pixelSize: 16
                    }
                }

                // ── Quick amounts + currency pill ───────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "10%", frac: 0.10 },
                            { label: "50%", frac: 0.50 },
                            { label: "Max", frac: 1.00 }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: chipText.implicitWidth + 22
                            height: 26
                            radius: 13
                            color: chipMa.containsMouse ? brand.raised : brand.surface
                            border.color: brand.border
                            border.width: 1

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: brand.subtext
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setAmountFraction(modelData.frac)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 116
                        height: 26
                        radius: 13
                        color: brand.surface
                        border.color: brand.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 3

                            Repeater {
                                model: [ "RUB", "USD" ]

                                delegate: Rectangle {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 10
                                    color: root.transferTargetCurrency === modelData ? brand.green : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.currencySymbols[modelData] || modelData
                                        color: root.transferTargetCurrency === modelData ? "#ffffff" : brand.subtext
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchTransferCurrency(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Recipient: ID/Username pill + field ─────────
                Text {
                    text: i18n("Recipient")
                    color: brand.subtext
                    font.pixelSize: 11
                    Layout.leftMargin: 2
                    Layout.topMargin: 2
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 150
                        height: 34
                        radius: 8
                        color: brand.surface
                        border.color: brand.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 3

                            Repeater {
                                model: [
                                    { t: "By ID",  isId: true  },
                                    { t: "Username", isId: false }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 6
                                    color: root.transferUseId === modelData.isId ? brand.green : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.t
                                        color: root.transferUseId === modelData.isId ? "#ffffff" : brand.subtext
                                        font.bold: true
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.transferUseId = modelData.isId
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        color: brand.surface
                        radius: 8
                        border.width: 1
                        border.color: userField.activeFocus ? brand.green : brand.border

                        QQC2.TextField {
                            id: userField
                            anchors.fill: parent
                            leftPadding: 12
                            rightPadding: 12
                            topPadding: 0
                            bottomPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: root.transferUseId ? "123456" : "@username"
                            onTextChanged: {
                                if (root.transferUseId) root.transferUserId   = text
                                else                    root.transferUsername = text
                            }
                            color: brand.text
                            font.pixelSize: 12
                            background: Item {}
                            placeholderTextColor: brand.muted
                        }
                    }
                }

                // ── Comment ─────────────────────────────────────
                Text {
                    text: i18n("Comment")
                    color: brand.subtext
                    font.pixelSize: 11
                    Layout.leftMargin: 2
                    Layout.topMargin: 2
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    color: brand.surface
                    radius: 8
                    border.width: 1
                    border.color: commentField.activeFocus ? brand.green : brand.border

                    QQC2.TextField {
                        id: commentField
                        anchors.fill: parent
                        leftPadding: 12
                        rightPadding: 12
                        topPadding: 0
                        bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: i18n("Optional")
                        maximumLength: 255
                        onTextChanged: root.transferComment = text
                        color: brand.text
                        font.pixelSize: 12
                        background: Item {}
                        placeholderTextColor: brand.muted
                    }
                }

                // ── Status ──────────────────────────────────────
                // Fixed-height slot so an error never resizes the dialog or
                // pushes the Transfer button off the bottom; the text elides.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18

                    Text {
                        anchors.fill: parent
                        text: root.transferStatus
                        color: root.transferSuccess ? brand.green : "#e0a0a0"
                        font.pixelSize: 11
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                // ── Primary action ──────────────────────────────
                Rectangle {
                    id: sendBtn
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    height: 40
                    radius: 8
                    readonly property bool ready: !root.pendingTransfer
                        && amountField.text.length > 0 && userField.text.length > 0
                    color: !ready ? brand.surface
                                  : (sendMa.containsMouse ? "#25c07d" : brand.green)
                    border.width: 1
                    border.color: root.pendingTransfer ? brand.green : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: root.pendingTransfer ? i18n("Sending…") : i18n("Transfer")
                        color: sendBtn.ready ? "#ffffff" : brand.muted
                        font.bold: true
                        font.pixelSize: 13
                        font.letterSpacing: 0.3
                    }

                    MouseArea {
                        id: sendMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: sendBtn.ready
                        cursorShape: sendBtn.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
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
        // flight, and stay quiet while a backoff retry is scheduled so the
        // periodic timer can't defeat the backoff by firing every N seconds.
        running:  !root.pendingFetch && !root.retryScheduled
                  && (root.apiKey.length > 0 || root.canFetchCryptoWithoutToken)
        repeat:   true
        onTriggered: root.fetchAll()
    }

    // Backoff retry timer. Armed by noteFailure() with an exponentially growing
    // interval (or the server's Retry-After), disarmed by resetRetry() on the
    // first success. Because refreshTimer pauses while retryScheduled is true,
    // the longest of the two schedules wins — so a rate-limited API is never
    // hammered.
    Timer {
        id: recoveryTimer
        interval: root.retryDelayMs > 0 ? root.retryDelayMs : 1000
        repeat: true
        running: root.retryScheduled && !root.pendingFetch
        onTriggered: {
            console.log("[lzt] retry #" + root.failureStreak
                        + " after " + root.retryDelayMs + "ms")
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
            // Treat a wedged request like any other failure so we back off
            // instead of leaning on refreshTimer to fire again immediately.
            root.noteFailure(0, 0)
        }
    }

    Component.onCompleted: {
        // Migrate any legacy plain-text token to the obfuscated form on disk.
        var stored = Plasmoid.configuration.apiKey || ""
        if (Secret.isPlain(stored)) {
            console.log("[lzt] migrating plain token to obfuscated form")
            Plasmoid.configuration.apiKey = Secret.encode(stored)
        }
        var storedCg = Plasmoid.configuration.coingeckoApiKey || ""
        if (Secret.isPlain(storedCg)) {
            console.log("[lzt] migrating plain CoinGecko key to obfuscated form")
            Plasmoid.configuration.coingeckoApiKey = Secret.encode(storedCg)
        }

        // Only api.lzt.market serves the /me and /currency endpoints we need;
        // move any stored value (prod-api, lolz.team, zelenka.guru) to it.
        var storedServer = Plasmoid.configuration.apiServer || ""
        if (storedServer !== "https://api.lzt.market") {
            console.log("[lzt] migrating API server to https://api.lzt.market")
            Plasmoid.configuration.apiServer = "https://api.lzt.market"
        }

        console.log("[lzt] init — stored.len=" + stored.length
                  + " decoded.len=" + apiKey.length
                  + " crypto.provider=" + cryptoProvider
                  + " cg.key=" + (coingeckoApiKey.length > 0)
                  + " stored.prefix=" + (stored.length > 0 ? stored.substring(0, 4) : "<empty>"))

        // Drive the update checker from metadata (single source of truth).
        try {
            if (Plasmoid.metaData) {
                if (Plasmoid.metaData.version) updateChecker.currentVersion = Plasmoid.metaData.version
                var u = Plasmoid.metaData.value("X-LZT-UpdateChecker-Url", "")
                if (u && u.length) updateChecker.url = u
            }
        } catch (e) {}
        updateChecker.check(false)
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
        function onCoingeckoApiKeyChanged(){ root.resetRetry(); root.forceRefresh() }
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

    // Transferable balance in the given currency (RUB balance converted by the
    // live rate). Returns 0 when the balance or rate is unknown.
    function transferAvailable(currency) {
        var rub = parseFloat(rawBalance)
        if (isNaN(rub) || rub <= 0) return 0
        if (currency === "RUB") return rub
        var rate = currencyRates[currency]
        if (!rate || rate <= 0) return 0
        return rub / rate
    }

    // Quick-amount chip: fill the field with `frac` of the transferable balance.
    function setAmountFraction(frac) {
        var max = transferAvailable(transferTargetCurrency)
        if (max <= 0) return
        var v = String(Math.floor(max * frac * 100) / 100)
        amountField.text = v
        transferAmount = v
    }

    // Switch the transfer currency while preserving the VALUE already typed:
    // 100 ₽ -> "$1.19" -> back to "100 ₽". Skipped when rates are unknown.
    function switchTransferCurrency(to) {
        if (to === transferTargetCurrency) return
        var amount = parseFloat(amountField.text)
        if (!isNaN(amount) && amount > 0) {
            var fromRate = (transferTargetCurrency === "RUB") ? 1 : currencyRates[transferTargetCurrency]
            var toRate   = (to === "RUB") ? 1 : currencyRates[to]
            if (fromRate > 0 && toRate > 0) {
                var v = String(Math.floor(amount * fromRate / toRate * 100) / 100)
                amountField.text = v
                transferAmount = v
            }
        }
        transferTargetCurrency = to
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

    // Begin a new fetch cycle: bump the generation, abort whatever the previous
    // cycle left in flight, and arm the watchdog. Returns the generation stamp
    // that every callback in this cycle must compare against.
    function startFetch() {
        fetchGeneration++
        for (var i = 0; i < activeXhrs.length; i++) {
            try { activeXhrs[i].abort() } catch (e) {}
        }
        activeXhrs = []
        fetchCycle = { closed: false }
        pendingFetch = true
        fetchWatchdog.restart()
        return fetchGeneration
    }

    // Register an extra request belonging to the current cycle so endFetch can
    // abort it if the cycle is superseded before it finishes.
    function trackRequest(xhr) {
        activeXhrs.push(xhr)
    }

    // Single point that clears the in-flight flag, stops the watchdog, and
    // aborts every request of the cycle. Every code path that finishes a fetch
    // must call this so pendingFetch can never get permanently stuck.
    function endFetch() {
        // Mark the cycle closed BEFORE aborting, so any readystatechange that
        // abort() fires synchronously is already silenced by the guard in
        // fireGet()/the cycle check below.
        if (fetchCycle) fetchCycle.closed = true
        var xs = activeXhrs
        activeXhrs = []
        for (var i = 0; i < xs.length; i++) {
            try { xs[i].abort() } catch (e) {}
        }
        pendingFetch = false
        fetchWatchdog.stop()
    }

    function isCurrentRequest(gen) {
        return gen === fetchGeneration
    }

    // Fire one GET in the current cycle. `headers` is an optional map of extra
    // request headers. onDone(status, text, xhr) is called at most once, and
    // never once the cycle it belongs to has ended (generation changed OR the
    // cycle token was closed by endFetch). A throwing handler is caught and
    // treated as a failed cycle so pendingFetch can't stay stuck.
    function fireGet(gen, url, headers, onDone) {
        var cycle = fetchCycle
        var xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        trackRequest(xhr)
        function deliver(status, text) {
            if (!isCurrentRequest(gen) || (cycle && cycle.closed)) return
            try {
                onDone(status, text, xhr)
            } catch (e) {
                console.log("[lzt] request handler threw: " + e)
                endFetch()
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            deliver(xhr.status, xhr.responseText)
        }
        xhr.ontimeout = function() { deliver(0, "") }
        try {
            xhr.open("GET", url)
            xhr.setRequestHeader("Accept", "application/json")
            if (headers)
                for (var h in headers)
                    if (headers.hasOwnProperty(h) && headers[h]) xhr.setRequestHeader(h, headers[h])
            xhr.send()
        } catch (e) {
            console.log("[lzt] GET send threw: " + e)
            deliver(-1, "")
        }
    }

    // Read the server-requested cooldown from a Retry-After header (seconds).
    // Returns 0 when absent/unparseable. Qt exposes response headers even for
    // non-2xx replies, which is exactly what we need for 429/503.
    function retryAfterSeconds(xhr) {
        try {
            var v = xhr.getResponseHeader("Retry-After")
            if (v) {
                var n = parseInt(v, 10)
                if (!isNaN(n) && n > 0) return n
            }
        } catch (e) {}
        return 0
    }

    // A fetch attempt failed. Arm a single backoff retry: exponential from
    // retryBaseMs (3s, 6s, 12s, …) capped at maxRetryDelayMs (5 min), with
    // ±20% jitter, unless the server sent Retry-After — then respect that.
    // 401/403 with no Retry-After still backs off, but a bad token (401) is
    // permanent, so we don't schedule a retry at all in that case.
    function noteFailure(status, retryAfterSec) {
        // A bad token will never fix itself by retrying — wait for the user.
        if (status === 401) {
            resetRetry()
            return
        }

        failureStreak++

        var delay = 0
        if (retryAfterSec && retryAfterSec > 0)
            delay = retryAfterSec * 1000
        else {
            var exp = Math.min(failureStreak - 1, 10)
            delay = retryBaseMs * Math.pow(2, exp)
        }
        delay = Math.min(delay, maxRetryDelayMs)

        // ±20% jitter so many clients don't retry in lockstep.
        var jitter = Math.round(delay * 0.2)
        delay = delay - jitter + Math.round(Math.random() * jitter * 2)
        delay = Math.max(1000, delay)

        retryDelayMs = delay
        retryScheduled = true
        console.log("[lzt] fetch failed (" + status + "), retry #"
                    + failureStreak + " in " + retryDelayMs + "ms"
                    + (retryAfterSec > 0 ? " (Retry-After " + retryAfterSec + "s)" : ""))
    }

    // A fetch succeeded — clear the backoff so the normal refresh cadence and
    // the retry timer both stand down.
    function resetRetry() {
        failureStreak = 0
        retryScheduled = false
        retryDelayMs    = 0
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
                var gen0 = startFetch()
                hasError = false
                statusText = ""
                fetchCryptoRates(gen0)
            } else {
                statusText = "No API Key"
                hasError = true
            }
            return
        }
        doFetchLzt()
    }

    // LZT: two independent GETs in parallel instead of one /batch POST.
    // /batch costs three upstream calls (1 POST + the 2 GETs it fans out to)
    // and the POST is limited to 30/min, so hitting /me and /currency directly
    // is cheaper, simpler and rate-limits far less.
    function doFetchLzt() {
        if (pendingFetch) return
        var gen = startFetch()
        var server = primaryServer
        var remaining = 2
        var gotCurrency = false
        var gotUser = false
        var lastStatus = 0
        var lastXhr = null

        function settle() {
            if (remaining > 0) return
            if (gotCurrency || gotUser) {
                resetRetry()
                fetchCryptoRates(gen)
            } else {
                if (!hasFetchedOnce) {
                    if      (lastStatus === 429) statusText = "Rate Limit"
                    else if (lastStatus <= 0)    statusText = "Offline"
                    else                         statusText = "Err " + lastStatus
                    hasError = true
                }
                noteFailure(lastStatus <= 0 ? 0 : lastStatus,
                            lastXhr ? retryAfterSeconds(lastXhr) : 0)
                endFetch()
            }
        }
        function badToken() {
            if (!hasFetchedOnce) { statusText = "Bad Token"; hasError = true }
            resetRetry(); endFetch()
        }
        function onCurrency(status, text, xhr) {
            if (status === 401) { badToken(); return }
            lastStatus = status; lastXhr = xhr
            if (status === 200 && parseLztCurrency(text)) gotCurrency = true
            remaining--; settle()
        }
        function onUser(status, text, xhr) {
            if (status === 401) { badToken(); return }
            lastStatus = status; lastXhr = xhr
            if (status === 200 && parseLztUser(text)) gotUser = true
            remaining--; settle()
        }

        fireGet(gen, server + "/currency", authHeaders(), onCurrency)
        fireGet(gen, server + "/me",       authHeaders(), onUser)
    }

    function authHeaders() {
        return { "Authorization": "Bearer " + apiKey }
    }

    function isEmptyObj(o) {
        for (var k in o) if (o.hasOwnProperty(k)) return false
        return true
    }

    function parseLztCurrency(raw) {
        try {
            var list = JSON.parse(raw).currencyList
            if (!list) return false
            var rates = {}
            for (var key in list)
                if (list.hasOwnProperty(key) && list[key].rate > 0) rates[key] = list[key].rate
            currencyRates = rates
            recalcDisplay()
            return true
        } catch (e) {
            console.log("[lzt] currency parse failed: " + e)
            return false
        }
    }

    function parseLztUser(raw) {
        try {
            var u = JSON.parse(raw).user
            if (!u) return false
            var newBalStr = (u.balance !== undefined && u.balance !== null) ? String(u.balance) : "0.00"

            // Detect balance change and fire a desktop notification. Skip the
            // very first fetch — we don't want a popup showing the entire
            // initial balance on widget load / Plasma restart.
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
            recalcDisplay()
            return true
        } catch (e) {
            console.log("[lzt] user parse failed: " + e)
            return false
        }
    }

    // A crypto-provider request failed. Surface a status only before the first
    // successful load; always arm the shared backoff.
    function cryptoFailed(status, tag, xhr) {
        if (!hasFetchedOnce && !hasCryptoFetchedOnce) {
            statusText = (status <= 0) ? "Offline" : (tag + " Err " + status)
            hasError = true
        }
        noteFailure(status <= 0 ? 0 : status, xhr ? retryAfterSeconds(xhr) : 0)
    }

    // Dispatch to the selected provider. "lzt" needs nothing extra: its crypto
    // rates already arrived with /currency.
    function fetchCryptoRates(gen) {
        var entries = visibleCryptoEntries
        if (entries.length === 0) { endFetch(); return }
        if      (cryptoProvider === "coingecko") fetchCoinGeckoRates(gen, entries)
        else if (cryptoProvider === "binance")   fetchUsdProvider(gen, entries, "binance")
        else if (cryptoProvider === "kraken")    fetchUsdProvider(gen, entries, "kraken")
        else if (cryptoProvider === "coinbase")  fetchCoinbaseRates(gen, entries)
        else                                     endFetch()
    }

    // Fiat anchors (RUB/EUR/UAH per unit) — LZT's own rates win, else the
    // free keyless open.er-api snapshot.
    function resolveFiat(erFiat) {
        var out = {}
        var keys = ["USD", "EUR", "UAH"]
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            if (currencyRates[k] > 0)            out[k] = currencyRates[k]
            else if (erFiat && erFiat[k] > 0)    out[k] = erFiat[k]
        }
        return out
    }

    // Merge USD-priced coins into currencyRates (RUB-per-unit), the same shape
    // the panel already consumes.
    function applyUsdPrices(usdPerCoin, erFiat) {
        var fiat = resolveFiat(erFiat)
        var rubPerUsd = fiat["USD"]
        if (!rubPerUsd || rubPerUsd <= 0) {
            console.log("[lzt] no fiat anchor available for " + cryptoProvider)
            cryptoFailed(0, cryptoProvider)
            return
        }
        var merged = {}
        for (var k in currencyRates)
            if (currencyRates.hasOwnProperty(k)) merged[k] = currencyRates[k]

        var touched = false
        for (var i = 0; i < visibleCryptoEntries.length; i++) {
            var code = visibleCryptoEntries[i].code
            var usd = usdPerCoin[code]
            if (usd > 0) { merged[code] = usd * rubPerUsd; touched = true }
        }
        if (fiat["EUR"] > 0) merged["EUR"] = fiat["EUR"]
        if (fiat["UAH"] > 0) merged["UAH"] = fiat["UAH"]
        merged["USD"] = rubPerUsd

        if (!touched && !hasCryptoFetchedOnce) { cryptoFailed(0, cryptoProvider); return }

        currencyRates = merged
        var first = !hasCryptoFetchedOnce
        hasCryptoFetchedOnce = true
        resetRetry()
        if (first) console.log("[lzt] " + cryptoProvider + " ok — crypto rates loaded")
        if (apiKey.length === 0) { hasError = false; statusText = "" }
        recalcDisplay()
    }

    // Binance / Kraken: USD/USDT tickers. Binance has no usable RUB pair any
    // more, so both go through the fiat anchor lane.
    function fetchUsdProvider(gen, entries, provider) {
        var map = (provider === "binance") ? Rates.BINANCE_PAIRS : Rates.KRAKEN_PAIRS
        var syms = Rates.providerSymbolsForEntries(map, entries)
        if (syms.length === 0) { endFetch(); return }

        var needAnchor = !(currencyRates["USD"] > 0)
        var pending = needAnchor ? 2 : 1
        var prices = null
        var erFiat = null
        var finished = false

        function fail(status, xhr) {
            if (finished) return
            finished = true
            cryptoFailed(status, provider, xhr)
            endFetch()
        }
        function done() {
            if (finished) return
            if (--pending > 0) return
            finished = true
            if (!prices || isEmptyObj(prices)) { cryptoFailed(0, provider); endFetch(); return }
            applyUsdPrices(prices, erFiat)
            endFetch()
        }

        var tickerUrl
        if (provider === "binance")
            tickerUrl = "https://api.binance.com/api/v3/ticker/price?symbols="
                      + encodeURIComponent(JSON.stringify(syms))
        else
            tickerUrl = "https://api.kraken.com/0/public/Ticker?pair=" + syms.join(",")

        fireGet(gen, tickerUrl, null, function(status, text, xhr) {
            if (status === 200) {
                try {
                    prices = (provider === "binance") ? Rates.parseBinancePrices(text)
                                                      : Rates.parseKrakenPrices(text)
                } catch (e) { prices = null }
            }
            if (!prices || isEmptyObj(prices)) { fail(status, xhr); return }
            done()
        })

        if (needAnchor) {
            fireGet(gen, "https://open.er-api.com/v6/latest/USD", null, function(status, text) {
                if (status === 200) {
                    try { erFiat = Rates.parseErApiFiat(text) } catch (e) { erFiat = null }
                }
                done()
            })
        }
    }

    // Coinbase: a single request gives both the coin prices and the fiat
    // anchors (native RUB/EUR/UAH), so it never needs the er-api fallback.
    function fetchCoinbaseRates(gen, entries) {
        fireGet(gen, "https://api.coinbase.com/v2/exchange-rates?currency=USD",
                null, function(status, text, xhr) {
            if (status !== 200) { cryptoFailed(status, "CB", xhr); endFetch(); return }
            var data = null
            try { data = Rates.parseCoinbaseRates(text) } catch (e) { data = null }
            if (!data || isEmptyObj(data.coins)) { cryptoFailed(0, "CB"); endFetch(); return }

            var erFiat = null
            if (data.fiat && data.fiat.RUB > 0) {
                erFiat = { "USD": data.fiat.RUB }
                if (data.fiat.EUR > 0) erFiat["EUR"] = data.fiat.RUB / data.fiat.EUR
                if (data.fiat.UAH > 0) erFiat["UAH"] = data.fiat.RUB / data.fiat.UAH
            }
            applyUsdPrices(data.coins, erFiat)
            endFetch()
        })
    }

    function fetchCoinGeckoRates(gen, entries) {
        var ids = Rates.coingeckoIdsForEntries(entries, displayCurrency !== "RUB")
        var quotes = Rates.coingeckoQuotesForEntries(entries, displayCurrency)
        if (ids.length === 0) { endFetch(); return }

        var url = "https://api.coingecko.com/api/v3/simple/price"
            + "?ids=" + encodeURIComponent(ids.join(","))
            + "&vs_currencies=" + encodeURIComponent(quotes.join(","))
            + "&include_last_updated_at=true"

        var headers = coingeckoApiKey.length > 0 ? { "x-cg-demo-api-key": coingeckoApiKey } : null
        fireGet(gen, url, headers, function(status, text, xhr) {
            if (status === 200) {
                try {
                    parseCoinGeckoResponse(text, entries, quotes)
                } catch (e) {
                    console.log("[lzt] coingecko parse failed: " + e)
                    cryptoFailed(0, "CG", xhr)
                }
            } else {
                console.log("[lzt] coingecko failed: " + status)
                cryptoFailed(status, "CG", xhr)
            }
            endFetch()
        })
    }

    function parseCoinGeckoResponse(raw, entries, quotes) {
        try {
            var data = JSON.parse(raw)
            var merged = {}
            for (var k in currencyRates)
                if (currencyRates.hasOwnProperty(k)) merged[k] = currencyRates[k]

            var touched = false
            for (var i = 0; i < entries.length; i++) {
                var code = entries[i].code
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
            var firstCrypto = !hasCryptoFetchedOnce
            hasCryptoFetchedOnce = true
            resetRetry()
            if (firstCrypto) console.log("[lzt] coingecko ok — crypto rates loaded")
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
            noteFailure(0, 0)
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
        // Cooldown: a flapping balance (e.g. hold/balance jitter from the API)
        // must not spam desktop notifications. At most one per interval.
        var now = Date.now()
        if (now - lastBalanceNotifyMs < balanceNotifyCooldownMs) return
        lastBalanceNotifyMs = now

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

        try {
            xhr.open("POST", server + "/balance/transfer")
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.setRequestHeader("Accept",       "application/json")
            xhr.setRequestHeader("Authorization","Bearer " + apiKey)
            xhr.send(JSON.stringify(body))
        } catch (e) {
            // Never leave the form stuck in "Sending…" if the request can't
            // even be constructed (bad URL, serialization error, …).
            console.log("[lzt] transfer send threw: " + e)
            transferStatus = "Failed"; transferSuccess = false; pendingTransfer = false
        }
    }
}
