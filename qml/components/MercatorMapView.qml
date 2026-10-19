import QtQuick
import QtLocation
import QtPositioning
import "MapUtils.js" as MapUtils

Item {
    id: mercatorView
    anchors.fill: parent

    property var stationsModel: null
    property var satellitesModel: null
    property string selectedStationId: ""
    property string selectedSatelliteId: ""
    property real targetSatelliteAltitudeKm: 500.0
    property real minElevationDeg: 5.0
    property bool pickModeEnabled: false

    property bool hasDraft: false
    property real draftLat: 0.0
    property real draftLon: 0.0
    property real draftAlt: 0.0
    property string draftName: ""

    signal markerSelected(string stationId, string stationName)
    signal satelliteSelected(string satId, string satName)
    signal coordinatePicked(real latitude, real longitude)

    function focusOnCoordinate(latitude, longitude, zoom) {
        osmMap.center = QtPositioning.coordinate(latitude, longitude)
        if (zoom !== undefined && zoom !== null) {
            osmMap.zoomLevel = zoom
        }
    }

    function zoomIn() {
        osmMap.zoomLevel = Math.min(osmMap.zoomLevel + 1, 20)
    }

    function zoomOut() {
        osmMap.zoomLevel = Math.max(osmMap.zoomLevel - 1, 3)
    }

    Plugin {
        id: osmPlugin
        name: "osm"
    }

    Map {
        id: osmMap
        plugin: osmPlugin
        anchors.fill: parent
        center: QtPositioning.coordinate(52.0, 19.0)
        zoomLevel: 6
        focus: true

        property point lastMousePos

        // Station Visibility Footprints (with Antimeridian Split Support)
        MapItemView {
            model: mercatorView.stationsModel
            delegate: MapItemGroup {
                id: stationFootprintGroup
                property bool isSelected: mercatorView.selectedStationId === model.stationId
                property real rad: MapUtils.calculateStationSatVisibilityRadius(
                    mercatorView.targetSatelliteAltitudeKm,
                    model.minElevation !== undefined ? model.minElevation : mercatorView.minElevationDeg,
                    mercatorView.targetSatelliteAltitudeKm,
                    mercatorView.minElevationDeg
                )
                property real lat: model.latitude !== undefined ? model.latitude : 0
                property real lon: model.longitude !== undefined ? model.longitude : 0

                property bool isActive: model.active !== false

                Repeater {
                    model: stationFootprintGroup.rad > 0 ? MapUtils.generateGeodesicPolygons(stationFootprintGroup.lat, stationFootprintGroup.lon, stationFootprintGroup.rad, 48, QtPositioning) : []
                    MapPolygon {
                        path: modelData
                        color: stationFootprintGroup.isSelected
                               ? "#33228be6"
                               : (stationFootprintGroup.isActive ? "#1a228be6" : "#0d868e96")
                        border.color: stationFootprintGroup.isSelected
                                      ? "#228be6"
                                      : (stationFootprintGroup.isActive ? "#74c0fc" : "#868e96")
                        border.width: stationFootprintGroup.isSelected ? 2 : 1
                        opacity: stationFootprintGroup.isActive ? 0.85 : 0.4
                    }
                }
            }
        }

        // Satellite Visibility Footprints (Ground Horizon Entrance/Exit Coverage)
        MapItemView {
            model: mercatorView.satellitesModel
            delegate: MapItemGroup {
                id: satFootprintGroup
                property bool isSelected: mercatorView.selectedSatelliteId === model.satId
                property real rad: model.visibilityRadiusMeters !== undefined ? model.visibilityRadiusMeters : 0
                property real lat: model.latitude !== undefined ? model.latitude : 0
                property real lon: model.longitude !== undefined ? model.longitude : 0

                Repeater {
                    model: satFootprintGroup.rad > 0 ? MapUtils.generateGeodesicPolygons(satFootprintGroup.lat, satFootprintGroup.lon, satFootprintGroup.rad, 64, QtPositioning) : []
                    MapPolygon {
                        path: modelData
                        color: satFootprintGroup.isSelected ? "#33f59f00" : "#1af59f00"
                        border.color: satFootprintGroup.isSelected ? "#f59f00" : "#ffd43b"
                        border.width: satFootprintGroup.isSelected ? 2 : 1
                        opacity: 0.9
                    }
                }
            }
        }

        // Satellite Ground Track Trajectories (previous 50%, current 100%, next 50%)
        MapItemView {
            model: mercatorView.satellitesModel
            delegate: MapItemGroup {
                id: trackGroup
                property bool isSelected: mercatorView.selectedSatelliteId === model.satId
                property var currentTraj: (typeof model !== "undefined" && model) ? model.trajectory : null
                property var prevTraj: (typeof model !== "undefined" && model) ? model.prevTrajectory : null
                property var nextTraj: (typeof model !== "undefined" && model) ? model.nextTrajectory : null

                // Previous Orbit Trajectory (50% opacity, dashed)
                Repeater {
                    model: MapUtils.buildDashedPolylineSegments(trackGroup.prevTraj, QtPositioning)
                    MapPolyline {
                        line.width: trackGroup.isSelected ? 2.5 : 1.5
                        line.color: trackGroup.isSelected ? "#ffd43b" : "#fab005"
                        opacity: 0.50
                        path: modelData
                    }
                }

                // Next Orbit Trajectory (50% opacity, dashed)
                Repeater {
                    model: MapUtils.buildDashedPolylineSegments(trackGroup.nextTraj, QtPositioning)
                    MapPolyline {
                        line.width: trackGroup.isSelected ? 2.5 : 1.5
                        line.color: trackGroup.isSelected ? "#ffd43b" : "#fab005"
                        opacity: 0.50
                        path: modelData
                    }
                }

                // Current Orbit Trajectory (100% opacity, dashed)
                Repeater {
                    model: MapUtils.buildDashedPolylineSegments(trackGroup.currentTraj, QtPositioning)
                    MapPolyline {
                        line.width: trackGroup.isSelected ? 3.0 : 2.0
                        line.color: trackGroup.isSelected ? "#ffd43b" : "#fab005"
                        opacity: 1.00
                        path: modelData
                    }
                }
            }
        }

        // Station Markers
        MapItemView {
            model: mercatorView.stationsModel
            delegate: StationMarker {}
        }

        // Satellite Markers
        MapItemView {
            model: mercatorView.satellitesModel
            delegate: SatelliteMarker {
                isSelected: mercatorView.selectedSatelliteId === model.satId
                onClicked: (id, name) => mercatorView.satelliteSelected(id, name)
            }
        }

        // Draft Station Footprint Preview
        MapItemGroup {
            id: draftPolygonGroup
            property real draftRad: MapUtils.calculateStationSatVisibilityRadius(
                mercatorView.targetSatelliteAltitudeKm,
                mercatorView.minElevationDeg,
                mercatorView.targetSatelliteAltitudeKm,
                mercatorView.minElevationDeg
            )
            visible: mercatorView.hasDraft && (draftRad > 0)
            Repeater {
                model: draftPolygonGroup.visible ? MapUtils.generateGeodesicPolygons(mercatorView.draftLat, mercatorView.draftLon, draftPolygonGroup.draftRad, 48, QtPositioning) : []
                MapPolygon {
                    path: modelData
                    color: "#33fa5252"
                    border.color: "#fa5252"
                    border.width: 2
                    opacity: 0.85
                }
            }
        }

        // Draft Station Marker Preview
        DraftStationMarker {
            visible: mercatorView.hasDraft
            draftLat: mercatorView.draftLat
            draftLon: mercatorView.draftLon
            draftName: mercatorView.draftName
        }

        MouseArea {
            id: osmMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: mercatorView.pickModeEnabled ? Qt.CrossCursor : Qt.ArrowCursor

            onPositionChanged: (mouse) => osmMap.lastMousePos = Qt.point(mouse.x, mouse.y)

            onClicked: (mouse) => {
                if (mercatorView.pickModeEnabled) {
                    var coord = osmMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                    mercatorView.coordinatePicked(coord.latitude, coord.longitude)
                }
            }
        }

        PinchHandler {
            id: osmPinch
            target: null
            enabled: !mercatorView.pickModeEnabled
            property var startCentroid: null

            onActiveChanged: if (active) {
                startCentroid = osmMap.toCoordinate(osmPinch.centroid.position, false)
            }
            onScaleChanged: (delta) => {
                osmMap.zoomLevel += Math.log2(delta)
                if (startCentroid && startCentroid.isValid) {
                    osmMap.alignCoordinateToPoint(startCentroid, osmPinch.centroid.position)
                }
            }
        }

        WheelHandler {
            id: osmWheel
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            rotationScale: 1 / 120

            onWheel: (event) => {
                var wheelPos = (event && event.point && event.point.position) ? event.point.position : osmMap.lastMousePos
                var coordBefore = osmMap.toCoordinate(wheelPos)
                var zoomChange = (event.angleDelta.y / 120) * 0.5
                osmMap.zoomLevel = Math.max(3, Math.min(20, osmMap.zoomLevel + zoomChange))
                var coordAfter = osmMap.toCoordinate(wheelPos)

                if (coordBefore && coordBefore.isValid && coordAfter && coordAfter.isValid) {
                    osmMap.center = QtPositioning.coordinate(
                        osmMap.center.latitude + (coordBefore.latitude - coordAfter.latitude),
                        osmMap.center.longitude + (coordBefore.longitude - coordAfter.longitude)
                    )
                }
            }
        }

        DragHandler {
            id: osmDrag
            target: null
            onTranslationChanged: (delta) => osmMap.pan(-delta.x, -delta.y)
        }
    }
}
