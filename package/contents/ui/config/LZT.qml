import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: configPage
    wideMode: true

    property alias cfg_apiKey:         apiKeyField.text
    property alias cfg_updateInterval: intervalSpinBox.value
    property alias cfg_displayCurrency:currencyCombo.currentValue
    property alias cfg_apiServer:      serverCombo.currentValue

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Connection")
    }

    QQC2.TextField {
        id: apiKeyField
        Kirigami.FormData.label: i18n("API Key:")
        placeholderText: "LZT Bearer token"
        echoMode: TextInput.Password
        Layout.fillWidth: true
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
            { text: "GBP  £",  value: "GBP" },
            { text: "BYN  Br", value: "BYN" },
            { text: "KZT  ₸",  value: "KZT" },
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
}
