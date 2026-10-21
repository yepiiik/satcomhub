#include "SignalLossModel.h"

#include <libsgp4/CoordGeodetic.h>
#include <libsgp4/DateTime.h>
#include <libsgp4/Eci.h>
#include <libsgp4/SGP4.h>
#include <libsgp4/Tle.h>
#include <libsgp4/Util.h>
#include <libsgp4/Observer.h>
#include <libsgp4/CoordTopocentric.h>

#include <QTimeZone>
#include <QRegularExpression>
#include <algorithm>
#include <numeric>

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

static bool extractTle(const QString &in1, const QString &in2,
                       QString &name, QString &line1, QString &line2) {
    QString t1 = in1.trimmed();
    QString t2 = in2.trimmed();

    if (t1.startsWith("1 ") && t2.startsWith("2 ")) {
        name = "SAT";
        line1 = t1;
        line2 = t2;
        return true;
    }

    QStringList lines = (t1 + "\n" + t2).split(QRegularExpression("[\r\n]+"), Qt::SkipEmptyParts);
    for (int i = 0; i < lines.size(); ++i) {
        QString trimmed = lines[i].trimmed();
        if (trimmed.startsWith("1 ") && (i + 1 < lines.size()) && lines[i + 1].trimmed().startsWith("2 ")) {
            name = (i > 0) ? lines[i - 1].trimmed() : "SAT";
            line1 = trimmed;
            line2 = lines[i + 1].trimmed();
            return true;
        }
    }
    return false;
}
} // namespace

double SignalLossModel::calculateFspl(double slantRangeKm, double freqMhz) {
    if (slantRangeKm <= 0.0 || freqMhz <= 0.0) return 0.0;
    // Standard FSPL formula: 20*log10(d_km) + 20*log10(f_MHz) + 32.4418
    return 20.0 * std::log10(slantRangeKm) + 20.0 * std::log10(freqMhz) + 32.4418;
}

double SignalLossModel::calculateAtmosphericLoss(double elevationDeg, double freqMhz) {
    Q_UNUSED(freqMhz);
    if (elevationDeg <= 0.0) return 3.0; // High attenuation near 0 horizon
    // Tropospheric cosecant law with zenith attenuation of ~0.075 dB at C-band
    double safeElRad = std::max(4.0, elevationDeg) * (M_PI / 180.0);
    double loss = 0.075 / std::sin(safeElRad);
    return std::clamp(loss, 0.05, 3.5);
}

double SignalLossModel::calculateLinkBudgetSnr(double txPowerDbm, double txAntennaGainDbi,
                                              double totalLossDb, double gOverTDbK,
                                              double channelBandwidthKhz) {
    if (channelBandwidthKhz <= 0.0) return -99.0;

    // 1. Satellite EIRP [dBW] = (P_tx [dBm] - 30) + G_tx [dBi]
    double eirpDbw = (txPowerDbm - 30.0) + txAntennaGainDbi;

    // 2. Boltzmann constant: k_B = 1.380649e-23 J/K -> -10*log10(k_B) = +228.599 dBW/(Hz*K)
    constexpr double boltzmannDbwHzK = 228.599;

    // 3. Noise Bandwidth in dBHz: 10*log10(B_Hz)
    double bwHz = channelBandwidthKhz * 1000.0;
    double bwDbHz = 10.0 * std::log10(bwHz);

    // 4. SNR (Carrier-to-Noise Ratio C/N):
    // SNR = EIRP - TotalLoss + G/T + 228.599 - 10*log10(B)
    double snrDb = eirpDbw - totalLossDb + gOverTDbK + boltzmannDbwHzK - bwDbHz;
    return snrDb;
}

double SignalLossModel::calculateDopplerShift(double carrierFreqMhz, double rangeRateKmS) {
    // Doppler equation: Delta_f = - f0 * (v_los / c)
    constexpr double cKmS = 299792.458;
    return - (carrierFreqMhz * 1e6) * (rangeRateKmS / cKmS);
}

