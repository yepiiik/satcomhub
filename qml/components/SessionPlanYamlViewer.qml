import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property string sessionTitle: ""
    property string yamlContent: ""
    property bool lightMode: false
    property color accentColor: "#e67700" // warm amber / gold for mission plans
    property var stationManager: null

    property string documentTitle: qsTr("Session Plan YAML Document")
    property string headerIcon: "📄"
    property string copyButtonText: qsTr("📋 Copy YAML")
    property string exportButtonText: qsTr("💾 Export to YAML File")
    property string defaultFileName: "session_plan.yaml"
    property string fileDialogFilter: "YAML Files (*.yaml *.yml)"
    property bool isJsonMode: false

    function openForYaml(subtitle, yamlText, suggestedFileName) {
        root.isJsonMode = false
        root.accentColor = "#e67700"
        root.documentTitle = qsTr("Session Plan YAML Document")
        root.headerIcon = "📄"
        root.copyButtonText = qsTr("📋 Copy YAML")
        root.exportButtonText = qsTr("💾 Export to YAML File")
        root.defaultFileName = suggestedFileName || "session_plan.yaml"
        root.fileDialogFilter = "YAML Files (*.yaml *.yml)"
        root.sessionTitle = subtitle || qsTr("Adaptive Coding & Modulation Transmission Schedule")
        root.yamlContent = yamlText || ""
        root.open()
    }

    function openForJson(docTitle, subtitle, jsonText, suggestedFileName) {
        root.isJsonMode = true
        root.accentColor = "#339af0"
        root.documentTitle = docTitle || qsTr("Module JSON Document")
        root.headerIcon = "{ }"
        root.copyButtonText = qsTr("📋 Copy JSON")
        root.exportButtonText = qsTr("💾 Export to JSON File")
        root.defaultFileName = suggestedFileName || "module_data.json"
        root.fileDialogFilter = "JSON Files (*.json)"
        root.sessionTitle = subtitle || qsTr("Python Module Data Payload")
        root.yamlContent = jsonText || "{}"
        root.open()
    }

    signal exportRequested(string yamlText)
    signal copyRequested()

    modal: true
    focus: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 660, 680)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 60 : 700, 720)
    padding: 0

    background: Rectangle {
        radius: 12
        color: root.lightMode ? "#ffffff" : "#1a1b1e"
        border.color: root.lightMode ? "#ced4da" : "#373a40"
        border.width: 1
    }

    // Exit cross button positioned in top right corner
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
                    text: root.headerIcon
                    font.bold: root.isJsonMode
                    font.pixelSize: root.isJsonMode ? 14 : 16
                    color: "#ffffff"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: root.documentTitle
                    font.bold: true
                    font.pixelSize: 16
                    color: root.lightMode ? "#212529" : "#ffffff"
                }
                Label {
                    text: root.sessionTitle !== "" ? root.sessionTitle : qsTr("Adaptive Coding & Modulation Transmission Schedule")
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
                id: yamlArea
                text: root.yamlContent
                readOnly: true
                wrapMode: TextEdit.NoWrap
                font.family: "Consolas, 'Courier New', monospace"
                font.pixelSize: 12
                color: root.isJsonMode
                       ? (root.lightMode ? "#1864ab" : "#74c0fc")
                       : (root.lightMode ? "#d9480f" : "#ff922b")
                selectByMouse: true
                background: Rectangle {
                    radius: 8
                    color: root.lightMode ? "#f8f9fa" : "#141517"
                    border.color: root.lightMode ? "#dee2e6" : "#25262b"
                    border.width: 1
                }
            }
        }

        // Bottom Action Bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                id: copyBtn
                text: root.copyButtonText
                implicitHeight: 34
                background: Rectangle {
                    radius: 6
                    color: copyBtn.hovered ? (root.lightMode ? "#e9ecef" : "#2c2e33") : (root.lightMode ? "#f1f3f5" : "#25262b")
                    border.color: root.lightMode ? "#ced4da" : "#373a40"
                    border.width: 1
                }
                contentItem: Text {
                    text: copyBtn.text
                    color: root.lightMode ? "#495057" : "#c1c2c5"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    yamlArea.selectAll()
                    yamlArea.copy()
                    yamlArea.deselect()
                    root.copyRequested()
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                id: exportBtn
                text: root.exportButtonText
                implicitHeight: 34
                background: Rectangle {
                    radius: 6
                    color: exportBtn.hovered ? Qt.darker(root.accentColor, 1.1) : root.accentColor
                }
                contentItem: Text {
                    text: exportBtn.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    root.exportRequested(root.yamlContent)
                }
            }

            Button {
                id: doneBtn
                text: qsTr("Close")
                implicitHeight: 34
                background: Rectangle {
                    radius: 6
                    color: doneBtn.hovered ? (root.lightMode ? "#dee2e6" : "#373a40") : (root.lightMode ? "#e9ecef" : "#2c2e33")
                }
                contentItem: Text {
                    text: doneBtn.text
                    color: root.lightMode ? "#495057" : "#c1c2c5"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.close()
            }
        }
    }
}

