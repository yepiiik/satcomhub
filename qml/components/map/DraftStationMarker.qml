import QtQuick
import QtQuick.Shapes
import QtLocation
import QtPositioning

MapQuickItem {
    id: draftQuickItem

    property real draftLat: 0
    property real draftLon: 0
    property string draftName: "New Station (Unsaved)"

    coordinate: QtPositioning.coordinate(draftLat, draftLon)
    anchorPoint.x: 18
    anchorPoint.y: 40
    z: 30

    sourceItem: Item {
        width: 36
        height: 44

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeWidth: 2
                strokeColor: "#ffffff"
                fillColor: "#fa5252"
                joinStyle: ShapePath.RoundJoin

                startX: 18
                startY: 40

                PathCubic { control1X: 13; control1Y: 33; control2X: 4; control2Y: 22; x: 4; y: 16 }
                PathArc { x: 32; y: 16; radiusX: 14; radiusY: 14; useLargeArc: true }
                PathCubic { control1X: 32; control1Y: 22; control2X: 23; control2Y: 33; x: 18; y: 40 }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            width: 10
            height: 10
            radius: 5
            color: "#ffffff"
        }

        Rectangle {
            anchors.bottom: parent.top
            anchors.bottomMargin: 4
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: draftBadgeText.implicitWidth + 12
            implicitHeight: 22
            radius: 4
            color: "#1a1b1e"
            border.color: "#fa5252"
            border.width: 1

            Text {
                id: draftBadgeText
                anchors.centerIn: parent
                text: draftQuickItem.draftName
                color: "#ffffff"
                font.pixelSize: 11
                font.bold: true
            }
        }
    }
}
