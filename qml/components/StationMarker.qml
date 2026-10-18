import QtQuick
import QtQuick.Shapes
import QtLocation
import QtPositioning

MapQuickItem {
    id: marker

    property string stationId: model.stationId !== undefined ? model.stationId : ""
    property string stationName: model.name !== undefined ? model.name : ""
    property bool isSelected: root.selectedStationId === stationId

    coordinate: QtPositioning.coordinate(model.latitude, model.longitude)

    anchorPoint.x: 18
    anchorPoint.y: 40
    z: isSelected ? 20 : 10

    sourceItem: Item {
        width: 36
        height: 44

        transform: Scale {
            origin.x: 18
            origin.y: 40
            xScale: marker.isSelected ? 1.3 : 1.0
            yScale: marker.isSelected ? 1.3 : 1.0

            Behavior on xScale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
            Behavior on yScale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        }

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeWidth: 2
                strokeColor: "#ffffff"
                fillColor: marker.isSelected ? "#fa5252" : "#228be6"
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
            visible: marker.isSelected
            implicitWidth: badgeText.implicitWidth + 12
            implicitHeight: 22
            radius: 4
            color: "#1a1b1e"
            border.color: "#373a40"
            border.width: 1

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: marker.stationName
                color: "#ffffff"
                font.pixelSize: 11
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
                root.markerSelected(marker.stationId, marker.stationName)
            }
        }
    }
}
