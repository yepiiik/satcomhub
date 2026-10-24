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

    // ================= ACTIVE SESSION DETAILS =================
    ScrollView {
        anchors.fill: parent
        visible: detailsRoot.sessionEvent !== null
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            anchors.margins: 18
            spacing: 14

            // --- TOP SESSION HEADER BANNER ---
            Rectangle {
                Layout.fillWidth: true
                height: headerCol.implicitHeight + 24
                radius: 10
                color: detailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: detailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: headerCol
                    anchors.fill: parent
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
                height: 36
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

                        // Station Curves (Shifted Heaps!)
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
                        height: 90
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
        }
    }

    onSnrProfileDataChanged: {
        hoveredSampleIndex = -1
        embeddedPlotCanvas.requestPaint()
    }
}
