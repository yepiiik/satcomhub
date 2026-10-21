import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root

    property bool lightMode: false
    property color accentColor: "#228be6"
    property string editingStationId: ""

    // External references
    property var stationManager: null

    // Signals
    signal stationCommitted(var stationData, bool isEdit)
    signal pickOnMapRequested()

    modal: true
    focus: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 660, 680)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 40 : 760, 780)
    padding: 0

    background: Rectangle {
        radius: 12
        color: root.lightMode ? "#ffffff" : "#1a1b1e"
        border.color: root.lightMode ? "#ced4da" : "#373a40"
        border.width: 1
    }

    // Active Tab: 0 = Add/Configure, 1 = Import File, 2 = Export (Disabled)
    property int activeTab: 0

    // Local calculation state
    property real calcFreqMin: 4000.0
    property real calcFreqMax: 8000.0
    property real calcMaxChannelWidth: 4000.0
    property real calcTotalNf: 1.0
    property real calcRecNoiseTemp: 75.1
    property real calcSysNoiseTemp: 125.1
    property real calcGOverT: 17.5

    // Imported station preview
    property var importedStationData: null
    property string importStatusText: ""
    property bool importSuccess: false

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

        // ================= HEADER =================
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: 36
            spacing: 10

            Rectangle {
                width: 36
                height: 36
                radius: 8
                color: root.accentColor
                Text {
                    anchors.centerIn: parent
                    text: root.editingStationId !== "" ? "✏️" : "📡"
                    font.pixelSize: 18
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: root.editingStationId !== ""
                          ? qsTr("Edit Ground Station Antenna (" + root.editingStationId + ")")
                          : qsTr("Ground Station Antenna Configuration")
                    font.bold: true
                    font.pixelSize: 16
                    color: root.lightMode ? "#212529" : "#ffffff"
                }
                Label {
                    text: qsTr("Configure RF parameters, noise figures & coordinates or import from JSON")
                    font.pixelSize: 12
                    color: root.lightMode ? "#868e96" : "#909296"
                }
            }
        }

        // ================= 2-OPTION SEGMENTED BAR =================
        Rectangle {
            Layout.fillWidth: true
            height: 40
            radius: 8
            color: root.lightMode ? "#f1f3f5" : "#141517"
            border.color: root.lightMode ? "#dee2e6" : "#2c2e33"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 4

                // Option 1: Add / Configure
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: root.activeTab === 0 ? root.accentColor : "transparent"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "➕"
                            font.pixelSize: 12
                        }
                        Text {
                            text: root.editingStationId !== "" ? qsTr("Edit Antenna") : qsTr("Add Antenna")
                            font.bold: true
                            font.pixelSize: 12
                            color: root.activeTab === 0 ? "#ffffff" : (root.lightMode ? "#495057" : "#ced4da")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 0
                    }
                }

                // Option 2: Import from File
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 6
                    color: root.activeTab === 1 ? root.accentColor : "transparent"

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            text: "📂"
                            font.pixelSize: 12
                        }
                        Text {
                            text: qsTr("Import from File")
                            font.bold: true
                            font.pixelSize: 12
                            color: root.activeTab === 1 ? "#ffffff" : (root.lightMode ? "#495057" : "#ced4da")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = 1
                    }
                }
            }
        }

        // ================= TAB 0: ADD / CONFIGURE STATION FORM =================
        ScrollView {
            id: formScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activeTab === 0
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 12

                // --- 1. STATION NAME ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: qsTr("1. Station Name")
                        font.pixelSize: 12
                        font.bold: true
                        color: root.lightMode ? "#495057" : "#ced4da"
                    }
                    TextField {
                        id: nameInput
                        Layout.fillWidth: true
                        height: 36
                        placeholderText: qsTr("e.g. Warsaw Primary C-Band Hub")
                        color: root.lightMode ? "#212529" : "#ffffff"
                        background: Rectangle {
                            radius: 6
                            color: root.lightMode ? "#ffffff" : "#1a1b1e"
                            border.color: nameInput.activeFocus ? root.accentColor : (root.lightMode ? "#ced4da" : "#373a40")
                        }
                        onTextChanged: root.recalculateParameters()
                    }
                }

                // --- 2. COORDINATES: LAT / LON / ALT (3 COMPACT SPINBOXES ON A SINGLE LINE, ALT OPTIONAL) ---
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("2. Coordinates (Lat / Lon / Alt)")
                            font.pixelSize: 12
                            font.bold: true
                            color: root.lightMode ? "#495057" : "#ced4da"
                            Layout.fillWidth: true
                        }

                        Button {
                            id: pickMapBtn
                            text: qsTr("🗺️ Pick on Map")
                            height: 24
                            background: Rectangle {
                                radius: 4
                                color: pickMapBtn.hovered ? "#1c7ed6" : (root.lightMode ? "#e7f5ff" : "#182842")
                                border.color: root.accentColor
                            }
                            contentItem: Text {
                                text: pickMapBtn.text
                                font.pixelSize: 11
                                font.bold: true
                                color: pickMapBtn.hovered ? "#ffffff" : root.accentColor
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                root.pickOnMapRequested()
                            }
                        }
                    }

                    // 3 Compact DoubleSpinBoxes on a single horizontal line
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        CompactDoubleSpinBox {
                            id: latSpinBox
                            Layout.fillWidth: true
                            label: qsTr("Latitude")
                            suffix: "°"
                            from: -90.0
                            to: 90.0
                            stepSize: 0.01
                            decimals: 4
                            value: 52.2297
                            lightMode: root.lightMode
                            accentColor: root.accentColor
                            onValueModified: root.recalculateParameters()
                        }

                        CompactDoubleSpinBox {
                            id: lonSpinBox
                            Layout.fillWidth: true
                            label: qsTr("Longitude")
                            suffix: "°"
                            from: -180.0
                            to: 180.0
                            stepSize: 0.01
                            decimals: 4
                            value: 21.0122
                            lightMode: root.lightMode
                            accentColor: root.accentColor
                            onValueModified: root.recalculateParameters()
                        }

                        CompactDoubleSpinBox {
                            id: altSpinBox
                            Layout.fillWidth: true
                            label: qsTr("Alt (Opt)")
                            suffix: "m"
                            from: -500.0
                            to: 10000.0
                            stepSize: 10.0
                            decimals: 1
                            value: 150.0
                            isOptional: true
                            optionalEnabled: true
                            lightMode: root.lightMode
                            accentColor: root.accentColor
                            onValueModified: root.recalculateParameters()
                        }
                    }
                }

                // --- 3. MOBILITY TYPE & 4. MIN ELEVATION MASK ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // 3. Mobility type
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("3. Mobility Type")
                            font.pixelSize: 12
                            font.bold: true
                            color: root.lightMode ? "#495057" : "#ced4da"
                        }

                        ComboBox {
                            id: mobilityCombo
                            Layout.fillWidth: true
                            height: 36
                            model: ["Stationary", "Mobile"]
                            currentIndex: 0

                            background: Rectangle {
                                radius: 6
                                color: root.lightMode ? "#ffffff" : "#1a1b1e"
                                border.color: root.lightMode ? "#ced4da" : "#373a40"
                            }

                            contentItem: Text {
                                leftPadding: 10
                                text: mobilityCombo.displayText
                                font.pixelSize: 12
                                font.bold: true
                                color: root.lightMode ? "#212529" : "#ffffff"
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // 4. Min elevation mask (default 5 deg)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        CompactDoubleSpinBox {
                            id: elevationSpinBox
                            Layout.fillWidth: true
                            label: qsTr("4. Min Elevation Mask")
                            suffix: "°"
                            from: 0.0
                            to: 90.0
                            stepSize: 0.5
                            decimals: 1
                            value: 5.0
                            lightMode: root.lightMode
                            accentColor: root.accentColor
                            onValueModified: root.recalculateParameters()
                        }
                    }
                }

                // --- 5. OPERATING BAND (PRESET) & 6. POLARIZATION ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // 5. Operating Band
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("5. Operating Band (Preset)")
                            font.pixelSize: 12
                            font.bold: true
                            color: root.lightMode ? "#495057" : "#ced4da"
                        }

                        ComboBox {
                            id: bandCombo
                            Layout.fillWidth: true
                            height: 36
                            model: [
                                "C-band (4.0 - 8.0 GHz)",
                                "S-band (2.0 - 4.0 GHz)",
                                "X-band (8.0 - 12.0 GHz)",
                                "Ku-band (12.0 - 18.0 GHz)",
                                "Ka-band (26.5 - 40.0 GHz)",
                                "L-band (1.0 - 2.0 GHz)",
                                "UHF (400 - 470 MHz)",
                                "VHF (136 - 174 MHz)"
                            ]
                            currentIndex: 0

                            background: Rectangle {
                                radius: 6
                                color: root.lightMode ? "#ffffff" : "#1a1b1e"
                                border.color: root.lightMode ? "#ced4da" : "#373a40"
                            }

                            contentItem: Text {
                                leftPadding: 10
                                text: bandCombo.displayText
                                font.pixelSize: 12
                                font.bold: true
                                color: root.lightMode ? "#212529" : "#ffffff"
                                verticalAlignment: Text.AlignVCenter
                            }

                            onCurrentIndexChanged: root.applyBandPreset(currentIndex)
                        }
                    }

                    // 6. Polarization
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("6. Polarization")
                            font.pixelSize: 12
                            font.bold: true
                            color: root.lightMode ? "#495057" : "#ced4da"
                        }

                        ComboBox {
                            id: polCombo
                            Layout.fillWidth: true
                            height: 36
                            model: ["RHCP", "LHCP", "Linear"]
                            currentIndex: 0

                            background: Rectangle {
                                radius: 6
                                color: root.lightMode ? "#ffffff" : "#1a1b1e"
                                border.color: root.lightMode ? "#ced4da" : "#373a40"
                            }

                            contentItem: Text {
                                leftPadding: 10
                                text: polCombo.displayText
                                font.pixelSize: 12
                                font.bold: true
                                color: root.lightMode ? "#212529" : "#ffffff"
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                // --- 5b. PRECISE OPERATING FREQUENCIES (f_min, f_max) ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    CompactDoubleSpinBox {
                        id: fMinSpinBox
                        Layout.fillWidth: true
                        label: qsTr("5b. Min Frequency (f_min)")
                        suffix: " GHz"
                        from: 0.05
                        to: 100.0
                        stepSize: 0.1
                        decimals: 3
                        value: 4.000
                        lightMode: root.lightMode
                        accentColor: root.accentColor
                        onValueModified: (val) => {
                            if (val > fMaxSpinBox.value) {
                                fMaxSpinBox.value = val
                            }
                            root.recalculateParameters()
                        }
                    }

                    CompactDoubleSpinBox {
                        id: fMaxSpinBox
                        Layout.fillWidth: true
                        label: qsTr("5c. Max Frequency (f_max)")
                        suffix: " GHz"
                        from: 0.05
                        to: 100.0
                        stepSize: 0.1
                        decimals: 3
                        value: 8.000
                        lightMode: root.lightMode
                        accentColor: root.accentColor
                        onValueModified: (val) => {
                            if (val < fMinSpinBox.value) {
                                fMinSpinBox.value = val
                            }
                            root.recalculateParameters()
                        }
                    }
                }

                // --- 7. ANTENNA GAIN [dBi] ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    CompactDoubleSpinBox {
                        id: gainSpinBox
                        Layout.fillWidth: true
                        label: qsTr("7. Antenna Gain [dBi]")
                        suffix: " dBi"
                        from: 0.0
                        to: 80.0
                        stepSize: 0.5
                        decimals: 1
                        value: 38.5
                        lightMode: root.lightMode
                        accentColor: root.accentColor
                        onValueModified: root.recalculateParameters()
                    }
                }

                // --- 8. LNA NF [dB] & FEEDER LOSS [dB] ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    CompactDoubleSpinBox {
                        id: lnaNfSpinBox
                        Layout.fillWidth: true
                        label: qsTr("8a. LNA Noise Figure [dB]")
                        suffix: " dB"
                        from: 0.0
                        to: 15.0
                        stepSize: 0.05
                        decimals: 2
                        value: 0.70
                        lightMode: root.lightMode
                        accentColor: root.accentColor
                        onValueModified: root.recalculateParameters()
                    }

                    CompactDoubleSpinBox {
                        id: feederLossSpinBox
                        Layout.fillWidth: true
                        label: qsTr("8b. Feeder Loss [dB]")
                        suffix: " dB"
                        from: 0.0
                        to: 15.0
                        stepSize: 0.05
                        decimals: 2
                        value: 0.30
                        lightMode: root.lightMode
                        accentColor: root.accentColor
                        onValueModified: root.recalculateParameters()
                    }
                }

                // ================= LIVE FRIIS & BAND CALCULATION CARD =================
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: calcCardCol.implicitHeight + 16
                    radius: 8
                    color: root.lightMode ? "#e7f5ff" : "#14243b"
                    border.color: root.lightMode ? "#a5d8ff" : "#1c7ed6"
                    border.width: 1

                    ColumnLayout {
                        id: calcCardCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: "⚡"
                                font.pixelSize: 13
                            }
                            Label {
                                text: qsTr("Instant RF & Friis Noise System Derivations:")
                                font.bold: true
                                font.pixelSize: 11
                                color: root.accentColor
                                Layout.fillWidth: true
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 4
                            columnSpacing: 16

                            // Frequencies
                            RowLayout {
                                spacing: 4
                                Label {
                                    text: qsTr("Operating Freq:")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#495057" : "#adb5bd"
                                }
                                Label {
                                    text: (fMinSpinBox.value >= 1.0
                                          ? (fMinSpinBox.value.toFixed(2) + " – " + fMaxSpinBox.value.toFixed(2) + " GHz")
                                          : (root.calcFreqMin.toFixed(0) + " – " + root.calcFreqMax.toFixed(0) + " MHz"))
                                          + " (" + root.calcFreqMin.toFixed(0) + " – " + root.calcFreqMax.toFixed(0) + " MHz)"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: root.lightMode ? "#1864ab" : "#74c0fc"
                                }
                            }

                            // Channel width
                            RowLayout {
                                spacing: 4
                                Label {
                                    text: qsTr("Max Channel Width (Δf):")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#495057" : "#adb5bd"
                                }
                                Label {
                                    text: (root.calcMaxChannelWidth >= 1000.0
                                          ? ((root.calcMaxChannelWidth / 1000.0).toFixed(2) + " GHz / ")
                                          : "") + root.calcMaxChannelWidth.toFixed(0) + " MHz"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: "#40c057"
                                }
                            }

                            // Total NF
                            RowLayout {
                                spacing: 4
                                Label {
                                    text: qsTr("Total Cascade NF:")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#495057" : "#adb5bd"
                                }
                                Label {
                                    text: root.calcTotalNf.toFixed(2) + " dB"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: root.lightMode ? "#1864ab" : "#74c0fc"
                                }
                            }

                            // System Noise Temp
                            RowLayout {
                                spacing: 4
                                Label {
                                    text: qsTr("System Noise Temp (Tsys):")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#495057" : "#adb5bd"
                                }
                                Label {
                                    text: root.calcSysNoiseTemp.toFixed(1) + " K"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: "#f59f00"
                                }
                            }

                            // G/T
                            RowLayout {
                                spacing: 4
                                Label {
                                    text: qsTr("Antenna Figure of Merit (G/T):")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#495057" : "#adb5bd"
                                }
                                Label {
                                    text: root.calcGOverT.toFixed(2) + " dB/K"
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: "#38d9a9"
                                }
                            }
                        }
                    }
                }
            }
        }

        // ================= TAB 1: IMPORT FROM JSON FILE =================
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.activeTab === 1
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: parent.width
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: importInfoCol.implicitHeight + 28
                    radius: 8
                    color: root.lightMode ? "#f8f9fa" : "#141517"
                    border.color: root.lightMode ? "#dee2e6" : "#2c2e33"
                    border.width: 1

                    ColumnLayout {
                        id: importInfoCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                        Label {
                            text: qsTr("📁 Import Ground Station Configuration File")
                            font.bold: true
                            font.pixelSize: 13
                            color: root.lightMode ? "#212529" : "#ffffff"
                        }
                        Label {
                            text: qsTr("Select a saved .json file containing antenna parameters, or paste the JSON text directly below.")
                            font.pixelSize: 11
                            color: root.lightMode ? "#868e96" : "#909296"
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // Horizontally scrollable row for actions and sample presets
                        Flickable {
                            id: sampleFlickable
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            contentWidth: sampleRow.implicitWidth
                            contentHeight: 38
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            WheelHandler {
                                target: sampleFlickable
                                onWheel: (event) => {
                                    if (event.angleDelta.y !== 0) {
                                        sampleFlickable.contentX = Math.max(0, Math.min(sampleRow.implicitWidth - sampleFlickable.width, sampleFlickable.contentX - event.angleDelta.y))
                                    } else if (event.angleDelta.x !== 0) {
                                        sampleFlickable.contentX = Math.max(0, Math.min(sampleRow.implicitWidth - sampleFlickable.width, sampleFlickable.contentX - event.angleDelta.x))
                                    }
                                }
                            }

                            RowLayout {
                                id: sampleRow
                                height: 38
                                spacing: 8

                                Button {
                                    id: browseBtn
                                    text: qsTr("📂  Browse JSON File...")
                                    height: 36
                                    background: Rectangle {
                                        radius: 6
                                        color: browseBtn.hovered ? "#1c7ed6" : root.accentColor
                                    }
                                    contentItem: Text {
                                        text: browseBtn.text
                                        color: "#ffffff"
                                        font.bold: true
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: root.triggerFileBrowse()
                                }

                                Button {
                                    id: openFolderImportBtn
                                    text: qsTr("📁  Open Stations Folder")
                                    height: 36
                                    background: Rectangle {
                                        radius: 6
                                        color: openFolderImportBtn.hovered ? (root.lightMode ? "#dee2e6" : "#373a40") : (root.lightMode ? "#e9ecef" : "#2c2e33")
                                    }
                                    contentItem: Text {
                                        text: openFolderImportBtn.text
                                        color: root.lightMode ? "#495057" : "#ced4da"
                                        font.bold: true
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        if (root.stationManager) {
                                            root.stationManager.openStationsFolder()
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 1
                                    height: 22
                                    color: root.lightMode ? "#dee2e6" : "#2c2e33"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Quick sample load buttons
                                Label {
                                    text: qsTr("or Samples:")
                                    font.pixelSize: 11
                                    color: root.lightMode ? "#868e96" : "#adb5bd"
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Button {
                                    text: "C-Band"
                                    height: 32
                                    onClicked: root.loadSampleJson("C-band")
                                }
                                Button {
                                    text: "S-Band"
                                    height: 32
                                    onClicked: root.loadSampleJson("S-band")
                                }
                                Button {
                                    text: "X-Band"
                                    height: 32
                                    onClicked: root.loadSampleJson("X-band")
                                }
                                Button {
                                    text: "Ku-Band"
                                    height: 32
                                    onClicked: root.loadSampleJson("Ku-band")
                                }
                                Button {
                                    text: "Ka-Band"
                                    height: 32
                                    onClicked: root.loadSampleJson("Ka-band")
                                }
                            }
                        }

                        // Dedicated prominent horizontal scrollbar
                        Rectangle {
                            id: sampleScrollBarTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            radius: 5
                            color: root.lightMode ? "#e9ecef" : "#1e2024"
                            border.color: root.lightMode ? "#ced4da" : "#2c2e33"
                            border.width: 1

                            Rectangle {
                                id: scrollThumb
                                height: parent.height - 2
                                y: 1
                                radius: 4
                                color: thumbMouse.pressed ? root.accentColor : (thumbMouse.containsMouse ? (root.lightMode ? "#74c0fc" : "#4dabf7") : (root.lightMode ? "#adb5bd" : "#5c5f66"))

                                // Proportional width with a minimum of 40px
                                width: Math.max(40, parent.width * Math.min(1.0, sampleFlickable.width / Math.max(1, sampleRow.implicitWidth)))

                                // Position bound to sampleFlickable.contentX
                                x: {
                                    var maxScroll = Math.max(1, sampleRow.implicitWidth - sampleFlickable.width)
                                    var maxThumbX = parent.width - width - 2
                                    var ratio = Math.max(0, Math.min(1.0, sampleFlickable.contentX / maxScroll))
                                    return 1 + ratio * maxThumbX
                                }

                                MouseArea {
                                    id: thumbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    drag.target: scrollThumb
                                    drag.axis: Drag.XAxis
                                    drag.minimumX: 1
                                    drag.maximumX: sampleScrollBarTrack.width - scrollThumb.width - 1
                                    cursorShape: Qt.PointingHandCursor

                                    onPositionChanged: {
                                        if (drag.active) {
                                            var maxThumbX = sampleScrollBarTrack.width - scrollThumb.width - 2
                                            if (maxThumbX > 0) {
                                                var ratio = (scrollThumb.x - 1) / maxThumbX
                                                var maxScroll = Math.max(0, sampleRow.implicitWidth - sampleFlickable.width)
                                                sampleFlickable.contentX = ratio * maxScroll
                                            }
                                        }
                                    }
                                }
                            }

                            // Click anywhere on track to jump
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    var maxThumbX = parent.width - scrollThumb.width - 2
                                    if (maxThumbX > 0) {
                                        var targetX = Math.max(1, Math.min(maxThumbX, mouse.x - scrollThumb.width / 2))
                                        var ratio = (targetX - 1) / maxThumbX
                                        var maxScroll = Math.max(0, sampleRow.implicitWidth - sampleFlickable.width)
                                        sampleFlickable.contentX = ratio * maxScroll
                                    }
                                }
                            }
                        }
                    }
                }

                // JSON Paste / Direct Input Box with ScrollView and ScrollBar
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: qsTr("JSON Document Content:")
                        font.pixelSize: 11
                        font.bold: true
                        color: root.lightMode ? "#495057" : "#ced4da"
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 200
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
                            id: importTextArea
                            wrapMode: TextEdit.NoWrap
                            font.family: "Consolas, 'Courier New', monospace"
                            font.pixelSize: 11
                            color: root.lightMode ? "#212529" : "#a9e34b"
                            selectByMouse: true
                            placeholderText: qsTr("{\n  \"name\": \"Antenna Station\",\n  \"coordinates\": { \"latitude\": 52.23, \"longitude\": 21.01 },\n  \"rf_configuration\": { ... }\n}")

                            background: Rectangle {
                                radius: 6
                                color: root.lightMode ? "#ffffff" : "#1a1b1e"
                                border.color: importTextArea.activeFocus ? root.accentColor : (root.lightMode ? "#ced4da" : "#373a40")
                            }

                            onTextChanged: root.validateImportJson(importTextArea.text)
                        }
                    }
                }

                // Parse Status / Preview Box
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: importPreviewCol.implicitHeight + 16
                    visible: root.importStatusText !== ""
                    radius: 6
                    color: root.importSuccess
                           ? (root.lightMode ? "#ebfbee" : "#142c1b")
                           : (root.lightMode ? "#fff5f5" : "#2c1414")
                    border.color: root.importSuccess ? "#40c057" : "#fa5252"
                    border.width: 1

                    ColumnLayout {
                        id: importPreviewCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Label {
                            text: root.importStatusText
                            font.bold: true
                            font.pixelSize: 12
                            color: root.importSuccess ? "#2b8a3e" : "#e03131"
                        }

                        Label {
                            visible: root.importSuccess && root.importedStationData !== null
                            text: root.importedStationData
                                  ? qsTr("Station: ") + root.importedStationData.name + " (" + root.importedStationData.operatingBand + ", " + root.importedStationData.polarization + ") • Lat: " + Number(root.importedStationData.latitude).toFixed(3) + "°, Lon: " + Number(root.importedStationData.longitude).toFixed(3) + "° • Tsys: " + Number(root.importedStationData.systemNoiseTempK).toFixed(1) + " K"
                                  : ""
                            font.pixelSize: 11
                            color: root.lightMode ? "#495057" : "#ced4da"
                        }
                    }
                }
            }
        }

        // ================= FOOTER ACTIONS =================
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.lightMode ? "#e9ecef" : "#2c2e33"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Live JSON Preview button (Tab 0 only)
            Button {
                visible: root.activeTab === 0
                text: qsTr("{ } Preview JSON")
                height: 38
                background: Rectangle {
                    radius: 6
                    color: root.lightMode ? "#e9ecef" : "#2c2e33"
                }
                contentItem: Text {
                    text: parent.text
                    color: root.lightMode ? "#495057" : "#ced4da"
                    font.bold: true
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    var data = root.gatherFormData()
                    var json = root.stationManager ? root.stationManager.buildStationJson(data) : JSON.stringify(data, null, 2)
                    previewViewer.jsonContent = json
                    previewViewer.stationName = nameInput.text.trim() || qsTr("Station Configuration")
                    previewViewer.open()
                }
            }

            // Export JSON button (Tab 0 only)
            Button {
                visible: root.activeTab === 0
                text: qsTr("💾  Export JSON")
                height: 38
                background: Rectangle {
                    radius: 6
                    color: root.lightMode ? "#e9ecef" : "#2c2e33"
                }
                contentItem: Text {
                    text: parent.text
                    color: root.lightMode ? "#495057" : "#ced4da"
                    font.bold: true
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    var data = root.gatherFormData()
                    var json = root.stationManager ? root.stationManager.buildStationJson(data) : JSON.stringify(data, null, 2)
                    var defaultName = (nameInput.text.trim().length > 0
                                       ? nameInput.text.trim().toLowerCase().replace(/[^a-z0-9_-]/g, "_")
                                       : "station") + ".json"
                    if (root.stationManager) {
                        var filePath = root.stationManager.saveFileDialog(qsTr("Export Station JSON"), defaultName, "JSON Files (*.json)")
                        if (filePath && filePath.length > 0) {
                            root.stationManager.writeTextFile(filePath, json)
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                id: cancelBtn
                text: qsTr("Cancel")
                height: 38
                Layout.preferredWidth: 80
                background: Rectangle {
                    radius: 6
                    color: root.lightMode ? "#e9ecef" : "#2c2e33"
                }
                contentItem: Text {
                    text: cancelBtn.text
                    color: root.lightMode ? "#495057" : "#ced4da"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.close()
            }

            // Commit Button (Add/Save in Tab 0, Import in Tab 1)
            Button {
                id: commitBtn
                height: 38
                Layout.preferredWidth: root.activeTab === 0 ? 170 : 150
                text: root.activeTab === 0
                      ? (root.editingStationId !== "" ? qsTr("💾  Update Station") : qsTr("💾  Save & Place Station"))
                      : qsTr("📥  Import Station")

                enabled: root.activeTab === 0
                         ? (nameInput.text.trim().length > 0 && !isNaN(latSpinBox.value) && !isNaN(lonSpinBox.value))
                         : (root.importSuccess && root.importedStationData !== null)

                background: Rectangle {
                    radius: 6
                    color: commitBtn.enabled
                           ? (commitBtn.hovered ? "#2b8a3e" : "#2f9e44")
                           : (root.lightMode ? "#ced4da" : "#373a40")
                }

                contentItem: Text {
                    text: commitBtn.text
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    if (root.activeTab === 0) {
                        var stData = root.gatherFormData()
                        root.stationCommitted(stData, root.editingStationId !== "")
                        root.close()
                    } else if (root.activeTab === 1 && root.importedStationData) {
                        root.stationCommitted(root.importedStationData, false)
                        root.close()
                    }
                }
            }
        }
    }

    // Modal JSON previewer
    StationJsonViewer {
        id: previewViewer
        lightMode: root.lightMode
        accentColor: root.accentColor
        stationManager: root.stationManager
    }

    // ================= HELPER FUNCTIONS =================
    function openForCreate() {
        root.editingStationId = ""
        root.activeTab = 0
        nameInput.text = ""
        latSpinBox.value = 52.2297
        lonSpinBox.value = 21.0122
        altSpinBox.value = 150.0
        altSpinBox.optionalEnabled = true
        mobilityCombo.currentIndex = 0
        elevationSpinBox.value = 5.0
        bandCombo.currentIndex = 0
        polCombo.currentIndex = 0
        gainSpinBox.value = 38.5
        lnaNfSpinBox.value = 0.70
        feederLossSpinBox.value = 0.30
        fMinSpinBox.value = 4.000
        fMaxSpinBox.value = 8.000
        importTextArea.text = ""
        root.importStatusText = ""
        root.importSuccess = false
        root.importedStationData = null
        recalculateParameters()
        root.open()
    }

    function openForEdit(station) {
        root.editingStationId = station.stationId
        root.activeTab = 0
        nameInput.text = station.name || ""
        latSpinBox.value = Number(station.latitude) || 0.0
        lonSpinBox.value = Number(station.longitude) || 0.0
        altSpinBox.value = Number(station.altitude) || 0.0
        altSpinBox.optionalEnabled = station.altitudeSpecified !== false
        mobilityCombo.currentIndex = (station.mobility && station.mobility.toLowerCase() === "mobile") ? 1 : 0
        elevationSpinBox.value = Number(station.minElevation) || 5.0

        // Find band index
        var b = (station.operatingBand || "C-band").toLowerCase()
        if (b.indexOf("c") >= 0) bandCombo.currentIndex = 0
        else if (b.indexOf("s") >= 0) bandCombo.currentIndex = 1
        else if (b.indexOf("x") >= 0) bandCombo.currentIndex = 2
        else if (b.indexOf("ku") >= 0) bandCombo.currentIndex = 3
        else if (b.indexOf("ka") >= 0) bandCombo.currentIndex = 4
        else if (b.indexOf("l") >= 0) bandCombo.currentIndex = 5
        else if (b.indexOf("uhf") >= 0) bandCombo.currentIndex = 6
        else if (b.indexOf("vhf") >= 0) bandCombo.currentIndex = 7

        // Polarization
        var p = (station.polarization || "RHCP").toUpperCase()
        if (p.indexOf("RHCP") >= 0) polCombo.currentIndex = 0
        else if (p.indexOf("LHCP") >= 0) polCombo.currentIndex = 1
        else polCombo.currentIndex = 2

        gainSpinBox.value = Number(station.antennaGain) || 38.5
        lnaNfSpinBox.value = Number(station.lnaNf) || 0.70
        feederLossSpinBox.value = Number(station.feederLoss) || 0.30

        if (station.freqMinGhz !== undefined && station.freqMinGhz > 0) {
            fMinSpinBox.value = Number(station.freqMinGhz)
        } else if (station.freqMinMhz !== undefined && station.freqMinMhz > 0) {
            fMinSpinBox.value = Number(station.freqMinMhz) / 1000.0
        } else if (station.frequency_min_mhz !== undefined && station.frequency_min_mhz > 0) {
            fMinSpinBox.value = Number(station.frequency_min_mhz) / 1000.0
        } else {
            fMinSpinBox.value = 4.000
        }

        if (station.freqMaxGhz !== undefined && station.freqMaxGhz > 0) {
            fMaxSpinBox.value = Number(station.freqMaxGhz)
        } else if (station.freqMaxMhz !== undefined && station.freqMaxMhz > 0) {
            fMaxSpinBox.value = Number(station.freqMaxMhz) / 1000.0
        } else if (station.frequency_max_mhz !== undefined && station.frequency_max_mhz > 0) {
            fMaxSpinBox.value = Number(station.frequency_max_mhz) / 1000.0
        } else {
            fMaxSpinBox.value = 8.000
        }

        recalculateParameters()
        root.open()
    }

    function setCoordinates(lat, lon) {
        latSpinBox.value = lat
        lonSpinBox.value = lon
        recalculateParameters()
    }

    function applyBandPreset(index) {
        switch (index) {
            case 0: // C-band
                fMinSpinBox.value = 4.000
                fMaxSpinBox.value = 8.000
                gainSpinBox.value = 38.5
                lnaNfSpinBox.value = 0.70
                feederLossSpinBox.value = 0.30
                break
            case 1: // S-band
                fMinSpinBox.value = 2.000
                fMaxSpinBox.value = 4.000
                gainSpinBox.value = 30.0
                lnaNfSpinBox.value = 0.85
                feederLossSpinBox.value = 0.25
                break
            case 2: // X-band
                fMinSpinBox.value = 8.000
                fMaxSpinBox.value = 12.000
                gainSpinBox.value = 43.5
                lnaNfSpinBox.value = 0.75
                feederLossSpinBox.value = 0.35
                break
            case 3: // Ku-band
                fMinSpinBox.value = 12.000
                fMaxSpinBox.value = 18.000
                gainSpinBox.value = 48.0
                lnaNfSpinBox.value = 0.90
                feederLossSpinBox.value = 0.40
                break
            case 4: // Ka-band
                fMinSpinBox.value = 26.500
                fMaxSpinBox.value = 40.000
                gainSpinBox.value = 54.0
                lnaNfSpinBox.value = 1.30
                feederLossSpinBox.value = 0.60
                break
            case 5: // L-band
                fMinSpinBox.value = 1.000
                fMaxSpinBox.value = 2.000
                gainSpinBox.value = 24.0
                lnaNfSpinBox.value = 0.80
                feederLossSpinBox.value = 0.20
                break
            case 6: // UHF
                fMinSpinBox.value = 0.400
                fMaxSpinBox.value = 0.470
                gainSpinBox.value = 16.0
                lnaNfSpinBox.value = 1.10
                feederLossSpinBox.value = 0.20
                break
            case 7: // VHF
                fMinSpinBox.value = 0.136
                fMaxSpinBox.value = 0.174
                gainSpinBox.value = 12.0
                lnaNfSpinBox.value = 1.50
                feederLossSpinBox.value = 0.20
                break
        }
        recalculateParameters()
    }

    function recalculateParameters() {
        var rawBand = bandCombo.currentText
        var bandName = rawBand.split(" ")[0]

        var fMinMhz = fMinSpinBox.value * 1000.0
        var fMaxMhz = fMaxSpinBox.value * 1000.0

        if (root.stationManager) {
            var der = root.stationManager.computeDerivedParameters(
                bandName,
                lnaNfSpinBox.value,
                feederLossSpinBox.value,
                gainSpinBox.value,
                fMinMhz,
                fMaxMhz
            )
            root.calcFreqMin = der.freq_min_mhz
            root.calcFreqMax = der.freq_max_mhz
            root.calcMaxChannelWidth = der.max_channel_width_mhz
            root.calcTotalNf = der.total_noise_figure_db
            root.calcRecNoiseTemp = der.receiver_noise_temp_k
            root.calcSysNoiseTemp = der.system_noise_temp_k
            root.calcGOverT = der.g_over_t_db_k
        } else {
            // Pure JS fallback
            root.calcFreqMin = fMinMhz
            root.calcFreqMax = fMaxMhz
            root.calcMaxChannelWidth = Math.max(0, fMaxMhz - fMinMhz)
            root.calcTotalNf = lnaNfSpinBox.value + feederLossSpinBox.value
            var fLin = Math.pow(10.0, root.calcTotalNf / 10.0)
            root.calcRecNoiseTemp = 290.0 * (fLin - 1.0)
            root.calcSysNoiseTemp = root.calcRecNoiseTemp + 50.0
            root.calcGOverT = gainSpinBox.value - 10.0 * (Math.log(root.calcSysNoiseTemp) / Math.LN10)
        }
    }

    function gatherFormData() {
        var rawBand = bandCombo.currentText
        var bandName = rawBand.split(" ")[0]

        var data = {
            stationId: root.editingStationId,
            name: nameInput.text.trim(),
            latitude: latSpinBox.value,
            longitude: lonSpinBox.value,
            altitude: altSpinBox.optionalEnabled ? altSpinBox.value : 0.0,
            altitudeSpecified: altSpinBox.optionalEnabled,
            mobility: mobilityCombo.currentText,
            minElevation: elevationSpinBox.value,
            operatingBand: bandName,
            polarization: polCombo.currentText,
            antennaGain: gainSpinBox.value,
            lnaNf: lnaNfSpinBox.value,
            feederLoss: feederLossSpinBox.value,
            freqMinMhz: root.calcFreqMin,
            freqMaxMhz: root.calcFreqMax,
            freqMinGhz: fMinSpinBox.value,
            freqMaxGhz: fMaxSpinBox.value,
            maxChannelWidthMhz: root.calcMaxChannelWidth,
            totalNoiseFigureDb: root.calcTotalNf,
            systemNoiseTempK: root.calcSysNoiseTemp,
            gOverT: root.calcGOverT
        }

        if (root.stationManager) {
            data["stationJson"] = root.stationManager.buildStationJson(data)
        }
        return data
    }

    function triggerFileBrowse() {
        if (!root.stationManager) return
        var path = root.stationManager.openFileDialog(qsTr("Open Station Configuration JSON"), "JSON Files (*.json)")
        if (path && path.length > 0) {
            var content = root.stationManager.readTextFile(path)
            if (content && content.length > 0) {
                importTextArea.text = content
                validateImportJson(content)
            }
        }
    }

    function loadSampleJson(band) {
        if (!root.stationManager) return
        var json = root.stationManager.getSampleStationJson(band)
        importTextArea.text = json
        validateImportJson(json)
    }

    function validateImportJson(text) {
        if (!text || text.trim().length === 0) {
            root.importStatusText = ""
            root.importSuccess = false
            root.importedStationData = null
            return
        }

        if (root.stationManager) {
            var res = root.stationManager.parseStationJson(text)
            if (res.valid) {
                root.importSuccess = true
                root.importedStationData = res
                root.importStatusText = qsTr("✓ Valid station configuration loaded!")
            } else {
                root.importSuccess = false
                root.importedStationData = null
                root.importStatusText = qsTr("⚠️ ") + (res.error || qsTr("Invalid station JSON format"))
            }
        }
    }
}
