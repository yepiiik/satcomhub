import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: overviewRoot

    property bool lightMode: false
    property bool isHistoryMode: false
    property var sessionEvent: null        // Pass / session card metadata
    property string startTimeText: "--"
    property string endTimeText: "--"
    property string durationText: "--"
    property var stationsList: []          // Array of { stationId, name, latitude, longitude, ... }
    property var targetSatellite: null     // Satellite object (for TLE & altitude)
    property var propagator: null          // SatellitePropagator instance for exact flyby trajectory
    property var foundPasses: []           // History mode: array of pass events from propagator
    property string selectedPassAos: ""    // Currently selected pass AOS for highlight
    property bool hasSearchedPasses: false

    signal findPassesRangeRequested(string startUtcStr, string endUtcStr)
    signal passWindowSelected(var passEvent)

    spacing: 8

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

    function formatUtcInput(dt) {
        function pad2(n) { return n < 10 ? ("0" + n) : String(n) }
        return dt.getUTCFullYear() + "-" + pad2(dt.getUTCMonth() + 1) + "-" + pad2(dt.getUTCDate()) +
               " " + pad2(dt.getUTCHours()) + ":" + pad2(dt.getUTCMinutes())
    }

    function applyPresetRange(offsetHours, windowHours) {
        var nowMs = Date.now()
        var fromDt = new Date(nowMs + offsetHours * 3600 * 1000)
        var toDt = new Date(fromDt.getTime() + windowHours * 3600 * 1000)
        fromDateInput.text = formatUtcInput(fromDt)
        toDateInput.text = formatUtcInput(toDt)
    }

    ListModel { id: overviewStationsModel }
    ListModel { id: overviewSatellitesModel }
    property var overviewStationsMap: ({})
    property var overviewSatellitesMap: ({})
    property var overviewSatellitesList: []
    property var overviewSatelliteTracksMap: ({})

    function syncMapModels() {
        overviewStationsModel.clear()
        var stMap = {}
        var sts = overviewRoot.stationsList || []
        var sumLat = 0.0
        var sumLon = 0.0
        for (var i = 0; i < sts.length; i++) {
            var st = sts[i]
            var stCopy = {
                stationId: st.stationId || ("GS-" + (i + 1)),
                name: st.name || ("Station " + (i + 1)),
                latitude: Number(st.latitude !== undefined ? st.latitude : 0.0),
                longitude: Number(st.longitude !== undefined ? st.longitude : 0.0),
                altitude: Number(st.altitude !== undefined ? st.altitude : 0.0),
                minElevation: Number(st.minElevation !== undefined ? st.minElevation : 5.0),
                operatingBand: st.operatingBand || st.band || "C-band",
                active: true
            }
            overviewStationsModel.append(stCopy)
            stMap[stCopy.stationId] = stCopy
            sumLat += stCopy.latitude
            sumLon += stCopy.longitude
        }
        overviewStationsMap = stMap

        overviewSatellitesModel.clear()
        var satMap = {}
        var satList = []
        var tracksMap = {}
        var selSatId = ""

        if (overviewRoot.targetSatellite && overviewRoot.targetSatellite.name) {
            var sat = overviewRoot.targetSatellite
            var sid = sat.satId || "SAT-01"
            var latVal = Number(sat.latitude !== undefined ? sat.latitude : 0.0)
            var lonVal = Number(sat.longitude !== undefined ? sat.longitude : 0.0)
            var altVal = Number(sat.altitudeKm !== undefined ? sat.altitudeKm : 500.0)

            // Compute exact flyby trajectory for [startTimeText, endTimeText]
            if (overviewRoot.propagator && sat.tle1 && sat.tle2 &&
                overviewRoot.startTimeText && overviewRoot.startTimeText !== "--" &&
                overviewRoot.endTimeText && overviewRoot.endTimeText !== "--") {
                var flybyPts = overviewRoot.propagator.computeSessionTrajectory(
                    sat.tle1, sat.tle2,
                    overviewRoot.startTimeText, overviewRoot.endTimeText,
                    10.0
                )
                if (flybyPts && flybyPts.length > 0) {
                    tracksMap[sid] = {
                        current: flybyPts,
                        previous: [],
                        next: []
                    }
                    var midPt = flybyPts[Math.floor(flybyPts.length / 2)]
                    latVal = Number(midPt.latitude)
                    lonVal = Number(midPt.longitude)
                    if (midPt.altitudeKm !== undefined) altVal = Number(midPt.altitudeKm)
                }
            }

            var visRad = Number(sat.visibilityRadiusMeters !== undefined ? sat.visibilityRadiusMeters : 0.0)
            if (visRad <= 0.0 && overviewRoot.propagator) {
                visRad = overviewRoot.propagator.calculateVisibilityRadius(altVal, 5.0)
            }

            var satCopy = {
                satId: sid,
                name: sat.name || "Satellite",
                latitude: latVal,
                longitude: lonVal,
                altitudeKm: altVal,
                visibilityRadiusMeters: visRad
            }
            overviewSatellitesModel.append(satCopy)
            satMap[sid] = satCopy
            satList.push(satCopy)
            selSatId = sid
            overviewMapComponent.targetSatelliteAltitudeKm = altVal
        }
        overviewSatellitesMap = satMap
        overviewSatellitesList = satList
        overviewSatelliteTracksMap = tracksMap
        overviewMapComponent.selectedSatelliteId = selSatId

        if (sts.length > 0) {
            overviewMapComponent.focusOnCoordinate(sumLat / sts.length, sumLon / sts.length, sts.length > 1 ? 3.0 : 4.5)
        } else if (satList.length > 0) {
            overviewMapComponent.focusOnCoordinate(satList[0].latitude, satList[0].longitude, 3.0)
        }
        overviewMapComponent.requestCanvasRedraw()
    }

    onStationsListChanged: syncMapModels()
    onTargetSatelliteChanged: syncMapModels()
    onStartTimeTextChanged: syncMapModels()
    onEndTimeTextChanged: syncMapModels()
    onPropagatorChanged: syncMapModels()
    Component.onCompleted: {
        syncMapModels()
        applyPresetRange(-24, 24)
    }

    // Derived session summary fields for the Planning-style card
    readonly property string cardPassIndex: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.passIndex !== undefined)
            return String(overviewRoot.sessionEvent.passIndex)
        return "1"
    }
    readonly property string cardRelativeAos: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.relativeAos && overviewRoot.sessionEvent.relativeAos !== "")
            return overviewRoot.sessionEvent.relativeAos
        if (overviewRoot.startTimeText && overviewRoot.startTimeText !== "--")
            return overviewRoot.startTimeText
        return qsTr("No pass selected")
    }
    readonly property string cardDuration: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.combinedDurationFormatted)
            return overviewRoot.sessionEvent.combinedDurationFormatted
        return overviewRoot.durationText || "--"
    }
    readonly property string cardStationNames: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.stationNames && overviewRoot.sessionEvent.stationNames !== "")
            return overviewRoot.sessionEvent.stationNames
        var sts = overviewRoot.stationsList || []
        if (sts.length === 0) return qsTr("No ground stations")
        var names = []
        for (var i = 0; i < sts.length; i++) names.push(sts[i].name || sts[i].stationId)
        return names.join(" + ")
    }
    readonly property int cardStationCount: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.stationCount !== undefined)
            return overviewRoot.sessionEvent.stationCount
        return overviewRoot.stationsList ? overviewRoot.stationsList.length : 0
    }
    readonly property bool cardIsMulti: {
        if (overviewRoot.sessionEvent && overviewRoot.sessionEvent.isMultiStation !== undefined)
            return overviewRoot.sessionEvent.isMultiStation
        return cardStationCount >= 2
    }
    readonly property bool cardHasOverlap: Boolean(overviewRoot.sessionEvent && overviewRoot.sessionEvent.hasConcurrentOverlap)
    readonly property string cardOverlapDur: (overviewRoot.sessionEvent && overviewRoot.sessionEvent.overlapDurationFormatted) ? overviewRoot.sessionEvent.overlapDurationFormatted : ""
    readonly property real cardWinGain: (overviewRoot.sessionEvent && overviewRoot.sessionEvent.windowGainPercent !== undefined) ? Number(overviewRoot.sessionEvent.windowGainPercent) : 0
    readonly property real cardMaxEl: (overviewRoot.sessionEvent && overviewRoot.sessionEvent.maxElevationDeg !== undefined) ? Number(overviewRoot.sessionEvent.maxElevationDeg) : 0
    readonly property string cardTimeWindow: {
        var aos = overviewRoot.startTimeText || ""
        var los = overviewRoot.endTimeText || ""
        if (aos.length >= 19 && los.length >= 19) {
            return aos.substring(11, 19) + " → " + los.substring(11, 19)
        }
        if (aos !== "--" && los !== "--") return aos + " → " + los
        return "-- → --"
    }

    // Section Title
    Label {
        text: qsTr("Session Overview:")
        font.bold: true
        font.pixelSize: 13
        color: overviewRoot.lightMode ? "#1a1b1e" : "#e9ecef"
        Layout.topMargin: 4
    }

    // Overview Card (50% Interactive Map | 50% Session Info)
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.max(300, overviewSplitRow.implicitHeight + 24)
        radius: 10
        color: overviewRoot.lightMode ? "#ffffff" : "#141720"
        border.color: overviewRoot.lightMode ? "#dee2e6" : "#222736"
        border.width: 1

        RowLayout {
            id: overviewSplitRow
            anchors.fill: parent
            anchors.margins: 12
            spacing: 14

            // --- LEFT HALF (50%): INTERACTIVE MAP COMPONENT (same as Objects Tab) ---
            Rectangle {
                id: mapHalfContainer
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.minimumHeight: 276
                radius: 8
                color: "#090d16"
                border.color: overviewRoot.lightMode ? "#ced4da" : "#262b3a"
                border.width: 1
                clip: true

                MapComponent {
                    id: overviewMapComponent
                    anchors.fill: parent
                    lightMode: overviewRoot.lightMode
                    stationsModel: overviewStationsModel
                    stationsList: overviewRoot.stationsList || []
                    stationsMap: overviewRoot.overviewStationsMap
                    satellitesModel: overviewSatellitesModel
                    satellitesList: overviewRoot.overviewSatellitesList
                    satellitesMap: overviewRoot.overviewSatellitesMap
                    satelliteTracksMap: overviewRoot.overviewSatelliteTracksMap
                    pickModeEnabled: false
                }
            }

            // --- RIGHT HALF (50%): PLANNING-STYLE SESSION CARD + TIMING + HISTORY SELECTOR ---
            ColumnLayout {
                id: infoHalfCol
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: 10

                // 1. Session Card (exact same structure as PlanningListSidebar card)
                Rectangle {
                    id: overviewSessionCard
                    Layout.fillWidth: true
                    implicitHeight: sessionCardInnerCol.implicitHeight + 16
                    radius: 8
                    color: overviewRoot.lightMode ? "#e7f5ff" : "#162238"
                    border.color: "#339af0"
                    border.width: 1.5

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        radius: 2
                        color: "#339af0"
                    }

                    ColumnLayout {
                        id: sessionCardInnerCol
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 5

                        // Top Row: Pass # + Relative AOS + Duration
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                width: 24
                                height: 18
                                radius: 4
                                color: overviewRoot.lightMode ? "#d0ebff" : "#262c3d"
                                Text {
                                    anchors.centerIn: parent
                                    text: "#" + overviewRoot.cardPassIndex
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: overviewRoot.lightMode ? "#1971c2" : "#adb5bd"
                                }
                            }

                            Label {
                                text: overviewRoot.cardRelativeAos
                                font.bold: true
                                font.pixelSize: 12
                                color: "#339af0"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                height: 18
                                implicitWidth: ovCardDurText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 9
                                color: overviewRoot.lightMode ? "#d0ebff" : "#14233c"
                                Text {
                                    id: ovCardDurText
                                    anchors.centerIn: parent
                                    text: overviewRoot.cardDuration
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: "#339af0"
                                }
                            }
                        }

                        // Stations Tag
                        Label {
                            text: "📡 " + overviewRoot.cardStationNames
                            font.pixelSize: 11
                            color: overviewRoot.lightMode ? "#495057" : "#ced4da"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Multi-station / Overlap Badges
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            visible: overviewRoot.cardIsMulti || overviewRoot.cardHasOverlap

                            Rectangle {
                                visible: overviewRoot.cardIsMulti
                                height: 17
                                implicitWidth: ovCardMultiText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 4
                                color: overviewRoot.lightMode ? "#ebfbee" : "#132d1d"
                                border.color: "#40c057"
                                Text {
                                    id: ovCardMultiText
                                    anchors.centerIn: parent
                                    text: "🤝 " + overviewRoot.cardStationCount + " Stations" +
                                          (overviewRoot.cardWinGain > 0 ? " (+" + overviewRoot.cardWinGain + "%)" : "")
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#40c057"
                                }
                            }

                            Rectangle {
                                visible: overviewRoot.cardHasOverlap
                                height: 17
                                implicitWidth: ovCardOvText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 4
                                color: overviewRoot.lightMode ? "#fff9db" : "#2d2411"
                                border.color: "#f59f00"
                                Text {
                                    id: ovCardOvText
                                    anchors.centerIn: parent
                                    text: "⚡ Overlap " + overviewRoot.cardOverlapDur
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#f59f00"
                                }
                            }
                        }

                        // Metrics Row (Elevation + UTC Window)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                height: 17
                                implicitWidth: ovCardElText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 4
                                color: overviewRoot.cardMaxEl >= 50.0 ? "#2f9e44" : (overviewRoot.cardMaxEl >= 20.0 ? "#f59f00" : "#868e96")
                                Text {
                                    id: ovCardElText
                                    anchors.centerIn: parent
                                    text: "Peak " + overviewRoot.cardMaxEl + "°"
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#ffffff"
                                }
                            }

                            Label {
                                text: overviewRoot.cardTimeWindow
                                font.pixelSize: 10
                                font.family: "monospace"
                                color: overviewRoot.lightMode ? "#495057" : "#adb5bd"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // 2. Session Start / End / Duration Cards
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: 8
                    rowSpacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: startCol.implicitHeight + 12
                        radius: 7
                        color: overviewRoot.lightMode ? "#f8f9fa" : "#181c26"
                        border.color: overviewRoot.lightMode ? "#dee2e6" : "#262b3a"

                        ColumnLayout {
                            id: startCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            Label {
                                text: qsTr("Session Start")
                                font.pixelSize: 10
                                font.bold: true
                                color: "#51cf66"
                            }
                            Label {
                                Layout.fillWidth: true
                                text: overviewRoot.startTimeText || "--"
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: true
                                color: overviewRoot.lightMode ? "#212529" : "#f1f3f5"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: endCol.implicitHeight + 12
                        radius: 7
                        color: overviewRoot.lightMode ? "#f8f9fa" : "#181c26"
                        border.color: overviewRoot.lightMode ? "#dee2e6" : "#262b3a"

                        ColumnLayout {
                            id: endCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            Label {
                                text: qsTr("Session End")
                                font.pixelSize: 10
                                font.bold: true
                                color: "#ff6b6b"
                            }
                            Label {
                                Layout.fillWidth: true
                                text: overviewRoot.endTimeText || "--"
                                font.pixelSize: 10
                                font.family: "monospace"
                                font.bold: true
                                color: overviewRoot.lightMode ? "#212529" : "#f1f3f5"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: durCol.implicitHeight + 12
                        radius: 7
                        color: overviewRoot.lightMode ? "#f8f9fa" : "#181c26"
                        border.color: overviewRoot.lightMode ? "#dee2e6" : "#262b3a"

                        ColumnLayout {
                            id: durCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            Label {
                                text: qsTr("Duration")
                                font.pixelSize: 10
                                font.bold: true
                                color: "#339af0"
                            }
                            Label {
                                Layout.fillWidth: true
                                text: overviewRoot.durationText || "--"
                                font.pixelSize: 11
                                font.family: "monospace"
                                font.bold: true
                                color: overviewRoot.lightMode ? "#212529" : "#f1f3f5"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // 3. History Mode: Button to open Date-Range Pass Selection Popup
                Button {
                    id: openPassSelectorBtn
                    visible: overviewRoot.isHistoryMode
                    Layout.fillWidth: true
                    height: 32
                    enabled: Boolean(overviewRoot.targetSatellite &&
                                     overviewRoot.targetSatellite.tle1 &&
                                     overviewRoot.targetSatellite.tle2 &&
                                     overviewRoot.stationsList &&
                                     overviewRoot.stationsList.length > 0)
                    background: Rectangle {
                        radius: 7
                        color: openPassSelectorBtn.enabled
                               ? (openPassSelectorBtn.hovered ? "#1c7ed6" : "#228be6")
                               : (overviewRoot.lightMode ? "#e9ecef" : "#1c202c")
                    }
                    contentItem: Text {
                        text: qsTr("🔍 Select Pass Window (Date Range)...")
                        font.bold: true
                        font.pixelSize: 11
                        color: openPassSelectorBtn.enabled ? "#ffffff" : "#868e96"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: historyPassPopup.open()
                }

                Label {
                    visible: overviewRoot.isHistoryMode && !openPassSelectorBtn.enabled
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Assign a Target Satellite (with TLE) and at least one Ground Station above to select a pass window.")
                    font.pixelSize: 10
                    color: "#f59f00"
                }
            }
        }
    }

    // ================= HISTORY PASS WINDOW SELECTOR POPUP (DATE RANGE FROM -> TO) =================
    Popup {
        id: historyPassPopup
        modal: true
        focus: true
        dim: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        anchors.centerIn: Overlay.overlay
        width: Math.min(Overlay.overlay ? Overlay.overlay.width - 60 : 720, 740)
        height: Math.min(Overlay.overlay ? Overlay.overlay.height - 80 : 620, 620)
        padding: 0

        background: Rectangle {
            radius: 12
            color: overviewRoot.lightMode ? "#ffffff" : "#141720"
            border.color: overviewRoot.lightMode ? "#ced4da" : "#373a40"
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Popup Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "🛰️"
                    font.pixelSize: 20
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: qsTr("Select Satellite Pass Window")
                        font.bold: true
                        font.pixelSize: 16
                        color: overviewRoot.lightMode ? "#1a1b1e" : "#f1f3f5"
                    }
                    Label {
                        text: qsTr("Search passes for %1 across %2 session station(s)")
                              .arg(overviewRoot.targetSatellite ? overviewRoot.targetSatellite.name : "Satellite")
                              .arg(overviewRoot.stationsList ? overviewRoot.stationsList.length : 0)
                        font.pixelSize: 11
                        color: overviewRoot.lightMode ? "#6c757d" : "#909296"
                    }
                }

                Button {
                    width: 30
                    height: 30
                    background: Rectangle {
                        radius: 6
                        color: parent.hovered ? (overviewRoot.lightMode ? "#e9ecef" : "#2c2e33") : "transparent"
                    }
                    contentItem: Text {
                        text: "✕"
                        font.bold: true
                        font.pixelSize: 14
                        color: overviewRoot.lightMode ? "#495057" : "#c1c2c5"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: historyPassPopup.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: overviewRoot.lightMode ? "#dee2e6" : "#262b3a"
            }

            // Date Range From -> To Inputs + Quick Presets
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: rangeCol.implicitHeight + 20
                radius: 8
                color: overviewRoot.lightMode ? "#f8f9fa" : "#181c26"
                border.color: overviewRoot.lightMode ? "#dee2e6" : "#262b3a"

                ColumnLayout {
                    id: rangeCol
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label {
                                text: qsTr("From (UTC, yyyy-MM-dd HH:mm)")
                                font.pixelSize: 10
                                font.bold: true
                                color: overviewRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                            TextField {
                                id: fromDateInput
                                Layout.fillWidth: true
                                height: 30
                                placeholderText: "yyyy-MM-dd HH:mm"
                                font.family: "monospace"
                                font.pixelSize: 12
                                color: overviewRoot.lightMode ? "#212529" : "#f8f9fa"
                                background: Rectangle {
                                    radius: 6
                                    color: overviewRoot.lightMode ? "#ffffff" : "#11141c"
                                    border.color: fromDateInput.activeFocus ? "#339af0" : (overviewRoot.lightMode ? "#ced4da" : "#2d3345")
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label {
                                text: qsTr("To (UTC, yyyy-MM-dd HH:mm)")
                                font.pixelSize: 10
                                font.bold: true
                                color: overviewRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                            TextField {
                                id: toDateInput
                                Layout.fillWidth: true
                                height: 30
                                placeholderText: "yyyy-MM-dd HH:mm"
                                font.family: "monospace"
                                font.pixelSize: 12
                                color: overviewRoot.lightMode ? "#212529" : "#f8f9fa"
                                background: Rectangle {
                                    radius: 6
                                    color: overviewRoot.lightMode ? "#ffffff" : "#11141c"
                                    border.color: toDateInput.activeFocus ? "#339af0" : (overviewRoot.lightMode ? "#ced4da" : "#2d3345")
                                }
                            }
                        }

                        Button {
                            Layout.alignment: Qt.AlignBottom
                            height: 30
                            background: Rectangle {
                                radius: 6
                                color: parent.hovered ? "#1c7ed6" : "#228be6"
                            }
                            contentItem: Text {
                                text: qsTr("🔍 Search Passes")
                                font.bold: true
                                font.pixelSize: 11
                                color: "#ffffff"
                                leftPadding: 12; rightPadding: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                overviewRoot.findPassesRangeRequested(fromDateInput.text, toDateInput.text)
                            }
                        }
                    }

                    // Quick Preset Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Label {
                            text: qsTr("Presets:")
                            font.pixelSize: 10
                            color: overviewRoot.lightMode ? "#6c757d" : "#909296"
                        }

                        Repeater {
                            model: [
                                { label: "Last 24h", offset: -24, hours: 24 },
                                { label: "Last 48h", offset: -48, hours: 48 },
                                { label: "Last 7d", offset: -168, hours: 168 },
                                { label: "Next 24h", offset: 0, hours: 24 },
                                { label: "Next 48h", offset: 0, hours: 48 }
                            ]

                            Button {
                                height: 22
                                background: Rectangle {
                                    radius: 4
                                    color: parent.hovered
                                           ? (overviewRoot.lightMode ? "#e7f5ff" : "#1c3252")
                                           : (overviewRoot.lightMode ? "#ffffff" : "#141720")
                                    border.color: overviewRoot.lightMode ? "#ced4da" : "#2d3345"
                                }
                                contentItem: Text {
                                    text: modelData.label
                                    font.pixelSize: 10
                                    color: overviewRoot.lightMode ? "#495057" : "#ced4da"
                                    leftPadding: 8; rightPadding: 8
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: {
                                    overviewRoot.applyPresetRange(modelData.offset, modelData.hours)
                                    overviewRoot.findPassesRangeRequested(fromDateInput.text, toDateInput.text)
                                }
                            }
                        }
                    }
                }
            }

            // Results Count / Hint
            Label {
                text: overviewRoot.hasSearchedPasses
                      ? qsTr("Found %1 pass(es) in date range — click a pass to calculate SNR & apply to this history session:").arg(overviewRoot.foundPasses ? overviewRoot.foundPasses.length : 0)
                      : qsTr("Enter a UTC date range (From → To) or pick a preset and click Search Passes.")
                font.pixelSize: 11
                color: overviewRoot.lightMode ? "#6c757d" : "#909296"
            }

            // Found Passes ListView (same card style as PlanningListSidebar)
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: overviewRoot.foundPasses || []

                delegate: Rectangle {
                    id: popupPassCard
                    width: ListView.view.width
                    implicitHeight: popupCardCol.implicitHeight + 16
                    radius: 8

                    readonly property bool isSelected: overviewRoot.selectedPassAos !== "" &&
                                                       overviewRoot.selectedPassAos === modelData.combinedAosUtc

                    color: isSelected
                           ? (overviewRoot.lightMode ? "#e7f5ff" : "#162238")
                           : (popupPassMouse.containsMouse
                              ? (overviewRoot.lightMode ? "#f1f3f5" : "#222736")
                              : (overviewRoot.lightMode ? "#f8f9fa" : "#1a1e29"))
                    border.color: isSelected ? "#339af0" : (overviewRoot.lightMode ? "#dee2e6" : "#262b3a")
                    border.width: isSelected ? 1.5 : 1

                    ColumnLayout {
                        id: popupCardCol
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                width: 24
                                height: 18
                                radius: 4
                                color: overviewRoot.lightMode ? "#e9ecef" : "#262c3d"
                                Text {
                                    anchors.centerIn: parent
                                    text: "#" + modelData.passIndex
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: overviewRoot.lightMode ? "#495057" : "#adb5bd"
                                }
                            }

                            Label {
                                text: modelData.relativeAos || ""
                                font.bold: true
                                font.pixelSize: 11
                                color: popupPassCard.isSelected ? "#339af0" : (overviewRoot.lightMode ? "#212529" : "#f1f3f5")
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                height: 18
                                implicitWidth: pDurText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 9
                                color: overviewRoot.lightMode ? "#e7f5ff" : "#14233c"
                                Text {
                                    id: pDurText
                                    anchors.centerIn: parent
                                    text: modelData.combinedDurationFormatted || "--"
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: "#339af0"
                                }
                            }
                        }

                        Label {
                            text: "📡 " + (modelData.stationNames || "")
                            font.pixelSize: 10
                            color: overviewRoot.lightMode ? "#6c757d" : "#909296"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                visible: modelData.isMultiStation
                                height: 16
                                implicitWidth: pMultiText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 4
                                color: overviewRoot.lightMode ? "#ebfbee" : "#132d1d"
                                border.color: "#40c057"
                                Text {
                                    id: pMultiText
                                    anchors.centerIn: parent
                                    text: "🤝 " + modelData.stationCount + " Stations" +
                                          (modelData.windowGainPercent > 0 ? " (+" + modelData.windowGainPercent + "%)" : "")
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#40c057"
                                }
                            }

                            Rectangle {
                                height: 16
                                implicitWidth: pElText.implicitWidth + 8
                                Layout.preferredWidth: implicitWidth
                                radius: 4
                                color: modelData.maxElevationDeg >= 50.0 ? "#2f9e44" : (modelData.maxElevationDeg >= 20.0 ? "#f59f00" : "#868e96")
                                Text {
                                    id: pElText
                                    anchors.centerIn: parent
                                    text: "Peak " + modelData.maxElevationDeg + "°"
                                    font.bold: true
                                    font.pixelSize: 9
                                    color: "#ffffff"
                                }
                            }

                            Label {
                                text: (modelData.combinedAosUtc || "") + " → " + (modelData.combinedLosUtc || "")
                                font.pixelSize: 10
                                font.family: "monospace"
                                color: overviewRoot.lightMode ? "#868e96" : "#6c757d"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    MouseArea {
                        id: popupPassMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            historyPassPopup.close()
                            overviewRoot.passWindowSelected(modelData)
                        }
                    }
                }
            }
        }
    }
}
