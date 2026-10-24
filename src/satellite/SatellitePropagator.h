#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QString>
#include <QDateTime>
#include <cmath>

namespace libsgp4 {
    class SGP4;
    class DateTime;
}

class SatellitePropagator : public QObject {
    Q_OBJECT
public:
    explicit SatellitePropagator(QObject *parent = nullptr);

    // Parses TLE lines and computes live position (lat, lon, alt) and visibility radius (meters)
    // minutesOffset is the offset in minutes from the current live UTC time (default: 0.0 = now)
    Q_INVOKABLE QVariantMap propagateTle(const QString &tleLine1, const QString &tleLine2, double minutesOffset = 0.0);

    // Computes ground track path for a full orbit period (e.g. -48 min to +48 min) centered around current live time
    Q_INVOKABLE QVariantList computeGroundTrack(const QString &tleLine1, const QString &tleLine2, int totalMinutes = 96, int stepMinutes = 2);

    // Computes previous (-1 orbit), current (0 orbit), and next (+1 orbit) trajectories
    // Returns QVariantMap with "current", "previous", "next" (each QVariantList), and "periodMinutes" (double)
    Q_INVOKABLE QVariantMap computeOrbitTracks(const QString &tleLine1, const QString &tleLine2, double stepMinutes = 0.75);

    // Calculates maximum line-of-sight visibility ground radius from satellite altitude (in meters)
    // Formula: R_E * arccos( (R_E / (R_E + h)) * cos(minElevation) ) - minElevation
    Q_INVOKABLE double calculateVisibilityRadius(double altitudeKm, double minElevationDeg = 0.0) const;

    // Helper to get current UTC date/time formatted string
    Q_INVOKABLE QString currentUtcIsoString() const;

    // Calculates future satellite pass windows taking into account selected satellite (TLE) and selected station(s).
    // Supports single-station prediction and multi-station diversity / handover window combining.
    Q_INVOKABLE QVariantMap calculatePassWindows(const QString &tleLine1,
                                                const QString &tleLine2,
                                                const QVariantList &stations,
                                                int forecastHours = 24,
                                                double stepSeconds = 20.0);

    // Computes aligned signal loss vectors (FSPL, atmospheric, total loss) and SNR time-series for a satellite pass across participating stations
    Q_INVOKABLE QVariantMap calculatePassSnrProfile(const QString &tleLine1,
                                                   const QString &tleLine2,
                                                   const QVariantList &stations,
                                                   const QString &startUtcIso,
                                                   const QString &endUtcIso,
                                                   double sampleRateHz = 1.0,
                                                   double txPowerDbm = 33.0,
                                                   double txAntennaGainDbi = 3.0,
                                                   double carrierFreqMhz = 5840.0,
                                                   double channelBandwidthKhz = 10000.0);

private:
    static bool extractTleLines(const QString &inLine1, const QString &inLine2,
                                QString &outName, QString &outLine1, QString &outLine2);
    QVariantList computeTrackRange(libsgp4::SGP4 &sgp4, const QDateTime &baseUtc,
                                   double startMinutesFromNow, double endMinutesFromNow, double stepMinutes) const;

    static constexpr double EarthRadiusKm = 6378.137; // WGS-84 equatorial radius
};
