import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtLocation
import QtPositioning
import satcomhub

Item {
    id: root

    property var stationsModel: null
    property var satellitesModel: null
    property string selectedStationId: ""
    property string selectedSatelliteId: ""
    property real targetSatelliteAltitudeKm: 500.0 // Default LEO altitude (km)
    property real minElevationDeg: 5.0 // Operational elevation mask (standard 5 deg)
    property bool pickModeEnabled: false

    property string projectionMode: "mercator"

    // Draft marker state
    property bool hasDraft: false
    property real draftLat: 0
    property real draftLon: 0
    property real draftAlt: 0
    property string draftName: ""

    signal markerSelected(string stationId, string stationName)
    signal satelliteSelected(string satId, string satName)
    signal coordinatePicked(real latitude, real longitude)

    readonly property real earthRadiusMeters: 6371000.0

    // Satellite Line-of-Sight Visibility Radius on Earth surface (in meters)
    // Formula: R_E * [ arccos( (R_E / (R_E + h_sat)) * cos(minElevation) ) - minElevation ]
    function calculateStationSatVisibilityRadius(satAltKm, elevationDeg) {
        var h = Math.max(50.0, parseFloat(satAltKm) || root.targetSatelliteAltitudeKm)
        var el = (elevationDeg !== undefined ? elevationDeg : root.minElevationDeg) * (Math.PI / 180.0)
        var rSat = (earthRadiusMeters / 1000.0) + h

        var cosArg = ((earthRadiusMeters / 1000.0) / rSat) * Math.cos(el)
        if (cosArg > 1.0) cosArg = 1.0
        if (cosArg < -1.0) cosArg = -1.0

        var theta = Math.acos(cosArg) - el
        if (theta < 0.0) theta = 0.0

        return earthRadiusMeters * theta
    }

    function calculateVisibilityRadius(altitudeMeters) {
        return calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, root.minElevationDeg)
    }

    function generateGeodesicCoordinates(centerLat, centerLon, radiusMeters, numPoints) {
        var coords = []
        var n = numPoints || 64
        var d = radiusMeters / earthRadiusMeters
        var lat1 = centerLat * Math.PI / 180.0
        var lon1 = centerLon * Math.PI / 180.0

        for (var i = 0; i < n; i++) {
            var bearing = (2.0 * Math.PI * i) / n
            var lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearing))
            var lon2 = lon1 + Math.atan2(Math.sin(bearing) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2))

            var lonDeg = (lon2 * 180.0 / Math.PI + 540.0) % 360.0 - 180.0
            var latDeg = lat2 * 180.0 / Math.PI

            coords.push(QtPositioning.coordinate(latDeg, lonDeg))
        }
        return coords
    }

    function lonToX(lon, totalWidth) {
        return ((lon + 180.0) / 360.0) * totalWidth
    }

    function latToY(lat, totalHeight) {
        return ((90.0 - lat) / 180.0) * totalHeight
    }

    function xToLon(x, totalWidth) {
        return (x / totalWidth) * 360.0 - 180.0
    }

    function yToLat(y, totalHeight) {
        return 90.0 - (y / totalHeight) * 180.0
    }

    function setDraftMarker(latitude, longitude, altitude, stationName) {
        draftLat = latitude
        draftLon = longitude
        draftAlt = altitude
        draftName = stationName || "New Station (Unsaved)"
        hasDraft = true
        if (projectionMode === "equirectangular") {
            equiFootprintCanvas.requestPaint()
        }
    }

    function removeDraftMarker() {
        hasDraft = false
        if (projectionMode === "equirectangular") {
            equiFootprintCanvas.requestPaint()
        }
    }

    function focusOnCoordinate(latitude, longitude, zoom) {
        if (projectionMode === "mercator") {
            osmMap.center = QtPositioning.coordinate(latitude, longitude)
            if (zoom !== undefined && zoom !== null) {
                osmMap.zoomLevel = zoom
            }
        } else {
            var targetContentX = lonToX(longitude, equiMapImage.width) * equiZoomScale - equiFlickable.width / 2
            var targetContentY = latToY(latitude, equiMapImage.height) * equiZoomScale - equiFlickable.height / 2

            equiFlickable.contentX = Math.max(0, Math.min(equiContainer.width - equiFlickable.width, targetContentX))
            equiFlickable.contentY = Math.max(0, Math.min(equiContainer.height - equiFlickable.height, targetContentY))
        }
    }

    function requestCanvasRedraw() {
        if (projectionMode === "equirectangular") {
            equiFootprintCanvas.requestPaint()
        }
    }

    // =========================================================================
    // 1. OPENSTREETMAP (MERCATOR PROJECTION)
    // =========================================================================
    Item {
        id: mercatorView
        anchors.fill: parent
        visible: root.projectionMode === "mercator"

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

            // Station Visibility Footprints (MapPolygon)
            MapItemView {
                model: root.stationsModel
                delegate: MapPolygon {
                    property bool isSelected: root.selectedStationId === model.stationId
                    property real rad: root.calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, model.minElevation !== undefined ? model.minElevation : root.minElevationDeg)

                    path: rad > 0 ? root.generateGeodesicCoordinates(model.latitude, model.longitude, rad, 48) : []
                    color: isSelected ? "#33228be6" : "#1a228be6"
                    border.color: isSelected ? "#228be6" : "#74c0fc"
                    border.width: isSelected ? 2 : 1
                    opacity: 0.85
                    visible: rad > 0
                }
            }

            // Satellite Visibility Footprints (Ground Horizon Entrance/Exit Coverage)
            MapItemView {
                model: root.satellitesModel
                delegate: MapPolygon {
                    property bool isSelected: root.selectedSatelliteId === model.satId
                    property real rad: model.visibilityRadiusMeters !== undefined ? model.visibilityRadiusMeters : 0

                    path: rad > 0 ? root.generateGeodesicCoordinates(model.latitude, model.longitude, rad, 64) : []
                    color: isSelected ? "#33f59f00" : "#1af59f00"
                    border.color: isSelected ? "#f59f00" : "#ffd43b"
                    border.width: isSelected ? 2 : 1
                    opacity: 0.9
                    visible: rad > 0
                }
            }

            // Satellite Ground Track Trajectories (MapPolyline)
            MapItemView {
                model: root.satellitesModel
                delegate: MapPolyline {
                    property bool isSelected: root.selectedSatelliteId === model.satId
                    line.width: isSelected ? 3 : 2
                    line.color: isSelected ? "#ffd43b" : "#fab005"
                    opacity: isSelected ? 0.95 : 0.75

                    path: {
                        var pts = []
                        if (model.trajectory) {
                            for (var t = 0; t < model.trajectory.length; t++) {
                                pts.push(QtPositioning.coordinate(model.trajectory[t].latitude, model.trajectory[t].longitude))
                            }
                        }
                        return pts
                    }
                }
            }

            // Station Markers
            MapItemView {
                model: root.stationsModel
                delegate: StationMarker {}
            }

            // Satellite Markers
            MapItemView {
                model: root.satellitesModel
                delegate: MapQuickItem {
                    id: satMarker
                    coordinate: QtPositioning.coordinate(model.latitude, model.longitude)
                    anchorPoint.x: 16
                    anchorPoint.y: 16
                    z: 25

                    sourceItem: Item {
                        width: 32
                        height: 32

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.selectedSatelliteId === model.satId ? 30 : 24
                            height: width
                            radius: width / 2
                            color: "#f59f00"
                            border.color: "#ffffff"
                            border.width: 2

                            Text {
                                anchors.centerIn: parent
                                text: "🛰️"
                                font.pixelSize: 13
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.top
                            anchors.bottomMargin: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitWidth: satBadgeText.implicitWidth + 10
                            implicitHeight: 20
                            radius: 4
                            color: "#1a1b1e"
                            border.color: "#f59f00"
                            border.width: 1

                            Text {
                                id: satBadgeText
                                anchors.centerIn: parent
                                text: model.name
                                color: "#ffffff"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.satelliteSelected(model.satId, model.name)
                        }
                    }
                }
            }

            // Draft Footprint Preview
            MapPolygon {
                id: draftPolygon
                visible: root.hasDraft && (root.calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, root.minElevationDeg) > 0)
                path: visible ? root.generateGeodesicCoordinates(root.draftLat, root.draftLon, root.calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, root.minElevationDeg), 48) : []
                color: "#33fa5252"
                border.color: "#fa5252"
                border.width: 2
                opacity: 0.85
            }

            // Draft Marker Preview
            MapQuickItem {
                id: draftQuickItem
                visible: root.hasDraft
                coordinate: QtPositioning.coordinate(root.draftLat, root.draftLon)
                anchorPoint.x: 18
                anchorPoint.y: 40
                z: 30

                sourceItem: Item {
                    width: 36
                    height: 44

                    Shape {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.samples: 4

                        ShapePath {
                            strokeWidth: 2
                            strokeColor: "#ffffff"
                            fillColor: "#fa5252"
                            joinStyle: ShapePath.RoundJoin

                            startX: 18
                            startY: 40

                            PathCubic { control1X: 13; control1Y: 33; control2X: 4; control2Y: 22; x: 4; y: 16 }
                            PathArc { x: 32; y: 16; radiusX: 14; radiusY: 14; useLargeArc: true }
                            PathCubic { control1X: 32; control1Y: 22; control2X: 23; control2Y: 33; x: 18; y: 40 }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 10
                        width: 10
                        height: 10
                        radius: 5
                        color: "#ffffff"
                    }

                    Rectangle {
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: draftBadgeText.implicitWidth + 12
                        implicitHeight: 22
                        radius: 4
                        color: "#1a1b1e"
                        border.color: "#fa5252"
                        border.width: 1

                        Text {
                            id: draftBadgeText
                            anchors.centerIn: parent
                            text: root.draftName
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }
            }

            MouseArea {
                id: osmMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.pickModeEnabled ? Qt.CrossCursor : Qt.ArrowCursor

                onPositionChanged: (mouse) => osmMap.lastMousePos = Qt.point(mouse.x, mouse.y)

                onClicked: (mouse) => {
                    if (root.pickModeEnabled) {
                        var coord = osmMap.toCoordinate(Qt.point(mouse.x, mouse.y))
                        root.coordinatePicked(coord.latitude, coord.longitude)
                    }
                }
            }

            PinchHandler {
                id: osmPinch
                target: null
                enabled: !root.pickModeEnabled
                onActiveChanged: if (active) {
                    osmMap.startCentroid = osmMap.toCoordinate(osmPinch.centroid.position, false)
                }
                onScaleChanged: (delta) => {
                    osmMap.zoomLevel += Math.log2(delta)
                    osmMap.alignCoordinateToPoint(osmMap.startCentroid, osmPinch.centroid.position)
                }
            }

            WheelHandler {
                id: osmWheel
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                rotationScale: 1 / 120

                onWheel: (event) => {
                    var coordBefore = osmMap.toCoordinate(osmMap.lastMousePos)
                    var zoomChange = (event.angleDelta.y / 120) * 0.5
                    osmMap.zoomLevel = Math.max(3, Math.min(20, osmMap.zoomLevel + zoomChange))
                    var coordAfter = osmMap.toCoordinate(osmMap.lastMousePos)

                    osmMap.center = QtPositioning.coordinate(
                        osmMap.center.latitude + (coordBefore.latitude - coordAfter.latitude),
                        osmMap.center.longitude + (coordBefore.longitude - coordAfter.longitude)
                    )
                }
            }

            DragHandler {
                id: osmDrag
                target: null
                onTranslationChanged: (delta) => osmMap.pan(-delta.x, -delta.y)
            }
        }
    }

    // =========================================================================
    // 2. EQUIRECTANGULAR / PLATE CARRÉE (GPREDICT PROJECTION)
    // =========================================================================
    Item {
        id: equirectangularView
        anchors.fill: parent
        visible: root.projectionMode === "equirectangular"
        clip: true

        property real equiZoomScale: 1.0

        Flickable {
            id: equiFlickable
            anchors.fill: parent
            contentWidth: equiContainer.width
            contentHeight: equiContainer.height
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: equiContainer
                width: equiMapImage.width * equirectangularView.equiZoomScale
                height: equiMapImage.height * equirectangularView.equiZoomScale

                Item {
                    id: equiScaledContent
                    width: equiMapImage.width
                    height: equiMapImage.height
                    scale: equirectangularView.equiZoomScale
                    transformOrigin: Item.TopLeft

                    Image {
                        id: equiMapImage
                        source: "qrc:/qt/qml/satcomhub/resources/earth_equirectangular.jpg"
                        width: 2048
                        height: 1024
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: true
                    }

                    // Coordinate Grid Overlay (30 deg lines)
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.12)"
                            ctx.lineWidth = 1

                            for (var lon = -180; lon <= 180; lon += 30) {
                                var x = root.lonToX(lon, width)
                                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                            }
                            for (var lat = -90; lat <= 90; lat += 30) {
                                var y = root.latToY(lat, height)
                                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                            }
                            ctx.strokeStyle = "rgba(34, 139, 230, 0.35)"
                            ctx.lineWidth = 1.5
                            var eqY = root.latToY(0, height)
                            ctx.beginPath(); ctx.moveTo(0, eqY); ctx.lineTo(width, eqY); ctx.stroke()
                        }
                    }

                    // Equirectangular Canvas (Station Footprints, Satellite Trajectories, and Satellite Footprints)
                    Canvas {
                        id: equiFootprintCanvas
                        anchors.fill: parent

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)

                            // 1. Station Footprints
                            if (root.stationsModel) {
                                for (var i = 0; i < root.stationsModel.count; i++) {
                                    var item = root.stationsModel.get(i)
                                    var rad = root.calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, item.minElevation !== undefined ? item.minElevation : root.minElevationDeg)
                                    if (rad <= 0) continue

                                    var isSel = (root.selectedStationId === item.stationId)
                                    var coords = root.generateGeodesicCoordinates(item.latitude, item.longitude, rad, 64)
                                    if (coords.length < 3) continue

                                    ctx.beginPath()
                                    ctx.moveTo(root.lonToX(coords[0].longitude, width), root.latToY(coords[0].latitude, height))
                                    for (var p = 1; p < coords.length; p++) {
                                        ctx.lineTo(root.lonToX(coords[p].longitude, width), root.latToY(coords[p].latitude, height))
                                    }
                                    ctx.closePath()

                                    ctx.fillStyle = isSel ? "rgba(34, 139, 230, 0.28)" : "rgba(34, 139, 230, 0.14)"
                                    ctx.fill()
                                    ctx.strokeStyle = isSel ? "#228be6" : "#74c0fc"
                                    ctx.lineWidth = isSel ? 2 : 1
                                    ctx.stroke()
                                }
                            }

                            // 2. Satellite Trajectories & Footprints
                            if (root.satellitesModel) {
                                for (var s = 0; s < root.satellitesModel.count; s++) {
                                    var sat = root.satellitesModel.get(s)
                                    var isSatSel = (root.selectedSatelliteId === sat.satId)

                                    // Draw Ground Track Trajectory Curve
                                    if (sat.trajectory && sat.trajectory.length > 1) {
                                        ctx.beginPath()
                                        ctx.strokeStyle = isSatSel ? "#ffd43b" : "#fab005"
                                        ctx.lineWidth = isSatSel ? 2.5 : 1.5

                                        for (var tp = 0; tp < sat.trajectory.length; tp++) {
                                            var tx = root.lonToX(sat.trajectory[tp].longitude, width)
                                            var ty = root.latToY(sat.trajectory[tp].latitude, height)
                                            if (tp === 0 || Math.abs(sat.trajectory[tp].longitude - sat.trajectory[tp - 1].longitude) > 180) {
                                                ctx.moveTo(tx, ty)
                                            } else {
                                                ctx.lineTo(tx, ty)
                                            }
                                        }
                                        ctx.stroke()
                                    }

                                    // Draw Satellite Visibility Footprint Ellipse (Horizon Entrance/Exit)
                                    if (sat.visibilityRadiusMeters > 0) {
                                        var satCoords = root.generateGeodesicCoordinates(sat.latitude, sat.longitude, sat.visibilityRadiusMeters, 64)
                                        if (satCoords.length >= 3) {
                                            ctx.beginPath()
                                            ctx.moveTo(root.lonToX(satCoords[0].longitude, width), root.latToY(satCoords[0].latitude, height))
                                            for (var sp = 1; sp < satCoords.length; sp++) {
                                                ctx.lineTo(root.lonToX(satCoords[sp].longitude, width), root.latToY(satCoords[sp].latitude, height))
                                            }
                                            ctx.closePath()

                                            ctx.fillStyle = isSatSel ? "rgba(245, 159, 0, 0.28)" : "rgba(245, 159, 0, 0.14)"
                                            ctx.fill()
                                            ctx.strokeStyle = isSatSel ? "#f59f00" : "#ffd43b"
                                            ctx.lineWidth = isSatSel ? 2 : 1
                                            ctx.stroke()
                                        }
                                    }
                                }
                            }

                            // 3. Draft Station Footprint
                            if (root.hasDraft) {
                                var draftRad = root.calculateStationSatVisibilityRadius(root.targetSatelliteAltitudeKm, root.minElevationDeg)
                                if (draftRad > 0) {
                                    var dcoords = root.generateGeodesicCoordinates(root.draftLat, root.draftLon, draftRad, 64)
                                    if (dcoords.length >= 3) {
                                        ctx.beginPath()
                                        ctx.moveTo(root.lonToX(dcoords[0].longitude, width), root.latToY(dcoords[0].latitude, height))
                                        for (var dp = 1; dp < dcoords.length; dp++) {
                                            ctx.lineTo(root.lonToX(dcoords[dp].longitude, width), root.latToY(dcoords[dp].latitude, height))
                                        }
                                        ctx.closePath()
                                        ctx.fillStyle = "rgba(250, 82, 82, 0.25)"
                                        ctx.fill()
                                        ctx.strokeStyle = "#fa5252"
                                        ctx.lineWidth = 2
                                        ctx.stroke()
                                    }
                                }
                            }
                        }
                    }

                    // Equirectangular Station Pins Repeater
                    Repeater {
                        model: root.stationsModel
                        delegate: Item {
                            x: root.lonToX(model.longitude, equiMapImage.width) - 18
                            y: root.latToY(model.latitude, equiMapImage.height) - 40
                            width: 36
                            height: 44
                            z: (root.selectedStationId === model.stationId) ? 20 : 10

                            Shape {
                                anchors.fill: parent
                                layer.enabled: true
                                layer.samples: 4

                                ShapePath {
                                    strokeWidth: 2
                                    strokeColor: "#ffffff"
                                    fillColor: (root.selectedStationId === model.stationId) ? "#fa5252" : "#228be6"
                                    joinStyle: ShapePath.RoundJoin

                                    startX: 18; startY: 40
                                    PathCubic { control1X: 13; control1Y: 33; control2X: 4; control2Y: 22; x: 4; y: 16 }
                                    PathArc { x: 32; y: 16; radiusX: 14; radiusY: 14; useLargeArc: true }
                                    PathCubic { control1X: 32; control1Y: 22; control2X: 23; control2Y: 33; x: 18; y: 40 }
                                }
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 10
                                width: 10; height: 10; radius: 5; color: "#ffffff"
                            }

                            Rectangle {
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: root.selectedStationId === model.stationId
                                implicitWidth: pinBadgeText.implicitWidth + 12
                                implicitHeight: 22
                                radius: 4
                                color: "#1a1b1e"
                                border.color: "#373a40"
                                border.width: 1

                                Text {
                                    id: pinBadgeText
                                    anchors.centerIn: parent
                                    text: model.name
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.markerSelected(model.stationId, model.name)
                            }
                        }
                    }

                    // Equirectangular Satellite Pins Repeater
                    Repeater {
                        model: root.satellitesModel
                        delegate: Item {
                            x: root.lonToX(model.longitude, equiMapImage.width) - 16
                            y: root.latToY(model.latitude, equiMapImage.height) - 16
                            width: 32
                            height: 32
                            z: 25

                            Rectangle {
                                anchors.centerIn: parent
                                width: root.selectedSatelliteId === model.satId ? 30 : 24
                                height: width
                                radius: width / 2
                                color: "#f59f00"
                                border.color: "#ffffff"
                                border.width: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: "🛰️"
                                    font.pixelSize: 13
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitWidth: equiSatBadgeText.implicitWidth + 10
                                implicitHeight: 20
                                radius: 4
                                color: "#1a1b1e"
                                border.color: "#f59f00"
                                border.width: 1

                                Text {
                                    id: equiSatBadgeText
                                    anchors.centerIn: parent
                                    text: model.name
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.satelliteSelected(model.satId, model.name)
                            }
                        }
                    }

                    // Equirectangular Draft Marker
                    Item {
                        visible: root.hasDraft
                        x: root.lonToX(root.draftLon, equiMapImage.width) - 18
                        y: root.latToY(root.draftLat, equiMapImage.height) - 40
                        width: 36
                        height: 44
                        z: 30

                        Shape {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.samples: 4

                            ShapePath {
                                strokeWidth: 2
                                strokeColor: "#ffffff"
                                fillColor: "#fa5252"
                                joinStyle: ShapePath.RoundJoin

                                startX: 18; startY: 40
                                PathCubic { control1X: 13; control1Y: 33; control2X: 4; control2Y: 22; x: 4; y: 16 }
                                PathArc { x: 32; y: 16; radiusX: 14; radiusY: 14; useLargeArc: true }
                                PathCubic { control1X: 32; control1Y: 22; control2X: 23; control2Y: 33; x: 18; y: 40 }
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            width: 10; height: 10; radius: 5; color: "#ffffff"
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: root.pickModeEnabled ? Qt.CrossCursor : Qt.ArrowCursor

                onClicked: (mouse) => {
                    if (root.pickModeEnabled) {
                        var contentX = (mouse.x + equiFlickable.contentX) / equirectangularView.equiZoomScale
                        var contentY = (mouse.y + equiFlickable.contentY) / equirectangularView.equiZoomScale

                        var lon = root.xToLon(contentX, equiMapImage.width)
                        var lat = root.yToLat(contentY, equiMapImage.height)

                        root.coordinatePicked(lat, lon)
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                rotationScale: 1 / 120

                onWheel: (event) => {
                    var zoomChange = (event.angleDelta.y / 120) * 0.25
                    equirectangularView.equiZoomScale = Math.max(0.6, Math.min(4.0, equirectangularView.equiZoomScale + zoomChange))
                    equiFootprintCanvas.requestPaint()
                }
            }
        }
    }

    onSelectedStationIdChanged: requestCanvasRedraw()
    onTargetSatelliteAltitudeKmChanged: requestCanvasRedraw()
    onSelectedSatelliteIdChanged: requestCanvasRedraw()
    onProjectionModeChanged: requestCanvasRedraw()

    // =========================================================================
    // FLOATING PROJECTION SWITCHER & CONTROLS
    // =========================================================================
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 16
        height: 40
        radius: 8
        color: "#1a1b1e"
        border.color: "#373a40"
        border.width: 1

        Row {
            anchors.centerIn: parent
            spacing: 4
            padding: 4

            Button {
                id: osmBtn
                height: 32
                text: "🗺️ Street View (OSM)"
                background: Rectangle {
                    radius: 6
                    color: root.projectionMode === "mercator" ? "#228be6" : "transparent"
                }
                contentItem: Text {
                    text: osmBtn.text
                    color: root.projectionMode === "mercator" ? "#ffffff" : "#adb5bd"
                    font.bold: root.projectionMode === "mercator"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.projectionMode = "mercator"
            }

            Button {
                id: equiBtn
                height: 32
                text: "🛰️ Orbital View (Equirectangular)"
                background: Rectangle {
                    radius: 6
                    color: root.projectionMode === "equirectangular" ? "#228be6" : "transparent"
                }
                contentItem: Text {
                    text: equiBtn.text
                    color: root.projectionMode === "equirectangular" ? "#ffffff" : "#adb5bd"
                    font.bold: root.projectionMode === "equirectangular"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                }
                onClicked: root.projectionMode = "equirectangular"
            }
        }
    }

    // Pick Mode Banner
    Rectangle {
        visible: root.pickModeEnabled
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 16
        radius: 20
        color: "#1c7ed6"
        implicitWidth: bannerRow.implicitWidth + 30
        implicitHeight: 38

        Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: "📍 Click anywhere on the map to place station"
                color: "#ffffff"
                font.bold: true
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Floating Zoom Buttons
    Column {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Button {
            text: "+"
            width: 38
            height: 38
            onClicked: {
                if (root.projectionMode === "mercator") {
                    osmMap.zoomLevel = Math.min(osmMap.zoomLevel + 1, 20)
                } else {
                    equirectangularView.equiZoomScale = Math.min(equirectangularView.equiZoomScale + 0.3, 4.0)
                    equiFootprintCanvas.requestPaint()
                }
            }
        }

        Button {
            text: "−"
            width: 38
            height: 38
            onClicked: {
                if (root.projectionMode === "mercator") {
                    osmMap.zoomLevel = Math.max(osmMap.zoomLevel - 1, 3)
                } else {
                    equirectangularView.equiZoomScale = Math.max(equirectangularView.equiZoomScale - 0.3, 0.6)
                    equiFootprintCanvas.requestPaint()
                }
            }
        }
    }
}
