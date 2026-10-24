#include "SatellitePropagator.h"
#include "SignalLossModel.h"

#include <libsgp4/CoordGeodetic.h>
#include <libsgp4/DateTime.h>
#include <libsgp4/Eci.h>
#include <libsgp4/SGP4.h>
#include <libsgp4/Tle.h>
#include <libsgp4/Util.h>
#include <libsgp4/Observer.h>
#include <libsgp4/CoordTopocentric.h>
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
#include <vector>
#include <memory>
#include <set>

namespace {
static libsgp4::DateTime toSgp4DateTime(const QDateTime &qdt) {
    QDateTime utc = qdt.isValid() ? qdt.toUTC() : QDateTime::currentDateTimeUtc();
    QDate d = utc.date();
    QTime t = utc.time();
    int y = d.year() > 0 ? d.year() : 2026;
    int m = (d.month() >= 1 && d.month() <= 12) ? d.month() : 1;
    int day = (d.day() >= 1 && d.day() <= 31) ? d.day() : 1;
    return libsgp4::DateTime(y, m, day,
                             t.hour(), t.minute(), t.second(),
                             t.msec() * 1000);
}

static QDateTime fromSgp4DateTime(const libsgp4::DateTime &dt) {
    return QDateTime(QDate(dt.Year(), dt.Month(), dt.Day()),
                     QTime(dt.Hour(), dt.Minute(), dt.Second(), dt.Microsecond() / 1000),
                     QTimeZone::UTC);
}

static QString formatAzimuthCompass(double azDeg) {
    static const char* directions[] = {
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
    };
    double normAz = std::fmod(azDeg, 360.0);
    if (normAz < 0.0) normAz += 360.0;
    int idx = static_cast<int>((normAz + 11.25) / 22.5) % 16;
    return QString("%1° (%2)").arg(static_cast<int>(std::round(normAz))).arg(directions[idx]);
}

static QString formatDuration(qint64 totalSeconds) {
    qint64 mins = totalSeconds / 60;
    qint64 secs = totalSeconds % 60;
    return QString("%1m %2s")
        .arg(mins, 2, 10, QChar('0'))
        .arg(secs, 2, 10, QChar('0'));
}

static QString formatRelativePassTime(const QDateTime &tUtc, const QDateTime &nowUtc) {
    if (tUtc.date() == nowUtc.date()) {
        return QString("Today %1 UTC").arg(tUtc.toString("HH:mm:ss"));
    } else if (tUtc.date() == nowUtc.date().addDays(1)) {
        return QString("Tomorrow %1 UTC").arg(tUtc.toString("HH:mm:ss"));
    } else {
        return tUtc.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
    }
}

struct SingleStationPass {
    QString stationId;
    QString stationName;
    QDateTime aosUtc;
    QDateTime losUtc;
    QDateTime tcaUtc;
    double maxElDeg = 0.0;
    double aosAzDeg = 0.0;
    double losAzDeg = 0.0;
    double tcaAzDeg = 0.0;
    double tcaRangeKm = 0.0;
    double minElevationDeg = 5.0;
    qint64 durationSeconds = 0;
};
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

QVariantMap SatellitePropagator::calculatePassWindows(const QString &tleLine1,
                                                      const QString &tleLine2,
                                                      const QVariantList &stations,
                                                      int forecastHours,
                                                      double stepSeconds) {
    QVariantMap result;
    result["valid"] = false;
    result["passes"] = QVariantList();
    result["totalPasses"] = 0;
    result["multiStationPasses"] = 0;
    result["forecastHours"] = forecastHours;

    QString name, l1, l2;
    if (!extractTleLines(tleLine1, tleLine2, name, l1, l2) || stations.isEmpty()) {
        return result;
    }

    try {
        libsgp4::Tle tle(name.toStdString(), l1.toStdString(), l2.toStdString());
        libsgp4::SGP4 sgp4(tle);

        struct GroundStationData {
            QString stationId;
            QString name;
            double lat = 0.0;
            double lon = 0.0;
            double altKm = 0.0;
            double minElDeg = 5.0;
            double minElRad = 5.0 * (M_PI / 180.0);
            std::unique_ptr<libsgp4::Observer> observer;
        };

        std::vector<GroundStationData> stationObservers;
        for (const QVariant &stVar : stations) {
            QVariantMap stMap = stVar.toMap();
            GroundStationData gsd;
            gsd.stationId = stMap.value("stationId").toString();
            gsd.name = stMap.value("name").toString();
            gsd.lat = stMap.value("latitude").toDouble();
            gsd.lon = stMap.value("longitude").toDouble();
            double altM = stMap.value("altitude", 0.0).toDouble();
            gsd.altKm = altM / 1000.0;
            gsd.minElDeg = stMap.value("minElevation", 5.0).toDouble();
            if (gsd.minElDeg <= 0.0) gsd.minElDeg = 5.0;
            gsd.minElRad = gsd.minElDeg * (M_PI / 180.0);
            gsd.observer = std::make_unique<libsgp4::Observer>(gsd.lat, gsd.lon, gsd.altKm);
            stationObservers.push_back(std::move(gsd));
        }

        if (stationObservers.empty()) {
            return result;
        }

        QDateTime nowUtc = QDateTime::currentDateTimeUtc();
        int totalSeconds = std::clamp(forecastHours, 1, 168) * 3600;
        int stepSec = static_cast<int>(std::clamp(stepSeconds, 5.0, 60.0));

        std::vector<SingleStationPass> allSinglePasses;

        // Bisection helper to find exact time when elevation crosses threshold
        auto refineCrossing = [&](libsgp4::Observer &obs, const QDateTime &tBelow, const QDateTime &tAbove, double thresholdRad) -> QDateTime {
            QDateTime low = tBelow;
            QDateTime high = tAbove;
            for (int iter = 0; iter < 5; ++iter) {
                qint64 midMs = (low.toMSecsSinceEpoch() + high.toMSecsSinceEpoch()) / 2;
                QDateTime mid = QDateTime::fromMSecsSinceEpoch(midMs, QTimeZone::UTC);
                libsgp4::DateTime dtMid = toSgp4DateTime(mid);
                libsgp4::Eci eciMid = sgp4.FindPosition(dtMid);
                libsgp4::CoordTopocentric topoMid = obs.GetLookAngle(eciMid);
                if (topoMid.elevation >= thresholdRad) {
                    high = mid;
                } else {
                    low = mid;
                }
            }
            return high;
        };

        // 1. Calculate individual passes for each station
        for (auto &st : stationObservers) {
            bool inPass = false;
            QDateTime aosTime;
            QDateTime tcaTime;
            double maxElRad = 0.0;
            double aosAzRad = 0.0;
            double tcaAzRad = 0.0;
            double tcaRangeKm = 0.0;

            QDateTime prevTime = nowUtc;
            double prevElRad = -100.0;

            for (int sec = 0; sec <= totalSeconds; sec += stepSec) {
                QDateTime currTime = nowUtc.addSecs(sec);
                libsgp4::DateTime dt = toSgp4DateTime(currTime);

                double elRad = 0.0;
                double azRad = 0.0;
                double rangeKm = 0.0;
                try {
                    libsgp4::Eci eci = sgp4.FindPosition(dt);
                    libsgp4::CoordTopocentric topo = st.observer->GetLookAngle(eci);
                    elRad = topo.elevation;
                    azRad = topo.azimuth;
                    rangeKm = topo.range;
                } catch (...) {
                    continue;
                }

                if (elRad >= st.minElRad) {
                    if (!inPass) {
                        inPass = true;
                        // Refine AOS
                        if (sec > 0 && prevElRad < st.minElRad) {
                            aosTime = refineCrossing(*st.observer, prevTime, currTime, st.minElRad);
                        } else {
                            aosTime = currTime;
                        }
                        aosAzRad = azRad;
                        maxElRad = elRad;
                        tcaTime = currTime;
                        tcaAzRad = azRad;
                        tcaRangeKm = rangeKm;
                    } else if (elRad > maxElRad) {
                        maxElRad = elRad;
                        tcaTime = currTime;
                        tcaAzRad = azRad;
                        tcaRangeKm = rangeKm;
                    }
                } else {
                    if (inPass) {
                        inPass = false;
                        // Refine LOS
                        QDateTime losTime;
                        if (prevElRad >= st.minElRad) {
                            losTime = refineCrossing(*st.observer, currTime, prevTime, st.minElRad);
                        } else {
                            losTime = currTime;
                        }

                        qint64 durSec = aosTime.secsTo(losTime);
                        if (durSec >= 30) {
                            SingleStationPass p;
                            p.stationId = st.stationId;
                            p.stationName = st.name;
                            p.aosUtc = aosTime;
                            p.losUtc = losTime;
                            p.tcaUtc = tcaTime;
                            p.maxElDeg = libsgp4::Util::RadiansToDegrees(maxElRad);
                            p.aosAzDeg = libsgp4::Util::RadiansToDegrees(aosAzRad);
                            p.losAzDeg = libsgp4::Util::RadiansToDegrees(azRad);
                            p.tcaAzDeg = libsgp4::Util::RadiansToDegrees(tcaAzRad);
                            p.tcaRangeKm = tcaRangeKm;
                            p.minElevationDeg = st.minElDeg;
                            p.durationSeconds = durSec;
                            allSinglePasses.push_back(p);
                        }
                    }
                }

                prevTime = currTime;
                prevElRad = elRad;
            }
        }

        // 2. Sort all single-station passes chronologically
        std::sort(allSinglePasses.begin(), allSinglePasses.end(), [](const SingleStationPass &a, const SingleStationPass &b) {
            return a.aosUtc < b.aosUtc;
        });

        // 3. Group overlapping / handover passes from different stations into Joint Pass Events
        struct PassGroup {
            std::vector<SingleStationPass> passes;
            QDateTime combinedAos;
            QDateTime combinedLos;
        };

        std::vector<PassGroup> passGroups;
        for (const auto &p : allSinglePasses) {
            bool merged = false;
            for (auto &grp : passGroups) {
                // Passes belong to the same orbit passage if they overlap or are within 15 minutes of each other
                if (p.aosUtc <= grp.combinedLos.addSecs(900) && p.losUtc >= grp.combinedAos.addSecs(-900)) {
                    grp.passes.push_back(p);
                    if (p.aosUtc < grp.combinedAos) grp.combinedAos = p.aosUtc;
                    if (p.losUtc > grp.combinedLos) grp.combinedLos = p.losUtc;
                    merged = true;
                    break;
                }
            }
            if (!merged) {
                PassGroup newGrp;
                newGrp.passes.push_back(p);
                newGrp.combinedAos = p.aosUtc;
                newGrp.combinedLos = p.losUtc;
                passGroups.push_back(newGrp);
            }
        }

        // 4. Format Output QVariantList of pass events
        QVariantList formattedPasses;
        int passIndex = 1;
        int multiStationCount = 0;

        for (const auto &grp : passGroups) {
            QVariantMap eventMap;
            eventMap["passIndex"] = passIndex++;
            eventMap["combinedAosUtc"] = grp.combinedAos.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
            eventMap["combinedLosUtc"] = grp.combinedLos.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
            eventMap["combinedAosIso"] = grp.combinedAos.toString(Qt::ISODate);
            eventMap["combinedLosIso"] = grp.combinedLos.toString(Qt::ISODate);
            eventMap["relativeAos"] = formatRelativePassTime(grp.combinedAos, nowUtc);

            qint64 totalDurSec = grp.combinedAos.secsTo(grp.combinedLos);
            eventMap["combinedDurationSeconds"] = totalDurSec;
            eventMap["combinedDurationFormatted"] = formatDuration(totalDurSec);

            // Participating stations
            std::set<QString> uniqueStationIds;
            QStringList stationNameList;
            double globalMaxElDeg = 0.0;
            QString maxElStationName;
            qint64 maxSingleDurationSec = 0;

            for (const auto &sp : grp.passes) {
                if (uniqueStationIds.insert(sp.stationId).second) {
                    stationNameList.append(sp.stationName);
                }
                if (sp.maxElDeg > globalMaxElDeg) {
                    globalMaxElDeg = sp.maxElDeg;
                    maxElStationName = sp.stationName;
                }
                if (sp.durationSeconds > maxSingleDurationSec) {
                    maxSingleDurationSec = sp.durationSeconds;
                }
            }

            bool isMultiStation = (uniqueStationIds.size() >= 2);
            if (isMultiStation) {
                multiStationCount++;
            }

            eventMap["isMultiStation"] = isMultiStation;
            eventMap["stationCount"] = static_cast<int>(uniqueStationIds.size());
            eventMap["stationNames"] = stationNameList.join(" + ");
            eventMap["maxElevationDeg"] = std::round(globalMaxElDeg * 10.0) / 10.0;
            eventMap["maxElevationStation"] = maxElStationName;

            // Window gain from multi-station diversity
            double windowGainPercent = 0.0;
            if (isMultiStation && maxSingleDurationSec > 0) {
                qint64 gainSec = totalDurSec - maxSingleDurationSec;
                if (gainSec > 0) {
                    windowGainPercent = std::round((gainSec * 1000.0) / maxSingleDurationSec) / 10.0;
                }
            }
            eventMap["windowGainPercent"] = windowGainPercent;

            // Check for concurrent overlap (stations seeing satellite simultaneously for High-SNR MRC)
            bool hasConcurrentOverlap = false;
            qint64 maxOverlapSec = 0;
            if (isMultiStation && grp.passes.size() >= 2) {
                for (size_t i = 0; i < grp.passes.size(); ++i) {
                    for (size_t j = i + 1; j < grp.passes.size(); ++j) {
                        QDateTime oStart = std::max(grp.passes[i].aosUtc, grp.passes[j].aosUtc);
                        QDateTime oEnd = std::min(grp.passes[i].losUtc, grp.passes[j].losUtc);
                        if (oStart < oEnd) {
                            hasConcurrentOverlap = true;
                            qint64 oDur = oStart.secsTo(oEnd);
                            if (oDur > maxOverlapSec) {
                                maxOverlapSec = oDur;
                            }
                        }
                    }
                }
            }
            eventMap["hasConcurrentOverlap"] = hasConcurrentOverlap;
            eventMap["overlapDurationSeconds"] = maxOverlapSec;
            eventMap["overlapDurationFormatted"] = formatDuration(maxOverlapSec);

            // Sub-passes breakdown
            QVariantList stationPassesList;
            for (const auto &sp : grp.passes) {
                QVariantMap spMap;
                spMap["stationId"] = sp.stationId;
                spMap["stationName"] = sp.stationName;
                spMap["aosUtc"] = sp.aosUtc.toString("HH:mm:ss");
                spMap["losUtc"] = sp.losUtc.toString("HH:mm:ss");
                spMap["tcaUtc"] = sp.tcaUtc.toString("HH:mm:ss");
                spMap["durationSeconds"] = sp.durationSeconds;
                spMap["durationFormatted"] = formatDuration(sp.durationSeconds);
                spMap["maxElevationDeg"] = std::round(sp.maxElDeg * 10.0) / 10.0;
                spMap["aosAzimuthCompass"] = formatAzimuthCompass(sp.aosAzDeg);
                spMap["losAzimuthCompass"] = formatAzimuthCompass(sp.losAzDeg);
                spMap["tcaAzimuthCompass"] = formatAzimuthCompass(sp.tcaAzDeg);
                spMap["tcaRangeKm"] = std::round(sp.tcaRangeKm);
                stationPassesList.append(spMap);
            }
            eventMap["stationPasses"] = stationPassesList;

            formattedPasses.append(eventMap);
        }

        result["valid"] = true;
        result["passes"] = formattedPasses;
        result["totalPasses"] = formattedPasses.size();
        result["multiStationPasses"] = multiStationCount;
        result["satelliteName"] = QString::fromStdString(tle.Name());
        result["calculatedAtUtc"] = nowUtc.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
        return result;
    } catch (...) {
        return result;
    }
}

QVariantMap SatellitePropagator::calculatePassSnrProfile(const QString &tleLine1,
                                                        const QString &tleLine2,
                                                        const QVariantList &stations,
                                                        const QString &startUtcIso,
                                                        const QString &endUtcIso,
                                                        double sampleRateHz,
                                                        double txPowerDbm,
                                                        double txAntennaGainDbi,
                                                        double carrierFreqMhz,
                                                        double channelBandwidthKhz) {
    QDateTime startUtc = QDateTime::fromString(startUtcIso, Qt::ISODate);
    if (!startUtc.isValid()) {
        startUtc = QDateTime::fromString(startUtcIso, "yyyy-MM-dd HH:mm:ss 'UTC'");
        if (!startUtc.isValid()) {
            startUtc = QDateTime::fromString(startUtcIso, "yyyy-MM-dd HH:mm:ss");
        }
    }
    startUtc.setTimeZone(QTimeZone::UTC);

    QDateTime endUtc = QDateTime::fromString(endUtcIso, Qt::ISODate);
    if (!endUtc.isValid()) {
        endUtc = QDateTime::fromString(endUtcIso, "yyyy-MM-dd HH:mm:ss 'UTC'");
        if (!endUtc.isValid()) {
            endUtc = QDateTime::fromString(endUtcIso, "yyyy-MM-dd HH:mm:ss");
        }
    }
    endUtc.setTimeZone(QTimeZone::UTC);

    JointSessionSnrResult res = SignalLossModel::computeJointSessionSnr(
        tleLine1, tleLine2, stations, startUtc, endUtc,
        sampleRateHz, txPowerDbm, txAntennaGainDbi, carrierFreqMhz, channelBandwidthKhz
    );

    return res.toVariantMap();
}

