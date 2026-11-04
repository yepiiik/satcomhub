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

    // Python Factor Calculation Modules state & models
    property var addedModulesModel: null
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

    signal browseModuleRequested()
    signal addRecentModuleRequested(string modulePath)
    signal removeAddedModuleRequested(int index)
    signal runModuleRequested(int index, string modulePath)
    signal runAllModulesRequested()
    signal generateInputJsonPreviewRequested()

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
                                        if (detailsRoot.activeMetric === "snr") return modelData.snrDb[idx].toFixed(1) + " dB (El: " + modelData.elevationDeg[idx].toFixed(1) + "°)"
                                        if (detailsRoot.activeMetric === "fspl") return modelData.fsplLossDb[idx].toFixed(1) + " dB"
                                        if (detailsRoot.activeMetric === "totalloss") return modelData.totalLossDb[idx].toFixed(1) + " dB"
                                        return modelData.elevationDeg[idx].toFixed(1) + "°"
                                    }
                                }
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
                            if (metric === "snr") vec = station.snrDb
                            else if (metric === "fspl") vec = station.fsplLossDb
                            else if (metric === "totalloss") vec = station.totalLossDb
                            else if (metric === "elevation") vec = station.elevationDeg

                            if (!vec || vec.length !== N) continue

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

            // --- PARTICIPATING GROUND STATIONS BREAKDOWN CARDS ---
            Label {
                text: qsTr("Participating Ground Stations Breakdown")
                font.bold: true
                font.pixelSize: 13
                color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Repeater {
                    model: (detailsRoot.sessionEvent && detailsRoot.sessionEvent.stationPasses) ? detailsRoot.sessionEvent.stationPasses : []

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 90
                        Layout.preferredHeight: 90
                        radius: 8
                        color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                        border.color: detailsRoot.getStationColor(index)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: detailsRoot.getStationColor(index)
                                }
                                Label {
                                    text: modelData.stationName
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: detailsRoot.getStationColor(index)
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Visible: " + modelData.durationFormatted
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: detailsRoot.lightMode ? "#212529" : "#ffffff"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: "AOS: " + modelData.aosUtc + " (" + modelData.aosAzimuthCompass + ") → LOS: " + modelData.losUtc + " (" + modelData.losAzimuthCompass + ")"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: "TCA: " + modelData.tcaUtc + " (" + modelData.tcaAzimuthCompass + ") • Peak El: " + modelData.maxElevationDeg + "°"
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: modelData.maxElevationDeg >= 50.0 ? "#2f9e44" : "#f59f00"
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: "TCA Range: " + Math.round(modelData.tcaRangeKm) + " km"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                }
                            }
                        }
                    }
                }
            }

            // --- 1. PYTHON MODULAR SIGNAL LOSS FACTORS SECTION ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: pythonSectionCol.implicitHeight + 28
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: pythonSectionCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    // Section Title & Runtime Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 7
                            color: detailsRoot.lightMode ? "#e7f5ff" : "#14233c"
                            border.color: "#339af0"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "🐍"
                                font.pixelSize: 15
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Label {
                                text: qsTr("Modular Signal Loss Factors (Python Calculation Modules)")
                                font.bold: true
                                font.pixelSize: 14
                                color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                            }
                            Label {
                                text: qsTr("Attach external Python modules to evaluate environmental factors (e.g., LOS rain density) for this session.")
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Python runtime badge
                        Rectangle {
                            height: 24
                            width: pyBadgeRow.implicitWidth + 14
                            radius: 12
                            color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available)
                                   ? (detailsRoot.lightMode ? "#ebfbee" : "#132d1d")
                                   : (detailsRoot.lightMode ? "#fff5f5" : "#2d1418")
                            border.color: (detailsRoot.pythonEnvInfo && detailsRoot.pythonEnvInfo.available)
                                          ? "#40c057"
                                          : "#fa5252"
                            border.width: 1

                            RowLayout {
                                id: pyBadgeRow
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

                    // Toolbar: Select from Recent Modules | Browse Computer | Inspect Session Input JSON | Run All
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("Recent Modules:")
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                        }

                        ComboBox {
                            id: recentModulesCombo
                            Layout.preferredWidth: 230
                            height: 32
                            model: detailsRoot.recentModulesList
                            textRole: "name"
                            valueRole: "path"
                            font.pixelSize: 11

                            delegate: ItemDelegate {
                                width: recentModulesCombo.width
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
                                           ? (detailsRoot.lightMode ? "#e7f5ff" : "#1e293b")
                                           : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                }
                            }
                        }

                        Button {
                            id: addRecentBtn
                            height: 32
                            enabled: detailsRoot.recentModulesList && detailsRoot.recentModulesList.length > 0
                            background: Rectangle {
                                radius: 6
                                color: addRecentBtn.hovered ? "#1c7ed6" : "#228be6"
                                opacity: addRecentBtn.enabled ? 1.0 : 0.5
                            }
                            contentItem: Text {
                                text: "＋ Add Selected"
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: {
                                if (recentModulesCombo.currentIndex >= 0 && recentModulesCombo.currentIndex < detailsRoot.recentModulesList.length) {
                                    var item = detailsRoot.recentModulesList[recentModulesCombo.currentIndex]
                                    detailsRoot.addRecentModuleRequested(item.path)
                                }
                            }
                        }

                        Button {
                            id: browseModBtn
                            height: 32
                            background: Rectangle {
                                radius: 6
                                color: browseModBtn.hovered
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                       : (detailsRoot.lightMode ? "#f1f3f5" : "#1e2230")
                                border.color: "#339af0"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "📂 Browse Module (.py)..."
                                font.bold: true
                                font.pixelSize: 11
                                color: "#339af0"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: detailsRoot.browseModuleRequested()
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: previewInputBtn
                            height: 32
                            background: Rectangle {
                                radius: 6
                                color: detailsRoot.showInputJsonPreview
                                       ? (detailsRoot.lightMode ? "#d0ebff" : "#1c3352")
                                       : (previewInputBtn.hovered
                                          ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                          : "transparent")
                                border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: detailsRoot.showInputJsonPreview ? "{ } Hide Input JSON" : "{ } View Input JSON"
                                font.bold: true
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: {
                                if (!detailsRoot.showInputJsonPreview) {
                                    detailsRoot.generateInputJsonPreviewRequested()
                                }
                                detailsRoot.showInputJsonPreview = !detailsRoot.showInputJsonPreview
                            }
                        }

                        Button {
                            id: runAllBtn
                            height: 32
                            enabled: detailsRoot.addedModulesModel && detailsRoot.addedModulesModel.count > 0
                            background: Rectangle {
                                radius: 6
                                color: runAllBtn.hovered ? "#2b8a3e" : "#2f9e44"
                                opacity: runAllBtn.enabled ? 1.0 : 0.45
                            }
                            contentItem: Text {
                                text: "▶ Run All Modules"
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 12
                                rightPadding: 12
                            }
                            onClicked: detailsRoot.runAllModulesRequested()
                        }
                    }

                    // Collapsible Session Input JSON Preview
                    Rectangle {
                        visible: detailsRoot.showInputJsonPreview
                        Layout.fillWidth: true
                        implicitHeight: visible ? 170 : 0
                        Layout.preferredHeight: implicitHeight
                        radius: 8
                        color: detailsRoot.lightMode ? "#f8f9fa" : "#0d1017"
                        border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Generated Session Prediction Input JSON (sent to Python stdin):")
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: "#339af0"
                                }
                                Item { Layout.fillWidth: true }
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                TextArea {
                                    text: detailsRoot.sessionInputJsonPreview
                                    readOnly: true
                                    selectByMouse: true
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    color: detailsRoot.lightMode ? "#212529" : "#e9ecef"
                                    background: null
                                }
                            }
                        }
                    }

                    // Empty state when no modules added yet
                    Rectangle {
                        visible: !detailsRoot.addedModulesModel || detailsRoot.addedModulesModel.count === 0
                        Layout.fillWidth: true
                        implicitHeight: visible ? 68 : 0
                        Layout.preferredHeight: implicitHeight
                        radius: 8
                        color: detailsRoot.lightMode ? "#f8f9fa" : "#10131c"
                        border.color: detailsRoot.lightMode ? "#e9ecef" : "#1e2433"
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                text: "🧩"
                                font.pixelSize: 18
                            }
                            Label {
                                text: qsTr("No Python modules attached to this session yet. Select a module from Recent Modules or click 'Browse Module (.py)...' to add one.")
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                            }
                        }
                    }

                    // List of Added Factor Calculation Modules for this Session
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: detailsRoot.addedModulesModel && detailsRoot.addedModulesModel.count > 0

                        Repeater {
                            model: detailsRoot.addedModulesModel

                            Rectangle {
                                id: modCard
                                Layout.fillWidth: true
                                implicitHeight: modCardCol.implicitHeight + 20
                                Layout.preferredHeight: implicitHeight
                                radius: 8
                                color: detailsRoot.lightMode ? "#f8f9fa" : "#10131c"
                                border.color: model.status === "error"
                                              ? "#fa5252"
                                              : (model.status === "done"
                                                 ? "#40c057"
                                                 : (model.status === "running"
                                                    ? "#339af0"
                                                    : (detailsRoot.lightMode ? "#dee2e6" : "#252a3a")))
                                border.width: 1

                                ColumnLayout {
                                    id: modCardCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Text {
                                            text: model.status === "error"
                                                  ? "⚠️"
                                                  : (model.status === "done"
                                                     ? "✅"
                                                     : (model.status === "running" ? "⏳" : "🐍"))
                                            font.pixelSize: 15
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1

                                            RowLayout {
                                                spacing: 8
                                                Label {
                                                    text: model.name
                                                    font.bold: true
                                                    font.pixelSize: 12
                                                    color: detailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                                }

                                                Rectangle {
                                                    height: 18
                                                    width: statusLbl.implicitWidth + 12
                                                    radius: 9
                                                    color: model.status === "error"
                                                           ? "#2d1418"
                                                           : (model.status === "done"
                                                              ? "#132d1d"
                                                              : (model.status === "running" ? "#14233c" : "#252a38"))
                                                    Text {
                                                        id: statusLbl
                                                        anchors.centerIn: parent
                                                        text: model.status === "error"
                                                              ? "Error"
                                                              : (model.status === "done"
                                                                 ? "Output Ready"
                                                                 : (model.status === "running" ? "Running..." : "Ready"))
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: model.status === "error"
                                                               ? "#ff6b6b"
                                                               : (model.status === "done"
                                                                  ? "#51cf66"
                                                                  : (model.status === "running" ? "#4dabf7" : "#adb5bd"))
                                                    }
                                                }
                                            }

                                            Label {
                                                text: model.path
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                            }
                                        }

                                        Button {
                                            id: runSingleBtn
                                            height: 28
                                            enabled: model.status !== "running"
                                            background: Rectangle {
                                                radius: 6
                                                color: runSingleBtn.hovered ? "#1c7ed6" : "#228be6"
                                                opacity: runSingleBtn.enabled ? 1.0 : 0.5
                                            }
                                            contentItem: Text {
                                                text: model.status === "running" ? "Running..." : "▶ Run Module"
                                                font.bold: true
                                                font.pixelSize: 11
                                                color: "#ffffff"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 10
                                                rightPadding: 10
                                            }
                                            onClicked: {
                                                detailsRoot.runModuleRequested(index, model.path)
                                            }
                                        }

                                        Button {
                                            id: toggleJsonBtn
                                            height: 28
                                            visible: (model.outputJson && model.outputJson.length > 0) || (model.errorText && model.errorText.length > 0)
                                            background: Rectangle {
                                                radius: 6
                                                color: toggleJsonBtn.hovered
                                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                                       : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                                border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                                border.width: 1
                                            }
                                            contentItem: Text {
                                                text: model.expanded ? "▲ Hide Output JSON" : "▼ Show Output JSON"
                                                font.bold: true
                                                font.pixelSize: 10
                                                color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 8
                                                rightPadding: 8
                                            }
                                            onClicked: {
                                                detailsRoot.addedModulesModel.setProperty(index, "expanded", !model.expanded)
                                            }
                                        }

                                        Button {
                                            id: removeModBtn
                                            width: 28
                                            height: 28
                                            background: Rectangle {
                                                radius: 6
                                                color: removeModBtn.hovered ? "#c92a2a" : "transparent"
                                            }
                                            contentItem: Text {
                                                text: "✕"
                                                font.bold: true
                                                font.pixelSize: 12
                                                color: removeModBtn.hovered ? "#ffffff" : (detailsRoot.lightMode ? "#868e96" : "#909296")
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            onClicked: {
                                                detailsRoot.removeAddedModuleRequested(index)
                                            }
                                        }
                                    }

                                    // Output JSON / Error Viewer Box
                                    Rectangle {
                                        visible: model.expanded && ((model.outputJson && model.outputJson.length > 0) || (model.errorText && model.errorText.length > 0))
                                        Layout.fillWidth: true
                                        implicitHeight: visible ? 210 : 0
                                        Layout.preferredHeight: implicitHeight
                                        radius: 6
                                        color: detailsRoot.lightMode ? "#ffffff" : "#0b0d13"
                                        border.color: model.status === "error" ? "#fa5252" : (detailsRoot.lightMode ? "#dee2e6" : "#222836")
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: model.status === "error"
                                                          ? qsTr("Module Execution Error:")
                                                          : qsTr("Module Output JSON:")
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    color: model.status === "error" ? "#fa5252" : "#40c057"
                                                }
                                                Item { Layout.fillWidth: true }
                                            }

                                            ScrollView {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                clip: true

                                                TextArea {
                                                    text: model.status === "error" ? model.errorText : model.outputJson
                                                    readOnly: true
                                                    selectByMouse: true
                                                    font.family: "monospace"
                                                    font.pixelSize: 11
                                                    color: model.status === "error"
                                                           ? "#ff8787"
                                                           : (detailsRoot.lightMode ? "#212529" : "#d0ebff")
                                                    background: null
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

            // --- 2. PREDICT ATTENUATION (CORRELATION MODULES PER GROUND STATION) ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: correlationSectionCol.implicitHeight + 28
                Layout.preferredHeight: implicitHeight
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: correlationSectionCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    // Section Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 7
                            color: detailsRoot.lightMode ? "#fff3bf" : "#2d2411"
                            border.color: "#f59f00"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "📊"
                                font.pixelSize: 15
                            }
                        }

                        ColumnLayout {
                            spacing: 1
                            Label {
                                text: qsTr("Predict Attenuation (Python Correlation Modules per Station)")
                                font.bold: true
                                font.pixelSize: 14
                                color: detailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                            }
                            Label {
                                text: qsTr("Correlate calculated environmental factors with an Excel (.xlsx) lookup table or model to predict total attenuation (dB) for each station in this session.")
                                font.pixelSize: 11
                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            id: predictAllStationsBtn
                            height: 32
                            enabled: detailsRoot.stationCorrelationModel && detailsRoot.stationCorrelationModel.count > 0
                            background: Rectangle {
                                radius: 6
                                color: predictAllStationsBtn.hovered ? "#e67700" : "#f59f00"
                                opacity: predictAllStationsBtn.enabled ? 1.0 : 0.45
                            }
                            contentItem: Text {
                                text: "▶ Predict Attenuation (All Stations)"
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 12
                                rightPadding: 12
                            }
                            onClicked: detailsRoot.predictAllStationsAttenuationRequested()
                        }
                    }

                    // Correlation Module (.py) & Excel Table (.xlsx) Selectors
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("Correlation Module:")
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                        }

                        ComboBox {
                            id: corrModuleCombo
                            Layout.preferredWidth: 210
                            height: 32
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
                            height: 32
                            background: Rectangle {
                                radius: 6
                                color: browseCorrModBtn.hovered
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                       : (detailsRoot.lightMode ? "#f1f3f5" : "#1e2230")
                                border.color: "#f59f00"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "📂 Browse Correlation (.py)..."
                                font.bold: true
                                font.pixelSize: 11
                                color: "#f59f00"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: detailsRoot.browseCorrelationModuleRequested()
                        }

                        Rectangle {
                            width: 1
                            height: 22
                            color: detailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                        }

                        Label {
                            text: qsTr("Excel Table:")
                            font.bold: true
                            font.pixelSize: 11
                            color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                        }

                        ComboBox {
                            id: excelFileCombo
                            Layout.preferredWidth: 210
                            height: 32
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
                            height: 32
                            background: Rectangle {
                                radius: 6
                                color: browseExcelBtn.hovered
                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                       : (detailsRoot.lightMode ? "#f1f3f5" : "#1e2230")
                                border.color: "#40c057"
                                border.width: 1
                            }
                            contentItem: Text {
                                text: "📊 Browse Excel (.xlsx)..."
                                font.bold: true
                                font.pixelSize: 11
                                color: "#40c057"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                                rightPadding: 10
                            }
                            onClicked: detailsRoot.browseExcelFileRequested()
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Dynamic "Predict Attenuation" Cards for each Ground Station in the Session
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        visible: detailsRoot.stationCorrelationModel && detailsRoot.stationCorrelationModel.count > 0

                        Repeater {
                            model: detailsRoot.stationCorrelationModel

                            Rectangle {
                                id: stCorrCard
                                Layout.fillWidth: true
                                implicitHeight: stCorrCol.implicitHeight + 20
                                Layout.preferredHeight: implicitHeight
                                radius: 8
                                color: detailsRoot.lightMode ? "#f8f9fa" : "#10131c"
                                border.color: model.status === "error"
                                              ? "#fa5252"
                                              : (model.status === "warning"
                                                 ? "#f59f00"
                                                 : (model.status === "done"
                                                    ? "#40c057"
                                                    : (model.status === "running"
                                                       ? "#339af0"
                                                       : detailsRoot.getStationColor(index))))
                                border.width: 1

                                ColumnLayout {
                                    id: stCorrCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: detailsRoot.getStationColor(index)
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            RowLayout {
                                                spacing: 8

                                                Label {
                                                    text: model.stationName
                                                    font.bold: true
                                                    font.pixelSize: 13
                                                    color: detailsRoot.getStationColor(index)
                                                }

                                                Rectangle {
                                                    height: 18
                                                    width: corrStatusLbl.implicitWidth + 12
                                                    radius: 9
                                                    color: model.status === "error"
                                                           ? "#2d1418"
                                                           : (model.status === "warning"
                                                              ? "#2d2411"
                                                              : (model.status === "done"
                                                                 ? "#132d1d"
                                                                 : (model.status === "running" ? "#14233c" : "#252a38")))
                                                    Text {
                                                        id: corrStatusLbl
                                                        anchors.centerIn: parent
                                                        text: model.status === "error"
                                                              ? "Error"
                                                              : (model.status === "warning"
                                                                 ? "Warning"
                                                                 : (model.status === "done"
                                                                    ? "Attenuation Predicted"
                                                                    : (model.status === "running" ? "Predicting..." : "Ready")))
                                                        font.bold: true
                                                        font.pixelSize: 9
                                                        color: model.status === "error"
                                                               ? "#ff6b6b"
                                                               : (model.status === "warning"
                                                                  ? "#fcc419"
                                                                  : (model.status === "done"
                                                                     ? "#51cf66"
                                                                     : (model.status === "running" ? "#4dabf7" : "#adb5bd")))
                                                    }
                                                }
                                            }

                                            Label {
                                                text: "Module: " + (detailsRoot.selectedCorrelationModulePath ? detailsRoot.selectedCorrelationModulePath.split("/").pop() : "step_correlation.py")
                                                      + "  •  Excel: " + (detailsRoot.selectedExcelFilePath ? detailsRoot.selectedExcelFilePath.split("/").pop() : "attenuation_table.xlsx")
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                                color: detailsRoot.lightMode ? "#6c757d" : "#909296"
                                            }
                                        }

                                        Button {
                                            id: predictSingleBtn
                                            height: 30
                                            enabled: model.status !== "running"
                                            background: Rectangle {
                                                radius: 6
                                                color: predictSingleBtn.hovered ? "#e67700" : "#f59f00"
                                                opacity: predictSingleBtn.enabled ? 1.0 : 0.5
                                            }
                                            contentItem: Text {
                                                text: model.status === "running" ? "Predicting..." : "▶ Predict Attenuation"
                                                font.bold: true
                                                font.pixelSize: 11
                                                color: "#ffffff"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 12
                                                rightPadding: 12
                                            }
                                            onClicked: {
                                                detailsRoot.predictStationAttenuationRequested(index)
                                            }
                                        }

                                        Button {
                                            id: toggleCorrInputBtn
                                            height: 28
                                            visible: model.inputJson && model.inputJson.length > 0
                                            background: Rectangle {
                                                radius: 6
                                                color: toggleCorrInputBtn.hovered
                                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                                       : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                                border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                                border.width: 1
                                            }
                                            contentItem: Text {
                                                text: model.showInput ? "{ } Hide Input JSON" : "{ } View Input JSON"
                                                font.bold: true
                                                font.pixelSize: 10
                                                color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 8
                                                rightPadding: 8
                                            }
                                            onClicked: {
                                                detailsRoot.stationCorrelationModel.setProperty(index, "showInput", !model.showInput)
                                            }
                                        }

                                        Button {
                                            id: toggleCorrOutputBtn
                                            height: 28
                                            visible: (model.outputJson && model.outputJson.length > 0) || (model.errorText && model.errorText.length > 0)
                                            background: Rectangle {
                                                radius: 6
                                                color: toggleCorrOutputBtn.hovered
                                                       ? (detailsRoot.lightMode ? "#e9ecef" : "#252a3a")
                                                       : (detailsRoot.lightMode ? "#ffffff" : "#1a1e29")
                                                border.color: detailsRoot.lightMode ? "#ced4da" : "#373a40"
                                                border.width: 1
                                            }
                                            contentItem: Text {
                                                text: model.expanded ? "▲ Hide Output JSON" : "▼ Show Output JSON"
                                                font.bold: true
                                                font.pixelSize: 10
                                                color: detailsRoot.lightMode ? "#495057" : "#c1c2c5"
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                leftPadding: 8
                                                rightPadding: 8
                                            }
                                            onClicked: {
                                                detailsRoot.stationCorrelationModel.setProperty(index, "expanded", !model.expanded)
                                            }
                                        }
                                    }

                                    // Collapsible Correlation Input JSON Viewer
                                    Rectangle {
                                        visible: model.showInput && model.inputJson && model.inputJson.length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: visible ? 160 : 0
                                        Layout.preferredHeight: implicitHeight
                                        radius: 6
                                        color: detailsRoot.lightMode ? "#ffffff" : "#0b0d13"
                                        border.color: detailsRoot.lightMode ? "#dee2e6" : "#222836"
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            Label {
                                                text: "Correlation Input JSON (" + model.stationName + "):"
                                                font.bold: true
                                                font.pixelSize: 10
                                                color: "#339af0"
                                            }

                                            ScrollView {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                clip: true

                                                TextArea {
                                                    text: model.inputJson
                                                    readOnly: true
                                                    selectByMouse: true
                                                    font.family: "monospace"
                                                    font.pixelSize: 10
                                                    color: detailsRoot.lightMode ? "#212529" : "#e9ecef"
                                                    background: null
                                                }
                                            }
                                        }
                                    }

                                    // Collapsible Correlation Output JSON Viewer
                                    Rectangle {
                                        visible: model.expanded && ((model.outputJson && model.outputJson.length > 0) || (model.errorText && model.errorText.length > 0))
                                        Layout.fillWidth: true
                                        implicitHeight: visible ? 210 : 0
                                        Layout.preferredHeight: implicitHeight
                                        radius: 6
                                        color: detailsRoot.lightMode ? "#ffffff" : "#0b0d13"
                                        border.color: model.status === "error"
                                                      ? "#fa5252"
                                                      : (model.status === "warning" ? "#f59f00" : (detailsRoot.lightMode ? "#dee2e6" : "#222836"))
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 4

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Label {
                                                    text: model.status === "error"
                                                          ? ("Correlation Output JSON / Error (" + model.stationName + "):")
                                                          : (model.status === "warning"
                                                             ? ("Correlation Output JSON with Warning (" + model.stationName + "):")
                                                             : ("Predicted Attenuation Output JSON (" + model.stationName + "):"))
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    color: model.status === "error"
                                                           ? "#fa5252"
                                                           : (model.status === "warning" ? "#fcc419" : "#40c057")
                                                }
                                                Item { Layout.fillWidth: true }
                                            }

                                            ScrollView {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                clip: true

                                                TextArea {
                                                    text: (model.outputJson && model.outputJson.length > 0) ? model.outputJson : model.errorText
                                                    readOnly: true
                                                    selectByMouse: true
                                                    font.family: "monospace"
                                                    font.pixelSize: 11
                                                    color: model.status === "error"
                                                           ? "#ff8787"
                                                           : (model.status === "warning"
                                                              ? "#ffe066"
                                                              : (detailsRoot.lightMode ? "#212529" : "#d0ebff"))
                                                    background: null
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
        }
    }

    onSnrProfileDataChanged: {
        hoveredSampleIndex = -1
        embeddedPlotCanvas.requestPaint()
    }
}
