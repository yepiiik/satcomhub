import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: historySidebarRoot

    property var historyModel: null
    property var selectedObservation: null
    property bool lightMode: false

    signal observationSelected(var obsItem)
    signal addObservationRequested()

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
                text: "📜"
                font.pixelSize: 18
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: qsTr("Observation History")
                    font.bold: true
                    font.pixelSize: 15
                    color: historySidebarRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                }

                Label {
                    text: qsTr("F9 Specification • Pass Telemetry Logs")
                    font.pixelSize: 11
                    color: historySidebarRoot.lightMode ? "#6c757d" : "#909296"
                }
            }

            Button {
                height: 26
                width: 26
                background: Rectangle {
                    radius: 4
                    color: parent.hovered ? (historySidebarRoot.lightMode ? "#e9ecef" : "#2c3245") : "transparent"
                    border.color: historySidebarRoot.lightMode ? "#dee2e6" : "#3b4256"
                }
                contentItem: Text {
                    text: "+"
                    font.bold: true
                    font.pixelSize: 14
                    color: "#20c997"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Log New Observation (F9)")
                onClicked: historySidebarRoot.addObservationRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: historySidebarRoot.lightMode ? "#e9ecef" : "#222736"
        }

        // Search & Filter
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: searchInput
                Layout.fillWidth: true
                height: 30
                placeholderText: qsTr("Search observations...")
                color: historySidebarRoot.lightMode ? "#212529" : "#f8f9fa"
                background: Rectangle {
                    radius: 6
                    color: historySidebarRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                    border.color: searchInput.activeFocus ? "#20c997" : (historySidebarRoot.lightMode ? "#dee2e6" : "#2d3345")
                }
            }
        }

        // Observations List
        ListView {
            id: obsListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: historySidebarRoot.historyModel

            delegate: Rectangle {
                id: obsCard
                width: obsListView.width
                implicitHeight: cardCol.implicitHeight + 14
                radius: 8

                property bool isSelected: historySidebarRoot.selectedObservation && 
                                          historySidebarRoot.selectedObservation.obsId === model.obsId

                color: isSelected ? 
                       (historySidebarRoot.lightMode ? "#e6fcf5" : "#0d2b23") : 
                       (historySidebarRoot.lightMode ? "#f8f9fa" : "#1a1e29")

                border.color: isSelected ? "#20c997" : (historySidebarRoot.lightMode ? "#dee2e6" : "#262b3a")
                border.width: isSelected ? 1.5 : 1

                // Active left bar
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 3.5
                    radius: 1
                    color: "#20c997"
                    visible: obsCard.isSelected
                }

                ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Label {
                            text: model.obsId
                            font.bold: true
                            font.pixelSize: 11
                            color: obsCard.isSelected ? "#20c997" : (historySidebarRoot.lightMode ? "#212529" : "#ffffff")
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            height: 16
                            width: statusText.implicitWidth + 8
                            radius: 4
                            color: model.status === "Decoded" ? "#2f9e44" : (model.status === "Partial" ? "#f59f00" : "#868e96")
                            Text {
                                id: statusText
                                anchors.centerIn: parent
                                text: model.status
                                font.bold: true
                                font.pixelSize: 9
                                color: "#ffffff"
                            }
                        }
                    }

                    Label {
                        text: "🛰️ " + model.satelliteName + " • 📡 " + model.stationName
                        font.pixelSize: 10
                        color: historySidebarRoot.lightMode ? "#495057" : "#ced4da"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: model.dateTimeUtc
                            font.pixelSize: 9
                            font.family: "monospace"
                            color: historySidebarRoot.lightMode ? "#868e96" : "#909296"
                            Layout.fillWidth: true
                        }

                        Label {
                            text: "Max " + model.maxSnrDb + " dB"
                            font.bold: true
                            font.pixelSize: 10
                            color: "#339af0"
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var obs = {
                            obsId: model.obsId,
                            satelliteName: model.satelliteName,
                            stationName: model.stationName,
                            dateTimeUtc: model.dateTimeUtc,
                            durationFormatted: model.durationFormatted,
                            maxSnrDb: model.maxSnrDb,
                            meanSnrDb: model.meanSnrDb,
                            maxElevationDeg: model.maxElevationDeg,
                            status: model.status,
                            decodedFrames: model.decodedFrames,
                            totalFrames: model.totalFrames,
                            operator: model.operator,
                            notes: model.notes
                        }
                        historySidebarRoot.selectedObservation = obs
                        historySidebarRoot.observationSelected(obs)
                    }
                }
            }
        }
    }
}
