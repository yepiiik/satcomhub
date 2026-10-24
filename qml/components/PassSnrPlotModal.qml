import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: snrModalRoot

    property var snrProfileData: null
    property bool lightMode: false
    property string activeMetric: "snr" // "snr", "fspl", "totalloss", "elevation"
    property bool showMrcEnvelope: true
    property bool showShannonLimits: true
    property int hoveredSampleIndex: -1

    signal closed()

    anchors.fill: parent
    color: "#b0000000"
    visible: snrProfileData !== null && snrProfileData.valid === true
    z: 200

    // Prevent mouse events from leaking to underlying map
    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    // Station palette colors
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

    Rectangle {
        id: dialogBox
        width: Math.min(parent.width - 40, 1150)
        height: Math.min(parent.height - 40, 780)
        anchors.centerIn: parent
        radius: 12
        color: lightMode ? "#f8f9fa" : "#141720"
        border.color: lightMode ? "#ced4da" : "#2d3345"
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // ================= HEADER =================
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 38
                    height: 38
                    radius: 9
                    color: lightMode ? "#e7f5ff" : "#1c2b42"
                    border.color: "#339af0"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "📈"
                        font.pixelSize: 18
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 8
                        Label {
                            text: qsTr("Multi-Station SNR & Signal Loss Profile")
                            font.bold: true
                            font.pixelSize: 16
                            color: lightMode ? "#1a1b1e" : "#f1f3f5"
                        }

                        Rectangle {
                            height: 20
                            width: satBadgeText.implicitWidth + 12
                            radius: 10
                            color: lightMode ? "#e9ecef" : "#252b3b"
                            border.color: lightMode ? "#ced4da" : "#3b4256"

                            Text {
                                id: satBadgeText
                                anchors.centerIn: parent
                                text: snrModalRoot.snrProfileData ? ("🛰️ " + snrModalRoot.snrProfileData.satelliteName) : ""
                                font.bold: true
                                font.pixelSize: 11
                                color: "#339af0"
                            }
                        }

                        Rectangle {
                            visible: snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.hasOverlap
                            height: 20
                            width: overlapBadgeText.implicitWidth + 12
                            radius: 10
                            color: lightMode ? "#ebfbee" : "#132d1d"
                            border.color: "#40c057"

                            Text {
                                id: overlapBadgeText
                                anchors.centerIn: parent
                                text: snrModalRoot.snrProfileData ? ("🤝 Joint Overlap: " + Math.round(snrModalRoot.snrProfileData.overlapDurationSeconds) + "s (Diversity Gain +" + snrModalRoot.snrProfileData.maxDiversityGainDb + " dB)") : ""
                                font.bold: true
                                font.pixelSize: 10
                                color: "#40c057"
                            }
                        }
                    }

                    Label {
                        text: snrModalRoot.snrProfileData ? 
                              ("Pass Window: " + snrModalRoot.snrProfileData.startUtcIso + " → " + snrModalRoot.snrProfileData.endUtcIso + 
                               " | Total Duration: " + Math.round(snrModalRoot.snrProfileData.durationSeconds) + "s (" + snrModalRoot.snrProfileData.sampleCount + " samples @ " + snrModalRoot.snrProfileData.sampleRateHz + " Hz)") : ""
                        font.pixelSize: 11
                        font.family: "monospace"
                        color: lightMode ? "#6c757d" : "#909296"
                    }
                }

                // Close button
                Button {
                    width: 32
                    height: 32
                    background: Rectangle {
                        radius: 8
                        color: parent.hovered ? (lightMode ? "#e9ecef" : "#2c3245") : "transparent"
                    }
                    contentItem: Text {
                        text: "✕"
                        font.bold: true
                        font.pixelSize: 15
                        color: lightMode ? "#495057" : "#adb5bd"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: snrModalRoot.closed()
                }
            }

            // ================= CONTROLS & METRIC TABS =================
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Metric Toggle Tabs
                RowLayout {
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "snr", label: "📶 Signal-to-Noise Ratio (SNR)", unit: "dB" },
                            { id: "fspl", label: "📉 Free Space Path Loss (FSPL)", unit: "dB" },
                            { id: "totalloss", label: "📊 Total Signal Loss", unit: "dB" },
                            { id: "elevation", label: "📐 Elevation Angle", unit: "°" }
                        ]

                        Button {
                            height: 28
                            checkable: true
                            checked: snrModalRoot.activeMetric === modelData.id
                            background: Rectangle {
                                radius: 6
                                color: checked ? "#339af0" : (parent.hovered ? (lightMode ? "#e9ecef" : "#232838") : (lightMode ? "#ffffff" : "#1a1f2c"))
                                border.color: checked ? "#339af0" : (lightMode ? "#dee2e6" : "#2d3345")
                            }
                            contentItem: Text {
                                text: modelData.label
                                font.bold: true
                                font.pixelSize: 11
                                color: checked ? "#ffffff" : (lightMode ? "#495057" : "#adb5bd")
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                snrModalRoot.activeMetric = modelData.id
                                plotCanvas.requestPaint()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Overlap & Shannon Toggles
                CheckBox {
                    id: mrcCheck
                    text: qsTr("Combined MRC Envelope")
                    checked: snrModalRoot.showMrcEnvelope
                    visible: snrModalRoot.activeMetric === "snr" && snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.hasOverlap
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        font.bold: true
                        color: "#ffd43b"
                        leftPadding: parent.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                    onCheckedChanged: {
                        snrModalRoot.showMrcEnvelope = checked
                        plotCanvas.requestPaint()
                    }
                }

                CheckBox {
                    id: shannonCheck
                    text: qsTr("Shannon Limits")
                    checked: snrModalRoot.showShannonLimits
                    visible: snrModalRoot.activeMetric === "snr"
                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: 11
                        font.bold: true
                        color: lightMode ? "#495057" : "#ced4da"
                        leftPadding: parent.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                    onCheckedChanged: {
                        snrModalRoot.showShannonLimits = checked
                        plotCanvas.requestPaint()
                    }
                }
            }

            // ================= LIVE CROSSHAIR TELEMETRY HUD =================
            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 6
                color: lightMode ? "#e9ecef" : "#1a1f2c"
                border.color: lightMode ? "#dee2e6" : "#2c3346"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 16

                    // Cursor Time Readout
                    RowLayout {
                        spacing: 6
                        Text {
                            text: "⏱️ Time:"
                            font.bold: true
                            font.pixelSize: 11
                            color: lightMode ? "#495057" : "#adb5bd"
                        }
                        Text {
                            text: {
                                if (!snrModalRoot.snrProfileData || snrModalRoot.hoveredSampleIndex < 0 ||
                                    snrModalRoot.hoveredSampleIndex >= snrModalRoot.snrProfileData.utcLabels.length) {
                                    return "Hover over plot to inspect"
                                }
                                var tSec = snrModalRoot.snrProfileData.timestampsSec[snrModalRoot.hoveredSampleIndex]
                                var utc = snrModalRoot.snrProfileData.utcLabels[snrModalRoot.hoveredSampleIndex]
                                return utc + " (+" + Math.round(tSec) + "s)"
                            }
                            font.bold: true
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#339af0"
                        }
                    }

                    Rectangle { width: 1; height: 20; color: lightMode ? "#ced4da" : "#373a40" }

                    // Per-station dynamic values
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            model: (snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.stations) ? snrModalRoot.snrProfileData.stations : []

                            RowLayout {
                                spacing: 6
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: snrModalRoot.getStationColor(index)
                                }
                                Text {
                                    text: modelData.stationName + ":"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: snrModalRoot.getStationColor(index)
                                }
                                Text {
                                    font.bold: true
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: lightMode ? "#212529" : "#f8f9fa"
                                    text: {
                                        var idx = snrModalRoot.hoveredSampleIndex
                                        if (idx < 0 || !modelData.elevationDeg || idx >= modelData.elevationDeg.length) {
                                            return "Max SNR: " + (modelData.maxSnrDb > -900 ? modelData.maxSnrDb.toFixed(1) + " dB" : "N/A") + " (Peak " + modelData.maxElevationDeg.toFixed(1) + "°)"
                                        }
                                        var vis = modelData.isVisible[idx]
                                        var el = modelData.elevationDeg[idx].toFixed(1) + "°"
                                        var fspl = modelData.fsplLossDb[idx].toFixed(1) + " dB"
                                        var snr = modelData.snrDb[idx].toFixed(1) + " dB"
                                        var dist = Math.round(modelData.slantRangeKm[idx]) + " km"

                                        if (!vis) {
                                            return "Below Horizon (" + el + ")"
                                        }

                                        if (snrModalRoot.activeMetric === "snr") {
                                            return "SNR: " + snr + " | El: " + el + " | Dist: " + dist
                                        } else if (snrModalRoot.activeMetric === "fspl") {
                                            return "FSPL: " + fspl + " | Dist: " + dist
                                        } else if (snrModalRoot.activeMetric === "totalloss") {
                                            return "Loss: " + modelData.totalLossDb[idx].toFixed(1) + " dB | Atm: " + modelData.atmosphericLossDb[idx].toFixed(2) + " dB"
                                        } else {
                                            return "El: " + el + " | Az: " + Math.round(modelData.azimuthDeg[idx]) + "°"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Combined MRC Readout if applicable
                    RowLayout {
                        visible: snrModalRoot.activeMetric === "snr" && snrModalRoot.showMrcEnvelope && snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.hasOverlap
                        spacing: 6

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: "#ffd43b"
                        }
                        Text {
                            text: "Combined MRC:"
                            font.bold: true
                            font.pixelSize: 11
                            color: "#ffd43b"
                        }
                        Text {
                            font.bold: true
                            font.family: "monospace"
                            font.pixelSize: 11
                            color: "#ffd43b"
                            text: {
                                var idx = snrModalRoot.hoveredSampleIndex
                                if (idx >= 0 && snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.combinedMrcSnrDb && idx < snrModalRoot.snrProfileData.combinedMrcSnrDb.length) {
                                    return snrModalRoot.snrProfileData.combinedMrcSnrDb[idx].toFixed(1) + " dB"
                                }
                                return "Overlap Gain +" + (snrModalRoot.snrProfileData ? snrModalRoot.snrProfileData.maxDiversityGainDb : 0) + " dB"
                            }
                        }
                    }
                }
            }

            // ================= PLOT CANVAS AREA =================
            Rectangle {
                id: plotContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: lightMode ? "#ffffff" : "#0d1017"
                border.color: lightMode ? "#dee2e6" : "#242a3a"
                clip: true

                Canvas {
                    id: plotCanvas
                    anchors.fill: parent
                    antialiasing: true

                    property real paddingLeft: 60
                    property real paddingRight: 30
                    property real paddingTop: 30
                    property real paddingBottom: 45

                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
                        ctx.clearRect(0, 0, w, h)

                        if (!snrModalRoot.snrProfileData || !snrModalRoot.snrProfileData.valid) {
                            ctx.fillStyle = lightMode ? "#868e96" : "#495057"
                            ctx.font = "14px sans-serif"
                            ctx.textAlign = "center"
                            ctx.fillText("No SNR profile data available for this pass", w / 2, h / 2)
                            return
                        }

                        var data = snrModalRoot.snrProfileData
                        var N = data.sampleCount
                        if (N < 2) return

                        var plotW = w - paddingLeft - paddingRight
                        var plotH = h - paddingTop - paddingBottom

                        // 1. Determine Min & Max bounds for active metric
                        var yMin = 0
                        var yMax = 30
                        var metric = snrModalRoot.activeMetric

                        if (metric === "snr") {
                            yMin = -15
                            yMax = 30
                            // Check if stations exceed 30 dB
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

                        function mapX(sampleIdx) {
                            return paddingLeft + (sampleIdx / (N - 1)) * plotW
                        }

                        function mapY(val) {
                            var clamped = Math.max(yMin, Math.min(yMax, val))
                            return paddingTop + (1.0 - (clamped - yMin) / (yMax - yMin)) * plotH
                        }

                        // 2. Draw Overlap Window Background Highlight
                        if (data.hasOverlap && metric === "snr") {
                            var overlapStartIdx = -1
                            var overlapEndIdx = -1
                            for (var k = 0; k < N; k++) {
                                var visCount = 0
                                for (var si = 0; si < data.stations.length; si++) {
                                    if (data.stations[si].isVisible[k]) visCount++
                                }
                                if (visCount >= 2) {
                                    if (overlapStartIdx === -1) overlapStartIdx = k
                                    overlapEndIdx = k
                                }
                            }

                            if (overlapStartIdx !== -1 && overlapEndIdx >= overlapStartIdx) {
                                var ox1 = mapX(overlapStartIdx)
                                var ox2 = mapX(overlapEndIdx)
                                ctx.fillStyle = lightMode ? "rgba(47, 158, 68, 0.12)" : "rgba(47, 158, 68, 0.15)"
                                ctx.fillRect(ox1, paddingTop, ox2 - ox1, plotH)

                                // Overlap top border accent
                                ctx.strokeStyle = "#40c057"
                                ctx.lineWidth = 1.5
                                ctx.setLineDash([4, 4])
                                ctx.beginPath()
                                ctx.moveTo(ox1, paddingTop)
                                ctx.lineTo(ox1, paddingTop + plotH)
                                ctx.moveTo(ox2, paddingTop)
                                ctx.lineTo(ox2, paddingTop + plotH)
                                ctx.stroke()
                                ctx.setLineDash([])

                                // Label
                                ctx.fillStyle = "#40c057"
                                ctx.font = "bold 10px sans-serif"
                                ctx.textAlign = "center"
                                ctx.fillText("🤝 DIVERSITY OVERLAP WINDOW", (ox1 + ox2) / 2, paddingTop + 14)
                            }
                        }

                        // 3. Draw Grid Lines & Y-axis Ticks
                        ctx.strokeStyle = lightMode ? "#e9ecef" : "#1a2130"
                        ctx.lineWidth = 1
                        ctx.fillStyle = lightMode ? "#868e96" : "#6c757d"
                        ctx.font = "10px monospace"
                        ctx.textAlign = "right"

                        var yStep = (yMax - yMin) <= 40 ? 5 : ((yMax - yMin) <= 100 ? 10 : 20)
                        for (var yv = yMin; yv <= yMax; yv += yStep) {
                            var yp = mapY(yv)
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, yp)
                            ctx.lineTo(paddingLeft + plotW, yp)
                            ctx.stroke()

                            var labelUnit = (metric === "elevation") ? "°" : " dB"
                            ctx.fillText(yv + labelUnit, paddingLeft - 8, yp + 3)
                        }

                        // 4. Draw X-axis Ticks (Time & UTC labels)
                        var timeStepSec = Math.max(30, Math.floor(data.durationSeconds / 8))
                        var sampleStep = Math.max(1, Math.round(timeStepSec * data.sampleRateHz))
                        ctx.textAlign = "center"

                        for (var tIdx = 0; tIdx < N; tIdx += sampleStep) {
                            var xp = mapX(tIdx)
                            ctx.beginPath()
                            ctx.moveTo(xp, paddingTop)
                            ctx.lineTo(xp, paddingTop + plotH)
                            ctx.stroke()

                            var utcText = data.utcLabels[tIdx]
                            var secText = "+" + Math.round(data.timestampsSec[tIdx]) + "s"

                            ctx.fillStyle = lightMode ? "#495057" : "#adb5bd"
                            ctx.fillText(utcText, xp, paddingTop + plotH + 16)
                            ctx.fillStyle = lightMode ? "#adb5bd" : "#5c6270"
                            ctx.fillText(secText, xp, paddingTop + plotH + 28)
                        }

                        // 5. Draw Shannon Limit Threshold Lines (if SNR metric)
                        if (metric === "snr" && snrModalRoot.showShannonLimits) {
                            // Shannon Raw (0 dB)
                            var y0 = mapY(data.shannonRawThresholdDb)
                            ctx.strokeStyle = "#ff6b6b"
                            ctx.lineWidth = 1.2
                            ctx.setLineDash([6, 4])
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, y0)
                            ctx.lineTo(paddingLeft + plotW, y0)
                            ctx.stroke()

                            ctx.fillStyle = "#ff6b6b"
                            ctx.font = "bold 9px sans-serif"
                            ctx.textAlign = "left"
                            ctx.fillText("0 dB Shannon Raw Limit (10 Mbps in 10 MHz)", paddingLeft + 10, y0 - 4)

                            // Shannon Rate 1/2 Turbo Code (4.77 dB)
                            var yTurbo = mapY(data.shannonTurbocodeThresholdDb)
                            ctx.strokeStyle = "#fcc419"
                            ctx.beginPath()
                            ctx.moveTo(paddingLeft, yTurbo)
                            ctx.lineTo(paddingLeft + plotW, yTurbo)
                            ctx.stroke()

                            ctx.fillStyle = "#fcc419"
                            ctx.fillText("4.77 dB Rate 1/2 Turbo Limit (20 Mbps)", paddingLeft + 10, yTurbo - 4)
                            ctx.setLineDash([])
                        }

                        // 6. Draw Curves for Each Ground Station (Shifted Heaps!)
                        for (var sIdx = 0; sIdx < data.stations.length; sIdx++) {
                            var station = data.stations[sIdx]
                            var col = snrModalRoot.getStationColor(sIdx)
                            var vec = []

                            if (metric === "snr") vec = station.snrDb
                            else if (metric === "fspl") vec = station.fsplLossDb
                            else if (metric === "totalloss") vec = station.totalLossDb
                            else if (metric === "elevation") vec = station.elevationDeg

                            if (!vec || vec.length !== N) continue

                            // Draw subtle gradient fill under curve for SNR and Elevation
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
                                grad.addColorStop(0, col + "33") // 20% alpha
                                grad.addColorStop(1, col + "00") // 0% alpha
                                ctx.fillStyle = grad
                                ctx.fill()
                            }

                            // Stroke the curve
                            ctx.beginPath()
                            ctx.strokeStyle = col
                            ctx.lineWidth = 2.5
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"

                            for (var k2 = 0; k2 < N; k2++) {
                                var val2 = vec[k2]
                                if (metric === "snr" && !station.isVisible[k2]) {
                                    val2 = yMin
                                }
                                var cx = mapX(k2)
                                var cy = mapY(val2)
                                if (k2 === 0) ctx.moveTo(cx, cy)
                                else ctx.lineTo(cx, cy)
                            }
                            ctx.stroke()

                            // Highlight Peak Point (TCA)
                            if (station.visibleDurationSeconds > 0) {
                                var peakVal = -9999
                                var peakIdx = -1
                                for (var kp = 0; kp < N; kp++) {
                                    if (station.isVisible[kp] && vec[kp] > peakVal) {
                                        peakVal = vec[kp]
                                        peakIdx = kp
                                    }
                                }
                                if (peakIdx !== -1) {
                                    var px = mapX(peakIdx)
                                    var py = mapY(peakVal)

                                    ctx.fillStyle = col
                                    ctx.beginPath()
                                    ctx.arc(px, py, 4.5, 0, 2 * Math.PI)
                                    ctx.fill()
                                    ctx.strokeStyle = "#ffffff"
                                    ctx.lineWidth = 1.5
                                    ctx.stroke()

                                    // Peak label
                                    ctx.fillStyle = col
                                    ctx.font = "bold 10px monospace"
                                    ctx.textAlign = "center"
                                    var peakUnit = (metric === "elevation") ? "°" : " dB"
                                    ctx.fillText(station.stationName + ": " + peakVal.toFixed(1) + peakUnit, px, py - 10)
                                }
                            }
                        }

                        // 7. Draw Combined MRC Envelope (Golden Dashed Curve)
                        if (metric === "snr" && snrModalRoot.showMrcEnvelope && data.hasOverlap && data.combinedMrcSnrDb) {
                            ctx.beginPath()
                            ctx.strokeStyle = "#ffd43b"
                            ctx.lineWidth = 2.2
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

                        // 8. Draw Hover Crosshair Line
                        if (snrModalRoot.hoveredSampleIndex >= 0 && snrModalRoot.hoveredSampleIndex < N) {
                            var hx = mapX(snrModalRoot.hoveredSampleIndex)
                            ctx.strokeStyle = "#ffffff"
                            ctx.lineWidth = 1
                            ctx.setLineDash([3, 3])
                            ctx.beginPath()
                            ctx.moveTo(hx, paddingTop)
                            ctx.lineTo(hx, paddingTop + plotH)
                            ctx.stroke()
                            ctx.setLineDash([])

                            // Draw circles at each curve intersection
                            for (var sc = 0; sc < data.stations.length; sc++) {
                                var stn = data.stations[sc]
                                var sVec = []
                                if (metric === "snr") sVec = stn.snrDb
                                else if (metric === "fspl") sVec = stn.fsplLossDb
                                else if (metric === "totalloss") sVec = stn.totalLossDb
                                else if (metric === "elevation") sVec = stn.elevationDeg

                                if (sVec && snrModalRoot.hoveredSampleIndex < sVec.length) {
                                    var sVal = sVec[snrModalRoot.hoveredSampleIndex]
                                    if (metric === "snr" && !stn.isVisible[snrModalRoot.hoveredSampleIndex]) sVal = yMin
                                    var hy = mapY(sVal)

                                    ctx.fillStyle = snrModalRoot.getStationColor(sc)
                                    ctx.beginPath()
                                    ctx.arc(hx, hy, 4, 0, 2 * Math.PI)
                                    ctx.fill()
                                    ctx.strokeStyle = "#ffffff"
                                    ctx.lineWidth = 1.5
                                    ctx.stroke()
                                }
                            }
                        }

                        // 9. Outer Axis Borders
                        ctx.strokeStyle = lightMode ? "#dee2e6" : "#2d3345"
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(paddingLeft, paddingTop)
                        ctx.lineTo(paddingLeft, paddingTop + plotH)
                        ctx.lineTo(paddingLeft + plotW, paddingTop + plotH)
                        ctx.stroke()
                    }

                    // Mouse Interaction
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true

                        onPositionChanged: function(mouse) {
                            if (!snrModalRoot.snrProfileData || !snrModalRoot.snrProfileData.valid) return
                            var data = snrModalRoot.snrProfileData
                            var N = data.sampleCount
                            var plotW = plotCanvas.width - plotCanvas.paddingLeft - plotCanvas.paddingRight

                            if (mouse.x >= plotCanvas.paddingLeft && mouse.x <= plotCanvas.paddingLeft + plotW) {
                                var ratio = (mouse.x - plotCanvas.paddingLeft) / plotW
                                var idx = Math.round(ratio * (N - 1))
                                snrModalRoot.hoveredSampleIndex = Math.max(0, Math.min(N - 1, idx))
                            } else {
                                snrModalRoot.hoveredSampleIndex = -1
                            }
                            plotCanvas.requestPaint()
                        }

                        onExited: {
                            snrModalRoot.hoveredSampleIndex = -1
                            plotCanvas.requestPaint()
                        }
                    }
                }
            }

            // ================= BOTTOM SUMMARY CARDS =================
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Per-Station Metrics Card
                Repeater {
                    model: (snrModalRoot.snrProfileData && snrModalRoot.snrProfileData.stations) ? snrModalRoot.snrProfileData.stations : []

                    Rectangle {
                        Layout.fillWidth: true
                        height: 72
                        radius: 8
                        color: lightMode ? "#ffffff" : "#1a1f2c"
                        border.color: snrModalRoot.getStationColor(index)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: snrModalRoot.getStationColor(index)
                                }
                                Text {
                                    text: modelData.stationName
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: snrModalRoot.getStationColor(index)
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Visible: " + modelData.visibleDurationSeconds + "s"
                                    font.pixelSize: 10
                                    color: lightMode ? "#6c757d" : "#909296"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Max SNR: " + (modelData.maxSnrDb > -900 ? modelData.maxSnrDb.toFixed(1) + " dB" : "N/A")
                                    font.bold: true
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: lightMode ? "#212529" : "#ffffff"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "Min FSPL: " + (modelData.minFsplDb < 900 ? modelData.minFsplDb.toFixed(1) + " dB" : "N/A")
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                    color: lightMode ? "#495057" : "#adb5bd"
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Peak El: " + modelData.maxElevationDeg.toFixed(1) + "° | TCA Range: " + Math.round(modelData.tcaRangeKm) + " km"
                                    font.pixelSize: 10
                                    color: lightMode ? "#6c757d" : "#868e96"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: "G/T: " + modelData.gOverTDbK + " dB/K"
                                    font.pixelSize: 10
                                    color: lightMode ? "#6c757d" : "#868e96"
                                }
                            }
                        }
                    }
                }

                // Link Budget RF Params Card
                Rectangle {
                    width: 240
                    height: 72
                    radius: 8
                    color: lightMode ? "#ffffff" : "#1a1f2c"
                    border.color: lightMode ? "#dee2e6" : "#2d3345"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            text: "📡 POLYITAN-3 RF Config"
                            font.bold: true
                            font.pixelSize: 11
                            color: lightMode ? "#212529" : "#ffffff"
                        }

                        Text {
                            text: snrModalRoot.snrProfileData ? 
                                  ("Carrier: " + snrModalRoot.snrProfileData.carrierFreqMhz + " MHz (C-Band)") : ""
                            font.pixelSize: 10
                            color: lightMode ? "#6c757d" : "#909296"
                        }

                        Text {
                            text: snrModalRoot.snrProfileData ? 
                                  ("Tx: " + snrModalRoot.snrProfileData.txPowerDbm + " dBm (2W) | Gain: " + snrModalRoot.snrProfileData.txAntennaGainDbi + " dBi") : ""
                            font.pixelSize: 10
                            color: lightMode ? "#6c757d" : "#909296"
                        }

                        Text {
                            text: snrModalRoot.snrProfileData ? 
                                  ("Bandwidth: " + (snrModalRoot.snrProfileData.channelBandwidthKhz / 1000) + " MHz (10 Mb/s)") : ""
                            font.pixelSize: 10
                            color: lightMode ? "#6c757d" : "#909296"
                        }
                    }
                }
            }
        }
    }

    onSnrProfileDataChanged: {
        hoveredSampleIndex = -1
        plotCanvas.requestPaint()
    }
}
