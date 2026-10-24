#pragma once

#include <QString>
#include <QDateTime>
#include <QVariantMap>
#include <QVariantList>
#include <vector>
#include <memory>
#include <cmath>

namespace libsgp4 {
    class SGP4;
    class Observer;
}

/**
 * @brief Represents the aligned time-series vectors of signal loss and link budget for a single ground station.
 * Vector length is exactly equal to round(session_time * sample_rate) + 1.
 */
struct StationSignalLossSeries {
    QString stationId;
    QString stationName;
    double minElevationDeg = 5.0;
    double gOverTDbK = 17.5;        // Ground station Figure of Merit (G/T)
    double feederLossDb = 0.3;      // Feeder line loss
    double carrierFreqMhz = 5840.0; // Operating frequency (C-band default)

    // Aligned vectors of equal length N = session_time / sample_interval:
    std::vector<double> timestampsSec;     // Relative time from session start [s]
    std::vector<QString> utcTimeLabels;    // Absolute UTC timestamps ("HH:mm:ss")
    std::vector<double> elevationDeg;      // Satellite elevation angle [deg]
    std::vector<double> azimuthDeg;        // Satellite azimuth angle [deg]
    std::vector<double> slantRangeKm;      // Slant range to satellite [km]

    // Signal loss factor vectors [dB] (extensible for future loss components):
    std::vector<double> fsplLossDb;        // Free Space Path Loss (F7)
    std::vector<double> atmosphericLossDb; // Atmospheric gas/tropospheric attenuation
    std::vector<double> totalLossDb;       // Sum of all loss factors (fspl + atm + feeder)

    // Link budget and RF parameters:
    std::vector<double> rxPowerDbm;        // Received signal power at LNA input [dBm]
    std::vector<double> snrDb;             // Signal-to-Noise Ratio (C/N) [dB]
    std::vector<double> dopplerShiftHz;    // Frequency Doppler shift [Hz]
    std::vector<bool> isVisible;           // True when satellite >= minElevationDeg

    // Scalar pass metrics:
    double maxSnrDb = -999.0;
    double minFsplDb = 999.0;
    double maxElevationDeg = 0.0;
    double tcaRangeKm = 0.0;
    int visibleSampleCount = 0;
    int visibleDurationSeconds = 0;
    QString aosUtc;
    QString losUtc;
    QString tcaUtc;

    QVariantMap toVariantMap() const;
};

/**
 * @brief Represents the multi-station joint session analysis containing time-aligned SNR vectors for all stations.
 */
struct JointSessionSnrResult {
    bool valid = false;
    QString satelliteName;
    QDateTime startUtc;
    QDateTime endUtc;
    double durationSeconds = 0.0;
    double sampleRateHz = 1.0;
    int sampleCount = 0;

    // Transmit parameters (POLYITAN-3-PUT specification defaults):
    double txPowerDbm = 33.0;           // 2 W transmitter (+33 dBm)
    double txAntennaGainDbi = 3.0;      // CubeSat patch/helical antenna gain
    double carrierFreqMhz = 5840.0;     // Central carrier frequency (5830-5850 MHz C-band)
    double channelBandwidthKhz = 10000.0;// 10 MHz channel bandwidth

    // Theoretical Shannon-Hartley threshold limits (from PDF specification Section 2):
    double shannonRawThresholdDb = 0.0;       // Raw 10 Mb/s in 10 MHz -> SNR = 0 dB
    double shannonTurbocodeThresholdDb = 4.77;// Rate 1/2 Turbocode (20 Mb/s) -> SNR = 4.77 dB

    // Master time base vectors:
    std::vector<double> timestampsSec;
    std::vector<QString> utcLabels;

    // Participating ground stations:
    std::vector<StationSignalLossSeries> stationSeries;

    // Multi-station diversity envelope vectors:
    std::vector<double> combinedSelectionSnrDb; // Best station SNR at each second
    std::vector<double> combinedMrcSnrDb;       // Maximum Ratio Combining SNR envelope

    bool hasOverlap = false;
    double overlapDurationSeconds = 0.0;
    double maxDiversityGainDb = 0.0;

    QVariantMap toVariantMap() const;
};

/**
 * @brief Engine that computes FSPL, loss vectors, and link-budget SNR over a satellite pass window.
 */
class SignalLossModel {
public:
    // Core physical formulas:
    static double calculateFspl(double slantRangeKm, double freqMhz);
    static double calculateAtmosphericLoss(double elevationDeg, double freqMhz);
    static double calculateLinkBudgetSnr(double txPowerDbm, double txAntennaGainDbi,
                                         double totalLossDb, double gOverTDbK,
                                         double channelBandwidthKhz);
    static double calculateDopplerShift(double carrierFreqMhz, double rangeRateKmS);

    // Full session calculation:
    static JointSessionSnrResult computeJointSessionSnr(
        const QString &tleLine1,
        const QString &tleLine2,
        const QVariantList &stations,
        const QDateTime &startUtc,
        const QDateTime &endUtc,
        double sampleRateHz = 1.0,
        double txPowerDbm = 33.0,
        double txAntennaGainDbi = 3.0,
        double carrierFreqMhz = 5840.0,
        double channelBandwidthKhz = 10000.0
    );
};
