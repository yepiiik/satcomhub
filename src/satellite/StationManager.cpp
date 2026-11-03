#include "StationManager.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QDateTime>
#include <QCoreApplication>
#include <QRegularExpression>
#include <QSet>
#include <QDesktopServices>
#include <QUrl>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commdlg.h>
#endif

StationManager::StationManager(QObject *parent)
    : QObject(parent)
{
}

void StationManager::getBandFrequencies(const QString &band, double customMin, double customMax,
                                        double &outMinMhz, double &outMaxMhz)
{
    if (customMin > 0.0 && customMax >= customMin) {
        outMinMhz = customMin;
        outMaxMhz = customMax;
        return;
    }

    QString b = band.trimmed().toLower();
    if (b.contains("c-band") || b == "c") {
        outMinMhz = 4000.0;
        outMaxMhz = 8000.0;
    } else if (b.contains("s-band") || b == "s") {
        outMinMhz = 2000.0;
        outMaxMhz = 4000.0;
    } else if (b.contains("x-band") || b == "x") {
        outMinMhz = 8000.0;
        outMaxMhz = 12000.0;
    } else if (b.contains("ku-band") || b == "ku") {
        outMinMhz = 12000.0;
        outMaxMhz = 18000.0;
    } else if (b.contains("ka-band") || b == "ka") {
        outMinMhz = 26500.0;
        outMaxMhz = 40000.0;
    } else if (b.contains("l-band") || b == "l") {
        outMinMhz = 1000.0;
        outMaxMhz = 2000.0;
    } else if (b.contains("uhf")) {
        outMinMhz = 400.0;
        outMaxMhz = 470.0;
    } else if (b.contains("vhf")) {
        outMinMhz = 136.0;
        outMaxMhz = 174.0;
    } else if (b.contains("custom")) {
        outMinMhz = (customMin > 0.0) ? customMin : 2000.0;
        outMaxMhz = (customMax > outMinMhz) ? customMax : (outMinMhz + 500.0);
    } else {
        // Default to C-band if unrecognized
        outMinMhz = 4000.0;
        outMaxMhz = 8000.0;
    }
}

