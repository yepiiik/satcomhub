#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QProcess>
#include <QTimer>
#include <QHash>

/**
 * @class PythonModuleRunner
 * @brief Asynchronous external Python runner for RF attenuation factor and correlation modules.
 *
 * Discovers Python environments (preferring workspace `.venv`), manages recent factor `.py`
 * and correlation `.xlsx`/`.py` modules, builds JSON input payloads, and executes scripts
 * non-blockingly via `QProcess` while emitting progress/completion signals to QML.
 */
class PythonModuleRunner : public QObject {
    Q_OBJECT
public:
    explicit PythonModuleRunner(QObject *parent = nullptr);
    ~PythonModuleRunner() override;

    /** @brief Detects Python interpreter (prefers workspace `.venv`, falls back to system `python3`/`python`). */
    Q_INVOKABLE QVariantMap detectPythonEnvironment() const;

    /** @brief Opens a native file dialog to select a Python module (`.py`). */
    Q_INVOKABLE QString selectPythonModuleDialog();

    /** @brief Opens a native file dialog to select an Excel attenuation table (`.xlsx` / `.csv`). */
    Q_INVOKABLE QString selectExcelFileDialog();

    /// @name Recent Modules & Excel Tables Discovery
    /// @{
    Q_INVOKABLE QVariantList loadRecentModules();
    Q_INVOKABLE QVariantList addRecentModule(const QString &modulePath);
    Q_INVOKABLE QVariantList removeRecentModule(const QString &modulePath);
    Q_INVOKABLE QVariantList loadRecentCorrelationModules();
    Q_INVOKABLE QVariantList addRecentCorrelationModule(const QString &modulePath);
    Q_INVOKABLE QVariantList loadRecentExcelFiles();
    Q_INVOKABLE QVariantList addRecentExcelFile(const QString &excelPath);
    /// @}

    /** @brief Builds the session prediction input JSON payload for Python factor modules. */
    Q_INVOKABLE QString buildSessionInputJson(
        const QString &tleLine1,
        const QString &tleLine2,
        const QVariantList &stations,
        const QString &startUtcIso,
        const QString &endUtcIso,
        double sampleRateHz = 1.0
    );

    /** @brief Builds the correlation module input JSON payload for a ground station. */
    Q_INVOKABLE QString buildCorrelationInputJson(
        const QString &groundStationName,
        const QString &stationId,
        int expectedSampleCount,
        const QVariantList &factorModuleOutputs
    );

    /** @brief Starts a Python factor module asynchronously in a separate OS process. */
    Q_INVOKABLE void runModuleAsync(
        const QString &runId,
        const QString &modulePath,
        const QString &inputJson
    );

    /** @brief Starts a Python correlation module asynchronously for a specific ground station. */
    Q_INVOKABLE void runCorrelationModuleAsync(
        const QString &runId,
        const QString &modulePath,
        const QString &excelPath,
        const QString &groundStationName,
        const QString &inputJson
    );

    /** @brief Cancels an active module process by @p runId. */
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
