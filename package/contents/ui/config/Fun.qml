import QtQuick
import QtQuick.Layouts
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Plasma injects every config entry into each config page; declare the
    // ones we don't use so the runtime stops spamming "does not have a property".
    property string cfg_apiKey: ""
    property int    cfg_updateInterval: 30
    property string cfg_displayCurrency: "RUB"
    property string cfg_apiServer: "https://prod-api.lzt.market"
    property string cfg_cryptoProvider: "lzt"
    property string cfg_cryptoList: "[]"

    Image {
        anchors.centerIn: parent
        source: Qt.resolvedUrl("../images/tyanka.png")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 300
        smooth: true
        mipmap: true
    }
}
