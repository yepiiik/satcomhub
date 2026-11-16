import QtQuick
import QtLocation
import QtPositioning

MapQuickItem {
    id: satMarker

    property string satId: (typeof model !== "undefined" && model.satId !== undefined) ? model.satId : ""
    property string satName: (typeof model !== "undefined" && model.name !== undefined) ? model.name : ""
    property real satLatitude: (typeof model !== "undefined" && model.latitude !== undefined) ? model.latitude : 0.0
    property real satLongitude: (typeof model !== "undefined" && model.longitude !== undefined) ? model.longitude : 0.0
    property bool isSelected: false

    signal clicked(string id, string name)

    coordinate: QtPositioning.coordinate(satLatitude, satLongitude)
    anchorPoint.x: 16
    anchorPoint.y: 16
    z: 25

    sourceItem: Item {
        width: 32
        height: 32

        Rectangle {
            anchors.centerIn: parent
            width: satMarker.isSelected ? 30 : 24
            height: width
            radius: width / 2
            color: "#f59f00"
            border.color: "#ffffff"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "🛰️"
                font.pixelSize: 13
            }
        }

        Rectangle {
            anchors.bottom: parent.top
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: satBadgeText.implicitWidth + 10
            implicitHeight: 20
            radius: 4
            color: "#1a1b1e"
            border.color: "#f59f00"
            border.width: 1

            Text {
                id: satBadgeText
                anchors.centerIn: parent
                text: satMarker.satName
                color: "#ffffff"
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: satMarker.clicked(satMarker.satId, satMarker.satName)
        }
    }
}
