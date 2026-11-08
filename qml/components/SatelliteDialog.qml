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
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 640, 660)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 40 : 680, 700)
    padding: 0

    readonly property var modulationPresets: [
        { name: "BPSK", bits: 1 },
        { name: "QPSK", bits: 2 },
        { name: "OQPSK", bits: 2 },
        { name: "pi/4-QPSK", bits: 2 },
        { name: "8PSK", bits: 3 },
        { name: "8QAM", bits: 3 },
        { name: "16APSK", bits: 4 },
        { name: "16QAM", bits: 4 },
        { name: "32APSK", bits: 5 },
        { name: "32QAM", bits: 5 },
        { name: "64APSK", bits: 6 },
        { name: "64QAM", bits: 6 },
        { name: "128APSK", bits: 7 },
        { name: "256APSK", bits: 8 },
        { name: "256QAM", bits: 8 }
    ]

    function deriveBitsPerSymbol(modStr) {
        if (!modStr) return 2.0
        var upper = modStr.trim().toUpperCase()
        for (var i = 0; i < modulationPresets.length; i++) {
            if (modulationPresets[i].name.toUpperCase() === upper) {
                return modulationPresets[i].bits
            }
        }
        var mMatch = upper.match(/^(\d+)/)
        if (mMatch) {
            var val = parseInt(mMatch[1], 10)
            if (val > 1 && (val & (val - 1)) === 0) {
                return Math.round(Math.log2(val))
            }
        }
        return 2.0
    }

    function parseTleEpochDisplay(tle1) {
        if (!tle1 || tle1.length < 32) return "N/A"
        var raw = tle1.substring(18, 32).trim()
        var yr2 = parseInt(raw.substring(0, 2), 10)
        var doyFloat = parseFloat(raw.substring(2))
        if (isNaN(yr2) || isNaN(doyFloat)) return raw
        var year = yr2 < 57 ? (2000 + yr2) : (1900 + yr2)
        var dayInt = Math.floor(doyFloat)
        var fracDay = doyFloat - dayInt
        var totalSec = Math.round(fracDay * 86400)
        var hrs = Math.floor(totalSec / 3600)
        var mins = Math.floor((totalSec % 3600) / 60)
        var secs = totalSec % 60
        var dt = new Date(Date.UTC(year, 0, dayInt, hrs, mins, secs))
        function pad2(n) { return n < 10 ? ("0" + n) : String(n) }
        return pad2(dt.getUTCDate()) + "." + pad2(dt.getUTCMonth() + 1) + "." + dt.getUTCFullYear() +
               " " + pad2(dt.getUTCHours()) + ":" + pad2(dt.getUTCMinutes()) + ":" + pad2(dt.getUTCSeconds())
    }

    background: Rectangle {
        radius: 12
        color: satDialogRoot.lightMode ? "#ffffff" : "#141720"
        border.color: satDialogRoot.lightMode ? "#ced4da" : "#2d3345"
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
            color: closeCrossBtn.hovered ? (satDialogRoot.lightMode ? "#e9ecef" : "#2c3245") : "transparent"
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

    function openForNew() {
        editingSatId = ""
        satNameInput.text = "ISS (ZARYA)"
        tle1Input.text = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
        tle2Input.text = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
        freqGhzInput.text = "5.85"
        bandwidthMhzInput.text = "20"
        modulationInput.text = "OQPSK"
        gammaInput.text = "1.24"
        alphaInput.text = "0.35"
        txPowerInput.text = "33.0"
        txGainInput.text = "3.0"
        validationStatusText.text = ""
        open()
    }

    function openForEdit(satModelItem) {
        if (!satModelItem) {
            openForNew()
            return
        }
        editingSatId = satModelItem.satId || ""
        satNameInput.text = satModelItem.name || ""
        tle1Input.text = satModelItem.tle1 || ""
        tle2Input.text = satModelItem.tle2 || ""

        var fMhz = satModelItem.carrierFreqMhz !== undefined ? Number(satModelItem.carrierFreqMhz) : 5850.0
        freqGhzInput.text = (fMhz / 1000.0).toFixed(2).replace(/\.?0+$/, "")

        var bwKhz = satModelItem.channelBandwidthKhz !== undefined ? Number(satModelItem.channelBandwidthKhz) : 20000.0
        bandwidthMhzInput.text = (bwKhz / 1000.0).toFixed(3).replace(/\.?0+$/, "")

        modulationInput.text = satModelItem.modulation || "OQPSK"
        var gVal = satModelItem.codeEfficiencyCoef !== undefined ? Number(satModelItem.codeEfficiencyCoef) : 1.24
        gammaInput.text = gVal.toFixed(2)

        var aVal = satModelItem.rolloffAlpha !== undefined ? Number(satModelItem.rolloffAlpha) : 0.35
        alphaInput.text = aVal.toFixed(2)

        var pTx = satModelItem.txPowerDbm !== undefined ? Number(satModelItem.txPowerDbm) : 33.0
        txPowerInput.text = pTx.toFixed(1)

        var gTx = satModelItem.txAntennaGainDbi !== undefined ? Number(satModelItem.txAntennaGainDbi) : 3.0
        txGainInput.text = gTx.toFixed(1)

        validationStatusText.text = ""
        open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
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
                    text: satDialogRoot.editingSatId !== "" ? qsTr("Satellite Configuration") : qsTr("Add New Satellite")
                    font.bold: true
                    font.pixelSize: 16
                    color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                }

                Label {
                    text: qsTr("Configure TLE orbital elements, RF carrier, bandwidth, modulation, coder efficiency Γ & roll-off α")
                    font.pixelSize: 11
                    color: satDialogRoot.lightMode ? "#6c757d" : "#909296"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: satDialogRoot.lightMode ? "#dee2e6" : "#2d3345"
        }

        // ================= INPUT FIELDS =================
        ScrollView {
            id: satScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            ColumnLayout {
                width: satScrollView.availableWidth
                spacing: 12

                // 1. Satellite Name + Quick Presets
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("1. Satellite Name / Identifier")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            height: 22
                            text: qsTr("📋 ISS Preset")
                            background: Rectangle {
                                radius: 4
                                color: satDialogRoot.lightMode ? "#e7f5ff" : "#182842"
                                border.color: "#339af0"
                            }
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 10
                                font.bold: true
                                color: "#339af0"
                                leftPadding: 6; rightPadding: 6
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
                            height: 22
                            text: qsTr("📋 POLYITAN-3 Preset")
                            background: Rectangle {
                                radius: 4
                                color: satDialogRoot.lightMode ? "#fff9db" : "#2b2512"
                                border.color: "#f59f00"
                            }
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 10
                                font.bold: true
                                color: "#f59f00"
                                leftPadding: 6; rightPadding: 6
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

                    TextField {
                        id: satNameInput
                        Layout.fillWidth: true
                        height: 34
                        placeholderText: qsTr("e.g., ISS (ZARYA), POLYITAN-3-PUT")
                        color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                        background: Rectangle {
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                            border.color: satNameInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                        }
                    }
                }

                // 2. TLE Line 1 & Line 2
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Label {
                            text: qsTr("2. NORAD Two-Line Element Set (TLE)")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }
                        Rectangle {
                            height: 18
                            width: epochBadgeText.implicitWidth + 10
                            radius: 4
                            color: satDialogRoot.lightMode ? "#f1f3f5" : "#1e2433"
                            border.color: satDialogRoot.lightMode ? "#ced4da" : "#373a40"
                            Text {
                                id: epochBadgeText
                                anchors.centerIn: parent
                                text: "TLE=" + satDialogRoot.parseTleEpochDisplay(tle1Input.text)
                                font.pixelSize: 10
                                font.family: "monospace"
                                color: satDialogRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: "L1: " + tle1Input.text.length + "/69 • L2: " + tle2Input.text.length + "/69"
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: (tle1Input.text.trim().length >= 60 && tle2Input.text.trim().length >= 60) ? "#40c057" : "#fa5252"
                        }
                    }

                    TextField {
                        id: tle1Input
                        Layout.fillWidth: true
                        height: 32
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

                    TextField {
                        id: tle2Input
                        Layout.fillWidth: true
                        height: 32
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

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: satDialogRoot.lightMode ? "#e9ecef" : "#222736"
                }

                // 3. RF Downlink Parameters (Carrier Frequency f, Bandwidth B, TX Power, TX Gain)
                Label {
                    text: qsTr("3. Downlink RF & Channel Parameters (Used in Link Budget & SNR Calculations)")
                    font.bold: true
                    font.pixelSize: 12
                    color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 10

                    // Carrier Frequency f (GHz)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: qsTr("Carrier Frequency f (GHz)")
                                font.bold: true
                                font.pixelSize: 11
                                color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: {
                                    var v = parseFloat(freqGhzInput.text)
                                    return !isNaN(v) ? ("= " + (v * 1000.0).toFixed(1) + " MHz") : ""
                                }
                                font.pixelSize: 10
                                font.family: "monospace"
                                color: "#339af0"
                            }
                        }

                        TextField {
                            id: freqGhzInput
                            Layout.fillWidth: true
                            height: 34
                            text: "5.85"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: 12
                            placeholderText: "e.g. 5.85"
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: freqGhzInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }
                    }

                    // Channel Bandwidth B (MHz) - Manual writing + quick chips
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                text: qsTr("Bandwidth B (MHz)")
                                font.bold: true
                                font.pixelSize: 11
                                color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                            }
                            Item { Layout.fillWidth: true }
                            Repeater {
                                model: ["5", "10", "20", "40"]
                                Button {
                                    height: 18
                                    padding: 0
                                    background: Rectangle {
                                        radius: 3
                                        color: bandwidthMhzInput.text.trim() === modelData ? "#339af0" : (satDialogRoot.lightMode ? "#e9ecef" : "#252b3b")
                                    }
                                    contentItem: Text {
                                        text: modelData + "M"
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: bandwidthMhzInput.text.trim() === modelData ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                        leftPadding: 4; rightPadding: 4
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: bandwidthMhzInput.text = modelData
                                }
                            }
                        }

                        TextField {
                            id: bandwidthMhzInput
                            Layout.fillWidth: true
                            height: 34
                            text: "20"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: 12
                            placeholderText: qsTr("Type bandwidth in MHz (e.g. 20)")
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: bandwidthMhzInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }
                    }

                    // TX Power (dBm)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("TX Power (dBm)")
                            font.bold: true
                            font.pixelSize: 11
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        TextField {
                            id: txPowerInput
                            Layout.fillWidth: true
                            height: 32
                            text: "33.0"
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: txPowerInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }
                    }

                    // TX Antenna Gain (dBi)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("TX Antenna Gain (dBi)")
                            font.bold: true
                            font.pixelSize: 11
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        TextField {
                            id: txGainInput
                            Layout.fillWidth: true
                            height: 32
                            text: "3.0"
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: txGainInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: satDialogRoot.lightMode ? "#e9ecef" : "#222736"
                }

                // 4. Modulation & Coding Parameters (Mod, Coder Efficiency Γ, Roll-off alpha)
                Label {
                    text: qsTr("4. Modulation & Coding Parameters (Mod, Coder Efficiency Γ, Roll-off α)")
                    font.bold: true
                    font.pixelSize: 12
                    color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 8

                    // Modulation
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: qsTr("Modulation")
                                font.bold: true
                                font.pixelSize: 11
                                color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                height: 16
                                width: bitsBadge.implicitWidth + 8
                                radius: 3
                                color: satDialogRoot.lightMode ? "#e7f5ff" : "#102a45"
                                border.color: "#339af0"
                                Text {
                                    id: bitsBadge
                                    anchors.centerIn: parent
                                    text: satDialogRoot.deriveBitsPerSymbol(modulationInput.text) + " b/sym"
                                    font.pixelSize: 9
                                    font.bold: true
                                    color: "#339af0"
                                }
                            }
                        }

                        TextField {
                            id: modulationInput
                            Layout.fillWidth: true
                            height: 34
                            text: "OQPSK"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: 12
                            placeholderText: "OQPSK, QPSK, 8PSK..."
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: modulationInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: ["BPSK", "QPSK", "OQPSK", "8PSK", "16APSK", "64QAM"]
                                Button {
                                    height: 18
                                    padding: 0
                                    background: Rectangle {
                                        radius: 3
                                        color: modulationInput.text.trim().toUpperCase() === modelData ? "#f59f00" : (satDialogRoot.lightMode ? "#e9ecef" : "#252b3b")
                                    }
                                    contentItem: Text {
                                        text: modelData
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: modulationInput.text.trim().toUpperCase() === modelData ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                        leftPadding: 4; rightPadding: 4
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: modulationInput.text = modelData
                                }
                            }
                        }
                    }

                    // Coder Efficiency Γ
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("Coder Efficiency (Γ)")
                            font.bold: true
                            font.pixelSize: 11
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        TextField {
                            id: gammaInput
                            Layout.fillWidth: true
                            height: 34
                            text: "1.24"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: 12
                            placeholderText: "e.g. 1.24"
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: gammaInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: ["1.00", "1.24", "1.35", "1.60"]
                                Button {
                                    height: 18
                                    padding: 0
                                    background: Rectangle {
                                        radius: 3
                                        color: gammaInput.text.trim() === modelData ? "#f59f00" : (satDialogRoot.lightMode ? "#e9ecef" : "#252b3b")
                                    }
                                    contentItem: Text {
                                        text: "Γ=" + modelData
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: gammaInput.text.trim() === modelData ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                        leftPadding: 4; rightPadding: 4
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: gammaInput.text = modelData
                                }
                            }
                        }
                    }

                    // Roll-off Factor alpha
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Label {
                            text: qsTr("Roll-off Factor (alpha)")
                            font.bold: true
                            font.pixelSize: 11
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        TextField {
                            id: alphaInput
                            Layout.fillWidth: true
                            height: 34
                            text: "0.35"
                            font.family: "monospace"
                            font.bold: true
                            font.pixelSize: 12
                            placeholderText: "e.g. 0.35"
                            color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                            background: Rectangle {
                                radius: 6
                                color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                border.color: alphaInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Repeater {
                                model: ["0.20", "0.25", "0.35", "0.50"]
                                Button {
                                    height: 18
                                    padding: 0
                                    background: Rectangle {
                                        radius: 3
                                        color: alphaInput.text.trim() === modelData ? "#f59f00" : (satDialogRoot.lightMode ? "#e9ecef" : "#252b3b")
                                    }
                                    contentItem: Text {
                                        text: "α=" + modelData
                                        font.pixelSize: 9
                                        font.bold: true
                                        color: alphaInput.text.trim() === modelData ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                        leftPadding: 4; rightPadding: 4
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: alphaInput.text = modelData
                                }
                            }
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
                id: cancelBtn
                height: 38
                Layout.preferredWidth: 90
                text: qsTr("Cancel")
                background: Rectangle {
                    radius: 6
                    color: satDialogRoot.lightMode ? "#e9ecef" : "#252b3b"
                }
                contentItem: Text {
                    text: cancelBtn.text
                    font.bold: true
                    font.pixelSize: 12
                    color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: satDialogRoot.close()
            }

            Button {
                id: commitBtn
                Layout.fillWidth: true
                height: 38
                enabled: satNameInput.text.trim().length > 0 &&
                         tle1Input.text.trim().length >= 60 &&
                         tle2Input.text.trim().length >= 60

                text: satDialogRoot.editingSatId !== "" ? qsTr("💾  Save Satellite Configuration") : qsTr("🚀  Calculate Orbit & Add")

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

                    var fGhz = parseFloat(freqGhzInput.text.replace(/,/g, "."))
                    if (isNaN(fGhz) || fGhz <= 0) fGhz = 5.85
                    var fMhz = fGhz * 1000.0

                    var bwMhz = parseFloat(bandwidthMhzInput.text.replace(/,/g, "."))
                    if (isNaN(bwMhz) || bwMhz <= 0) bwMhz = 20.0
                    var bwKhz = bwMhz * 1000.0

                    var modStr = modulationInput.text.trim() || "OQPSK"
                    var bitsSym = satDialogRoot.deriveBitsPerSymbol(modStr)

                    var gammaVal = parseFloat(gammaInput.text.replace(/,/g, "."))
                    if (isNaN(gammaVal) || gammaVal <= 0) gammaVal = 1.24

                    var alphaVal = parseFloat(alphaInput.text.replace(/,/g, "."))
                    if (isNaN(alphaVal) || alphaVal < 0) alphaVal = 0.35

                    var pTx = parseFloat(txPowerInput.text.replace(/,/g, "."))
                    if (isNaN(pTx)) pTx = 33.0

                    var gTx = parseFloat(txGainInput.text.replace(/,/g, "."))
                    if (isNaN(gTx)) gTx = 3.0

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
                            carrierFreqMhz: fMhz,
                            channelBandwidthKhz: bwKhz,
                            modulation: modStr,
                            bitsPerSymbol: bitsSym,
                            codeEfficiencyCoef: gammaVal,
                            rolloffAlpha: alphaVal,
                            txPowerDbm: pTx,
                            txAntennaGainDbi: gTx,
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
