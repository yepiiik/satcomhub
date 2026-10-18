import QtQuick
import QtPositioning
import "MapUtils.js" as MapUtils

Item {
    id: root

    // Data models
    property var stationsModel: null
    property var satellitesModel: null

    // Selection state
    property string selectedStationId: ""
    property string selectedSatelliteId: ""

    // Operational parameters
    property real targetSatelliteAltitudeKm: 500.0 // Default LEO altitude (km)
    property real minElevationDeg: 5.0 // Operational elevation mask (standard 5 deg)
    property bool pickModeEnabled: false
    property string projectionMode: "mercator" // "mercator" or "equirectangular"

    // Draft marker state (new/unsaved station)
    property bool hasDraft: false
    property real draftLat: 0.0
    property real draftLon: 0.0
    property real draftAlt: 0.0
    property string draftName: ""

    // Public Signals
    signal markerSelected(string stationId, string stationName)
    signal satelliteSelected(string satId, string satName)
    signal coordinatePicked(real latitude, real longitude)

    // Forwarded utility calculation methods
    function calculateStationSatVisibilityRadius(satAltKm, elevationDeg) {
        return MapUtils.calculateStationSatVisibilityRadius(
            satAltKm,
            elevationDeg,
            root.targetSatelliteAltitudeKm,
            root.minElevationDeg
        )
    }

    function calculateVisibilityRadius(altitudeMeters) {
        return calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, root.minElevationDeg)
    }

    function lonToX(lon, totalWidth) { return MapUtils.lonToX(lon, totalWidth) }
    function latToY(lat, totalHeight) { return MapUtils.latToY(lat, totalHeight) }
    function xToLon(x, totalWidth) { return MapUtils.xToLon(x, totalWidth) }
    function yToLat(y, totalHeight) { return MapUtils.yToLat(y, totalHeight) }

    function generateGeodesicPolygons(centerLat, centerLon, radiusMeters, numPoints) {
        return MapUtils.generateGeodesicPolygons(centerLat, centerLon, radiusMeters, numPoints, QtPositioning)
    }

    function generateGeodesicCoordinates(centerLat, centerLon, radiusMeters, numPoints) {
        var polys = generateGeodesicPolygons(centerLat, centerLon, radiusMeters, numPoints)
        return polys.length > 0 ? polys[0] : []
    }

    function setDraftMarker(latitude, longitude, altitude, stationName) {
        draftLat = latitude
        draftLon = longitude
        draftAlt = altitude
        draftName = stationName || "New Station (Unsaved)"
        hasDraft = true
        requestCanvasRedraw()
    }

    function removeDraftMarker() {
        hasDraft = false
        requestCanvasRedraw()
    }

    function focusOnCoordinate(latitude, longitude, zoom) {
        if (projectionMode === "mercator") {
            mercatorView.focusOnCoordinate(latitude, longitude, zoom)
        } else {
            equiView.focusOnCoordinate(latitude, longitude)
        }
    }

    function requestCanvasRedraw() {
        if (projectionMode === "equirectangular") {
            equiView.requestCanvasRedraw()
        }
    }

    // 1. Mercator / OpenStreetMap View
    MercatorMapView {
        id: mercatorView
        visible: root.projectionMode === "mercator"
        stationsModel: root.stationsModel
        satellitesModel: root.satellitesModel
        selectedStationId: root.selectedStationId
        selectedSatelliteId: root.selectedSatelliteId
        targetSatelliteAltitudeKm: root.targetSatelliteAltitudeKm
        minElevationDeg: root.minElevationDeg
        pickModeEnabled: root.pickModeEnabled
        hasDraft: root.hasDraft
        draftLat: root.draftLat
        draftLon: root.draftLon
        draftAlt: root.draftAlt
        draftName: root.draftName

        onMarkerSelected: (id, name) => root.markerSelected(id, name)
        onSatelliteSelected: (id, name) => root.satelliteSelected(id, name)
        onCoordinatePicked: (lat, lon) => root.coordinatePicked(lat, lon)
    }

    // 2. Equirectangular / Plate Carrée View
    EquirectangularMapView {
        id: equiView
        visible: root.projectionMode === "equirectangular"
        stationsModel: root.stationsModel
        satellitesModel: root.satellitesModel
        selectedStationId: root.selectedStationId
        selectedSatelliteId: root.selectedSatelliteId
        targetSatelliteAltitudeKm: root.targetSatelliteAltitudeKm
        minElevationDeg: root.minElevationDeg
        pickModeEnabled: root.pickModeEnabled
        hasDraft: root.hasDraft
        draftLat: root.draftLat
        draftLon: root.draftLon
        draftAlt: root.draftAlt
        draftName: root.draftName

        onMarkerSelected: (id, name) => root.markerSelected(id, name)
        onSatelliteSelected: (id, name) => root.satelliteSelected(id, name)
        onCoordinatePicked: (lat, lon) => root.coordinatePicked(lat, lon)
    }

    // 3. Floating Overlay Controls (Projection switcher, Pick banner, Zoom buttons)
    MapControlsOverlay {
        id: controlsOverlay
        projectionMode: root.projectionMode
        pickModeEnabled: root.pickModeEnabled

        onProjectionSelected: (mode) => {
            root.projectionMode = mode
            root.requestCanvasRedraw()
        }

        onZoomInRequested: () => {
            if (root.projectionMode === "mercator") {
                mercatorView.zoomIn()
            } else {
                equiView.zoomIn()
            }
        }

        onZoomOutRequested: () => {
            if (root.projectionMode === "mercator") {
                mercatorView.zoomOut()
            } else {
                equiView.zoomOut()
            }
        }
    }
}
