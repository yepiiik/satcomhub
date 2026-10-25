import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: objectsSidebarRoot

    property var satellitesModel: null
    property var stationsModel: null
    property string selectedSatelliteId: ""
    property string selectedStationId: ""
    property real currentSatAltKm: 500.0
    property bool lightMode: false

    signal addSatelliteRequested()
    signal editSatelliteRequested(var satModelItem)
    signal deleteSatelliteRequested(string satId)
    signal satelliteSelected(string satId, real lat, real lon, real altKm, string name)
    signal calculateSatellitePassesRequested(string satId, string name)

    signal addStationRequested()
    signal editStationRequested(var stationModelItem)
    signal viewStationJsonRequested(var stationModelItem)
    signal deleteStationRequested(string stationId)
    signal stationSelected(string stationId, real lat, real lon)
    signal stationActiveToggled(string stationId, bool active)

    radius: 12
    clip: true
    color: "transparent"
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ================= TOP HEADER =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "🌐"
                font.pixelSize: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: qsTr("Objects & Infrastructure")
                    font.bold: true
                    font.pixelSize: 15
                    color: objectsSidebarRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                }

                Label {
                    text: (satellitesModel ? satellitesModel.count : 0) + " Satellites • " + 
                          (stationsModel ? stationsModel.count : 0) + " Ground Stations"
                    font.pixelSize: 11
                    color: objectsSidebarRoot.lightMode ? "#6c757d" : "#909296"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: objectsSidebarRoot.lightMode ? "#e9ecef" : "#222736"
        }

        // ================= SECTION 1: SATELLITES =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: qsTr("SATELLITES")
                font.bold: true
                font.pixelSize: 11
                color: objectsSidebarRoot.lightMode ? "#495057" : "#adb5bd"
                Layout.fillWidth: true
            }

            Rectangle {
                height: 18
                width: satCountText.implicitWidth + 10
                radius: 9
                color: "#f59f00"
                Text {
                    id: satCountText
                    anchors.centerIn: parent
                    text: String(satellitesModel ? satellitesModel.count : 0)
                    font.bold: true
                    font.pixelSize: 10
                    color: "#ffffff"
                }
            }

            Button {
                height: 24
                width: 24
                background: Rectangle {
                    radius: 4
                    color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#e9ecef" : "#2c3245") : "transparent"
                    border.color: objectsSidebarRoot.lightMode ? "#dee2e6" : "#3b4256"
                }
                contentItem: Text {
                    text: "+"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#f59f00"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add New Satellite (TLE)")
                onClicked: objectsSidebarRoot.addSatelliteRequested()
            }
        }

        ListView {
            id: satListView
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 180)
            Layout.maximumHeight: 220
            clip: true
            spacing: 6
            model: satellitesModel

            delegate: Rectangle {
                id: satCard
                width: satListView.width
                implicitHeight: satCardLayout.implicitHeight + 14
                radius: 8

                property bool isSelected: objectsSidebarRoot.selectedSatelliteId === model.satId

                color: isSelected ? 
                       (objectsSidebarRoot.lightMode ? "#fff9db" : "#2d2411") : 
                       (objectsSidebarRoot.lightMode ? "#f8f9fa" : "#1a1e29")
                border.color: isSelected ? "#f59f00" : (objectsSidebarRoot.lightMode ? "#dee2e6" : "#262b3a")
                border.width: isSelected ? 1.5 : 1

                // Active left accent bar
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 1
                    color: "#f59f00"
                    visible: satCard.isSelected
                }

                RowLayout {
                    id: satCardLayout
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    spacing: 8

                    Text {
                        text: "🛰️"
                        font.pixelSize: 16
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: model.name
                            font.bold: true
                            font.pixelSize: 12
                            color: satCard.isSelected ? "#f59f00" : (objectsSidebarRoot.lightMode ? "#212529" : "#f1f3f5")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            property string latDir: model.latitude >= 0 ? "°N" : "°S"
                            property string lonDir: model.longitude >= 0 ? "°E" : "°W"
                            text: Math.abs(model.latitude).toFixed(2) + latDir + ", " + Math.abs(model.longitude).toFixed(2) + lonDir + " • " + Math.round(model.altitudeKm) + " km"
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: satCard.isSelected ? "#f59f00" : (objectsSidebarRoot.lightMode ? "#1971c2" : "#74c0fc")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Pass Planning Button
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#d0ebff" : "#182842") : "transparent"
                        }
                        contentItem: Text {
                            text: "📅"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Calculate Future Passes in Planning Tab")
                        onClicked: objectsSidebarRoot.calculateSatellitePassesRequested(model.satId, model.name)
                    }

                    // Edit
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#dee2e6" : "#2d3345") : "transparent"
                        }
                        contentItem: Text {
                            text: "✏️"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Edit TLE")
                        onClicked: objectsSidebarRoot.editSatelliteRequested(model)
                    }

                    // Delete
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? "#ffe3e3" : "transparent"
                        }
                        contentItem: Text {
                            text: "✕"
                            font.bold: true
                            font.pixelSize: 12
                            color: parent.hovered ? "#fa5252" : (objectsSidebarRoot.lightMode ? "#adb5bd" : "#5c6375")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Remove Satellite")
                        onClicked: objectsSidebarRoot.deleteSatelliteRequested(model.satId)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: objectsSidebarRoot.satelliteSelected(model.satId, model.latitude, model.longitude, model.altitudeKm, model.name)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: objectsSidebarRoot.lightMode ? "#e9ecef" : "#222736"
        }

        // ================= SECTION 2: GROUND STATIONS =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: qsTr("GROUND STATIONS")
                font.bold: true
                font.pixelSize: 11
                color: objectsSidebarRoot.lightMode ? "#495057" : "#adb5bd"
                Layout.fillWidth: true
            }

            Rectangle {
                height: 18
                width: stCountText.implicitWidth + 10
                radius: 9
                color: "#228be6"
                Text {
                    id: stCountText
                    anchors.centerIn: parent
                    text: String(stationsModel ? stationsModel.count : 0)
                    font.bold: true
                    font.pixelSize: 10
                    color: "#ffffff"
                }
            }

            Button {
                height: 24
                width: 24
                background: Rectangle {
                    radius: 4
                    color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#e9ecef" : "#2c3245") : "transparent"
                    border.color: objectsSidebarRoot.lightMode ? "#dee2e6" : "#3b4256"
                }
                contentItem: Text {
                    text: "+"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#228be6"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add New Ground Station (F1)")
                onClicked: objectsSidebarRoot.addStationRequested()
            }
        }

        ListView {
            id: stListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: stationsModel

            delegate: Rectangle {
                id: stCard
                width: stListView.width
                implicitHeight: stCardLayout.implicitHeight + 14
                radius: 8

                property bool isSelected: objectsSidebarRoot.selectedStationId === model.stationId
                property bool isActive: model.active !== false

                color: isSelected ? 
                       (objectsSidebarRoot.lightMode ? "#e7f5ff" : "#12233b") : 
                       (objectsSidebarRoot.lightMode ? "#f8f9fa" : "#1a1e29")
                border.color: isSelected ? "#228be6" : (objectsSidebarRoot.lightMode ? "#dee2e6" : "#262b3a")
                border.width: isSelected ? 1.5 : 1

                // Active left accent bar
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3
                    radius: 1
                    color: "#228be6"
                    visible: stCard.isSelected
                }

                RowLayout {
                    id: stCardLayout
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    spacing: 8

                    // Active Toggle CheckBox (CoolerControl style)
                    CheckBox {
                        id: activeChk
                        checked: stCard.isActive
                        onToggled: objectsSidebarRoot.stationActiveToggled(model.stationId, checked)
                        ToolTip.visible: hovered
                        ToolTip.text: checked ? qsTr("Station Active in Passes & Diversity") : qsTr("Station Inactive")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            spacing: 6
                            Label {
                                text: model.name
                                font.bold: true
                                font.pixelSize: 12
                                color: stCard.isSelected ? "#228be6" : (objectsSidebarRoot.lightMode ? "#212529" : "#f1f3f5")
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                height: 16
                                width: bandText.implicitWidth + 8
                                radius: 4
                                color: objectsSidebarRoot.lightMode ? "#e9ecef" : "#282e3f"
                                Text {
                                    id: bandText
                                    anchors.centerIn: parent
                                    text: model.operatingBand || "C-band"
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#339af0"
                                }
                            }
                        }

                        Label {
                            property string latDir: model.latitude >= 0 ? "°N" : "°S"
                            property string lonDir: model.longitude >= 0 ? "°E" : "°W"
                            text: Math.abs(model.latitude).toFixed(2) + latDir + ", " + Math.abs(model.longitude).toFixed(2) + lonDir + 
                                  " • " + (model.minElevation !== undefined ? model.minElevation : 5) + "° Mask" +
                                  (model.gOverT ? " • G/T " + model.gOverT + " dB/K" : "")
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: objectsSidebarRoot.lightMode ? "#6c757d" : "#909296"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // View JSON
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#dee2e6" : "#2d3345") : "transparent"
                        }
                        contentItem: Text {
                            text: "{}"
                            font.bold: true
                            font.pixelSize: 11
                            color: objectsSidebarRoot.lightMode ? "#495057" : "#ced4da"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("View Station JSON (F2)")
                        onClicked: objectsSidebarRoot.viewStationJsonRequested(model)
                    }

                    // Edit
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? (objectsSidebarRoot.lightMode ? "#dee2e6" : "#2d3345") : "transparent"
                        }
                        contentItem: Text {
                            text: "✏️"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Edit Station Antenna Properties (F1)")
                        onClicked: objectsSidebarRoot.editStationRequested(model)
                    }

                    // Delete
                    Button {
                        width: 24
                        height: 24
                        background: Rectangle {
                            radius: 4
                            color: parent.hovered ? "#ffe3e3" : "transparent"
                        }
                        contentItem: Text {
                            text: "✕"
                            font.bold: true
                            font.pixelSize: 12
                            color: parent.hovered ? "#fa5252" : (objectsSidebarRoot.lightMode ? "#adb5bd" : "#5c6375")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Delete Station")
                        onClicked: objectsSidebarRoot.deleteStationRequested(model.stationId)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: objectsSidebarRoot.stationSelected(model.stationId, model.latitude, model.longitude)
                }
            }
        }
    }
}
