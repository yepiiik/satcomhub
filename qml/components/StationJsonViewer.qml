import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property string stationName: ""
    property string jsonContent: ""
    property bool lightMode: false
    property color accentColor: "#228be6"
    property var stationManager: null

    modal: true
    focus: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 600, 620)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 60 : 650, 680)
    padding: 0

    background: Rectangle {
        radius: 12
        color: root.lightMode ? "#ffffff" : "#1a1b1e"
        border.color: root.lightMode ? "#ced4da" : "#373a40"
        border.width: 1
    }

    // Exit cross button positioned in the exact top right corner
    Button {
        id: closeCrossBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.rightMargin: 12
        width: 32
        height: 32
        z: 99
        background: Rectangle {
            radius: 6
            color: closeCrossBtn.hovered ? (root.lightMode ? "#e9ecef" : "#2c2e33") : "transparent"
        }
        contentItem: Text {
            text: "✕"
            color: root.lightMode ? "#495057" : "#c1c2c5"
            font.bold: true
            font.pixelSize: 15
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: root.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 36
            spacing: 8

            Rectangle {
                width: 32
                height: 32
                radius: 6
                color: root.accentColor
                Text {
                    anchors.centerIn: parent
                    text: "{ }"
                    font.bold: true
                    font.pixelSize: 15
                    color: "#ffffff"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: qsTr("Station JSON Document")
                    font.bold: true
                    font.pixelSize: 16
                    color: root.lightMode ? "#212529" : "#ffffff"
                }
                Label {
                    text: root.stationName !== "" ? root.stationName : qsTr("Single Antenna RF Configuration")
                    font.pixelSize: 12
                    color: root.lightMode ? "#868e96" : "#909296"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.lightMode ? "#e9ecef" : "#2c2e33"
        }

        // Code Editor / Viewer View with responsive ScrollBar
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 8
                contentItem: Rectangle {
                    implicitWidth: 8
                    radius: 4
                    color: root.lightMode ? "#ced4da" : "#495057"
                }
            }
            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
                height: 8
                contentItem: Rectangle {
                    implicitHeight: 8
                    radius: 4
                    color: root.lightMode ? "#ced4da" : "#495057"
                }
            }

            TextArea {
                id: jsonArea
                text: root.jsonContent
                readOnly: true
                wrapMode: TextEdit.NoWrap
                font.family: "Consolas, 'Courier New', monospace"
                font.pixelSize: 12
                color: root.lightMode ? "#2b8a3e" : "#51cf66"
                selectByMouse: true
                background: Rectangle {
                    radius: 8
                    color: root.lightMode ? "#f8f9fa" : "#141517"
                    border.color: root.lightMode ? "#dee2e6" : "#25262b"
                }
            }
        }

        // Footer Actions
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                id: copyStatusLabel
                text: ""
                font.pixelSize: 12
                font.bold: true
                color: "#40c057"
                Layout.fillWidth: true
            }

            Button {
                id: copyBtn
                Layout.preferredHeight: 36
                text: qsTr("📋  Copy JSON")
                background: Rectangle {
                    radius: 6
                    color: copyBtn.hovered ? "#1c7ed6" : root.accentColor
                }
                contentItem: Text {
                    text: copyBtn.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    jsonArea.selectAll()
                    jsonArea.copy()
                    copyStatusLabel.text = qsTr("Copied to clipboard!")
                    copyTimer.restart()
                }
            }

            Button {
                id: exportBtn
                Layout.preferredHeight: 36
                text: qsTr("💾  Export JSON")
                background: Rectangle {
                    radius: 6
                    color: exportBtn.hovered ? (root.lightMode ? "#2b8a3e" : "#2f9e44") : (root.lightMode ? "#e9ecef" : "#2c2e33")
                }
                contentItem: Text {
                    text: exportBtn.text
                    color: root.lightMode ? "#212529" : "#ced4da"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    var defaultName = (root.stationName ? root.stationName.toLowerCase().replace(/[^a-z0-9_-]/g, "_") : "station") + ".json"
                    if (root.stationManager) {
                        var filePath = root.stationManager.saveFileDialog(qsTr("Export Station JSON"), defaultName, "JSON Files (*.json)")
                        if (filePath && filePath.length > 0) {
                            var success = root.stationManager.writeTextFile(filePath, root.jsonContent)
                            if (success) {
                                var parts = filePath.replace(/\\/g, "/").split("/")
                                copyStatusLabel.text = qsTr("Exported: ") + parts[parts.length - 1]
                                copyTimer.restart()
                            }
                        }
                    }
                }
            }

            Button {
                id: closeBtn
                Layout.preferredHeight: 36
                text: qsTr("Close")
                background: Rectangle {
                    radius: 6
                    color: root.lightMode ? "#e9ecef" : "#2c2e33"
                }
                contentItem: Text {
                    text: closeBtn.text
                    color: root.lightMode ? "#495057" : "#ced4da"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.close()
            }
        }
    }

    Timer {
        id: copyTimer
        interval: 3000
        onTriggered: copyStatusLabel.text = ""
    }
}
