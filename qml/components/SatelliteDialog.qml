import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: satDialogRoot

    property bool lightMode: false
    property var propagator: null
    property string editingSatId: ""

    signal satelliteCommitted(var satData, bool isEdit)

    modal: true
    focus: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 580, 600)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 40 : 540, 560)
    padding: 0

    background: Rectangle {
        radius: 12
        color: satDialogRoot.lightMode ? "#ffffff" : "#141720"
        border.color: satDialogRoot.lightMode ? "#ced4da" : "#2d3345"
        border.width: 1
    }

    function openForNew() {
        editingSatId = ""
        satNameInput.text = "ISS (ZARYA)"
        tle1Input.text = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
        tle2Input.text = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
        validationStatusText.text = ""
        open()
    }

    function openForEdit(satModelItem) {
        editingSatId = satModelItem.satId || ""
        satNameInput.text = satModelItem.name || ""
        tle1Input.text = satModelItem.tle1 || ""
        tle2Input.text = satModelItem.tle2 || ""
        validationStatusText.text = ""
        open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        // ================= HEADER =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                width: 36
                height: 36
                radius: 8
                color: satDialogRoot.lightMode ? "#fff3bf" : "#372c15"
                border.color: "#f59f00"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "🛰️"
                    font.pixelSize: 18
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: satDialogRoot.editingSatId !== "" ? qsTr("Edit Satellite") : qsTr("Add New Satellite")
                    font.bold: true
                    font.pixelSize: 16
                    color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                }

                Label {
                    text: qsTr("Provide NORAD Two-Line Element (TLE) set for SGP4 orbit propagation")
                    font.pixelSize: 11
                    color: satDialogRoot.lightMode ? "#6c757d" : "#909296"
                }
            }

            // Close cross button
            Button {
                width: 32
                height: 32
                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? (satDialogRoot.lightMode ? "#e9ecef" : "#2c3245") : "transparent"
                }
                contentItem: Text {
                    text: "✕"
                    font.bold: true
                    font.pixelSize: 15
                    color: satDialogRoot.lightMode ? "#495057" : "#adb5bd"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: satDialogRoot.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: satDialogRoot.lightMode ? "#dee2e6" : "#2d3345"
        }

        // ================= INPUT FIELDS =================
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: 12

                // Satellite Name
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: qsTr("Satellite Name / Identifier")
                        font.bold: true
                        font.pixelSize: 12
                        color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                    }

                    TextField {
                        id: satNameInput
                        Layout.fillWidth: true
                        height: 36
                        placeholderText: qsTr("e.g., ISS (ZARYA), POLYITAN-3-PUT")
                        color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                            border.color: satNameInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                        }
                    }
                }

                // TLE Line 1
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("TLE Line 1 (69 chars)")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: tle1Input.text.length + " / 69"
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: tle1Input.text.trim().length >= 60 ? "#40c057" : "#fa5252"
                        }
                    }

                    TextField {
                        id: tle1Input
                        Layout.fillWidth: true
                        height: 36
                        font.family: "monospace"
                        font.pixelSize: 11
                        placeholderText: "1 25544U 98067A   ..."
                        color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                            border.color: tle1Input.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                        }
                    }
                }

                // TLE Line 2
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("TLE Line 2 (69 chars)")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: tle2Input.text.length + " / 69"
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: tle2Input.text.trim().length >= 60 ? "#40c057" : "#fa5252"
                        }
                    }

                    TextField {
                        id: tle2Input
                        Layout.fillWidth: true
                        height: 36
                        font.family: "monospace"
                        font.pixelSize: 11
                        placeholderText: "2 25544  51.6327  ..."
                        color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                            border.color: tle2Input.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                        }
                    }
                }

                // Quick Presets Buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        Layout.fillWidth: true
                        height: 28
                        text: qsTr("📋 Paste ISS (ZARYA)")
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#e7f5ff" : "#182842"
                            border.color: "#339af0"
                        }
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 11
                            font.bold: true
                            color: "#339af0"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            satNameInput.text = "ISS (ZARYA)"
                            tle1Input.text = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
                            tle2Input.text = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        height: 28
                        text: qsTr("📋 Paste POLYITAN-3 (500 km)")
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#fff9db" : "#2b2512"
                            border.color: "#f59f00"
                        }
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 11
                            font.bold: true
                            color: "#f59f00"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            satNameInput.text = "POLYITAN-3-PUT (LEO)"
                            tle1Input.text = "1 99999U 24001A   26290.50000000  .00005000  00000+0  10000-3 0  9990"
                            tle2Input.text = "2 99999  97.4000 120.0000 0012000  90.0000 270.0000 15.15000000012345"
                        }
                    }
                }

                // Validation Status Box
                Label {
                    id: validationStatusText
                    Layout.fillWidth: true
                    font.pixelSize: 11
                    color: "#fa5252"
                    visible: text !== ""
                }
            }
        }

        // ================= BOTTOM ACTIONS =================
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Button {
                height: 38
                width: 90
                text: qsTr("Cancel")
                background: Rectangle {
                    radius: 6
                    color: satDialogRoot.lightMode ? "#e9ecef" : "#252b3b"
                }
                contentItem: Text {
                    text: parent.text
                    font.bold: true
                    font.pixelSize: 12
                    color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: satDialogRoot.close()
            }

            Item { Layout.fillWidth: true }

            Button {
                id: commitBtn
                Layout.fillWidth: true
                height: 38
                enabled: satNameInput.text.trim().length > 0 && 
                         tle1Input.text.trim().length >= 60 && 
                         tle2Input.text.trim().length >= 60

                text: satDialogRoot.editingSatId !== "" ? qsTr("💾  Update Satellite") : qsTr("🚀  Calculate Orbit & Add")

                background: Rectangle {
                    radius: 6
                    color: commitBtn.enabled ? "#2f9e44" : (satDialogRoot.lightMode ? "#ced4da" : "#3b4256")
                }

                contentItem: Text {
                    text: commitBtn.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    var name = satNameInput.text.trim()
                    var l1 = tle1Input.text.trim()
                    var l2 = tle2Input.text.trim()

                    if (propagator) {
                        var prop = propagator.propagateTle(l1, l2, 0.0)
                        if (!prop.valid) {
                            validationStatusText.text = "⚠️ SGP4 failed to propagate orbit from provided TLE. Please check format."
                            return
                        }

                        var tracks = propagator.computeOrbitTracks(l1, l2, 0.75)
                        var satObj = {
                            satId: satDialogRoot.editingSatId,
                            name: name,
                            tle1: l1,
                            tle2: l2,
                            latitude: prop.latitude,
                            longitude: prop.longitude,
                            altitudeKm: prop.altitudeKm,
                            visibilityRadiusMeters: prop.visibilityRadiusMeters,
                            velocityKmS: prop.velocityKmS || 0,
                            trajectory: tracks.current || [],
                            prevTrajectory: tracks.previous || [],
                            nextTrajectory: tracks.next || []
                        }

                        satDialogRoot.satelliteCommitted(satObj, satDialogRoot.editingSatId !== "")
                        satDialogRoot.close()
                    }
                }
            }
        }
    }
}