QVariantMap StationManager::computeDerivedParameters(
    const QString &band,
    double lnaNfDb,
    double feederLossDb,
    double antennaGainDbi,
    double customFMinMhz,
    double customFMaxMhz,
    double antennaSkyNoiseK)
{
    QVariantMap res;

    // 1. Operating Band Frequencies & Channel Width
    double fMinMhz = 0.0;
    double fMaxMhz = 0.0;
    getBandFrequencies(band, customFMinMhz, customFMaxMhz, fMinMhz, fMaxMhz);
    double maxChannelWidthMhz = std::max(0.0, fMaxMhz - fMinMhz);

    // 2. Average Frequency & Wavelength
    double fAvgMhz = (fMinMhz + fMaxMhz) / 2.0;
    if (fAvgMhz <= 0.0) fAvgMhz = 4000.0;
    const double c = 299792458.0; // speed of light in m/s
    double wavelength = c / (fAvgMhz * 1e6); // in meters

    // 3. Dish Diameter (D) [m] from antenna gain and avg frequency (aperture efficiency eta = 0.55)
    // G_lin = eta * (pi * D / lambda)^2  =>  D = (lambda / pi) * sqrt(G_lin / eta)
    const double eta = 0.55;
    double gLinear = std::pow(10.0, antennaGainDbi / 10.0);
    double dishDiameterM = (wavelength / M_PI) * std::sqrt(gLinear / eta);
    if (dishDiameterM < 0.01) dishDiameterM = 0.01;

    // 4. Half-Power Beamwidth HPBW [deg]: theta ~ 70 * (lambda / D)
    double beamwidthHpbwDeg = 70.0 * (wavelength / dishDiameterM);

    // 5. Friis Noise Calculations:
    // Total Cascade Noise Figure = LNA NF + Feeder Loss (feeder before LNA)
    double safeLnaNf = std::max(0.0, lnaNfDb);
    double safeLoss = std::max(0.0, feederLossDb);
    double totalNoiseFigureDb = safeLnaNf + safeLoss;

    // Linear noise factor F = 10^(NF / 10)
    double fLinear = std::pow(10.0, totalNoiseFigureDb / 10.0);

    // Receiver noise temperature Te = T0 * (F - 1), where T0 = 290 K standard reference
    const double T0 = 290.0;
    double receiverNoiseTempK = T0 * (fLinear - 1.0);
    if (receiverNoiseTempK < 0.0) receiverNoiseTempK = 0.0;

    // Clear sky background antenna noise temperature
    double TantK = (antennaSkyNoiseK > 0.0) ? antennaSkyNoiseK : 40.0;
    double systemNoiseTempK = receiverNoiseTempK + TantK;

    // 6. Antenna G/T Figure of Merit [dB/K] = G [dBi] - 10 * log10(Tsys)
    double gOverT = 0.0;
    if (systemNoiseTempK > 0.0) {
        gOverT = antennaGainDbi - 10.0 * std::log10(systemNoiseTempK);
    }

    res["operating_band"] = band;
    res["freq_min_mhz"] = std::round(fMinMhz * 100.0) / 100.0;
    res["freq_max_mhz"] = std::round(fMaxMhz * 100.0) / 100.0;
    res["max_channel_width_mhz"] = std::round(maxChannelWidthMhz * 100.0) / 100.0;

    res["dish_diameter_m"] = std::round(dishDiameterM * 100.0) / 100.0;
    res["beamwidth_hpbw_deg"] = std::round(beamwidthHpbwDeg * 100.0) / 100.0;

    res["lna_noise_figure_db"] = std::round(safeLnaNf * 100.0) / 100.0;
    res["feeder_loss_db"] = std::round(safeLoss * 100.0) / 100.0;
    res["total_noise_figure_db"] = std::round(totalNoiseFigureDb * 100.0) / 100.0;
    res["receiver_noise_temp_k"] = std::round(receiverNoiseTempK * 10.0) / 10.0;
    res["antenna_noise_temp_k"] = TantK;
    res["system_noise_temp_k"] = std::round(systemNoiseTempK * 10.0) / 10.0;

    res["antenna_gain_dbi"] = std::round(antennaGainDbi * 10.0) / 10.0;
    res["g_over_t_db_k"] = std::round(gOverT * 100.0) / 100.0;

    return res;
}

