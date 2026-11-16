#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>

/**
 * @class StationManager
 * @brief Central persistence, RF parameter calculation, and JSON serialization manager exposed to QML.
 *
 * Manages three persistent data domains under the application data directory (`QStandardPaths::AppDataLocation`
 * or portable subdirectories next to the executable):
 * - **Ground Stations** (`stations/<stationId>.json` + `stations.json`)
 * - **Satellites** (`satellites/<satId>.json` + `satellites.json`)
 * - **History Sessions** (`history/<sessionId>/session.json`, `satellite.json`, `telemetry.json`, `stations/<stationId>.json`)
 */
class StationManager : public QObject {
    Q_OBJECT
public:
    explicit StationManager(QObject *parent = nullptr);

    /**
     * @brief Computes derived RF and noise parameters using Friis noise formula, dish size estimation, and band presets.
     * @param band Frequency band preset name (e.g. `"C-band"`, `"X-band"`, `"Custom"`).
     * @param lnaNfDb Low-Noise Amplifier noise figure [dB].
     * @param feederLossDb Feeder cable/waveguide loss [dB].
     * @param antennaGainDbi Antenna gain [dBi].
     * @param customFMinMhz Minimum frequency [MHz] when `band` is `"Custom"`.
     * @param customFMaxMhz Maximum frequency [MHz] when `band` is `"Custom"`.
     * @param antennaSkyNoiseK Antenna sky noise temperature [K].
     * @return Map containing `fMinMhz`, `fMaxMhz`, `systemNoiseTempK`, `totalNoiseFigureDb`, `gOverT`, and `estimatedDishM`.
     */
    Q_INVOKABLE QVariantMap computeDerivedParameters(
        const QString &band,
        double lnaNfDb,
        double feederLossDb,
        double antennaGainDbi,
        double customFMinMhz = 0.0,
        double customFMaxMhz = 0.0,
        double antennaSkyNoiseK = 40.0
    );

    /** @brief Generates a formatted JSON document string from a ground station QVariantMap. */
    Q_INVOKABLE QString buildStationJson(const QVariantMap &stationData);

    /** @brief Parses a ground station JSON string (single object or array) into a structured QVariantMap. */
    Q_INVOKABLE QVariantMap parseStationJson(const QString &jsonString);

    /** @brief Opens a native file dialog to select a JSON file. */
    Q_INVOKABLE QString openFileDialog(
        const QString &title = "Import Station Configuration",
        const QString &filter = "JSON Files (*.json);;All Files (*.*)"
    );

    /** @brief Opens a native save file dialog to export a JSON/YAML/text file. */
    Q_INVOKABLE QString saveFileDialog(
        const QString &title = "Export Station Configuration",
        const QString &defaultFileName = "ground_station.json",
        const QString &filter = "JSON Files (*.json);;All Files (*.*)"
    );

    /** @brief Reads the full UTF-8 text contents of @p filePath. */
    Q_INVOKABLE QString readTextFile(const QString &filePath);

    /** @brief Writes @p content as UTF-8 text to @p filePath. */
    Q_INVOKABLE bool writeTextFile(const QString &filePath, const QString &content);

    /** @brief Returns a pre-built ground station JSON template for quick testing/importing. */
    Q_INVOKABLE QString getSampleStationJson(const QString &band = "C-band");

    /// @name Ground Station Persistence
    /// @{
    Q_INVOKABLE QString getStationsDirectory() const;
    Q_INVOKABLE void openStationsFolder();
    Q_INVOKABLE bool saveStationFile(const QVariantMap &stationData);
    Q_INVOKABLE bool deleteStationFile(const QString &stationId);
    Q_INVOKABLE bool saveStationsToDisk(const QVariantList &stations);
    Q_INVOKABLE QVariantList loadStationsFromDisk();
    Q_INVOKABLE QString getDefaultStoragePath() const;
    /// @}

    /// @name Satellite Persistence
    /// @{
    Q_INVOKABLE QString getSatellitesDirectory() const;
    Q_INVOKABLE void openSatellitesFolder();
    Q_INVOKABLE QString buildSatelliteJson(const QVariantMap &satData);
    Q_INVOKABLE QVariantMap parseSatelliteJson(const QString &jsonString);
    Q_INVOKABLE bool saveSatelliteFile(const QVariantMap &satData);
    Q_INVOKABLE bool deleteSatelliteFile(const QString &satId);
    Q_INVOKABLE bool saveSatellitesToDisk(const QVariantList &satellites);
    Q_INVOKABLE QVariantList loadSatellitesFromDisk();
    /// @}

    /// @name History Session Persistence
    /// @{
    Q_INVOKABLE QString getHistoryDirectory() const;
    Q_INVOKABLE void openHistoryFolder();

    /**
     * @brief Saves a complete planning session snapshot (metadata, satellite, stations, and optional SNR telemetry) into its own history folder.
     */
    Q_INVOKABLE QVariantMap saveHistorySession(const QVariantMap &sessionMeta,
                                               const QVariantMap &satelliteData,
                                               const QVariantList &stationsList);

    /** @brief Lists all saved history sessions sorted newest-first. */
    Q_INVOKABLE QVariantList loadHistorySessions();

    /** @brief Loads full details (`session`, `satellite`, `stations`, `snrProfileData`) for a single history session. */
    Q_INVOKABLE QVariantMap loadHistorySessionDetails(const QString &sessionId);

    /** @brief Updates only the target satellite JSON inside a specific history session folder. */
    Q_INVOKABLE bool updateHistorySessionSatellite(const QString &sessionId, const QVariantMap &satData);

    /** @brief Updates or adds a ground station JSON inside a specific history session folder. */
    Q_INVOKABLE bool updateHistorySessionStation(const QString &sessionId, const QVariantMap &stationData);

    /** @brief Removes a ground station JSON from a specific history session folder. */
    Q_INVOKABLE bool deleteHistorySessionStation(const QString &sessionId, const QString &stationId);

    /** @brief Updates a history session's pass timing metadata and telemetry.json without touching satellite/station configs. */
    Q_INVOKABLE bool updateHistorySessionPass(const QString &sessionId, const QVariantMap &sessionMeta, const QVariantMap &snrData);

    /** @brief Creates a blank manual history session folder with empty satellite and station slots. */
    Q_INVOKABLE QVariantMap createBlankHistorySession(const QString &customName = QString());

    /** @brief Recursively deletes a history session folder. */
    Q_INVOKABLE bool deleteHistorySession(const QString &sessionId);
    /// @}

private:
    static void getBandFrequencies(const QString &band, double customMin, double customMax,
                                   double &outMinMhz, double &outMaxMhz);
};
