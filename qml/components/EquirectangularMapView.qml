import QtQuick
import QtQuick.Shapes
import "MapUtils.js" as MapUtils

Item {
    id: equirectangularView
    anchors.fill: parent
    clip: true

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

    property real equiZoomScale: 1.0

    signal markerSelected(string stationId, string stationName)
    signal satelliteSelected(string satId, string satName)
    signal coordinatePicked(real latitude, real longitude)

    function requestCanvasRedraw() {
        equiFootprintCanvas.requestPaint()
    }

    function zoomIn() {
        equiZoomScale = Math.min(equiZoomScale + 0.3, 4.0)
        equiFootprintCanvas.requestPaint()
    }

    function zoomOut() {
        equiZoomScale = Math.max(equiZoomScale - 0.3, 0.6)
        equiFootprintCanvas.requestPaint()
    }

    function focusOnCoordinate(latitude, longitude) {
        var targetContentX = MapUtils.lonToX(longitude, equiMapImage.width) * equiZoomScale - equiFlickable.width / 2
        var targetContentY = MapUtils.latToY(latitude, equiMapImage.height) * equiZoomScale - equiFlickable.height / 2

        equiFlickable.contentX = Math.max(0, Math.min(equiContainer.width - equiFlickable.width, targetContentX))
        equiFlickable.contentY = Math.max(0, Math.min(equiContainer.height - equiFlickable.height, targetContentY))
    }

    onSelectedStationIdChanged: equiFootprintCanvas.requestPaint()
    onSelectedSatelliteIdChanged: equiFootprintCanvas.requestPaint()
    onTargetSatelliteAltitudeKmChanged: equiFootprintCanvas.requestPaint()
    onHasDraftChanged: equiFootprintCanvas.requestPaint()
    onDraftLatChanged: equiFootprintCanvas.requestPaint()
    onDraftLonChanged: equiFootprintCanvas.requestPaint()

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
                            var x = MapUtils.lonToX(lon, width)
                            ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                        }
                        for (var lat = -90; lat <= 90; lat += 30) {
                            var y = MapUtils.latToY(lat, height)
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                        }
                        ctx.strokeStyle = "rgba(34, 139, 230, 0.35)"
                        ctx.lineWidth = 1.5
                        var eqY = MapUtils.latToY(0, height)
                        ctx.beginPath(); ctx.moveTo(0, eqY); ctx.lineTo(width, eqY); ctx.stroke()
                    }
                }

                // Footprint & Orbit Tracks Canvas
                Canvas {
                    id: equiFootprintCanvas
                    anchors.fill: parent

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        // 1. Station Footprints
                        if (equirectangularView.stationsModel) {
                            for (var i = 0; i < equirectangularView.stationsModel.count; i++) {
                                var item = equirectangularView.stationsModel.get(i)
                                var rad = MapUtils.calculateStationSatVisibilityRadius(
                                    equirectangularView.targetSatelliteAltitudeKm,
                                    item.minElevation !== undefined ? item.minElevation : equirectangularView.minElevationDeg,
                                    equirectangularView.targetSatelliteAltitudeKm,
                                    equirectangularView.minElevationDeg
                                )
                                if (rad <= 0) continue

                                var isSel = (equirectangularView.selectedStationId === item.stationId)
                                MapUtils.drawCanvasFootprint(
                                    ctx, item.latitude, item.longitude, rad,
                                    isSel ? "rgba(34, 139, 230, 0.28)" : "rgba(34, 139, 230, 0.14)",
                                    isSel ? "#228be6" : "#74c0fc",
                                    isSel ? 2 : 1,
                                    width, height
                                )
                            }
                        }

                        // 2. Satellite Trajectories & Footprints
                        if (equirectangularView.satellitesModel) {
                            for (var s = 0; s < equirectangularView.satellitesModel.count; s++) {
                                var sat = equirectangularView.satellitesModel.get(s)
                                var isSatSel = (equirectangularView.selectedSatelliteId === sat.satId)

                                function drawCanvasTrack(trackPts, strokeColor, lineWidth, dashArray) {
                                    var count = MapUtils.getTrajectoryCount(trackPts)
                                    if (count < 2) return
                                    ctx.save()
                                    ctx.beginPath()
                                    ctx.strokeStyle = strokeColor
                                    ctx.lineWidth = lineWidth
                                    if (ctx.setLineDash) {
                                        ctx.setLineDash(dashArray)
                                    }

                                    var prevLon = 0
                                    for (var tp = 0; tp < count; tp++) {
                                        var pt = MapUtils.getTrajectoryItem(trackPts, tp)
                                        if (!pt) continue

                                        var ptLat = Number(pt.latitude)
                                        var ptLon = Number(pt.longitude)
                                        if (isNaN(ptLat) || isNaN(ptLon)) continue

                                        var tx = MapUtils.lonToX(ptLon, width)
                                        var ty = MapUtils.latToY(ptLat, height)
                                        if (tp === 0 || Math.abs(ptLon - prevLon) > 180) {
                                            ctx.moveTo(tx, ty)
                                        } else {
                                            ctx.lineTo(tx, ty)
                                        }
                                        prevLon = ptLon
                                    }
                                    ctx.stroke()
                                    ctx.restore()
                                }

                                // Previous Orbit Trajectory (50% opacity, dashed)
                                if (MapUtils.getTrajectoryCount(sat.prevTrajectory) > 1) {
                                    drawCanvasTrack(
                                        sat.prevTrajectory,
                                        isSatSel ? "rgba(255, 212, 59, 0.50)" : "rgba(250, 176, 5, 0.50)",
                                        isSatSel ? 2.0 : 1.2,
                                        [6, 5]
                                    )
                                }

                                // Next Orbit Trajectory (50% opacity, dashed)
                                if (MapUtils.getTrajectoryCount(sat.nextTrajectory) > 1) {
                                    drawCanvasTrack(
                                        sat.nextTrajectory,
                                        isSatSel ? "rgba(255, 212, 59, 0.50)" : "rgba(250, 176, 5, 0.50)",
                                        isSatSel ? 2.0 : 1.2,
                                        [6, 5]
                                    )
                                }

                                // Current Orbit Trajectory (100% opacity, dashed)
                                if (MapUtils.getTrajectoryCount(sat.trajectory) > 1) {
                                    drawCanvasTrack(
                                        sat.trajectory,
                                        isSatSel ? "#ffd43b" : "#fab005",
                                        isSatSel ? 2.5 : 1.5,
                                        [8, 6]
                                    )
                                }

                                // Satellite Visibility Footprint
                                if (sat.visibilityRadiusMeters > 0) {
                                    MapUtils.drawCanvasFootprint(
                                        ctx, sat.latitude, sat.longitude, sat.visibilityRadiusMeters,
                                        isSatSel ? "rgba(245, 159, 0, 0.28)" : "rgba(245, 159, 0, 0.14)",
                                        isSatSel ? "#f59f00" : "#ffd43b",
                                        isSatSel ? 2 : 1,
                                        width, height
                                    )
                                }
                            }
                        }

                        // 3. Draft Station Footprint
                        if (equirectangularView.hasDraft) {
                            var draftRad = MapUtils.calculateStationSatVisibilityRadius(
                                equirectangularView.targetSatelliteAltitudeKm,
                                equirectangularView.minElevationDeg,
                                equirectangularView.targetSatelliteAltitudeKm,
                                equirectangularView.minElevationDeg
                            )
                            if (draftRad > 0) {
                                MapUtils.drawCanvasFootprint(
                                    ctx, equirectangularView.draftLat, equirectangularView.draftLon, draftRad,
                                    "rgba(250, 82, 82, 0.25)",
                                    "#fa5252",
                                    2,
                                    width, height
                                )
                            }
                        }
                    }
                }

                // Station Pins Repeater
                Repeater {
                    model: equirectangularView.stationsModel
                    delegate: Item {
                        x: MapUtils.lonToX(model.longitude, equiMapImage.width) - 18
                        y: MapUtils.latToY(model.latitude, equiMapImage.height) - 40
                        width: 36
                        height: 44
                        z: (equirectangularView.selectedStationId === model.stationId) ? 20 : 10

                        Shape {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.samples: 4

                            ShapePath {
                                strokeWidth: 2
                                strokeColor: "#ffffff"
                                fillColor: (equirectangularView.selectedStationId === model.stationId) ? "#fa5252" : "#228be6"
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
                            visible: equirectangularView.selectedStationId === model.stationId
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
                            onClicked: equirectangularView.markerSelected(model.stationId, model.name)
                        }
                    }
                }

                // Satellite Pins Repeater
                Repeater {
                    model: equirectangularView.satellitesModel
                    delegate: Item {
                        x: MapUtils.lonToX(model.longitude, equiMapImage.width) - 16
                        y: MapUtils.latToY(model.latitude, equiMapImage.height) - 16
                        width: 32
                        height: 32
                        z: 25

                        Rectangle {
                            anchors.centerIn: parent
                            width: equirectangularView.selectedSatelliteId === model.satId ? 30 : 24
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
                            onClicked: equirectangularView.satelliteSelected(model.satId, model.name)
                        }
                    }
                }

                // Draft Station Marker Pin
                Item {
                    visible: equirectangularView.hasDraft
                    x: MapUtils.lonToX(equirectangularView.draftLon, equiMapImage.width) - 18
                    y: MapUtils.latToY(equirectangularView.draftLat, equiMapImage.height) - 40
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
            cursorShape: equirectangularView.pickModeEnabled ? Qt.CrossCursor : Qt.ArrowCursor

            onClicked: (mouse) => {
                if (equirectangularView.pickModeEnabled) {
                    var contentX = (mouse.x + equiFlickable.contentX) / equirectangularView.equiZoomScale
                    var contentY = (mouse.y + equiFlickable.contentY) / equirectangularView.equiZoomScale

                    var lon = MapUtils.xToLon(contentX, equiMapImage.width)
                    var lat = MapUtils.yToLat(contentY, equiMapImage.height)

                    equirectangularView.coordinatePicked(lat, lon)
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
