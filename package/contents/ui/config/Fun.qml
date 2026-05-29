import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: page
    Layout.fillWidth: true
    Layout.fillHeight: true

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Kirigami.Units.largeSpacing

        Image {
            source: Qt.resolvedUrl("../images/tyanka.png")
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 300
            Layout.alignment: Qt.AlignHCenter
            smooth: true
            mipmap: true
        }

        Text {
            text: "^.^"
            color: "#2BAD72"
            font.bold: true
            font.pixelSize: 30
            font.letterSpacing: 2
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
