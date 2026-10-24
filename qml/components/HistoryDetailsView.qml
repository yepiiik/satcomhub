import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: historyDetailsRoot

    property var observationData: null
    property bool lightMode: false

    radius: 12
    clip: true
    color: "transparent"

    // ================= EMPTY STATE =================
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16
        visible: historyDetailsRoot.observationData === null

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 18
            color: historyDetailsRoot.lightMode ? "#e6fcf5" : "#0d2b23"
            border.color: "#20c997"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "📜"
                font.pixelSize: 34
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Select an Observation to View History Details")
            font.bold: true
            font.pixelSize: 18
            color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Choose a historical pass observation from the list on the left\nto inspect decoded telemetry, SNR logs, and reception parameters.")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
        }
    }

    // ================= ACTIVE OBSERVATION VIEW =================
    ScrollView {
        anchors.fill: parent
        visible: historyDetailsRoot.observationData !== null
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            anchors.margins: 18
            spacing: 14

            // --- HEADER CARD ---
            Rectangle {
                Layout.fillWidth: true
                height: obsHeaderCol.implicitHeight + 24
                radius: 10
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: obsHeaderCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            height: 24
                            width: obsIdText.implicitWidth + 14
                            radius: 6
                            color: "#20c997"
                            Text {
                                id: obsIdText
                                anchors.centerIn: parent
                                text: historyDetailsRoot.observationData ? (historyDetailsRoot.observationData.obsId || "") : ""
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                            }
                        }

                        Label {
                            text: historyDetailsRoot.observationData ? 
                                  (historyDetailsRoot.observationData.satelliteName + " @ " + historyDetailsRoot.observationData.stationName) : ""
                            font.bold: true
                            font.pixelSize: 16
                            color: historyDetailsRoot.lightMode ? "#212529" : "#ffffff"
                        }

                        Rectangle {
                            height: 22
                            width: statusBadgeText.implicitWidth + 12
                            radius: 11
                            color: (historyDetailsRoot.observationData && historyDetailsRoot.observationData.status === "Decoded") ? 
                                   "#2f9e44" : "#f59f00"
                            Text {
                                id: statusBadgeText
                                anchors.centerIn: parent
                                text: historyDetailsRoot.observationData ? historyDetailsRoot.observationData.status : ""
                                font.bold: true
                                font.pixelSize: 10
                                color: "#ffffff"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            height: 28
                            text: qsTr("💾 Export JSON / CSV")
                            background: Rectangle {
                                radius: 6
                                color: historyDetailsRoot.lightMode ? "#e9ecef" : "#242a3a"
                                border.color: historyDetailsRoot.lightMode ? "#ced4da" : "#3b4256"
                            }
                            contentItem: Text {
                                text: parent.text
                                font.bold: true
                                font.pixelSize: 11
                                color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Label {
                            text: historyDetailsRoot.observationData ? ("Recorded: " + historyDetailsRoot.observationData.dateTimeUtc) : ""
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                        }

                        Label {
                            text: historyDetailsRoot.observationData ? ("Duration: " + historyDetailsRoot.observationData.durationFormatted) : ""
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        Label {
                            text: historyDetailsRoot.observationData ? ("Operator: " + historyDetailsRoot.observationData.operator) : ""
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                        }
                    }
                }
            }

            // --- TELEMETRY SUMMARY CARDS ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Peak SNR
                StatPillCard {
                    title: "Max SNR"
                    value: historyDetailsRoot.observationData ? (historyDetailsRoot.observationData.maxSnrDb + " dB") : "--"
                    subtitle: "Peak C/N ratio"
                    accentColor: "#339af0"
                    lightMode: historyDetailsRoot.lightMode
                }

                // Mean SNR
                StatPillCard {
                    title: "Mean SNR"
                    value: historyDetailsRoot.observationData ? (historyDetailsRoot.observationData.meanSnrDb + " dB") : "--"
                    subtitle: "Pass average"
                    accentColor: "#51cf66"
                    lightMode: historyDetailsRoot.lightMode
                }

                // Peak Elevation
                StatPillCard {
                    title: "Peak Elevation"
                    value: historyDetailsRoot.observationData ? (historyDetailsRoot.observationData.maxElevationDeg + "°") : "--"
                    subtitle: "Closest approach (TCA)"
                    accentColor: "#f59f00"
                    lightMode: historyDetailsRoot.lightMode
                }

                // Decoded Frames
                StatPillCard {
                    title: "Telemetry Frames"
                    value: historyDetailsRoot.observationData ? 
                           (historyDetailsRoot.observationData.decodedFrames + " / " + historyDetailsRoot.observationData.totalFrames) : "--"
                    subtitle: "CRC-verified packets"
                    accentColor: "#20c997"
                    lightMode: historyDetailsRoot.lightMode
                }
            }

            // --- HISTORICAL RF WATERFALL / SPECTRUM PREVIEW (F9) ---
            Rectangle {
                Layout.fillWidth: true
                height: 240
                radius: 8
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("RF Signal Waterfall & Spectrogram Log (F9 Under Development)")
                            font.bold: true
                            font.pixelSize: 13
                            color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            height: 20
                            width: specTag.implicitWidth + 10
                            radius: 10
                            color: historyDetailsRoot.lightMode ? "#e7f5ff" : "#182842"
                            border.color: "#339af0"
                            Text {
                                id: specTag
                                anchors.centerIn: parent
                                text: "F9 Specification"
                                font.bold: true
                                font.pixelSize: 10
                                color: "#339af0"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 6
                        color: historyDetailsRoot.lightMode ? "#0b101c" : "#07090e"
                        clip: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "📊"
                                font.pixelSize: 28
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: qsTr("Historical RF IQ / Baseband Recording & Waterfall View")
                                font.bold: true
                                font.pixelSize: 13
                                color: "#4dabf7"
                            }

                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: qsTr("This section will render stored signal strength timelines, Doppler track curves,\nand IQ sample waterfalls recorded during satellite flyby.")
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: 11
                                color: "#868e96"
                            }
                        }
                    }
                }
            }

            // --- OPERATOR NOTES & LOGS ---
            Rectangle {
                Layout.fillWidth: true
                height: notesCol.implicitHeight + 24
                radius: 8
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a"

                ColumnLayout {
                    id: notesCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    Label {
                        text: qsTr("Operator Session Notes")
                        font.bold: true
                        font.pixelSize: 13
                        color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                    }

                    Label {
                        text: historyDetailsRoot.observationData ? 
                              historyDetailsRoot.observationData.notes : 
                              qsTr("No notes recorded for this observation.")
                        font.pixelSize: 11
                        color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    component StatPillCard: Rectangle {
        property string title: ""
        property string value: ""
        property string subtitle: ""
        property color accentColor: "#339af0"
        property bool lightMode: false

        Layout.fillWidth: true
        height: 72
        radius: 8
        color: lightMode ? "#ffffff" : "#141720"
        border.color: accentColor
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            Label {
                text: title
                font.bold: true
                font.pixelSize: 11
                color: accentColor
            }

            Label {
                text: value
                font.bold: true
                font.pixelSize: 16
                font.family: "monospace"
                color: lightMode ? "#212529" : "#ffffff"
            }

            Label {
                text: subtitle
                font.pixelSize: 10
                color: lightMode ? "#6c757d" : "#868e96"
            }
        }
    }
}
