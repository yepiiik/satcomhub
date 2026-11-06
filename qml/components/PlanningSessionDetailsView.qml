import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: detailsRoot

    property var sessionEvent: null
    property var snrProfileData: null
    property bool lightMode: false
    property string activeMetric: "snr" // "snr", "fspl", "totalloss", "elevation"
    property bool showMrcEnvelope: true
    property bool showShannonLimits: true
    property int hoveredSampleIndex: -1

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

    // Session Plan & Transmission AMC parameters
    property string selectedModulation: "QPSK"
    property real bitsPerSymbol: 2.0
    property real rolloffAlpha: 0.20
    property real codeEfficiencyCoef: 1.00
    property real carrierFreqMhz: (snrProfileData && snrProfileData.carrierFreqMhz) ? snrProfileData.carrierFreqMhz : 5840.0
    property real channelBandwidthKhz: (snrProfileData && snrProfileData.channelBandwidthKhz) ? snrProfileData.channelBandwidthKhz : 10000.0

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

    // Exact formula from user screenshot:
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

    readonly property real derivedMeanRMax: {
        if (!snrProfileData || !snrProfileData.combinedSelectionSnrDb) return 0.0
        var sum = 0.0, cnt = 0
        var arr = snrProfileData.combinedSelectionSnrDb
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] > -20.0) {
                sum += calculateRMaxFormula(arr[i], bitsPerSymbol, rolloffAlpha, codeEfficiencyCoef)
                cnt++
            }
        }
        return cnt > 0 ? (sum / cnt) : 0.0
    }

    readonly property real derivedSymbolRateKbaud: (1.0 + rolloffAlpha) > 0 ? (channelBandwidthKhz / (1.0 + rolloffAlpha)) : channelBandwidthKhz
    readonly property real derivedSpectralEfficiency: (bitsPerSymbol * derivedPeakRMax) / (1.0 + rolloffAlpha)
    readonly property real derivedPeakBitrateMbps: (derivedSymbolRateKbaud * bitsPerSymbol * derivedPeakRMax) / 1000.0

    function getTransmissionParams() {
        return {
            "modulation": detailsRoot.selectedModulation,
            "bitsPerSymbol": detailsRoot.bitsPerSymbol,
            "alpha": detailsRoot.rolloffAlpha,
            "codeEfficiencyCoef": detailsRoot.codeEfficiencyCoef,
            "carrierFreqMhz": detailsRoot.carrierFreqMhz,
            "channelBandwidthKhz": detailsRoot.channelBandwidthKhz
        }
    }

    signal previewSessionPlanYamlRequested(var transmissionParams)
    signal exportSessionPlanYamlRequested(var transmissionParams)

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

    function getStationColor(index) {
        return stationColors[index % stationColors.length]
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

        // Allow both horizontal and vertical scrolling
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
            y: 18
            width: mainFlickable.contentWidth - 36
            spacing: 14

            // --- TOP SESSION HEADER BANNER ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerCol.implicitHeight + 24
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: headerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            height: 24
                            width: passNumText.implicitWidth + 14
                            radius: 6
                            color: "#339af0"
                            Text {
                                id: passNumText
                                anchors.centerIn: parent
                                text: detailsRoot.sessionEvent ? ("Pass #" + detailsRoot.sessionEvent.passIndex) : ""
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                            }
                        }

                        Label {
                            text: detailsRoot.snrProfileData ? detailsRoot.snrProfileData.satelliteName : "Satellite Pass"
                            font.bold: true
                            font.pixelSize: 16
                            color: detailsRoot.lightMode ? "#212529" : "#ffffff"
                        }

                        Rectangle {
                            visible: detailsRoot.sessionEvent && detailsRoot.sessionEvent.isMultiStation
                            height: 22
                            width: multiBadge.implicitWidth + 12
                            radius: 11
                            color: detailsRoot.lightMode ? "#ebfbee" : "#132d1d"
                            border.color: "#40c057"
                            Text {
                                id: multiBadge
                                anchors.centerIn: parent
                                text: detailsRoot.sessionEvent ? ("🤝 Multi-Station Diversity: " + detailsRoot.sessionEvent.stationCount + " Stations") : ""
                                font.bold: true
                                font.pixelSize: 10
                                color: "#40c057"
                            }
                        }

                        Rectangle {
                            visible: detailsRoot.sessionEvent && detailsRoot.sessionEvent.hasConcurrentOverlap
                            height: 22
                            width: ovBadge.implicitWidth + 12
                            radius: 11
                            color: detailsRoot.lightMode ? "#fff9db" : "#2d2411"
                            border.color: "#f59f00"
                            Text {
                                id: ovBadge
                                anchors.centerIn: parent
                                text: detailsRoot.sessionEvent ? ("⚡ Overlap: " + detailsRoot.sessionEvent.overlapDurationFormatted) : ""
                                font.bold: true
                                font.pixelSize: 10
                                color: "#f59f00"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            height: 24
                            width: durBadge.implicitWidth + 14
                            radius: 12
                            color: detailsRoot.lightMode ? "#e7f5ff" : "#14233c"
                            Text {
                                id: durBadge
                                anchors.centerIn: parent
                                text: detailsRoot.sessionEvent ? ("⏱️ " + detailsRoot.sessionEvent.combinedDurationFormatted) : ""
                                font.bold: true
                                font.pixelSize: 11
                                color: "#339af0"
                            }
                        }
                    }

                    // Timeline row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Label {
                            text: detailsRoot.sessionEvent ?
                                  ("UTC Window: " + detailsRoot.sessionEvent.combinedAosUtc + " → " + detailsRoot.sessionEvent.combinedLosUtc) : ""
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                        }

                        Label {
                            text: detailsRoot.sessionEvent ? ("Peak Elevation: " + detailsRoot.sessionEvent.maxElevationDeg + "°") : ""
                            font.bold: true
                            font.pixelSize: 11
                            color: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.maxElevationDeg >= 50) ? "#2f9e44" : "#f59f00"
                        }

                        Label {
                            text: detailsRoot.sessionEvent ? ("Stations: " + detailsRoot.sessionEvent.stationNames) : ""
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#ced4da"
                        }
                    }
                }
            }

            // --- PARTICIPATING GROUND STATIONS BREAKDOWN (WITH PER-STATION FACTOR MODULES & POLAR PLOT) ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: qsTr("Participating Ground Stations Breakdown")
                    font.bold: true
                    font.pixelSize: 13
                    color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                }

                Rectangle {
                    height: 20
                    width: graphLossBadgeText.implicitWidth + 14
                    radius: 10
                    color: (detailsRoot.snrProfileData && detailsRoot.snrProfileData.hasExtraAttenuation)
                           ? (detailsRoot.lightMode ? "#ebfbee" : "#132d1d")
                           : (detailsRoot.lightMode ? "#f1f3f5" : "#1e2230")
                    border.color: (detailsRoot.snrProfileData && detailsRoot.snrProfileData.hasExtraAttenuation)
                                  ? "#40c057"
                                  : (detailsRoot.lightMode ? "#ced4da" : "#373a40")
                    border.width: 1
                    Text {
                        id: graphLossBadgeText
                        anchors.centerIn: parent
                        text: (detailsRoot.snrProfileData && detailsRoot.snrProfileData.hasExtraAttenuation)
                              ? "⚡ Extra Factor Losses Applied to Graph"
                              : "Baseline Link Budget (Default FSPL Active)"
                        font.bold: true
                        font.pixelSize: 10
                        color: (detailsRoot.snrProfileData && detailsRoot.snrProfileData.hasExtraAttenuation)
                               ? "#40c057"
                               : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    id: previewSessionInputPopupBtn
                    height: 24
                    background: Rectangle {
                        radius: 6
                        color: previewSessionInputPopupBtn.hovered
                               ? (detailsRoot.lightMode ? "#e7f5ff" : "#1c3352")
                               : (detailsRoot.lightMode ? "#ffffff" : "#141720")
                        border.color: "#339af0"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: "{ } Session Input JSON"
                        font.bold: true
                        font.pixelSize: 10
                        color: "#339af0"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8
                        rightPadding: 8
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

                // Python runtime badge
                Rectangle {
                    height: 24
                    width: pyTopBadgeRow.implicitWidth + 12
                    radius: 12
                    color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available)
                           ? (detailsRoot.lightMode ? "#ebfbee" : "#132d1d")
                           : (detailsRoot.lightMode ? "#fff5f5" : "#2d1418")
                    border.color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available)
                                  ? "#40c057"
                                  : "#fa5252"
                    border.width: 1

                    RowLayout {
                        id: pyTopBadgeRow
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available) ? "#40c057" : "#fa5252"
                        }
                        Text {
                            text: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available)
                                  ? (detailsRoot.pythonEnvInfo.version + (detailsRoot.pythonEnvInfo.isVenv ? " (venv)" : " (Global)"))
                                  : "Python Not Found"
                            font.bold: true
                            font.pixelSize: 10
                            color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available) ? "#40c057" : "#fa5252"
                        }
                    }
                }
            }

            // Participating Ground Station Cards Grid (each station has Pass Geometry + Per-Station Factor Modules + Polar Plot Space)
            GridLayout {
                Layout.fillWidth: true
                columns: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.stationPasses && detailsRoot.sessionEvent.stationPasses.length === 1) ? 1 : 2
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.stationPasses) ? detailsRoot.sessionEvent.stationPasses : []

                    Rectangle {
                        id: stationBreakdownCard
                        readonly property int stationIndex: index
                        readonly property string stId: modelData.stationId || ("GS-" + (index + 1))
                        readonly property string stName: modelData.stationName || ("Station " + (index + 1))
                        readonly property color stColor: detailsRoot.getStationColor(index)
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

                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        implicitHeight: stationCardMainRow.implicitHeight + 22
                        Layout.preferredHeight: implicitHeight
                        radius: 10
                        color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                        border.color: stColor
                        border.width: 1.2

                        RowLayout {
                            id: stationCardMainRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 11
                            spacing: 12

                            // LEFT/CENTER COLUMN: Station Telemetry + Per-Station Factor Modules + Correlation Status
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 7

                                // 1. Station Header & Pass Geometry
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        width: 9; height: 9; radius: 4.5
                                        color: stationBreakdownCard.stColor
                                    }

                                    Label {
                                        text: stationBreakdownCard.stName
                                        font.bold: true
                                        font.pixelSize: 13
                                        color: stationBreakdownCard.stColor
                                    }

                                    Item { Layout.fillWidth: true }

                                    Button {
                                        id: stInputJsonBtn
                                        height: 22
                                        background: Rectangle {
                                            radius: 4
                                            color: stInputJsonBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#e7f5ff" : "#1c3352")
                                                   : (detailsRoot.lightMode ? "#f1f3f5" : "#1a1e29")
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#2d3548"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "{ } Input JSON"
                                            font.bold: true
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 6
                                            rightPadding: 6
                                        }
                                        onClicked: {
                                            detailsRoot.previewStationInputJsonRequested(stationBreakdownCard.stId, stationBreakdownCard.stName)
                                        }
                                    }

                                    Rectangle {
                                        height: 20
                                        width: visTimeTxt.implicitWidth + 12
                                        radius: 10
                                        color: detailsRoot.lightMode ? "#f1f3f5" : "#1c2130"
                                        Text {
                                            id: visTimeTxt
                                            anchors.centerIn: parent
                                            text: "Visible: " + modelData.durationFormatted
                                            font.bold: true
                                            font.pixelSize: 10
                                            color: detailsRoot.lightMode ? "#212529" : "#ffffff"
                                        }
                                    }
                                }

                                // AOS / LOS / TCA / Peak Elevation Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Label {
                                        text: "AOS: " + modelData.aosUtc + " (" + modelData.aosAzimuthCompass + ") → LOS: " + modelData.losUtc + " (" + modelData.losAzimuthCompass + ")"
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                    }

                                    Item { Layout.fillWidth: true }

                                    Label {
                                        text: "TCA: " + modelData.tcaUtc + " • Peak El: " + modelData.maxElevationDeg + "° • " + Math.round(modelData.tcaRangeKm) + " km"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: modelData.maxElevationDeg >= 50.0 ? "#2f9e44" : "#f59f00"
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: detailsRoot.lightMode ? "#e9ecef" : "#222838"
                                }

                                // 2. Per-Station Factor Modules Header & Add Controls
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Label {
                                        text: qsTr("Loss Factor Modules:")
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: detailsRoot.lightMode ? "#343a40" : "#ced4da"
                                    }

                                    ComboBox {
                                        id: stRecentModulesCombo
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 110
                                        height: 24
                                        model: detailsRoot.recentModulesList
                                        textRole: "name"
                                        valueRole: "path"
                                        font.pixelSize: 10

                                        delegate: ItemDelegate {
                                            width: stRecentModulesCombo.width
                                            contentItem: ColumnLayout {
                                                spacing: 1
                                                Text {
                                                    text: modelData.name
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: modelData.path
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                    color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                                    elide: Text.ElideMiddle
                                                    Layout.fillWidth: true
                                                }
                                            }
                                            background: Rectangle {
                                                color: highlighted
                                                       ? (detailsRoot.lightMode ? "#e7f5ff" : "#1e293b")
                                                       : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                            }
                                        }
                                    }

                                    Button {
                                        id: stAddModBtn
                                        height: 24
                                        enabled: detailsRoot.recentModulesList && detailsRoot.recentModulesList.length > 0
                                        background: Rectangle {
                                            radius: 5
                                            color: stAddModBtn.hovered ? "#1c7ed6" : "#228be6"
                                            opacity: stAddModBtn.enabled ? 1.0 : 0.5
                                        }
                                        contentItem: Text {
                                            text: "＋ Add"
                                            font.bold: true
                                            font.pixelSize: 9
                                            color: "#ffffff"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 7
                                            rightPadding: 7
                                        }
                                        onClicked: {
                                            if (stRecentModulesCombo.currentIndex >= 0 && stRecentModulesCombo.currentIndex < detailsRoot.recentModulesList.length) {
                                                var item = detailsRoot.recentModulesList[stRecentModulesCombo.currentIndex]
                                                detailsRoot.addRecentStationModuleRequested(stationBreakdownCard.stId, item.path)
                                            }
                                        }
                                    }

                                    Button {
                                        id: stBrowseModBtn
                                        height: 24
                                        background: Rectangle {
                                            radius: 5
                                            color: stBrowseModBtn.hovered
                                                   ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#181c28")
                                            border.color: "#339af0"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "📂 .py"
                                            font.bold: true
                                            font.pixelSize: 9
                                            color: "#339af0"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            leftPadding: 6
                                            rightPadding: 6
                                        }
                                        onClicked: detailsRoot.browseStationModuleRequested(stationBreakdownCard.stId)
                                    }
                                }

                                // 3. Factor Modules List for THIS Station (Starts with Default Locked FSPL)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    // DEFAULT LOCKED FACTOR MODULE: FSPL (Free Space Path Loss) — Cannot be turned off
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        radius: 5
                                        color: detailsRoot.lightMode ? "#ebfbee" : "#0f1e19"
                                        border.color: detailsRoot.lightMode ? "#b2f2bb" : "#234832"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            // Locked ON Pill (cannot be turned off)
                                            Rectangle {
                                                width: 52
                                                height: 20
                                                radius: 10
                                                color: "#2b8a3e"
                                                border.color: "#40c057"
                                                border.width: 1

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: 2
                                                    Text {
                                                        text: "ON"
                                                        font.bold: true
                                                        font.pixelSize: 8
                                                        color: "#ffffff"
                                                    }
                                                    Text {
                                                        text: "🔒"
                                                        font.pixelSize: 8
                                                    }
                                                }
                                            }

                                            Label {
                                                text: "FSPL (Free Space Path Loss)"
                                                font.bold: true
                                                font.pixelSize: 10
                                                color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                            }

                                            Rectangle {
                                                height: 15
                                                width: fsplUnitBadge.implicitWidth + 8
                                                radius: 4
                                                color: detailsRoot.lightMode ? "#d3f9d8" : "#163624"
                                                Text {
                                                    id: fsplUnitBadge
                                                    anchors.centerIn: parent
                                                    text: "fspl [dB]"
                                                    font.pixelSize: 8
                                                    font.family: "monospace"
                                                    font.bold: true
                                                    color: "#51cf66"
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: stationBreakdownCard.stSnrEntry && stationBreakdownCard.stSnrEntry.minFsplDb < 900
                                                      ? ("Min: " + stationBreakdownCard.stSnrEntry.minFsplDb.toFixed(1) + " dB • Default")
                                                      : "Default (Always Active)"
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                                font.bold: true
                                                color: "#40c057"
                                            }
                                        }
                                    }

                                    // ATTACHABLE PYTHON FACTOR MODULES FOR THIS STATION (Toggled ON/OFF Independently)
                                    Repeater {
                                        model: stationBreakdownCard.stModulesList

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 32
                                            radius: 5
                                            color: modelData.enabled
                                                   ? (detailsRoot.lightMode ? "#ebfbee" : "#11211c")
                                                   : (detailsRoot.lightMode ? "#f8f9fa" : "#151924")
                                            border.color: modelData.status === "error"
                                                          ? "#fa5252"
                                                          : (modelData.enabled
                                                             ? "#40c057"
                                                             : (modelData.status === "running"
                                                                ? "#339af0"
                                                                : (detailsRoot.lightMode ? "#dee2e6" : "#252a3a")))
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 6
                                                spacing: 6

                                                // Independent ON / OFF Toggle Switch for this station's factor module
                                                Button {
                                                    id: stFactorToggleBtn
                                                    implicitWidth: 52
                                                    implicitHeight: 20
                                                    padding: 0
                                                    background: Rectangle {
                                                        radius: 10
                                                        color: modelData.enabled
                                                               ? "#40c057"
                                                               : (detailsRoot.lightMode ? "#ced4da" : "#2c3242")
                                                        border.color: modelData.enabled ? "#2f9e44" : (detailsRoot.lightMode ? "#adb5bd" : "#3b4254")
                                                        border.width: 1

                                                        Rectangle {
                                                            width: 14
                                                            height: 14
                                                            radius: 7
                                                            y: 3
                                                            x: modelData.enabled ? (parent.width - width - 3) : 3
                                                            color: "#ffffff"
                                                            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: modelData.enabled ? 6 : 21
                                                            text: modelData.enabled ? "ON" : "OFF"
                                                            font.bold: true
                                                            font.pixelSize: 8
                                                            color: modelData.enabled ? "#ffffff" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                                        }
                                                    }
                                                    onClicked: {
                                                        detailsRoot.toggleStationModuleEnabledRequested(
                                                            stationBreakdownCard.stId,
                                                            index,
                                                            !modelData.enabled
                                                        )
                                                    }
                                                }

                                                Label {
                                                    text: modelData.name
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                    color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                                }

                                                Rectangle {
                                                    visible: modelData.factorName !== undefined && modelData.factorName !== ""
                                                    height: 15
                                                    width: stFactorMetaTxt.implicitWidth + 8
                                                    radius: 4
                                                    color: detailsRoot.lightMode ? "#e7f5ff" : "#182b49"
                                                    Text {
                                                        id: stFactorMetaTxt
                                                        anchors.centerIn: parent
                                                        text: (modelData.factorName || "") + (modelData.units ? (" [" + modelData.units + "]") : "")
                                                        font.pixelSize: 8
                                                        font.family: "monospace"
                                                        font.bold: true
                                                        color: "#4dabf7"
                                                    }
                                                }

                                                Rectangle {
                                                    height: 15
                                                    width: stModStatusTxt.implicitWidth + 8
                                                    radius: 7
                                                    color: modelData.status === "error"
                                                           ? "#2d1418"
                                                           : (modelData.status === "running"
                                                              ? "#14233c"
                                                              : (modelData.enabled && modelData.status === "done"
                                                                 ? "#132d1d"
                                                                 : (detailsRoot.lightMode ? "#e9ecef" : "#252a38")))
                                                    Text {
                                                        id: stModStatusTxt
                                                        anchors.centerIn: parent
                                                        text: modelData.status === "error"
                                                              ? "Error"
                                                              : (modelData.status === "running"
                                                                 ? "Running..."
                                                                 : (modelData.enabled
                                                                    ? (modelData.status === "done" ? "Applied" : "Queued")
                                                                    : (modelData.status === "done" ? "Cached (OFF)" : "OFF")))
                                                        font.bold: true
                                                        font.pixelSize: 8
                                                        color: modelData.status === "error"
                                                               ? "#ff6b6b"
                                                               : (modelData.status === "running"
                                                                  ? "#4dabf7"
                                                                  : (modelData.enabled && modelData.status === "done"
                                                                     ? "#51cf66"
                                                                     : (detailsRoot.lightMode ? "#6c757d" : "#adb5bd")))
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }

                                                // Preview Factor Output JSON in Modal Popup
                                                Button {
                                                    id: stFactorJsonBtn
                                                    height: 20
                                                    visible: (modelData.outputJson && modelData.outputJson.length > 0) || (modelData.errorText && modelData.errorText.length > 0)
                                                    background: Rectangle {
                                                        radius: 4
                                                        color: stFactorJsonBtn.hovered
                                                               ? (detailsRoot.lightMode ? "#e7f5ff" : "#1c3352")
                                                               : (detailsRoot.lightMode ? "#ffffff" : "#1c2230")
                                                        border.color: modelData.status === "error" ? "#fa5252" : "#339af0"
                                                        border.width: 1
                                                    }
                                                    contentItem: Text {
                                                        text: modelData.status === "error" ? "⚠️ Error" : "{ } JSON"
                                                        font.bold: true
                                                        font.pixelSize: 8
                                                        color: modelData.status === "error" ? "#fa5252" : "#4dabf7"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        leftPadding: 5
                                                        rightPadding: 5
                                                    }
                                                    onClicked: {
                                                        var passIdx = detailsRoot.sessionEvent ? detailsRoot.sessionEvent.passIndex : 1
                                                        detailsRoot.previewJsonModalRequested(
                                                            qsTr("Factor Output JSON — ") + stationBreakdownCard.stName + " (" + modelData.name + ")",
                                                            (modelData.factorName ? ("Factor: " + modelData.factorName + " [" + modelData.units + "] — ") : "") + "Pass #" + passIdx,
                                                            (modelData.outputJson && modelData.outputJson.length > 0) ? modelData.outputJson : modelData.errorText,
                                                            modelData.name.replace(/\.py$/i, "") + "_" + stationBreakdownCard.stId + "_pass_" + passIdx + ".json"
                                                        )
                                                    }
                                                }

                                                // Re-run Factor Module for this Station
                                                Button {
                                                    id: stRerunFactorBtn
                                                    height: 20
                                                    enabled: modelData.status !== "running"
                                                    background: Rectangle {
                                                        radius: 4
                                                        color: stRerunFactorBtn.hovered
                                                               ? (detailsRoot.lightMode ? "#dee2e6" : "#2c3347")
                                                               : (detailsRoot.lightMode ? "#e9ecef" : "#222736")
                                                    }
                                                    contentItem: Text {
                                                        text: modelData.status === "running" ? "⏳" : "↻"
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: detailsRoot.lightMode ? "#495057" : "#ced4da"
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        leftPadding: 5
                                                        rightPadding: 5
                                                    }
                                                    onClicked: {
                                                        detailsRoot.runStationModuleRequested(stationBreakdownCard.stId, index)
                                                    }
                                                }

                                                // Remove Factor Module from this Station
                                                Button {
                                                    id: stRemoveModBtn
                                                    width: 20
                                                    height: 20
                                                    padding: 0
                                                    background: Rectangle {
                                                        radius: 4
                                                        color: stRemoveModBtn.hovered ? "#c92a2a" : "transparent"
                                                    }
                                                    contentItem: Text {
                                                        text: "✕"
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: stRemoveModBtn.hovered ? "#ffffff" : (detailsRoot.lightMode ? "#868e96" : "#909296")
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                    onClicked: {
                                                        detailsRoot.removeStationModuleRequested(stationBreakdownCard.stId, index)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // RIGHT COLUMN: Dedicated Space for Polar Plot (Azimuth/Elevation Skyplot) for this Station
                            Rectangle {
                                Layout.preferredWidth: 162
                                Layout.preferredHeight: 162
                                Layout.minimumWidth: 162
                                Layout.minimumHeight: 162
                                Layout.alignment: Qt.AlignTop
                                radius: 8
                                color: detailsRoot.lightMode ? "#f8f9fa" : "#0d1017"
                                border.color: detailsRoot.lightMode ? "#dee2e6" : "#242a3a"
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

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        var w = width
                                        var h = height
                                        ctx.clearRect(0, 0, w, h)

                                        var cx = w / 2
                                        var cy = h / 2 + 5
                                        var maxR = 58

                                        var isHoverValid = (hoverIdx >= 0 && stSnr && stSnr.isVisible && hoverIdx < stSnr.isVisible.length && stSnr.isVisible[hoverIdx])

                                        // Title / Live Hover Readout
                                        ctx.fillStyle = isHoverValid ? "#ffd43b" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                        ctx.font = isHoverValid ? "bold 8.5px monospace" : "bold 9px sans-serif"
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
                                        ctx.font = "7px sans-serif"
                                        ctx.textAlign = "left"
                                        ctx.fillText("30°", cx + 2, cy - maxR * (2.0 / 3.0) + 7)
                                        ctx.fillText("60°", cx + 2, cy - maxR * (1.0 / 3.0) + 7)

                                        // Crosshair spokes (N-S, E-W)
                                        ctx.beginPath()
                                        ctx.moveTo(cx - maxR, cy); ctx.lineTo(cx + maxR, cy)
                                        ctx.moveTo(cx, cy - maxR); ctx.lineTo(cx, cy + maxR)
                                        ctx.stroke()

                                        // Compass labels (N, E, S, W)
                                        ctx.fillStyle = detailsRoot.lightMode ? "#6c757d" : "#868e96"
                                        ctx.font = "bold 8.5px monospace"
                                        ctx.textAlign = "center"
                                        ctx.textBaseline = "middle"
                                        ctx.fillText("N", cx, cy - maxR - 6)
                                        ctx.fillText("S", cx, cy + maxR + 7)
                                        ctx.fillText("E", cx + maxR + 7, cy)
                                        ctx.fillText("W", cx - maxR - 7, cy)
                                        ctx.textBaseline = "alphabetic" // reset

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
                                                ctx.beginPath(); ctx.arc(firstX, firstY, 3.5, 0, 2 * Math.PI); ctx.fill()
                                                ctx.strokeStyle = "#ffffff"
                                                ctx.lineWidth = 1
                                                ctx.stroke()

                                                ctx.fillStyle = "#ff6b6b"
                                                ctx.beginPath(); ctx.arc(lastX, lastY, 3.5, 0, 2 * Math.PI); ctx.fill()
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
                                                ctx.beginPath(); ctx.arc(hx, hy, 4.5, 0, 2 * Math.PI); ctx.fill()
                                                ctx.strokeStyle = "#ffffff"
                                                ctx.lineWidth = 1.2
                                                ctx.stroke()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- SESSION-WIDE CORRELATION MODULE BAR (ONE FOR THE SESSION, ABOVE GRAPH) ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sessionCorrCol.implicitHeight + 20
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: sessionCorrCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 6
                            color: detailsRoot.lightMode ? "#fff3bf" : "#2d2411"
                            border.color: "#f59f00"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "📊"
                                font.pixelSize: 13
                            }
                        }

                        Label {
                            text: qsTr("Session Correlation Module:")
                            font.bold: true
                            font.pixelSize: 12
                            color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                        }

                        ComboBox {
                            id: corrModuleCombo
                            Layout.preferredWidth: 195
                            height: 28
                            model: detailsRoot.recentCorrelationModulesList
                            textRole: "name"
                            valueRole: "path"
                            font.pixelSize: 11

                            onActivated: function(idx) {
                                if (idx >= 0 && idx < detailsRoot.recentCorrelationModulesList.length) {
                                    detailsRoot.correlationModuleSelected(detailsRoot.recentCorrelationModulesList[idx].path)
                                }
                            }

                            delegate: ItemDelegate {
                                width: corrModuleCombo.width
                                contentItem: ColumnLayout {
                                    spacing: 1
                                    Text {
                                        text: modelData.name
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.path
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }
                                background: Rectangle {
                                    color: highlighted
                                           ? (detailsRoot.lightMode ? "#fff3bf" : "#2d2411")
                                           : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                }
                            }
                        }

                        Button {
                            id: browseCorrModBtn
                            height: 28
                            background: Rectangle {
                                radius: 6
                                color: browseCorrModBtn.hovered
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                       : (detailsRoot.lightMode ? "#f8f9fa" : "#181c28")
                                border.color: "#f59f00"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "📂 Browse (.py)"
                                font.bold: true
                                font.pixelSize: 10
                                color: "#f59f00"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                                rightPadding: 8
                            }
                            onClicked: detailsRoot.browseCorrelationModuleRequested()
                        }

                        Rectangle {
                            width: 1; height: 18
                            color: detailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                        }

                        Label {
                            text: qsTr("Lookup Table (.xlsx):")
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                        }

                        ComboBox {
                            id: excelFileCombo
                            Layout.preferredWidth: 195
                            height: 28
                            model: detailsRoot.recentExcelFilesList
                            textRole: "name"
                            valueRole: "path"
                            font.pixelSize: 11

                            onActivated: function(idx) {
                                if (idx >= 0 && idx < detailsRoot.recentExcelFilesList.length) {
                                    detailsRoot.excelFileSelected(detailsRoot.recentExcelFilesList[idx].path)
                                }
                            }

                            delegate: ItemDelegate {
                                width: excelFileCombo.width
                                contentItem: ColumnLayout {
                                    spacing: 1
                                    Text {
                                        text: modelData.name
                                        font.bold: true
                                        font.pixelSize: 11
                                        color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.path
                                        font.pixelSize: 9
                                        font.family: "monospace"
                                        color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }
                                background: Rectangle {
                                    color: highlighted
                                           ? (detailsRoot.lightMode ? "#ebfbee" : "#132d1d")
                                           : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                }
                            }
                        }

                        Button {
                            id: browseExcelBtn
                            height: 28
                            background: Rectangle {
                                radius: 6
                                color: browseExcelBtn.hovered
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                       : (detailsRoot.lightMode ? "#f8f9fa" : "#181c28")
                                border.color: "#40c057"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "📊 Browse (.xlsx)"
                                font.bold: true
                                font.pixelSize: 10
                                color: "#40c057"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                                rightPadding: 8
                            }
                            onClicked: detailsRoot.browseExcelFileRequested()
                        }

                        Item { Layout.fillWidth: true }

                        // Per-Station Correlated Attenuation Badges & JSON Preview Buttons
                        Repeater {
                            model: detailsRoot.stationCorrelationModel

                            Rectangle {
                                height: 28
                                width: stCorrPillRow.implicitWidth + 14
                                radius: 6
                                color: detailsRoot.lightMode ? "#f8f9fa" : "#10131c"
                                border.color: model.status === "error"
                                              ? "#fa5252"
                                              : ((model.status === "done" || model.status === "warning")
                                                 ? "#40c057"
                                                 : (detailsRoot.lightMode ? "#dee2e6" : "#252a3a"))
                                border.width: 1

                                RowLayout {
                                    id: stCorrPillRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Rectangle {
                                        width: 7; height: 7; radius: 3.5
                                        color: detailsRoot.getStationColor(index)
                                    }

                                    Text {
                                        text: model.stationName + ":"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: detailsRoot.getStationColor(index)
                                    }

                                    Text {
                                        text: {
                                            if (model.status === "error") return "Error"
                                            if (model.status === "running") return "Correlating..."
                                            if (model.status === "done" || model.status === "warning") {
                                                var pk = model.peakAttenuationDb !== undefined ? Number(model.peakAttenuationDb) : 0.0
                                                return "-" + pk.toFixed(1) + " dB peak"
                                            }
                                            return "0.0 dB extra"
                                        }
                                        font.bold: true
                                        font.pixelSize: 10
                                        font.family: "monospace"
                                        color: (model.status === "done" || model.status === "warning")
                                               ? "#fcc419"
                                               : (detailsRoot.lightMode ? "#6c757d" : "#909296")
                                    }

                                    Button {
                                        id: corrInMiniBtn
                                        height: 20
                                        visible: model.inputJson && model.inputJson.length > 0
                                        background: Rectangle {
                                            radius: 4
                                            color: corrInMiniBtn.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a") : "transparent"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "{ } In"
                                            font.bold: true
                                            font.pixelSize: 8
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                            leftPadding: 4; rightPadding: 4
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            detailsRoot.previewJsonModalRequested(
                                                qsTr("Correlation Input JSON — ") + model.stationName,
                                                qsTr("Per-station factor arrays sent to session correlation module"),
                                                model.inputJson,
                                                "correlation_input_" + (model.stationId || "station") + ".json"
                                            )
                                        }
                                    }

                                    Button {
                                        id: corrOutMiniBtn
                                        height: 20
                                        visible: (model.outputJson && model.outputJson.length > 0) || (model.errorText && model.errorText.length > 0)
                                        background: Rectangle {
                                            radius: 4
                                            color: corrOutMiniBtn.hovered ? (detailsRoot.lightMode ? "#fff3bf" : "#3b2e14") : "transparent"
                                            border.color: model.status === "error" ? "#fa5252" : "#f59f00"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "{ } Out"
                                            font.bold: true
                                            font.pixelSize: 8
                                            color: model.status === "error" ? "#fa5252" : "#fcc419"
                                            leftPadding: 4; rightPadding: 4
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        onClicked: {
                                            var corrModName = detailsRoot.selectedCorrelationModulePath ? detailsRoot.selectedCorrelationModulePath.split("/").pop() : "step_correlation.py"
                                            detailsRoot.previewJsonModalRequested(
                                                qsTr("Predicted Attenuation Output JSON — ") + model.stationName,
                                                "Correlated via " + corrModName + " (" + (model.expectedSamples || 0) + " visible samples)",
                                                (model.outputJson && model.outputJson.length > 0) ? model.outputJson : model.errorText,
                                                "predicted_attenuation_" + (model.stationId || "station") + ".json"
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- CONTROLS & METRIC TABS ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    spacing: 4

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
            }

            // --- LIVE CROSSHAIR TELEMETRY HUD ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                Layout.preferredHeight: 36
                radius: 6
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"

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

                    Rectangle { width: 1; height: 18; color: detailsRoot.lightMode ? "#ced4da" : "#373a40" }

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
                                    color: detailsRoot.getStationColor(index)
                                }
                                Text {
                                    text: modelData.stationName + ":"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.getStationColor(index)
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

                    Rectangle { width: 1; height: 18; color: detailsRoot.lightMode ? "#ced4da" : "#373a40" }

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
                }
            }

            // --- EMBEDDED SNR CANVAS PLOT ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 320
                Layout.preferredHeight: 320
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
                    property real paddingTop: 25
                    property real paddingBottom: 40

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

                        // Station Curves
                        for (var sIdx = 0; sIdx < data.stations.length; sIdx++) {
                            var station = data.stations[sIdx]
                            var col = detailsRoot.getStationColor(sIdx)
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
                                grad.addColorStop(0, col + "26")
                                grad.addColorStop(1, col + "00")
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

            // --- TRANSMISSION PARAMETERS & SESSION PLAN (AMC) ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: amcSectionCol.implicitHeight + 28
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: amcSectionCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    // Header Row with Title and Action Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 30
                            height: 30
                            radius: 6
                            color: "#e67700"
                            Text {
                                anchors.centerIn: parent
                                text: "📡"
                                font.pixelSize: 15
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                text: qsTr("Transmission Parameters & Adaptive Coding (Session Plan)")
                                font.bold: true
                                font.pixelSize: 14
                                color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                            }

                            Label {
                                text: qsTr("Configure modulation, roll-off α, and code efficiency to compute r_max and generate the YAML session plan")
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                            }
                        }

                        Button {
                            id: previewPlanBtn
                            text: qsTr("👁️ Preview YAML Plan")
                            implicitHeight: 32
                            background: Rectangle {
                                radius: 6
                                color: previewPlanBtn.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#2c2e33") : (detailsRoot.lightMode ? "#f1f3f5" : "#1a1b1e")
                                border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: previewPlanBtn.text
                                font.bold: true
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: detailsRoot.previewSessionPlanYamlRequested(detailsRoot.getTransmissionParams())
                        }

                        Button {
                            id: exportPlanBtn
                            text: qsTr("💾 Export Session Plan (.yaml)")
                            implicitHeight: 32
                            background: Rectangle {
                                radius: 6
                                color: exportPlanBtn.hovered ? "#d9480f" : "#e67700"
                            }
                            contentItem: Text {
                                text: exportPlanBtn.text
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: detailsRoot.exportSessionPlanYamlRequested(detailsRoot.getTransmissionParams())
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: detailsRoot.lightMode ? "#f1f3f5" : "#1e2230"
                    }

                    // Three-Column Parameter Inputs Grid
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        // 1. Modulation Scheme (QLineEdit + QCompleter)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 260
                            spacing: 4

                            RowLayout {
                                spacing: 6
                                Label {
                                    text: qsTr("1. Modulation Scheme:")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#343a40" : "#ced4da"
                                }
                                Rectangle {
                                    height: 18
                                    width: modBitsBadgeText.implicitWidth + 10
                                    radius: 4
                                    color: detailsRoot.lightMode ? "#e7f5ff" : "#102a45"
                                    border.color: "#339af0"
                                    border.width: 1
                                    Text {
                                        id: modBitsBadgeText
                                        anchors.centerIn: parent
                                        text: "m = " + detailsRoot.bitsPerSymbol.toFixed(0) + " bits/sym"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#339af0"
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                height: 32

                                TextField {
                                    id: modInput
                                    anchors.fill: parent
                                    anchors.rightMargin: 28
                                    text: detailsRoot.selectedModulation
                                    placeholderText: qsTr("Type or pick (e.g. QPSK, 16APSK)...")
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: detailsRoot.lightMode ? "#212529" : "#ffffff"
                                    selectByMouse: true
                                    background: Rectangle {
                                        radius: 6
                                        color: detailsRoot.lightMode ? "#f8f9fa" : "#1a1b1e"
                                        border.color: modInput.activeFocus ? "#339af0" : (detailsRoot.lightMode ? "#ced4da" : "#373a40")
                                        border.width: 1
                                    }

                                    onTextChanged: {
                                        if (text !== detailsRoot.selectedModulation) {
                                            detailsRoot.selectedModulation = text
                                            detailsRoot.bitsPerSymbol = detailsRoot.deriveBitsPerSymbol(text)
                                        }
                                    }

                                    onActiveFocusChanged: {
                                        if (activeFocus) {
                                            modCompleterPopup.open()
                                        }
                                    }
                                }

                                Button {
                                    id: modDropBtn
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 26
                                    background: Rectangle {
                                        radius: 4
                                        color: modDropBtn.hovered ? (detailsRoot.lightMode ? "#e9ecef" : "#2c2e33") : "transparent"
                                    }
                                    contentItem: Text {
                                        text: "▼"
                                        font.pixelSize: 9
                                        color: detailsRoot.lightMode ? "#495057" : "#adb5bd"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        if (modCompleterPopup.opened) {
                                            modCompleterPopup.close()
                                        } else {
                                            modInput.forceActiveFocus()
                                            modCompleterPopup.open()
                                        }
                                    }
                                }

                                Popup {
                                    id: modCompleterPopup
                                    y: parent.height + 4
                                    width: Math.max(parent.width, 240)
                                    height: Math.min(260, completerCol.implicitHeight + 12)
                                    padding: 6
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                                    background: Rectangle {
                                        radius: 8
                                        color: detailsRoot.lightMode ? "#ffffff" : "#1c1f26"
                                        border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                        border.width: 1
                                    }

                                    ScrollView {
                                        anchors.fill: parent
                                        clip: true
                                        ColumnLayout {
                                            id: completerCol
                                            width: parent.width
                                            spacing: 2

                                            Repeater {
                                                model: {
                                                    var query = modInput.text.trim().toUpperCase()
                                                    var matches = []
                                                    for (var i = 0; i < detailsRoot.modulationPresets.length; i++) {
                                                        var p = detailsRoot.modulationPresets[i]
                                                        if (query === "" || p.name.toUpperCase().indexOf(query) !== -1) {
                                                            matches.push(p)
                                                        }
                                                    }
                                                    return matches.length > 0 ? matches : detailsRoot.modulationPresets
                                                }

                                                delegate: Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 28
                                                    radius: 4
                                                    color: modPresetMouse.containsMouse ? (detailsRoot.lightMode ? "#e7f5ff" : "#1e293b") : "transparent"

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 8

                                                        Text {
                                                            text: modelData.name
                                                            font.bold: true
                                                            font.pixelSize: 12
                                                            color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        Text {
                                                            text: "log₂(M)=" + modelData.bits + " bits/sym"
                                                            font.pixelSize: 10
                                                            color: detailsRoot.lightMode ? "#6c757d" : "#94a3b8"
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: modPresetMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            modInput.text = modelData.name
                                                            detailsRoot.selectedModulation = modelData.name
                                                            detailsRoot.bitsPerSymbol = modelData.bits
                                                            modCompleterPopup.close()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Roll-off Factor (alpha)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 230
                            spacing: 4

                            RowLayout {
                                spacing: 6
                                Label {
                                    text: qsTr("2. Roll-off Factor (α):")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#343a40" : "#ced4da"
                                }
                                Rectangle {
                                    height: 18
                                    width: alphaBadgeText.implicitWidth + 10
                                    radius: 4
                                    color: detailsRoot.lightMode ? "#fff4e6" : "#382405"
                                    border.color: "#f59f00"
                                    border.width: 1
                                    Text {
                                        id: alphaBadgeText
                                        anchors.centerIn: parent
                                        text: "α = " + detailsRoot.rolloffAlpha.toFixed(2)
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#f59f00"
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [0.20, 0.25, 0.35]
                                    delegate: Button {
                                        id: alphaPillBtn
                                        text: modelData.toFixed(2)
                                        Layout.preferredWidth: 44
                                        height: 32
                                        background: Rectangle {
                                            radius: 6
                                            color: Math.abs(detailsRoot.rolloffAlpha - modelData) < 0.001
                                                   ? (detailsRoot.lightMode ? "#f59f00" : "#e67700")
                                                   : (alphaPillBtn.hovered ? (detailsRoot.lightMode ? "#f1f3f5" : "#2c2e33") : (detailsRoot.lightMode ? "#f8f9fa" : "#1a1b1e"))
                                            border.color: Math.abs(detailsRoot.rolloffAlpha - modelData) < 0.001 ? "#f59f00" : (detailsRoot.lightMode ? "#ced4da" : "#373a40")
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: alphaPillBtn.text
                                            font.bold: true
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: Math.abs(detailsRoot.rolloffAlpha - modelData) < 0.001 ? "#ffffff" : (detailsRoot.lightMode ? "#495057" : "#adb5bd")
                                        }
                                        onClicked: detailsRoot.rolloffAlpha = modelData
                                    }
                                }

                                RowLayout {
                                    spacing: 2
                                    Button {
                                        text: "−"
                                        Layout.preferredWidth: 26
                                        height: 32
                                        background: Rectangle {
                                            radius: 4
                                            color: detailsRoot.lightMode ? "#e9ecef" : "#25262b"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "−"
                                            font.bold: true
                                            font.pixelSize: 13
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                        }
                                        onClicked: detailsRoot.rolloffAlpha = Math.max(0.05, Math.round((detailsRoot.rolloffAlpha - 0.05) * 100) / 100)
                                    }
                                    Button {
                                        text: "+"
                                        Layout.preferredWidth: 26
                                        height: 32
                                        background: Rectangle {
                                            radius: 4
                                            color: detailsRoot.lightMode ? "#e9ecef" : "#25262b"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "+"
                                            font.bold: true
                                            font.pixelSize: 13
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                        }
                                        onClicked: detailsRoot.rolloffAlpha = Math.min(0.50, Math.round((detailsRoot.rolloffAlpha + 0.05) * 100) / 100)
                                    }
                                }
                            }
                        }

                        // 3. Code Efficiency Coef (Gamma)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 220
                            spacing: 4

                            RowLayout {
                                spacing: 6
                                Label {
                                    text: qsTr("3. Code Efficiency Coef (Γ):")
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#343a40" : "#ced4da"
                                }
                                Rectangle {
                                    height: 18
                                    width: gammaBadgeText.implicitWidth + 10
                                    radius: 4
                                    color: detailsRoot.lightMode ? "#f8f0fc" : "#2c1736"
                                    border.color: "#da77f2"
                                    border.width: 1
                                    Text {
                                        id: gammaBadgeText
                                        anchors.centerIn: parent
                                        text: "Γ = " + detailsRoot.codeEfficiencyCoef.toFixed(2)
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#da77f2"
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 32
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#f8f9fa" : "#1a1b1e"
                                    border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: detailsRoot.codeEfficiencyCoef.toFixed(2)
                                        font.bold: true
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        color: detailsRoot.lightMode ? "#212529" : "#ffffff"
                                    }
                                }

                                RowLayout {
                                    spacing: 2
                                    Button {
                                        text: "−"
                                        Layout.preferredWidth: 26
                                        height: 32
                                        background: Rectangle {
                                            radius: 4
                                            color: detailsRoot.lightMode ? "#e9ecef" : "#25262b"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "−"
                                            font.bold: true
                                            font.pixelSize: 13
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                        }
                                        onClicked: detailsRoot.codeEfficiencyCoef = Math.max(0.10, Math.round((detailsRoot.codeEfficiencyCoef - 0.05) * 100) / 100)
                                    }
                                    Button {
                                        text: "+"
                                        Layout.preferredWidth: 26
                                        height: 32
                                        background: Rectangle {
                                            radius: 4
                                            color: detailsRoot.lightMode ? "#e9ecef" : "#25262b"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "+"
                                            font.bold: true
                                            font.pixelSize: 13
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                        }
                                        onClicked: detailsRoot.codeEfficiencyCoef = Math.min(10.00, Math.round((detailsRoot.codeEfficiencyCoef + 0.05) * 100) / 100)
                                    }
                                    Button {
                                        text: "1.0"
                                        Layout.preferredWidth: 32
                                        height: 32
                                        background: Rectangle {
                                            radius: 4
                                            color: detailsRoot.lightMode ? "#e9ecef" : "#25262b"
                                            border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                            border.width: 1
                                        }
                                        contentItem: Text {
                                            text: "1.0"
                                            font.bold: true
                                            font.pixelSize: 10
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                        }
                                        onClicked: detailsRoot.codeEfficiencyCoef = 1.00
                                    }
                                }
                            }
                        }
                    }

                    // Formula Banner & Live Derivations Card
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: formulaInnerCol.implicitHeight + 16
                        Layout.preferredHeight: implicitHeight
                        radius: 8
                        color: detailsRoot.lightMode ? "#f8f9fa" : "#0d1117"
                        border.color: detailsRoot.lightMode ? "#e9ecef" : "#30363d"
                        border.width: 1

                        ColumnLayout {
                            id: formulaInnerCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "📐 Key Shannon-Hartley AMC Formula:"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#495057" : "#8b949e"
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    height: 22
                                    width: formulaFormulaText.implicitWidth + 14
                                    radius: 4
                                    color: detailsRoot.lightMode ? "#e7f5ff" : "#161b22"
                                    border.color: "#339af0"
                                    border.width: 1
                                    Text {
                                        id: formulaFormulaText
                                        anchors.centerIn: parent
                                        text: "r_max = [ 1 / (bits_per_symbol · (1 + α)) ] · log₂( 1 + 10^(SNR_dB / 10) / Code_efficiency_coef )"
                                        font.family: "Consolas, 'Courier New', monospace"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: "#339af0"
                                    }
                                }
                            }

                            // Metrics Badges Row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Peak r_max
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 44
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#ffffff" : "#161b22"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#21262d"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            text: "Peak r_max"
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#6c757d" : "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: detailsRoot.derivedPeakRMax.toFixed(3)
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                            color: "#fab005"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                // Mean r_max
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 44
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#ffffff" : "#161b22"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#21262d"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            text: "Mean r_max"
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#6c757d" : "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: detailsRoot.derivedMeanRMax.toFixed(3)
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                            color: "#ffd43b"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                // Spectral Efficiency
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 44
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#ffffff" : "#161b22"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#21262d"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            text: "Spectral Efficiency (η)"
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#6c757d" : "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: detailsRoot.derivedSpectralEfficiency.toFixed(2) + " bps/Hz"
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                            color: "#51cf66"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                // Symbol Rate
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 44
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#ffffff" : "#161b22"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#21262d"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            text: "Symbol Rate (Rs)"
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#6c757d" : "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: Math.round(detailsRoot.derivedSymbolRateKbaud) + " kbaud"
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                            color: "#339af0"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }

                                // Peak Bitrate
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 44
                                    radius: 6
                                    color: detailsRoot.lightMode ? "#ffffff" : "#161b22"
                                    border.color: detailsRoot.lightMode ? "#dee2e6" : "#21262d"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1
                                        Text {
                                            text: "Est. Peak Bitrate"
                                            font.pixelSize: 9
                                            color: detailsRoot.lightMode ? "#6c757d" : "#8b949e"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: detailsRoot.derivedPeakBitrateMbps.toFixed(2) + " Mbps"
                                            font.bold: true
                                            font.pixelSize: 13
                                            font.family: "monospace"
                                            color: "#ff922b"
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function syncCorrelationCombos() {
        if (recentCorrelationModulesList && selectedCorrelationModulePath) {
            for (var i = 0; i < recentCorrelationModulesList.length; i++) {
                if (recentCorrelationModulesList[i].path === selectedCorrelationModulePath) {
                    corrModuleCombo.currentIndex = i
                    break
                }
            }
        }
        if (recentExcelFilesList && selectedExcelFilePath) {
            for (var j = 0; j < recentExcelFilesList.length; j++) {
                if (recentExcelFilesList[j].path === selectedExcelFilePath) {
                    excelFileCombo.currentIndex = j
                    break
                }
            }
        }
    }

    onSelectedCorrelationModulePathChanged: syncCorrelationCombos()
    onSelectedExcelFilePathChanged: syncCorrelationCombos()
    onRecentCorrelationModulesListChanged: syncCorrelationCombos()
    onRecentExcelFilesListChanged: syncCorrelationCombos()

    onSnrProfileDataChanged: {
        hoveredSampleIndex = -1
        embeddedPlotCanvas.requestPaint()
    }
}
