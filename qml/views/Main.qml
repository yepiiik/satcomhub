import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import satcomhub

ApplicationWindow {
    id: window
    width: 1440
    height: 880
    minimumWidth: 900
    minimumHeight: 550
    visible: true
    title: qsTr("SatComHub - Satellite & Ground Station Monitor")
    color: lightMode ? bgLight : bgDark

    property bool lightMode: Application.styleHints.colorScheme === Qt.Light
    property color bgDark: "#10121a"
    property color bgLight: "#f8f9fa"
    property color panelDark: "#141720"
    property color panelLight: "#ffffff"
    property color cardDark: "#1a1e29"
    property color cardLight: "#f1f3f5"
    property color textDark: "#e9ecef"
    property color textLight: "#212529"
    property color subTextDark: "#909296"
    property color subTextLight: "#6c757d"
    property color accentColor: "#228be6"
    property color satColor: "#f59f00"
    property color borderDark: "#262b3a"
    property color borderLight: "#dee2e6"

    // Active navigation tab (0: Objects, 1: Planning, 2: History)
    property int currentNavTab: 0

    property bool pickOnMapActive: false
    property string selectedStationId: ""
    property string selectedSatelliteId: ""
    property real currentSatAltKm: 500.0
    property string currentSatName: "Default LEO (500 km)"

    // Planning state
    property var planningPassResult: null
    property var currentPlanningSession: null
    property var planningSnrData: null
    property int planningForecastHours: 24
    property bool isCalculatingPlanning: false

    // History state
    property var currentHistoricalObservation: null

    // Python Factor Modules state
    property var recentModulesList: []
    property var pythonEnvInfo: ({ available: true, version: "Python 3", isVenv: false })
    property string sessionInputJsonPreview: ""
    property int moduleRunCounter: 0

    // Python Correlation Modules ("Predict Attenuation") state
    property var recentCorrelationModulesList: []
    property var recentExcelFilesList: []
    property string selectedCorrelationModulePath: ""
    property string selectedExcelFilePath: ""
    property var pendingCorrelationIndices: []

    ListModel {
        id: addedPythonModulesModel
    }

    ListModel {
        id: stationCorrelationModel
    }

    ListModel {
        id: toastsModel
    }

    SatellitePropagator {
        id: propagator
    }

    StationManager {
        id: stationManager
    }

    PythonModuleRunner {
        id: pythonModuleRunner

        onModuleStarted: (runId, moduleName, modulePath) => {
            // Update factor module card status
            for (var i = 0; i < addedPythonModulesModel.count; i++) {
                if (addedPythonModulesModel.get(i).activeRunId === runId) {
                    addedPythonModulesModel.setProperty(i, "status", "running")
                    break
                }
            }
            // Update station correlation card status
            for (var c = 0; c < stationCorrelationModel.count; c++) {
                if (stationCorrelationModel.get(c).activeRunId === runId) {
                    stationCorrelationModel.setProperty(c, "status", "running")
                    break
                }
            }
            // Add or update toast in stack
            var foundToast = false
            for (var t = 0; t < toastsModel.count; t++) {
                if (toastsModel.get(t).runId === runId) {
                    toastsModel.setProperty(t, "progress", 0.08)
                    toastsModel.setProperty(t, "status", "running")
                    toastsModel.setProperty(t, "statusText", "Starting " + moduleName + "...")
                    foundToast = true
                    break
                }
            }
            if (!foundToast) {
                toastsModel.append({
                    runId: runId,
                    moduleName: moduleName,
                    progress: 0.08,
                    status: "running",
                    statusText: "Starting " + moduleName + "..."
                })
            }
        }

        onModuleProgress: (runId, moduleName, progress, statusText) => {
            for (var t = 0; t < toastsModel.count; t++) {
                if (toastsModel.get(t).runId === runId) {
                    toastsModel.setProperty(t, "progress", progress)
                    toastsModel.setProperty(t, "statusText", statusText)
                    break
                }
            }
        }

        onModuleFinished: (runId, moduleName, modulePath, success, outputJson, errorMessage) => {
            var wasFactorModule = false
            for (var i = 0; i < addedPythonModulesModel.count; i++) {
                if (addedPythonModulesModel.get(i).activeRunId === runId) {
                    wasFactorModule = true
                    addedPythonModulesModel.setProperty(i, "status", success ? "done" : "error")
                    addedPythonModulesModel.setProperty(i, "outputJson", outputJson || "")
                    addedPythonModulesModel.setProperty(i, "errorText", errorMessage || "")
                    addedPythonModulesModel.setProperty(i, "expanded", true)
                    break
                }
            }

            var toastFinalStatus = success ? "done" : "error"
            var toastFinalMsg = success ? "Completed — Output JSON ready" : ("Error: " + errorMessage)

            for (var c = 0; c < stationCorrelationModel.count; c++) {
                if (stationCorrelationModel.get(c).activeRunId === runId) {
                    var corrStatus = success ? "done" : "error"
                    if (success && outputJson && outputJson.length > 0) {
                        try {
                            var parsed = JSON.parse(outputJson)
                            if (parsed.status !== undefined && Number(parsed.status) !== 0) {
                                corrStatus = "error"
                                toastFinalStatus = "error"
                                toastFinalMsg = parsed.message || "Error in correlation output JSON"
                            } else if (parsed.message && String(parsed.message).indexOf("Warning:") === 0) {
                                corrStatus = "warning"
                                toastFinalMsg = parsed.message
                            }
                        } catch (e) {
                        }
                    }
                    stationCorrelationModel.setProperty(c, "status", corrStatus)
                    stationCorrelationModel.setProperty(c, "outputJson", outputJson || "")
                    stationCorrelationModel.setProperty(c, "errorText", errorMessage || "")
                    stationCorrelationModel.setProperty(c, "expanded", true)
                    break
                }
            }

            for (var t = 0; t < toastsModel.count; t++) {
                if (toastsModel.get(t).runId === runId) {
                    toastsModel.setProperty(t, "progress", 1.0)
                    toastsModel.setProperty(t, "status", toastFinalStatus)
                    toastsModel.setProperty(t, "statusText", toastFinalMsg)
                    break
                }
            }

            window.recentModulesList = pythonModuleRunner.loadRecentModules()
            window.recentCorrelationModulesList = pythonModuleRunner.loadRecentCorrelationModules()
            window.recentExcelFilesList = pythonModuleRunner.loadRecentExcelFiles()

            // If factor modules finished and any station correlation predictions were waiting, execute them now
            if (wasFactorModule && window.pendingCorrelationIndices && window.pendingCorrelationIndices.length > 0) {
                var anyStillRunning = false
                for (var k = 0; k < addedPythonModulesModel.count; k++) {
                    if (addedPythonModulesModel.get(k).status === "running") {
                        anyStillRunning = true
                        break
                    }
                }
                if (!anyStillRunning) {
                    var queued = window.pendingCorrelationIndices.slice()
                    window.pendingCorrelationIndices = []
                    for (var q = 0; q < queued.length; q++) {
                        window.executeStationCorrelationNow(queued[q])
                    }
                }
            }
        }
    }

    // ================= MODAL DIALOGS =================
    StationDialog {
        id: stationDialog
        lightMode: window.lightMode
        accentColor: window.accentColor
        stationManager: stationManager

        onStationCommitted: (data, isEdit) => {
            if (isEdit) {
                for (var i = 0; i < stationsModel.count; i++) {
                    if (stationsModel.get(i).stationId === data.stationId) {
                        if (data.active === undefined) {
                            data.active = stationsModel.get(i).active !== false
                        }
                        stationsModel.set(i, data)
                        break
                    }
                }
                window.selectedStationId = data.stationId
            } else {
                var newId = (data.stationId && data.stationId.length > 0) ? data.stationId : ("GS-0" + (stationsModel.count + 1))
                data.stationId = newId
                if (data.active === undefined) {
                    data.active = true
                }
                stationsModel.append(data)
                window.selectedStationId = newId
            }
            window.syncStationsToDisk()
            mapComponent.focusOnCoordinate(data.latitude, data.longitude)
            mapComponent.removeDraftMarker()
            mapComponent.requestCanvasRedraw()
            if (window.currentNavTab === 1) {
                window.calculateFuturePasses()
            }
        }

        onPickOnMapRequested: {
            stationDialog.close()
            window.pickOnMapActive = true
            mapComponent.pickModeEnabled = true
        }
    }

    SatelliteDialog {
        id: satelliteDialog
        lightMode: window.lightMode
        propagator: propagator

        onSatelliteCommitted: (data, isEdit) => {
            if (isEdit) {
                for (var s = 0; s < satellitesModel.count; s++) {
                    if (satellitesModel.get(s).satId === data.satId) {
                        satellitesModel.setProperty(s, "name", data.name)
                        satellitesModel.setProperty(s, "tle1", data.tle1)
                        satellitesModel.setProperty(s, "tle2", data.tle2)
                        satellitesModel.setProperty(s, "latitude", data.latitude)
                        satellitesModel.setProperty(s, "longitude", data.longitude)
                        satellitesModel.setProperty(s, "altitudeKm", data.altitudeKm)
                        satellitesModel.setProperty(s, "visibilityRadiusMeters", data.visibilityRadiusMeters)
                        satellitesModel.setProperty(s, "velocityKmS", data.velocityKmS || 0)
                        satellitesModel.setProperty(s, "trajectory", data.trajectory || [])
                        satellitesModel.setProperty(s, "prevTrajectory", data.prevTrajectory || [])
                        satellitesModel.setProperty(s, "nextTrajectory", data.nextTrajectory || [])
                        break
                    }
                }
                window.selectSatellite(data.satId, data.latitude, data.longitude, data.altitudeKm, data.name)
            } else {
                var newSatId = (data.satId && data.satId.length > 0) ? data.satId : ("SAT-0" + (satellitesModel.count + 1))
                data.satId = newSatId
                satellitesModel.append(data)
                window.selectSatellite(newSatId, data.latitude, data.longitude, data.altitudeKm, data.name)
            }
            mapComponent.focusOnCoordinate(data.latitude, data.longitude)
            mapComponent.requestCanvasRedraw()
            if (window.currentNavTab === 1) {
                window.calculateFuturePasses()
            }
        }
    }

    StationJsonViewer {
        id: stationDetailsViewer
        lightMode: window.lightMode
        accentColor: window.accentColor
    }

    PassSnrPlotModal {
        id: snrPlotModal
        lightMode: window.lightMode
        onClosed: snrProfileData = null
    }

    // ================= LIVE SATELLITE PROPAGATION TIMER =================
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

    // ================= DATA MODELS =================
    ListModel {
        id: stationsModel
    }

    ListModel {
        id: satellitesModel
    }

    ListModel {
        id: historyModel
        ListElement {
            obsId: "OBS-2026-10-21-01"
            satelliteName: "ISS (ZARYA)"
            stationName: "Warsaw Primary Hub"
            dateTimeUtc: "2026-10-21 14:22:10 UTC"
            durationFormatted: "10m 15s"
            maxSnrDb: 18.4
            meanSnrDb: 12.1
            maxElevationDeg: 62.4
            status: "Decoded"
            decodedFrames: 1240
            totalFrames: 1248
            operator: "SP3PUT Lab Team"
            notes: "Clear pass above Central Europe. C-band downlink fully locked from AOS+45s to LOS-30s. Turbo decoder rate 1/2 achieved 99.3% packet success."
        }
        ListElement {
            obsId: "OBS-2026-10-20-03"
            satelliteName: "POLYITAN-3-PUT (LEO)"
            stationName: "Warsaw Primary Hub"
            dateTimeUtc: "2026-10-20 18:05:44 UTC"
            durationFormatted: "8m 30s"
            maxSnrDb: 14.8
            meanSnrDb: 9.6
            maxElevationDeg: 41.0
            status: "Decoded"
            decodedFrames: 940
            totalFrames: 960
            operator: "SP5PUT Ground Station"
            notes: "Multi-station handover test. Track handover initiated at TCA+60s with Krakow GS."
        }
        ListElement {
            obsId: "OBS-2026-10-19-02"
            satelliteName: "ISS (ZARYA)"
            stationName: "Krakow GS-02"
            dateTimeUtc: "2026-10-19 09:12:00 UTC"
            durationFormatted: "6m 50s"
            maxSnrDb: 11.2
            meanSnrDb: 6.8
            maxElevationDeg: 24.5
            status: "Partial"
            decodedFrames: 610
            totalFrames: 820
            operator: "AGH Space Systems"
            notes: "Low elevation pass. Tree obstruction near horizon caused minor packet drops between 5° and 10° elevation."
        }
    }

    // ================= HELPER FUNCTIONS =================
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
        if (window.currentNavTab === 1) {
            window.calculateFuturePasses()
        }
    }

    function openStationJsonViewer(station) {
        var json = station.stationJson || ""
        if (json === "") {
            json = stationManager.buildStationJson(station)
        }
        stationDetailsViewer.stationName = station.name + " (" + station.stationId + ")"
        stationDetailsViewer.jsonContent = json
        stationDetailsViewer.open()
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
        mapComponent.requestCanvasRedraw()
        if (window.currentNavTab === 1) {
            window.calculateFuturePasses()
        }
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
                gOverT: Number(st.gOverT) || 17.53,
                active: st.active !== false
            })
        }
        stationManager.saveStationsToDisk(list)
    }

    function getSelectedSatellite() {
        if (!satellitesModel || satellitesModel.count === 0) return null
        if (window.selectedSatelliteId !== "") {
            for (var i = 0; i < satellitesModel.count; i++) {
                if (satellitesModel.get(i).satId === window.selectedSatelliteId) {
                    return satellitesModel.get(i)
                }
            }
        }
        return satellitesModel.get(0)
    }

    function getActiveStations() {
        var list = []
        for (var s = 0; s < stationsModel.count; s++) {
            var item = stationsModel.get(s)
            if (item.active !== false) {
                list.push({
                    stationId: item.stationId,
                    name: item.name,
                    latitude: item.latitude,
                    longitude: item.longitude,
                    altitude: item.altitude || 0,
                    minElevation: item.minElevation !== undefined ? item.minElevation : 5.0,
                    gOverT: item.gOverT !== undefined ? item.gOverT : 17.5,
                    feederLoss: item.feederLoss !== undefined ? item.feederLoss : 0.3,
                    freqMinMhz: item.freqMinMhz || 0.0,
                    freqMaxMhz: item.freqMaxMhz || 0.0
                })
            }
        }
        return list
    }

    function calculateFuturePasses() {
        if (!propagator) return
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) {
            planningPassResult = null
            currentPlanningSession = null
            planningSnrData = null
            return
        }

        var stationsToCalc = getActiveStations()
        if (stationsToCalc.length === 0) {
            planningPassResult = { totalPasses: 0, multiStationPasses: 0, passes: [] }
            currentPlanningSession = null
            planningSnrData = null
            return
        }

        isCalculatingPlanning = true
        var res = propagator.calculatePassWindows(sat.tle1, sat.tle2, stationsToCalc, planningForecastHours, 20.0)
        planningPassResult = res
        isCalculatingPlanning = false

        if (res && res.passes && res.passes.length > 0) {
            currentPlanningSession = res.passes[0]
            calculatePlanningSnr(res.passes[0])
        } else {
            currentPlanningSession = null
            planningSnrData = null
        }
    }

    function calculatePlanningSnr(passEvent) {
        if (!propagator || !passEvent) {
            planningSnrData = null
            stationCorrelationModel.clear()
            return
        }
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) return
        var stationsToCalc = getActiveStations()
        if (stationsToCalc.length === 0) return

        var startIso = passEvent.combinedAosUtc
        var endIso = passEvent.combinedLosUtc

        var res = propagator.calculatePassSnrProfile(
            sat.tle1, sat.tle2, stationsToCalc,
            startIso, endIso,
            1.0, 33.0, 3.0, 5840.0, 10000.0
        )
        planningSnrData = res
        // Reset previous session's factor module outputs when switching sessions
        for (var m = 0; m < addedPythonModulesModel.count; m++) {
            addedPythonModulesModel.setProperty(m, "status", "ready")
            addedPythonModulesModel.setProperty(m, "outputJson", "")
            addedPythonModulesModel.setProperty(m, "errorText", "")
        }
        window.syncStationCorrelationModel(passEvent)
        if (planningDetailsView.showInputJsonPreview) {
            window.sessionInputJsonPreview = window.buildCurrentSessionInputJson()
        }
    }

    function syncStationCorrelationModel(passEvent) {
        stationCorrelationModel.clear()
        window.pendingCorrelationIndices = []
        if (!passEvent) return

        var passes = passEvent.stationPasses || []
        if (passes.length > 0) {
            for (var i = 0; i < passes.length; i++) {
                var sp = passes[i]
                var stSamples = sp.durationSeconds !== undefined ? (Math.round(Number(sp.durationSeconds)) + 1) : 0
                stationCorrelationModel.append({
                    stationId: sp.stationId || ("GS-" + (i + 1)),
                    stationName: sp.stationName || ("Ground Station " + (i + 1)),
                    expectedSamples: stSamples,
                    status: "ready",
                    activeRunId: "",
                    inputJson: "",
                    outputJson: "",
                    errorText: "",
                    showInput: false,
                    expanded: false
                })
            }
        } else {
            var activeSt = getActiveStations()
            for (var s = 0; s < activeSt.length; s++) {
                stationCorrelationModel.append({
                    stationId: activeSt[s].stationId || ("GS-" + (s + 1)),
                    stationName: activeSt[s].name || ("Ground Station " + (s + 1)),
                    expectedSamples: 0,
                    status: "ready",
                    activeRunId: "",
                    inputJson: "",
                    outputJson: "",
                    errorText: "",
                    showInput: false,
                    expanded: false
                })
            }
        }
    }

    function executeStationCorrelationNow(stationIdx) {
        if (stationIdx < 0 || stationIdx >= stationCorrelationModel.count) return
        var stItem = stationCorrelationModel.get(stationIdx)

        var factorOutputs = []
        for (var i = 0; i < addedPythonModulesModel.count; i++) {
            var mod = addedPythonModulesModel.get(i)
            if (mod.outputJson && mod.outputJson.length > 0) {
                factorOutputs.push(mod.outputJson)
            }
        }

        var expectedSamples = stItem.expectedSamples > 0
                              ? stItem.expectedSamples
                              : ((window.planningSnrData && window.planningSnrData.sampleCount)
                                 ? window.planningSnrData.sampleCount
                                 : 0)

        var corrInputJson = pythonModuleRunner.buildCorrelationInputJson(
            stItem.stationName,
            stItem.stationId,
            expectedSamples,
            factorOutputs
        )

        window.moduleRunCounter += 1
        var runId = "corr-" + window.moduleRunCounter + "-" + Date.now()

        stationCorrelationModel.setProperty(stationIdx, "activeRunId", runId)
        stationCorrelationModel.setProperty(stationIdx, "status", "running")
        stationCorrelationModel.setProperty(stationIdx, "inputJson", corrInputJson)

        pythonModuleRunner.runCorrelationModuleAsync(
            runId,
            window.selectedCorrelationModulePath,
            window.selectedExcelFilePath,
            stItem.stationName,
            corrInputJson
        )
    }

    function predictStationAttenuationAtIndex(stationIdx) {
        if (stationIdx < 0 || stationIdx >= stationCorrelationModel.count) return
        if (!window.currentPlanningSession) return

        // Check if any added factor modules have not been run yet; if so, run them first and queue correlation
        var needFactorRun = false
        for (var i = 0; i < addedPythonModulesModel.count; i++) {
            var mod = addedPythonModulesModel.get(i)
            if (!mod.outputJson || mod.outputJson.length === 0) {
                needFactorRun = true
                if (mod.status !== "running") {
                    runPythonModuleAtIndex(i)
                }
            }
        }

        if (needFactorRun) {
            stationCorrelationModel.setProperty(stationIdx, "status", "running")
            if (window.pendingCorrelationIndices.indexOf(stationIdx) === -1) {
                var updated = window.pendingCorrelationIndices.slice()
                updated.push(stationIdx)
                window.pendingCorrelationIndices = updated
            }
        } else {
            executeStationCorrelationNow(stationIdx)
        }
    }

    function predictAllStationsAttenuation() {
        if (!window.currentPlanningSession) return
        for (var c = 0; c < stationCorrelationModel.count; c++) {
            predictStationAttenuationAtIndex(c)
        }
    }

    function buildCurrentSessionInputJson() {
        if (!window.currentPlanningSession) return "{}"
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) return "{}"
        var allActiveStations = getActiveStations()
        var sessionStations = []
        var passes = window.currentPlanningSession.stationPasses || []
        if (passes.length > 0) {
            for (var p = 0; p < passes.length; p++) {
                var sp = passes[p]
                for (var a = 0; a < allActiveStations.length; a++) {
                    var st = allActiveStations[a]
                    if ((sp.stationId && st.stationId === sp.stationId) ||
                        (sp.stationName && st.name === sp.stationName)) {
                        sessionStations.push(st)
                        break
                    }
                }
            }
        }
        if (sessionStations.length === 0) {
            sessionStations = allActiveStations
        }
        return pythonModuleRunner.buildSessionInputJson(
            sat.tle1,
            sat.tle2,
            sessionStations,
            window.currentPlanningSession.combinedAosUtc,
            window.currentPlanningSession.combinedLosUtc,
            1.0
        )
    }

    function addPythonModuleToSession(modulePath) {
        if (!modulePath || modulePath.length === 0) return
        // Avoid duplicate module path in the active list
        for (var i = 0; i < addedPythonModulesModel.count; i++) {
            if (addedPythonModulesModel.get(i).path === modulePath) {
                return
            }
        }
        var parts = modulePath.replace(/\\/g, "/").split("/")
        var fileName = parts.length > 0 ? parts[parts.length - 1] : "module.py"

        addedPythonModulesModel.append({
            name: fileName,
            path: modulePath,
            status: "ready",
            activeRunId: "",
            outputJson: "",
            errorText: "",
            expanded: false
        })

        window.recentModulesList = pythonModuleRunner.addRecentModule(modulePath)
    }

    function runPythonModuleAtIndex(idx) {
        if (idx < 0 || idx >= addedPythonModulesModel.count) return
        if (!window.currentPlanningSession) return

        var item = addedPythonModulesModel.get(idx)
        window.moduleRunCounter += 1
        var runId = "run-" + window.moduleRunCounter + "-" + Date.now()

        addedPythonModulesModel.setProperty(idx, "activeRunId", runId)
        addedPythonModulesModel.setProperty(idx, "status", "running")

        var inputJson = window.buildCurrentSessionInputJson()
        window.sessionInputJsonPreview = inputJson
        pythonModuleRunner.runModuleAsync(runId, item.path, inputJson)
    }

    function runAllAddedPythonModules() {
        if (!window.currentPlanningSession) return
        for (var i = 0; i < addedPythonModulesModel.count; i++) {
            runPythonModuleAtIndex(i)
        }
    }

    function closeToastById(runId) {
        for (var t = 0; t < toastsModel.count; t++) {
            if (toastsModel.get(t).runId === runId) {
                if (toastsModel.get(t).status === "running") {
                    pythonModuleRunner.cancelModuleRun(runId)
                }
                toastsModel.remove(t)
                break
            }
        }
    }

    // ================= MAIN APPLICATION LAYOUT (GridLayout: 3 Columns) =================
    // Columns: [0: sideNavBar] [1: leftBlock] [2: rightBlock]
    GridLayout {
        id: mainLayout
        anchors.fill: parent
        columns: 3
        rows: 1
        columnSpacing: 12
        rowSpacing: 12
        anchors.margins: 12

        // ----------------- COLUMN 0: SIDENAVBAR (Width 64) -----------------
        VerticalNavBar {
            id: sideNavBar
            Layout.row: 0
            Layout.column: 0
            Layout.fillHeight: true
            Layout.preferredWidth: 64
            Layout.minimumWidth: 64
            Layout.maximumWidth: 64
            currentTab: window.currentNavTab
            lightMode: window.lightMode
            currentUtcString: window.currentUtcString

            onTabSelected: (idx) => {
                window.currentNavTab = idx
                if (idx === 1 && (!window.planningPassResult || window.planningPassResult.passes.length === 0)) {
                    window.calculateFuturePasses()
                }
            }

            onThemeToggleRequested: {
                window.lightMode = !window.lightMode
            }
        }

        // ----------------- COLUMN 1: LEFTBLOCK (Contextual List Block, Width 350) -----------------
        Rectangle {
            id: leftBlock
            Layout.row: 0
            Layout.column: 1
            Layout.fillHeight: true
            Layout.preferredWidth: 350
            Layout.minimumWidth: 280
            radius: 12
            clip: true
            color: window.lightMode ? "#ffffff" : "#141720"
            border.color: window.lightMode ? "#dee2e6" : "#262b3a"
            border.width: 1

            // TAB 0 LIST BLOCK: Objects (Satellites & Ground Stations)
            ObjectsListSidebar {
                anchors.fill: parent
                visible: window.currentNavTab === 0
                satellitesModel: satellitesModel
                stationsModel: stationsModel
                selectedSatelliteId: window.selectedSatelliteId
                selectedStationId: window.selectedStationId
                currentSatAltKm: window.currentSatAltKm
                lightMode: window.lightMode

                onAddSatelliteRequested: satelliteDialog.openForNew()
                onEditSatelliteRequested: (sat) => satelliteDialog.openForEdit(sat)
                onDeleteSatelliteRequested: (satId) => window.deleteSatellite(satId)
                onSatelliteSelected: (satId, lat, lon, altKm, name) => window.selectSatellite(satId, lat, lon, altKm, name)
                onCalculateSatellitePassesRequested: (satId, name) => {
                    window.selectedSatelliteId = satId
                    window.currentNavTab = 1
                    window.calculateFuturePasses()
                }

                onAddStationRequested: {
                    stationDialog.openForCreate()
                }
                onEditStationRequested: (st) => window.startEditStation(st)
                onViewStationJsonRequested: (st) => window.openStationJsonViewer(st)
                onDeleteStationRequested: (stId) => window.deleteStation(stId)
                onStationSelected: (stId, lat, lon) => window.selectStation(stId, lat, lon)
                onStationActiveToggled: (stId, active) => {
                    for (var i = 0; i < stationsModel.count; i++) {
                        if (stationsModel.get(i).stationId === stId) {
                            stationsModel.setProperty(i, "active", active)
                            break
                        }
                    }
                    window.syncStationsToDisk()
                    mapComponent.requestCanvasRedraw()
                    if (window.currentNavTab === 1) {
                        window.calculateFuturePasses()
                    }
                }
            }

            // TAB 1 LIST BLOCK: Planning (Future Pass Sessions)
            PlanningListSidebar {
                anchors.fill: parent
                visible: window.currentNavTab === 1
                satellitesModel: satellitesModel
                stationsModel: stationsModel
                selectedSatelliteId: window.selectedSatelliteId
                passResult: window.planningPassResult
                selectedSession: window.currentPlanningSession
                isCalculating: window.isCalculatingPlanning
                lightMode: window.lightMode
                forecastHours: window.planningForecastHours

                onSessionSelected: (passEvent) => {
                    window.currentPlanningSession = passEvent
                    window.calculatePlanningSnr(passEvent)
                }

                onRecalculateRequested: window.calculateFuturePasses()
                onSatelliteChanged: (satId) => {
                    window.selectedSatelliteId = satId
                    window.calculateFuturePasses()
                }
                onForecastDurationSelected: (hrs) => {
                    window.planningForecastHours = hrs
                    window.calculateFuturePasses()
                }
            }

            // TAB 2 LIST BLOCK: History (Observation Logs F9)
            HistoryListSidebar {
                anchors.fill: parent
                visible: window.currentNavTab === 2
                historyModel: historyModel
                selectedObservation: window.currentHistoricalObservation
                lightMode: window.lightMode

                onObservationSelected: (obs) => {
                    window.currentHistoricalObservation = obs
                }

                onAddObservationRequested: {
                    var nextId = "OBS-2026-10-23-0" + (historyModel.count + 1)
                    var stName = stationsModel.count > 0 ? stationsModel.get(0).name : "Warsaw Primary Hub"
                    historyModel.insert(0, {
                        obsId: nextId,
                        satelliteName: window.currentSatName,
                        stationName: stName,
                        dateTimeUtc: propagator.currentUtcIsoString(),
                        durationFormatted: "9m 45s",
                        maxSnrDb: 18.5,
                        meanSnrDb: 11.2,
                        maxElevationDeg: 54.2,
                        status: "Decoded",
                        decodedFrames: 1120,
                        totalFrames: 1145,
                        operator: "SP3PUT Ground Team",
                        notes: "Live pass telemetry logged via SatComHub F9 observation manager."
                    })
                    window.currentHistoricalObservation = historyModel.get(0)
                }
            }
        }

        // ----------------- COLUMN 2: RIGHTBLOCK (Main Area, Takes remaining width) -----------------
        Rectangle {
            id: rightBlock
            Layout.row: 0
            Layout.column: 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            clip: true
            color: window.lightMode ? "#ffffff" : "#141720"
            border.color: window.lightMode ? "#dee2e6" : "#262b3a"
            border.width: 1

            // TAB 0 MAIN AREA: Map Component
            MapComponent {
                id: mapComponent
                anchors.fill: parent
                visible: window.currentNavTab === 0
                lightMode: window.lightMode
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

            // TAB 1 MAIN AREA: Planning Session Details View
            PlanningSessionDetailsView {
                id: planningDetailsView
                anchors.fill: parent
                visible: window.currentNavTab === 1
                sessionEvent: window.currentPlanningSession
                snrProfileData: window.planningSnrData
                lightMode: window.lightMode

                addedModulesModel: addedPythonModulesModel
                recentModulesList: window.recentModulesList
                pythonEnvInfo: window.pythonEnvInfo
                sessionInputJsonPreview: window.sessionInputJsonPreview

                stationCorrelationModel: stationCorrelationModel
                recentCorrelationModulesList: window.recentCorrelationModulesList
                recentExcelFilesList: window.recentExcelFilesList
                selectedCorrelationModulePath: window.selectedCorrelationModulePath
                selectedExcelFilePath: window.selectedExcelFilePath

                onBrowseModuleRequested: {
                    var selectedPath = pythonModuleRunner.selectPythonModuleDialog()
                    if (selectedPath && selectedPath.length > 0) {
                        window.addPythonModuleToSession(selectedPath)
                    }
                }

                onAddRecentModuleRequested: (modulePath) => {
                    window.addPythonModuleToSession(modulePath)
                }

                onRemoveAddedModuleRequested: (idx) => {
                    if (idx >= 0 && idx < addedPythonModulesModel.count) {
                        var runId = addedPythonModulesModel.get(idx).activeRunId
                        if (runId && runId.length > 0) {
                            pythonModuleRunner.cancelModuleRun(runId)
                        }
                        addedPythonModulesModel.remove(idx)
                    }
                }

                onRunModuleRequested: (idx, modulePath) => {
                    window.runPythonModuleAtIndex(idx)
                }

                onRunAllModulesRequested: {
                    window.runAllAddedPythonModules()
                }

                onGenerateInputJsonPreviewRequested: {
                    window.sessionInputJsonPreview = window.buildCurrentSessionInputJson()
                }

                onBrowseCorrelationModuleRequested: {
                    var corrPath = pythonModuleRunner.selectPythonModuleDialog()
                    if (corrPath && corrPath.length > 0) {
                        window.recentCorrelationModulesList = pythonModuleRunner.addRecentCorrelationModule(corrPath)
                        window.selectedCorrelationModulePath = corrPath
                    }
                }

                onCorrelationModuleSelected: (modulePath) => {
                    window.selectedCorrelationModulePath = modulePath
                    window.recentCorrelationModulesList = pythonModuleRunner.addRecentCorrelationModule(modulePath)
                }

                onBrowseExcelFileRequested: {
                    var exPath = pythonModuleRunner.selectExcelFileDialog()
                    if (exPath && exPath.length > 0) {
                        window.recentExcelFilesList = pythonModuleRunner.addRecentExcelFile(exPath)
                        window.selectedExcelFilePath = exPath
                    }
                }

                onExcelFileSelected: (excelPath) => {
                    window.selectedExcelFilePath = excelPath
                    window.recentExcelFilesList = pythonModuleRunner.addRecentExcelFile(excelPath)
                }

                onPredictStationAttenuationRequested: (stationIdx) => {
                    window.predictStationAttenuationAtIndex(stationIdx)
                }

                onPredictAllStationsAttenuationRequested: {
                    window.predictAllStationsAttenuation()
                }
            }

            // TAB 2 MAIN AREA: History Observation Details View
            HistoryDetailsView {
                id: historyDetailsView
                anchors.fill: parent
                visible: window.currentNavTab === 2
                observationData: window.currentHistoricalObservation
                lightMode: window.lightMode
            }

            // Smooth rounded corner mask overlay (masks the map/views to clean radius: 12)
            Canvas {
                id: rightBlockCornerOverlay
                anchors.fill: parent
                z: 99
                enabled: false

                property real radiusVal: 12
                property color bgColor: window.lightMode ? window.bgLight : window.bgDark
                property color borderColor: window.lightMode ? window.borderLight : window.borderDark

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onBgColorChanged: requestPaint()
                onBorderColorChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var r = radiusVal
                    var w = width
                    var h = height
                    if (w <= 0 || h <= 0) return

                    ctx.fillStyle = bgColor

                    // Top-Left corner wedge
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(r, 0)
                    ctx.arc(r, r, r, 1.5 * Math.PI, Math.PI, true)
                    ctx.lineTo(0, 0)
                    ctx.closePath()
                    ctx.fill()

                    // Top-Right corner wedge
                    ctx.beginPath()
                    ctx.moveTo(w, 0)
                    ctx.lineTo(w, r)
                    ctx.arc(w - r, r, r, 0, 1.5 * Math.PI, true)
                    ctx.lineTo(w, 0)
                    ctx.closePath()
                    ctx.fill()

                    // Bottom-Right corner wedge
                    ctx.beginPath()
                    ctx.moveTo(w, h)
                    ctx.lineTo(w - r, h)
                    ctx.arc(w - r, h - r, r, 0.5 * Math.PI, 0, true)
                    ctx.lineTo(w, h)
                    ctx.closePath()
                    ctx.fill()

                    // Bottom-Left corner wedge
                    ctx.beginPath()
                    ctx.moveTo(0, h)
                    ctx.lineTo(0, h - r)
                    ctx.arc(r, h - r, r, Math.PI, 0.5 * Math.PI, true)
                    ctx.lineTo(0, h)
                    ctx.closePath()
                    ctx.fill()

                    // Rounded perimeter border
                    ctx.beginPath()
                    ctx.moveTo(0.5 + r, 0.5)
                    ctx.lineTo(w - 0.5 - r, 0.5)
                    ctx.arc(w - 0.5 - r, 0.5 + r, r, 1.5 * Math.PI, 0, false)
                    ctx.lineTo(w - 0.5, h - 0.5 - r)
                    ctx.arc(w - 0.5 - r, h - 0.5 - r, r, 0, 0.5 * Math.PI, false)
                    ctx.lineTo(0.5 + r, h - 0.5)
                    ctx.arc(0.5 + r, h - 0.5 - r, r, 0.5 * Math.PI, Math.PI, false)
                    ctx.lineTo(0.5, 0.5 + r)
                    ctx.arc(0.5 + r, 0.5 + r, r, Math.PI, 1.5 * Math.PI, false)
                    ctx.closePath()
                    ctx.strokeStyle = borderColor
                    ctx.lineWidth = 1
                    ctx.stroke()
                }
            }
        }
    }

    // ================= STACKING TOAST PROGRESS OVERLAY (BOTTOM-RIGHT) =================
    ToastStackOverlay {
        id: toastStackOverlay
        lightMode: window.lightMode
        toastsModel: toastsModel

        onToastCloseRequested: (runId) => {
            window.closeToastById(runId)
        }
    }

    // ================= INITIAL DATA SETUP =================
    Component.onCompleted: {
        // Detect Python environment & load recent/discovered factor and correlation modules
        window.pythonEnvInfo = pythonModuleRunner.detectPythonEnvironment()
        window.recentModulesList = pythonModuleRunner.loadRecentModules()
        if (window.recentModulesList && window.recentModulesList.length > 0 && addedPythonModulesModel.count === 0) {
            window.addPythonModuleToSession(window.recentModulesList[0].path)
        }

        window.recentCorrelationModulesList = pythonModuleRunner.loadRecentCorrelationModules()
        if (window.recentCorrelationModulesList && window.recentCorrelationModulesList.length > 0) {
            window.selectedCorrelationModulePath = window.recentCorrelationModulesList[0].path
        }

        window.recentExcelFilesList = pythonModuleRunner.loadRecentExcelFiles()
        if (window.recentExcelFilesList && window.recentExcelFilesList.length > 0) {
            window.selectedExcelFilePath = window.recentExcelFilesList[0].path
        }

        // Load persisted ground stations if available
        var saved = stationManager.loadStationsFromDisk()
        if (saved && saved.length > 0) {
            for (var s = 0; s < saved.length; s++) {
                if (saved[s].active === undefined) saved[s].active = true
                stationsModel.append(saved[s])
            }
        } else {
            // Sample Ground Stations with rich RF configurations
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
                    lnaNf: 0.7,
                    feederLoss: 0.3,
                    freqMinMhz: 4000.0,
                    freqMaxMhz: 8000.0,
                    maxChannelWidthMhz: 4000.0,
                    totalNoiseFigureDb: 1.0,
                    systemNoiseTempK: 125.1,
                    gOverT: 17.53,
                    active: true
                },
                {
                    stationId: "GS-02",
                    name: "Krakow Auxiliary Station",
                    latitude: 50.0647,
                    longitude: 19.9450,
                    altitude: 240.0,
                    altitudeSpecified: true,
                    mobility: "Stationary",
                    minElevation: 5.0,
                    operatingBand: "C-band",
                    polarization: "RHCP",
                    antennaGain: 40.0,
                    lnaNf: 0.65,
                    feederLoss: 0.25,
                    freqMinMhz: 4000.0,
                    freqMaxMhz: 8000.0,
                    maxChannelWidthMhz: 4000.0,
                    totalNoiseFigureDb: 0.9,
                    systemNoiseTempK: 118.0,
                    gOverT: 19.28,
                    active: true
                },
                {
                    stationId: "GS-03",
                    name: "Gdansk Coastal Station",
                    latitude: 54.3520,
                    longitude: 18.6466,
                    altitude: 35.0,
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
                    gOverT: 22.24,
                    active: true
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

        // Initial Sample Satellite 2 (POLYITAN-3-PUT)
        var polyL1 = "1 99999U 24001A   26290.50000000  .00005000  00000+0  10000-3 0  9990"
        var polyL2 = "2 99999  97.4000 120.0000 0012000  90.0000 270.0000 15.15000000012345"
        var propPoly = propagator.propagateTle(polyL1, polyL2, 0.0)
        if (propPoly.valid) {
            var tracksPoly = propagator.computeOrbitTracks(polyL1, polyL2, 0.75)
            satellitesModel.append({
                satId: "SAT-02",
                name: "POLYITAN-3-PUT (LEO)",
                tle1: polyL1,
                tle2: polyL2,
                latitude: propPoly.latitude,
                longitude: propPoly.longitude,
                altitudeKm: propPoly.altitudeKm,
                visibilityRadiusMeters: propPoly.visibilityRadiusMeters,
                velocityKmS: propPoly.velocityKmS || 0,
                trajectory: tracksPoly.current || [],
                prevTrajectory: tracksPoly.previous || [],
                nextTrajectory: tracksPoly.next || []
            })
        }

        // Set initial historical observation
        if (historyModel.count > 0) {
            window.currentHistoricalObservation = historyModel.get(0)
        }

        // Trigger initial future pass prediction
        window.calculateFuturePasses()
    }
}
