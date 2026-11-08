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

// =========================================================================
// SATELLITE PERSISTENCE & JSON SERIALIZATION
// =========================================================================

QString StationManager::getSatellitesDirectory() const
{
    QString baseDir;
    QString portablePath = QCoreApplication::applicationDirPath() + "/satellites";
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

    QDir dir(baseDir + "/satellites");
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dir.absolutePath();
}

void StationManager::openSatellitesFolder()
{
    QString path = getSatellitesDirectory();
    QDir().mkpath(path);
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

QString StationManager::buildSatelliteJson(const QVariantMap &satData)
{
    QJsonObject root;
    QString id = satData.value("satId").toString().trimmed();
    if (id.isEmpty()) id = "SAT-01";
    root["satId"] = id;
    root["name"] = satData.value("name", "Unknown Satellite").toString();

    QJsonObject tleObj;
    tleObj["line1"] = satData.value("tle1").toString();
    tleObj["line2"] = satData.value("tle2").toString();
    root["tle"] = tleObj;

    QJsonObject rfObj;
    rfObj["carrier_frequency_mhz"] = satData.value("carrierFreqMhz", 5850.0).toDouble();
    rfObj["channel_bandwidth_khz"] = satData.value("channelBandwidthKhz", 20000.0).toDouble();
    rfObj["modulation"] = satData.value("modulation", "OQPSK").toString();
    rfObj["bits_per_symbol"] = satData.value("bitsPerSymbol", 2.0).toDouble();
    rfObj["code_efficiency_coef"] = satData.value("codeEfficiencyCoef", 1.24).toDouble();
    rfObj["rolloff_alpha"] = satData.value("rolloffAlpha", 0.35).toDouble();
    rfObj["tx_power_dbm"] = satData.value("txPowerDbm", 33.0).toDouble();
    rfObj["tx_antenna_gain_dbi"] = satData.value("txAntennaGainDbi", 3.0).toDouble();
    root["rf_configuration"] = rfObj;

    QJsonObject codingObj;
    codingObj["code_rate_register"] = satData.value("codeRateRegister", "").toString();
    QVariant tableVar = satData.value("codeRateTable");
    if (tableVar.isValid()) {
        QJsonArray tableArr;
        QVariantList list = tableVar.toList();
        for (const QVariant &item : list) {
            QVariantMap itemMap = item.toMap();
            QJsonObject entry;
            entry["name"] = itemMap.value("name").toString();
            entry["rate"] = itemMap.value("rate").toDouble();
            entry["hw"] = itemMap.value("hw").toString();
            tableArr.append(entry);
        }
        codingObj["code_rate_table"] = tableArr;
    }
    root["coding"] = codingObj;

    QJsonObject meta;
    meta["created_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
    root["metadata"] = meta;

    QJsonDocument doc(root);
    return QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
}

QVariantMap StationManager::parseSatelliteJson(const QString &jsonString)
{
    QVariantMap result;
    result["valid"] = false;

    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(jsonString.trimmed().toUtf8(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        return result;
    }

    QJsonObject root = doc.object();
    result["valid"] = true;
    result["satId"] = root.value("satId").toString();
    result["name"] = root.value("name").toString();

    if (root.contains("tle") && root["tle"].isObject()) {
        QJsonObject tle = root["tle"].toObject();
        result["tle1"] = tle.value("line1").toString();
        result["tle2"] = tle.value("line2").toString();
    } else {
        result["tle1"] = root.value("tle1").toString();
        result["tle2"] = root.value("tle2").toString();
    }

    if (root.contains("rf_configuration") && root["rf_configuration"].isObject()) {
        QJsonObject rf = root["rf_configuration"].toObject();
        result["carrierFreqMhz"] = rf.value("carrier_frequency_mhz").toDouble(5850.0);
        result["channelBandwidthKhz"] = rf.value("channel_bandwidth_khz").toDouble(20000.0);
        result["modulation"] = rf.value("modulation").toString("OQPSK");
        result["bitsPerSymbol"] = rf.value("bits_per_symbol").toDouble(2.0);
        result["codeEfficiencyCoef"] = rf.value("code_efficiency_coef").toDouble(1.24);
        result["rolloffAlpha"] = rf.value("rolloff_alpha").toDouble(0.35);
        result["txPowerDbm"] = rf.value("tx_power_dbm").toDouble(33.0);
        result["txAntennaGainDbi"] = rf.value("tx_antenna_gain_dbi").toDouble(3.0);
    } else {
        result["carrierFreqMhz"] = root.value("carrierFreqMhz").toDouble(5850.0);
        result["channelBandwidthKhz"] = root.value("channelBandwidthKhz").toDouble(20000.0);
        result["modulation"] = root.value("modulation").toString("OQPSK");
        result["bitsPerSymbol"] = root.value("bitsPerSymbol").toDouble(2.0);
        result["codeEfficiencyCoef"] = root.value("codeEfficiencyCoef").toDouble(1.24);
        result["rolloffAlpha"] = root.value("rolloffAlpha").toDouble(0.35);
        result["txPowerDbm"] = root.value("txPowerDbm").toDouble(33.0);
        result["txAntennaGainDbi"] = root.value("txAntennaGainDbi").toDouble(3.0);
    }

    if (root.contains("coding") && root["coding"].isObject()) {
        QJsonObject cd = root["coding"].toObject();
        result["codeRateRegister"] = cd.value("code_rate_register").toString();
        if (cd.contains("code_rate_table") && cd["code_rate_table"].isArray()) {
            QVariantList crList;
            QJsonArray crArr = cd["code_rate_table"].toArray();
            for (const QJsonValue &v : crArr) {
                if (v.isObject()) {
                    QVariantMap crMap;
                    QJsonObject o = v.toObject();
                    crMap["name"] = o.value("name").toString();
                    crMap["rate"] = o.value("rate").toDouble();
                    crMap["hw"] = o.value("hw").toString();
                    crList.append(crMap);
                }
            }
            result["codeRateTable"] = crList;
        }
    } else {
        result["codeRateRegister"] = root.value("codeRateRegister").toString();
        result["codeRateTable"] = root.value("codeRateTable").toVariant().toList();
    }

    result["satelliteJson"] = buildSatelliteJson(result);
    return result;
}

bool StationManager::saveSatelliteFile(const QVariantMap &satData)
{
    QString id = satData.value("satId").toString().trimmed();
    if (id.isEmpty()) {
        id = "SAT-" + QString::number(QDateTime::currentMSecsSinceEpoch());
    }
    QString safeId = id;
    safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString dirPath = getSatellitesDirectory();
    QDir().mkpath(dirPath);
    QString filePath = QDir(dirPath).filePath(safeId + ".json");

    QString json = buildSatelliteJson(satData);
    return writeTextFile(filePath, json);
}

bool StationManager::deleteSatelliteFile(const QString &satId)
{
    QString safeId = satId.trimmed();
    safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString dirPath = getSatellitesDirectory();
    QDir dir(dirPath);
    QString filePath = dir.filePath(safeId + ".json");
    if (QFile::exists(filePath)) {
        return dir.remove(safeId + ".json");
    }
    return false;
}

bool StationManager::saveSatellitesToDisk(const QVariantList &satellites)
{
    QString dirPath = getSatellitesDirectory();
    QDir dir(dirPath);
    dir.mkpath(".");

    QSet<QString> activeFiles;
    QJsonArray arr;

    for (const QVariant &item : satellites) {
        QVariantMap map = item.toMap();
        QString id = map.value("satId").toString().trimmed();
        if (id.isEmpty()) {
            id = "SAT-0" + QString::number(activeFiles.size() + 1);
            map["satId"] = id;
        }

        QString safeId = id;
        safeId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");
        QString filename = safeId + ".json";
        activeFiles.insert(filename);

        QString satJson = buildSatelliteJson(map);
        writeTextFile(dir.filePath(filename), satJson);

        QJsonDocument doc = QJsonDocument::fromJson(satJson.toUtf8());
        if (doc.isObject()) {
            arr.append(doc.object());
        }
    }

    QStringList existingJsonFiles = dir.entryList(QStringList() << "*.json", QDir::Files);
    for (const QString &file : existingJsonFiles) {
        if (file == "satellites.json") continue;
        if (!activeFiles.contains(file)) {
            dir.remove(file);
        }
    }

    QJsonDocument aggDoc(arr);
    writeTextFile(dir.filePath("satellites.json"), QString::fromUtf8(aggDoc.toJson(QJsonDocument::Indented)));

    return true;
}

QVariantList StationManager::loadSatellitesFromDisk()
{
    QVariantList list;
    QString dirPath = getSatellitesDirectory();
    QDir dir(dirPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }

    QSet<QString> loadedIds;
    QStringList jsonFiles = dir.entryList(QStringList() << "*.json", QDir::Files, QDir::Name);

    for (const QString &file : jsonFiles) {
        if (file == "satellites.json") continue;
        QString content = readTextFile(dir.filePath(file));
        if (content.trimmed().isEmpty()) continue;

        QVariantMap parsed = parseSatelliteJson(content);
        if (parsed.value("valid", false).toBool()) {
            QString id = parsed.value("satId").toString();
            if (!id.isEmpty() && !loadedIds.contains(id)) {
                loadedIds.insert(id);
                list.append(parsed);
            }
        }
    }

    // Default seed satellites if folder is empty
    if (list.isEmpty()) {
        QVariantMap iss;
        iss["satId"] = "SAT-01";
        iss["name"] = "ISS (ZARYA)";
        iss["tle1"] = "1 25544U 98067A   26290.17683437  .00008767  00000+0  16757-3 0  9994";
        iss["tle2"] = "2 25544  51.6327  56.4129 0006776 273.6806  86.3408 15.48906925590665";
        iss["carrierFreqMhz"] = 5850.0;
        iss["channelBandwidthKhz"] = 20000.0;
        iss["modulation"] = "OQPSK";
        iss["bitsPerSymbol"] = 2.0;
        iss["codeEfficiencyCoef"] = 1.24;
        iss["rolloffAlpha"] = 0.35;
        iss["txPowerDbm"] = 33.0;
        iss["txAntennaGainDbi"] = 3.0;
        iss["codeRateRegister"] = "0x40001000";

        QVariantMap poly;
        poly["satId"] = "SAT-02";
        poly["name"] = "POLYITAN-3-PUT (LEO)";
        poly["tle1"] = "1 99999U 24001A   26290.18000000  .00010000  00000+0  20000-3 0  9991";
        poly["tle2"] = "2 99999  97.4000 120.0000 0012000  90.0000 270.0000 15.15000000012345";
        poly["carrierFreqMhz"] = 5840.0;
        poly["channelBandwidthKhz"] = 10000.0;
        poly["modulation"] = "QPSK";
        poly["bitsPerSymbol"] = 2.0;
        poly["codeEfficiencyCoef"] = 1.24;
        poly["rolloffAlpha"] = 0.35;
        poly["txPowerDbm"] = 33.0;
        poly["txAntennaGainDbi"] = 3.0;
        poly["codeRateRegister"] = "0x40001000";

        QVariantList polyRates;
        auto addRate = [&](const QString &nm, double rt, const QString &hw) {
            QVariantMap r;
            r["name"] = nm; r["rate"] = rt; r["hw"] = hw;
            polyRates.append(r);
        };
        addRate("R1", 0.910, "0");
        addRate("R2", 0.830, "1");
        addRate("R3", 0.700, "2");
        addRate("R4", 0.570, "3");
        addRate("R5", 0.410, "4");
        addRate("R6", 0.285, "5");
        addRate("R7", 0.190, "6");
        poly["codeRateTable"] = polyRates;

        saveSatelliteFile(iss);
        saveSatelliteFile(poly);

        list.append(parseSatelliteJson(buildSatelliteJson(iss)));
        list.append(parseSatelliteJson(buildSatelliteJson(poly)));
    }

    return list;
}

// =========================================================================
// HISTORY SESSIONS PERSISTENCE & DIRECTORY STRUCTURE
// =========================================================================

QString StationManager::getHistoryDirectory() const
{
    QString baseDir;
    QString portablePath = QCoreApplication::applicationDirPath() + "/history";
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

    QDir dir(baseDir + "/history");
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dir.absolutePath();
}

void StationManager::openHistoryFolder()
{
    QString path = getHistoryDirectory();
    QDir().mkpath(path);
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

QVariantMap StationManager::saveHistorySession(const QVariantMap &sessionMeta,
                                               const QVariantMap &satelliteData,
                                               const QVariantList &stationsList)
{
    QString historyDir = getHistoryDirectory();
    QDir().mkpath(historyDir);

    QString sid = sessionMeta.value("sessionId").toString().trimmed();
    if (sid.isEmpty()) {
        QString timeTag = QDateTime::currentDateTimeUtc().toString("yyyyMMdd_hhmmss");
        QString satTag = sessionMeta.value("satelliteName", "Session").toString().trimmed();
        satTag.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");
        sid = "SESSION_" + timeTag + "_" + satTag;
    }
    QString safeSid = sid;
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString sessionFolderPath = historyDir + "/" + safeSid;
    QDir sessionDir(sessionFolderPath);
    sessionDir.mkpath("stations");

    // 1. Write satellite.json if satellite data is valid
    if (!satelliteData.isEmpty()) {
        QString satJson = buildSatelliteJson(satelliteData);
        writeTextFile(sessionDir.filePath("satellite.json"), satJson);
    }

    // 2. Write stations/<stationId>.json
    int stCount = 0;
    QJsonArray stationIdsArr;
    for (const QVariant &stVal : stationsList) {
        QVariantMap stMap = stVal.toMap();
        QString stId = stMap.value("stationId").toString().trimmed();
        if (stId.isEmpty()) stId = "GS-" + QString::number(stCount + 1);
        QString safeStId = stId;
        safeStId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

        QString stJson = buildStationJson(stMap);
        writeTextFile(sessionDir.filePath("stations/" + safeStId + ".json"), stJson);
        stationIdsArr.append(stId);
        stCount++;
    }

    // 2b. Write telemetry.json if SNR data is provided
    if (sessionMeta.contains("snrData")) {
        QVariant snrVar = sessionMeta.value("snrData");
        QJsonDocument snrDoc;
        if (snrVar.userType() == QMetaType::QVariantMap) {
            snrDoc = QJsonDocument(QJsonObject::fromVariantMap(snrVar.toMap()));
        } else if (snrVar.userType() == QMetaType::QString) {
            snrDoc = QJsonDocument::fromJson(snrVar.toString().toUtf8());
        }
        if (!snrDoc.isNull()) {
            writeTextFile(sessionDir.filePath("telemetry.json"), QString::fromUtf8(snrDoc.toJson(QJsonDocument::Indented)));
        }
    }

    // 3. Write session.json metadata
    QJsonObject sessObj;
    sessObj["sessionId"] = safeSid;
    sessObj["sessionName"] = sessionMeta.value("sessionName", safeSid).toString();
    sessObj["dateUtc"] = sessionMeta.value("dateUtc", QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd hh:mm:ss 'UTC'")).toString();
    sessObj["combinedAosUtc"] = sessionMeta.value("combinedAosUtc", "").toString();
    sessObj["combinedLosUtc"] = sessionMeta.value("combinedLosUtc", "").toString();
    sessObj["durationSeconds"] = sessionMeta.value("durationSeconds", 0).toDouble();
    sessObj["durationFormatted"] = sessionMeta.value("durationFormatted", "--").toString();
    sessObj["satelliteId"] = satelliteData.value("satId", sessionMeta.value("satelliteId", "")).toString();
    sessObj["satelliteName"] = satelliteData.value("name", sessionMeta.value("satelliteName", "None")).toString();
    sessObj["stationCount"] = stCount;
    sessObj["stationIds"] = stationIdsArr;
    sessObj["status"] = sessionMeta.value("status", "Planned").toString();
    sessObj["notes"] = sessionMeta.value("notes", "").toString();
    sessObj["maxSnrDb"] = sessionMeta.value("maxSnrDb", 0.0).toDouble();
    sessObj["meanSnrDb"] = sessionMeta.value("meanSnrDb", 0.0).toDouble();
    sessObj["maxElevationDeg"] = sessionMeta.value("maxElevationDeg", 0.0).toDouble();
    sessObj["created_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    QJsonDocument sessDoc(sessObj);
    writeTextFile(sessionDir.filePath("session.json"), QString::fromUtf8(sessDoc.toJson(QJsonDocument::Indented)));

    QVariantMap res = sessObj.toVariantMap();
    res["valid"] = true;
    return res;
}

QVariantList StationManager::loadHistorySessions()
{
    QVariantList list;
    QString historyDir = getHistoryDirectory();
    QDir dir(historyDir);
    if (!dir.exists()) return list;

    QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);
    for (const QString &sub : subdirs) {
        QString sessPath = dir.filePath(sub + "/session.json");
        if (!QFile::exists(sessPath)) continue;

        QString json = readTextFile(sessPath);
        QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
        if (!doc.isObject()) continue;

        QVariantMap map = doc.object().toVariantMap();
        map["valid"] = true;
        map["sessionFolder"] = sub;
        list.append(map);
    }

    return list;
}

QVariantMap StationManager::loadHistorySessionDetails(const QString &sessionId)
{
    QVariantMap result;
    result["valid"] = false;

    QString safeSid = sessionId.trimmed();
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString sessionFolderPath = getHistoryDirectory() + "/" + safeSid;
    QDir sessionDir(sessionFolderPath);
    if (!sessionDir.exists()) return result;

    QString sessJsonPath = sessionDir.filePath("session.json");
    if (QFile::exists(sessJsonPath)) {
        QJsonDocument doc = QJsonDocument::fromJson(readTextFile(sessJsonPath).toUtf8());
        if (doc.isObject()) {
            result["session"] = doc.object().toVariantMap();
        }
    }

    // Load satellite.json if present
    QString satJsonPath = sessionDir.filePath("satellite.json");
    if (QFile::exists(satJsonPath)) {
        QVariantMap sat = parseSatelliteJson(readTextFile(satJsonPath));
        if (sat.value("valid", false).toBool()) {
            result["satellite"] = sat;
            result["hasSatellite"] = true;
        } else {
            result["hasSatellite"] = false;
        }
    } else {
        result["hasSatellite"] = false;
    }

    // Load stations/*.json
    QVariantList stationsList;
    QDir stationsDir(sessionDir.filePath("stations"));
    if (stationsDir.exists()) {
        QStringList stFiles = stationsDir.entryList(QStringList() << "*.json", QDir::Files, QDir::Name);
        for (const QString &file : stFiles) {
            QString content = readTextFile(stationsDir.filePath(file));
            QVariantMap parsed = parseStationJson(content);
            if (parsed.value("valid", false).toBool()) {
                stationsList.append(parsed);
            }
        }
    }
    result["stations"] = stationsList;
    result["hasStations"] = !stationsList.isEmpty();

    // Load telemetry.json if present
    QString telemPath = sessionDir.filePath("telemetry.json");
    if (QFile::exists(telemPath)) {
        QJsonDocument doc = QJsonDocument::fromJson(readTextFile(telemPath).toUtf8());
        if (doc.isObject()) {
            result["snrProfileData"] = doc.object().toVariantMap();
            result["hasSnrData"] = true;
        } else {
            result["hasSnrData"] = false;
        }
    } else {
        result["hasSnrData"] = false;
    }

    result["valid"] = true;

    return result;
}

bool StationManager::updateHistorySessionSatellite(const QString &sessionId, const QVariantMap &satData)
{
    QString safeSid = sessionId.trimmed();
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString sessionFolderPath = getHistoryDirectory() + "/" + safeSid;
    QDir sessionDir(sessionFolderPath);
    if (!sessionDir.exists()) return false;

    QString satJson = buildSatelliteJson(satData);
    bool ok = writeTextFile(sessionDir.filePath("satellite.json"), satJson);

    // Update session.json
    QString sessPath = sessionDir.filePath("session.json");
    if (QFile::exists(sessPath)) {
        QJsonDocument doc = QJsonDocument::fromJson(readTextFile(sessPath).toUtf8());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            obj["satelliteId"] = satData.value("satId", "").toString();
            obj["satelliteName"] = satData.value("name", "Satellite").toString();
            writeTextFile(sessPath, QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented)));
        }
    }

    return ok;
}

bool StationManager::updateHistorySessionStation(const QString &sessionId, const QVariantMap &stationData)
{
    QString safeSid = sessionId.trimmed();
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString sessionFolderPath = getHistoryDirectory() + "/" + safeSid;
    QDir sessionDir(sessionFolderPath);
    if (!sessionDir.exists()) return false;
    sessionDir.mkpath("stations");

    QString stId = stationData.value("stationId").toString().trimmed();
    if (stId.isEmpty()) {
        stId = "GS-" + QString::number(QDateTime::currentMSecsSinceEpoch());
    }
    QString safeStId = stId;
    safeStId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString stJson = buildStationJson(stationData);
    bool ok = writeTextFile(sessionDir.filePath("stations/" + safeStId + ".json"), stJson);

    // Update session.json count
    QString sessPath = sessionDir.filePath("session.json");
    if (QFile::exists(sessPath)) {
        QDir stDir(sessionDir.filePath("stations"));
        int cnt = stDir.entryList(QStringList() << "*.json", QDir::Files).count();
        QJsonDocument doc = QJsonDocument::fromJson(readTextFile(sessPath).toUtf8());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            obj["stationCount"] = cnt;
            writeTextFile(sessPath, QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented)));
        }
    }

    return ok;
}