JointSessionSnrResult SignalLossModel::computeJointSessionSnr(
    const QString &tleLine1,
    const QString &tleLine2,
    const QVariantList &stations,
    const QDateTime &startUtc,
    const QDateTime &endUtc,
    double sampleRateHz,
    double txPowerDbm,
    double txAntennaGainDbi,
    double carrierFreqMhz,
    double channelBandwidthKhz)
{
    JointSessionSnrResult result;
    result.valid = false;
    result.sampleRateHz = (sampleRateHz <= 0.0) ? 1.0 : std::clamp(sampleRateHz, 0.1, 10.0);
    result.txPowerDbm = txPowerDbm;
    result.txAntennaGainDbi = txAntennaGainDbi;
    result.carrierFreqMhz = (carrierFreqMhz <= 0.0) ? 5840.0 : carrierFreqMhz;
    result.channelBandwidthKhz = (channelBandwidthKhz <= 0.0) ? 10000.0 : channelBandwidthKhz;

    QString name, l1, l2;
    if (!extractTle(tleLine1, tleLine2, name, l1, l2)) {
        return result;
    }
    result.satelliteName = name;

    if (!startUtc.isValid() || !endUtc.isValid() || startUtc >= endUtc || stations.isEmpty()) {
        return result;
    }

    try {
        libsgp4::Tle tle(name.toStdString(), l1.toStdString(), l2.toStdString());
        libsgp4::SGP4 sgp4(tle);

        // Ground stations setup
        struct StationConfig {
            QString stationId;
            QString name;
            double lat = 0.0;
            double lon = 0.0;
            double altKm = 0.0;
            double minElDeg = 5.0;
            double gOverT = 17.5;
            double feederLoss = 0.3;
            double freqMhz = 5840.0;
            std::unique_ptr<libsgp4::Observer> observer;
        };

        std::vector<StationConfig> stationConfigs;
        for (const QVariant &stVar : stations) {
            QVariantMap m = stVar.toMap();
            StationConfig sc;
            sc.stationId = m.value("stationId").toString();
            sc.name = m.value("name").toString();
            sc.lat = m.value("latitude").toDouble();
            sc.lon = m.value("longitude").toDouble();
            sc.altKm = m.value("altitude", 0.0).toDouble() / 1000.0;
            sc.minElDeg = m.value("minElevation", 5.0).toDouble();
            if (sc.minElDeg <= 0.0) sc.minElDeg = 5.0;
            sc.gOverT = m.value("gOverT", 17.5).toDouble();
            sc.feederLoss = m.value("feederLoss", 0.3).toDouble();

            double stFreq = m.value("freqMinMhz", 0.0).toDouble();
            if (stFreq > 0.0) {
                double stFreqMax = m.value("freqMaxMhz", stFreq).toDouble();
                sc.freqMhz = (stFreq + stFreqMax) / 2.0;
            } else {
                sc.freqMhz = result.carrierFreqMhz;
            }

            sc.observer = std::make_unique<libsgp4::Observer>(sc.lat, sc.lon, sc.altKm);
            stationConfigs.push_back(std::move(sc));
        }

        if (stationConfigs.empty()) {
            return result;
        }

        result.startUtc = startUtc.toUTC();
        result.endUtc = endUtc.toUTC();
        qint64 totalDurSec = result.startUtc.secsTo(result.endUtc);
        if (totalDurSec <= 0) return result;

        result.durationSeconds = static_cast<double>(totalDurSec);
        double stepSec = 1.0 / result.sampleRateHz;
        int sampleCount = static_cast<int>(std::round(totalDurSec * result.sampleRateHz)) + 1;
        result.sampleCount = sampleCount;

        // Initialize master time vectors
        result.timestampsSec.resize(sampleCount);
        result.utcLabels.resize(sampleCount);

        // Preallocate station time-series vectors
        result.stationSeries.resize(stationConfigs.size());
        for (size_t s = 0; s < stationConfigs.size(); ++s) {
            auto &series = result.stationSeries[s];
            series.stationId = stationConfigs[s].stationId;
            series.stationName = stationConfigs[s].name;
            series.minElevationDeg = stationConfigs[s].minElDeg;
            series.gOverTDbK = stationConfigs[s].gOverT;
            series.feederLossDb = stationConfigs[s].feederLoss;
            series.carrierFreqMhz = stationConfigs[s].freqMhz;

            series.timestampsSec.resize(sampleCount);
            series.utcTimeLabels.resize(sampleCount);
            series.elevationDeg.resize(sampleCount);
            series.azimuthDeg.resize(sampleCount);
            series.slantRangeKm.resize(sampleCount);
            series.fsplLossDb.resize(sampleCount);
            series.atmosphericLossDb.resize(sampleCount);
            series.totalLossDb.resize(sampleCount);
            series.rxPowerDbm.resize(sampleCount);
            series.snrDb.resize(sampleCount);
            series.dopplerShiftHz.resize(sampleCount);
            series.isVisible.resize(sampleCount, false);
        }

        result.combinedSelectionSnrDb.resize(sampleCount, -25.0);
        result.combinedMrcSnrDb.resize(sampleCount, -25.0);

        int overlapSampleCount = 0;
        double maxDiversityGain = 0.0;

        // Sample along the unified session timeline
        for (int k = 0; k < sampleCount; ++k) {
            double relSec = k * stepSec;
            if (k == sampleCount - 1) {
                relSec = totalDurSec;
            }
            result.timestampsSec[k] = relSec;

            QDateTime curTime = result.startUtc.addMSecs(static_cast<qint64>(relSec * 1000.0));
            result.utcLabels[k] = curTime.toString("HH:mm:ss");

            libsgp4::DateTime dt = toSgp4DateTime(curTime);
            libsgp4::Eci eci(dt, 0.0, 0.0, 0.0);
            bool eciValid = false;
            try {
                eci = sgp4.FindPosition(dt);
                eciValid = true;
            } catch (...) {
                eciValid = false;
            }

            int visibleStationCountAtStep = 0;
            double bestSnrAtStep = -999.0;
            double sumLinearSnrAtStep = 0.0;

            for (size_t s = 0; s < stationConfigs.size(); ++s) {
                auto &series = result.stationSeries[s];
                series.timestampsSec[k] = relSec;
                series.utcTimeLabels[k] = result.utcLabels[k];

                if (!eciValid) {
                    series.elevationDeg[k] = 0.0;
                    series.azimuthDeg[k] = 0.0;
                    series.slantRangeKm[k] = 0.0;
                    series.fsplLossDb[k] = 0.0;
                    series.atmosphericLossDb[k] = 0.0;
                    series.totalLossDb[k] = 0.0;
                    series.rxPowerDbm[k] = -150.0;
                    series.snrDb[k] = -25.0; // Floor threshold
                    series.dopplerShiftHz[k] = 0.0;
                    series.isVisible[k] = false;
                    continue;
                }

                libsgp4::CoordTopocentric topo = stationConfigs[s].observer->GetLookAngle(eci);
                double elDeg = libsgp4::Util::RadiansToDegrees(topo.elevation);
                double azDeg = libsgp4::Util::RadiansToDegrees(topo.azimuth);
                double rangeKm = topo.range;
                double rangeRate = topo.rangeRate;

                series.elevationDeg[k] = std::round(elDeg * 100.0) / 100.0;
                series.azimuthDeg[k] = std::round(azDeg * 10.0) / 100.0;
                series.slantRangeKm[k] = std::round(rangeKm * 10.0) / 10.0;

                if (elDeg >= stationConfigs[s].minElDeg) {
                    series.isVisible[k] = true;
                    visibleStationCountAtStep++;

                    double fspl = calculateFspl(rangeKm, series.carrierFreqMhz);
                    double atm = calculateAtmosphericLoss(elDeg, series.carrierFreqMhz);
                    double totalLoss = fspl + atm + series.feederLossDb;

                    double snr = calculateLinkBudgetSnr(result.txPowerDbm, result.txAntennaGainDbi,
                                                        totalLoss, series.gOverTDbK,
                                                        result.channelBandwidthKhz);

                    // P_rx [dBm] = P_tx + G_tx - totalLoss + G_rx
                    double rxPower = result.txPowerDbm + result.txAntennaGainDbi - totalLoss;
                    double doppler = calculateDopplerShift(series.carrierFreqMhz, rangeRate);

                    series.fsplLossDb[k] = std::round(fspl * 100.0) / 100.0;
                    series.atmosphericLossDb[k] = std::round(atm * 100.0) / 100.0;
                    series.totalLossDb[k] = std::round(totalLoss * 100.0) / 100.0;
                    series.rxPowerDbm[k] = std::round(rxPower * 100.0) / 100.0;
                    series.snrDb[k] = std::round(snr * 100.0) / 100.0;
                    series.dopplerShiftHz[k] = std::round(doppler);

                    // Track maximums for this station
                    if (snr > series.maxSnrDb) {
                        series.maxSnrDb = series.snrDb[k];
                        series.tcaUtc = result.utcLabels[k];
                        series.tcaRangeKm = series.slantRangeKm[k];
                    }
                    if (fspl < series.minFsplDb) {
                        series.minFsplDb = series.fsplLossDb[k];
                    }
                    if (elDeg > series.maxElevationDeg) {
                        series.maxElevationDeg = series.elevationDeg[k];
                    }

                    if (series.visibleSampleCount == 0) {
                        series.aosUtc = result.utcLabels[k];
                    }
                    series.losUtc = result.utcLabels[k];
                    series.visibleSampleCount++;

                    // For combined multi-station envelope:
                    if (snr > bestSnrAtStep) {
                        bestSnrAtStep = snr;
                    }
                    sumLinearSnrAtStep += std::pow(10.0, snr / 10.0);
                } else {
                    series.isVisible[k] = false;
                    series.fsplLossDb[k] = 0.0;
                    series.atmosphericLossDb[k] = 0.0;
                    series.totalLossDb[k] = 0.0;
                    series.rxPowerDbm[k] = -150.0;
                    series.snrDb[k] = -25.0; // Below sensitivity floor
                    series.dopplerShiftHz[k] = 0.0;
                }
            }

            // Multi-station combined envelope:
            if (visibleStationCountAtStep > 0) {
                result.combinedSelectionSnrDb[k] = std::round(bestSnrAtStep * 100.0) / 100.0;

                // MRC combining: SNR_mrc = 10 * log10(sum(10^(snr_i/10)))
                double mrcSnr = 10.0 * std::log10(sumLinearSnrAtStep);
                result.combinedMrcSnrDb[k] = std::round(mrcSnr * 100.0) / 100.0;

                if (visibleStationCountAtStep >= 2) {
                    overlapSampleCount++;
                    double gain = mrcSnr - bestSnrAtStep;
                    if (gain > maxDiversityGain) {
                        maxDiversityGain = gain;
                    }
                }
            } else {
                result.combinedSelectionSnrDb[k] = -25.0;
                result.combinedMrcSnrDb[k] = -25.0;
            }
        }

        // Finalize summary metrics
        for (auto &series : result.stationSeries) {
            series.visibleDurationSeconds = static_cast<int>(std::round(series.visibleSampleCount * stepSec));
            if (series.minFsplDb > 900.0) series.minFsplDb = 0.0;
            if (series.maxSnrDb < -900.0) series.maxSnrDb = -25.0;
        }

        result.hasOverlap = (overlapSampleCount > 0);
        result.overlapDurationSeconds = std::round(overlapSampleCount * stepSec);
        result.maxDiversityGainDb = std::round(maxDiversityGain * 100.0) / 100.0;
        result.valid = true;
    } catch (...) {
        result.valid = false;
    }

    return result;
}

