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

/**
 * @class SatellitePropagator
 * @brief SGP4 orbital propagator, pass window predictor, and link-budget analyzer exposed to QML.
 *
 * Wraps `libsgp4` to compute live sub-satellite coordinates, ground tracks, multi-station
 * visibility windows, joint SNR/FSPL profiles, maximum AMC code rate ($r_{\max}$), and YAML session plans.
 */
class SatellitePropagator : public QObject {
    Q_OBJECT
public:
    explicit SatellitePropagator(QObject *parent = nullptr);

    /**
     * @brief Parses TLE lines and computes live satellite position and visibility footprint radius.
     * @param tleLine1 NORAD TLE Line 1.
     * @param tleLine2 NORAD TLE Line 2.
     * @param minutesOffset Offset in minutes from current UTC time (0.0 = live).
     * @return Map containing `valid`, `latitude`, `longitude`, `altitudeKm`, `velocityKmS`, `visibilityRadiusMeters`.
     */
    Q_INVOKABLE QVariantMap propagateTle(const QString &tleLine1, const QString &tleLine2, double minutesOffset = 0.0);

    /** @brief Computes ground track path for a single orbit window centered around current UTC time. */
    Q_INVOKABLE QVariantList computeGroundTrack(const QString &tleLine1, const QString &tleLine2, int totalMinutes = 96, int stepMinutes = 2);

    /**
     * @brief Computes previous (-1 orbit), current (0 orbit), and next (+1 orbit) trajectories.
     * @return Map with `"current"`, `"previous"`, `"next"` (`QVariantList` of `{lat, lon}`) and `"periodMinutes"`.
     */
    Q_INVOKABLE QVariantMap computeOrbitTracks(const QString &tleLine1, const QString &tleLine2, double stepMinutes = 0.75);

    /**
     * @brief Calculates maximum line-of-sight ground visibility radius [m] from satellite altitude.
     * Formula: $R_E \cdot \arccos(\frac{R_E}{R_E + h}\cos(\theta_{\min})) - \theta_{\min}$.
     */
    Q_INVOKABLE double calculateVisibilityRadius(double altitudeKm, double minElevationDeg = 0.0) const;

    /** @brief Returns current UTC date/time as an ISO/formatted string. */
    Q_INVOKABLE QString currentUtcIsoString() const;

    /**
     * @brief Predicts satellite pass windows across active ground stations (single & multi-station handover).
     * @param tleLine1 NORAD TLE Line 1.
     * @param tleLine2 NORAD TLE Line 2.
     * @param stations List of ground station parameter maps.
     * @param forecastHours Search window duration in hours (default: 24).
     * @param stepSeconds Coarse search step in seconds (default: 20.0).
     * @param startOffsetHours Offset in hours from current UTC time (0.0 = from now; negative = past passes).
     * @return Map with `valid` and `passes` list.
     */
    Q_INVOKABLE QVariantMap calculatePassWindows(const QString &tleLine1,
                                                const QString &tleLine2,
                                                const QVariantList &stations,
                                                int forecastHours = 24,
                                                double stepSeconds = 20.0,
                                                double startOffsetHours = 0.0);

    /**
     * @brief Predicts satellite pass windows within an explicit UTC date/time range `[startUtcIso, endUtcIso]`.
     */
    Q_INVOKABLE QVariantMap calculatePassWindowsInRange(const QString &tleLine1,
                                                       const QString &tleLine2,
                                                       const QVariantList &stations,
                                                       const QString &startUtcIso,
                                                       const QString &endUtcIso,
                                                       double stepSeconds = 20.0);

    /**
     * @brief Computes time-aligned FSPL, atmospheric loss, total loss, and SNR profiles for a pass window.
     */
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

    /**
     * @brief Computes the exact satellite ground trajectory `{latitude, longitude, altitudeKm}` for a pass window `[startUtcIso, endUtcIso]`.
     */
    Q_INVOKABLE QVariantList computeSessionTrajectory(const QString &tleLine1,
                                                      const QString &tleLine2,
                                                      const QString &startUtcIso,
                                                      const QString &endUtcIso,
                                                      double stepSeconds = 10.0) const;

    /**
     * @brief Computes max achievable code rate $r_{\max}$ for Adaptive Coding & Modulation (AMC).
     * Formula: $r_{\max} = \frac{1}{b \cdot (1 + \alpha)} \log_2\left(1 + \frac{10^{\mathrm{SNR}/10}}{\Gamma}\right)$.
     */
    Q_INVOKABLE double calculateRMax(double snrDb, double bitsPerSymbol, double alpha, double codeEfficiencyCoef) const;

    /** @brief Generates a YAML session plan string from pass event, SNR profile, and AMC parameters. */
    Q_INVOKABLE QString generateSessionPlanYaml(const QVariantMap &sessionEvent,
                                                const QVariantMap &snrProfileData,
                                                const QVariantMap &transmissionParams) const;

private:
    static bool extractTleLines(const QString &inLine1, const QString &inLine2,
                                QString &outName, QString &outLine1, QString &outLine2);
    QVariantMap computePassWindowsForInterval(const QString &tleLine1,
                                              const QString &tleLine2,
                                              const QVariantList &stations,
                                              const QDateTime &windowStartUtc,
                                              const QDateTime &windowEndUtc,
                                              double stepSeconds) const;
    QVariantList computeTrackRange(libsgp4::SGP4 &sgp4, const QDateTime &baseUtc,
                                   double startMinutesFromNow, double endMinutesFromNow, double stepMinutes) const;

    static constexpr double EarthRadiusKm = 6378.137; // WGS-84 equatorial radius
};
