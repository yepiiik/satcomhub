import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: toastOverlayRoot
    anchors.fill: parent
    z: 9999
    // Pass-through for mouse events outside individual toast cards
    enabled: true

    property bool lightMode: false
    property var toastsModel: null

    signal toastCloseRequested(string runId)

    ColumnLayout {
        id: toastColumn
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 22
        anchors.bottomMargin: 22
        spacing: 10
        width: 340

        Repeater {
            model: toastOverlayRoot.toastsModel

            Rectangle {
                id: toastCard
                Layout.fillWidth: true
                height: cardCol.implicitHeight + 22
                radius: 10
                color: toastOverlayRoot.lightMode ? "#ffffff" : "#181c26"
                border.color: model.status === "error"
                              ? "#fa5252"
                              : (model.status === "done"
                                 ? "#40c057"
                                 : (toastOverlayRoot.lightMode ? "#ced4da" : "#2d3548"))
                border.width: 1.5
                clip: true

                // Subtle left accent stripe
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    color: model.status === "error"
                           ? "#fa5252"
                           : (model.status === "done" ? "#40c057" : "#339af0")
                }

                // Consume mouse clicks on the toast card so they don't click underlying elements
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                }

                ColumnLayout {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    anchors.topMargin: 11
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: model.status === "error"
                                  ? "⚠️"
                                  : (model.status === "done" ? "✅" : "🐍")
                            font.pixelSize: 14
                        }

                        Label {
                            Layout.fillWidth: true
                            text: model.moduleName
                            font.bold: true
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                            color: toastOverlayRoot.lightMode ? "#212529" : "#f1f3f5"
                        }

                        Label {
                            text: Math.round((model.progress || 0) * 100) + "%"
                            font.bold: true
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: model.status === "error"
                                   ? "#fa5252"
                                   : (model.status === "done" ? "#40c057" : "#339af0")
                        }

                        Button {
                            id: closeBtn
                            implicitWidth: 22
                            implicitHeight: 22
                            padding: 0
                            background: Rectangle {
                                radius: 5
                                color: closeBtn.hovered
                                       ? (toastOverlayRoot.lightMode ? "#e9ecef" : "#262b3a")
                                       : "transparent"
                            }
                            contentItem: Text {
                                text: "✕"
                                font.bold: true
                                font.pixelSize: 11
                                color: toastOverlayRoot.lightMode ? "#495057" : "#adb5bd"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                toastOverlayRoot.toastCloseRequested(model.runId)
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: model.statusText || "Running module..."
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        color: model.status === "error"
                               ? "#ff6b6b"
                               : (toastOverlayRoot.lightMode ? "#6c757d" : "#909296")
                    }

                    // Filling Progress Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: toastOverlayRoot.lightMode ? "#e9ecef" : "#252a38"
                        clip: true

                        Rectangle {
                            height: parent.height
                            width: Math.max(4, parent.width * Math.min(1.0, Math.max(0.0, model.progress || 0.0)))
                            radius: 3
                            color: model.status === "error"
                                   ? "#fa5252"
                                   : (model.status === "done" ? "#40c057" : "#339af0")

                            Behavior on width {
                                NumberAnimation {
                                    duration: 110
                                    easing.type: Easing.OutQuad
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