QString StationManager::buildStationJson(const QVariantMap &stationData)
{
    QJsonObject root;
    QString stationId = stationData.value("stationId").toString();
    QString name = stationData.value("name").toString();
    double lat = stationData.value("latitude").toDouble();
    double lon = stationData.value("longitude").toDouble();
    double alt = stationData.value("altitude", 0.0).toDouble();
    bool altSpecified = stationData.value("altitudeSpecified", true).toBool();
    QString mobility = stationData.value("mobility", "stationary").toString();
    double minElevation = stationData.value("minElevation", 5.0).toDouble();

    QString band = stationData.value("operatingBand", "C-band").toString();
    QString polarization = stationData.value("polarization", "RHCP").toString();
    double gain = stationData.value("antennaGain", 38.5).toDouble();
    double lnaNf = stationData.value("lnaNf", 0.7).toDouble();
    double feederLoss = stationData.value("feederLoss", 0.3).toDouble();

    double customFMin = stationData.value("freqMinMhz", 0.0).toDouble();
    double customFMax = stationData.value("freqMaxMhz", 0.0).toDouble();
    if (customFMin <= 0.0 && stationData.contains("frequency_min_mhz")) {
        customFMin = stationData.value("frequency_min_mhz").toDouble();
    }
    if (customFMax <= 0.0 && stationData.contains("frequency_max_mhz")) {
        customFMax = stationData.value("frequency_max_mhz").toDouble();
    }

    double skyNoise = stationData.value("antennaSkyNoiseK", stationData.value("antenna_sky_noise_k", 40.0)).toDouble();
    if (skyNoise <= 0.0) skyNoise = 40.0;

    QVariantMap derived = computeDerivedParameters(band, lnaNf, feederLoss, gain, customFMin, customFMax, skyNoise);

    root["version"] = "1.0";
    root["type"] = "ground_station_antenna";
    root["stationId"] = stationId;
    root["name"] = name;
    root["mobility"] = mobility;
    root["min_elevation_deg"] = minElevation;

    // Coordinates block
    QJsonObject coords;
    coords["latitude"] = lat;
    coords["longitude"] = lon;
    if (altSpecified) {
        coords["altitude_m"] = alt;
    } else {
        coords["altitude_m"] = QJsonValue::Null;
    }
    coords["altitude_specified"] = altSpecified;
    root["coordinates"] = coords;

    // RF & Antenna Configuration block
    QJsonObject rf;
    rf["operating_band"] = band;
    rf["frequency_min_mhz"] = derived["freq_min_mhz"].toDouble();
    rf["frequency_max_mhz"] = derived["freq_max_mhz"].toDouble();
    rf["max_channel_width_mhz"] = derived["max_channel_width_mhz"].toDouble();
    rf["frequency_min_ghz"] = std::round((derived["freq_min_mhz"].toDouble() / 1000.0) * 1000.0) / 1000.0;
    rf["frequency_max_ghz"] = std::round((derived["freq_max_mhz"].toDouble() / 1000.0) * 1000.0) / 1000.0;
    rf["max_channel_width_ghz"] = std::round((derived["max_channel_width_mhz"].toDouble() / 1000.0) * 1000.0) / 1000.0;
    rf["polarization"] = polarization;
    rf["antenna_gain_dbi"] = gain;
    rf["lna_noise_figure_db"] = lnaNf;
    rf["feeder_loss_db"] = feederLoss;
    rf["total_noise_figure_db"] = derived["total_noise_figure_db"].toDouble();
    rf["receiver_noise_temp_k"] = derived["receiver_noise_temp_k"].toDouble();
    rf["antenna_noise_temp_k"] = derived["antenna_noise_temp_k"].toDouble();
    rf["system_noise_temp_k"] = derived["system_noise_temp_k"].toDouble();
    rf["g_over_t_db_k"] = derived["g_over_t_db_k"].toDouble();
    root["rf_configuration"] = rf;

    // Advanced Parameters block
    bool advOverridden = stationData.value("advancedFieldsOverridden", false).toBool();
    if (stationData.contains("metadata") && stationData.value("metadata").toMap().contains("advanced_fields_overridden")) {
        advOverridden = stationData.value("metadata").toMap().value("advanced_fields_overridden").toBool();
    }

    double dishD = stationData.contains("dishDiameterM") ? stationData.value("dishDiameterM").toDouble()
                 : (stationData.contains("dish_diameter_m") ? stationData.value("dish_diameter_m").toDouble()
                 : derived["dish_diameter_m"].toDouble());
    double hpbw = stationData.contains("beamwidthHpbwDeg") ? stationData.value("beamwidthHpbwDeg").toDouble()
                : (stationData.contains("beamwidth_hpbw_deg") ? stationData.value("beamwidth_hpbw_deg").toDouble()
                : derived["beamwidth_hpbw_deg"].toDouble());
    QString radome = stationData.value("radomeProtection",
                     stationData.value("radome_protection", "None / Open Air")).toString();
    QString mount = stationData.value("mountType",
                    stationData.value("mount_type", "Az-El")).toString();
    double pointingAcc = stationData.value("pointingAccuracyDeg",
                         stationData.value("pointing_accuracy_deg", 0.15)).toDouble();
    double slewRate = stationData.value("maxSlewRateDegS",
                      stationData.value("max_slew_rate_deg_s", 5.0)).toDouble();
    double modemLoss = stationData.value("modemImplementationLossDb",
                       stationData.value("modem_implementation_loss_db", 1.0)).toDouble();
    QString clutter = stationData.value("environmentClutter",
                      stationData.value("environment_clutter", "Urban")).toString();

    QJsonObject advObj;
    advObj["dish_diameter_m"] = std::round(dishD * 100.0) / 100.0;
    advObj["beamwidth_hpbw_deg"] = std::round(hpbw * 100.0) / 100.0;
    advObj["radome_protection"] = radome;
    advObj["mount_type"] = mount;
    advObj["pointing_accuracy_deg"] = std::round(pointingAcc * 1000.0) / 1000.0;
    advObj["max_slew_rate_deg_s"] = std::round(slewRate * 10.0) / 10.0;
    advObj["antenna_sky_noise_k"] = std::round(skyNoise * 10.0) / 10.0;
    advObj["modem_implementation_loss_db"] = std::round(modemLoss * 100.0) / 100.0;
    advObj["environment_clutter"] = clutter;
    root["advanced_parameters"] = advObj;

    // Metadata block
    QJsonObject metaObj;
    metaObj["advanced_fields_overridden"] = advOverridden;
    metaObj["created_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    root["metadata"] = metaObj;

    QJsonDocument doc(root);
    return QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
}

QVariantMap StationManager::parseStationJson(const QString &jsonString)
{
    QVariantMap result;
    result["valid"] = false;

    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(jsonString.trimmed().toUtf8(), &parseErr);
    if (parseErr.error != QJsonParseError::NoError) {
        result["error"] = QString("JSON parse error: %1").arg(parseErr.errorString());
        return result;
    }

    QJsonObject obj;
    if (doc.isObject()) {
        obj = doc.object();
        // If wrapped in a single key like "station" or "antenna"
        if (obj.contains("station") && obj["station"].isObject()) {
            obj = obj["station"].toObject();
        }
    } else if (doc.isArray()) {
        QJsonArray arr = doc.array();
        if (!arr.isEmpty() && arr.first().isObject()) {
            obj = arr.first().toObject();
        } else {
            result["error"] = "Empty or invalid JSON array";
            return result;
        }
    } else {
        result["error"] = "JSON is neither an object nor an array";
        return result;
    }

    // Extract Station Name
    QString name = obj.value("name").toString();
    if (name.isEmpty()) name = obj.value("station_name").toString();
    if (name.isEmpty()) name = "Imported Station";

    // Extract Station ID
    QString id = obj.value("stationId").toString();
    if (id.isEmpty()) id = obj.value("station_id").toString();
    if (id.isEmpty()) id = obj.value("id").toString();

    // Coordinates extraction
    double lat = 0.0;
    double lon = 0.0;
    double alt = 0.0;
    bool altSpecified = false;

    if (obj.contains("coordinates") && obj["coordinates"].isObject()) {
        QJsonObject coords = obj["coordinates"].toObject();
        lat = coords.value("latitude").toDouble(coords.value("lat").toDouble(0.0));
        lon = coords.value("longitude").toDouble(coords.value("lon").toDouble(0.0));
        if (coords.contains("altitude_m") && !coords["altitude_m"].isNull()) {
            alt = coords.value("altitude_m").toDouble();
            altSpecified = true;
        } else if (coords.contains("altitude") && !coords["altitude"].isNull()) {
            alt = coords.value("altitude").toDouble();
            altSpecified = true;
        }
    } else {
        lat = obj.value("latitude").toDouble(obj.value("lat").toDouble(0.0));
        lon = obj.value("longitude").toDouble(obj.value("lon").toDouble(0.0));
        if (obj.contains("altitude") && !obj["altitude"].isNull()) {
            alt = obj.value("altitude").toDouble();
            altSpecified = true;
        }
    }

    // Mobility
    QString mobility = obj.value("mobility").toString();
    if (mobility.isEmpty()) mobility = obj.value("mobility_type").toString();
    if (mobility.toLower() != "mobile") mobility = "Stationary";
    else mobility = "Mobile";

    // Min elevation
    double minElevation = 5.0;
    if (obj.contains("min_elevation_deg")) minElevation = obj.value("min_elevation_deg").toDouble(5.0);
    else if (obj.contains("minElevation")) minElevation = obj.value("minElevation").toDouble(5.0);
    else if (obj.contains("elevation_mask")) minElevation = obj.value("elevation_mask").toDouble(5.0);

    // RF Configuration
    QString band = "C-band";
    QString polarization = "RHCP";
    double gain = 38.5;
    double lnaNf = 0.7;
    double feederLoss = 0.3;
    double fMinMhz = 0.0;
    double fMaxMhz = 0.0;

    if (obj.contains("rf_configuration") && obj["rf_configuration"].isObject()) {
        QJsonObject rf = obj["rf_configuration"].toObject();
        if (rf.contains("operating_band")) band = rf.value("operating_band").toString();
        else if (rf.contains("band")) band = rf.value("band").toString();

        if (rf.contains("frequency_min_mhz")) fMinMhz = rf.value("frequency_min_mhz").toDouble();
        if (rf.contains("frequency_max_mhz")) fMaxMhz = rf.value("frequency_max_mhz").toDouble();

        if (rf.contains("polarization")) polarization = rf.value("polarization").toString();
        if (rf.contains("antenna_gain_dbi")) gain = rf.value("antenna_gain_dbi").toDouble(38.5);
        if (rf.contains("lna_noise_figure_db")) lnaNf = rf.value("lna_noise_figure_db").toDouble(0.7);
        if (rf.contains("feeder_loss_db")) feederLoss = rf.value("feeder_loss_db").toDouble(0.3);
    } else {
        if (obj.contains("operatingBand")) band = obj.value("operatingBand").toString();
        else if (obj.contains("band")) band = obj.value("band").toString();

        if (obj.contains("freqMinMhz")) fMinMhz = obj.value("freqMinMhz").toDouble();
        else if (obj.contains("frequency_min_mhz")) fMinMhz = obj.value("frequency_min_mhz").toDouble();

        if (obj.contains("freqMaxMhz")) fMaxMhz = obj.value("freqMaxMhz").toDouble();
        else if (obj.contains("frequency_max_mhz")) fMaxMhz = obj.value("frequency_max_mhz").toDouble();

        if (obj.contains("polarization")) polarization = obj.value("polarization").toString();
        if (obj.contains("antennaGain")) gain = obj.value("antennaGain").toDouble(38.5);
        if (obj.contains("lnaNf")) lnaNf = obj.value("lnaNf").toDouble(0.7);
        if (obj.contains("feederLoss")) feederLoss = obj.value("feederLoss").toDouble(0.3);
    }

    // Advanced parameters extraction
    double dishD = 0.0;
    double hpbw = 0.0;
    QString radome = "None / Open Air";
    QString mount = "Az-El";
    double pointingAcc = 0.15;
    double slewRate = 5.0;
    double skyNoise = 40.0;
    double modemLoss = 1.0;
    QString clutter = "Urban";
    bool advOverridden = false;

    if (obj.contains("advanced_parameters") && obj["advanced_parameters"].isObject()) {
        QJsonObject adv = obj["advanced_parameters"].toObject();
        dishD = adv.value("dish_diameter_m").toDouble(0.0);
        hpbw = adv.value("beamwidth_hpbw_deg").toDouble(0.0);
        if (adv.contains("radome_protection")) radome = adv.value("radome_protection").toString();
        if (adv.contains("mount_type")) mount = adv.value("mount_type").toString();
        pointingAcc = adv.value("pointing_accuracy_deg").toDouble(0.15);
        slewRate = adv.value("max_slew_rate_deg_s").toDouble(5.0);
        skyNoise = adv.value("antenna_sky_noise_k").toDouble(40.0);
        modemLoss = adv.value("modem_implementation_loss_db").toDouble(1.0);
        if (adv.contains("environment_clutter")) clutter = adv.value("environment_clutter").toString();
    }

    if (obj.contains("metadata") && obj["metadata"].isObject()) {
        QJsonObject meta = obj["metadata"].toObject();
        advOverridden = meta.value("advanced_fields_overridden").toBool(false);
    }

    // Compute derived parameters
    QVariantMap derived = computeDerivedParameters(band, lnaNf, feederLoss, gain, fMinMhz, fMaxMhz, skyNoise);

    if (dishD <= 0.0) dishD = derived["dish_diameter_m"].toDouble();
    if (hpbw <= 0.0) hpbw = derived["beamwidth_hpbw_deg"].toDouble();

    result["valid"] = true;
    result["stationId"] = id;
    result["name"] = name;
    result["latitude"] = lat;
    result["longitude"] = lon;
    result["altitude"] = alt;
    result["altitudeSpecified"] = altSpecified;
    result["mobility"] = mobility;
    result["minElevation"] = minElevation;

    result["operatingBand"] = band;
    result["polarization"] = polarization;
    result["antennaGain"] = gain;
    result["lnaNf"] = lnaNf;
    result["feederLoss"] = feederLoss;

    result["freqMinMhz"] = derived["freq_min_mhz"];
    result["freqMaxMhz"] = derived["freq_max_mhz"];
    result["maxChannelWidthMhz"] = derived["max_channel_width_mhz"];
    result["totalNoiseFigureDb"] = derived["total_noise_figure_db"];
    result["systemNoiseTempK"] = derived["system_noise_temp_k"];
    result["gOverT"] = derived["g_over_t_db_k"];

    result["dishDiameterM"] = dishD;
    result["beamwidthHpbwDeg"] = hpbw;
    result["radomeProtection"] = radome;
    result["mountType"] = mount;
    result["pointingAccuracyDeg"] = pointingAcc;
    result["maxSlewRateDegS"] = slewRate;
    result["antennaSkyNoiseK"] = skyNoise;
    result["modemImplementationLossDb"] = modemLoss;
    result["environmentClutter"] = clutter;
    result["advancedFieldsOverridden"] = advOverridden;

    result["estDishDiameterM"] = derived["dish_diameter_m"];
    result["estBeamwidthHpbwDeg"] = derived["beamwidth_hpbw_deg"];

    result["stationJson"] = buildStationJson(result);

    return result;
}

QString StationManager::openFileDialog(const QString &title, const QString &filter)
{
    Q_UNUSED(filter);
#ifdef _WIN32
    wchar_t szFile[MAX_PATH] = L"";
    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFilter = L"JSON Station Configurations (*.json)\0*.json\0All Files (*.*)\0*.*\0";
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = sizeof(szFile) / sizeof(szFile[0]);
    std::wstring titleW = title.toStdWString();
    ofn.lpstrTitle = titleW.c_str();
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    if (GetOpenFileNameW(&ofn)) {
        return QString::fromWCharArray(szFile);
    }
#endif
    return QString();
}

QString StationManager::saveFileDialog(const QString &title, const QString &defaultFileName, const QString &filter)
{
    Q_UNUSED(filter);
#ifdef _WIN32
    wchar_t szFile[MAX_PATH] = L"";
    std::wstring defNameW = defaultFileName.toStdWString();
    wcsncpy_s(szFile, defNameW.c_str(), _TRUNCATE);

    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFilter = L"JSON Station Configurations (*.json)\0*.json\0All Files (*.*)\0*.*\0";
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = sizeof(szFile) / sizeof(szFile[0]);
    ofn.lpstrDefExt = L"json";
    std::wstring titleW = title.toStdWString();
    ofn.lpstrTitle = titleW.c_str();
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT | OFN_NOCHANGEDIR;

    if (GetSaveFileNameW(&ofn)) {
        return QString::fromWCharArray(szFile);
    }
#endif
    return QString();
}

QString StationManager::readTextFile(const QString &filePath)
{
    QString cleanPath = filePath;
    if (cleanPath.startsWith("file:///")) {
#ifdef _WIN32
        cleanPath = cleanPath.mid(8);
#else
        cleanPath = cleanPath.mid(7);
#endif
    }
    QFile file(cleanPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(file.readAll());
}

bool StationManager::writeTextFile(const QString &filePath, const QString &content)
{
    QString cleanPath = filePath;
    if (cleanPath.startsWith("file:///")) {
#ifdef _WIN32
        cleanPath = cleanPath.mid(8);
#else
        cleanPath = cleanPath.mid(7);
#endif
    }
    QFile file(cleanPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }
    file.write(content.toUtf8());
    file.close();
    return true;
}

QString StationManager::getSampleStationJson(const QString &band)
{
    QVariantMap sample;
    sample["stationId"] = "GS-SAMPLE";
    sample["mobility"] = "Stationary";
    sample["minElevation"] = 5.0;
    sample["altitudeSpecified"] = true;

    QString b = band.trimmed().toLower();
    if (b.contains("c-band") || b == "c") {
        sample["name"] = "Warsaw Primary C-Band Hub";
        sample["latitude"] = 52.2297;
        sample["longitude"] = 21.0122;
        sample["altitude"] = 220.0;
        sample["operatingBand"] = "C-band";
        sample["polarization"] = "RHCP";
        sample["antennaGain"] = 38.5;
        sample["lnaNf"] = 0.70;
        sample["feederLoss"] = 0.30;
    } else if (b.contains("s-band") || b == "s") {
        sample["name"] = "Gdansk Coastal S-Band Relay";
        sample["latitude"] = 54.3520;
        sample["longitude"] = 18.6466;
        sample["altitude"] = 45.0;
        sample["operatingBand"] = "S-band";
        sample["polarization"] = "LHCP";
        sample["antennaGain"] = 30.0;
        sample["lnaNf"] = 0.85;
        sample["feederLoss"] = 0.25;
    } else if (b.contains("ku-band") || b == "ku") {
        sample["name"] = "Krakow Southern Ku-Band Gateway";
        sample["latitude"] = 50.0647;
        sample["longitude"] = 19.9450;
        sample["altitude"] = 380.0;
        sample["operatingBand"] = "Ku-band";
        sample["polarization"] = "Linear";
        sample["antennaGain"] = 48.0;
        sample["lnaNf"] = 0.90;
        sample["feederLoss"] = 0.40;
    } else {
        sample["name"] = "Wroclaw X-Band Deep Link";
        sample["latitude"] = 51.1079;
        sample["longitude"] = 17.0385;
        sample["altitude"] = 175.0;
        sample["operatingBand"] = "X-band";
        sample["polarization"] = "RHCP";
        sample["antennaGain"] = 43.5;
        sample["lnaNf"] = 0.75;
        sample["feederLoss"] = 0.35;
    }

    return buildStationJson(sample);
}

QString StationManager::getStationsDirectory() const
{
    QString baseDir;
    QString portablePath = QCoreApplication::applicationDirPath() + "/stations";
    if (QDir(portablePath).exists()) {
        return QDir(portablePath).absolutePath();
    }

    baseDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (baseDir.isEmpty()) {
        baseDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    }
    if (baseDir.isEmpty()) {
        baseDir = QDir::homePath() + "/AppData/Roaming/satcomhub";
    }

    if (baseDir.endsWith("/satcomhub/satcomhub", Qt::CaseInsensitive)) {
        baseDir = baseDir.left(baseDir.length() - 10);
    }

    QDir stationsDir(baseDir + "/stations");
    if (!stationsDir.exists()) {
        stationsDir.mkpath(".");
    }
    return stationsDir.absolutePath();
}

void StationManager::openStationsFolder()
{
    QString path = getStationsDirectory();
    QDir().mkpath(path);
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

QString StationManager::getDefaultStoragePath() const
{
    QDir dir(getStationsDirectory());
    return dir.filePath("stations.json");
}

bool StationManager::saveStationFile(const QVariantMap &stationData)
{
    QString id = stationData.value("stationId").toString().trimmed();
    if (id.isEmpty()) {
        id = "station_" + QString::number(QDateTime::currentMSecsSinceEpoch());
    }
    QString safeId = id;
    safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString dirPath = getStationsDirectory();
    QDir().mkpath(dirPath);
    QString filePath = QDir(dirPath).filePath(safeId + ".json");

    QString json = buildStationJson(stationData);
    return writeTextFile(filePath, json);
}

bool StationManager::deleteStationFile(const QString &stationId)
{
    QString safeId = stationId.trimmed();
    safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString dirPath = getStationsDirectory();
    QDir dir(dirPath);
    QString filePath = dir.filePath(safeId + ".json");
    if (QFile::exists(filePath)) {
        return dir.remove(safeId + ".json");
    }
    return false;
}

bool StationManager::saveStationsToDisk(const QVariantList &stations)
{
    QString dirPath = getStationsDirectory();
    QDir dir(dirPath);
    dir.mkpath(".");

    QSet<QString> activeFiles;
    QJsonArray arr;

    for (const QVariant &item : stations) {
        QVariantMap map = item.toMap();
        QString id = map.value("stationId").toString().trimmed();
        if (id.isEmpty()) {
            id = "GS-" + QString::number(activeFiles.size() + 1);
            map["stationId"] = id;
        }

        QString safeId = id;
        safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");
        QString filename = safeId + ".json";
        activeFiles.insert(filename);

        QString stationJson = buildStationJson(map);
        writeTextFile(dir.filePath(filename), stationJson);

        QJsonDocument doc = QJsonDocument::fromJson(stationJson.toUtf8());
        if (doc.isObject()) {
            arr.append(doc.object());
        }
    }

    QStringList existingJsonFiles = dir.entryList(QStringList() << "*.json", QDir::Files);
    for (const QString &file : existingJsonFiles) {
        if (file == "stations.json" || file == "ground_stations.json") continue;
        if (!activeFiles.contains(file)) {
            dir.remove(file);
        }
    }

    QJsonDocument aggDoc(arr);
    writeTextFile(dir.filePath("stations.json"), QString::fromUtf8(aggDoc.toJson(QJsonDocument::Indented)));

    return true;
}

QVariantList StationManager::loadStationsFromDisk()
{
    QVariantList list;
    QString dirPath = getStationsDirectory();
    QDir dir(dirPath);
    if (!dir.exists()) {
        return list;
    }

    QSet<QString> loadedIds;

    QStringList jsonFiles = dir.entryList(QStringList() << "*.json", QDir::Files, QDir::Name);

    for (const QString &file : jsonFiles) {
        if (file == "stations.json" || file == "ground_stations.json") continue;

        QString content = readTextFile(dir.filePath(file));
        if (content.trimmed().isEmpty()) continue;

        QVariantMap parsed = parseStationJson(content);
        if (parsed.value("valid", false).toBool()) {
            QString id = parsed.value("stationId").toString();
            if (!id.isEmpty() && !loadedIds.contains(id)) {
                loadedIds.insert(id);
                list.append(parsed);
            }
        }
    }

    if (list.isEmpty()) {
        QString aggFile = dir.filePath("stations.json");
        if (!QFile::exists(aggFile)) {
            aggFile = dir.filePath("ground_stations.json");
        }

        if (QFile::exists(aggFile)) {
            QString json = readTextFile(aggFile);
            QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
            if (doc.isArray()) {
                QJsonArray arr = doc.array();
                for (const QJsonValue &val : arr) {
                    if (!val.isObject()) continue;
                    QJsonDocument singleDoc(val.toObject());
                    QVariantMap parsed = parseStationJson(QString::fromUtf8(singleDoc.toJson(QJsonDocument::Compact)));
                    if (parsed.value("valid", false).toBool()) {
                        QString id = parsed.value("stationId").toString();
                        if (!id.isEmpty() && !loadedIds.contains(id)) {
                            loadedIds.insert(id);
                            list.append(parsed);
                        }
                    }
                }
            }
        }
    }

    return list;
}
