import QtQuick
import QtQuick.Controls

Item {
    id: overlay
    anchors.fill: parent

    property string projectionMode: "mercator"
    property bool pickModeEnabled: false

    signal projectionSelected(string mode)
    signal zoomInRequested()
    signal zoomOutRequested()

    // Floating Projection Switcher in Main Block (Top-Right)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        height: 40
        radius: 8
        color: "#1a1b1e"
        border.color: "#373a40"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 4
            padding: 4

            Button {
                id: osmBtn
                height: 32
                text: "🗺️ Street View (OSM)"
                background: Rectangle {
                    radius: 6
                    color: overlay.projectionMode === "mercator" ? "#228be6" : "transparent"
                }
                contentItem: Text {
                    text: osmBtn.text
                    color: overlay.projectionMode === "mercator" ? "#ffffff" : "#adb5bd"
                    font.bold: overlay.projectionMode === "mercator"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: overlay.projectionSelected("mercator")
            }

            Button {
                id: equiBtn
                height: 32
                text: "🛰️ Orbital View (Equirectangular)"
                background: Rectangle {
                    radius: 6
                    color: overlay.projectionMode === "equirectangular" ? "#228be6" : "transparent"
                }
                contentItem: Text {
                    text: equiBtn.text
                    color: overlay.projectionMode === "equirectangular" ? "#ffffff" : "#adb5bd"
                    font.bold: overlay.projectionMode === "equirectangular"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: overlay.projectionSelected("equirectangular")
            }
        }
    }

    // Pick Mode Banner
    Rectangle {
        visible: overlay.pickModeEnabled
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        radius: 20
        color: "#1c7ed6"
        implicitWidth: bannerRow.implicitWidth + 30
        implicitHeight: 38

        Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: "📍 Click anywhere on the map to place station"
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Floating Zoom Buttons
    Column {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Button {
            text: "+"
            width: 38
            height: 38
            onClicked: overlay.zoomInRequested()
        }

        Button {
            text: "−"
            width: 38
            height: 38
            onClicked: overlay.zoomOutRequested()
        }
    }
}
