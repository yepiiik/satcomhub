.pragma library

var earthRadiusMeters = 6371000.0

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

// Satellite Line-of-Sight Visibility Radius on Earth surface (in meters)
// Formula: R_E * [ arccos( (R_E / (R_E + h_sat)) * cos(minElevation) ) - minElevation ]
function calculateStationSatVisibilityRadius(satAltKm, elevationDeg, defaultSatAltKm, defaultMinElDeg) {
    var defAlt = (defaultSatAltKm !== undefined) ? defaultSatAltKm : 500.0
    var defEl = (defaultMinElDeg !== undefined) ? defaultMinElDeg : 5.0
    var h = Math.max(50.0, parseFloat(satAltKm) || defAlt)
    var el = ((elevationDeg !== undefined && elevationDeg !== null) ? elevationDeg : defEl) * (Math.PI / 180.0)
    var rSat = (earthRadiusMeters / 1000.0) + h

    var cosArg = ((earthRadiusMeters / 1000.0) / rSat) * Math.cos(el)
    if (cosArg > 1.0) cosArg = 1.0
    if (cosArg < -1.0) cosArg = -1.0

    var theta = Math.acos(cosArg) - el
    if (theta < 0.0) theta = 0.0

    return earthRadiusMeters * theta
}

function generateContinuousFootprintPoints(centerLat, centerLon, radiusMeters, numPoints, canvasWidth, canvasHeight) {
    if (radiusMeters <= 0) return null
    var pts = []
    var n = numPoints || 64
    var d = radiusMeters / earthRadiusMeters
    var lat1 = centerLat * Math.PI / 180.0
    var normCenterLon = ((centerLon + 180.0) % 360.0 + 360.0) % 360.0 - 180.0

    var minX = Infinity
    var maxX = -Infinity
    var prevDLon = 0.0

    for (var i = 0; i < n; i++) {
        var bearing = (2.0 * Math.PI * i) / n
        var sinLat2 = Math.max(-1.0, Math.min(1.0, Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearing)))
        var lat2 = Math.asin(sinLat2)
        var dLon = Math.atan2(Math.sin(bearing) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2))

        if (i > 0) {
            while (dLon - prevDLon > Math.PI) dLon -= 2 * Math.PI
            while (dLon - prevDLon < -Math.PI) dLon += 2 * Math.PI
        }
        prevDLon = dLon

        var lonDeg = normCenterLon + (dLon * 180.0 / Math.PI)
        var latDeg = lat2 * 180.0 / Math.PI

        var px = lonToX(lonDeg, canvasWidth)
        var py = latToY(latDeg, canvasHeight)

        if (px < minX) minX = px
        if (px > maxX) maxX = px

        pts.push({ x: px, y: py })
    }

    pts.minX = minX
    pts.maxX = maxX
    return pts
}

function drawCanvasFootprint(ctx, centerLat, centerLon, radiusMeters, fillColor, strokeColor, lineWidth, canvasWidth, canvasHeight) {
    if (radiusMeters <= 0) return
    var pts = generateContinuousFootprintPoints(centerLat, centerLon, radiusMeters, 64, canvasWidth, canvasHeight)
    if (!pts || pts.length < 3) return

    ctx.save()
    ctx.beginPath()
    ctx.rect(0, 0, canvasWidth, canvasHeight)
    ctx.clip()

    function renderPath(dx) {
        ctx.beginPath()
        ctx.moveTo(pts[0].x + dx, pts[0].y)
        for (var i = 1; i < pts.length; i++) {
            ctx.lineTo(pts[i].x + dx, pts[i].y)
        }
        ctx.closePath()
        ctx.fillStyle = fillColor
        ctx.fill()
        ctx.strokeStyle = strokeColor
        ctx.lineWidth = lineWidth
        ctx.stroke()
    }

    renderPath(0)
    if (pts.minX < 0) {
        renderPath(canvasWidth)
    }
    if (pts.maxX > canvasWidth) {
        renderPath(-canvasWidth)
    }

    ctx.restore()
}

