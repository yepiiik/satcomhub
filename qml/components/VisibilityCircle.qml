import QtQuick
import QtLocation

MapCircle {
    id: root

    property string stationId: ""
    property bool isSelected: false

    color: isSelected ? "#2a228be6" : "#14228be6"
    border.color: isSelected ? "#228be6" : "#74c0fc"
    border.width: isSelected ? 2 : 1
    opacity: 0.8
}
