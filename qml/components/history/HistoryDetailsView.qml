import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: historyDetailsRoot

    property var sessionDetails: null
    property var propagator: null
    property bool lightMode: false
    property var availableSatellites: []
    property var availableStations: []
    property string activeMetric: "snr" // "snr", "fspl", "totalloss", "elevation"
    property int hoveredSampleIndex: -1
    property var historyFoundPasses: []
    property bool historyHasSearchedPasses: false

    onSessionDetailsChanged: historyCanvas.requestPaint()
    onLightModeChanged: historyCanvas.requestPaint()
    onActiveMetricChanged: historyCanvas.requestPaint()

    signal editSatelliteRequested(var satData)
    signal addSatelliteRequested()
    signal copySatelliteReferenceRequested(var refSatData)
    signal removeSatelliteRequested()

    signal editStationRequested(var stationData)
    signal addStationRequested()
    signal copyStationReferenceRequested(var refStationData)
    signal removeStationRequested(string stationId)

    signal previewSessionJsonRequested(string jsonText)
    signal previewSatelliteJsonRequested(string jsonText)
    signal previewStationJsonRequested(string stationName, string jsonText)
    signal openSessionFolderRequested(string sessionId)
    signal findHistoryPassesRangeRequested(string startUtcStr, string endUtcStr)
    signal historyPassWindowSelected(var passEvent)

    radius: 12
    clip: true
    color: "transparent"

    readonly property var stationPalette: [
        "#339af0", // Blue
        "#51cf66", // Green
        "#cc5de8", // Violet / Pink
        "#ff922b", // Orange
        "#20c997", // Teal
        "#fcc419", // Yellow
        "#845ef7", // Purple
        "#ff6b6b"  // Coral
    ]

    function getStationColor(nameOrId, idx) {
        if (!nameOrId) return stationPalette[idx % stationPalette.length]
        var s = String(nameOrId).toLowerCase()
        if (s.indexOf("piotrowo") !== -1 || s.indexOf("warsaw") !== -1) return "#339af0"
        if (s.indexOf("kpi") !== -1 || s.indexOf("krakow") !== -1) return "#51cf66"
        if (s.indexOf("london") !== -1) return "#cc5de8"
        if (s.indexOf("madrid") !== -1) return "#ff922b"
        return stationPalette[idx % stationPalette.length]
    }

    function parseTleEpochDisplay(tle1) {
        if (!tle1 || tle1.length < 32) return "--"
        var raw = tle1.substring(18, 32).trim()
        if (raw.length < 5) return raw
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

    // ================= EMPTY STATE =================
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16
        visible: historyDetailsRoot.sessionDetails === null

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72
            height: 72
            radius: 18
            color: historyDetailsRoot.lightMode ? "#e6fcf5" : "#0d2b23"
            border.color: "#20c997"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "📜"
                font.pixelSize: 34
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Select an Observation to View History Details")
            font.bold: true
            font.pixelSize: 18
            color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Choose a historical pass observation from the list on the left\nor click '+' to create a manual session entry.")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
        }
    }

    // ================= ACTIVE OBSERVATION VIEW =================
    ScrollView {
        anchors.fill: parent
        visible: historyDetailsRoot.sessionDetails !== null
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            id: mainContentCol
            width: parent.width
            anchors.margins: 14
            spacing: 14

            // --- 1. SESSION HEADER CARD ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: sessHeaderCol.implicitHeight + 24
                radius: 10
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a"
                border.width: 1

                ColumnLayout {
                    id: sessHeaderCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            height: 24
                            implicitWidth: sessIdBadge.implicitWidth + 14
                            Layout.preferredWidth: implicitWidth
                            radius: 6
                            color: "#20c997"
                            Text {
                                id: sessIdBadge
                                anchors.centerIn: parent
                                text: {
                                    if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return ""
                                    var sid = historyDetailsRoot.sessionDetails.session.sessionId || historyDetailsRoot.sessionDetails.session.obsId || ""
                                    return sid
                                }
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                            }
                        }

                        Label {
                            text: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return ""
                                return historyDetailsRoot.sessionDetails.session.sessionName || historyDetailsRoot.sessionDetails.session.dateUtc || "Session History"
                            }
                            font.bold: true
                            font.pixelSize: 16
                            color: historyDetailsRoot.lightMode ? "#212529" : "#ffffff"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            height: 22
                            implicitWidth: statusBadgeText.implicitWidth + 12
                            Layout.preferredWidth: implicitWidth
                            radius: 11
                            color: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return "#868e96"
                                var st = historyDetailsRoot.sessionDetails.session.status
                                if (st === "Decoded") return "#2f9e44"
                                if (st === "Planned") return "#228be6"
                                if (st === "Partial") return "#f59f00"
                                return "#868e96"
                            }
                            Text {
                                id: statusBadgeText
                                anchors.centerIn: parent
                                text: historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session
                                      ? (historyDetailsRoot.sessionDetails.session.status || "Planned") : ""
                                font.bold: true
                                font.pixelSize: 10
                                color: "#ffffff"
                            }
                        }

                        Button {
                            height: 26
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? (historyDetailsRoot.lightMode ? "#e9ecef" : "#242a3a") : "transparent"
                                border.color: historyDetailsRoot.lightMode ? "#ced4da" : "#3b4256"
                            }
                            contentItem: Text {
                                text: "{ } Session JSON"
                                font.bold: true
                                font.pixelSize: 11
                                color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session) {
                                    var str = JSON.stringify(historyDetailsRoot.sessionDetails.session, null, 2)
                                    historyDetailsRoot.previewSessionJsonRequested(str)
                                }
                            }
                        }

                        Button {
                            height: 26
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? (historyDetailsRoot.lightMode ? "#e9ecef" : "#242a3a") : "transparent"
                                border.color: historyDetailsRoot.lightMode ? "#ced4da" : "#3b4256"
                            }
                            contentItem: Text {
                                text: "📂 Open Folder"
                                font.bold: true
                                font.pixelSize: 11
                                color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session) {
                                    var sid = historyDetailsRoot.sessionDetails.session.sessionId || ""
                                    historyDetailsRoot.openSessionFolderRequested(sid)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Label {
                            text: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return ""
                                return "Date: " + (historyDetailsRoot.sessionDetails.session.dateUtc || historyDetailsRoot.sessionDetails.session.dateTimeUtc || "--")
                            }
                            font.pixelSize: 11
                            font.family: "monospace"
                            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                        }

                        Label {
                            text: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return ""
                                return "Duration: " + (historyDetailsRoot.sessionDetails.session.durationFormatted || "--")
                            }
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        Label {
                            text: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.session) return ""
                                return "Stations: " + (historyDetailsRoot.sessionDetails.stations ? historyDetailsRoot.sessionDetails.stations.length : 0)
                            }
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                        }
                    }
                }
            }

            // --- 2. CONTROLS & METRIC TABS + GRAPH AREA ---
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

                        Rectangle {
                            readonly property bool isSelected: historyDetailsRoot.activeMetric === modelData.id
                            height: 26
                            implicitWidth: tabBtnText.implicitWidth + 20
                            Layout.preferredWidth: implicitWidth
                            radius: 6
                            color: isSelected
                                   ? (historyDetailsRoot.lightMode ? "#e7f5ff" : "#182842")
                                   : (historyDetailsRoot.lightMode ? "#f8f9fa" : "#151822")
                            border.color: isSelected ? "#339af0" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a")
                            border.width: 1

                            Text {
                                id: tabBtnText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.bold: isSelected
                                font.pixelSize: 11
                                color: isSelected ? "#339af0" : (historyDetailsRoot.lightMode ? "#495057" : "#adb5bd")
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    historyDetailsRoot.activeMetric = modelData.id
                                    historyCanvas.requestPaint()
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Graph Area or Empty Placeholder
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 280
                radius: 8
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#0d1017"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#242a3a"
                clip: true

                // Telemetry plot when snrProfileData is present
                Canvas {
                    id: historyCanvas
                    anchors.fill: parent
                    visible: Boolean(historyDetailsRoot.sessionDetails &&
                                     historyDetailsRoot.sessionDetails.hasSnrData &&
                                     historyDetailsRoot.sessionDetails.snrProfileData &&
                                     ((historyDetailsRoot.sessionDetails.snrProfileData.stations &&
                                       historyDetailsRoot.sessionDetails.snrProfileData.stations.length > 0) ||
                                      (historyDetailsRoot.sessionDetails.snrProfileData.stationCurves &&
                                       historyDetailsRoot.sessionDetails.snrProfileData.stationCurves.length > 0)))
                    antialiasing: true

                    property real paddingLeft: 55
                    property real paddingRight: 25
                    property real paddingTop: 22
                    property real paddingBottom: 38

                    onAvailableChanged: { if (available) requestPaint() }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width
                        var h = height
                        ctx.clearRect(0, 0, w, h)

                        if (!visible) return

                        var data = historyDetailsRoot.sessionDetails.snrProfileData
                        var N = data.sampleCount || 0
                        if (N < 2) return

                        var stationsArr = data.stations || data.stationCurves || []
                        if (stationsArr.length === 0) return

                        var plotW = w - paddingLeft - paddingRight
                        var plotH = h - paddingTop - paddingBottom
                        var yMin = -15
                        var yMax = 30
                        var metric = historyDetailsRoot.activeMetric

                        if (metric === "snr") {
                            yMin = -15
                            yMax = 30
                            for (var s = 0; s < stationsArr.length; s++) {
                                var st0 = stationsArr[s]
                                if (st0.maxSnrDb !== undefined && st0.maxSnrDb > yMax - 5) {
                                    yMax = Math.ceil((st0.maxSnrDb + 5) / 5) * 5
                                }
                            }
                        } else if (metric === "fspl" || metric === "totalloss") {
                            yMin = 150
                            yMax = 195
                            for (var s2 = 0; s2 < stationsArr.length; s2++) {
                                var st2 = stationsArr[s2]
                                if (st2.minFsplDb !== undefined && st2.minFsplDb < yMin + 5 && st2.minFsplDb > 50) {
                                    yMin = Math.floor((st2.minFsplDb - 5) / 5) * 5
                                }
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
                            for (var oi = 0; oi < N; oi++) {
                                var visCount = 0
                                for (var si = 0; si < stationsArr.length; si++) {
                                    if (stationsArr[si].isVisible && stationsArr[si].isVisible[oi]) visCount++
                                }
                                if (visCount >= 2) {
                                    if (overlapStart === -1) overlapStart = oi
                                    overlapEnd = oi
                                }
                            }
                            if (overlapStart !== -1 && overlapEnd >= overlapStart) {
                                var ox1 = mapX(overlapStart)
                                var ox2 = mapX(overlapEnd)
                                ctx.fillStyle = historyDetailsRoot.lightMode ? "rgba(47, 158, 68, 0.12)" : "rgba(47, 158, 68, 0.15)"
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

                        // Grid
                        ctx.strokeStyle = historyDetailsRoot.lightMode ? "#e9ecef" : "#1a2130"
                        ctx.lineWidth = 1
                        ctx.fillStyle = historyDetailsRoot.lightMode ? "#868e96" : "#6c757d"
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
                        if (data.utcLabels && data.timestampsSec && data.durationSeconds > 0) {
                            var timeStepSec = Math.max(30, Math.floor(data.durationSeconds / 7))
                            var sampleStep = Math.max(1, Math.round(timeStepSec * (data.sampleRateHz || 1.0)))
                            ctx.textAlign = "center"
                            for (var tIdx = 0; tIdx < N; tIdx += sampleStep) {
                                var xp = mapX(tIdx)
                                ctx.beginPath()
                                ctx.moveTo(xp, paddingTop); ctx.lineTo(xp, paddingTop + plotH); ctx.stroke()
                                var utcText = data.utcLabels[tIdx] || ""
                                var secText = "+" + Math.round(data.timestampsSec[tIdx] || 0) + "s"
                                ctx.fillStyle = historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                ctx.fillText(utcText, xp, paddingTop + plotH + 14)
                                ctx.fillStyle = historyDetailsRoot.lightMode ? "#adb5bd" : "#5c6270"
                                ctx.fillText(secText, xp, paddingTop + plotH + 24)
                            }
                        }

                        // Curves
                        for (var c = 0; c < stationsArr.length; c++) {
                            var curve = stationsArr[c]
                            var samples = curve.snrDb || curve.snrSamples || []
                            if (metric === "fspl") samples = curve.fsplLossDb || curve.fsplSamples || []
                            if (metric === "totalloss") samples = curve.totalLossDb || curve.totalLossSamples || []
                            if (metric === "elevation") samples = curve.elevationDeg || curve.elevationSamples || []

                            if (!samples || samples.length === 0) continue

                            var clr = historyDetailsRoot.getStationColor(curve.stationId || curve.stationName, c)
                            ctx.strokeStyle = clr
                            ctx.lineWidth = 2.0
                            ctx.beginPath()
                            for (var k = 0; k < samples.length; k++) {
                                var x = mapX(k)
                                var y = mapY(samples[k])
                                if (k === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }
                    }
                }

                // Clean empty placeholder when no SNR logs exist (e.g. manual entry)
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: !historyCanvas.visible

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "📊"
                        font.pixelSize: 36
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("No RF Telemetry / SNR Data Recorded")
                        font.bold: true
                        font.pixelSize: 15
                        color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("This history entry was created manually. Adjust satellite and ground station parameters below to configure session RF parameters.")
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12
                        color: historyDetailsRoot.lightMode ? "#6c757d" : "#868e96"
                    }
                }
            }

            // --- 3. TARGET SATELLITE SECTION ---
            Label {
                text: qsTr("Target Satellite:")
                font.bold: true
                font.pixelSize: 13
                color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#e9ecef"
                Layout.topMargin: 4
            }

            // Case A: Satellite Present
            Rectangle {
                id: targetSatelliteCard
                visible: historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasSatellite && historyDetailsRoot.sessionDetails.satellite
                Layout.preferredWidth: Math.min(mainContentCol.width, 560)
                implicitHeight: targetSatCol.implicitHeight + 28
                radius: 10
                color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#222736"
                border.width: 1

                ColumnLayout {
                    id: targetSatCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "🛰️"
                            font.pixelSize: 16
                        }

                        Label {
                            text: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.satellite)
                                  ? (historyDetailsRoot.sessionDetails.satellite.name || "Target Satellite") : ""
                            font.bold: true
                            font.pixelSize: 14
                            color: historyDetailsRoot.lightMode ? "#212529" : "#f1f3f5"
                            Layout.fillWidth: true
                        }

                        Button {
                            id: editSatCfgBtn
                            height: 24
                            background: Rectangle {
                                radius: 5
                                color: editSatCfgBtn.hovered
                                       ? (historyDetailsRoot.lightMode ? "#fff3bf" : "#2b2412")
                                       : (historyDetailsRoot.lightMode ? "#f8f9fa" : "#1c202c")
                                border.color: editSatCfgBtn.hovered ? "#f59f00" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#2d3345")
                            }
                            contentItem: Text {
                                text: qsTr("✏️ Edit Config")
                                font.bold: true
                                font.pixelSize: 11
                                color: editSatCfgBtn.hovered ? "#f59f00" : (historyDetailsRoot.lightMode ? "#495057" : "#ced4da")
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.satellite) {
                                    historyDetailsRoot.editSatelliteRequested(historyDetailsRoot.sessionDetails.satellite)
                                }
                            }
                        }

                        Button {
                            id: satJsonBtn
                            height: 24
                            background: Rectangle {
                                radius: 5
                                color: satJsonBtn.hovered
                                       ? (historyDetailsRoot.lightMode ? "#e9ecef" : "#242a3a")
                                       : "transparent"
                                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                            }
                            contentItem: Text {
                                text: "{ }"
                                font.bold: true
                                font.pixelSize: 11
                                color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                leftPadding: 6; rightPadding: 6
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                if (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.satellite) {
                                    var sat = historyDetailsRoot.sessionDetails.satellite
                                    var js = sat.satelliteJson || JSON.stringify(sat, null, 2)
                                    historyDetailsRoot.previewSatelliteJsonRequested(js)
                                }
                            }
                        }

                        Button {
                            id: removeSatBtn
                            height: 24
                            background: Rectangle {
                                radius: 5
                                color: removeSatBtn.hovered ? "#fa5252" : "transparent"
                            }
                            contentItem: Text {
                                text: "✕"
                                font.bold: true
                                font.pixelSize: 11
                                color: removeSatBtn.hovered ? "#ffffff" : (historyDetailsRoot.lightMode ? "#868e96" : "#6c757d")
                                leftPadding: 6; rightPadding: 6
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Remove satellite from this session")
                            onClicked: historyDetailsRoot.removeSatelliteRequested()
                        }
                    }

                    Label {
                        text: qsTr("Config")
                        font.pixelSize: 12
                        color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: {
                                if (!historyDetailsRoot.sessionDetails || !historyDetailsRoot.sessionDetails.satellite) return []
                                var s = historyDetailsRoot.sessionDetails.satellite
                                var fGhz = ((s.carrierFreqMhz || 5850.0) / 1000.0).toFixed(2).replace(/\.?0+$/, "")
                                var bMhz = ((s.channelBandwidthKhz || 20000.0) / 1000.0).toFixed(2).replace(/\.?0+$/, "")
                                var tleEpoch = historyDetailsRoot.parseTleEpochDisplay(s.tle1 || "")
                                var mod = s.modulation || "OQPSK"
                                var gamma = Number(s.codeEfficiencyCoef !== undefined ? s.codeEfficiencyCoef : 1.24).toFixed(2).replace(/\.?0+$/, "")
                                var alpha = Number(s.rolloffAlpha !== undefined ? s.rolloffAlpha : 0.35).toFixed(2).replace(/\.?0+$/, "")
                                var txPwr = (s.txPowerDbm !== undefined ? s.txPowerDbm : 33.0) + " dBm"
                                var gain = (s.txAntennaGainDbi !== undefined ? s.txAntennaGainDbi : 3.0) + " dBi"
                                return [
                                    "f=" + fGhz + " GHz",
                                    "B=" + bMhz + " MHz",
                                    "TLE=" + tleEpoch,
                                    "Mod=" + mod,
                                    "Γ=" + gamma,
                                    "alpha=" + alpha,
                                    "Tx=" + txPwr,
                                    "Gain=" + gain
                                ]
                            }

                            Rectangle {
                                height: 28
                                width: satPillText.implicitWidth + 18
                                radius: 6
                                color: satPillMouse.containsMouse
                                       ? (historyDetailsRoot.lightMode ? "#e9ecef" : "#232838")
                                       : (historyDetailsRoot.lightMode ? "#f8f9fa" : "#181c26")
                                border.color: satPillMouse.containsMouse
                                              ? "#f59f00"
                                              : (historyDetailsRoot.lightMode ? "#ced4da" : "#262b3a")
                                border.width: 1

                                Text {
                                    id: satPillText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: historyDetailsRoot.lightMode ? "#212529" : "#e9ecef"
                                }

                                MouseArea {
                                    id: satPillMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.satellite) {
                                            historyDetailsRoot.editSatelliteRequested(historyDetailsRoot.sessionDetails.satellite)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Case B: No Satellite Assigned (Blank session empty slot)
            Rectangle {
                visible: !(historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasSatellite && historyDetailsRoot.sessionDetails.satellite)
                Layout.preferredWidth: Math.min(mainContentCol.width, 560)
                implicitHeight: emptySatCol.implicitHeight + 24
                radius: 10
                color: historyDetailsRoot.lightMode ? "#f8f9fa" : "#151822"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#2c3345"
                border.width: 1

                ColumnLayout {
                    id: emptySatCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "🛰️"
                            font.pixelSize: 18
                        }

                        Label {
                            text: qsTr("No Target Satellite Assigned")
                            font.bold: true
                            font.pixelSize: 13
                            color: historyDetailsRoot.lightMode ? "#495057" : "#ced4da"
                        }
                    }

                    Label {
                        text: qsTr("Select an existing satellite as a reference to copy config from, or configure a new satellite for this session.")
                        font.pixelSize: 11
                        color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ComboBox {
                            id: refSatCombo
                            Layout.fillWidth: true
                            height: 28
                            model: historyDetailsRoot.availableSatellites
                            textRole: "name"
                            font.pixelSize: 11
                            enabled: count > 0
                            displayText: count > 0 && currentIndex >= 0 ? model[currentIndex].name : qsTr("Select reference satellite...")
                        }

                        Button {
                            height: 28
                            enabled: refSatCombo.count > 0 && refSatCombo.currentIndex >= 0
                            background: Rectangle {
                                radius: 6
                                color: parent.enabled
                                       ? (parent.hovered ? (historyDetailsRoot.lightMode ? "#e7f5ff" : "#1c3252") : (historyDetailsRoot.lightMode ? "#ffffff" : "#182236"))
                                       : (historyDetailsRoot.lightMode ? "#f1f3f5" : "#141720")
                                border.color: parent.enabled ? "#339af0" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a")
                            }
                            contentItem: Text {
                                text: qsTr("📋 Copy Reference")
                                font.bold: true
                                font.pixelSize: 11
                                color: parent.enabled ? "#339af0" : "#6c757d"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                var refSat = historyDetailsRoot.availableSatellites[refSatCombo.currentIndex]
                                if (refSat) {
                                    historyDetailsRoot.copySatelliteReferenceRequested(refSat)
                                }
                            }
                        }

                        Text {
                            text: qsTr("or")
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#868e96" : "#6c757d"
                        }

                        Button {
                            height: 28
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? "#087f5b" : "#099268"
                            }
                            contentItem: Text {
                                text: qsTr("➕ Add Target Satellite")
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: historyDetailsRoot.addSatelliteRequested()
                        }
                    }
                }
            }

            // --- 4. GROUND STATIONS SECTION ---
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 10

                Label {
                    text: qsTr("Ground Stations:")
                    font.bold: true
                    font.pixelSize: 13
                    color: historyDetailsRoot.lightMode ? "#1a1b1e" : "#e9ecef"
                }

                Item { Layout.fillWidth: true }
            }

            // Ground Stations Grid / Flow (when stations exist)
            Flow {
                Layout.fillWidth: true
                spacing: 14
                visible: historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasStations

                // Station Cards
                Repeater {
                    model: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.stations)
                           ? historyDetailsRoot.sessionDetails.stations : []

                    Rectangle {
                        id: stationCard
                        width: 380
                        implicitHeight: stCol.implicitHeight + 24
                        radius: 10
                        color: historyDetailsRoot.lightMode ? "#ffffff" : "#141720"
                        border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#222736"
                        border.width: 1

                        ColumnLayout {
                            id: stCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // Header
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: historyDetailsRoot.getStationColor(modelData.stationId || modelData.name, index)
                                }

                                Label {
                                    text: modelData.name || ("Station " + (index + 1))
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: historyDetailsRoot.lightMode ? "#212529" : "#f1f3f5"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Button {
                                    id: stCfgBtn
                                    height: 22
                                    background: Rectangle {
                                        radius: 4
                                        color: stCfgBtn.hovered
                                               ? (historyDetailsRoot.lightMode ? "#fff3bf" : "#2b2412")
                                               : (historyDetailsRoot.lightMode ? "#f8f9fa" : "#1c202c")
                                        border.color: stCfgBtn.hovered ? "#f59f00" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#2d3345")
                                    }
                                    contentItem: Text {
                                        text: qsTr("✏️ Config")
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: stCfgBtn.hovered ? "#f59f00" : (historyDetailsRoot.lightMode ? "#495057" : "#ced4da")
                                        leftPadding: 6; rightPadding: 6
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: historyDetailsRoot.editStationRequested(modelData)
                                }

                                Button {
                                    id: stJsonBtn
                                    height: 22
                                    background: Rectangle {
                                        radius: 4
                                        color: stJsonBtn.hovered
                                               ? (historyDetailsRoot.lightMode ? "#e9ecef" : "#242a3a")
                                               : "transparent"
                                        border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#2d3345"
                                    }
                                    contentItem: Text {
                                        text: "{ }"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: historyDetailsRoot.lightMode ? "#495057" : "#adb5bd"
                                        leftPadding: 5; rightPadding: 5
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        var js = modelData.stationJson || JSON.stringify(modelData, null, 2)
                                        historyDetailsRoot.previewStationJsonRequested(modelData.name || "Station", js)
                                    }
                                }

                                Button {
                                    id: stDelBtn
                                    height: 22
                                    background: Rectangle {
                                        radius: 4
                                        color: stDelBtn.hovered ? "#fa5252" : "transparent"
                                    }
                                    contentItem: Text {
                                        text: "✕"
                                        font.bold: true
                                        font.pixelSize: 10
                                        color: stDelBtn.hovered ? "#ffffff" : (historyDetailsRoot.lightMode ? "#868e96" : "#6c757d")
                                        leftPadding: 5; rightPadding: 5
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Remove station from this session")
                                    onClicked: historyDetailsRoot.removeStationRequested(modelData.stationId)
                                }
                            }

                            Label {
                                text: qsTr("Config")
                                font.pixelSize: 11
                                color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: {
                                        var band = modelData.operatingBand || modelData.band || "C-band"
                                        var gain = modelData.antennaGain !== undefined ? Number(modelData.antennaGain) : (modelData.gain || 42.0)
                                        var got = modelData.gOverT !== undefined ? Number(modelData.gOverT) : 17.5
                                        var minEl = modelData.minElevation !== undefined ? Number(modelData.minElevation) : (modelData.minElevationDeg || 5.0)
                                        return [
                                            band,
                                            "G=" + Number(gain).toFixed(1).replace(/\.0$/, "") + " dBi",
                                            "G/T=" + Number(got).toFixed(1) + " dB/K",
                                            "El≥" + Number(minEl).toFixed(0) + "°"
                                        ]
                                    }

                                    Rectangle {
                                        height: 24
                                        width: stPillText.implicitWidth + 14
                                        radius: 5
                                        color: historyDetailsRoot.lightMode ? "#f8f9fa" : "#181c26"
                                        border.color: historyDetailsRoot.lightMode ? "#ced4da" : "#262b3a"

                                        Text {
                                            id: stPillText
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.pixelSize: 10
                                            color: historyDetailsRoot.lightMode ? "#212529" : "#ced4da"
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: historyDetailsRoot.editStationRequested(stationCard.modelData)
                                        }
                                    }
                                }
                            }

                            // Coordinates badge
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Label {
                                    text: "Lat: " + (modelData.latitude !== undefined ? Number(modelData.latitude).toFixed(3) : "0.000") + "°  " +
                                          "Lon: " + (modelData.longitude !== undefined ? Number(modelData.longitude).toFixed(3) : "0.000") + "°"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    color: historyDetailsRoot.lightMode ? "#868e96" : "#6c757d"
                                }
                            }
                        }
                    }
                }

                // Add Station Section (attached card when stations exist)
                Rectangle {
                    visible: historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasStations
                    width: 320
                    implicitHeight: 120
                    radius: 10
                    color: historyDetailsRoot.lightMode ? "#f8f9fa" : "#151822"
                    border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#2c3345"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        Label {
                            text: qsTr("➕ Add Station to Session")
                            font.bold: true
                            font.pixelSize: 12
                            color: historyDetailsRoot.lightMode ? "#495057" : "#ced4da"
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            ComboBox {
                                id: existStCombo
                                Layout.fillWidth: true
                                height: 26
                                model: historyDetailsRoot.availableStations
                                textRole: "name"
                                font.pixelSize: 10
                                enabled: count > 0
                                displayText: count > 0 && currentIndex >= 0 ? model[currentIndex].name : qsTr("Select reference...")
                            }

                            Button {
                                height: 26
                                enabled: existStCombo.count > 0 && existStCombo.currentIndex >= 0
                                background: Rectangle {
                                    radius: 5
                                    color: parent.enabled
                                           ? (parent.hovered ? (historyDetailsRoot.lightMode ? "#e7f5ff" : "#1c3252") : (historyDetailsRoot.lightMode ? "#ffffff" : "#182236"))
                                           : (historyDetailsRoot.lightMode ? "#f1f3f5" : "#141720")
                                    border.color: parent.enabled ? "#339af0" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a")
                                }
                                contentItem: Text {
                                    text: qsTr("📋 Copy")
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: parent.enabled ? "#339af0" : "#6c757d"
                                    leftPadding: 6; rightPadding: 6
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: {
                                    var ref = historyDetailsRoot.availableStations[existStCombo.currentIndex]
                                    if (ref) historyDetailsRoot.copyStationReferenceRequested(ref)
                                }
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            height: 26
                            background: Rectangle {
                                radius: 5
                                color: parent.hovered ? "#087f5b" : "#099268"
                            }
                            contentItem: Text {
                                text: qsTr("➕ Create New Station")
                                font.bold: true
                                font.pixelSize: 10
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: historyDetailsRoot.addStationRequested()
                        }
                    }
                }
            }

            // Empty Ground Stations Card (when no stations exist in session)
            Rectangle {
                visible: !(historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasStations)
                Layout.preferredWidth: Math.min(mainContentCol.width, 560)
                implicitHeight: emptyStCol.implicitHeight + 24
                radius: 10
                color: historyDetailsRoot.lightMode ? "#f8f9fa" : "#151822"
                border.color: historyDetailsRoot.lightMode ? "#dee2e6" : "#2c3345"
                border.width: 1

                ColumnLayout {
                    id: emptyStCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "📡"
                            font.pixelSize: 18
                        }

                        Label {
                            text: qsTr("No Ground Stations Added to this Session")
                            font.bold: true
                            font.pixelSize: 13
                            color: historyDetailsRoot.lightMode ? "#495057" : "#ced4da"
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: qsTr("Select an existing ground station to copy config from, or create a new ground station for this session.")
                        font.pixelSize: 11
                        color: historyDetailsRoot.lightMode ? "#6c757d" : "#909296"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ComboBox {
                            id: emptyRefStCombo
                            Layout.fillWidth: true
                            height: 28
                            model: historyDetailsRoot.availableStations
                            textRole: "name"
                            font.pixelSize: 11
                            enabled: count > 0
                            displayText: count > 0 && currentIndex >= 0 ? model[currentIndex].name : qsTr("Select reference ground station...")
                        }

                        Button {
                            height: 28
                            enabled: emptyRefStCombo.count > 0 && emptyRefStCombo.currentIndex >= 0
                            background: Rectangle {
                                radius: 6
                                color: parent.enabled
                                       ? (parent.hovered ? (historyDetailsRoot.lightMode ? "#e7f5ff" : "#1c3252") : (historyDetailsRoot.lightMode ? "#ffffff" : "#182236"))
                                       : (historyDetailsRoot.lightMode ? "#f1f3f5" : "#141720")
                                border.color: parent.enabled ? "#339af0" : (historyDetailsRoot.lightMode ? "#dee2e6" : "#262b3a")
                            }
                            contentItem: Text {
                                text: qsTr("📋 Copy Reference")
                                font.bold: true
                                font.pixelSize: 11
                                color: parent.enabled ? "#339af0" : "#6c757d"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                var refSt = historyDetailsRoot.availableStations[emptyRefStCombo.currentIndex]
                                if (refSt) {
                                    historyDetailsRoot.copyStationReferenceRequested(refSt)
                                }
                            }
                        }

                        Text {
                            text: qsTr("or")
                            font.pixelSize: 11
                            color: historyDetailsRoot.lightMode ? "#868e96" : "#6c757d"
                        }

                        Button {
                            height: 28
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? "#087f5b" : "#099268"
                            }
                            contentItem: Text {
                                text: qsTr("➕ Add Ground Station")
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                leftPadding: 8; rightPadding: 8
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: historyDetailsRoot.addStationRequested()
                        }
                    }
                }
            }

            // --- 5. SESSION OVERVIEW BLOCK (Map + Start/End/Duration + History Pass Selector) ---
            SessionOverviewBlock {
                Layout.fillWidth: true
                lightMode: historyDetailsRoot.lightMode
                isHistoryMode: true
                sessionEvent: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session)
                              ? historyDetailsRoot.sessionDetails.session : null
                startTimeText: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session)
                               ? (historyDetailsRoot.sessionDetails.session.combinedAosUtc ||
                                  historyDetailsRoot.sessionDetails.session.dateUtc || "--")
                               : "--"
                endTimeText: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session)
                             ? (historyDetailsRoot.sessionDetails.session.combinedLosUtc || "--")
                             : "--"
                durationText: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session)
                              ? (historyDetailsRoot.sessionDetails.session.durationFormatted || "--")
                              : "--"
                targetSatellite: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.hasSatellite)
                                 ? historyDetailsRoot.sessionDetails.satellite : null
                propagator: historyDetailsRoot.propagator
                stationsList: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.stations)
                              ? historyDetailsRoot.sessionDetails.stations : []
                foundPasses: historyDetailsRoot.historyFoundPasses
                hasSearchedPasses: historyDetailsRoot.historyHasSearchedPasses
                selectedPassAos: (historyDetailsRoot.sessionDetails && historyDetailsRoot.sessionDetails.session)
                                 ? (historyDetailsRoot.sessionDetails.session.combinedAosUtc || "") : ""

                onFindPassesRangeRequested: (startUtcStr, endUtcStr) => {
                    historyDetailsRoot.findHistoryPassesRangeRequested(startUtcStr, endUtcStr)
                }

                onPassWindowSelected: (passEvent) => {
                    historyDetailsRoot.historyPassWindowSelected(passEvent)
                }
            }
        }
    }
}
