import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "../secret.js" as Secret

KCM.SimpleKCM {
    id: configPage

    // cfg_apiKey stores the OBFUSCATED token; the visible field shows the raw
    // one. We decode on load and encode on edit so plain text never persists.
    property string cfg_apiKey: ""
    property string cfg_apiKeyDefault: ""
    property alias  cfg_updateInterval: intervalSpinBox.value
    property int    cfg_updateIntervalDefault: 30
    property alias  cfg_displayCurrency:currencyCombo.currentValue
    property string cfg_displayCurrencyDefault: "RUB"
    property alias  cfg_apiServer:      serverCombo.currentValue
    property string cfg_apiServerDefault: "https://prod-api.lzt.market"
    property alias  cfg_cryptoProvider: providerCombo.currentValue
    property string cfg_cryptoProviderDefault: "lzt"
    property string cfg_cryptoList: "[]"
    property string cfg_cryptoListDefault: "[]"
    // Optional CoinGecko Demo API key, stored obfuscated like the LZT token.
    property string cfg_coingeckoApiKey: ""
    property string cfg_coingeckoApiKeyDefault: ""
    function syncKeyField()   { apiKeyField.text   = Secret.decode(cfg_apiKey) }
    function syncCgKeyField() { cgApiKeyField.text = Secret.decode(cfg_coingeckoApiKey) }
    Component.onCompleted: { syncKeyField(); syncCgKeyField() }
    // Re-sync when the stored value arrives/changes, unless the user is typing.
    onCfg_apiKeyChanged: if (!apiKeyField.activeFocus) syncKeyField()
    onCfg_coingeckoApiKeyChanged: if (!cgApiKeyField.activeFocus) syncCgKeyField()

    Kirigami.FormLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.topMargin: Kirigami.Units.smallSpacing
        // Keep the form compact (and clear of the overlay scrollbar) instead of
        // stretching inputs across the whole dialog.
        width: Math.min(parent.width - Kirigami.Units.largeSpacing * 2,
                        Kirigami.Units.gridUnit * 26)

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Connection")
        }

    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        Kirigami.FormData.label: i18n("API Key:")
        QQC2.TextField {
            id: apiKeyField
            Layout.fillWidth: true
            placeholderText: "LZT Bearer token"
            echoMode: TextInput.Password
            onTextEdited: configPage.cfg_apiKey = Secret.encode(text)
        }
        QQC2.ToolButton {
            icon.name: apiKeyField.echoMode === TextInput.Password
                       ? "password-show-on" : "password-show-off"
            checkable: true
            QQC2.ToolTip.text: i18n("Show / hide")
            QQC2.ToolTip.visible: hovered
            onClicked: apiKeyField.echoMode = checked ? TextInput.Normal
                                                      : TextInput.Password
        }
    }

    QQC2.ComboBox {
        id: serverCombo
        Kirigami.FormData.label: i18n("API Server:")
        model: [
            { text: "Production (prod-api)", value: "https://prod-api.lzt.market" },
            { text: "Alternative (api)",     value: "https://api.lzt.market" }
        ]
        textRole: "text"
        valueRole: "value"
        Component.onCompleted: {
            for (var i = 0; i < model.length; i++) {
                if (model[i].value === cfg_apiServer) { currentIndex = i; return }
            }
            currentIndex = 0
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Display")
    }

    QQC2.SpinBox {
        id: intervalSpinBox
        Kirigami.FormData.label: i18n("Refresh interval (sec):")
        from: 10
        to: 3600
        value: 30
        stepSize: 5
    }

    QQC2.ComboBox {
        id: currencyCombo
        Kirigami.FormData.label: i18n("Display currency:")
        model: [
            { text: "RUB  ₽",  value: "RUB" },
            { text: "USD  $",  value: "USD" },
            { text: "EUR  €",  value: "EUR" },
            { text: "UAH  ₴",  value: "UAH" },
            { text: "BTC  ₿",  value: "BTC" }
        ]
        textRole: "text"
        valueRole: "value"
        Component.onCompleted: {
            for (var i = 0; i < model.length; i++) {
                if (model[i].value === cfg_displayCurrency) { currentIndex = i; return }
            }
            currentIndex = 0
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Crypto")
    }

    QQC2.ComboBox {
        id: providerCombo
        Kirigami.FormData.label: i18n("Crypto provider:")
        model: [
            { text: "LZT Market", value: "lzt" },
            { text: "CoinGecko",  value: "coingecko" }
        ]
        textRole: "text"
        valueRole: "value"
        Component.onCompleted: {
            for (var i = 0; i < model.length; i++) {
                if (model[i].value === cfg_cryptoProvider) { currentIndex = i; return }
            }
            currentIndex = 0
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        Kirigami.FormData.label: i18n("CoinGecko API key:")
        visible: providerCombo.currentValue === "coingecko"
        QQC2.TextField {
            id: cgApiKeyField
            Layout.fillWidth: true
            placeholderText: i18n("Free Demo key (optional)")
            echoMode: TextInput.Password
            onTextEdited: configPage.cfg_coingeckoApiKey = Secret.encode(text)
        }
        QQC2.ToolButton {
            icon.name: cgApiKeyField.echoMode === TextInput.Password
                       ? "password-show-on" : "password-show-off"
            checkable: true
            QQC2.ToolTip.text: i18n("Show / hide")
            QQC2.ToolTip.visible: hovered
            onClicked: cgApiKeyField.echoMode = checked ? TextInput.Normal
                                                        : TextInput.Password
        }
    }

    QQC2.Label {
        visible: providerCombo.currentValue === "coingecko"
        text: i18n("Keyless CoinGecko is rate-limited per IP. A free Demo key (coingecko.com) allows 100 calls/min.")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
}
