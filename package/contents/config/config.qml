import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("LZT")
        icon: "preferences-system"
        source: "config/LZT.qml"
    }
    ConfigCategory {
        name: i18n("CRYPTO")
        icon: "office-chart-line"
        source: "config/Crypto.qml"
    }
    ConfigCategory {
        name: "^.^"
        icon: "lzt-help"
        source: "config/Fun.qml"
    }
}
