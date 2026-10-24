import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: planningSidebarRoot

    property var satellitesModel: null
    property var stationsModel: null
    property string selectedSatelliteId: ""
    property var passResult: null
    property var selectedSession: null
    property bool isCalculating: false
    property bool lightMode: false
    property int forecastHours: 24

    signal sessionSelected(var passEvent)
    signal recalculateRequested()
    signal satelliteChanged(string satId)
    signal forecastDurationSelected(int hours)

    radius: 12
    clip: true
    color: "transparent"
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // ================= HEADER =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "📅"
                font.pixelSize: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: qsTr("Future Session Windows")
                    font.bold: true
                    font.pixelSize: 15
                    color: planningSidebarRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                }

                Label {
                    text: planningSidebarRoot.passResult ? 
                          (planningSidebarRoot.passResult.totalPasses + " passes found (" + planningSidebarRoot.passResult.multiStationPasses + " multi-station)") : 
                          qsTr("Configure forecast and calculate")
                    font.pixelSize: 11
                    color: planningSidebarRoot.lightMode ? "#6c757d" : "#909296"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: planningSidebarRoot.lightMode ? "#e9ecef" : "#222736"
        }

        // ================= CONTROLS =================
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            // Satellite Selector
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: qsTr("Satellite:")
                    font.bold: true
                    font.pixelSize: 11
                    color: planningSidebarRoot.lightMode ? "#495057" : "#ced4da"
                }

                ComboBox {
                    id: satCombo
                    Layout.fillWidth: true
                    height: 32
                    model: planningSidebarRoot.satellitesModel
                    textRole: "name"

                    currentIndex: {
                        if (!planningSidebarRoot.satellitesModel) return 0
                        for (var i = 0; i < planningSidebarRoot.satellitesModel.count; i++) {
                            if (planningSidebarRoot.satellitesModel.get(i).satId === planningSidebarRoot.selectedSatelliteId) {
                                return i
                            }
                        }
                        return 0
                    }

                    onActivated: function(index) {
                        if (planningSidebarRoot.satellitesModel && index >= 0 && index < planningSidebarRoot.satellitesModel.count) {
                            var sId = planningSidebarRoot.satellitesModel.get(index).satId
                            planningSidebarRoot.satelliteChanged(sId)
                        }
                    }
                }
            }

            // Forecast Duration + Recalculate Button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ComboBox {
                    id: forecastCombo
                    Layout.preferredWidth: 95
                    height: 32
                    model: [
                        { text: "12 hours", hours: 12 },
                        { text: "24 hours", hours: 24 },
                        { text: "48 hours", hours: 48 },
                        { text: "72 hours", hours: 72 }
                    ]
                    textRole: "text"
                    currentIndex: 1 // 24 hours
                    onActivated: function(index) {
                        planningSidebarRoot.forecastHours = model[index].hours
                        planningSidebarRoot.forecastDurationSelected(model[index].hours)
                    }
                }

                Button {
                    id: recalcBtn
                    Layout.fillWidth: true
                    height: 32
                    text: planningSidebarRoot.isCalculating ? qsTr("Calculating...") : qsTr("⚡ Recalculate")
                    enabled: !planningSidebarRoot.isCalculating

                    background: Rectangle {
                        radius: 6
                        color: recalcBtn.enabled ? (planningSidebarRoot.lightMode ? "#228be6" : "#1c7ed6") : "#adb5bd"
                    }

                    contentItem: Text {
                        text: recalcBtn.text
                        font.bold: true
                        font.pixelSize: 11
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: planningSidebarRoot.recalculateRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: planningSidebarRoot.lightMode ? "#e9ecef" : "#222736"
        }

        // ================= PASS SESSIONS LIST =================
        ListView {
            id: passListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: (planningSidebarRoot.passResult && planningSidebarRoot.passResult.passes) ? planningSidebarRoot.passResult.passes : []

            delegate: Rectangle {
                id: passCard
                width: passListView.width
                implicitHeight: passCardLayout.implicitHeight + 14
                radius: 8

                property bool isSelected: planningSidebarRoot.selectedSession && 
                                          (planningSidebarRoot.selectedSession.passIndex === modelData.passIndex &&
                                           planningSidebarRoot.selectedSession.combinedAosUtc === modelData.combinedAosUtc)

                color: isSelected ? 
                       (planningSidebarRoot.lightMode ? "#e7f5ff" : "#122842") : 
                       (planningSidebarRoot.lightMode ? "#f8f9fa" : "#1a1e29")

                border.color: isSelected ? 
                              "#339af0" : 
                              (modelData.isMultiStation ? "#2f9e44" : (planningSidebarRoot.lightMode ? "#dee2e6" : "#262b3a"))
                border.width: isSelected ? 2 : (modelData.isMultiStation ? 1.5 : 1)

                // Left active accent bar
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3.5
                    radius: 1
                    color: isSelected ? "#339af0" : (modelData.isMultiStation ? "#40c057" : "transparent")
                    visible: isSelected || modelData.isMultiStation
                }

                ColumnLayout {
                    id: passCardLayout
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 4

                    // Top Row: Pass # + Relative AOS + Duration
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 22
                            height: 18
                            radius: 4
                            color: planningSidebarRoot.lightMode ? "#e9ecef" : "#262c3d"
                            Text {
                                anchors.centerIn: parent
                                text: "#" + modelData.passIndex
                                font.bold: true
                                font.pixelSize: 10
                                color: planningSidebarRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                        }

                        Label {
                            text: modelData.relativeAos
                            font.bold: true
                            font.pixelSize: 11
                            color: passCard.isSelected ? "#339af0" : (planningSidebarRoot.lightMode ? "#212529" : "#f1f3f5")
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            height: 18
                            width: durText.implicitWidth + 8
                            radius: 9
                            color: planningSidebarRoot.lightMode ? "#e7f5ff" : "#14233c"
                            Text {
                                id: durText
                                anchors.centerIn: parent
                                text: modelData.combinedDurationFormatted
                                font.bold: true
                                font.pixelSize: 10
                                color: "#339af0"
                            }
                        }
                    }

                    // Stations Tag
                    Label {
                        text: "📡 " + modelData.stationNames
                        font.pixelSize: 10
                        color: planningSidebarRoot.lightMode ? "#6c757d" : "#909296"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Multi-station / Overlap Badges
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: modelData.isMultiStation || modelData.hasConcurrentOverlap

                        Rectangle {
                            visible: modelData.isMultiStation
                            height: 16
                            width: multiText.implicitWidth + 8
                            radius: 4
                            color: planningSidebarRoot.lightMode ? "#ebfbee" : "#132d1d"
                            border.color: "#40c057"
                            Text {
                                id: multiText
                                anchors.centerIn: parent
                                text: "🤝 " + modelData.stationCount + " Stations" + (modelData.windowGainPercent > 0 ? " (+" + modelData.windowGainPercent + "%)" : "")
                                font.bold: true
                                font.pixelSize: 9
                                color: "#40c057"
                            }
                        }

                        Rectangle {
                            visible: modelData.hasConcurrentOverlap
                            height: 16
                            width: ovText.implicitWidth + 8
                            radius: 4
                            color: planningSidebarRoot.lightMode ? "#fff9db" : "#2d2411"
                            border.color: "#f59f00"
                            Text {
                                id: ovText
                                anchors.centerIn: parent
                                text: "⚡ Overlap " + modelData.overlapDurationFormatted
                                font.bold: true
                                font.pixelSize: 9
                                color: "#f59f00"
                            }
                        }
                    }

                    // Metrics Row (Elevation + UTC Window)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            height: 16
                            width: elText.implicitWidth + 8
                            radius: 4
                            color: modelData.maxElevationDeg >= 50.0 ? "#2f9e44" : (modelData.maxElevationDeg >= 20.0 ? "#f59f00" : "#868e96")
                            Text {
                                id: elText
                                anchors.centerIn: parent
                                text: "Peak " + modelData.maxElevationDeg + "°"
                                font.bold: true
                                font.pixelSize: 9
                                color: "#ffffff"
                            }
                        }

                        Label {
                            text: modelData.combinedAosUtc.substring(11, 19) + " → " + modelData.combinedLosUtc.substring(11, 19)
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: planningSidebarRoot.lightMode ? "#868e96" : "#6c757d"
                            Layout.fillWidth: true
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        planningSidebarRoot.selectedSession = modelData
                        planningSidebarRoot.sessionSelected(modelData)
                    }
                }
            }
        }
    }
}
