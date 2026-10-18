#include "SatellitePropagator.h"

#include <libsgp4/CoordGeodetic.h>
#include <libsgp4/DateTime.h>
#include <libsgp4/Eci.h>
#include <libsgp4/SGP4.h>
#include <libsgp4/Tle.h>
#include <libsgp4/Util.h>
#include <libsgp4/TleException.h>
#include <libsgp4/SatelliteException.h>
#include <libsgp4/DecayedException.h>

#include <QDateTime>
#include <QTimeZone>
#include <QDate>
#include <QTime>
#include <QRegularExpression>
#include <cmath>
#include <algorithm>

namespace {
static libsgp4::DateTime toSgp4DateTime(const QDateTime &qdt) {
    QDateTime utc = qdt.toUTC();
    QDate d = utc.date();
    QTime t = utc.time();
    return libsgp4::DateTime(d.year(), d.month(), d.day(),
                             t.hour(), t.minute(), t.second(),
                             t.msec() * 1000);
}

static QDateTime fromSgp4DateTime(const libsgp4::DateTime &dt) {
    return QDateTime(QDate(dt.Year(), dt.Month(), dt.Day()),
                     QTime(dt.Hour(), dt.Minute(), dt.Second(), dt.Microsecond() / 1000),
                     QTimeZone::UTC);
}
} // namespace

SatellitePropagator::SatellitePropagator(QObject *parent)
    : QObject(parent)
{
}

bool SatellitePropagator::extractTleLines(const QString &inLine1, const QString &inLine2,
                                         QString &outName, QString &outLine1, QString &outLine2) {
    QString l1 = inLine1.trimmed();
    QString l2 = inLine2.trimmed();
    outName.clear();

    // Support multi-line or 3-line TLE blocks pasted into inLine1
    if (l1.contains('\n') || l1.contains('\r')) {
        QStringList lines = l1.split(QRegularExpression("[\r\n]+"), Qt::SkipEmptyParts);
        for (const QString &rawLine : lines) {
            QString trimmed = rawLine.trimmed();
            if (trimmed.startsWith('1') && trimmed.length() >= 60) {
                l1 = trimmed;
            } else if (trimmed.startsWith('2') && trimmed.length() >= 60) {
                l2 = trimmed;
            } else if (!trimmed.isEmpty() && outName.isEmpty()) {
                outName = trimmed;
            }
        }
    }

    if (!l1.startsWith('1') || !l2.startsWith('2') || l1.length() < 60 || l2.length() < 60) {
        return false;
    }

    // Standard TLE line length expected by libsgp4 is strictly 69 characters.
    // If copy-paste stripped trailing whitespace, pad to 69 characters.
    if (l1.length() < 69) {
        l1 = l1.leftJustified(69, ' ');
    } else if (l1.length() > 69) {
        l1 = l1.left(69);
    }

    if (l2.length() < 69) {
        l2 = l2.leftJustified(69, ' ');
    } else if (l2.length() > 69) {
        l2 = l2.left(69);
    }

    outLine1 = l1;
    outLine2 = l2;
    if (outName.isEmpty()) {
        outName = QStringLiteral("SATELLITE");
    }
    return true;
}

double SatellitePropagator::calculateVisibilityRadius(double altitudeKm, double minElevationDeg) const {
    if (altitudeKm <= 0.0) return 0.0;

    double elRad = minElevationDeg * (M_PI / 180.0);
    double rSat = EarthRadiusKm + altitudeKm;

    // Earth central angle theta from spherical trigonometry
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
    QString name, l1, l2;
    if (!extractTleLines(tleLine1, tleLine2, name, l1, l2)) {
        res["valid"] = false;
        return res;
    }

    try {
        libsgp4::Tle tle(name.toStdString(), l1.toStdString(), l2.toStdString());
        libsgp4::SGP4 sgp4(tle);

        QDateTime nowUtc = QDateTime::currentDateTimeUtc();
        QDateTime targetUtc = nowUtc.addMSecs(static_cast<qint64>(minutesOffset * 60000.0));
        libsgp4::DateTime targetDt = toSgp4DateTime(targetUtc);

        libsgp4::Eci eci = sgp4.FindPosition(targetDt);
        libsgp4::CoordGeodetic geo = eci.ToGeodetic();

        double lat = libsgp4::Util::RadiansToDegrees(geo.latitude);
        double lon = libsgp4::Util::RadiansToDegrees(geo.longitude);
        double altKm = geo.altitude;
        double speed = eci.Velocity().Magnitude();
        double visRadiusMeters = calculateVisibilityRadius(altKm, 0.0);

        QDateTime epochUtc = fromSgp4DateTime(tle.Epoch());

        res["valid"] = true;
        res["satNumber"] = static_cast<int>(tle.NoradNumber());
        res["satName"] = QString::fromStdString(tle.Name());
        res["latitude"] = lat;
        res["longitude"] = lon;
        res["altitudeKm"] = altKm;
        res["velocityKmS"] = speed;
        res["visibilityRadiusMeters"] = visRadiusMeters;
        res["epochUtc"] = epochUtc.toString(Qt::ISODate);
        res["targetUtc"] = targetUtc.toString(Qt::ISODate);
        return res;
    } catch (...) {
        res["valid"] = false;
        return res;
    }
}