QVariantMap StationSignalLossSeries::toVariantMap() const {
    QVariantMap map;
    map["stationId"] = stationId;
    map["stationName"] = stationName;
    map["minElevationDeg"] = minElevationDeg;
    map["gOverTDbK"] = gOverTDbK;
    map["feederLossDb"] = feederLossDb;
    map["carrierFreqMhz"] = carrierFreqMhz;

    QVariantList tsList, utcList, elList, azList, rangeList, fsplList, atmList, totList, rxList, snrList, dopList, visList;
    tsList.reserve(timestampsSec.size());
    utcList.reserve(utcTimeLabels.size());
    elList.reserve(elevationDeg.size());
    azList.reserve(azimuthDeg.size());
    rangeList.reserve(slantRangeKm.size());
    fsplList.reserve(fsplLossDb.size());
    atmList.reserve(atmosphericLossDb.size());
    totList.reserve(totalLossDb.size());
    rxList.reserve(rxPowerDbm.size());
    snrList.reserve(snrDb.size());
    dopList.reserve(dopplerShiftHz.size());
    visList.reserve(isVisible.size());

    for (size_t i = 0; i < timestampsSec.size(); ++i) {
        tsList.append(timestampsSec[i]);
        utcList.append(utcTimeLabels[i]);
        elList.append(elevationDeg[i]);
        azList.append(azimuthDeg[i]);
        rangeList.append(slantRangeKm[i]);
        fsplList.append(fsplLossDb[i]);
        atmList.append(atmosphericLossDb[i]);
        totList.append(totalLossDb[i]);
        rxList.append(rxPowerDbm[i]);
        snrList.append(snrDb[i]);
        dopList.append(dopplerShiftHz[i]);
        visList.append(isVisible[i]);
    }

    map["timestampsSec"] = tsList;
    map["utcTimeLabels"] = utcList;
    map["elevationDeg"] = elList;
    map["azimuthDeg"] = azList;
    map["slantRangeKm"] = rangeList;
    map["fsplLossDb"] = fsplList;
    map["atmosphericLossDb"] = atmList;
    map["totalLossDb"] = totList;
    map["rxPowerDbm"] = rxList;
    map["snrDb"] = snrList;
    map["dopplerShiftHz"] = dopList;
    map["isVisible"] = visList;

    map["maxSnrDb"] = maxSnrDb;
    map["minFsplDb"] = minFsplDb;
    map["maxElevationDeg"] = maxElevationDeg;
    map["tcaRangeKm"] = tcaRangeKm;
    map["visibleDurationSeconds"] = visibleDurationSeconds;
    map["aosUtc"] = aosUtc;
    map["losUtc"] = losUtc;
    map["tcaUtc"] = tcaUtc;

    return map;
}

