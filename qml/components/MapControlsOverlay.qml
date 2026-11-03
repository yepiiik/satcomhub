import QtQuick
import QtQuick.Controls

Item {
    id: overlay
    anchors.fill: parent

    property string projectionMode: "mercator"
    property bool pickModeEnabled: false
    property bool lightMode: false

    signal projectionSelected(string mode)
    signal zoomInRequested()
    signal zoomOutRequested()
    signal recenterRequested()

    // ================= ALL-IN-ONE MISSION HUD (TOP-CENTER) =================
    Rectangle {
        id: missionHudPill
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        height: 40
        implicitWidth: hudRow.implicitWidth + 14
        radius: 8
        color: overlay.lightMode ? "#f8f9fa" : "#141720"
        border.color: overlay.lightMode ? "#dee2e6" : "#2d3345"
        border.width: 1

        Row {
            id: hudRow
            anchors.centerIn: parent
            spacing: 8
            padding: 4

            // --- STATIC SEGMENTED VIEW MODE CONTAINER (EQUAL 50/50 SPLIT) ---
            Rectangle {
                id: modeSegmentTrack
                width: 236
                height: 32
                radius: 6
                color: overlay.lightMode ? "#e9ecef" : "#1a1e29"
                border.color: overlay.lightMode ? "#dee2e6" : "#2d3345"
                border.width: 1

                Row {
                    anchors.fill: parent
                    spacing: 0

                    // 1. Street View (Left 50%)
                    Rectangle {
                        width: parent.width / 2
                        height: parent.height
                        radius: 5
                        color: overlay.projectionMode === "mercator"
                               ? "#228be6"
                               : (osmMouse.containsMouse ? (overlay.lightMode ? "#dee2e6" : "#252b3b") : "transparent")

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "🗺️"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: qsTr("Street View")
                                font.bold: overlay.projectionMode === "mercator"
                                font.pixelSize: 12
                                color: overlay.projectionMode === "mercator"
                                       ? "#ffffff"
                                       : (overlay.lightMode ? "#495057" : "#adb5bd")
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ToolTip.visible: osmMouse.containsMouse
                        ToolTip.text: qsTr("OpenStreetMap Mercator view for local ground station siting & azimuth orientation")

                        MouseArea {
                            id: osmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.projectionSelected("mercator")
                        }
                    }

                    // 2. Orbital View (Right 50%)
                    Rectangle {
                        width: parent.width / 2
                        height: parent.height
                        radius: 5
                        color: overlay.projectionMode === "equirectangular"
                               ? "#228be6"
                               : (equiMouse.containsMouse ? (overlay.lightMode ? "#dee2e6" : "#252b3b") : "transparent")

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "🛰️"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                text: qsTr("Orbital View")
                                font.bold: overlay.projectionMode === "equirectangular"
                                font.pixelSize: 12
                                color: overlay.projectionMode === "equirectangular"
                                       ? "#ffffff"
                                       : (overlay.lightMode ? "#495057" : "#ced4da")
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ToolTip.visible: equiMouse.containsMouse
                        ToolTip.text: qsTr("Equirectangular 2D global view for SGP4 satellite orbits & visibility footprints")

                        MouseArea {
                            id: equiMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.projectionSelected("equirectangular")
                        }
                    }
                }
            }

            // --- VERTICAL DIVIDER ---
            Rectangle {
                width: 1
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                color: overlay.lightMode ? "#dee2e6" : "#2d3345"
            }

            // --- VIEWPORT NAVIGATION BUTTONS ---
            // Zoom In (+)
            Rectangle {
                width: 32
                height: 32
                radius: 6
                color: zoomInMouse.pressed
                       ? (overlay.lightMode ? "#dee2e6" : "#252b3b")
                       : (zoomInMouse.containsMouse ? (overlay.lightMode ? "#e9ecef" : "#1e2230") : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.bold: true
                    font.pixelSize: 16
                    color: overlay.lightMode ? "#343a40" : "#f1f3f5"
                }

                ToolTip.visible: zoomInMouse.containsMouse
                ToolTip.text: qsTr("Zoom In (+)")

                MouseArea {
                    id: zoomInMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.zoomInRequested()
                }
            }

            // Zoom Out (−)
            Rectangle {
                width: 32
                height: 32
                radius: 6
                color: zoomOutMouse.pressed
                       ? (overlay.lightMode ? "#dee2e6" : "#252b3b")
                       : (zoomOutMouse.containsMouse ? (overlay.lightMode ? "#e9ecef" : "#1e2230") : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: "−"
                    font.bold: true
                    font.pixelSize: 16
                    color: overlay.lightMode ? "#343a40" : "#f1f3f5"
                }

                ToolTip.visible: zoomOutMouse.containsMouse
                ToolTip.text: qsTr("Zoom Out (−)")

                MouseArea {
                    id: zoomOutMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.zoomOutRequested()
                }
            }

            // Recenter / Reset View (🎯)
            Rectangle {
                width: 32
                height: 32
                radius: 6
                color: recenterMouse.pressed
                       ? (overlay.lightMode ? "#dee2e6" : "#252b3b")
                       : (recenterMouse.containsMouse ? (overlay.lightMode ? "#e9ecef" : "#1e2230") : "transparent")

                Text {
                    anchors.centerIn: parent
                    text: "🎯"
                    font.pixelSize: 13
                }

                ToolTip.visible: recenterMouse.containsMouse
                ToolTip.text: qsTr("Recenter / Fit View")

                MouseArea {
                    id: recenterMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: overlay.recenterRequested()
                }
            }
        }
    }

    // ================= PICK MODE BANNER =================
    Rectangle {
        visible: overlay.pickModeEnabled
        anchors.top: missionHudPill.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 10
        radius: 20
        color: "#1c7ed6"
        implicitWidth: bannerRow.implicitWidth + 30
        implicitHeight: 36

        Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: "📍 Click anywhere on the map to place station"
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
