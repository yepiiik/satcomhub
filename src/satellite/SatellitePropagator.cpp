#include "SatellitePropagator.h"
#include <QDateTime>
#include <cmath>

SatellitePropagator::SatellitePropagator(QObject *parent)
    : QObject(parent)
{
}

SatellitePropagator::TleData SatellitePropagator::parseTle(const QString &line1, const QString &line2) const {
    TleData tle;
    QString l1 = line1.trimmed();
    QString l2 = line2.trimmed();

    if (!l1.startsWith('1') || !l2.startsWith('2') || l1.length() < 68 || l2.length() < 68) {
        return tle;
    }

    bool ok = false;
    tle.satNumber = l1.mid(2, 5).trimmed().toInt(&ok);
    if (!ok) return tle;

    tle.epochYear = l1.mid(18, 2).trimmed().toInt(&ok);
    tle.epochYear += (tle.epochYear < 57) ? 2000 : 1900;
    tle.epochDay = l1.mid(20, 12).trimmed().toDouble(&ok);

    tle.inclinationRad = l2.mid(8, 8).trimmed().toDouble(&ok) * (M_PI / 180.0);
    tle.raanRad = l2.mid(17, 8).trimmed().toDouble(&ok) * (M_PI / 180.0);
    tle.eccentricity = ("0." + l2.mid(26, 7).trimmed()).toDouble(&ok);
    tle.argPerigeeRad = l2.mid(34, 8).trimmed().toDouble(&ok) * (M_PI / 180.0);
    tle.meanAnomalyRad = l2.mid(43, 8).trimmed().toDouble(&ok) * (M_PI / 180.0);
    tle.meanMotionRevDay = l2.mid(52, 11).trimmed().toDouble(&ok);

    if (tle.meanMotionRevDay > 0) {
        tle.valid = true;
    }
    return tle;
}

void SatellitePropagator::propagateOrbit(const TleData &tle, double minutesFromEpoch, double &outLat, double &outLon, double &outAltKm) const {
    // Mean motion in radians per minute
    double n = tle.meanMotionRevDay * TwoPi / 1440.0;
    
    // Semi-major axis from Kepler's third law: a = (mu / n^2)^(1/3)
    double nSec = n / 60.0;
    double a = std::cbrt(Mu / (nSec * nSec));

    // Propagate Mean Anomaly
    double M = std::fmod(tle.meanAnomalyRad + n * minutesFromEpoch, TwoPi);
    if (M < 0) M += TwoPi;

    // Solve Kepler's equation for Eccentric Anomaly E: M = E - e*sin(E)
    double E = M;
    for (int iter = 0; iter < 10; ++iter) {
        double delta = (E - tle.eccentricity * std::sin(E) - M) / (1.0 - tle.eccentricity * std::cos(E));
        E -= delta;
        if (std::abs(delta) < 1e-8) break;
    }

    // True anomaly nu
    double sinNu = (std::sqrt(1.0 - tle.eccentricity * tle.eccentricity) * std::sin(E)) / (1.0 - tle.eccentricity * std::cos(E));
    double cosNu = (std::cos(E) - tle.eccentricity) / (1.0 - tle.eccentricity * std::cos(E));
    double nu = std::atan2(sinNu, cosNu);

    // Distance r from Earth center
    double r = a * (1.0 - tle.eccentricity * std::cos(E));
    outAltKm = std::max(100.0, r - EarthRadiusKm);

    // Argument of latitude u = omega + nu
    double u = tle.argPerigeeRad + nu;

    // Position in orbital plane
    double xOrb = r * std::cos(u);
    double yOrb = r * std::sin(u);

    // Position in inertial geocentric equatorial coordinates
    double cosNode = std::cos(tle.raanRad);
    double sinNode = std::sin(tle.raanRad);
    double cosInc = std::cos(tle.inclinationRad);
    double sinInc = std::sin(tle.inclinationRad);

    double x = xOrb * cosNode - yOrb * cosInc * sinNode;
    double y = xOrb * sinNode + yOrb * cosInc * cosNode;
    double z = yOrb * sinInc;

    // Latitude
    outLat = std::asin(std::max(-1.0, std::min(1.0, z / r))) * (180.0 / M_PI);

    // Greenwich Hour Angle / Earth rotation adjustment
    // Earth rotates ~360 deg in 1436.068 min (sidereal day)
    double earthRotRad = (minutesFromEpoch / 1436.068) * TwoPi;
    double ra = std::atan2(y, x);
    double lonRad = ra - earthRotRad;

    outLon = std::fmod(lonRad * (180.0 / M_PI) + 540.0, 360.0) - 180.0;
}

double SatellitePropagator::calculateVisibilityRadius(double altitudeKm, double minElevationDeg) const {
    if (altitudeKm <= 0) return 0.0;

    double elRad = minElevationDeg * (M_PI / 180.0);
    double rSat = EarthRadiusKm + altitudeKm;

    // Earth central angle theta from law of cosines / spherical trig
    // cos(theta + el) = (EarthRadius / rSat) * cos(el)
    double cosArg = (EarthRadiusKm / rSat) * std::cos(elRad);
    if (cosArg > 1.0) cosArg = 1.0;
    if (cosArg < -1.0) cosArg = -1.0;

    double theta = std::acos(cosArg) - elRad;
    if (theta < 0.0) theta = 0.0;

    // Arc distance along Earth surface in meters
    return (EarthRadiusKm * 1000.0) * theta;
}

QVariantMap SatellitePropagator::propagateTle(const QString &tleLine1, const QString &tleLine2, double minutesOffset) {
    QVariantMap res;
    TleData tle = parseTle(tleLine1, tleLine2);
    if (!tle.valid) {
        res["valid"] = false;
        return res;
    }

    double lat = 0, lon = 0, altKm = 0;
    propagateOrbit(tle, minutesOffset, lat, lon, altKm);

    double visRadiusMeters = calculateVisibilityRadius(altKm, 0.0);

    res["valid"] = true;
    res["latitude"] = lat;
    res["longitude"] = lon;
    res["altitudeKm"] = altKm;
    res["visibilityRadiusMeters"] = visRadiusMeters;
    return res;
}

QVariantList SatellitePropagator::computeGroundTrack(const QString &tleLine1, const QString &tleLine2, int totalMinutes, int stepMinutes) {
    QVariantList track;
    TleData tle = parseTle(tleLine1, tleLine2);
    if (!tle.valid) return track;

    int half = totalMinutes / 2;
    for (int m = -half; m <= half; m += std::max(1, stepMinutes)) {
        double lat = 0, lon = 0, altKm = 0;
        propagateOrbit(tle, static_cast<double>(m), lat, lon, altKm);

        QVariantMap pt;
        pt["latitude"] = lat;
        pt["longitude"] = lon;
        pt["altitudeKm"] = altKm;
        pt["minuteOffset"] = m;
        track.append(pt);
    }
    return track;
}
