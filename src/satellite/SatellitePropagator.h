#pragma once

#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include <QString>
#include <cmath>

class SatellitePropagator : public QObject {
    Q_OBJECT
public:
    explicit SatellitePropagator(QObject *parent = nullptr);

    // Parses TLE lines and computes current position (lat, lon, alt) and visibility radius (meters)
    Q_INVOKABLE QVariantMap propagateTle(const QString &tleLine1, const QString &tleLine2, double minutesOffset = 0.0);

    // Computes ground track path for a full orbit period (e.g. -45 min to +45 min)
    Q_INVOKABLE QVariantList computeGroundTrack(const QString &tleLine1, const QString &tleLine2, int totalMinutes = 96, int stepMinutes = 2);

    // Calculates maximum line-of-sight visibility ground radius from satellite altitude (in meters)
    // Formula: R_E * arccos( (R_E / (R_E + h)) * cos(minElevation) ) - minElevation
    Q_INVOKABLE double calculateVisibilityRadius(double altitudeKm, double minElevationDeg = 0.0) const;

private:
    struct TleData {
        int satNumber = 0;
        int epochYear = 0;
        double epochDay = 0.0;
        double inclinationRad = 0.0;
        double raanRad = 0.0;
        double eccentricity = 0.0;
        double argPerigeeRad = 0.0;
        double meanAnomalyRad = 0.0;
        double meanMotionRevDay = 0.0;
        bool valid = false;
    };

    TleData parseTle(const QString &line1, const QString &line2) const;
    void propagateOrbit(const TleData &tle, double minutesFromEpoch, double &outLat, double &outLon, double &outAltKm) const;

    static constexpr double EarthRadiusKm = 6378.137;
    static constexpr double Mu = 398600.4418; // km^3 / s^2
    static constexpr double TwoPi = 6.28318530717958647692;
};
