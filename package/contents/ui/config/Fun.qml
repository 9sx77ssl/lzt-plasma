import QtQuick
import QtQuick.Layouts

Item {
    id: page
    Layout.fillWidth: true
    Layout.fillHeight: true

    Image {
        anchors.centerIn: parent
        source: Qt.resolvedUrl("../images/tyanka.png")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 300
        smooth: true
        mipmap: true
    }
}
