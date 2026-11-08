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
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 700, 720)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 40 : 720, 740)
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

    ListModel {
        id: codeRateModel
    }

    function resetCodeRateTableToPolyitan() {
        codeRateModel.clear()
        codeRateModel.append({ name: "R1", rate: 0.910, hw: "0" })
        codeRateModel.append({ name: "R2", rate: 0.830, hw: "1" })
        codeRateModel.append({ name: "R3", rate: 0.700, hw: "2" })
        codeRateModel.append({ name: "R4", rate: 0.570, hw: "3" })
        codeRateModel.append({ name: "R5", rate: 0.410, hw: "4" })
        codeRateModel.append({ name: "R6", rate: 0.285, hw: "5" })
        codeRateModel.append({ name: "R7", rate: 0.190, hw: "6" })
    }

    function getCodeRateTableArray() {
        var arr = []
        for (var i = 0; i < codeRateModel.count; i++) {
            var item = codeRateModel.get(i)
            arr.push({
                name: item.name,
                rate: Number(item.rate),
                hw: String(item.hw)
            })
        }
        return arr
    }

    function loadCodeRateTableFromArray(arr) {
        codeRateModel.clear()
        if (arr && arr.length > 0) {
            for (var i = 0; i < arr.length; i++) {
                codeRateModel.append({
                    name: arr[i].name || ("R" + (i + 1)),
                    rate: Number(arr[i].rate !== undefined ? arr[i].rate : 0.5),
                    hw: String(arr[i].hw !== undefined ? arr[i].hw : i)
                })
            }
        } else {
            resetCodeRateTableToPolyitan()
        }
    }

    // CelesTrak Search & TLE Mode State
    property bool tleModeCelestrak: false
    property bool celestrakLoading: false
    property string celestrakStatusMessage: ""
    property string celestrakStatusType: "info" // "info", "success", "error"
    property var celestrakResults: []

    function parseCelestrakTleResponse(rawText) {
        if (!rawText) return []
        var lines = rawText.split(/\r?\n/)
        var cleanLines = []
        for (var i = 0; i < lines.length; i++) {
            var tr = lines[i].trim()
            if (tr.length > 0) {
                cleanLines.push(tr)
            }
        }
        var results = []
        var j = 0
        while (j < cleanLines.length) {
            var l = cleanLines[j]
            if (l.startsWith("1 ") && j + 1 < cleanLines.length && cleanLines[j + 1].startsWith("2 ")) {
                var satName = (j > 0 && !cleanLines[j - 1].startsWith("1 ") && !cleanLines[j - 1].startsWith("2 "))
                              ? cleanLines[j - 1]
                              : ("SAT-" + l.substring(2, 7).trim())
                var catnr = l.substring(2, 7).trim()
                results.push({
                    name: satName,
                    catnr: catnr,
                    tle1: l,
                    tle2: cleanLines[j + 1]
                })
                j += 2
            } else {
                j++
            }
        }
        return results
    }

    function searchCelestrak(query) {
        if (!query || query.trim().length === 0) {
            celestrakStatusMessage = qsTr("Please enter a satellite name or NORAD ID.")
            celestrakStatusType = "info"
            return
        }
        var q = query.trim()
        var isCatnr = /^\d+$/.test(q)
        var param = isCatnr ? ("CATNR=" + encodeURIComponent(q)) : ("NAME=" + encodeURIComponent(q))
        var url = "https://celestrak.org/NORAD/elements/gp.php?" + param + "&FORMAT=TLE"

        celestrakLoading = true
        celestrakStatusMessage = qsTr("Connecting to CelesTrak...")
        celestrakStatusType = "info"
        celestrakResults = []

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                celestrakLoading = false
                if (xhr.status === 200) {
                    var text = xhr.responseText.trim()
                    if (text.indexOf("No GP data found") !== -1 || text.length === 0) {
                        celestrakStatusMessage = qsTr("No satellite found on CelesTrak for '") + q + "'"
                        celestrakStatusType = "error"
                        return
                    }
                    var list = parseCelestrakTleResponse(text)
                    if (list.length === 0) {
                        celestrakStatusMessage = qsTr("CelesTrak returned data but no valid TLE lines were found.")
                        celestrakStatusType = "error"
                        return
                    }
                    celestrakResults = list
                    if (list.length === 1) {
                        applyCelestrakSatellite(list[0])
                        celestrakStatusMessage = qsTr("✓ Loaded ") + list[0].name + " (NORAD " + list[0].catnr + ")"
                        celestrakStatusType = "success"
                    } else {
                        celestrakStatusMessage = qsTr("Found ") + list.length + qsTr(" matching satellites. Select one below:")
                        celestrakStatusType = "success"
                    }
                } else {
                    celestrakStatusMessage = qsTr("CelesTrak request failed (HTTP ") + xhr.status + ")"
                    celestrakStatusType = "error"
                }
            }
        }
        xhr.onerror = function() {
            celestrakLoading = false
            celestrakStatusMessage = qsTr("Network error connecting to CelesTrak. Check internet connection.")
            celestrakStatusType = "error"
        }
        xhr.send()
    }

    function applyCelestrakSatellite(satItem) {
        if (!satItem) return
        tle1Input.text = satItem.tle1
        tle2Input.text = satItem.tle2
        if (satNameInput.text.trim() === "" || satNameInput.text.startsWith("Satellite") || satNameInput.text === "POLYITAN-3-PUT (LEO)" || satNameInput.text === "ISS (ZARYA)") {
            satNameInput.text = satItem.name
        }
        validationStatusText.text = ""
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
        resetCodeRateTableToPolyitan()
        codeRateRegisterInput.text = "fpgatrx/code_rate"
        tleModeCelestrak = false
        celestrakSearchInput.text = ""
        celestrakStatusMessage = ""
        celestrakResults = []
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

        loadCodeRateTableFromArray(satModelItem.codeRateTable)
        codeRateRegisterInput.text = satModelItem.codeRateRegister || "fpgatrx/code_rate"
        tleModeCelestrak = false
        celestrakSearchInput.text = ""
        celestrakStatusMessage = ""
        celestrakResults = []

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
                                freqGhzInput.text = "5.84"
                                bandwidthMhzInput.text = "10"
                                modulationInput.text = "QPSK"
                                satDialogRoot.resetCodeRateTableToPolyitan()
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

                // 2. NORAD Orbital Elements (TLE) - CelesTrak Search & Manual Toggle
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("2. NORAD Orbital Elements (TLE)")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        // Epoch Badge
                        Rectangle {
                            height: 20
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

                        // Mode Segmented Toggle: [ 🌐 CelesTrak Search | ✏️ Manual TLE ]
                        Rectangle {
                            height: 26
                            width: modeToggleRow.implicitWidth + 4
                            radius: 6
                            color: satDialogRoot.lightMode ? "#e9ecef" : "#1a1f2c"
                            border.color: satDialogRoot.lightMode ? "#ced4da" : "#2d3345"

                            RowLayout {
                                id: modeToggleRow
                                anchors.centerIn: parent
                                spacing: 2

                                Rectangle {
                                    width: btnCelestrakText.implicitWidth + 14
                                    height: 22
                                    radius: 4
                                    color: satDialogRoot.tleModeCelestrak ? "#339af0" : "transparent"
                                    Text {
                                        id: btnCelestrakText
                                        anchors.centerIn: parent
                                        text: qsTr("🌐 CelesTrak Search")
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: satDialogRoot.tleModeCelestrak ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: satDialogRoot.tleModeCelestrak = true
                                    }
                                }

                                Rectangle {
                                    width: btnManualText.implicitWidth + 14
                                    height: 22
                                    radius: 4
                                    color: !satDialogRoot.tleModeCelestrak ? "#339af0" : "transparent"
                                    Text {
                                        id: btnManualText
                                        anchors.centerIn: parent
                                        text: qsTr("✏️ Manual TLE")
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: !satDialogRoot.tleModeCelestrak ? "#ffffff" : (satDialogRoot.lightMode ? "#495057" : "#adb5bd")
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: satDialogRoot.tleModeCelestrak = false
                                    }
                                }
                            }
                        }
                    }

                    // --- CELESTRAK SEARCH VIEW ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: satDialogRoot.tleModeCelestrak

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: celestrakSearchInput
                                Layout.fillWidth: true
                                height: 32
                                placeholderText: qsTr("Enter Satellite Name (e.g. ISS, POLYITAN, NOAA) or NORAD ID (e.g. 25544)...")
                                font.pixelSize: 11
                                color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                                background: Rectangle {
                                    radius: 6
                                    color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                                    border.color: celestrakSearchInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                                }
                                onAccepted: satDialogRoot.searchCelestrak(text)
                            }

                            Button {
                                id: celestrakSearchBtn
                                height: 32
                                enabled: !satDialogRoot.celestrakLoading && celestrakSearchInput.text.trim().length > 0
                                background: Rectangle {
                                    radius: 6
                                    color: parent.enabled ? (parent.hovered ? "#228be6" : "#339af0") : (satDialogRoot.lightMode ? "#e9ecef" : "#222736")
                                }
                                contentItem: RowLayout {
                                    spacing: 4
                                    Text {
                                        text: satDialogRoot.celestrakLoading ? "⏳" : "🔍"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: satDialogRoot.celestrakLoading ? qsTr("Searching...") : qsTr("Fetch TLE")
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: celestrakSearchBtn.enabled ? "#ffffff" : (satDialogRoot.lightMode ? "#adb5bd" : "#6c757d")
                                    }
                                }
                                onClicked: satDialogRoot.searchCelestrak(celestrakSearchInput.text)
                            }
                        }

                        // Search feedback / status banner
                        Rectangle {
                            Layout.fillWidth: true
                            height: 26
                            visible: satDialogRoot.celestrakStatusMessage !== ""
                            radius: 4
                            color: {
                                if (satDialogRoot.celestrakStatusType === "success") return (satDialogRoot.lightMode ? "#ebfbee" : "#102a18")
                                if (satDialogRoot.celestrakStatusType === "error") return (satDialogRoot.lightMode ? "#fff5f5" : "#2f1517")
                                return (satDialogRoot.lightMode ? "#e7f5ff" : "#122338")
                            }
                            border.color: {
                                if (satDialogRoot.celestrakStatusType === "success") return "#40c057"
                                if (satDialogRoot.celestrakStatusType === "error") return "#fa5252"
                                return "#339af0"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: satDialogRoot.celestrakStatusMessage
                                font.pixelSize: 10
                                font.bold: true
                                color: {
                                    if (satDialogRoot.celestrakStatusType === "success") return "#40c057"
                                    if (satDialogRoot.celestrakStatusType === "error") return "#fa5252"
                                    return "#339af0"
                                }
                            }
                        }

                        // Multiple Results Selection List
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Math.min(celestrakListCol.implicitHeight + 8, 120)
                            Layout.preferredHeight: implicitHeight
                            visible: satDialogRoot.celestrakResults.length > 1
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#161a25"
                            border.color: satDialogRoot.lightMode ? "#dee2e6" : "#2d3345"
                            clip: true

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 4
                                contentWidth: availableWidth

                                ColumnLayout {
                                    id: celestrakListCol
                                    width: parent.width
                                    spacing: 4

                                    Repeater {
                                        model: satDialogRoot.celestrakResults
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            height: 28
                                            radius: 4
                                            color: resHover.hovered ? (satDialogRoot.lightMode ? "#e7f5ff" : "#1e2e48") : "transparent"

                                            MouseArea {
                                                id: resHover
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: satDialogRoot.applyCelestrakSatellite(modelData)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 8

                                                Text {
                                                    text: modelData.name
                                                    font.bold: true
                                                    font.pixelSize: 11
                                                    color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                                                }

                                                Text {
                                                    text: "NORAD ID: " + modelData.catnr
                                                    font.pixelSize: 10
                                                    font.family: "monospace"
                                                    color: "#339af0"
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: (tle1Input.text === modelData.tle1) ? qsTr("✓ Selected") : qsTr("Select ➔")
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    color: (tle1Input.text === modelData.tle1) ? "#40c057" : "#339af0"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Loaded TLE Summary Box (shows current L1 & L2 in CelesTrak mode)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: 6
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#11141c"
                            border.color: satDialogRoot.lightMode ? "#e9ecef" : "#232838"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 2

                                Text {
                                    text: "L1: " + (tle1Input.text.trim().length > 0 ? tle1Input.text : qsTr("(No TLE line 1 loaded)"))
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    color: tle1Input.text.trim().length >= 60 ? (satDialogRoot.lightMode ? "#495057" : "#ced4da") : "#868e96"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "L2: " + (tle2Input.text.trim().length > 0 ? tle2Input.text : qsTr("(No TLE line 2 loaded)"))
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    color: tle2Input.text.trim().length >= 60 ? (satDialogRoot.lightMode ? "#495057" : "#ced4da") : "#868e96"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // --- MANUAL TLE VIEW ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: !satDialogRoot.tleModeCelestrak

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: qsTr("Raw Two-Line Orbital Elements (69 chars per line)")
                                font.pixelSize: 10
                                color: satDialogRoot.lightMode ? "#868e96" : "#868e96"
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

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: satDialogRoot.lightMode ? "#e9ecef" : "#222736"
                }

                // 5. Hardware Code Rate Table (FPGA / Transceiver MCS Modes)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Label {
                            text: qsTr("5. Hardware Code Rate Table (FPGA / Transceiver MCS Modes)")
                            font.bold: true
                            font.pixelSize: 12
                            color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                        }
                        Label {
                            text: qsTr("Define discrete available code rates and target hardware registers (e.g. Polyitan R1-R7)")
                            font.pixelSize: 10
                            color: satDialogRoot.lightMode ? "#868e96" : "#868e96"
                        }
                    }

                    Button {
                        height: 24
                        text: qsTr("📋 Polyitan-3 Preset")
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
                        onClicked: satDialogRoot.resetCodeRateTableToPolyitan()
                    }

                    Button {
                        height: 24
                        text: qsTr("+ Add Tier")
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
                            var nextIdx = codeRateModel.count + 1
                            codeRateModel.append({
                                name: "R" + nextIdx,
                                rate: 0.50,
                                hw: (codeRateModel.count).toString()
                            })
                        }
                    }
                }

                // Target Register setting
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: qsTr("Target Hardware Register:")
                        font.pixelSize: 11
                        font.bold: true
                        color: satDialogRoot.lightMode ? "#495057" : "#ced4da"
                    }

                    TextField {
                        id: codeRateRegisterInput
                        Layout.preferredWidth: 220
                        height: 28
                        text: "fpgatrx/code_rate"
                        font.family: "monospace"
                        font.pixelSize: 11
                        color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                        background: Rectangle {
                            radius: 4
                            color: satDialogRoot.lightMode ? "#f8f9fa" : "#1a1f2c"
                            border.color: codeRateRegisterInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // Table Container
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: codeRateListCol.implicitHeight + 16
                    Layout.preferredHeight: implicitHeight
                    radius: 6
                    color: satDialogRoot.lightMode ? "#f8f9fa" : "#12151d"
                    border.color: satDialogRoot.lightMode ? "#dee2e6" : "#242a3a"
                    border.width: 1

                    ColumnLayout {
                        id: codeRateListCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4

                        // Header Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: qsTr("Tier ID")
                                Layout.preferredWidth: 60
                                font.bold: true
                                font.pixelSize: 10
                                color: satDialogRoot.lightMode ? "#6c757d" : "#868e96"
                            }
                            Text {
                                text: qsTr("Code Rate Value (r)")
                                Layout.preferredWidth: 140
                                font.bold: true
                                font.pixelSize: 10
                                color: satDialogRoot.lightMode ? "#6c757d" : "#868e96"
                            }
                            Text {
                                text: qsTr("HW Register ID")
                                Layout.preferredWidth: 90
                                font.bold: true
                                font.pixelSize: 10
                                color: satDialogRoot.lightMode ? "#6c757d" : "#868e96"
                            }
                            Text {
                                text: qsTr("Action")
                                Layout.preferredWidth: 32
                                font.bold: true
                                font.pixelSize: 10
                                color: satDialogRoot.lightMode ? "#6c757d" : "#868e96"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: satDialogRoot.lightMode ? "#e9ecef" : "#1e2230"
                        }

                        // Empty State if no rows
                        Text {
                            visible: codeRateModel.count === 0
                            text: qsTr("No code rate tiers defined. Click '+ Add Tier' or '📋 Polyitan-3 Preset'.")
                            font.pixelSize: 11
                            color: satDialogRoot.lightMode ? "#868e96" : "#5c6370"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8
                            Layout.bottomMargin: 8
                        }

                        // Rows
                        Repeater {
                            model: codeRateModel
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                TextField {
                                    id: tierNameInput
                                    Layout.preferredWidth: 60
                                    height: 28
                                    text: model.name
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    color: "#f59f00"
                                    background: Rectangle {
                                        radius: 4
                                        color: satDialogRoot.lightMode ? "#ffffff" : "#1a1f2c"
                                        border.color: tierNameInput.activeFocus ? "#f59f00" : (satDialogRoot.lightMode ? "#ced4da" : "#2d3345")
                                    }
                                    onTextChanged: {
                                        if (model.name !== text) model.name = text
                                    }
                                }

                                TextField {
                                    id: tierRateInput
                                    Layout.preferredWidth: 140
                                    height: 28
                                    text: model.rate.toString()
                                    font.family: "monospace"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: satDialogRoot.lightMode ? "#212529" : "#f8f9fa"
                                    background: Rectangle {
                                        radius: 4
                                        color: satDialogRoot.lightMode ? "#ffffff" : "#1a1f2c"
                                        border.color: tierRateInput.activeFocus ? "#339af0" : (satDialogRoot.lightMode ? "#ced4da" : "#2d3345")
                                    }
                                    onTextChanged: {
                                        var val = parseFloat(text.replace(/,/g, "."))
                                        if (!isNaN(val) && val > 0 && model.rate !== val) {
                                            model.rate = val
                                        }
                                    }
                                }

                                TextField {
                                    id: tierHwInput
                                    Layout.preferredWidth: 90
                                    height: 28
                                    text: model.hw.toString()
                                    font.family: "monospace"
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    color: "#51cf66"
                                    background: Rectangle {
                                        radius: 4
                                        color: satDialogRoot.lightMode ? "#ffffff" : "#1a1f2c"
                                        border.color: tierHwInput.activeFocus ? "#51cf66" : (satDialogRoot.lightMode ? "#ced4da" : "#2d3345")
                                    }
                                    onTextChanged: {
                                        if (model.hw !== text) model.hw = text
                                    }
                                }

                                Button {
                                    id: rowDeleteBtn
                                    Layout.preferredWidth: 32
                                    height: 28
                                    background: Rectangle {
                                        radius: 4
                                        color: rowDeleteBtn.hovered ? "#fa5252" : (satDialogRoot.lightMode ? "#f1f3f5" : "#1e2230")
                                        border.color: rowDeleteBtn.hovered ? "#fa5252" : (satDialogRoot.lightMode ? "#dee2e6" : "#2d3345")
                                    }
                                    contentItem: Text {
                                        text: "🗑️"
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Delete this code rate tier")
                                    onClicked: codeRateModel.remove(index)
                                }

                                Item { Layout.fillWidth: true }
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

                        var codeRateArr = satDialogRoot.getCodeRateTableArray()
                        var regPath = codeRateRegisterInput.text.trim() || "fpgatrx/code_rate"

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
                            codeRateTable: codeRateArr,
                            codeRateRegister: regPath,
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
