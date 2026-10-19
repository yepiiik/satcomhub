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
        window.editingStationId = station.stationId
        window.showAddStationForm = true
        window.showAddSatForm = false

        stationNameInput.text = station.name
        latInput.text = String(station.latitude)
        lonInput.text = String(station.longitude)
        altInput.text = String(station.altitude)
        elevationInput.text = String(station.minElevation !== undefined ? station.minElevation : 5)

        window.selectedStationId = station.stationId
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
        if (window.editingStationId === stationId) {
            resetStationFormFields()
        }
        mapComponent.requestCanvasRedraw()
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
        window.isResettingForm = true
        window.editingStationId = ""
        mapComponent.removeDraftMarker()
        stationNameInput.text = ""
        latInput.text = ""
        lonInput.text = ""
        altInput.text = "150"
        elevationInput.text = "5"
        window.pickOnMapActive = false
        mapComponent.pickModeEnabled = false
        window.showAddStationForm = false
        window.isResettingForm = false
    }

    function resetSatFormFields() {
        window.editingSatId = ""
        satNameInput.text = ""
        tle1Input.text = ""
        tle2Input.text = ""
        window.showAddSatForm = false
    }

    function toggleStationActive(stationId) {
        for (var i = 0; i < stationsModel.count; i++) {
            if (stationsModel.get(i).stationId === stationId) {
                var cur = stationsModel.get(i).active !== false
                stationsModel.setProperty(i, "active", !cur)
                mapComponent.requestCanvasRedraw()
                break
            }
        }
    }

    function setAllStationsActive(activeState) {
        for (var i = 0; i < stationsModel.count; i++) {
            stationsModel.setProperty(i, "active", activeState)
        }
        mapComponent.requestCanvasRedraw()
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
                        id: toggleAddStationBtn
                        Layout.fillWidth: true
                        height: 38
                        text: window.showAddStationForm
                              ? (window.editingStationId !== "" ? qsTr("✕  Cancel Editing Station") : qsTr("✕  Cancel Ground Station"))
                              : qsTr("📡  Add new station")

                        background: Rectangle {
                            radius: 8
                            color: window.showAddStationForm ? "#e03131" : window.accentColor
                        }

                        contentItem: Text {
                            text: toggleAddStationBtn.text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            if (window.showAddStationForm) {
                                window.resetStationFormFields()
                            } else {
                                window.editingStationId = ""
                                window.showAddStationForm = true
                                window.showAddSatForm = false
                            }
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

                    // ================= FORM 2: GROUND STATION (CREATE / EDIT) =================
                    Rectangle {
                        id: addStationBlock
                        visible: window.showAddStationForm
                        Layout.fillWidth: true
                        implicitHeight: formLayout.implicitHeight + 28
                        radius: 10
                        color: window.lightMode ? window.cardLight : window.cardDark
                        border.color: window.lightMode ? window.borderLight : window.borderDark
                        border.width: 1

                        ColumnLayout {
                            id: formLayout
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            Label {
                                text: window.editingStationId !== "" ? qsTr("✏️ Edit Ground Station (" + window.editingStationId + ")") : qsTr("New Station Details")
                                font.bold: true
                                font.pixelSize: 14
                                color: window.accentColor
                            }

                            Label {
                                text: qsTr("Station Name")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: stationNameInput
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("e.g. Warsaw Relay Station")
                                color: window.lightMode ? window.textLight : window.textDark
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: stationNameInput.activeFocus ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                                onTextChanged: window.updateMarkerPreview()
                            }

                            Label {
                                text: qsTr("Latitude")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: latInput
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("e.g. 52.2297")
                                color: window.lightMode ? window.textLight : window.textDark
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: latInput.activeFocus ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                                onTextChanged: window.updateMarkerPreview()
                            }

                            Label {
                                text: qsTr("Longitude")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: lonInput
                                Layout.fillWidth: true
                                height: 36
                                placeholderText: qsTr("e.g. 21.0122")
                                color: window.lightMode ? window.textLight : window.textDark
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: lonInput.activeFocus ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                                onTextChanged: window.updateMarkerPreview()
                            }

                            Label {
                                text: qsTr("Altitude / Antenna Elevation (meters)")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: altInput
                                Layout.fillWidth: true
                                height: 36
                                text: "150"
                                placeholderText: qsTr("e.g. 150")
                                color: window.lightMode ? window.textLight : window.textDark
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: altInput.activeFocus ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                                onTextChanged: window.updateMarkerPreview()
                            }

                            Label {
                                text: qsTr("Min Elevation Mask (degrees, e.g. 5° or 10°)")
                                font.pixelSize: 12
                                color: window.lightMode ? window.textLight : window.textDark
                            }
                            TextField {
                                id: elevationInput
                                Layout.fillWidth: true
                                height: 36
                                text: "5"
                                placeholderText: qsTr("e.g. 5")
                                color: window.lightMode ? window.textLight : window.textDark
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                background: Rectangle {
                                    radius: 6
                                    color: window.lightMode ? "#ffffff" : "#1a1b1e"
                                    border.color: elevationInput.activeFocus ? window.accentColor : (window.lightMode ? window.borderLight : window.borderDark)
                                }
                                onTextChanged: window.updateMarkerPreview()
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 28
                                radius: 4
                                color: window.lightMode ? "#e7f5ff" : "#182842"
                                Text {
                                    anchors.centerIn: parent
                                    text: "Usable Pass Range for " + window.currentSatName + " (" + (parseFloat(elevationInput.text) || 5) + "° mask): " + Math.round(mapComponent.calculateStationSatVisibilityRadius(window.currentSatAltKm, (parseFloat(elevationInput.text) || 5)) / 1000) + " km"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: window.accentColor
                                }
                            }

                            Button {
                                id: pickBtn
                                Layout.fillWidth: true
                                height: 36
                                text: window.pickOnMapActive ? qsTr("📍 Click map to pick...") : qsTr("🗺️ Select from map")

                                background: Rectangle {
                                    radius: 6
                                    color: window.pickOnMapActive ? "#1c7ed6" : (window.lightMode ? "#e9ecef" : "#373a40")
                                    border.color: window.pickOnMapActive ? "#74c0fc" : "transparent"
                                }

                                contentItem: Text {
                                    text: pickBtn.text
                                    color: window.pickOnMapActive ? "#ffffff" : (window.lightMode ? window.textLight : window.textDark)
                                    font.bold: true
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    window.pickOnMapActive = !window.pickOnMapActive
                                    mapComponent.pickModeEnabled = window.pickOnMapActive
                                }
                            }

                            Button {
                                id: submitBtn
                                Layout.fillWidth: true
                                height: 38
                                text: window.editingStationId !== "" ? qsTr("💾  Update Station") : qsTr("Save & Place Station")
                                enabled: stationNameInput.text.trim().length > 0 &&
                                         !isNaN(parseFloat(latInput.text)) &&
                                         !isNaN(parseFloat(lonInput.text))

                                background: Rectangle {
                                    radius: 6
                                    color: submitBtn.enabled ? "#2f9e44" : (window.lightMode ? "#ced4da" : "#495057")
                                }

                                contentItem: Text {
                                    text: submitBtn.text
                                    color: "#ffffff"
                                    font.bold: true
                                    font.pixelSize: 13
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    var name = stationNameInput.text.trim()
                                    var lat = parseFloat(latInput.text)
                                    var lon = parseFloat(lonInput.text)
                                    var alt = parseFloat(altInput.text) || 0
                                    var elMask = parseFloat(elevationInput.text) || 5.0

                                    mapComponent.removeDraftMarker()

                                    if (window.editingStationId !== "") {
                                        // Update existing station
                                        for (var st = 0; st < stationsModel.count; st++) {
                                            if (stationsModel.get(st).stationId === window.editingStationId) {
                                                stationsModel.setProperty(st, "name", name)
                                                stationsModel.setProperty(st, "latitude", lat)
                                                stationsModel.setProperty(st, "longitude", lon)
                                                stationsModel.setProperty(st, "altitude", alt)
                                                stationsModel.setProperty(st, "minElevation", elMask)
                                                break
                                            }
                                        }
                                        window.selectedStationId = window.editingStationId
                                    } else {
                                        // Add new station
                                        var newId = "GS-0" + (stationsModel.count + 1)
                                        stationsModel.append({
                                            stationId: newId,
                                            name: name,
                                            latitude: lat,
                                            longitude: lon,
                                            altitude: alt,
                                            minElevation: elMask,
                                            active: true
                                        })
                                        window.selectedStationId = newId
                                    }

                                    mapComponent.focusOnCoordinate(lat, lon)
                                    mapComponent.requestCanvasRedraw()
                                    window.resetStationFormFields()
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
                latInput.text = lat.toFixed(5)
                lonInput.text = lon.toFixed(5)
                window.pickOnMapActive = false
                mapComponent.pickModeEnabled = false

                mapComponent.focusOnCoordinate(lat, lon)
            }
        }

        // ================= RIGHT PANEL (List of Satellites & Stations / Pass Windows F5) =================
        Rectangle {
            id: rightPanel
            Layout.fillHeight: true
            Layout.preferredWidth: 380
            color: window.lightMode ? window.panelLight : window.panelDark

            property int currentTab: 0 // 0 = Fleet & Stations, 1 = Pass Windows (F5)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Top View Switcher (Tabs)
                Rectangle {
                    Layout.fillWidth: true
                    height: 38
                    radius: 8
                    color: window.lightMode ? "#e9ecef" : "#1a1b1e"
                    border.color: window.lightMode ? "#dee2e6" : "#2c2e33"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 4

                        Button {
                            id: tabFleetBtn
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: qsTr("🛰️ Network Fleet")
                            background: Rectangle {
                                radius: 6
                                color: rightPanel.currentTab === 0
                                       ? (window.lightMode ? "#ffffff" : "#25262b")
                                       : "transparent"
                                border.color: rightPanel.currentTab === 0
                                              ? (window.lightMode ? "#ced4da" : "#373a40")
                                              : "transparent"
                            }
                            contentItem: Text {
                                text: tabFleetBtn.text
                                color: rightPanel.currentTab === 0
                                       ? (window.lightMode ? window.textLight : "#ffffff")
                                       : (window.lightMode ? window.subTextLight : window.subTextDark)
                                font.bold: rightPanel.currentTab === 0
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: rightPanel.currentTab = 0
                        }

                        Button {
                            id: tabPassesBtn
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: qsTr("📅 Pass Windows (F5)")
                            background: Rectangle {
                                radius: 6
                                color: rightPanel.currentTab === 1
                                       ? (window.lightMode ? "#ffffff" : "#25262b")
                                       : "transparent"
                                border.color: rightPanel.currentTab === 1
                                              ? (window.lightMode ? "#ced4da" : "#373a40")
                                              : "transparent"
                            }
                            contentItem: Text {
                                text: tabPassesBtn.text
                                color: rightPanel.currentTab === 1
                                       ? (window.lightMode ? "#1971c2" : "#4dabf7")
                                       : (window.lightMode ? window.subTextLight : window.subTextDark)
                                font.bold: rightPanel.currentTab === 1
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: rightPanel.currentTab = 1
                        }
                    }
                }

                // --- TAB 0: Fleet & Stations ---
                ColumnLayout {
                    id: fleetViewCol
                    visible: rightPanel.currentTab === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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

                                // Quick Calculate Pass Windows Button (F5)
                                Button {
                                    width: 28
                                    height: 28
                                    text: "📅"
                                    background: Rectangle {
                                        radius: 4
                                        color: window.lightMode ? "#e7f5ff" : "#182842"
                                    }
                                    ToolTip.visible: hovered
                                    ToolTip.text: qsTr("Calculate Pass Windows (F5)")
                                    onClicked: {
                                        window.selectSatellite(model.satId, model.latitude, model.longitude, model.altitudeKm, model.name)
                                        rightPanel.currentTab = 1
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
                        spacing: 6

                        Label {
                            text: qsTr("Ground Stations")
                            font.bold: true
                            font.pixelSize: 16
                            color: window.lightMode ? window.textLight : window.textDark
                            Layout.fillWidth: true
                        }

                        // Active status badge
                        Rectangle {
                            property int activeCount: {
                                var c = 0
                                for (var i = 0; i < stationsModel.count; i++) {
                                    if (stationsModel.get(i).active !== false) c++
                                }
                                return c
                            }
                            width: activeCountText.implicitWidth + 14
                            height: 22
                            radius: 11
                            color: activeCount > 0 ? "#2b8a3e" : "#868e96"
                            Text {
                                id: activeCountText
                                anchors.centerIn: parent
                                text: parent.activeCount + "/" + stationsModel.count + " Active"
                                color: "#ffffff"
                                font.bold: true
                                font.pixelSize: 10
                            }
                        }

                        // Quick Toggle All
                        Button {
                            height: 22
                            implicitWidth: 32
                            text: qsTr("All")
                            background: Rectangle {
                                radius: 4
                                color: window.lightMode ? "#e9ecef" : "#373a40"
                            }
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 10
                                font.bold: true
                                color: window.lightMode ? "#1971c2" : "#74c0fc"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: window.setAllStationsActive(true)
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Set all stations as Active")
                        }

                        Button {
                            height: 22
                            implicitWidth: 38
                            text: qsTr("None")
                            background: Rectangle {
                                radius: 4
                                color: window.lightMode ? "#e9ecef" : "#373a40"
                            }
                            contentItem: Text {
                                text: parent.text
                                font.pixelSize: 10
                                font.bold: true
                                color: window.lightMode ? "#868e96" : "#adb5bd"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: window.setAllStationsActive(false)
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Set all stations as Passive")
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
                            property bool isActive: model.active !== false

                            opacity: isActive ? 1.0 : 0.68

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
                                    color: stationCard.isSelected
                                           ? window.accentColor
                                           : (stationCard.isActive ? (window.lightMode ? "#dee2e6" : "#373a40") : (window.lightMode ? "#e9ecef" : "#2c2e33"))

                                    Text {
                                        anchors.centerIn: parent
                                        text: "📡"
                                        font.pixelSize: 15
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

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

                                        // Active / Passive Toggle Pill
                                        Button {
                                            id: stActiveBtn
                                            property bool isStActive: model.active !== false
                                            height: 22
                                            implicitWidth: togglePillText.implicitWidth + 14
                                            background: Rectangle {
                                                radius: 11
                                                color: stActiveBtn.isStActive
                                                       ? (window.lightMode ? "#d3f9d8" : "#143a1e")
                                                       : (window.lightMode ? "#f1f3f5" : "#1a1b1e")
                                                border.color: stActiveBtn.isStActive ? "#40c057" : (window.lightMode ? "#ced4da" : "#373a40")
                                                border.width: 1
                                            }
                                            contentItem: RowLayout {
                                                spacing: 3
                                                anchors.centerIn: parent
                                                Text {
                                                    text: stActiveBtn.isStActive ? "🟢" : "⚪"
                                                    font.pixelSize: 7
                                                }
                                                Text {
                                                    id: togglePillText
                                                    text: stActiveBtn.isStActive ? qsTr("Active") : qsTr("Passive")
                                                    font.bold: true
                                                    font.pixelSize: 10
                                                    color: stActiveBtn.isStActive
                                                           ? (window.lightMode ? "#2b8a3e" : "#51cf66")
                                                           : (window.lightMode ? "#868e96" : "#adb5bd")
                                                }
                                            }
                                            ToolTip.visible: hovered
                                            ToolTip.text: stActiveBtn.isStActive
                                                          ? qsTr("Active for session calculation. Click to make Passive.")
                                                          : qsTr("Passive (excluded). Click to make Active.")
                                            onClicked: {
                                                window.toggleStationActive(model.stationId)
                                            }
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
                                        text: Number(model.latitude).toFixed(3) + "°, " + Number(model.longitude).toFixed(3) + "°"
                                        font.pixelSize: 11
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

                    // --- FUTURE SESSION CALCULATION ACTION CARD ---
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: calcActionCol.implicitHeight + 18
                        radius: 8
                        color: window.lightMode ? "#e7f5ff" : "#112238"
                        border.color: window.lightMode ? "#a5d8ff" : "#1c7ed6"
                        border.width: 1

                        ColumnLayout {
                            id: calcActionCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "⚡"
                                    font.pixelSize: 15
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Label {
                                        text: qsTr("Future Session Window (F5)")
                                        font.bold: true
                                        font.pixelSize: 12
                                        color: window.lightMode ? "#1971c2" : "#74c0fc"
                                    }

                                    Label {
                                        property int activeCount: {
                                            var c = 0
                                            for (var i = 0; i < stationsModel.count; i++) {
                                                if (stationsModel.get(i).active !== false) c++
                                            }
                                            return c
                                        }
                                        text: activeCount > 0
                                              ? qsTr("%1 active station(s) selected for passes").arg(activeCount)
                                              : qsTr("⚠️ No active stations selected")
                                        font.pixelSize: 10
                                        color: activeCount > 0 ? (window.lightMode ? "#40c057" : "#51cf66") : "#fa5252"
                                        font.bold: true
                                    }
                                }
                            }

                            Button {
                                id: calcSessionBtn
                                Layout.fillWidth: true
                                height: 36
                                property int activeCount: {
                                    var c = 0
                                    for (var i = 0; i < stationsModel.count; i++) {
                                        if (stationsModel.get(i).active !== false) c++
                                    }
                                    return c
                                }
                                enabled: activeCount > 0

                                background: Rectangle {
                                    radius: 6
                                    color: calcSessionBtn.enabled
                                           ? (calcSessionBtn.down ? "#1864ab" : (window.lightMode ? "#228be6" : "#1c7ed6"))
                                           : (window.lightMode ? "#e9ecef" : "#2c2e33")
                                    border.color: calcSessionBtn.enabled ? "transparent" : (window.lightMode ? "#ced4da" : "#373a40")
                                }
                                contentItem: RowLayout {
                                    spacing: 6
                                    anchors.centerIn: parent
                                    Text {
                                        text: "🚀"
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        text: calcSessionBtn.enabled
                                              ? qsTr("Calculate Future Sessions (%1 active)").arg(calcSessionBtn.activeCount)
                                              : qsTr("Select Active Station to Calculate")
                                        color: calcSessionBtn.enabled ? "#ffffff" : (window.lightMode ? "#adb5bd" : "#5c5f66")
                                        font.bold: true
                                        font.pixelSize: 12
                                    }
                                }
                                onClicked: {
                                    rightPanel.currentTab = 1
                                    passWindowCalculator.calculatePasses()
                                }
                            }
                        }
                    }
                }

                // --- TAB 1: Pass Windows (F5) ---
                PassWindowCalculator {
                    id: passWindowCalculator
                    visible: rightPanel.currentTab === 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    satellitesModel: satellitesModel
                    stationsModel: stationsModel
                    selectedSatelliteId: window.selectedSatelliteId
                    selectedStationId: window.selectedStationId
                    propagator: propagator
                    lightMode: window.lightMode

                    onPassSelected: (passEvent) => {
                        if (passEvent.stationPasses && passEvent.stationPasses.length > 0) {
                            var stName = passEvent.stationPasses[0].stationName
                            for (var s = 0; s < stationsModel.count; s++) {
                                if (stationsModel.get(s).name === stName) {
                                    window.selectStation(stationsModel.get(s).stationId, stationsModel.get(s).latitude, stationsModel.get(s).longitude)
                                    break
                                }
                            }
                        }
                    }

                    onSatelliteSelected: (satId, satName) => {
                        for (var i = 0; i < satellitesModel.count; i++) {
                            if (satellitesModel.get(i).satId === satId) {
                                var sat = satellitesModel.get(i)
                                window.selectSatellite(sat.satId, sat.latitude, sat.longitude, sat.altitudeKm, sat.name)
                                break
                            }
                        }
                    }

                    onStationSelected: (stationId, stationName) => {
                        for (var s = 0; s < stationsModel.count; s++) {
                            if (stationsModel.get(s).stationId === stationId) {
                                var st = stationsModel.get(s)
                                window.selectStation(st.stationId, st.latitude, st.longitude)
                                break
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
        // Initial Ground Stations
        stationsModel.append([
            { stationId: "GS-01", name: "Warsaw Primary Hub", latitude: 52.2297, longitude: 21.0122, altitude: 220.0, minElevation: 5.0, active: true },
            { stationId: "GS-02", name: "Gdansk Coastal Relay", latitude: 54.3520, longitude: 18.6466, altitude: 110.0, minElevation: 5.0, active: true },
            { stationId: "GS-03", name: "Krakow Southern Node", latitude: 50.0647, longitude: 19.9450, altitude: 380.0, minElevation: 5.0, active: true },
            { stationId: "GS-04", name: "Wroclaw West Link", latitude: 51.1079, longitude: 17.0385, altitude: 175.0, minElevation: 5.0, active: true }
        ])

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
