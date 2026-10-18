import QtQuick
import QtQuick.Effects

Column {
    id: hc
    required property var info
    required property var wd
    property real colW: 40
    width: colW
    spacing: 3 * hc.wd.s
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: hc.info.h
        color: Qt.rgba(1, 1, 1, 0.85)
        font.family: hc.wd.fam
        font.pixelSize: 12 * hc.wd.s
        font.weight: Font.DemiBold
    }
    Item {
        width: parent.width
        height: 20 * hc.wd.s
        WeatherIcon {
            visible: hc.wd.showIcon(hc.info.k)
            anchors.centerIn: parent
            kind: hc.info.k
            size: 18 * hc.wd.s
        }
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: hc.info.t + hc.wd.unitSuffix
        color: "white"
        font.family: hc.wd.fam
        font.pixelSize: 15 * hc.wd.s
        font.weight: Font.DemiBold
    }
}