QVariantList SatellitePropagator::computeTrackRange(libsgp4::SGP4 &sgp4, const QDateTime &baseUtc,
                                                   double startMinutesFromNow, double endMinutesFromNow, double stepMinutes) const {
    QVariantList track;
    double step = std::max(0.1, stepMinutes);
    for (double m = startMinutesFromNow; m <= endMinutesFromNow; m += step) {
        QDateTime stepUtc = baseUtc.addMSecs(static_cast<qint64>(m * 60000.0));
        libsgp4::DateTime dt = toSgp4DateTime(stepUtc);

        try {
            libsgp4::Eci eci = sgp4.FindPosition(dt);
            libsgp4::CoordGeodetic geo = eci.ToGeodetic();

            QVariantMap pt;
            pt["latitude"] = libsgp4::Util::RadiansToDegrees(geo.latitude);
            pt["longitude"] = libsgp4::Util::RadiansToDegrees(geo.longitude);
            pt["altitudeKm"] = geo.altitude;
            pt["minuteOffset"] = m;
            track.append(pt);
        } catch (...) {
            // Satellite decayed or out of bounds for step
            continue;
        }
    }
    return track;
}

QVariantList SatellitePropagator::computeGroundTrack(const QString &tleLine1, const QString &tleLine2, int totalMinutes, int stepMinutes) {
    QString name, l1, l2;
    if (!extractTleLines(tleLine1, tleLine2, name, l1, l2)) return QVariantList();

    try {
        libsgp4::Tle tle(name.toStdString(), l1.toStdString(), l2.toStdString());
        libsgp4::SGP4 sgp4(tle);

        double half = totalMinutes / 2.0;
        QDateTime nowUtc = QDateTime::currentDateTimeUtc();
        return computeTrackRange(sgp4, nowUtc, -half, half, static_cast<double>(std::max(1, stepMinutes)));
    } catch (...) {
        return QVariantList();
    }
}

QVariantMap SatellitePropagator::computeOrbitTracks(const QString &tleLine1, const QString &tleLine2, double stepMinutes) {
    QVariantMap res;
    QString name, l1, l2;
    if (!extractTleLines(tleLine1, tleLine2, name, l1, l2)) return res;

    try {
        libsgp4::Tle tle(name.toStdString(), l1.toStdString(), l2.toStdString());
        libsgp4::SGP4 sgp4(tle);

        double meanMotion = tle.MeanMotion(); // rev / day
        if (meanMotion <= 0.0) return res;

        double periodMinutes = 1440.0 / meanMotion;
        double half = periodMinutes / 2.0;
        QDateTime nowUtc = QDateTime::currentDateTimeUtc();

        res["periodMinutes"] = periodMinutes;
        res["previous"] = computeTrackRange(sgp4, nowUtc, -half - periodMinutes, -half, stepMinutes);
        res["current"]  = computeTrackRange(sgp4, nowUtc, -half, half, stepMinutes);
        res["next"]     = computeTrackRange(sgp4, nowUtc, half, half + periodMinutes, stepMinutes);
        return res;
    } catch (...) {
        return res;
    }
}

QString SatellitePropagator::currentUtcIsoString() const {
    return QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd HH:mm:ss 'UTC'");
}
