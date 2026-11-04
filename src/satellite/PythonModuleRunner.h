#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QProcess>
#include <QTimer>
#include <QHash>

class PythonModuleRunner : public QObject {
    Q_OBJECT
public:
    explicit PythonModuleRunner(QObject *parent = nullptr);
    ~PythonModuleRunner() override;

    // Detects Python interpreter (prefers workspace .venv if present, falls back to global python3/python)
    Q_INVOKABLE QVariantMap detectPythonEnvironment() const;

    // Opens a native file dialog to select a Python module (.py)
    Q_INVOKABLE QString selectPythonModuleDialog();

    // Opens a native file dialog to select an Excel attenuation table (.xlsx / .csv)
    Q_INVOKABLE QString selectExcelFileDialog();

    // Returns list of recent/discovered Python factor calculation modules (each item: { name, path, exists })
    Q_INVOKABLE QVariantList loadRecentModules();

    // Adds a factor module path to the persistent recent modules list and returns updated list
    Q_INVOKABLE QVariantList addRecentModule(const QString &modulePath);

    // Removes a factor module path from the persistent recent modules list
    Q_INVOKABLE QVariantList removeRecentModule(const QString &modulePath);

    // Returns list of recent/discovered Python correlation modules (e.g. step_correlation.py)
    Q_INVOKABLE QVariantList loadRecentCorrelationModules();

    // Adds a correlation module path to the persistent recent correlation modules list
    Q_INVOKABLE QVariantList addRecentCorrelationModule(const QString &modulePath);

    // Returns list of recent/discovered Excel attenuation table files (e.g. attenuation_table.xlsx)
    Q_INVOKABLE QVariantList loadRecentExcelFiles();

    // Adds an Excel file path to the persistent recent Excel files list
    Q_INVOKABLE QVariantList addRecentExcelFile(const QString &excelPath);

    // Builds the session prediction input JSON conforming to Section 2 of README.md
    Q_INVOKABLE QString buildSessionInputJson(
        const QString &tleLine1,
        const QString &tleLine2,
        const QVariantList &stations,
        const QString &startUtcIso,
        const QString &endUtcIso,
        double sampleRateHz = 1.0
    );

    // Builds the correlation module input JSON conforming to Section 4 of README.md
    Q_INVOKABLE QString buildCorrelationInputJson(
        const QString &groundStationName,
        const QString &stationId,
        int expectedSampleCount,
        const QVariantList &factorModuleOutputs
    );

    // Starts a Python factor module asynchronously in a separate OS process (non-blocking)
    Q_INVOKABLE void runModuleAsync(
        const QString &runId,
        const QString &modulePath,
        const QString &inputJson
    );

    // Starts a Python correlation module asynchronously for a specific ground station
    Q_INVOKABLE void runCorrelationModuleAsync(
        const QString &runId,
        const QString &modulePath,
        const QString &excelPath,
        const QString &groundStationName,
        const QString &inputJson
    );

    // Cancels a running module process if active
    Q_INVOKABLE void cancelModuleRun(const QString &runId);

signals:
    void moduleStarted(const QString &runId, const QString &moduleName, const QString &modulePath);
    void moduleProgress(const QString &runId, const QString &moduleName, double progress, const QString &statusText);
    void moduleFinished(
        const QString &runId,
        const QString &moduleName,
        const QString &modulePath,
        bool success,
        const QString &outputJson,
        const QString &errorMessage
    );

private:
    struct ActiveRun {
        QString runId;
        QString moduleName;
        QString modulePath;
        QProcess *process = nullptr;
        QTimer *progressTimer = nullptr;
        double currentProgress = 0.0;
    };

    QHash<QString, ActiveRun*> m_activeRuns;

    QString resolvePythonExecutable(bool *outIsVenv = nullptr) const;
    QString getRecentModulesStoragePath() const;
    QJsonObject loadSettingsJson() const;
    void saveSettingsJson(const QJsonObject &obj) const;
    QStringList findBuiltInModules() const;
    QStringList findBuiltInCorrelationModules() const;
    QStringList findBuiltInExcelFiles() const;
};
