import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailsRoot

    property var sessionEvent: null
    property var snrProfileData: null
    property var targetSatelliteData: null
    property var stationsModel: null
    property var stationsList: []
    property var stationsMap: ({})
    property bool lightMode: false
    property string activeMetric: "snr" // "snr", "fspl", "totalloss", "elevation"
    property bool showMrcEnvelope: false
    property bool showShannonLimits: false
    property int hoveredSampleIndex: -1

    onSnrProfileDataChanged: embeddedPlotCanvas.requestPaint()
    onLightModeChanged: embeddedPlotCanvas.requestPaint()
    onActiveMetricChanged: embeddedPlotCanvas.requestPaint()
    onVisibleChanged: {
        if (visible) {
            embeddedPlotCanvas.requestPaint()
        }
    }

    // Python Factor Calculation Modules state & models (per-station map: stationId -> array of module objects)
    property var addedModulesModel: null
    property var stationFactorModulesMap: ({})
    property var recentModulesList: []
    property var pythonEnvInfo: ({ available: true, version: "Python 3", isVenv: false })
    property string sessionInputJsonPreview: ""
    property bool showInputJsonPreview: false

    // Python Correlation Modules ("Predict Attenuation") state & models
    property var stationCorrelationModel: null
    property var recentCorrelationModulesList: []
    property var recentExcelFilesList: []
    property string selectedCorrelationModulePath: ""
    property string selectedExcelFilePath: ""

    // Session Plan & Transmission AMC parameters (synced with Target Satellite config)
    property string selectedModulation: (targetSatelliteData && targetSatelliteData.modulation) ? targetSatelliteData.modulation : "OQPSK"
    property real bitsPerSymbol: deriveBitsPerSymbol(selectedModulation)
    property real rolloffAlpha: (targetSatelliteData && targetSatelliteData.rolloffAlpha !== undefined) ? Number(targetSatelliteData.rolloffAlpha) : 0.35
    property real codeEfficiencyCoef: (targetSatelliteData && targetSatelliteData.codeEfficiencyCoef !== undefined) ? Number(targetSatelliteData.codeEfficiencyCoef) : 1.24
    property real carrierFreqMhz: (targetSatelliteData && targetSatelliteData.carrierFreqMhz !== undefined)
                                  ? Number(targetSatelliteData.carrierFreqMhz)
                                  : ((snrProfileData && snrProfileData.carrierFreqMhz) ? snrProfileData.carrierFreqMhz : 5850.0)
    property real channelBandwidthKhz: (targetSatelliteData && targetSatelliteData.channelBandwidthKhz !== undefined)
                                       ? Number(targetSatelliteData.channelBandwidthKhz)
                                       : ((snrProfileData && snrProfileData.channelBandwidthKhz) ? snrProfileData.channelBandwidthKhz : 20000.0)

    property var activeCodeRateTable: (targetSatelliteData && targetSatelliteData.codeRateTable && targetSatelliteData.codeRateTable.length > 0)
                                      ? targetSatelliteData.codeRateTable
                                      : [
                                          { name: "R1", rate: 0.910, hw: "0" },
                                          { name: "R2", rate: 0.830, hw: "1" },
                                          { name: "R3", rate: 0.700, hw: "2" },
                                          { name: "R4", rate: 0.570, hw: "3" },
                                          { name: "R5", rate: 0.410, hw: "4" },
                                          { name: "R6", rate: 0.285, hw: "5" },
                                          { name: "R7", rate: 0.190, hw: "6" }
                                      ]
    property string activeCodeRateRegister: (targetSatelliteData && targetSatelliteData.codeRateRegister)
                                            ? targetSatelliteData.codeRateRegister
                                            : "fpgatrx/code_rate"

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
        if (!tle1 || tle1.length < 32) return "07.11.2026 20:32:11"
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

    function formatSessionDateDisplay(isoStr) {
        if (!isoStr || isoStr.length < 10) return ""
        var datePart = isoStr.substring(0, 10)
        var parts = datePart.split("-")
        if (parts.length === 3) {
            return parts[2] + "." + parts[1] + "." + parts[0]
        }
        return datePart
    }

    function formatModuleDisplayName(rawName, factorName) {
        if (factorName && factorName.length > 0) {
            return factorName.replace(/_/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase() })
        }
        if (!rawName) return "Factor Module"
        var base = rawName.replace(/\.py$/i, "").replace(/_/g, " ")
        return base.replace(/\b\w/g, function(c) { return c.toUpperCase() })
    }

    function findFullStationConfig(stId, stName) {
        if (stId && detailsRoot.stationsMap && detailsRoot.stationsMap[stId]) {
            return detailsRoot.stationsMap[stId]
        }
        if (detailsRoot.stationsList && detailsRoot.stationsList.length > 0) {
            for (var i = 0; i < detailsRoot.stationsList.length; i++) {
                var item = detailsRoot.stationsList[i]
                if ((stId && item.stationId === stId) || (stName && item.name === stName)) {
                    return item
                }
            }
        }
        return null
    }

    // r_max = [1 / (bits_per_symbol * (1 + alpha))] * log2(1 + (10^(SNR_dB / 10) / Code_efficiency_coef))
    function calculateRMaxFormula(snrDb, m, a, gamma) {
        if (m <= 0 || (1 + a) <= 0 || gamma <= 0) return 0.0
        if (snrDb <= -25.0) return 0.0
        var snrLinear = Math.pow(10.0, snrDb / 10.0)
        var arg = 1.0 + (snrLinear / gamma)
        if (arg <= 1.0) return 0.0
        var prefactor = 1.0 / (m * (1.0 + a))
        var rMax = prefactor * (Math.log(arg) / Math.LN2)
        return Math.max(0.0, rMax)
    }

    readonly property real currentPeakSnr: {
        if (!snrProfileData || !snrProfileData.combinedSelectionSnrDb) return 0.0
        var maxS = -999.0
        var arr = snrProfileData.combinedSelectionSnrDb
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] > maxS) maxS = arr[i]
        }
        return maxS > -900.0 ? maxS : 0.0
    }

    readonly property real derivedPeakRMax: calculateRMaxFormula(currentPeakSnr, bitsPerSymbol, rolloffAlpha, codeEfficiencyCoef)

    readonly property real derivedSymbolRateKbaud: (1.0 + rolloffAlpha) > 0 ? (channelBandwidthKhz / (1.0 + rolloffAlpha)) : channelBandwidthKhz

    // Estimated Session Data Volume (MB) integrated across visible samples
    readonly property real estimatedSessionVolumeMb: {
        if (!snrProfileData || !snrProfileData.combinedSelectionSnrDb) return 0.0
        var arr = snrProfileData.combinedSelectionSnrDb
        var rateHz = snrProfileData.sampleRateHz > 0 ? snrProfileData.sampleRateHz : 1.0
        var dtSec = 1.0 / rateHz
        var symRateBaud = derivedSymbolRateKbaud * 1000.0
        var totalBits = 0.0
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] > -20.0) {
                var rMaxStep = calculateRMaxFormula(arr[i], bitsPerSymbol, rolloffAlpha, codeEfficiencyCoef)
                var bitrateBps = symRateBaud * bitsPerSymbol * rMaxStep
                totalBits += bitrateBps * dtSec
            }
        }
        return totalBits / (8.0 * 1e6)
    }

    function getOptimalTierForRMax(rMaxVal) {
        var table = activeCodeRateTable
        if (!table || table.length === 0) return null
        var sorted = []
        for (var i = 0; i < table.length; i++) {
            sorted.push(table[i])
        }
        sorted.sort(function(a, b) { return Number(b.rate) - Number(a.rate) })

        for (var j = 0; j < sorted.length; j++) {
            if (Number(sorted[j].rate) <= rMaxVal) {
                return sorted[j]
            }
        }
        return sorted[sorted.length - 1]
    }

    function getTransmissionParams() {
        return {
            "modulation": detailsRoot.selectedModulation,
            "bitsPerSymbol": detailsRoot.bitsPerSymbol,
            "alpha": detailsRoot.rolloffAlpha,
            "codeEfficiencyCoef": detailsRoot.codeEfficiencyCoef,
            "carrierFreqMhz": detailsRoot.carrierFreqMhz,
            "channelBandwidthKhz": detailsRoot.channelBandwidthKhz,
            "codeRateTable": detailsRoot.activeCodeRateTable,
            "codeRateRegister": detailsRoot.activeCodeRateRegister
        }
    }

    signal previewSessionPlanYamlRequested(var transmissionParams)
    signal exportSessionPlanYamlRequested(var transmissionParams)
    signal saveToHistoryRequested()

    signal editTargetSatelliteConfigRequested()
    signal editGroundStationConfigRequested(string stationId)

    signal browseStationModuleRequested(string stationId)
    signal addRecentStationModuleRequested(string stationId, string modulePath)
    signal removeStationModuleRequested(string stationId, int moduleIndex)
    signal toggleStationModuleEnabledRequested(string stationId, int moduleIndex, bool enabled)
    signal runStationModuleRequested(string stationId, int moduleIndex)
    signal previewStationInputJsonRequested(string stationId, string stationName)

    signal browseModuleRequested()
    signal addRecentModuleRequested(string modulePath)
    signal removeAddedModuleRequested(int index)
    signal toggleModuleEnabledRequested(int index, bool enabled)
    signal runModuleRequested(int index, string modulePath)
    signal runAllModulesRequested()
    signal generateInputJsonPreviewRequested()
    signal previewJsonModalRequested(string docTitle, string subtitle, string jsonText, string suggestedFileName)

    signal browseCorrelationModuleRequested()
    signal correlationModuleSelected(string modulePath)
    signal browseExcelFileRequested()
    signal excelFileSelected(string excelPath)
    signal predictStationAttenuationRequested(int stationIndex)
    signal predictAllStationsAttenuationRequested()

    radius: 12
    clip: true
    color: "transparent"

    readonly property var stationColors: [
        "#339af0", // Cyan / Azure
        "#51cf66", // Emerald Green
        "#da77f2", // Violet
        "#ff922b", // Orange
        "#20c997"  // Teal
    ]

    function getStationColor(identifier, fallbackIndex) {
        if (typeof identifier === "number") {
            return stationColors[identifier % stationColors.length]
        }
        var idStr = String(identifier || "")
        if (detailsRoot.snrProfileData && detailsRoot.snrProfileData.stations) {
            for (var i = 0; i < detailsRoot.snrProfileData.stations.length; i++) {
                var st = detailsRoot.snrProfileData.stations[i]
                if (st && (st.stationId === idStr || st.stationName === idStr)) {
                    return stationColors[i % stationColors.length]
                }
            }
        }
        if (detailsRoot.sessionEvent && detailsRoot.sessionEvent.stationPasses) {
            for (var j = 0; j < detailsRoot.sessionEvent.stationPasses.length; j++) {
                var p = detailsRoot.sessionEvent.stationPasses[j]
                if (p && (p.stationId === idStr || p.stationName === idStr)) {
                    return stationColors[j % stationColors.length]
                }
            }
        }
        if (typeof fallbackIndex === "number") {
            return stationColors[fallbackIndex % stationColors.length]
        }
        return stationColors[0]
    }

    function getStationFillColor(hexCol, alphaHex) {
        if (!hexCol) return "#00000000"
        var raw = hexCol.toString().replace("#", "")
        if (raw.length === 8) {
            raw = raw.substring(2)
        }
        return "#" + (alphaHex !== undefined ? alphaHex : "26") + raw
    }

    // ================= EMPTY STATE (when no session selected) =================
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16
        visible: detailsRoot.sessionEvent === null

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 18
            color: detailsRoot.lightMode ? "#e7f5ff" : "#14233c"
            border.color: "#339af0"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "📅"
                font.pixelSize: 34
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Select a Pass Session to View Details")
            font.bold: true
            font.pixelSize: 18
            color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Choose a predicted satellite pass from the list on the left\nto inspect multi-station SNR curves, link budgets, and station geometry.")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            color: detailsRoot.lightMode ? "#6c757d" : "#909296"
        }
    }

    // ================= ACTIVE SESSION DETAILS (Scrollable Vertically & Horizontally) =================
    Flickable {
        id: mainFlickable
        anchors.fill: parent
        visible: detailsRoot.sessionEvent !== null
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        contentWidth: Math.max(width, 940, mainContentCol.implicitWidth + 36)
        contentHeight: mainContentCol.implicitHeight + 36

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }
        ScrollBar.horizontal: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: mainContentCol
            x: 18
            y: 16
            width: mainFlickable.contentWidth - 36
            spacing: 12

            // =========================================================================
            // 1. MINIMALISTIC SESSION TITLE BAR (+ Estimated Session Data Volume)
            // =========================================================================
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                Layout.preferredHeight: 46
                radius: 8
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#222736"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    spacing: 12

                    // Session Date (e.g. 07.11.2026)
                    Label {
                        text: detailsRoot.sessionEvent ? detailsRoot.formatSessionDateDisplay(detailsRoot.sessionEvent.combinedAosUtc) : ""
                        font.bold: true
                        font.pixelSize: 14
                        color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                    }

                    Rectangle {
                        width: 1
                        height: 16
                        color: detailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                    }

                    // Minimalistic Pass Window & Duration
                    Label {
                        text: {
                            if (!detailsRoot.sessionEvent) return ""
                            var aos = (detailsRoot.sessionEvent.combinedAosUtc || "").split(" ").pop()
                            var los = (detailsRoot.sessionEvent.combinedLosUtc || "").split(" ").pop()
                            return "Pass #" + detailsRoot.sessionEvent.passIndex + " • " + aos + " → " + los + " UTC (" + detailsRoot.sessionEvent.combinedDurationFormatted + ")"
                        }
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                    }

                    // Peak Elevation Pill
                    Rectangle {
                        height: 22
                        width: pkElText.implicitWidth + 12
                        radius: 6
                        color: detailsRoot.lightMode ? "#f1f3f5" : "#1c202c"
                        border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                        Text {
                            id: pkElText
                            anchors.centerIn: parent
                            text: detailsRoot.sessionEvent ? ("Peak El: " + detailsRoot.sessionEvent.maxElevationDeg + "°") : ""
                            font.bold: true
                            font.pixelSize: 11
                            color: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.maxElevationDeg >= 50) ? "#51cf66" : "#fcc419"
                        }
                    }

                    // Estimated Session Data Volume Pill
                    Rectangle {
                        height: 24
                        width: volBadgeRow.implicitWidth + 14
                        radius: 6
                        color: detailsRoot.lightMode ? "#e7f5ff" : "#122338"
                        border.color: "#339af0"
                        border.width: 1

                        RowLayout {
                            id: volBadgeRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "📦 Est. Data Volume:"
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                            Text {
                                text: {
                                    var mb = detailsRoot.estimatedSessionVolumeMb
                                    if (mb >= 1024.0) return (mb / 1024.0).toFixed(2) + " GB"
                                    return mb.toFixed(1) + " MB"
                                }
                                font.bold: true
                                font.family: "monospace"
                                font.pixelSize: 11
                                color: "#339af0"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Session Input JSON Preview Button
                    Button {
                        id: topInputJsonBtn
                        height: 26
                        background: Rectangle {
                            radius: 6
                            color: topInputJsonBtn.hovered
                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#222736")
                                   : "transparent"
                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                        }
                        contentItem: Text {
                            text: "{ } Input JSON"
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            leftPadding: 8; rightPadding: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            detailsRoot.generateInputJsonPreviewRequested()
                            var passIdx = detailsRoot.sessionEvent ? detailsRoot.sessionEvent.passIndex : 1
                            var satName = (detailsRoot.snrProfileData && detailsRoot.snrProfileData.satelliteName) ? detailsRoot.snrProfileData.satelliteName : "Satellite"
                            detailsRoot.previewJsonModalRequested(
                                qsTr("Session Prediction Input JSON"),
                                satName + " — Pass #" + passIdx + " (Full session prediction payload)",
                                detailsRoot.sessionInputJsonPreview,
                                "session_pass_" + passIdx + "_input.json"
                            )
                        }
                    }

                    // Preview YAML Plan Button
                    Button {
                        id: topPreviewPlanBtn
                        height: 26
                        background: Rectangle {
                            radius: 6
                            color: topPreviewPlanBtn.hovered
                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#222736")
                                   : "transparent"
                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                        }
                        contentItem: Text {
                            text: qsTr("👁️ Session Plan")
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            leftPadding: 8; rightPadding: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: detailsRoot.previewSessionPlanYamlRequested(detailsRoot.getTransmissionParams())
                    }

                    // Export YAML Plan Button
                    Button {
                        id: topExportPlanBtn
                        height: 26
                        background: Rectangle {
                            radius: 6
                            color: topExportPlanBtn.hovered ? "#d9480f" : "#e67700"
                        }
                        contentItem: Text {
                            text: qsTr("💾 Export .yaml")
                            font.bold: true
                            font.pixelSize: 11
                            color: "#ffffff"
                            leftPadding: 8; rightPadding: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: detailsRoot.exportSessionPlanYamlRequested(detailsRoot.getTransmissionParams())
                    }

                    // Save to History Button
                    Button {
                        id: topSaveHistoryBtn
                        height: 26
                        background: Rectangle {
                            radius: 6
                            color: topSaveHistoryBtn.hovered ? "#087f5b" : "#099268"
                        }
                        contentItem: Text {
                            text: qsTr("💾 Save to History")
                            font.bold: true
                            font.pixelSize: 11
                            color: "#ffffff"
                            leftPadding: 8; rightPadding: 8
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: detailsRoot.saveToHistoryRequested()
                    }
                }
            }

            // =========================================================================
            // 2. CONTROLS & METRIC TABS + TELEMETRY BAR + SNR/LOSS GRAPH
            // =========================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "snr", label: "📶 Signal-to-Noise Ratio (SNR)" },
                            { id: "fspl", label: "📉 Free Space Path Loss (FSPL)" },
                            { id: "totalloss", label: "📊 Total Signal Loss" },
                            { id: "elevation", label: "📐 Elevation Angle" }
                        ]

                        Button {
                            height: 28
                            checkable: true
                            checked: detailsRoot.activeMetric === modelData.id
                            background: Rectangle {
                                radius: 6
                                color: checked ? "#339af0" : (parent.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#232838") : (detailsRoot.lightMode ? "#ffffff" : "#141720"))
                                border.color: checked ? "#339af0" : (detailsRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                            contentItem: Text {
                                text: modelData.label
                                font.bold: true
                                font.pixelSize: 11
                                color: checked ? "#ffffff" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: {
                                detailsRoot.activeMetric = modelData.id
                                embeddedPlotCanvas.requestPaint()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                /* Commented out MRC Envelope and Shannon Limits toggles for now per user request:
                CheckBox {
                    text: qsTr("Combined MRC Envelope")
                    checked: detailsRoot.showMrcEnvelope
                    visible: detailsRoot.activeMetric === "snr" && detailsRoot.snrProfileData && detailsRoot.snrProfileData.hasOverlap
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        font.bold: true
                        color: "#ffd43b"
                        leftPadding: parent.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                    onCheckedChanged: {
                        detailsRoot.showMrcEnvelope = checked
                        embeddedPlotCanvas.requestPaint()
                    }
                }

                CheckBox {
                    text: qsTr("Shannon Limits")
                    checked: detailsRoot.showShannonLimits
                    visible: detailsRoot.activeMetric === "snr"
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        font.bold: true
                        color: detailsRoot.lightMode ? "#495057" : "#ced4da"
                        leftPadding: parent.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                    onCheckedChanged: {
                        detailsRoot.showShannonLimits = checked
                        embeddedPlotCanvas.requestPaint()
                    }
                }
                */
            }

            // --- LIVE CROSSHAIR TELEMETRY HUD ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 34
                Layout.preferredHeight: 34
                radius: 6
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#222736"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 16

                    RowLayout {
                        spacing: 6
                        Text {
                            text: "⏱️ Time:"
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                        }
                        Text {
                            text: {
                                if (!detailsRoot.snrProfileData || detailsRoot.hoveredSampleIndex < 0 ||
                                    detailsRoot.hoveredSampleIndex >= detailsRoot.snrProfileData.utcLabels.length) {
                                    return "Hover plot to inspect"
                                }
                                var tSec = detailsRoot.snrProfileData.timestampsSec[detailsRoot.hoveredSampleIndex]
                                var utc = detailsRoot.snrProfileData.utcLabels[detailsRoot.hoveredSampleIndex]
                                return utc + " (+" + Math.round(tSec) + "s)"
                            }
                            font.bold: true
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#339af0"
                        }
                    }

                    Rectangle { width: 1; height: 16; color: detailsRoot.lightMode ? "#ced4da" : "#373a40" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Repeater {
                            model: (detailsRoot.snrProfileData && detailsRoot.snrProfileData.stations) ? detailsRoot.snrProfileData.stations : []

                            RowLayout {
                                spacing: 4
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: detailsRoot.getStationColor(modelData.stationId || modelData.stationName, index)
                                }
                                Text {
                                    text: modelData.stationName + ":"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.getStationColor(modelData.stationId || modelData.stationName, index)
                                }
                                Text {
                                    font.bold: true
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#212529" : "#f8f9fa"
                                    text: {
                                        var idx = detailsRoot.hoveredSampleIndex
                                        if (idx < 0 || !modelData.elevationDeg || idx >= modelData.elevationDeg.length) {
                                            return "Peak SNR " + (modelData.maxSnrDb > -900 ? modelData.maxSnrDb.toFixed(1) + " dB" : "N/A")
                                        }
                                        if (!modelData.isVisible[idx]) return "Below Horizon"
                                        var extraLoss = (modelData.extraAttenuationDb && idx < modelData.extraAttenuationDb.length) ? Number(modelData.extraAttenuationDb[idx]) : 0.0
                                        if (detailsRoot.activeMetric === "snr") {
                                            var lossTag = extraLoss > 0.001 ? (" (-" + extraLoss.toFixed(1) + " dB factor)") : ""
                                            return modelData.snrDb[idx].toFixed(1) + " dB" + lossTag + " (El: " + modelData.elevationDeg[idx].toFixed(1) + "°)"
                                        }
                                        if (detailsRoot.activeMetric === "fspl") return modelData.fsplLossDb[idx].toFixed(1) + " dB"
                                        if (detailsRoot.activeMetric === "totalloss") {
                                            var extraTag = extraLoss > 0.001 ? (" (+" + extraLoss.toFixed(1) + " dB factor)") : ""
                                            return modelData.totalLossDb[idx].toFixed(1) + " dB" + extraTag
                                        }
                                        return modelData.elevationDeg[idx].toFixed(1) + "°"
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: 1; height: 16; color: detailsRoot.lightMode ? "#ced4da" : "#373a40" }

                    RowLayout {
                        spacing: 6
                        Text {
                            text: "📊 r_max:"
                            font.bold: true
                            font.pixelSize: 11
                            color: "#fab005"
                        }
                        Text {
                            font.bold: true
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#fab005"
                            text: {
                                var idx = detailsRoot.hoveredSampleIndex
                                if (!detailsRoot.snrProfileData || idx < 0 || !detailsRoot.snrProfileData.combinedSelectionSnrDb || idx >= detailsRoot.snrProfileData.combinedSelectionSnrDb.length) {
                                    return "Peak " + detailsRoot.derivedPeakRMax.toFixed(3)
                                }
                                var s = detailsRoot.snrProfileData.combinedSelectionSnrDb[idx]
                                if (s <= -20.0) return "0.000 (LOS)"
                                return detailsRoot.calculateRMaxFormula(s, detailsRoot.bitsPerSymbol, detailsRoot.rolloffAlpha, detailsRoot.codeEfficiencyCoef).toFixed(3)
                            }
                        }
                    }

                    Rectangle { width: 1; height: 16; color: detailsRoot.lightMode ? "#ced4da" : "#373a40" }

                    RowLayout {
                        spacing: 6
                        Text {
                            text: "⚙️ MCS Mode:"
                            font.bold: true
                            font.pixelSize: 11
                            color: "#51cf66"
                        }
                        Text {
                            font.bold: true
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#51cf66"
                            text: {
                                var idx = detailsRoot.hoveredSampleIndex
                                var rVal = detailsRoot.derivedPeakRMax
                                if (detailsRoot.snrProfileData && idx >= 0 && detailsRoot.snrProfileData.combinedSelectionSnrDb && idx < detailsRoot.snrProfileData.combinedSelectionSnrDb.length) {
                                    var s = detailsRoot.snrProfileData.combinedSelectionSnrDb[idx]
                                    rVal = s > -20.0 ? detailsRoot.calculateRMaxFormula(s, detailsRoot.bitsPerSymbol, detailsRoot.rolloffAlpha, detailsRoot.codeEfficiencyCoef) : 0.0
                                }
                                var tier = detailsRoot.getOptimalTierForRMax(rVal)
                                if (tier) {
                                    return "HW: " + tier.hw + " (" + tier.name + " " + Number(tier.rate).toFixed(2) + ")"
                                }
                                return "N/A"
                            }
                        }
                    }
                }
            }

            // --- EMBEDDED SNR CANVAS PLOT ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 310
                Layout.preferredHeight: 310
                radius: 8
                color: detailsRoot.lightMode ? "#ffffff" : "#0d1017"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#242a3a"
                clip: true

                Canvas {
                    id: embeddedPlotCanvas
                    anchors.fill: parent
                    antialiasing: true

                    property real paddingLeft: 55
                    property real paddingRight: 25
                    property real paddingTop: 22
                    property real paddingBottom: 38

                    onAvailableChanged: {
                        if (available) {
                            requestPaint()
                        }
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
                        ctx.clearRect(0, 0, w, h)

                        if (!detailsRoot.snrProfileData || !detailsRoot.snrProfileData.valid) {
                            ctx.fillStyle = detailsRoot.lightMode ? "#868e96" : "#495057"
                            ctx.font = "13px sans-serif"
                            ctx.textAlign = "center"
                            ctx.fillText("Calculating SNR & Loss profile for selected pass...", w / 2, h / 2)
                            return
                        }

                        var data = detailsRoot.snrProfileData
                        var N = data.sampleCount
                        if (N < 2) return

                        var plotW = w - paddingLeft - paddingRight
                        var plotH = h - paddingTop - paddingBottom

                        var yMin = 0
                        var yMax = 30
                        var metric = detailsRoot.activeMetric

                        if (metric === "snr") {
                            yMin = -15
                            yMax = 30
                            for (var s = 0; s < data.stations.length; s++) {
                                var st = data.stations[s]
                                if (st.maxSnrDb > yMax - 5) yMax = Math.ceil((st.maxSnrDb + 5) / 5) * 5
                            }
                        } else if (metric === "fspl" || metric === "totalloss") {
                            yMin = 150
                            yMax = 195
                            for (var s2 = 0; s2 < data.stations.length; s2++) {
                                var st2 = data.stations[s2]
                                if (st2.minFsplDb < yMin + 5 && st2.minFsplDb > 50) yMin = Math.floor((st2.minFsplDb - 5) / 5) * 5
                            }
                        } else if (metric === "elevation") {
                            yMin = 0
                            yMax = 90
                        }

                        function mapX(sampleIdx) { return paddingLeft + (sampleIdx / (N - 1)) * plotW }
                        function mapY(val) {
                            var clamped = Math.max(yMin, Math.min(yMax, val))
                            return paddingTop + (1.0 - (clamped - yMin) / (yMax - yMin)) * plotH
                        }

                        // Overlap Highlight
                        if (data.hasOverlap && metric === "snr") {
                            var overlapStart = -1
                            var overlapEnd = -1
                            for (var k = 0; k < N; k++) {
                                var visCount = 0
                                for (var si = 0; si < data.stations.length; si++) {
                                    if (data.stations[si].isVisible[k]) visCount++
                                }
                                if (visCount >= 2) {
                                    if (overlapStart === -1) overlapStart = k
                                    overlapEnd = k
                                }
                            }
                            if (overlapStart !== -1 && overlapEnd >= overlapStart) {
                                var ox1 = mapX(overlapStart)
                                var ox2 = mapX(overlapEnd)
                                ctx.fillStyle = detailsRoot.lightMode ? "rgba(47, 158, 68, 0.12)" : "rgba(47, 158, 68, 0.15)"
                                ctx.fillRect(ox1, paddingTop, ox2 - ox1, plotH)
                                ctx.strokeStyle = "#40c057"
                                ctx.lineWidth = 1.2
                                ctx.setLineDash([4, 4])
                                ctx.beginPath()
                                ctx.moveTo(ox1, paddingTop); ctx.lineTo(ox1, paddingTop + plotH)
                                ctx.moveTo(ox2, paddingTop); ctx.lineTo(ox2, paddingTop + plotH)
                                ctx.stroke()
                                ctx.setLineDash([])
                            }
                        }

                        // Grid & Ticks
                        ctx.strokeStyle = detailsRoot.lightMode ? "#e9ecef" : "#1a2130"
                        ctx.lineWidth = 1
                        ctx.fillStyle = detailsRoot.lightMode ? "#868e96" : "#6c757d"
                        ctx.font = "9px monospace"
                        ctx.textAlign = "right"

                        var yStep = (yMax - yMin) <= 40 ? 5 : ((yMax - yMin) <= 100 ? 10 : 20)
                        for (var yv = yMin; yv <= yMax; yv += yStep) {
                            var yp = mapY(yv)
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, yp)
                            ctx.lineTo(paddingLeft + plotW, yp)
                            ctx.stroke()
                            var labelUnit = (metric === "elevation") ? "°" : " dB"
                            ctx.fillText(yv + labelUnit, paddingLeft - 6, yp + 3)
                        }

                        // X-axis Time Ticks
                        var timeStepSec = Math.max(30, Math.floor(data.durationSeconds / 7))
                        var sampleStep = Math.max(1, Math.round(timeStepSec * data.sampleRateHz))
                        ctx.textAlign = "center"
                        for (var tIdx = 0; tIdx < N; tIdx += sampleStep) {
                            var xp = mapX(tIdx)
                            ctx.beginPath()
                            ctx.moveTo(xp, paddingTop); ctx.lineTo(xp, paddingTop + plotH); ctx.stroke()
                            var utcText = data.utcLabels[tIdx]
                            var secText = "+" + Math.round(data.timestampsSec[tIdx]) + "s"
                            ctx.fillStyle = detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            ctx.fillText(utcText, xp, paddingTop + plotH + 14)
                            ctx.fillStyle = detailsRoot.lightMode ? "#adb5bd" : "#5c6270"
                            ctx.fillText(secText, xp, paddingTop + plotH + 24)
                        }

                        /* Commented out Shannon Limits lines per user request:
                        // Shannon Limits
                        if (metric === "snr" && detailsRoot.showShannonLimits) {
                            var y0 = mapY(data.shannonRawThresholdDb)
                            ctx.strokeStyle = "#ff6b6b"
                            ctx.lineWidth = 1.2
                            ctx.setLineDash([5, 4])
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, y0); ctx.lineTo(paddingLeft + plotW, y0); ctx.stroke()
                            ctx.fillStyle = "#ff6b6b"
                            ctx.font = "bold 9px sans-serif"
                            ctx.textAlign = "left"
                            ctx.fillText("0 dB Shannon Raw Limit", paddingLeft + 8, y0 - 3)

                            var yTurbo = mapY(data.shannonTurbocodeThresholdDb)
                            ctx.strokeStyle = "#fcc419"
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, yTurbo); ctx.lineTo(paddingLeft + plotW, yTurbo); ctx.stroke()
                            ctx.fillStyle = "#fcc419"
                            ctx.fillText("4.77 dB Rate 1/2 Turbo Limit", paddingLeft + 8, yTurbo - 3)
                            ctx.setLineDash([])
                        }
                        */

                        // Station Curves
                        for (var sIdx = 0; sIdx < data.stations.length; sIdx++) {
                            var station = data.stations[sIdx]
                            var col = detailsRoot.getStationColor(station.stationId || station.stationName, sIdx)
                            var vec = []
                            var baseVec = null
                            if (metric === "snr") {
                                vec = station.snrDb
                                if (station.hasExtraAttenuation && station.baselineSnrDb) baseVec = station.baselineSnrDb
                            } else if (metric === "fspl") {
                                vec = station.fsplLossDb
                            } else if (metric === "totalloss") {
                                vec = station.totalLossDb
                                if (station.hasExtraAttenuation && station.baselineTotalLossDb) baseVec = station.baselineTotalLossDb
                            } else if (metric === "elevation") {
                                vec = station.elevationDeg
                            }

                            if (!vec || vec.length !== N) continue

                            // Optional Dashed Baseline Curve (when extra factor attenuation is active)
                            if (baseVec && baseVec.length === N) {
                                ctx.save()
                                ctx.beginPath()
                                ctx.strokeStyle = col
                                ctx.globalAlpha = 0.42
                                ctx.lineWidth = 1.4
                                ctx.setLineDash([4, 3])
                                for (var kb = 0; kb < N; kb++) {
                                    var bVal = baseVec[kb]
                                    if (metric === "snr" && !station.isVisible[kb]) bVal = yMin
                                    var bx = mapX(kb)
                                    var by = mapY(bVal)
                                    if (kb === 0) ctx.moveTo(bx, by)
                                    else ctx.lineTo(bx, by)
                                }
                                ctx.stroke()
                                ctx.restore()
                            }

                            // Fill
                            if (metric === "snr" || metric === "elevation") {
                                ctx.beginPath()
                                ctx.moveTo(mapX(0), mapY(yMin))
                                for (var k1 = 0; k1 < N; k1++) {
                                    var val1 = vec[k1]
                                    if (metric === "snr" && !station.isVisible[k1]) val1 = yMin
                                    ctx.lineTo(mapX(k1), mapY(val1))
                                }
                                ctx.lineTo(mapX(N - 1), mapY(yMin))
                                ctx.closePath()
                                var grad = ctx.createLinearGradient(0, paddingTop, 0, paddingTop + plotH)
                                grad.addColorStop(0, detailsRoot.getStationFillColor(col, "26"))
                                grad.addColorStop(1, detailsRoot.getStationFillColor(col, "00"))
                                ctx.fillStyle = grad
                                ctx.fill()
                            }

                            // Stroke
                            ctx.beginPath()
                            ctx.strokeStyle = col
                            ctx.lineWidth = 2.2
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"

                            for (var k2 = 0; k2 < N; k2++) {
                                var val2 = vec[k2]
                                if (metric === "snr" && !station.isVisible[k2]) val2 = yMin
                                var cx = mapX(k2)
                                var cy = mapY(val2)
                                if (k2 === 0) ctx.moveTo(cx, cy)
                                else ctx.lineTo(cx, cy)
                            }
                            ctx.stroke()
                        }

                        /* Commented out Combined MRC Envelope line per user request:
                        // Combined MRC Envelope
                        if (metric === "snr" && detailsRoot.showMrcEnvelope && data.hasOverlap && data.combinedMrcSnrDb) {
                            ctx.beginPath()
                            ctx.strokeStyle = "#ffd43b"
                            ctx.lineWidth = 2.0
                            ctx.setLineDash([4, 3])
                            for (var km = 0; km < N; km++) {
                                var mrcVal = data.combinedMrcSnrDb[km]
                                var mx = mapX(km)
                                var my = mapY(mrcVal)
                                if (km === 0) ctx.moveTo(mx, my)
                                else ctx.lineTo(mx, my)
                            }
                            ctx.stroke()
                            ctx.setLineDash([])
                        }
                        */

                        // Crosshair
                        if (detailsRoot.hoveredSampleIndex >= 0 && detailsRoot.hoveredSampleIndex < N) {
                            var hx = mapX(detailsRoot.hoveredSampleIndex)
                            ctx.strokeStyle = "#ffffff"
                            ctx.lineWidth = 1
                            ctx.setLineDash([3, 3])
                            ctx.beginPath()
                            ctx.moveTo(hx, paddingTop); ctx.lineTo(hx, paddingTop + plotH); ctx.stroke()
                            ctx.setLineDash([])
                        }

                        // Outer border
                        ctx.strokeStyle = detailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(paddingLeft, paddingTop)
                        ctx.lineTo(paddingLeft, paddingTop + plotH)
                        ctx.lineTo(paddingLeft + plotW, paddingTop + plotH)
                        ctx.stroke()
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: function(mouse) {
                            if (!detailsRoot.snrProfileData || !detailsRoot.snrProfileData.valid) return
                            var data = detailsRoot.snrProfileData
                            var N = data.sampleCount
                            var plotW = embeddedPlotCanvas.width - embeddedPlotCanvas.paddingLeft - embeddedPlotCanvas.paddingRight
                            if (mouse.x >= embeddedPlotCanvas.paddingLeft && mouse.x <= embeddedPlotCanvas.paddingLeft + plotW) {
                                var ratio = (mouse.x - embeddedPlotCanvas.paddingLeft) / plotW
                                detailsRoot.hoveredSampleIndex = Math.max(0, Math.min(N - 1, Math.round(ratio * (N - 1))))
                            } else {
                                detailsRoot.hoveredSampleIndex = -1
                            }
                            embeddedPlotCanvas.requestPaint()
                        }
                        onExited: {
                            detailsRoot.hoveredSampleIndex = -1
                            embeddedPlotCanvas.requestPaint()
                        }
                    }
                }
            }

            // =========================================================================
            // 3. TARGET SATELLITE BLOCK WITH CONFIG
            // =========================================================================
            Label {
                text: qsTr("Target Satellite:")
                font.bold: true
                font.pixelSize: 13
                color: detailsRoot.lightMode ? "#1a1b1e" : "#e9ecef"
                Layout.topMargin: 2
            }

            Rectangle {
                id: targetSatelliteCard
                Layout.preferredWidth: Math.min(mainContentCol.width, 540)
                Layout.maximumWidth: 620
                implicitHeight: targetSatCol.implicitHeight + 28
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#222736"
                border.width: 1

                ColumnLayout {
                    id: targetSatCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    // Satellite Name + Edit Config Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: (detailsRoot.targetSatelliteData && detailsRoot.targetSatelliteData.name)
                                  ? detailsRoot.targetSatelliteData.name
                                  : ((detailsRoot.snrProfileData && detailsRoot.snrProfileData.satelliteName)
                                     ? detailsRoot.snrProfileData.satelliteName
                                     : "ISS (ZARYA)")
                            font.bold: true
                            font.pixelSize: 14
                            color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: editSatCfgBtn
                            height: 24
                            background: Rectangle {
                                radius: 5
                                color: editSatCfgBtn.hovered
                                       ? (detailsRoot.lightMode ? "#fff3bf" : "#2b2412")
                                       : (detailsRoot.lightMode ? "#f8f9fa" : "#1c202c")
                                border.color: editSatCfgBtn.hovered ? "#f59f00" : (detailsRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                            contentItem: Text {
                                text: qsTr("✏️ Edit Config")
                                font.bold: true
                                font.pixelSize: 11
                                color: editSatCfgBtn.hovered ? "#f59f00" : (detailsRoot.lightMode ? "#495057" : "#ced4da")
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Edit satellite frequency, bandwidth, modulation, coder efficiency Γ, roll-off α, and TLE")
                            onClicked: detailsRoot.editTargetSatelliteConfigRequested()
                        }
                    }

                    // "Config" Subtitle
                    Label {
                        text: qsTr("Config")
                        font.pixelSize: 12
                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                    }

                    // Config Badges Flow (clickable to open Satellite Configuration Dialog)
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                "f=" + (detailsRoot.carrierFreqMhz / 1000.0).toFixed(2).replace(/\.?0+$/, "") + " GHz",
                                "B=" + (detailsRoot.channelBandwidthKhz / 1000.0).toFixed(2).replace(/\.?0+$/, "") + " MHz",
                                "TLE=" + detailsRoot.parseTleEpochDisplay(detailsRoot.targetSatelliteData ? detailsRoot.targetSatelliteData.tle1 : ""),
                                "Mod=" + detailsRoot.selectedModulation,
                                "Γ=" + detailsRoot.codeEfficiencyCoef.toFixed(2).replace(/\.?0+$/, ""),
                                "alpha=" + detailsRoot.rolloffAlpha.toFixed(2).replace(/\.?0+$/, "")
                            ]

                            Rectangle {
                                height: 28
                                width: satPillText.implicitWidth + 18
                                radius: 6
                                color: satPillMouse.containsMouse
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#232838")
                                       : (detailsRoot.lightMode ? "#f8f9fa" : "#181c26")
                                border.color: satPillMouse.containsMouse
                                              ? "#f59f00"
                                              : (detailsRoot.lightMode ? "#ced4da" : "#262b3a")
                                border.width: 1

                                Text {
                                    id: satPillText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 12
                                    color: detailsRoot.lightMode ? "#212529" : "#e9ecef"
                                }

                                MouseArea {
                                    id: satPillMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: detailsRoot.editTargetSatelliteConfigRequested()
                                }
                            }
                        }
                    }
                }
            }

            // =========================================================================
            // 4. GROUND STATIONS SECTION (with Polar Plot, Basic Info, Config & Modules)
            // =========================================================================
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Label {
                    text: qsTr("Ground Stations:")
                    font.bold: true
                    font.pixelSize: 13
                    color: detailsRoot.lightMode ? "#1a1b1e" : "#e9ecef"
                }

                Item { Layout.fillWidth: true }

                // Compact Session Correlation Selector (one correlation module for the session)
                RowLayout {
                    spacing: 6

                    Label {
                        text: qsTr("Session Correlation:")
                        font.pixelSize: 11
                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                    }

                    ComboBox {
                        id: corrScriptCombo
                        Layout.preferredWidth: 165
                        height: 24
                        model: detailsRoot.recentCorrelationModulesList ? detailsRoot.recentCorrelationModulesList : []
                        textRole: "name"
                        font.pixelSize: 10
                        enabled: count > 0
                        displayText: {
                            if (detailsRoot.selectedCorrelationModulePath && detailsRoot.selectedCorrelationModulePath.length > 0) {
                                var p = detailsRoot.selectedCorrelationModulePath.replace(/\\/g, "/").split("/")
                                return p[p.length - 1]
                            }
                            return "step_correlation.py"
                        }
                        onActivated: (idx) => {
                            var item = detailsRoot.recentCorrelationModulesList[idx]
                            if (item && item.path) {
                                detailsRoot.correlationModuleSelected(item.path)
                            }
                        }
                    }

                    Button {
                        id: browseCorrPyBtn
                        height: 24
                        background: Rectangle {
                            radius: 5
                            color: browseCorrPyBtn.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#222736") : (detailsRoot.lightMode ? "#ffffff" : "#141720")
                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                        }
                        contentItem: Text {
                            text: "📂 .py"
                            font.bold: true
                            font.pixelSize: 10
                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            leftPadding: 6; rightPadding: 6
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Browse Python correlation script (.py)")
                        onClicked: detailsRoot.browseCorrelationModuleRequested()
                    }

                    ComboBox {
                        id: excelTableCombo
                        Layout.preferredWidth: 175
                        height: 24
                        model: detailsRoot.recentExcelFilesList ? detailsRoot.recentExcelFilesList : []
                        textRole: "name"
                        font.pixelSize: 10
                        enabled: count > 0
                        displayText: {
                            if (detailsRoot.selectedExcelFilePath && detailsRoot.selectedExcelFilePath.length > 0) {
                                var p = detailsRoot.selectedExcelFilePath.replace(/\\/g, "/").split("/")
                                return p[p.length - 1]
                            }
                            return "attenuation_table.xlsx"
                        }
                        onActivated: (idx) => {
                            var item = detailsRoot.recentExcelFilesList[idx]
                            if (item && item.path) {
                                detailsRoot.excelFileSelected(item.path)
                            }
                        }
                    }

                    Button {
                        id: browseExcelBtn
                        height: 24
                        background: Rectangle {
                            radius: 5
                            color: browseExcelBtn.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#222736") : (detailsRoot.lightMode ? "#ffffff" : "#141720")
                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                        }
                        contentItem: Text {
                            text: "📊 .xlsx"
                            font.bold: true
                            font.pixelSize: 10
                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                            leftPadding: 6; rightPadding: 6
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Browse Excel attenuation lookup table (.xlsx)")
                        onClicked: detailsRoot.browseExcelFileRequested()
                    }
                }
            }

            // Ground Stations Horizontal Row / Grid (matching mockup)
            Flow {
                Layout.fillWidth: true
                spacing: 14

                Repeater {
                    model: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.stationPasses) ? detailsRoot.sessionEvent.stationPasses : []

                    Rectangle {
                        id: stationBreakdownCard
                        readonly property int stationIndex: index
                        readonly property string stId: modelData.stationId || ("GS-" + (index + 1))
                        readonly property string stName: modelData.stationName || ("Station " + (index + 1))
                        readonly property color stColor: detailsRoot.getStationColor(stId || stName, index)
                        readonly property var stFullCfg: detailsRoot.findFullStationConfig(stId, stName)
                        readonly property var stModulesList: (detailsRoot.stationFactorModulesMap && detailsRoot.stationFactorModulesMap[stId])
                                                              ? detailsRoot.stationFactorModulesMap[stId]
                                                              : []
                        readonly property var stSnrEntry: {
                            if (!detailsRoot.snrProfileData || !detailsRoot.snrProfileData.stations) return null
                            for (var s = 0; s < detailsRoot.snrProfileData.stations.length; s++) {
                                var candidate = detailsRoot.snrProfileData.stations[s]
                                if (candidate.stationId === stId || candidate.stationName === stName) {
                                    return candidate
                                }
                            }
                            if (index < detailsRoot.snrProfileData.stations.length) {
                                return detailsRoot.snrProfileData.stations[index]
                            }
                            return null
                        }

                        width: Math.max(430, Math.floor((mainContentCol.width - 14) / 2))
                        implicitHeight: Math.max(stationCardMainRow.implicitHeight + 28, 210)
                        radius: 10
                        color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                        border.color: detailsRoot.lightMode ? "#dee2e6" : "#222736"
                        border.width: 1

                        RowLayout {
                            id: stationCardMainRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 14

                            // LEFT COLUMN: Station Name, Config Pills, and Modules Pills
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 8

                                // 1. Station Name + Edit Config & JSON Preview Buttons
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        color: stationBreakdownCard.stColor
                                    }

                                    Label {
                                        text: stationBreakdownCard.stName
                                        font.bold: true
                                        font.pixelSize: 14
                                        color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Button {
                                        id: editStBtn
                                        height: 22
                                        background: Rectangle {
                                            radius: 4
                                            color: editStBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#e7f5ff" : "#182842")
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#1c202c")
                                            border.color: editStBtn.hovered ? "#339af0" : (detailsRoot.lightMode ? "#dee2e6" : "#2d3345")
                                        }
                                        contentItem: Text {
                                            text: qsTr("✏️ Config")
                                            font.bold: true
                                            font.pixelSize: 10
                                            color: editStBtn.hovered ? "#339af0" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                            leftPadding: 6; rightPadding: 6
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        ToolTip.visible: hovered
                                        ToolTip.text: qsTr("Edit ground station RF configuration and modules")
                                        onClicked: detailsRoot.editGroundStationConfigRequested(stationBreakdownCard.stId)
                                    }

                                    Button {
                                        id: stJsonBtn
                                        height: 22
                                        background: Rectangle {
                                            radius: 4
                                            color: stJsonBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#252b3b")
                                                   : "transparent"
                                            border.color: detailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                                        }
                                        contentItem: Text {
                                            text: "{ }"
                                            font.bold: true
                                            font.pixelSize: 10
                                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                                            leftPadding: 5; rightPadding: 5
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        ToolTip.visible: hovered
                                        ToolTip.text: qsTr("Preview Station Session Input JSON")
                                        onClicked: detailsRoot.previewStationInputJsonRequested(stationBreakdownCard.stId, stationBreakdownCard.stName)
                                    }
                                }

                                // 2. "Config" Label + Station RF Config Pills
                                Label {
                                    text: qsTr("Config")
                                    font.pixelSize: 12
                                    color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: {
                                            var cfg = stationBreakdownCard.stFullCfg
                                            var badges = []
                                            var band = (cfg && cfg.operatingBand) ? cfg.operatingBand : "C-band"
                                            var gain = (cfg && cfg.antennaGain !== undefined) ? Number(cfg.antennaGain) : 42.0
                                            var gOt = (cfg && cfg.gOverT !== undefined) ? Number(cfg.gOverT) : 17.5
                                            var minEl = (cfg && cfg.minElevation !== undefined) ? Number(cfg.minElevation) : 5.0
                                            badges.push(band)
                                            badges.push("G=" + gain.toFixed(1).replace(/\.0$/, "") + " dBi")
                                            badges.push("G/T=" + gOt.toFixed(1) + " dB/K")
                                            badges.push("El≥" + minEl.toFixed(0) + "°")
                                            return badges
                                        }

                                        Rectangle {
                                            height: 26
                                            width: stCfgPillText.implicitWidth + 16
                                            radius: 6
                                            color: stCfgPillMouse.containsMouse
                                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#232838")
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#181c26")
                                            border.color: stCfgPillMouse.containsMouse
                                                          ? "#339af0"
                                                          : (detailsRoot.lightMode ? "#ced4da" : "#262b3a")
                                            border.width: 1

                                            Text {
                                                id: stCfgPillText
                                                anchors.centerIn: parent
                                                text: modelData
                                                font.pixelSize: 11
                                                color: detailsRoot.lightMode ? "#212529" : "#e9ecef"
                                            }

                                            MouseArea {
                                                id: stCfgPillMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: detailsRoot.editGroundStationConfigRequested(stationBreakdownCard.stId)
                                            }
                                        }
                                    }
                                }

                                // 3. "Modules:" Label + Add Module Controls
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Label {
                                        text: qsTr("Modules:")
                                        font.pixelSize: 12
                                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                    }

                                    Item { Layout.fillWidth: true }

                                    ComboBox {
                                        id: stAddModCombo
                                        Layout.preferredWidth: 130
                                        height: 22
                                        model: detailsRoot.recentModulesList ? detailsRoot.recentModulesList : []
                                        textRole: "name"
                                        font.pixelSize: 10
                                        enabled: count > 0
                                        displayText: currentIndex >= 0 && count > 0
                                                     ? model[currentIndex].name
                                                     : qsTr("Recent .py...")
                                    }

                                    Button {
                                        id: stQuickAddBtn
                                        height: 22
                                        enabled: stAddModCombo.count > 0 && stAddModCombo.currentIndex >= 0
                                        background: Rectangle {
                                            radius: 4
                                            color: stQuickAddBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#d0ebff" : "#1c3352")
                                                   : (detailsRoot.lightMode ? "#e7f5ff" : "#14233c")
                                            border.color: "#339af0"
                                        }
                                        contentItem: Text {
                                            text: qsTr("+ Add")
                                            font.bold: true
                                            font.pixelSize: 10
                                            color: "#339af0"
                                            leftPadding: 6; rightPadding: 6
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            var item = detailsRoot.recentModulesList[stAddModCombo.currentIndex]
                                            if (item && item.path) {
                                                detailsRoot.addRecentStationModuleRequested(stationBreakdownCard.stId, item.path)
                                            }
                                        }
                                    }

                                    Button {
                                        id: stBrowsePyBtn
                                        height: 22
                                        background: Rectangle {
                                            radius: 4
                                            color: stBrowsePyBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#252b3b")
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#181c26")
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3345"
                                        }
                                        contentItem: Text {
                                            text: "📂"
                                            font.pixelSize: 10
                                            leftPadding: 5; rightPadding: 5
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        ToolTip.visible: hovered
                                        ToolTip.text: qsTr("Browse Python factor module (.py) for this station")
                                        onClicked: detailsRoot.browseStationModuleRequested(stationBreakdownCard.stId)
                                    }
                                }

                                // 4. Modules Pills Flow (FSPL Default + Attachable Factor Modules)
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    // Default Locked FSPL Pill (Always On)
                                    Rectangle {
                                        height: 28
                                        width: fsplPillText.implicitWidth + 18
                                        radius: 6
                                        color: detailsRoot.lightMode ? "#e7f5ff" : "#152236"
                                        border.color: "#339af0"
                                        border.width: 1

                                        Text {
                                            id: fsplPillText
                                            anchors.centerIn: parent
                                            text: "FSPL (Free Space Path Loss)"
                                            font.pixelSize: 11
                                            color: detailsRoot.lightMode ? "#1864ab" : "#e9ecef"
                                        }
                                    }

                                    // Attachable Station Python Factor Module Pills
                                    Repeater {
                                        model: stationBreakdownCard.stModulesList

                                        Rectangle {
                                            id: factorPill
                                            readonly property bool isOn: modelData.enabled === true
                                            readonly property bool hasOut: (modelData.outputJson && modelData.outputJson.length > 0) || (modelData.errorText && modelData.errorText.length > 0)
                                            height: 28
                                            width: factorPillRow.implicitWidth + 16
                                            radius: 6
                                            color: isOn
                                                   ? (modelData.status === "error"
                                                      ? (detailsRoot.lightMode ? "#fff5f5" : "#2b1518")
                                                      : (detailsRoot.lightMode ? "#ebfbee" : "#14291d"))
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#181c26")
                                            border.color: isOn
                                                          ? (modelData.status === "error" ? "#fa5252" : "#40c057")
                                                          : (detailsRoot.lightMode ? "#ced4da" : "#262b3a")
                                            border.width: 1

                                            RowLayout {
                                                id: factorPillRow
                                                anchors.centerIn: parent
                                                spacing: 5

                                                // Status dot / toggle indicator
                                                Rectangle {
                                                    width: 6
                                                    height: 6
                                                    radius: 3
                                                    color: {
                                                        if (!factorPill.isOn) return detailsRoot.lightMode ? "#adb5bd" : "#495057"
                                                        if (modelData.status === "running") return "#339af0"
                                                        if (modelData.status === "error") return "#fa5252"
                                                        return "#40c057"
                                                    }
                                                }

                                                // Module Display Name (Click to Toggle ON/OFF)
                                                Text {
                                                    text: detailsRoot.formatModuleDisplayName(modelData.name, modelData.factorName)
                                                          + (modelData.status === "running" ? " (⏳)" : "")
                                                    font.pixelSize: 11
                                                    font.bold: factorPill.isOn
                                                    color: factorPill.isOn
                                                           ? (detailsRoot.lightMode ? "#2b8a3e" : "#8ce99a")
                                                           : (detailsRoot.lightMode ? "#495057" : "#e9ecef")

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            detailsRoot.toggleStationModuleEnabledRequested(
                                                                stationBreakdownCard.stId,
                                                                index,
                                                                !factorPill.isOn
                                                            )
                                                        }
                                                    }
                                                }

                                                // Preview Factor Output JSON mini button
                                                Button {
                                                    visible: factorPill.hasOut
                                                    width: 18
                                                    height: 18
                                                    padding: 0
                                                    background: Rectangle {
                                                        radius: 3
                                                        color: parent.hovered ? (detailsRoot.lightMode ? "#dee2e6" : "#2c3347") : "transparent"
                                                    }
                                                    contentItem: Text {
                                                        text: "{}"
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: "#339af0"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    ToolTip.visible: hovered
                                                    ToolTip.text: qsTr("Inspect Factor Output JSON")
                                                    onClicked: {
                                                        var content = (modelData.outputJson && modelData.outputJson.length > 0)
                                                                      ? modelData.outputJson
                                                                      : ("// Module Error:\n" + (modelData.errorText || "No output"))
                                                        var passIdx = detailsRoot.sessionEvent ? detailsRoot.sessionEvent.passIndex : 1
                                                        detailsRoot.previewJsonModalRequested(
                                                            qsTr("Factor Output JSON — ") + stationBreakdownCard.stName + " (" + modelData.name + ")",
                                                            modelData.factorName
                                                                ? ("factor_name: " + modelData.factorName + (modelData.units ? (" [" + modelData.units + "]") : ""))
                                                                : qsTr("Python factor calculation output"),
                                                            content,
                                                            modelData.name.replace(/\.py$/i, "") + "_" + stationBreakdownCard.stId + "_pass_" + passIdx + ".json"
                                                        )
                                                    }
                                                }

                                                // Remove Factor Module button
                                                Button {
                                                    width: 16
                                                    height: 16
                                                    padding: 0
                                                    background: Rectangle {
                                                        radius: 3
                                                        color: parent.hovered ? "#c92a2a" : "transparent"
                                                    }
                                                    contentItem: Text {
                                                        text: "✕"
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: parent.hovered ? "#ffffff" : (detailsRoot.lightMode ? "#868e96" : "#6c757d")
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    ToolTip.visible: hovered
                                                    ToolTip.text: qsTr("Remove module from station")
                                                    onClicked: {
                                                        detailsRoot.removeStationModuleRequested(stationBreakdownCard.stId, index)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // RIGHT COLUMN: Polar Skyplot (Az/El) + Pass Visibility Time Window Underneath
                            ColumnLayout {
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                Rectangle {
                                    Layout.preferredWidth: 148
                                    Layout.preferredHeight: 148
                                    Layout.minimumWidth: 148
                                    Layout.minimumHeight: 148
                                    Layout.alignment: Qt.AlignHCenter
                                    radius: 8
                                    color: detailsRoot.lightMode ? "#f8f9fa" : "#0d1017"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#222736"
                                    border.width: 1

                                    Canvas {
                                        id: stationPolarCanvas
                                        anchors.fill: parent
                                        antialiasing: true

                                        property var stSnr: stationBreakdownCard.stSnrEntry
                                        property color passColor: stationBreakdownCard.stColor
                                        property int hoverIdx: detailsRoot.hoveredSampleIndex

                                        onStSnrChanged: requestPaint()
                                        onHoverIdxChanged: requestPaint()
                                        onAvailableChanged: {
                                            if (available) {
                                                requestPaint()
                                            }
                                        }
                                        onWidthChanged: requestPaint()
                                        onHeightChanged: requestPaint()

                                        Connections {
                                            target: detailsRoot
                                            function onSnrProfileDataChanged() { stationPolarCanvas.requestPaint() }
                                            function onLightModeChanged() { stationPolarCanvas.requestPaint() }
                                            function onVisibleChanged() {
                                                if (detailsRoot.visible) {
                                                    stationPolarCanvas.requestPaint()
                                                }
                                            }
                                        }

                                        onPaint: {
                                            var ctx = getContext("2d")
                                            var w = width
                                            var h = height
                                            ctx.clearRect(0, 0, w, h)

                                            var cx = w / 2
                                            var cy = h / 2 + 5
                                            var maxR = 52

                                            var isHoverValid = (hoverIdx >= 0 && stSnr && stSnr.isVisible && hoverIdx < stSnr.isVisible.length && stSnr.isVisible[hoverIdx])

                                            // Title / Live Hover Readout
                                            ctx.fillStyle = isHoverValid ? "#ffd43b" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                            ctx.font = isHoverValid ? "bold 8px monospace" : "bold 8.5px sans-serif"
                                            ctx.textAlign = "center"
                                            if (isHoverValid) {
                                                var curAz = Math.round(Number(stSnr.azimuthDeg[hoverIdx]) || 0)
                                                var curEl = Math.round(Number(stSnr.elevationDeg[hoverIdx]) || 0)
                                                ctx.fillText("Az " + curAz + "°  El " + curEl + "°", cx, 11)
                                            } else {
                                                ctx.fillText("Polar Skyplot (Az/El)", cx, 11)
                                            }

                                            // Concentric elevation circles: 0° (outer), 30°, 60°
                                            ctx.strokeStyle = detailsRoot.lightMode ? "#dee2e6" : "#1e2638"
                                            ctx.lineWidth = 1
                                            var rings = [1.0, 2.0 / 3.0, 1.0 / 3.0]
                                            for (var rIdx = 0; rIdx < rings.length; rIdx++) {
                                                ctx.beginPath()
                                                ctx.arc(cx, cy, maxR * rings[rIdx], 0, 2 * Math.PI)
                                                ctx.stroke()
                                            }

                                            // Elevation degree labels along North axis
                                            ctx.fillStyle = detailsRoot.lightMode ? "#adb5bd" : "#495057"
                                            ctx.font = "6.5px sans-serif"
                                            ctx.textAlign = "left"
                                            ctx.fillText("30°", cx + 2, cy - maxR * (2.0 / 3.0) + 6)
                                            ctx.fillText("60°", cx + 2, cy - maxR * (1.0 / 3.0) + 6)

                                            // Crosshair spokes (N-S, E-W)
                                            ctx.beginPath()
                                            ctx.moveTo(cx - maxR, cy); ctx.lineTo(cx + maxR, cy)
                                            ctx.moveTo(cx, cy - maxR); ctx.lineTo(cx, cy + maxR)
                                            ctx.stroke()

                                            // Compass labels (N, E, S, W)
                                            ctx.fillStyle = detailsRoot.lightMode ? "#6c757d" : "#868e96"
                                            ctx.font = "bold 8px monospace"
                                            ctx.textAlign = "center"
                                            ctx.textBaseline = "middle"
                                            ctx.fillText("N", cx, cy - maxR - 6)
                                            ctx.fillText("S", cx, cy + maxR + 7)
                                            ctx.fillText("E", cx + maxR + 6, cy)
                                            ctx.fillText("W", cx - maxR - 6, cy)
                                            ctx.textBaseline = "alphabetic"

                                            // Plot satellite pass trajectory if azimuthDeg & elevationDeg are available
                                            if (stSnr && stSnr.elevationDeg && stSnr.azimuthDeg && stSnr.isVisible) {
                                                var nPts = stSnr.elevationDeg.length
                                                ctx.beginPath()
                                                ctx.strokeStyle = passColor
                                                ctx.lineWidth = 2.0
                                                var started = false
                                                var prevVis = false
                                                var firstX = 0, firstY = 0, lastX = 0, lastY = 0

                                                for (var i = 0; i < nPts; i++) {
                                                    if (!stSnr.isVisible[i]) {
                                                        prevVis = false
                                                        continue
                                                    }
                                                    var el = Math.max(0.0, Math.min(90.0, Number(stSnr.elevationDeg[i]) || 0.0))
                                                    var azDeg = ((Number(stSnr.azimuthDeg[i]) || 0.0) % 360.0 + 360.0) % 360.0
                                                    // 0 deg = North (top), 90 deg = East (right), clockwise
                                                    var azRad = (azDeg - 90.0) * (Math.PI / 180.0)
                                                    var r = maxR * (1.0 - el / 90.0)
                                                    var px = cx + r * Math.cos(azRad)
                                                    var py = cy + r * Math.sin(azRad)

                                                    if (!started || !prevVis) {
                                                        ctx.moveTo(px, py)
                                                        if (!started) {
                                                            firstX = px; firstY = py
                                                            started = true
                                                        }
                                                    } else {
                                                        ctx.lineTo(px, py)
                                                    }
                                                    lastX = px; lastY = py
                                                    prevVis = true
                                                }
                                                if (started) {
                                                    ctx.stroke()

                                                    // AOS (Green) & LOS (Red) dots
                                                    ctx.fillStyle = "#51cf66"
                                                    ctx.beginPath(); ctx.arc(firstX, firstY, 3.2, 0, 2 * Math.PI); ctx.fill()
                                                    ctx.strokeStyle = "#ffffff"
                                                    ctx.lineWidth = 0.8
                                                    ctx.stroke()

                                                    ctx.fillStyle = "#ff6b6b"
                                                    ctx.beginPath(); ctx.arc(lastX, lastY, 3.2, 0, 2 * Math.PI); ctx.fill()
                                                    ctx.stroke()
                                                }

                                                // Hovered sample marker on polar plot
                                                if (isHoverValid && hoverIdx < nPts) {
                                                    var hEl = Math.max(0.0, Math.min(90.0, Number(stSnr.elevationDeg[hoverIdx]) || 0.0))
                                                    var hAzDeg = ((Number(stSnr.azimuthDeg[hoverIdx]) || 0.0) % 360.0 + 360.0) % 360.0
                                                    var hAzRad = (hAzDeg - 90.0) * (Math.PI / 180.0)
                                                    var hR = maxR * (1.0 - hEl / 90.0)
                                                    var hx = cx + hR * Math.cos(hAzRad)
                                                    var hy = cy + hR * Math.sin(hAzRad)
                                                    ctx.fillStyle = "#ffd43b"
                                                    ctx.beginPath(); ctx.arc(hx, hy, 4.2, 0, 2 * Math.PI); ctx.fill()
                                                    ctx.strokeStyle = "#ffffff"
                                                    ctx.lineWidth = 1.0
                                                    ctx.stroke()
                                                }
                                            }
                                        }
                                    }
                                }

                                // AOS -> LOS time range below Polar Skyplot (matching mockup: 22:23:04 -> 22:26:45)
                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (modelData.aosUtc || "") + " → " + (modelData.losUtc || "")
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