bool StationManager::deleteHistorySessionStation(const QString &sessionId, const QString &stationId)
{
    QString safeSid = sessionId.trimmed();
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString safeStId = stationId.trimmed();
    safeStId.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString filePath = getHistoryDirectory() + "/" + safeSid + "/stations/" + safeStId + ".json";
    if (QFile::exists(filePath)) {
        QFile::remove(filePath);
    }

    // Update count in session.json
    QString sessPath = getHistoryDirectory() + "/" + safeSid + "/session.json";
    if (QFile::exists(sessPath)) {
        QDir stDir(getHistoryDirectory() + "/" + safeSid + "/stations");
        int cnt = stDir.entryList(QStringList() << "*.json", QDir::Files).count();
        QJsonDocument doc = QJsonDocument::fromJson(readTextFile(sessPath).toUtf8());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            obj["stationCount"] = cnt;
            writeTextFile(sessPath, QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Indented)));
        }
    }

    return true;
}

QVariantMap StationManager::createBlankHistorySession(const QString &customName)
{
    QString timeTag = QDateTime::currentDateTimeUtc().toString("yyyyMMdd_hhmmss");
    QString sid = "SESSION_" + timeTag + "_Manual";
    QString safeSid = sid;

    QString sessionFolderPath = getHistoryDirectory() + "/" + safeSid;
    QDir sessionDir(sessionFolderPath);
    sessionDir.mkpath("stations");

    QJsonObject sessObj;
    sessObj["sessionId"] = safeSid;
    sessObj["sessionName"] = customName.isEmpty() ? ("Manual Session " + QDateTime::currentDateTimeUtc().toString("dd.MM.yyyy hh:mm")) : customName;
    sessObj["dateUtc"] = QDateTime::currentDateTimeUtc().toString("yyyy-MM-dd hh:mm:ss 'UTC'");
    sessObj["combinedAosUtc"] = "";
    sessObj["combinedLosUtc"] = "";
    sessObj["durationSeconds"] = 0;
    sessObj["durationFormatted"] = "--";
    sessObj["satelliteId"] = "";
    sessObj["satelliteName"] = "None";
    sessObj["stationCount"] = 0;
    sessObj["stationIds"] = QJsonArray();
    sessObj["status"] = "Draft";
    sessObj["notes"] = "";
    sessObj["created_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    writeTextFile(sessionDir.filePath("session.json"), QString::fromUtf8(QJsonDocument(sessObj).toJson(QJsonDocument::Indented)));

    QVariantMap res = sessObj.toVariantMap();
    res["valid"] = true;
    return res;
}

bool StationManager::deleteHistorySession(const QString &sessionId)
{
    QString safeSid = sessionId.trimmed();
    safeSid.replace(QRegularExpression("[^a-zA-Z0-9_-]"), "_");

    QString sessionFolderPath = getHistoryDirectory() + "/" + safeSid;
    QDir dir(sessionFolderPath);
    if (dir.exists()) {
        return dir.removeRecursively();
    }
    return false;
}
