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
    property int satelliteConfigVersion: 0
    property real currentSatAltKm: 500.0
    property string currentSatName: "Default LEO (500 km)"
    property var satelliteTracksMap: ({})
    property var satellitesList: []
    property var satellitesMap: ({})
    property var stationsList: []
    property var stationsMap: ({})

    // Planning state
    property var planningPassResult: null
    property var currentPlanningSession: null
    property var planningBaseSnrData: null
    property var planningSnrData: null
    property int planningForecastHours: 24
    property bool isCalculatingPlanning: false

    // History state
    property var currentHistoricalObservation: null

    // Python Factor Modules state (per-station map: stationId -> array of module objects)
    property var stationFactorModulesMap: ({})
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
            // Update per-station factor module status
            var mapCopy = Object.assign({}, window.stationFactorModulesMap)
            var mapChanged = false
            for (var stId in mapCopy) {
                var arr = (mapCopy[stId] || []).slice()
                for (var m = 0; m < arr.length; m++) {
                    if (arr[m].activeRunId === runId) {
                        var updatedMod = Object.assign({}, arr[m])
                        updatedMod.status = "running"
                        arr[m] = updatedMod
                        mapCopy[stId] = arr
                        mapChanged = true
                        break
                    }
                }
            }
            if (mapChanged) {
                window.stationFactorModulesMap = mapCopy
            }

            // Update legacy factor module card status
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
            var factorStationId = ""
            var factorModuleEnabled = false

            var fName = ""
            var fUnits = ""
            if (success && outputJson && outputJson.length > 0) {
                try {
                    var fParsed = JSON.parse(outputJson)
                    fName = fParsed.factor_name || ""
                    fUnits = fParsed.units || ""
                } catch (fe) {
                }
            }

            // Check per-station factor modules first
            var mapCopy = Object.assign({}, window.stationFactorModulesMap)
            for (var stId in mapCopy) {
                var stArr = (mapCopy[stId] || []).slice()
                var matchedInSt = false
                for (var mi = 0; mi < stArr.length; mi++) {
                    if (stArr[mi].activeRunId === runId) {
                        wasFactorModule = true
                        factorStationId = stId
                        factorModuleEnabled = stArr[mi].enabled === true
                        var modCopy = Object.assign({}, stArr[mi])
                        modCopy.status = success ? "done" : "error"
                        modCopy.outputJson = outputJson || ""
                        modCopy.errorText = errorMessage || ""
                        modCopy.factorName = fName
                        modCopy.units = fUnits
                        stArr[mi] = modCopy
                        mapCopy[stId] = stArr
                        matchedInSt = true
                        break
                    }
                }
                if (matchedInSt) {
                    window.stationFactorModulesMap = mapCopy
                    break
                }
            }

            for (var i = 0; i < addedPythonModulesModel.count; i++) {
                if (addedPythonModulesModel.get(i).activeRunId === runId) {
                    wasFactorModule = true
                    factorModuleEnabled = addedPythonModulesModel.get(i).enabled === true
                    addedPythonModulesModel.setProperty(i, "status", success ? "done" : "error")
                    addedPythonModulesModel.setProperty(i, "outputJson", outputJson || "")
                    addedPythonModulesModel.setProperty(i, "errorText", errorMessage || "")
                    addedPythonModulesModel.setProperty(i, "factorName", fName)
                    addedPythonModulesModel.setProperty(i, "units", fUnits)
                    addedPythonModulesModel.setProperty(i, "expanded", true)
                    break
                }
            }

            var toastFinalStatus = success ? "done" : "error"
            var toastFinalMsg = success ? "Completed — Output JSON ready" : ("Error: " + errorMessage)

            var wasCorrelationModule = false
            for (var c = 0; c < stationCorrelationModel.count; c++) {
                if (stationCorrelationModel.get(c).activeRunId === runId) {
                    wasCorrelationModule = true
                    var corrStatus = success ? "done" : "error"
                    var peakAtt = 0.0
                    var meanAtt = 0.0
                    if (success && outputJson && outputJson.length > 0) {
                        try {
                            var parsed = JSON.parse(outputJson)
                            if (parsed.status !== undefined && Number(parsed.status) !== 0) {
                                corrStatus = "error"
                                toastFinalStatus = "error"
                                toastFinalMsg = parsed.message || "Error in correlation output JSON"
                            } else {
                                if (parsed.message && String(parsed.message).indexOf("Warning:") === 0) {
                                    corrStatus = "warning"
                                    toastFinalMsg = parsed.message
                                }
                                var attArr = parsed.total_attenuation_db_list || []
                                if (attArr.length > 0) {
                                    var sumAtt = 0.0
                                    for (var aIdx = 0; aIdx < attArr.length; aIdx++) {
                                        var v = Number(attArr[aIdx]) || 0.0
                                        if (v > peakAtt) peakAtt = v
                                        sumAtt += v
                                    }
                                    meanAtt = sumAtt / attArr.length
                                }
                            }
                        } catch (e) {
                        }
                    }
                    stationCorrelationModel.setProperty(c, "status", corrStatus)
                    stationCorrelationModel.setProperty(c, "outputJson", outputJson || "")
                    stationCorrelationModel.setProperty(c, "errorText", errorMessage || "")
                    stationCorrelationModel.setProperty(c, "peakAttenuationDb", peakAtt)
                    stationCorrelationModel.setProperty(c, "meanAttenuationDb", meanAtt)
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

            // If a per-station factor module finished and is enabled, trigger correlation for that station once none of its enabled modules are still running
            if (wasFactorModule && factorStationId !== "") {
                var stMods = window.stationFactorModulesMap[factorStationId] || []
                var stAnyRunning = false
                for (var sm = 0; sm < stMods.length; sm++) {
                    if (stMods[sm].enabled && stMods[sm].status === "running") {
                        stAnyRunning = true
                        break
                    }
                }
                if (!stAnyRunning && factorModuleEnabled && success) {
                    var stCorrIdx = window.findStationCorrelationIndex(factorStationId)
                    if (stCorrIdx >= 0) {
                        window.executeStationCorrelationNow(stCorrIdx)
                    }
                }
            }

            if (wasCorrelationModule) {
                window.applyCorrelationAttenuationToGraph()
            }
        }
    }

    // ================= MODAL DIALOGS =================
    StationDialog {
        id: stationDialog
        lightMode: window.lightMode
        accentColor: window.accentColor
        stationManager: stationManager
        stationFactorModulesMap: window.stationFactorModulesMap
        recentModulesList: window.recentModulesList

        onBrowseStationModuleRequested: (stationId) => {
            var selectedPath = pythonModuleRunner.selectPythonModuleDialog()
            if (selectedPath && selectedPath.length > 0) {
                window.addFactorModuleToStation(stationId, selectedPath)
            }
        }

        onAddRecentStationModuleRequested: (stationId, modulePath) => {
            window.addFactorModuleToStation(stationId, modulePath)
        }

        onRemoveStationModuleRequested: (stationId, moduleIdx) => {
            window.removeFactorModuleFromStation(stationId, moduleIdx)
        }

        onStationCommitted: (data, isEdit) => {
            if (isEdit) {
                for (var i = 0; i < stationsModel.count; i++) {
                    var cachedSt = (window.stationsList && i < window.stationsList.length) ? window.stationsList[i] : null
                    var matchId = cachedSt ? cachedSt.stationId : ""
                    if (matchId === data.stationId) {
                        if (data.active === undefined) {
                            data.active = cachedSt.active !== false
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
            window.syncStationsCache()
            window.syncStationsToDisk()
            mapComponent.focusOnCoordinate(data.latitude, data.longitude)
            mapComponent.removeDraftMarker()
            mapComponent.requestCanvasRedraw()
            if (window.currentPlanningSession) {
                window.calculatePlanningSnr(window.currentPlanningSession)
            } else if (window.currentNavTab === 1) {
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
            var tleChanged = false
            if (isEdit) {
                for (var s = 0; s < satellitesModel.count; s++) {
                    var existingSat = (window.satellitesList && s < window.satellitesList.length) ? window.satellitesList[s] : null
                    if (existingSat && existingSat.satId === data.satId) {
                        if (existingSat.tle1 !== data.tle1 || existingSat.tle2 !== data.tle2) {
                            tleChanged = true
                        }
                        satellitesModel.setProperty(s, "name", data.name)
                        satellitesModel.setProperty(s, "tle1", data.tle1)
                        satellitesModel.setProperty(s, "tle2", data.tle2)
                        satellitesModel.setProperty(s, "carrierFreqMhz", data.carrierFreqMhz !== undefined ? data.carrierFreqMhz : 5850.0)
                        satellitesModel.setProperty(s, "channelBandwidthKhz", data.channelBandwidthKhz !== undefined ? data.channelBandwidthKhz : 20000.0)
                        satellitesModel.setProperty(s, "modulation", data.modulation || "OQPSK")
                        satellitesModel.setProperty(s, "bitsPerSymbol", data.bitsPerSymbol !== undefined ? data.bitsPerSymbol : 2.0)
                        satellitesModel.setProperty(s, "codeEfficiencyCoef", data.codeEfficiencyCoef !== undefined ? data.codeEfficiencyCoef : 1.24)
                        satellitesModel.setProperty(s, "rolloffAlpha", data.rolloffAlpha !== undefined ? data.rolloffAlpha : 0.35)
                        satellitesModel.setProperty(s, "txPowerDbm", data.txPowerDbm !== undefined ? data.txPowerDbm : 33.0)
                        satellitesModel.setProperty(s, "txAntennaGainDbi", data.txAntennaGainDbi !== undefined ? data.txAntennaGainDbi : 3.0)
                        satellitesModel.setProperty(s, "codeRateTable", data.codeRateTable || [])
                        satellitesModel.setProperty(s, "codeRateRegister", data.codeRateRegister || "fpgatrx/code_rate")
                        satellitesModel.setProperty(s, "latitude", data.latitude)
                        satellitesModel.setProperty(s, "longitude", data.longitude)
                        satellitesModel.setProperty(s, "altitudeKm", data.altitudeKm)
                        satellitesModel.setProperty(s, "visibilityRadiusMeters", data.visibilityRadiusMeters)
                        satellitesModel.setProperty(s, "velocityKmS", data.velocityKmS || 0)
                        break
                    }
                }
                var tracksMapCopy = Object.assign({}, window.satelliteTracksMap)
                tracksMapCopy[data.satId] = {
                    current: data.trajectory || [],
                    previous: data.prevTrajectory || [],
                    next: data.nextTrajectory || []
                }
                window.satelliteTracksMap = tracksMapCopy
                window.selectSatellite(data.satId, data.latitude, data.longitude, data.altitudeKm, data.name)
            } else {
                var newSatId = (data.satId && data.satId.length > 0) ? data.satId : ("SAT-0" + (satellitesModel.count + 1))
                data.satId = newSatId
                var newTracks = {
                    current: data.trajectory || [],
                    previous: data.prevTrajectory || [],
                    next: data.nextTrajectory || []
                }
                var appendData = Object.assign({}, data)
                delete appendData.trajectory
                delete appendData.prevTrajectory
                delete appendData.nextTrajectory
                satellitesModel.append(appendData)
                var tracksMapCopy2 = Object.assign({}, window.satelliteTracksMap)
                tracksMapCopy2[newSatId] = newTracks
                window.satelliteTracksMap = tracksMapCopy2
                window.selectSatellite(newSatId, data.latitude, data.longitude, data.altitudeKm, data.name)
                tleChanged = true
            }
            window.syncSatellitesCache()
            window.satelliteConfigVersion += 1
            mapComponent.focusOnCoordinate(data.latitude, data.longitude)
            mapComponent.requestCanvasRedraw()
            if (tleChanged) {
                window.calculateFuturePasses()
            } else if (window.currentPlanningSession) {
                window.calculatePlanningSnr(window.currentPlanningSession)
            }
        }
    }

    StationJsonViewer {
        id: stationDetailsViewer
        lightMode: window.lightMode
        accentColor: window.accentColor
    }

    SessionPlanYamlViewer {
        id: sessionPlanYamlViewer
        lightMode: window.lightMode
        onExportRequested: (yamlText) => {
            var defaultName = sessionPlanYamlViewer.defaultFileName
                ? sessionPlanYamlViewer.defaultFileName
                : (window.currentPlanningSession ? ("session_plan_pass_" + window.currentPlanningSession.passIndex + ".yaml") : "session_plan.yaml")
            var filter = sessionPlanYamlViewer.fileDialogFilter || "YAML Files (*.yaml *.yml)"
            var dlgTitle = sessionPlanYamlViewer.isJsonMode ? qsTr("Export Module JSON") : qsTr("Export Session Plan YAML")
            var path = stationManager.saveFileDialog(dlgTitle, defaultName, filter)
            if (path && path.length > 0) {
                var ok = stationManager.writeTextFile(path, yamlText)
                if (ok) {
                    toastStack.showToast(qsTr("Saved to: ") + path, "success")
                } else {
                    toastStack.showToast(qsTr("Failed to save file"), "error")
                }
            }
        }
        onCopyRequested: {
            toastStack.showToast(
                sessionPlanYamlViewer.isJsonMode
                    ? qsTr("JSON copied to clipboard")
                    : qsTr("Session Plan YAML copied to clipboard"),
                "success"
            )
        }
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
            if (window.currentNavTab === 0) {
                window.updateLiveSatellitePositions()
            }
        }
    }

    function updateLiveSatellitePositions() {
        if (!satellitesModel || satellitesModel.count === 0 || !window.satellitesList) return

        for (var i = 0; i < window.satellitesList.length; i++) {
            var satInfo = window.satellitesList[i]
            if (!satInfo || !satInfo.tle1 || !satInfo.tle2) continue

            var prop = propagator.propagateTle(satInfo.tle1, satInfo.tle2, 0.0)
            if (prop && prop.valid) {
                satellitesModel.setProperty(i, "latitude", prop.latitude)
                satellitesModel.setProperty(i, "longitude", prop.longitude)
                satellitesModel.setProperty(i, "altitudeKm", prop.altitudeKm)
                satellitesModel.setProperty(i, "visibilityRadiusMeters", prop.visibilityRadiusMeters)
                if (prop.velocityKmS !== undefined) {
                    satellitesModel.setProperty(i, "velocityKmS", prop.velocityKmS)
                }

                satInfo.latitude = prop.latitude
                satInfo.longitude = prop.longitude
                satInfo.altitudeKm = prop.altitudeKm

                if (window.selectedSatelliteId === satInfo.satId) {
                    window.currentSatAltKm = prop.altitudeKm
                }
            }
        }
        if (window.currentNavTab === 0) {
            mapComponent.requestCanvasRedraw()
        }
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
            var cachedSt = (window.stationsList && i < window.stationsList.length) ? window.stationsList[i] : null
            if (cachedSt && cachedSt.stationId === stationId) {
                stationsModel.remove(i)
                break
            }
        }
        if (window.selectedStationId === stationId) {
            window.selectedStationId = ""
        }
        window.syncStationsCache()
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
            var cachedSat = (window.satellitesList && i < window.satellitesList.length) ? window.satellitesList[i] : null
            if (cachedSat && cachedSat.satId === satId) {
                satellitesModel.remove(i)
                break
            }
        }
        window.syncSatellitesCache()
        if (window.selectedSatelliteId === satId) {
            window.selectedSatelliteId = ""
            if (window.satellitesList.length > 0) {
                var first = window.satellitesList[0]
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
            var st = (window.stationsList && i < window.stationsList.length) ? window.stationsList[i] : null
            if (!st) continue
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
        window.syncStationsCache()
    }

    function syncSatellitesCache() {
        var list = []
        var map = {}
        for (var i = 0; i < satellitesModel.count; i++) {
            var item = satellitesModel.get(i)
            if (!item) continue
            var copy = {
                satId: item.satId || "",
                name: item.name || "",
                tle1: item.tle1 || "",
                tle2: item.tle2 || "",
                carrierFreqMhz: item.carrierFreqMhz !== undefined ? item.carrierFreqMhz : 5850.0,
                channelBandwidthKhz: item.channelBandwidthKhz !== undefined ? item.channelBandwidthKhz : 20000.0,
                modulation: item.modulation || "OQPSK",
                bitsPerSymbol: item.bitsPerSymbol !== undefined ? item.bitsPerSymbol : 2.0,
                codeEfficiencyCoef: item.codeEfficiencyCoef !== undefined ? item.codeEfficiencyCoef : 1.24,
                rolloffAlpha: item.rolloffAlpha !== undefined ? item.rolloffAlpha : 0.35,
                txPowerDbm: item.txPowerDbm !== undefined ? item.txPowerDbm : 33.0,
                txAntennaGainDbi: item.txAntennaGainDbi !== undefined ? item.txAntennaGainDbi : 3.0,
                latitude: item.latitude || 0,
                longitude: item.longitude || 0,
                altitudeKm: item.altitudeKm || 500,
                visibilityRadiusMeters: item.visibilityRadiusMeters || 0,
                velocityKmS: item.velocityKmS || 0
            }
            list.push(copy)
            map[copy.satId] = copy
        }
        window.satellitesList = list
        window.satellitesMap = map
    }

    function syncStationsCache() {
        var list = []
        var map = {}
        for (var s = 0; s < stationsModel.count; s++) {
            var item = stationsModel.get(s)
            if (!item) continue
            var copy = {
                stationId: item.stationId || "",
                name: item.name || "",
                latitude: item.latitude !== undefined ? item.latitude : 0.0,
                longitude: item.longitude !== undefined ? item.longitude : 0.0,
                altitude: item.altitude !== undefined ? item.altitude : 0.0,
                minElevation: item.minElevation !== undefined ? item.minElevation : 5.0,
                operatingBand: item.operatingBand || "C-band",
                polarization: item.polarization || "RHCP",
                antennaGain: item.antennaGain !== undefined ? item.antennaGain : 38.5,
                lnaNf: item.lnaNf !== undefined ? item.lnaNf : 0.7,
                feederLoss: item.feederLoss !== undefined ? item.feederLoss : 0.3,
                freqMinMhz: item.freqMinMhz || 0.0,
                freqMaxMhz: item.freqMaxMhz || 0.0,
                gOverT: item.gOverT !== undefined ? item.gOverT : 17.5,
                active: item.active !== false
            }
            list.push(copy)
            map[copy.stationId] = copy
        }
        window.stationsList = list
        window.stationsMap = map
    }

    function getSelectedSatellite() {
        if (window.selectedSatelliteId && window.satellitesMap && window.satellitesMap[window.selectedSatelliteId]) {
            return window.satellitesMap[window.selectedSatelliteId]
        }
        if (window.satellitesList && window.satellitesList.length > 0) {
            return window.satellitesList[0]
        }
        return null
    }

    function getActiveStations() {
        var list = []
        if (window.stationsList) {
            for (var s = 0; s < window.stationsList.length; s++) {
                var item = window.stationsList[s]
                if (item.active !== false) {
                    list.push(item)
                }
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
            planningBaseSnrData = null
            planningSnrData = null
            stationCorrelationModel.clear()
            return
        }
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) return
        var stationsToCalc = []
        if (passEvent && passEvent.stationPasses && passEvent.stationPasses.length > 0) {
            var allActive = getActiveStations()
            for (var sp = 0; sp < passEvent.stationPasses.length; sp++) {
                var pId = passEvent.stationPasses[sp].stationId
                var pName = passEvent.stationPasses[sp].stationName
                for (var st = 0; st < allActive.length; st++) {
                    if ((pId && allActive[st].stationId === pId) || (pName && allActive[st].name === pName)) {
                        stationsToCalc.push(allActive[st])
                        break
                    }
                }
            }
        }
        if (stationsToCalc.length === 0) {
            stationsToCalc = getActiveStations()
        }
        if (stationsToCalc.length === 0) return

        var startIso = passEvent.combinedAosUtc
        var endIso = passEvent.combinedLosUtc

        var txPower = sat.txPowerDbm !== undefined ? Number(sat.txPowerDbm) : 33.0
        var txGain = sat.txAntennaGainDbi !== undefined ? Number(sat.txAntennaGainDbi) : 3.0
        var freqMhz = sat.carrierFreqMhz !== undefined ? Number(sat.carrierFreqMhz) : 5850.0
        var bwKhz = sat.channelBandwidthKhz !== undefined ? Number(sat.channelBandwidthKhz) : 20000.0

        var res = propagator.calculatePassSnrProfile(
            sat.tle1, sat.tle2, stationsToCalc,
            startIso, endIso,
            1.0, txPower, txGain, freqMhz, bwKhz
        )
        planningBaseSnrData = res
        planningSnrData = res
        // Reset previous session's factor module outputs & toggle states when switching sessions
        for (var m = 0; m < addedPythonModulesModel.count; m++) {
            addedPythonModulesModel.setProperty(m, "enabled", false)
            addedPythonModulesModel.setProperty(m, "status", "ready")
            addedPythonModulesModel.setProperty(m, "outputJson", "")
            addedPythonModulesModel.setProperty(m, "errorText", "")
            addedPythonModulesModel.setProperty(m, "factorName", "")
            addedPythonModulesModel.setProperty(m, "units", "")
        }
        window.syncStationCorrelationModel(passEvent)
        window.sessionInputJsonPreview = window.buildCurrentSessionInputJson()
    }

    function findStationCorrelationIndex(stationId) {
        for (var c = 0; c < stationCorrelationModel.count; c++) {
            if (stationCorrelationModel.get(c).stationId === stationId) {
                return c
            }
        }
        return -1
    }

    function syncStationCorrelationModel(passEvent) {
        stationCorrelationModel.clear()
        window.pendingCorrelationIndices = []
        if (!passEvent) return

        var nextMap = Object.assign({}, window.stationFactorModulesMap)
        var defaultModPath = (window.recentModulesList && window.recentModulesList.length > 0)
                             ? window.recentModulesList[0].path
                             : ""
        var defaultModName = defaultModPath ? defaultModPath.replace(/\\/g, "/").split("/").pop() : "rain_attenuation.py"

        function ensureStationModuleEntry(stId) {
            var existing = nextMap[stId]
            if (!existing || !Array.isArray(existing)) {
                if (defaultModPath !== "") {
                    nextMap[stId] = [{
                        name: defaultModName,
                        path: defaultModPath,
                        enabled: false,
                        status: "ready",
                        activeRunId: "",
                        inputJson: "",
                        outputJson: "",
                        errorText: "",
                        factorName: "",
                        units: ""
                    }]
                } else {
                    nextMap[stId] = []
                }
            } else {
                var resetArr = []
                for (var k = 0; k < existing.length; k++) {
                    resetArr.push({
                        name: existing[k].name,
                        path: existing[k].path,
                        enabled: false,
                        status: "ready",
                        activeRunId: "",
                        inputJson: "",
                        outputJson: "",
                        errorText: "",
                        factorName: "",
                        units: ""
                    })
                }
                nextMap[stId] = resetArr
            }
        }

        var passes = passEvent.stationPasses || []
        if (passes.length > 0) {
            for (var i = 0; i < passes.length; i++) {
                var sp = passes[i]
                var sid = sp.stationId || ("GS-" + (i + 1))
                ensureStationModuleEntry(sid)
                var stSamples = sp.durationSeconds !== undefined ? (Math.round(Number(sp.durationSeconds)) + 1) : 0
                stationCorrelationModel.append({
                    stationId: sid,
                    stationName: sp.stationName || ("Ground Station " + (i + 1)),
                    expectedSamples: stSamples,
                    status: "ready",
                    activeRunId: "",
                    inputJson: "",
                    outputJson: "",
                    errorText: "",
                    peakAttenuationDb: 0.0,
                    meanAttenuationDb: 0.0,
                    showInput: false,
                    expanded: false
                })
            }
        } else {
            var activeSt = getActiveStations()
            for (var s = 0; s < activeSt.length; s++) {
                var sid2 = activeSt[s].stationId || ("GS-" + (s + 1))
                ensureStationModuleEntry(sid2)
                stationCorrelationModel.append({
                    stationId: sid2,
                    stationName: activeSt[s].name || ("Ground Station " + (s + 1)),
                    expectedSamples: 0,
                    status: "ready",
                    activeRunId: "",
                    inputJson: "",
                    outputJson: "",
                    errorText: "",
                    peakAttenuationDb: 0.0,
                    meanAttenuationDb: 0.0,
                    showInput: false,
                    expanded: false
                })
            }
        }
        window.stationFactorModulesMap = nextMap
    }

    function stationHasAnyEnabledFactor(stationId) {
        var arr = window.stationFactorModulesMap[stationId] || []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].enabled === true) return true
        }
        return false
    }

    function applyCorrelationAttenuationToGraph() {
        if (!window.planningBaseSnrData || !window.planningBaseSnrData.valid) return

        // Check if any station has at least one factor module toggled ON
        var anyFactorEnabled = false
        for (var stId in window.stationFactorModulesMap) {
            if (stationHasAnyEnabledFactor(stId)) {
                anyFactorEnabled = true
                break
            }
        }

        if (!anyFactorEnabled) {
            window.planningSnrData = window.planningBaseSnrData
            return
        }

        var base = window.planningBaseSnrData
        var N = base.sampleCount || 0
        if (N < 2 || !base.stations) {
            window.planningSnrData = base
            return
        }

        var newStations = []
        var anyStationAttenuated = false

        for (var sIdx = 0; sIdx < base.stations.length; sIdx++) {
            var baseSt = base.stations[sIdx]
            var attList = []
            var stEnabled = stationHasAnyEnabledFactor(baseSt.stationId)

            if (stEnabled) {
                // Match station in stationCorrelationModel
                for (var c = 0; c < stationCorrelationModel.count; c++) {
                    var corrItem = stationCorrelationModel.get(c)
                    if ((corrItem.stationId && baseSt.stationId && corrItem.stationId === baseSt.stationId) ||
                        (corrItem.stationName && baseSt.stationName && corrItem.stationName === baseSt.stationName) ||
                        (c === sIdx && stationCorrelationModel.count === base.stations.length)) {
                        if ((corrItem.status === "done" || corrItem.status === "warning") &&
                            corrItem.outputJson && corrItem.outputJson.length > 0) {
                            try {
                                var parsedCorr = JSON.parse(corrItem.outputJson)
                                if (parsedCorr.total_attenuation_db_list && Array.isArray(parsedCorr.total_attenuation_db_list)) {
                                    attList = parsedCorr.total_attenuation_db_list
                                }
                            } catch (ce) {
                            }
                        }
                        break
                    }
                }
            }

            var newSnrDb = []
            var newTotalLossDb = []
            var extraAttArr = []
            var visCounter = 0
            var newMaxSnr = -999.0
            var stHasExtra = false

            for (var k = 0; k < N; k++) {
                var vis = baseSt.isVisible && baseSt.isVisible[k]
                var baseSnr = Number(baseSt.snrDb[k])
                var baseLoss = Number(baseSt.totalLossDb[k])
                var extraDb = 0.0

                if (vis && attList.length > 0) {
                    if (attList.length === N) {
                        extraDb = Math.max(0.0, Number(attList[k]) || 0.0)
                    } else {
                        var sampleIdx = Math.min(visCounter, attList.length - 1)
                        extraDb = Math.max(0.0, Number(attList[sampleIdx]) || 0.0)
                    }
                    visCounter++
                }

                if (extraDb > 0.0001) {
                    stHasExtra = true
                    anyStationAttenuated = true
                }

                var effSnr = vis ? (baseSnr - extraDb) : baseSnr
                var effLoss = vis ? (baseLoss + extraDb) : baseLoss
                if (vis && effSnr > newMaxSnr) {
                    newMaxSnr = effSnr
                }

                newSnrDb.push(effSnr)
                newTotalLossDb.push(effLoss)
                extraAttArr.push(extraDb)
            }

            newStations.push({
                stationId: baseSt.stationId,
                stationName: baseSt.stationName,
                snrDb: newSnrDb,
                baselineSnrDb: baseSt.snrDb,
                fsplLossDb: baseSt.fsplLossDb,
                atmosphericLossDb: baseSt.atmosphericLossDb,
                totalLossDb: newTotalLossDb,
                baselineTotalLossDb: baseSt.totalLossDb,
                extraAttenuationDb: extraAttArr,
                hasExtraAttenuation: stHasExtra,
                elevationDeg: baseSt.elevationDeg,
                azimuthDeg: baseSt.azimuthDeg,
                slantRangeKm: baseSt.slantRangeKm,
                isVisible: baseSt.isVisible,
                maxSnrDb: newMaxSnr > -900.0 ? newMaxSnr : baseSt.maxSnrDb,
                minFsplDb: baseSt.minFsplDb,
                maxElevationDeg: baseSt.maxElevationDeg
            })
        }

        // Recompute combinedSelectionSnrDb & combinedMrcSnrDb across visible stations
        var newCombinedMrc = []
        var newCombinedSel = []
        var newBestStationIdx = []

        for (var t = 0; t < N; t++) {
            var linearSum = 0.0
            var bestSnr = -999.0
            var bestIdx = -1
            var visCount = 0

            for (var s = 0; s < newStations.length; s++) {
                if (newStations[s].isVisible[t]) {
                    var sDb = newStations[s].snrDb[t]
                    linearSum += Math.pow(10.0, sDb / 10.0)
                    if (sDb > bestSnr) {
                        bestSnr = sDb
                        bestIdx = s
                    }
                    visCount++
                }
            }

            if (visCount > 0 && linearSum > 0.0) {
                newCombinedMrc.push(10.0 * (Math.log(linearSum) / Math.LN10))
                newCombinedSel.push(bestSnr)
                newBestStationIdx.push(bestIdx)
            } else {
                newCombinedMrc.push(-30.0)
                newCombinedSel.push(-30.0)
                newBestStationIdx.push(-1)
            }
        }

        window.planningSnrData = {
            valid: base.valid,
            satelliteName: base.satelliteName,
            startUtc: base.startUtc,
            endUtc: base.endUtc,
            durationSeconds: base.durationSeconds,
            sampleRateHz: base.sampleRateHz,
            sampleCount: base.sampleCount,
            carrierFreqMhz: base.carrierFreqMhz,
            channelBandwidthKhz: base.channelBandwidthKhz,
            txPowerDbm: base.txPowerDbm,
            txAntennaGainDbi: base.txAntennaGainDbi,
            shannonRawThresholdDb: base.shannonRawThresholdDb,
            shannonTurbocodeThresholdDb: base.shannonTurbocodeThresholdDb,
            timestampsSec: base.timestampsSec,
            utcLabels: base.utcLabels,
            stations: newStations,
            combinedMrcSnrDb: newCombinedMrc,
            combinedSelectionSnrDb: newCombinedSel,
            bestStationIndex: newBestStationIdx,
            hasOverlap: base.hasOverlap,
            hasExtraAttenuation: anyStationAttenuated
        }
    }

    function executeStationCorrelationNow(stationIdx) {
        if (stationIdx < 0 || stationIdx >= stationCorrelationModel.count) return
        var stItem = stationCorrelationModel.get(stationIdx)
        var stMods = window.stationFactorModulesMap[stItem.stationId] || []

        var factorOutputs = []
        for (var i = 0; i < stMods.length; i++) {
            var mod = stMods[i]
            if (mod.enabled && mod.outputJson && mod.outputJson.length > 0) {
                factorOutputs.push(mod.outputJson)
            }
        }

        if (factorOutputs.length === 0) {
            stationCorrelationModel.setProperty(stationIdx, "status", "ready")
            stationCorrelationModel.setProperty(stationIdx, "peakAttenuationDb", 0.0)
            stationCorrelationModel.setProperty(stationIdx, "meanAttenuationDb", 0.0)
            window.applyCorrelationAttenuationToGraph()
            return
        }

        var expectedSamples = stItem.expectedSamples > 0
                              ? stItem.expectedSamples
                              : ((window.planningBaseSnrData && window.planningBaseSnrData.sampleCount)
                                 ? window.planningBaseSnrData.sampleCount
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

    function buildStationSessionInputJson(stationId) {
        if (!window.currentPlanningSession) return "{}"
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) return "{}"
        var allActiveStations = getActiveStations()
        var targetStations = []
        for (var a = 0; a < allActiveStations.length; a++) {
            var st = allActiveStations[a]
            if (st.stationId === stationId || st.name === stationId) {
                targetStations.push(st)
                break
            }
        }
        if (targetStations.length === 0) {
            return window.buildCurrentSessionInputJson()
        }
        return pythonModuleRunner.buildSessionInputJson(
            sat.tle1,
            sat.tle2,
            targetStations,
            window.currentPlanningSession.combinedAosUtc,
            window.currentPlanningSession.combinedLosUtc,
            1.0
        )
    }

    function addFactorModuleToStation(stationId, modulePath) {
        if (!stationId || !modulePath || modulePath.length === 0) return
        var mapCopy = Object.assign({}, window.stationFactorModulesMap)
        var arr = (mapCopy[stationId] || []).slice()
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].path === modulePath) {
                return
            }
        }
        var parts = modulePath.replace(/\\/g, "/").split("/")
        var fileName = parts.length > 0 ? parts[parts.length - 1] : "module.py"
        arr.push({
            name: fileName,
            path: modulePath,
            enabled: false,
            status: "ready",
            activeRunId: "",
            inputJson: "",
            outputJson: "",
            errorText: "",
            factorName: "",
            units: ""
        })
        mapCopy[stationId] = arr
        window.stationFactorModulesMap = mapCopy
        window.recentModulesList = pythonModuleRunner.addRecentModule(modulePath)
    }

    function removeFactorModuleFromStation(stationId, moduleIdx) {
        if (!stationId) return
        var mapCopy = Object.assign({}, window.stationFactorModulesMap)
        var arr = (mapCopy[stationId] || []).slice()
        if (moduleIdx < 0 || moduleIdx >= arr.length) return
        var removed = arr[moduleIdx]
        if (removed.activeRunId && removed.activeRunId.length > 0) {
            pythonModuleRunner.cancelModuleRun(removed.activeRunId)
        }
        var wasEnabled = removed.enabled === true
        arr.splice(moduleIdx, 1)
        mapCopy[stationId] = arr
        window.stationFactorModulesMap = mapCopy
        if (wasEnabled) {
            window.recorrelateStationFactors(stationId)
        }
    }

    function runStationFactorModule(stationId, moduleIdx) {
        if (!stationId || !window.currentPlanningSession) return
        var mapCopy = Object.assign({}, window.stationFactorModulesMap)
        var arr = (mapCopy[stationId] || []).slice()
        if (moduleIdx < 0 || moduleIdx >= arr.length) return

        window.moduleRunCounter += 1
        var runId = "run-" + stationId + "-" + window.moduleRunCounter + "-" + Date.now()
        var stInputJson = window.buildStationSessionInputJson(stationId)
        window.sessionInputJsonPreview = stInputJson

        var updated = Object.assign({}, arr[moduleIdx])
        updated.enabled = true
        updated.activeRunId = runId
        updated.status = "running"
        updated.inputJson = stInputJson
        arr[moduleIdx] = updated
        mapCopy[stationId] = arr
        window.stationFactorModulesMap = mapCopy

        pythonModuleRunner.runModuleAsync(runId, updated.path, stInputJson)
    }

    function recorrelateStationFactors(stationId) {
        if (!stationId || !window.currentPlanningSession) return
        var cIdx = window.findStationCorrelationIndex(stationId)
        var arr = window.stationFactorModulesMap[stationId] || []

        var enabledIndices = []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i].enabled === true) {
                enabledIndices.push(i)
            }
        }

        if (enabledIndices.length === 0) {
            if (cIdx >= 0) {
                stationCorrelationModel.setProperty(cIdx, "status", "ready")
                stationCorrelationModel.setProperty(cIdx, "peakAttenuationDb", 0.0)
                stationCorrelationModel.setProperty(cIdx, "meanAttenuationDb", 0.0)
            }
            window.applyCorrelationAttenuationToGraph()
            return
        }

        var needFactorRun = false
        for (var k = 0; k < enabledIndices.length; k++) {
            var mIdx = enabledIndices[k]
            var mod = arr[mIdx]
            if (!mod.outputJson || mod.outputJson.length === 0 || mod.status === "error") {
                needFactorRun = true
                if (mod.status !== "running") {
                    window.runStationFactorModule(stationId, mIdx)
                }
            }
        }

        if (needFactorRun) {
            if (cIdx >= 0) {
                stationCorrelationModel.setProperty(cIdx, "status", "running")
            }
        } else if (cIdx >= 0) {
            window.executeStationCorrelationNow(cIdx)
        }
    }

    function toggleStationFactorModule(stationId, moduleIdx, enabledState) {
        if (!stationId) return
        var mapCopy = Object.assign({}, window.stationFactorModulesMap)
        var arr = (mapCopy[stationId] || []).slice()
        if (moduleIdx < 0 || moduleIdx >= arr.length) return
        var updated = Object.assign({}, arr[moduleIdx])
        updated.enabled = enabledState
        arr[moduleIdx] = updated
        mapCopy[stationId] = arr
        window.stationFactorModulesMap = mapCopy

        window.recorrelateStationFactors(stationId)
    }

    function recorrelateEnabledFactors() {
        if (!window.currentPlanningSession) return
        for (var c = 0; c < stationCorrelationModel.count; c++) {
            var stId = stationCorrelationModel.get(c).stationId
            window.recorrelateStationFactors(stId)
        }
    }

    function toggleFactorModuleAtIndex(idx, enabledState) {
        if (idx < 0 || idx >= addedPythonModulesModel.count) return
        addedPythonModulesModel.setProperty(idx, "enabled", enabledState)
        window.recorrelateEnabledFactors()
    }

    function predictStationAttenuationAtIndex(stationIdx) {
        if (stationIdx < 0 || stationIdx >= stationCorrelationModel.count) return
        if (!window.currentPlanningSession) return
        var stId = stationCorrelationModel.get(stationIdx).stationId
        var arr = window.stationFactorModulesMap[stId] || []

        var anyEnabled = false
        for (var e = 0; e < arr.length; e++) {
            if (arr[e].enabled === true) {
                anyEnabled = true
                break
            }
        }
        if (!anyEnabled && arr.length > 0) {
            window.toggleStationFactorModule(stId, 0, true)
            return
        }
        window.recorrelateStationFactors(stId)
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
            enabled: false,
            status: "ready",
            activeRunId: "",
            outputJson: "",
            errorText: "",
            factorName: "",
            units: "",
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

        addedPythonModulesModel.setProperty(idx, "enabled", true)
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
                if (idx === 0) {
                    window.updateLiveSatellitePositions()
                } else if (idx === 1 && (!window.planningPassResult || window.planningPassResult.passes.length === 0)) {
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
                        var cachedSt = (window.stationsList && i < window.stationsList.length) ? window.stationsList[i] : null
                        if (cachedSt && cachedSt.stationId === stId) {
                            stationsModel.setProperty(i, "active", active)
                            break
                        }
                    }
                    window.syncStationsCache()
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
                satellitesList: window.satellitesList
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
                stationsList: window.stationsList
                stationsMap: window.stationsMap
                satellitesModel: satellitesModel
                satellitesList: window.satellitesList
                satellitesMap: window.satellitesMap
                satelliteTracksMap: window.satelliteTracksMap
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
                targetSatelliteData: {
                    var _v = window.satelliteConfigVersion
                    var _sid = window.selectedSatelliteId
                    return window.getSelectedSatellite()
                }
                stationsModel: stationsModel
                stationsList: window.stationsList
                stationsMap: window.stationsMap
                lightMode: window.lightMode

                addedModulesModel: addedPythonModulesModel
                stationFactorModulesMap: window.stationFactorModulesMap
                recentModulesList: window.recentModulesList
                pythonEnvInfo: window.pythonEnvInfo
                sessionInputJsonPreview: window.sessionInputJsonPreview

                stationCorrelationModel: stationCorrelationModel
                recentCorrelationModulesList: window.recentCorrelationModulesList
                recentExcelFilesList: window.recentExcelFilesList
                selectedCorrelationModulePath: window.selectedCorrelationModulePath
                selectedExcelFilePath: window.selectedExcelFilePath

                onEditTargetSatelliteConfigRequested: {
                    var sat = window.getSelectedSatellite()
                    if (sat) {
                        satelliteDialog.openForEdit(sat)
                    } else {
                        satelliteDialog.openForNew()
                    }
                }

                onEditGroundStationConfigRequested: (stationId) => {
                    if (window.stationsMap && window.stationsMap[stationId]) {
                        window.startEditStation(window.stationsMap[stationId])
                        return
                    }
                    for (var i = 0; i < window.stationsList.length; i++) {
                        var st = window.stationsList[i]
                        if (st.stationId === stationId || st.name === stationId) {
                            window.startEditStation(st)
                            return
                        }
                    }
                }

                onBrowseStationModuleRequested: (stationId) => {
                    var selectedPath = pythonModuleRunner.selectPythonModuleDialog()
                    if (selectedPath && selectedPath.length > 0) {
                        window.addFactorModuleToStation(stationId, selectedPath)
                    }
                }

                onAddRecentStationModuleRequested: (stationId, modulePath) => {
                    window.addFactorModuleToStation(stationId, modulePath)
                }

                onRemoveStationModuleRequested: (stationId, moduleIdx) => {
                    window.removeFactorModuleFromStation(stationId, moduleIdx)
                }

                onToggleStationModuleEnabledRequested: (stationId, moduleIdx, enabled) => {
                    window.toggleStationFactorModule(stationId, moduleIdx, enabled)
                }

                onRunStationModuleRequested: (stationId, moduleIdx) => {
                    window.runStationFactorModule(stationId, moduleIdx)
                }

                onPreviewStationInputJsonRequested: (stationId, stationName) => {
                    var stJson = window.buildStationSessionInputJson(stationId)
                    var passIdx = window.currentPlanningSession ? (window.currentPlanningSession.passIndex || 1) : 1
                    sessionPlanYamlViewer.openForJson(
                        qsTr("Station Session Input JSON — ") + stationName,
                        qsTr("Per-station session prediction payload (Pass #") + passIdx + ")",
                        stJson,
                        "station_input_" + (stationId || "station") + "_pass_" + passIdx + ".json"
                    )
                }

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
                        var wasEnabled = addedPythonModulesModel.get(idx).enabled === true
                        var runId = addedPythonModulesModel.get(idx).activeRunId
                        if (runId && runId.length > 0) {
                            pythonModuleRunner.cancelModuleRun(runId)
                        }
                        addedPythonModulesModel.remove(idx)
                        if (wasEnabled) {
                            window.recorrelateEnabledFactors()
                        }
                    }
                }

                onToggleModuleEnabledRequested: (idx, enabled) => {
                    window.toggleFactorModuleAtIndex(idx, enabled)
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

                onPreviewJsonModalRequested: (docTitle, subtitle, jsonText, suggestedFileName) => {
                    sessionPlanYamlViewer.openForJson(docTitle, subtitle, jsonText, suggestedFileName)
                }

                onBrowseCorrelationModuleRequested: {
                    var corrPath = pythonModuleRunner.selectPythonModuleDialog()
                    if (corrPath && corrPath.length > 0) {
                        window.recentCorrelationModulesList = pythonModuleRunner.addRecentCorrelationModule(corrPath)
                        window.selectedCorrelationModulePath = corrPath
                        window.recorrelateEnabledFactors()
                    }
                }

                onCorrelationModuleSelected: (modulePath) => {
                    window.selectedCorrelationModulePath = modulePath
                    window.recentCorrelationModulesList = pythonModuleRunner.addRecentCorrelationModule(modulePath)
                    window.recorrelateEnabledFactors()
                }

                onBrowseExcelFileRequested: {
                    var exPath = pythonModuleRunner.selectExcelFileDialog()
                    if (exPath && exPath.length > 0) {
                        window.recentExcelFilesList = pythonModuleRunner.addRecentExcelFile(exPath)
                        window.selectedExcelFilePath = exPath
                        window.recorrelateEnabledFactors()
                    }
                }

                onExcelFileSelected: (excelPath) => {
                    window.selectedExcelFilePath = excelPath
                    window.recentExcelFilesList = pythonModuleRunner.addRecentExcelFile(excelPath)
                    window.recorrelateEnabledFactors()
                }

                onPredictStationAttenuationRequested: (stationIdx) => {
                    window.predictStationAttenuationAtIndex(stationIdx)
                }

                onPredictAllStationsAttenuationRequested: {
                    window.predictAllStationsAttenuation()
                }

                onPreviewSessionPlanYamlRequested: (params) => {
                    if (!window.currentPlanningSession || !window.planningSnrData) {
                        toastStack.showToast(qsTr("No active pass session data to generate plan"), "error")
                        return
                    }
                    var yaml = propagator.generateSessionPlanYaml(window.currentPlanningSession, window.planningSnrData, params)
                    var defaultName = "session_plan_pass_" + (window.currentPlanningSession.passIndex || 1) + ".yaml"
                    var subtitle = (window.currentPlanningSession.satelliteName || "Satellite") + " - Pass #" + (window.currentPlanningSession.passIndex || 1)
                    sessionPlanYamlViewer.openForYaml(subtitle, yaml, defaultName)
                }

                onExportSessionPlanYamlRequested: (params) => {
                    if (!window.currentPlanningSession || !window.planningSnrData) {
                        toastStack.showToast(qsTr("No active pass session data to generate plan"), "error")
                        return
                    }
                    var yaml = propagator.generateSessionPlanYaml(window.currentPlanningSession, window.planningSnrData, params)
                    var defaultName = (window.currentPlanningSession ? ("session_plan_pass_" + window.currentPlanningSession.passIndex + ".yaml") : "session_plan.yaml")
                    var path = stationManager.saveFileDialog(qsTr("Export Session Plan YAML"), defaultName, "YAML Files (*.yaml *.yml)")
                    if (path && path.length > 0) {
                        var ok = stationManager.writeTextFile(path, yaml)
                        if (ok) {
                            toastStack.showToast(qsTr("Session Plan saved to: ") + path, "success")
                        } else {
                            toastStack.showToast(qsTr("Failed to save session plan file"), "error")
                        }
                    }
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
        id: toastStack
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
                var cleanSt = {
                    stationId: String(saved[s].stationId || ("GS-0" + (s + 1))),
                    name: String(saved[s].name || ("Station " + (s + 1))),
                    latitude: Number(saved[s].latitude) || 0.0,
                    longitude: Number(saved[s].longitude) || 0.0,
                    altitude: Number(saved[s].altitude) || 0.0,
                    altitudeSpecified: saved[s].altitudeSpecified !== false,
                    mobility: String(saved[s].mobility || "Stationary"),
                    minElevation: Number(saved[s].minElevation) || 5.0,
                    operatingBand: String(saved[s].operatingBand || "C-band"),
                    polarization: String(saved[s].polarization || "RHCP"),
                    antennaGain: Number(saved[s].antennaGain) || 38.5,
                    lnaNf: Number(saved[s].lnaNf) || 0.70,
                    feederLoss: Number(saved[s].feederLoss) || 0.30,
                    freqMinMhz: Number(saved[s].freqMinMhz) || 4000.0,
                    freqMaxMhz: Number(saved[s].freqMaxMhz) || 8000.0,
                    maxChannelWidthMhz: Number(saved[s].maxChannelWidthMhz) || 4000.0,
                    totalNoiseFigureDb: Number(saved[s].totalNoiseFigureDb) || 1.0,
                    systemNoiseTempK: Number(saved[s].systemNoiseTempK) || 125.1,
                    gOverT: Number(saved[s].gOverT) || 17.53,
                    stationJson: String(saved[s].stationJson || ""),
                    active: saved[s].active !== false
                }
                stationsModel.append(cleanSt)
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

        var initialTracksMap = {}
        // Initial Sample Satellite (ISS) - Live NORAD TLE Elements
        var issL1 = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994"
        var issL2 = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665"
        var prop = propagator.propagateTle(issL1, issL2, 0.0)
        if (prop.valid) {
            var tracks = propagator.computeOrbitTracks(issL1, issL2, 0.75)
            initialTracksMap["SAT-01"] = tracks
            satellitesModel.append({
                satId: "SAT-01",
                name: "ISS (ZARYA)",
                tle1: issL1,
                tle2: issL2,
                carrierFreqMhz: 5850.0,
                channelBandwidthKhz: 20000.0,
                modulation: "OQPSK",
                bitsPerSymbol: 2.0,
                codeEfficiencyCoef: 1.24,
                rolloffAlpha: 0.35,
                txPowerDbm: 33.0,
                txAntennaGainDbi: 3.0,
                codeRateTable: [
                    { name: "R1", rate: 0.910, hw: "0" },
                    { name: "R2", rate: 0.830, hw: "1" },
                    { name: "R3", rate: 0.700, hw: "2" },
                    { name: "R4", rate: 0.570, hw: "3" },
                    { name: "R5", rate: 0.410, hw: "4" },
                    { name: "R6", rate: 0.285, hw: "5" },
                    { name: "R7", rate: 0.190, hw: "6" }
                ],
                codeRateRegister: "fpgatrx/code_rate",
                latitude: prop.latitude,
                longitude: prop.longitude,
                altitudeKm: prop.altitudeKm,
                visibilityRadiusMeters: prop.visibilityRadiusMeters,
                velocityKmS: prop.velocityKmS || 0
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
            initialTracksMap["SAT-02"] = tracksPoly
            satellitesModel.append({
                satId: "SAT-02",
                name: "POLYITAN-3-PUT (LEO)",
                tle1: polyL1,
                tle2: polyL2,
                carrierFreqMhz: 5840.0,
                channelBandwidthKhz: 10000.0,
                modulation: "QPSK",
                bitsPerSymbol: 2.0,
                codeEfficiencyCoef: 1.00,
                rolloffAlpha: 0.20,
                txPowerDbm: 33.0,
                txAntennaGainDbi: 3.0,
                codeRateTable: [
                    { name: "R1", rate: 0.910, hw: "0" },
                    { name: "R2", rate: 0.830, hw: "1" },
                    { name: "R3", rate: 0.700, hw: "2" },
                    { name: "R4", rate: 0.570, hw: "3" },
                    { name: "R5", rate: 0.410, hw: "4" },
                    { name: "R6", rate: 0.285, hw: "5" },
                    { name: "R7", rate: 0.190, hw: "6" }
                ],
                codeRateRegister: "fpgatrx/code_rate",
                latitude: propPoly.latitude,
                longitude: propPoly.longitude,
                altitudeKm: propPoly.altitudeKm,
                visibilityRadiusMeters: propPoly.visibilityRadiusMeters,
                velocityKmS: propPoly.velocityKmS || 0
            })
        }
        window.satelliteTracksMap = initialTracksMap
        window.syncStationsCache()
        window.syncSatellitesCache()

        // Set initial historical observation
        if (historyModel.count > 0) {
            window.currentHistoricalObservation = historyModel.get(0)
        }

        // Trigger initial future pass prediction
        window.calculateFuturePasses()
    }
}
