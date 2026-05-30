import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("LZT")
        icon: "lztbalance"
        source: "config/LZT.qml"
    }
    ConfigCategory {
        name: i18n("CRYPTO")
        icon: "lzt-crypto"
        source: "config/Crypto.qml"
    }
    ConfigCategory {
        name: "DEV"
        icon: "lzt-help"
        source: "config/Fun.qml"
    }
}
