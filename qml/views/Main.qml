import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import satcomhub

ApplicationWindow {
    id: window
    width: 1440
    height: 880
    minimumWidth: 800
    minimumHeight: 500
    visible: true
    title: qsTr("SatComHub - Satellite & Ground Station Monitor")

    property bool lightMode: Application.styleHints.colorScheme === Qt.Light
    property color bgDark: "#1a1b1e"
    property color bgLight: "#f8f9fa"
    property color panelDark: "#25262b"
    property color panelLight: "#ffffff"
    property color cardDark: "#2c2e33"
    property color cardLight: "#f1f3f5"
    property color textDark: "#e9ecef"
    property color textLight: "#212529"
    property color subTextDark: "#909296"
    property color subTextLight: "#6c757d"
    property color accentColor: "#228be6"
    property color satColor: "#f59f00"
    property color borderDark: "#373a40"
    property color borderLight: "#dee2e6"

    property bool showAddStationForm: false
    property bool showAddSatForm: false
    property bool pickOnMapActive: false
    property bool isResettingForm: false

    property string selectedStationId: ""
    property string selectedSatelliteId: ""
    property real currentSatAltKm: 500.0
    property string currentSatName: "Default LEO (500 km)"

    // Edit states
    property string editingStationId: ""
    property string editingSatId: ""

    SatellitePropagator {
        id: propagator
    }

    StationManager {
        id: stationManager
    }

    StationDialog {
        id: stationDialog
        lightMode: window.lightMode
        accentColor: window.accentColor
        stationManager: stationManager

        onStationCommitted: (data, isEdit) => {
            if (isEdit) {
                for (var i = 0; i < stationsModel.count; i++) {
                    if (stationsModel.get(i).stationId === data.stationId) {
                        stationsModel.set(i, data)
                        break
                    }
                }
                window.selectedStationId = data.stationId
            } else {
                var newId = (data.stationId && data.stationId.length > 0) ? data.stationId : ("GS-0" + (stationsModel.count + 1))
                data.stationId = newId
                stationsModel.append(data)
                window.selectedStationId = newId
            }
            window.syncStationsToDisk()
            mapComponent.focusOnCoordinate(data.latitude, data.longitude)
            mapComponent.removeDraftMarker()
            mapComponent.requestCanvasRedraw()
        }

        onPickOnMapRequested: {
            stationDialog.close()
            window.pickOnMapActive = true
            mapComponent.pickModeEnabled = true
        }
    }

    StationJsonViewer {
        id: stationDetailsViewer
        lightMode: window.lightMode
        accentColor: window.accentColor
    }

    property string currentUtcString: propagator.currentUtcIsoString()
    property int liveTickCounter: 0

    Timer {
        id: liveSatTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            window.currentUtcString = propagator.currentUtcIsoString()
            window.liveTickCounter++
            var shouldRefreshTrack = (window.liveTickCounter % 30 === 0)
            window.updateLiveSatellitePositions(shouldRefreshTrack)
        }
    }

    function updateLiveSatellitePositions(refreshTrack) {
        if (!satellitesModel || satellitesModel.count === 0) return

        for (var i = 0; i < satellitesModel.count; i++) {
            var sat = satellitesModel.get(i)
            if (!sat.tle1 || !sat.tle2) continue

            var prop = propagator.propagateTle(sat.tle1, sat.tle2, 0.0)
            if (prop.valid) {
                satellitesModel.setProperty(i, "latitude", prop.latitude)
                satellitesModel.setProperty(i, "longitude", prop.longitude)
                satellitesModel.setProperty(i, "altitudeKm", prop.altitudeKm)
                satellitesModel.setProperty(i, "visibilityRadiusMeters", prop.visibilityRadiusMeters)
                if (prop.velocityKmS !== undefined) {
                    satellitesModel.setProperty(i, "velocityKmS", prop.velocityKmS)
                }

                if (refreshTrack) {
                    var tracks = propagator.computeOrbitTracks(sat.tle1, sat.tle2, 0.75)
                    satellitesModel.setProperty(i, "trajectory", tracks.current || [])
                    satellitesModel.setProperty(i, "prevTrajectory", tracks.previous || [])
                    satellitesModel.setProperty(i, "nextTrajectory", tracks.next || [])
                }

                if (window.selectedSatelliteId === sat.satId) {
                    window.currentSatAltKm = prop.altitudeKm
                }
            }
        }
        mapComponent.requestCanvasRedraw()
    }

    ListModel {
        id: stationsModel
    }

    ListModel {
        id: satellitesModel
    }

    function selectStation(stationId, latitude, longitude) {
        window.selectedSatelliteId = ""
        window.selectedStationId = stationId
        mapComponent.focusOnCoordinate(latitude, longitude)
    }

    function selectSatellite(satId, latitude, longitude, altitudeKm, satName) {
        window.selectedStationId = ""
        window.selectedSatelliteId = satId
        if (altitudeKm > 0) {
            window.currentSatAltKm = altitudeKm
            window.currentSatName = satName || "Selected Satellite"
        }
        mapComponent.focusOnCoordinate(latitude, longitude)
    }

    // --- Station Edit & Delete ---
    function startEditStation(station) {
        window.selectedStationId = station.stationId
        stationDialog.openForEdit(station)
        mapComponent.focusOnCoordinate(station.latitude, station.longitude)
    }

    function deleteStation(stationId) {
        for (var i = 0; i < stationsModel.count; i++) {
            if (stationsModel.get(i).stationId === stationId) {
                stationsModel.remove(i)
                break
            }
        }
        if (window.selectedStationId === stationId) {
            window.selectedStationId = ""
        }
        window.syncStationsToDisk()
        mapComponent.requestCanvasRedraw()
    }

    function syncStationsToDisk() {
        var list = []
        for (var i = 0; i < stationsModel.count; i++) {
            var st = stationsModel.get(i)
            list.push({
                stationId: st.stationId || ("GS-0" + (i + 1)),
                name: st.name || ("Station " + (i + 1)),
                latitude: Number(st.latitude) || 0.0,
                longitude: Number(st.longitude) || 0.0,
                altitude: Number(st.altitude) || 0.0,
                altitudeSpecified: st.altitudeSpecified !== false,
                mobility: st.mobility || "Stationary",
                minElevation: Number(st.minElevation) || 5.0,
                operatingBand: st.operatingBand || "C-band",
                polarization: st.polarization || "RHCP",
                antennaGain: Number(st.antennaGain) || 38.5,
                lnaNf: Number(st.lnaNf) || 0.70,
                feederLoss: Number(st.feederLoss) || 0.30,
                freqMinMhz: Number(st.freqMinMhz) || 4000.0,
                freqMaxMhz: Number(st.freqMaxMhz) || 8000.0,
                maxChannelWidthMhz: Number(st.maxChannelWidthMhz) || 4000.0,
                totalNoiseFigureDb: Number(st.totalNoiseFigureDb) || 1.0,
                systemNoiseTempK: Number(st.systemNoiseTempK) || 125.1,
                gOverT: Number(st.gOverT) || 17.53
            })
        }
        stationManager.saveStationsToDisk(list)
    }

    // --- Satellite Edit & Delete ---
    function startEditSatellite(sat) {
        window.editingSatId = sat.satId
        window.showAddSatForm = true
        window.showAddStationForm = false

        satNameInput.text = sat.name
        tle1Input.text = sat.tle1 || ""
        tle2Input.text = sat.tle2 || ""

        window.selectSatellite(sat.satId, sat.latitude, sat.longitude, sat.altitudeKm, sat.name)
    }

    function deleteSatellite(satId) {
        for (var i = 0; i < satellitesModel.count; i++) {
            if (satellitesModel.get(i).satId === satId) {
                satellitesModel.remove(i)
                break
            }
        }
        if (window.selectedSatelliteId === satId) {
            window.selectedSatelliteId = ""
            if (satellitesModel.count > 0) {
                var first = satellitesModel.get(0)
                window.selectSatellite(first.satId, first.latitude, first.longitude, first.altitudeKm, first.name)
            } else {
                window.currentSatAltKm = 500.0
                window.currentSatName = "Default LEO (500 km)"
            }
        }
        if (window.editingSatId === satId) {
            resetSatFormFields()
        }
        mapComponent.requestCanvasRedraw()
    }

    function resetStationFormFields() {
        window.editingStationId = ""
        mapComponent.removeDraftMarker()
        window.pickOnMapActive = false
        mapComponent.pickModeEnabled = false
        window.showAddStationForm = false
    }

    function resetSatFormFields() {
        window.editingSatId = ""
        satNameInput.text = ""
        tle1Input.text = ""
        tle2Input.text = ""
        window.showAddSatForm = false
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ================= LEFT SIDEBAR (Creation & Edit Panels) =================
        Rectangle {
            id: leftPanel
            Layout.fillHeight: true
            Layout.preferredWidth: 350
            color: window.lightMode ? window.panelLight : window.panelDark

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    anchors.margins: 16
                    spacing: 14

                    Label {
                        text: qsTr("SatComHub")
                        font.bold: true
                        font.pixelSize: 22
                        color: window.lightMode ? window.textLight : window.textDark
                    }

                    Label {
                        text: qsTr("Satellite & Ground Station Monitor")
                        font.pixelSize: 13
                        color: window.lightMode ? window.subTextLight : window.subTextDark
                    }

                    // Live Status & UTC Clock
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: "#40c057"
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.3; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }

                        Label {
                            text: window.currentUtcString
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                            color: window.lightMode ? "#2b8a3e" : "#51cf66"
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: window.lightMode ? window.borderLight : window.borderDark
                    }

                    // --- BUTTON 1: Add New Ground Station ---
                    Button {
                        id: addStationBtn
                        Layout.fillWidth: true
                        height: 38
                        text: qsTr("📡  Add new station")

                        background: Rectangle {
                            radius: 8
                            color: addStationBtn.hovered ? "#1c7ed6" : window.accentColor
                        }

                        contentItem: Text {
                            text: addStationBtn.text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            stationDialog.openForCreate()
                        }
                    }

                    // --- BUTTON 2: Add New Satellite (TLE) ---
                    Button {
                        id: toggleAddSatBtn
                        Layout.fillWidth: true
                        height: 38
                        text: window.showAddSatForm
                              ? (window.editingSatId !== "" ? qsTr("✕  Cancel Editing Satellite") : qsTr("✕  Cancel Satellite"))
                              : qsTr("🛰️  Add new satellite (TLE)")

                        background: Rectangle {
                            radius: 8
                            color: window.showAddSatForm ? "#e03131" : window.satColor
                        }

                        contentItem: Text {
                            text: toggleAddSatBtn.text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            if (window.showAddSatForm) {
                                window.resetSatFormFields()
                            } else {
                                window.editingSatId = ""
                                window.showAddSatForm = true
                                window.showAddStationForm = false
                                window.resetStationFormFields()
                            }
                        }
                    }

                    // ================= FORM 1: SATELLITE (CREATE / EDIT) =================
                    Rectangle {
                        id: addSatBlock
                        visible: window.showAddSatForm
                        Layout.fillWidth: true
                        implicitHeight: satFormLayout.implicitHeight + 28
                        radius: 10
                        color: window.lightMode ? window.cardLight : window.cardDark
                        border.color: window.satColor
                        border.width: 1

                        ColumnLayout {
                            id: satFormLayout
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label {
                                text: window.editingSatId !== "" ? qsTr("✏️ Edit Satellite (" + window.editingSatId + ")") : qsTr("Satellite TLE Configuration")
                                font.bold: true
                                font.pixelSize: 14
                                color: window.satColor
                            }

                            Label {
                                text: qsTr("Satellite Name")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: satNameInput
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("e.g. ISS (ZARYA)")
                                color: window.lightMode ? window.textLight : window.textDark
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: satNameInput.activeFocus ? window.satColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                            }

                            Label {
                                text: qsTr("TLE Line 1")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: tle1Input
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("1 25544U 98067A ...")
                                font.family: "Courier New, monospace"
                                font.pixelSize: 11
                                color: window.lightMode ? window.textLight : window.textDark
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: tle1Input.activeFocus ? window.satColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                            }

                            Label {
                                text: qsTr("TLE Line 2")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: tle2Input
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("2 25544 51.64 ...")
                                font.family: "Courier New, monospace"
                                font.pixelSize: 11
                                color: window.lightMode ? window.textLight : window.textDark
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: tle2Input.activeFocus ? window.satColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                            }

                            Button {
                                text: qsTr("Paste Live Sample (ISS)")
                                Layout.fillWidth: true
                                height: 30
                                onClicked: {
                                    satNameInput.text = "ISS (ZARYA)"
                                    tle1Input.text = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
                                    tle2Input.text = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
                                }
                            }

                            Button {
                                id: saveSatBtn
                                Layout.fillWidth: true
                                height: 38
                                text: window.editingSatId !== "" ? qsTr("💾  Update Satellite") : qsTr("Calculate Orbit & Place Satellite")
                                enabled: satNameInput.text.trim().length > 0 && tle1Input.text.trim().length >= 60 && tle2Input.text.trim().length >= 60

                                background: Rectangle {
                                    radius: 6
                                    color: saveSatBtn.enabled ? "#2f9e44" : (window.lightMode ? "#ced4da" : "#495057")
                                }

                                contentItem: Text {
                                    text: saveSatBtn.text
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

                                    var prop = propagator.propagateTle(l1, l2, 0.0)
                                    if (prop.valid) {
                                        var tracks = propagator.computeOrbitTracks(l1, l2, 0.75)

                                        if (window.editingSatId !== "") {
                                            // Update existing satellite
                                            for (var s = 0; s < satellitesModel.count; s++) {
                                                if (satellitesModel.get(s).satId === window.editingSatId) {
                                                    satellitesModel.setProperty(s, "name", name)
                                                    satellitesModel.setProperty(s, "tle1", l1)
                                                    satellitesModel.setProperty(s, "tle2", l2)
                                                    satellitesModel.setProperty(s, "latitude", prop.latitude)
                                                    satellitesModel.setProperty(s, "longitude", prop.longitude)
                                                    satellitesModel.setProperty(s, "altitudeKm", prop.altitudeKm)
                                                    satellitesModel.setProperty(s, "visibilityRadiusMeters", prop.visibilityRadiusMeters)
                                                    satellitesModel.setProperty(s, "velocityKmS", prop.velocityKmS || 0)
                                                    satellitesModel.setProperty(s, "trajectory", tracks.current || [])
                                                    satellitesModel.setProperty(s, "prevTrajectory", tracks.previous || [])
                                                    satellitesModel.setProperty(s, "nextTrajectory", tracks.next || [])
                                                    break
                                                }
                                            }
                                            window.selectSatellite(window.editingSatId, prop.latitude, prop.longitude, prop.altitudeKm, name)
                                        } else {
                                            // Add new satellite
                                            var satId = "SAT-" + (satellitesModel.count + 1)
                                            satellitesModel.append({
                                                satId: satId,
                                                name: name,
                                                tle1: l1,
                                                tle2: l2,
                                                latitude: prop.latitude,
                                                longitude: prop.longitude,
                                                altitudeKm: prop.altitudeKm,
                                                visibilityRadiusMeters: prop.visibilityRadiusMeters,
                                                velocityKmS: prop.velocityKmS || 0,
                                                trajectory: tracks.current || [],
                                                prevTrajectory: tracks.previous || [],
                                                nextTrajectory: tracks.next || []
                                            })
                                            window.selectSatellite(satId, prop.latitude, prop.longitude, prop.altitudeKm, name)
                                        }

                                        mapComponent.focusOnCoordinate(prop.latitude, prop.longitude)
                                        mapComponent.requestCanvasRedraw()
                                        window.resetSatFormFields()
                                    }
                                }
                            }
                        }
                    }



                    Item { Layout.fillHeight: true }

                    Button {
                        Layout.fillWidth: true
                        height: 40
                        text: window.lightMode ? qsTr("🌙  Dark Theme") : qsTr("☀️  Light Theme")
                        onClicked: window.lightMode = !window.lightMode
                    }
                }
            }
        }

        // ================= CENTER MAP VIEW =================
        MapComponent {
            id: mapComponent
            Layout.fillWidth: true
            Layout.fillHeight: true
            stationsModel: stationsModel
            satellitesModel: satellitesModel
            selectedStationId: window.selectedStationId
            selectedSatelliteId: window.selectedSatelliteId
            targetSatelliteAltitudeKm: window.currentSatAltKm

            onMarkerSelected: (id, name) => {
                window.selectedStationId = id
                window.selectedSatelliteId = ""
            }

            onSatelliteSelected: (id, name) => {
                window.selectedSatelliteId = id
                window.selectedStationId = ""
            }

            onCoordinatePicked: (lat, lon) => {
                window.pickOnMapActive = false
                mapComponent.pickModeEnabled = false
                mapComponent.focusOnCoordinate(lat, lon)
                stationDialog.setCoordinates(lat, lon)
                stationDialog.open()
            }
        }

        // ================= RIGHT PANEL (List of Satellites & Stations) =================
        Rectangle {
            id: rightPanel
            Layout.fillHeight: true
            Layout.preferredWidth: 350
            color: window.lightMode ? window.panelLight : window.panelDark

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                // --- SATELLITES HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Tracked Satellites")
                        font.bold: true
                        font.pixelSize: 16
                        color: window.satColor
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: satCountText.implicitWidth + 14
                        height: 22
                        radius: 11
                        color: window.satColor
                        Text {
                            id: satCountText
                            anchors.centerIn: parent
                            text: String(satellitesModel.count)
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }
                }

                ListView {
                    id: satellitesListView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 200)
                    clip: true
                    spacing: 6
                    model: satellitesModel

                    delegate: Rectangle {
                        width: satellitesListView.width
                        implicitHeight: satCardContent.implicitHeight + 16
                        radius: 8

                        property bool isSelected: window.selectedSatelliteId === model.satId

                        color: isSelected ? (window.lightMode ? "#fff3bf" : "#372c15") : (window.lightMode ? window.cardLight : window.cardDark)
                        border.color: isSelected ? window.satColor : (window.lightMode ? window.borderLight : window.borderDark)
                        border.width: isSelected ? 2 : 1

                        RowLayout {
                            id: satCardContent
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Text {
                                text: "🛰️"
                                font.pixelSize: 18
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: model.name
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: isSelected ? window.satColor : (window.lightMode ? window.textLight : window.textDark)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    property string latDir: model.latitude >= 0 ? "°N" : "°S"
                                    property string lonDir: model.longitude >= 0 ? "°E" : "°W"
                                    text: Math.abs(model.latitude).toFixed(2) + latDir + ", " + Math.abs(model.longitude).toFixed(2) + lonDir
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: "monospace"
                                    color: isSelected ? window.satColor : (window.lightMode ? "#1971c2" : "#4dabf7")
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: "Alt: " + Math.round(model.altitudeKm) + " km • Range: " + Math.round(model.visibilityRadiusMeters / 1000) + " km" + (model.velocityKmS ? " • " + model.velocityKmS.toFixed(2) + " km/s" : "")
                                    font.pixelSize: 10
                                    color: window.lightMode ? window.subTextLight : window.subTextDark
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // Quick Edit Button
                            Button {
                                width: 28
                                height: 28
                                text: "✏️"
                                background: Rectangle {
                                    radius: 4
                                    color: window.lightMode ? "#e9ecef" : "#373a40"
                                }
                                onClicked: window.startEditSatellite(model)
                            }

                            // Quick Delete Button
                            Button {
                                width: 28
                                height: 28
                                text: "🗑️"
                                background: Rectangle {
                                    radius: 4
                                    color: "#fa5252"
                                }
                                contentItem: Text {
                                    text: "🗑️"
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                onClicked: window.deleteSatellite(model.satId)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: window.selectSatellite(model.satId, model.latitude, model.longitude, model.altitudeKm, model.name)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: window.lightMode ? window.borderLight : window.borderDark
                }

                // --- GROUND STATIONS HEADER ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: qsTr("Ground Stations")
                        font.bold: true
                        font.pixelSize: 16
                        color: window.lightMode ? window.textLight : window.textDark
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: badgeCountText.implicitWidth + 14
                        height: 22
                        radius: 11
                        color: window.accentColor
                        Text {
                            id: badgeCountText
                            anchors.centerIn: parent
                            text: String(stationsModel.count)
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                        }
                    }
                    Button {
                        id: openStationsFolderBtn
                        width: 28
                        height: 24
                        flat: true
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Open local stations folder in Explorer")
                        ToolTip.delay: 300
                        background: Rectangle {
                            radius: 4
                            color: openStationsFolderBtn.hovered ? (window.lightMode ? "#dee2e6" : "#373a40") : "transparent"
                        }
                        contentItem: Text {
                            text: "📁"
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: stationManager.openStationsFolder()
                    }
                }

                ListView {
                    id: stationsListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: stationsModel

                    delegate: Rectangle {
                        id: stationCard
                        width: stationsListView.width
                        implicitHeight: cardContent.implicitHeight + 16
                        radius: 8

                        property bool isSelected: window.selectedStationId === model.stationId

                        color: isSelected
                               ? (window.lightMode ? "#e7f5ff" : "#182842")
                               : (window.lightMode ? window.cardLight : window.cardDark)

                        border.color: isSelected ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                        border.width: isSelected ? 2 : 1

                        RowLayout {
                            id: cardContent
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: stationCard.isSelected ? window.accentColor : (window.lightMode ? "#dee2e6" : "#373a40")

                                Text {
                                    anchors.centerIn: parent
                                    text: "📡"
                                    font.pixelSize: 15
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3

                                Label {
                                    text: model.name
                                    font.bold: true
                                    font.pixelSize: 13
                                    color: stationCard.isSelected
                                           ? window.accentColor
                                           : (window.lightMode ? window.textLight : window.textDark)
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    spacing: 4
                                    Rectangle {
                                        height: 16
                                        width: bandBadgeText.implicitWidth + 8
                                        radius: 3
                                        color: window.lightMode ? "#e7f5ff" : "#182842"
                                        border.color: window.accentColor
                                        border.width: 1
                                        Text {
                                            id: bandBadgeText
                                            anchors.centerIn: parent
                                            text: model.operatingBand ? model.operatingBand : "C-band"
                                            font.pixelSize: 9
                                            font.bold: true
                                            color: window.accentColor
                                        }
                                    }

                                    Rectangle {
                                        height: 16
                                        width: polBadgeText.implicitWidth + 8
                                        radius: 3
                                        color: window.lightMode ? "#f8f9fa" : "#2c2e33"
                                        Text {
                                            id: polBadgeText
                                            anchors.centerIn: parent
                                            text: model.polarization ? model.polarization : "RHCP"
                                            font.pixelSize: 9
                                            color: window.lightMode ? "#495057" : "#adb5bd"
                                        }
                                    }

                                    Label {
                                        text: (model.gOverT !== undefined ? ("G/T: " + Number(model.gOverT).toFixed(1) + " dB/K") : "")
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: "#40c057"
                                        visible: model.gOverT !== undefined
                                    }
                                }

                                Label {
                                    text: model.stationId + " • " + (model.minElevation !== undefined ? model.minElevation : 5) + "° Mask: " + Math.round(mapComponent.calculateStationSatVisibilityRadius(window.currentSatAltKm, (model.minElevation !== undefined ? model.minElevation : 5)) / 1000) + " km"
                                    font.pixelSize: 11
                                    color: stationCard.isSelected ? window.accentColor : (window.lightMode ? window.subTextLight : window.subTextDark)
                                    font.bold: stationCard.isSelected
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: Number(model.latitude).toFixed(3) + "°, " + Number(model.longitude).toFixed(3) + "°" + (model.systemNoiseTempK ? (" • Tsys: " + Number(model.systemNoiseTempK).toFixed(0) + " K") : "")
                                    font.pixelSize: 11
                                    color: window.lightMode ? window.subTextLight : window.subTextDark
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            // View JSON Document Button
                            Button {
                                width: 28
                                height: 28
                                background: Rectangle {
                                    radius: 4
                                    color: window.lightMode ? "#e9ecef" : "#373a40"
                                }
                                contentItem: Text {
                                    text: "{ }"
                                    color: window.accentColor
                                    font.bold: true
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("View Station JSON Document")
                                onClicked: {
                                    var json = model.stationJson
                                    if (!json || json.length === 0) {
                                        json = stationManager.buildStationJson(model)
                                    }
                                    stationDetailsViewer.stationName = model.name + " (" + model.stationId + ")"
                                    stationDetailsViewer.jsonContent = json
                                    stationDetailsViewer.open()
                                }
                            }

                            // Quick Edit Button
                            Button {
                                width: 28
                                height: 28
                                text: "✏️"
                                background: Rectangle {
                                    radius: 4
                                    color: window.lightMode ? "#e9ecef" : "#373a40"
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Edit Ground Station")
                                onClicked: window.startEditStation(model)
                            }

                            // Quick Delete Button
                            Button {
                                width: 28
                                height: 28
                                text: "🗑️"
                                background: Rectangle {
                                    radius: 4
                                    color: "#fa5252"
                                }
                                contentItem: Text {
                                    text: "🗑️"
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("Delete Ground Station")
                                onClicked: window.deleteStation(model.stationId)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            z: -1
                            onClicked: {
                                window.selectStation(model.stationId, model.latitude, model.longitude)
                            }
                        }
                    }
                }
            }
        }
    }

    function updateMarkerPreview() {
        if (window.isResettingForm) return

        var lat = parseFloat(latInput.text)
        var lon = parseFloat(lonInput.text)
        var alt = parseFloat(altInput.text) || 0
        var name = stationNameInput.text.trim()
        if (!isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
            mapComponent.setDraftMarker(lat, lon, alt, name || (window.editingStationId !== "" ? name : qsTr("New Station (Unsaved)")))
            mapComponent.focusOnCoordinate(lat, lon)
        } else {
            mapComponent.removeDraftMarker()
        }
    }

    Component.onCompleted: {
        // Load persisted ground stations if available
        var saved = stationManager.loadStationsFromDisk()
        if (saved && saved.length > 0) {
            for (var s = 0; s < saved.length; s++) {
                stationsModel.append(saved[s])
            }
        } else {
            // Initial Ground Stations with rich RF configurations & band presets
            var sampleStations = [
                {
                    stationId: "GS-01",
                    name: "Warsaw Primary Hub",
                    latitude: 52.2297,
                    longitude: 21.0122,
                    altitude: 220.0,
                    altitudeSpecified: true,
                    mobility: "Stationary",
                    minElevation: 5.0,
                    operatingBand: "C-band",
                    polarization: "RHCP",
                    antennaGain: 38.5,
                    lnaNf: 0.70,
                    feederLoss: 0.30,
                    freqMinMhz: 4000.0,
                    freqMaxMhz: 8000.0,
                    maxChannelWidthMhz: 4000.0,
                    totalNoiseFigureDb: 1.0,
                    systemNoiseTempK: 125.1,
                    gOverT: 17.53
                },
                {
                    stationId: "GS-02",
                    name: "Gdansk Coastal Relay",
                    latitude: 54.3520,
                    longitude: 18.6466,
                    altitude: 110.0,
                    altitudeSpecified: true,
                    mobility: "Stationary",
                    minElevation: 5.0,
                    operatingBand: "S-band",
                    polarization: "LHCP",
                    antennaGain: 30.0,
                    lnaNf: 0.85,
                    feederLoss: 0.25,
                    freqMinMhz: 2000.0,
                    freqMaxMhz: 4000.0,
                    maxChannelWidthMhz: 2000.0,
                    totalNoiseFigureDb: 1.1,
                    systemNoiseTempK: 133.6,
                    gOverT: 8.74
                },
                {
                    stationId: "GS-03",
                    name: "Krakow Southern Node",
                    latitude: 50.0647,
                    longitude: 19.9450,
                    altitude: 380.0,
                    altitudeSpecified: true,
                    mobility: "Stationary",
                    minElevation: 5.0,
                    operatingBand: "Ku-band",
                    polarization: "Linear",
                    antennaGain: 48.0,
                    lnaNf: 0.90,
                    feederLoss: 0.40,
                    freqMinMhz: 12000.0,
                    freqMaxMhz: 18000.0,
                    maxChannelWidthMhz: 6000.0,
                    totalNoiseFigureDb: 1.3,
                    systemNoiseTempK: 151.2,
                    gOverT: 26.21
                },
                {
                    stationId: "GS-04",
                    name: "Wroclaw West Link",
                    latitude: 51.1079,
                    longitude: 17.0385,
                    altitude: 175.0,
                    altitudeSpecified: true,
                    mobility: "Stationary",
                    minElevation: 5.0,
                    operatingBand: "X-band",
                    polarization: "RHCP",
                    antennaGain: 43.5,
                    lnaNf: 0.75,
                    feederLoss: 0.35,
                    freqMinMhz: 8000.0,
                    freqMaxMhz: 12000.0,
                    maxChannelWidthMhz: 4000.0,
                    totalNoiseFigureDb: 1.1,
                    systemNoiseTempK: 133.6,
                    gOverT: 22.24
                }
            ]
            for (var k = 0; k < sampleStations.length; k++) {
                sampleStations[k]["stationJson"] = stationManager.buildStationJson(sampleStations[k])
                stationsModel.append(sampleStations[k])
            }
            window.syncStationsToDisk()
        }

        // Initial Sample Satellite (ISS) - Live NORAD TLE Elements
        var issL1 = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
        var issL2 = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
        var prop = propagator.propagateTle(issL1, issL2, 0.0)
        if (prop.valid) {
            var tracks = propagator.computeOrbitTracks(issL1, issL2, 0.75)
            satellitesModel.append({
                satId: "SAT-01",
                name: "ISS (ZARYA)",
                tle1: issL1,
                tle2: issL2,
                latitude: prop.latitude,
                longitude: prop.longitude,
                altitudeKm: prop.altitudeKm,
                visibilityRadiusMeters: prop.visibilityRadiusMeters,
                velocityKmS: prop.velocityKmS || 0,
                trajectory: tracks.current || [],
                prevTrajectory: tracks.previous || [],
                nextTrajectory: tracks.next || []
            })
            window.currentSatAltKm = prop.altitudeKm
            window.currentSatName = "ISS (ZARYA)"
            window.selectedSatelliteId = "SAT-01"
            mapComponent.focusOnCoordinate(prop.latitude, prop.longitude)
        }
    }
}