QVariantMap JointSessionSnrResult::toVariantMap() const {
    QVariantMap map;
    map["valid"] = valid;
    map["satelliteName"] = satelliteName;
    map["startUtc"] = startUtc.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
    map["endUtc"] = endUtc.toString("yyyy-MM-dd HH:mm:ss 'UTC'");
    map["durationSeconds"] = durationSeconds;
    map["sampleRateHz"] = sampleRateHz;
    map["sampleCount"] = sampleCount;
    map["carrierFreqMhz"] = carrierFreqMhz;
    map["txPowerDbm"] = txPowerDbm;
    map["txAntennaGainDbi"] = txAntennaGainDbi;
    map["channelBandwidthKhz"] = channelBandwidthKhz;

    map["shannonRawThresholdDb"] = shannonRawThresholdDb;
    map["shannonTurbocodeThresholdDb"] = shannonTurbocodeThresholdDb;

    QVariantList tsList, utcList, selList, mrcList;
    tsList.reserve(timestampsSec.size());
    utcList.reserve(utcLabels.size());
    selList.reserve(combinedSelectionSnrDb.size());
    mrcList.reserve(combinedMrcSnrDb.size());

    for (size_t i = 0; i < timestampsSec.size(); ++i) {
        tsList.append(timestampsSec[i]);
        utcList.append(utcLabels[i]);
        selList.append(combinedSelectionSnrDb[i]);
        mrcList.append(combinedMrcSnrDb[i]);
    }

    map["timestampsSec"] = tsList;
    map["utcLabels"] = utcList;
    map["combinedSelectionSnrDb"] = selList;
    map["combinedMrcSnrDb"] = mrcList;

    QVariantList stList;
    for (const auto &s : stationSeries) {
        stList.append(s.toVariantMap());
    }
    map["stations"] = stList;

    map["hasOverlap"] = hasOverlap;
    map["overlapDurationSeconds"] = overlapDurationSeconds;
    map["maxDiversityGainDb"] = maxDiversityGainDb;

    return map;
}
