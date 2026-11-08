#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>

class StationManager : public QObject {
    Q_OBJECT
public:
    explicit StationManager(QObject *parent = nullptr);

    // Computes derived RF and noise parameters using Friis noise formula, dish size estimation & band presets
    Q_INVOKABLE QVariantMap computeDerivedParameters(
        const QString &band,
        double lnaNfDb,
        double feederLossDb,
        double antennaGainDbi,
        double customFMinMhz = 0.0,
        double customFMaxMhz = 0.0,
        double antennaSkyNoiseK = 40.0
    );

    // Generates a formatted JSON document string from a station map
    Q_INVOKABLE QString buildStationJson(const QVariantMap &stationData);

    // Parses a JSON string (single station or collection) into structured QVariantMap
    Q_INVOKABLE QVariantMap parseStationJson(const QString &jsonString);

    // Native file dialog to select a JSON file on Windows/Desktop
    Q_INVOKABLE QString openFileDialog(
        const QString &title = "Import Station Configuration",
        const QString &filter = "JSON Files (*.json);;All Files (*.*)"
    );

    // Native save file dialog to export a JSON file on Windows/Desktop
    Q_INVOKABLE QString saveFileDialog(
        const QString &title = "Export Station Configuration",
        const QString &defaultFileName = "ground_station.json",
        const QString &filter = "JSON Files (*.json);;All Files (*.*)"
    );

    // File I/O helpers
    Q_INVOKABLE QString readTextFile(const QString &filePath);
    Q_INVOKABLE bool writeTextFile(const QString &filePath, const QString &content);

    // Pre-built station JSON templates for quick testing / importing
    Q_INVOKABLE QString getSampleStationJson(const QString &band = "C-band");

    // Persistent storage helpers for ground stations (stations folder & JSON files)
    Q_INVOKABLE QString getStationsDirectory() const;
    Q_INVOKABLE void openStationsFolder();
    Q_INVOKABLE bool saveStationFile(const QVariantMap &stationData);
    Q_INVOKABLE bool deleteStationFile(const QString &stationId);
    Q_INVOKABLE bool saveStationsToDisk(const QVariantList &stations);
    Q_INVOKABLE QVariantList loadStationsFromDisk();
    Q_INVOKABLE QString getDefaultStoragePath() const;

    // Persistent storage helpers for satellites (satellites folder & JSON files)
    Q_INVOKABLE QString getSatellitesDirectory() const;
    Q_INVOKABLE void openSatellitesFolder();
    Q_INVOKABLE QString buildSatelliteJson(const QVariantMap &satData);
    Q_INVOKABLE QVariantMap parseSatelliteJson(const QString &jsonString);
    Q_INVOKABLE bool saveSatelliteFile(const QVariantMap &satData);
    Q_INVOKABLE bool deleteSatelliteFile(const QString &satId);
    Q_INVOKABLE bool saveSatellitesToDisk(const QVariantList &satellites);
    Q_INVOKABLE QVariantList loadSatellitesFromDisk();

    // Persistent storage helpers for History Sessions (history folder & session JSONs)
    Q_INVOKABLE QString getHistoryDirectory() const;
    Q_INVOKABLE void openHistoryFolder();
    Q_INVOKABLE QVariantMap saveHistorySession(const QVariantMap &sessionMeta,
                                               const QVariantMap &satelliteData,
                                               const QVariantList &stationsList);
    Q_INVOKABLE QVariantList loadHistorySessions();
    Q_INVOKABLE QVariantMap loadHistorySessionDetails(const QString &sessionId);
    Q_INVOKABLE bool updateHistorySessionSatellite(const QString &sessionId, const QVariantMap &satData);
    Q_INVOKABLE bool updateHistorySessionStation(const QString &sessionId, const QVariantMap &stationData);
    Q_INVOKABLE bool deleteHistorySessionStation(const QString &sessionId, const QString &stationId);
    Q_INVOKABLE QVariantMap createBlankHistorySession(const QString &customName = QString());
    Q_INVOKABLE bool deleteHistorySession(const QString &sessionId);

private:
    static void getBandFrequencies(const QString &band, double customMin, double customMax,
                                   double &outMinMhz, double &outMaxMhz);
};
