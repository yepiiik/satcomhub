import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string label: ""
    property string suffix: ""
    property string prefix: ""
    property real value: 0.0
    property real from: -999999.0
    property real to: 999999.0
    property real stepSize: 1.0
    property int decimals: 2

    property bool isOptional: false
    property bool optionalEnabled: true

    property bool lightMode: false
    property color accentColor: "#228be6"

    signal valueModified(real newValue)

    implicitWidth: 120
    implicitHeight: (label !== "" || isOptional) ? 58 : 36

    ColumnLayout {
        anchors.fill: parent
        spacing: 3

        // Optional Label Row
        RowLayout {
            Layout.fillWidth: true
            visible: root.label !== "" || root.isOptional
            spacing: 4

            Label {
                text: root.label
                font.pixelSize: 11
                font.bold: true
                color: (!root.isOptional || root.optionalEnabled)
                       ? (root.lightMode ? "#495057" : "#ced4da")
                       : (root.lightMode ? "#adb5bd" : "#6c757d")
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Checkbox for optional fields (e.g. Alt)
            RowLayout {
                visible: root.isOptional
                spacing: 3
                CheckBox {
                    id: optCheck
                    checked: root.optionalEnabled
                    onCheckedChanged: root.optionalEnabled = checked
                    indicator: Rectangle {
                        implicitWidth: 14
                        implicitHeight: 14
                        radius: 3
                        color: optCheck.checked ? root.accentColor : "transparent"
                        border.color: optCheck.checked ? root.accentColor : (root.lightMode ? "#adb5bd" : "#5c5f66")
                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: 10
                            font.bold: true
                            color: "#ffffff"
                            visible: optCheck.checked
                        }
                    }
                }
                Label {
                    text: root.optionalEnabled ? qsTr("Active") : qsTr("None")
                    font.pixelSize: 10
                    color: optCheck.checked ? root.accentColor : (root.lightMode ? "#adb5bd" : "#6c757d")
                }
            }
        }

        // Stepper Row: [-] [ Input ] [+]
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitHeight: 34
            radius: 6
            color: (!root.isOptional || root.optionalEnabled)
                   ? (root.lightMode ? "#ffffff" : "#1a1b1e")
                   : (root.lightMode ? "#f1f3f5" : "#141517")
            border.color: textInput.activeFocus
                          ? root.accentColor
                          : (root.lightMode ? "#ced4da" : "#373a40")
            border.width: textInput.activeFocus ? 2 : 1

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Decrement button
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.fillHeight: true
                    radius: 5
                    color: decMouse.pressed
                           ? (root.lightMode ? "#dee2e6" : "#2c2e33")
                           : (decMouse.containsMouse ? (root.lightMode ? "#e9ecef" : "#25262b") : "transparent")
                    opacity: (!root.isOptional || root.optionalEnabled) ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        font.pixelSize: 14
                        font.bold: true
                        color: root.lightMode ? "#495057" : "#c1c2c5"
                    }

                    MouseArea {
                        id: decMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.isOptional || root.optionalEnabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.stepBy(-1)
                        }
                    }
                }

                // Value Text Field
                TextField {
                    id: textInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                    padding: 0
                    enabled: !root.isOptional || root.optionalEnabled
                    color: enabled
                           ? (root.lightMode ? "#212529" : "#ffffff")
                           : (root.lightMode ? "#adb5bd" : "#6c757d")
                    background: Item {}

                    text: formatValue(root.value)

                    onEditingFinished: {
                        var parsed = parseFloat(textInput.text.replace(/[^0-9.-]/g, ""))
                        if (!isNaN(parsed)) {
                            root.setValueClamped(parsed)
                        } else {
                            textInput.text = formatValue(root.value)
                        }
                    }
                }

                // Suffix label inside box if space permits
                Text {
                    visible: root.suffix !== "" && (!root.isOptional || root.optionalEnabled)
                    text: root.suffix
                    font.pixelSize: 10
                    color: root.lightMode ? "#868e96" : "#909296"
                    rightPadding: 4
                    verticalAlignment: Text.AlignVCenter
                }

                // Increment button
                Rectangle {
                    Layout.preferredWidth: 26
                    Layout.fillHeight: true
                    radius: 5
                    color: incMouse.pressed
                           ? (root.lightMode ? "#dee2e6" : "#2c2e33")
                           : (incMouse.containsMouse ? (root.lightMode ? "#e9ecef" : "#25262b") : "transparent")
                    opacity: (!root.isOptional || root.optionalEnabled) ? 1.0 : 0.4

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: 14
                        font.bold: true
                        color: root.lightMode ? "#495057" : "#c1c2c5"
                    }

                    MouseArea {
                        id: incMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.isOptional || root.optionalEnabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.stepBy(1)
                        }
                    }
                }
            }
        }
    }

    function formatValue(val) {
        if (root.decimals > 0) {
            return Number(val).toFixed(root.decimals)
        }
        return String(Math.round(val))
    }

    function stepBy(steps) {
        var newVal = root.value + (steps * root.stepSize)
        setValueClamped(newVal)
    }

    function setValueClamped(val) {
        var clamped = Math.min(root.to, Math.max(root.from, val))
        if (root.decimals > 0) {
            var factor = Math.pow(10, root.decimals)
            clamped = Math.round(clamped * factor) / factor
        }
        root.value = clamped
        textInput.text = formatValue(clamped)
        root.valueModified(clamped)
    }

    onValueChanged: {
        if (!textInput.activeFocus) {
            textInput.text = formatValue(root.value)
        }
    }
}