function generateGeodesicPolygons(centerLat, centerLon, radiusMeters, numPoints, qtPos) {
    if (radiusMeters <= 0) return []
    var n = numPoints || 64
    var d = radiusMeters / earthRadiusMeters
    var lat1 = centerLat * Math.PI / 180.0
    var normCenterLon = ((centerLon + 180.0) % 360.0 + 360.0) % 360.0 - 180.0

    var pts = []
    var prevDLon = 0.0
    var minLon = Infinity
    var maxLon = -Infinity

    for (var i = 0; i < n; i++) {
        var bearing = (2.0 * Math.PI * i) / n
        var sinLat2 = Math.max(-1.0, Math.min(1.0, Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearing)))
        var lat2 = Math.asin(sinLat2)
        var dLon = Math.atan2(Math.sin(bearing) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2))

        if (i > 0) {
            while (dLon - prevDLon > Math.PI) dLon -= 2 * Math.PI
            while (dLon - prevDLon < -Math.PI) dLon += 2 * Math.PI
        }
        prevDLon = dLon

        var lonDeg = normCenterLon + (dLon * 180.0 / Math.PI)
        var latDeg = lat2 * 180.0 / Math.PI

        if (lonDeg < minLon) minLon = lonDeg
        if (lonDeg > maxLon) maxLon = lonDeg

        pts.push({ lat: latDeg, lon: lonDeg })
    }

    function createCoord(lat, lon) {
        return qtPos ? qtPos.coordinate(lat, lon) : { latitude: lat, longitude: lon }
    }

    if (minLon >= -180.0 && maxLon <= 180.0) {
        var single = []
        for (var j = 0; j < pts.length; j++) {
            single.push(createCoord(pts[j].lat, pts[j].lon))
        }
        return [single]
    }

    if (minLon < -180.0) {
        var polyMain = []
        var polyWrapped = []
        for (var k = 0; k < pts.length; k++) {
            var p1 = pts[k]
            var p2 = pts[(k + 1) % pts.length]

            var p1In = (p1.lon >= -180.0)
            var p2In = (p2.lon >= -180.0)

            if (p1In) {
                polyMain.push(createCoord(p1.lat, p1.lon))
            } else {
                polyWrapped.push(createCoord(p1.lat, p1.lon + 360.0))
            }

            if (p1In !== p2In) {
                var t = (-180.0 - p1.lon) / (p2.lon - p1.lon)
                var latCross = p1.lat + t * (p2.lat - p1.lat)
                polyMain.push(createCoord(latCross, -180.0))
                polyWrapped.push(createCoord(latCross, 180.0))
            }
        }
        return [polyMain, polyWrapped]
    }

    if (maxLon > 180.0) {
        var polyMain2 = []
        var polyWrapped2 = []
        for (var m = 0; m < pts.length; m++) {
            var p1m = pts[m]
            var p2m = pts[(m + 1) % pts.length]

            var p1mIn = (p1m.lon <= 180.0)
            var p2mIn = (p2m.lon <= 180.0)

            if (p1mIn) {
                polyMain2.push(createCoord(p1m.lat, p1m.lon))
            } else {
                polyWrapped2.push(createCoord(p1m.lat, p1m.lon - 360.0))
            }

            if (p1mIn !== p2mIn) {
                var tm = (180.0 - p1m.lon) / (p2m.lon - p1m.lon)
                var latCrossM = p1m.lat + tm * (p2m.lat - p1m.lat)
                polyMain2.push(createCoord(latCrossM, 180.0))
                polyWrapped2.push(createCoord(latCrossM, -180.0))
            }
        }
        return [polyMain2, polyWrapped2]
    }

    return []
}

function getTrajectoryCount(trajectory) {
    if (!trajectory) return 0
    if (typeof trajectory.count === "number") {
        return trajectory.count
    }
    if (typeof trajectory.length === "number") {
        return trajectory.length
    }
    return 0
}

function getTrajectoryItem(trajectory, index) {
    if (!trajectory) return null
    if (typeof trajectory.get === "function") {
        return trajectory.get(index)
    }
    return trajectory[index]
}

function splitTrajectorySegments(trajectory, qtPos) {
    var count = getTrajectoryCount(trajectory)
    if (count === 0) return []
    var segments = []
    var current = []
    var prevLon = 0

    function createCoord(lat, lon) {
        return qtPos ? qtPos.coordinate(lat, lon) : { latitude: lat, longitude: lon }
    }

    for (var i = 0; i < count; i++) {
        var pt = getTrajectoryItem(trajectory, i)
        if (!pt) continue
        var lat = Number(pt.latitude)
        var lon = Number(pt.longitude)
        if (isNaN(lat) || isNaN(lon)) continue

        if (current.length > 0 && Math.abs(lon - prevLon) > 180) {
            segments.push(current)
            current = []
        }
        current.push(createCoord(lat, lon))
        prevLon = lon
    }
    if (current.length > 0) {
        segments.push(current)
    }
    return segments
}

function buildDashedPolylineSegments(trajectory, qtPos) {
    var count = getTrajectoryCount(trajectory)
    if (count < 2) return []
    var segments = []

    function createCoord(lat, lon) {
        return qtPos ? qtPos.coordinate(lat, lon) : { latitude: lat, longitude: lon }
    }

    for (var i = 0; i < count - 1; i += 2) {
        var p1 = getTrajectoryItem(trajectory, i)
        var p2 = getTrajectoryItem(trajectory, i + 1)
        if (!p1 || !p2) continue

        var lat1 = Number(p1.latitude)
        var lon1 = Number(p1.longitude)
        var lat2 = Number(p2.latitude)
        var lon2 = Number(p2.longitude)

        if (isNaN(lat1) || isNaN(lon1) || isNaN(lat2) || isNaN(lon2)) continue
        if (Math.abs(lon2 - lon1) > 180) continue

        segments.push([
            createCoord(lat1, lon1),
            createCoord(lat2, lon2)
        ])
    }
    return segments
}
