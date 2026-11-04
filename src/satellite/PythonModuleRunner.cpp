#include "PythonModuleRunner.h"
#include "StationManager.h"

#include <libsgp4/CoordGeodetic.h>
#include <libsgp4/DateTime.h>
#include <libsgp4/Eci.h>
#include <libsgp4/SGP4.h>
#include <libsgp4/Tle.h>
#include <libsgp4/Util.h>

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimeZone>
#include <algorithm>
#include <cmath>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commdlg.h>
#endif

namespace {

static libsgp4::DateTime toSgp4DateTime(const QDateTime &qdt) {
    QDateTime utc = qdt.isValid() ? qdt.toUTC() : QDateTime::currentDateTimeUtc();
    QDate d = utc.date();
    QTime t = utc.time();
    int y = d.year() > 0 ? d.year() : 2026;
    int m = (d.month() >= 1 && d.month() <= 12) ? d.month() : 1;
    int day = (d.day() >= 1 && d.day() <= 31) ? d.day() : 1;
    return libsgp4::DateTime(y, m, day, t.hour(), t.minute(), t.second(), t.msec() * 1000);
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

static QString cleanFileUrlPath(const QString &rawPath) {
    QString cleanPath = rawPath.trimmed();
    if (cleanPath.startsWith("file:///")) {
#ifdef _WIN32
        cleanPath = cleanPath.mid(8);
#else
        cleanPath = cleanPath.mid(7);
#endif
    }
    return cleanPath;
}

static QStringList candidateModulesDirs() {
    return {
        QDir::current().filePath("modules"),
        QDir(QCoreApplication::applicationDirPath()).filePath("modules"),
        QDir(QCoreApplication::applicationDirPath()).filePath("../modules"),
        QDir(QCoreApplication::applicationDirPath()).filePath("../../modules")
    };
}

} // namespace

PythonModuleRunner::PythonModuleRunner(QObject *parent)
    : QObject(parent)
{
}

PythonModuleRunner::~PythonModuleRunner()
{
    const auto keys = m_activeRuns.keys();
    for (const QString &id : keys) {
        cancelModuleRun(id);
    }
}

QString PythonModuleRunner::resolvePythonExecutable(bool *outIsVenv) const
{
    if (outIsVenv) *outIsVenv = false;

    // 1. Check for local virtual environment (.venv or venv) in workspace or app dir
    QStringList searchRoots = {
        QDir::currentPath(),
        QCoreApplication::applicationDirPath(),
        QDir(QCoreApplication::applicationDirPath()).filePath(".."),
        QDir(QCoreApplication::applicationDirPath()).filePath("../..")
    };

    for (const QString &root : searchRoots) {
        QDir d(root);
#ifdef _WIN32
        QStringList venvCandidates = {
            d.filePath(".venv/Scripts/python.exe"),
            d.filePath("venv/Scripts/python.exe")
        };
#else
        QStringList venvCandidates = {
            d.filePath(".venv/bin/python3"),
            d.filePath(".venv/bin/python"),
            d.filePath("venv/bin/python3"),
            d.filePath("venv/bin/python")
        };
#endif
        for (const QString &cand : venvCandidates) {
            QFileInfo fi(cand);
            if (fi.exists() && fi.isExecutable()) {
                if (outIsVenv) *outIsVenv = true;
                return fi.canonicalFilePath();
            }
        }
    }

    // 2. Fallback to globally installed Python on PATH
#ifdef _WIN32
    QString py = QStandardPaths::findExecutable("python");
    if (py.isEmpty()) py = QStandardPaths::findExecutable("python3");
    if (py.isEmpty()) py = QStandardPaths::findExecutable("py");
#else
    QString py = QStandardPaths::findExecutable("python3");
    if (py.isEmpty()) py = QStandardPaths::findExecutable("python");
#endif
    return py;
}

QVariantMap PythonModuleRunner::detectPythonEnvironment() const
{
    QVariantMap info;
    bool isVenv = false;
    QString exe = resolvePythonExecutable(&isVenv);

    if (exe.isEmpty()) {
        info["available"] = false;
        info["executable"] = "";
        info["version"] = "Not Found";
        info["isVenv"] = false;
        return info;
    }

    QProcess proc;
    proc.start(exe, {"--version"});
    proc.waitForFinished(1500);
    QString verOut = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    if (verOut.isEmpty()) {
        verOut = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    }

    info["available"] = (proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0);
    info["executable"] = exe;
    info["version"] = verOut.isEmpty() ? "Python 3" : verOut;
    info["isVenv"] = isVenv;
    return info;
}

QString PythonModuleRunner::selectPythonModuleDialog()
{
    QString startDir = QDir::currentPath();
    QStringList builtIn = findBuiltInModules();
    if (!builtIn.isEmpty()) {
        startDir = QFileInfo(builtIn.first()).absolutePath();
    }

#ifdef _WIN32
    wchar_t szFile[MAX_PATH] = L"";
    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFilter = L"Python Modules (*.py)\0*.py\0All Files (*.*)\0*.*\0";
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = sizeof(szFile) / sizeof(szFile[0]);
    std::wstring initDirW = QDir::toNativeSeparators(startDir).toStdWString();
    ofn.lpstrInitialDir = initDirW.c_str();
    ofn.lpstrTitle = L"Select Python Module (.py)";
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    if (GetOpenFileNameW(&ofn)) {
        return QString::fromWCharArray(szFile);
    }
#else
    QString zenity = QStandardPaths::findExecutable("zenity");
    if (!zenity.isEmpty()) {
        QProcess proc;
        proc.start(zenity, {
            "--file-selection",
            "--title=Select Python Module (.py)",
            "--filename=" + startDir + "/",
            "--file-filter=Python Modules (*.py) | *.py",
            "--file-filter=All Files | *"
        });
        proc.waitForFinished(-1);
        if (proc.exitCode() == 0) {
            return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        }
        return QString();
    }

    QString kdialog = QStandardPaths::findExecutable("kdialog");
    if (!kdialog.isEmpty()) {
        QProcess proc;
        proc.start(kdialog, {
            "--getopenfilename",
            startDir,
            "*.py|Python Modules (*.py)"
        });
        proc.waitForFinished(-1);
        if (proc.exitCode() == 0) {
            return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        }
        return QString();
    }
#endif
    return QString();
}

QString PythonModuleRunner::selectExcelFileDialog()
{
    QString startDir = QDir::currentPath();
    QStringList builtInExcel = findBuiltInExcelFiles();
    if (!builtInExcel.isEmpty()) {
        startDir = QFileInfo(builtInExcel.first()).absolutePath();
    }

#ifdef _WIN32
    wchar_t szFile[MAX_PATH] = L"";
    OPENFILENAMEW ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = NULL;
    ofn.lpstrFilter = L"Excel / Table Files (*.xlsx;*.csv)\0*.xlsx;*.csv\0All Files (*.*)\0*.*\0";
    ofn.lpstrFile = szFile;
    ofn.nMaxFile = sizeof(szFile) / sizeof(szFile[0]);
    std::wstring initDirW = QDir::toNativeSeparators(startDir).toStdWString();
    ofn.lpstrInitialDir = initDirW.c_str();
    ofn.lpstrTitle = L"Select Factor Attenuation Excel Table (.xlsx)";
    ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR;

    if (GetOpenFileNameW(&ofn)) {
        return QString::fromWCharArray(szFile);
    }
#else
    QString zenity = QStandardPaths::findExecutable("zenity");
    if (!zenity.isEmpty()) {
        QProcess proc;
        proc.start(zenity, {
            "--file-selection",
            "--title=Select Factor Attenuation Excel Table (.xlsx)",
            "--filename=" + startDir + "/",
            "--file-filter=Excel Files (*.xlsx, *.csv) | *.xlsx *.csv",
            "--file-filter=All Files | *"
        });
        proc.waitForFinished(-1);
        if (proc.exitCode() == 0) {
            return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        }
        return QString();
    }

    QString kdialog = QStandardPaths::findExecutable("kdialog");
    if (!kdialog.isEmpty()) {
        QProcess proc;
        proc.start(kdialog, {
            "--getopenfilename",
            startDir,
            "*.xlsx *.csv|Excel Files (*.xlsx, *.csv)"
        });
        proc.waitForFinished(-1);
        if (proc.exitCode() == 0) {
            return QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        }
        return QString();
    }
#endif
    return QString();
}

QString PythonModuleRunner::getRecentModulesStoragePath() const
{
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    if (configDir.isEmpty()) {
        configDir = QDir::homePath() + "/.config/satcomhub";
    }
    QDir dir(configDir);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dir.filePath("recent_python_modules.json");
}

QJsonObject PythonModuleRunner::loadSettingsJson() const
{
    QFile file(getRecentModulesStoragePath());
    if (file.exists() && file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            return doc.object();
        }
    }
    return QJsonObject();
}

void PythonModuleRunner::saveSettingsJson(const QJsonObject &obj) const
{
    QFile file(getRecentModulesStoragePath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

QStringList PythonModuleRunner::findBuiltInModules() const
{
    QStringList found;
    QStringList seenCanonical;
    for (const QString &dirPath : candidateModulesDirs()) {
        QDir d(dirPath);
        if (!d.exists()) continue;

        QFileInfoList files = d.entryInfoList({"*.py"}, QDir::Files | QDir::Readable, QDir::Name);
        for (const QFileInfo &fi : files) {
            QString base = fi.fileName();
            if (base == "__init__.py" || base.startsWith("test_") || base.endsWith("_correlation.py")) {
                continue;
            }
            QString canon = fi.canonicalFilePath();
            if (!canon.isEmpty() && !seenCanonical.contains(canon)) {
                seenCanonical.append(canon);
                found.append(canon);
            }
        }
    }
    return found;
}

QStringList PythonModuleRunner::findBuiltInCorrelationModules() const
{
    QStringList found;
    QStringList seenCanonical;
    for (const QString &dirPath : candidateModulesDirs()) {
        QDir d(dirPath);
        if (!d.exists()) continue;

        QFileInfoList files = d.entryInfoList({"*_correlation.py"}, QDir::Files | QDir::Readable, QDir::Name);
        for (const QFileInfo &fi : files) {
            QString base = fi.fileName();
            if (base.startsWith("test_")) continue;
            QString canon = fi.canonicalFilePath();
            if (!canon.isEmpty() && !seenCanonical.contains(canon)) {
                seenCanonical.append(canon);
                found.append(canon);
            }
        }
    }
    return found;
}

QStringList PythonModuleRunner::findBuiltInExcelFiles() const
{
    QStringList found;
    QStringList seenCanonical;
    for (const QString &dirPath : candidateModulesDirs()) {
        QDir d(dirPath);
        if (!d.exists()) continue;

        QFileInfoList files = d.entryInfoList({"*.xlsx", "*.csv"}, QDir::Files | QDir::Readable, QDir::Name);
        for (const QFileInfo &fi : files) {
            QString canon = fi.canonicalFilePath();
            if (!canon.isEmpty() && !seenCanonical.contains(canon)) {
                seenCanonical.append(canon);
                found.append(canon);
            }
        }
    }
    return found;
}

QVariantList PythonModuleRunner::loadRecentModules()
{
    QJsonObject root = loadSettingsJson();
    QStringList paths;

    QJsonArray arr = root.value("recent_modules").toArray();
    for (const QJsonValue &v : arr) {
        QString p = v.toString().trimmed();
        if (!p.isEmpty() && !p.endsWith("_correlation.py") && !paths.contains(p)) {
            paths.append(p);
        }
    }

    QStringList builtIns = findBuiltInModules();
    for (const QString &b : builtIns) {
        if (!paths.contains(b)) {
            paths.append(b);
        }
    }

    QJsonArray outArr;
    for (const QString &p : paths) outArr.append(p);
    root["recent_modules"] = outArr;
    saveSettingsJson(root);

    QVariantList result;
    for (const QString &p : paths) {
        QFileInfo fi(p);
        QVariantMap item;
        item["name"] = fi.fileName();
        item["baseName"] = fi.completeBaseName();
        item["path"] = fi.absoluteFilePath();
        item["exists"] = fi.exists();
        result.append(item);
    }
    return result;
}

QVariantList PythonModuleRunner::addRecentModule(const QString &modulePath)
{
    QString cleanPath = cleanFileUrlPath(modulePath);
    if (cleanPath.isEmpty()) {
        return loadRecentModules();
    }

    QFileInfo fi(cleanPath);
    QString absPath = fi.exists() ? fi.canonicalFilePath() : fi.absoluteFilePath();

    QVariantList current = loadRecentModules();
    QStringList updatedPaths;
    updatedPaths.append(absPath);

    for (const QVariant &v : current) {
        QString p = v.toMap().value("path").toString();
        if (!p.isEmpty() && p != absPath && !updatedPaths.contains(p)) {
            updatedPaths.append(p);
        }
    }

    QJsonObject root = loadSettingsJson();
    QJsonArray outArr;
    for (const QString &p : updatedPaths) outArr.append(p);
    root["recent_modules"] = outArr;
    saveSettingsJson(root);

    return loadRecentModules();
}

QVariantList PythonModuleRunner::removeRecentModule(const QString &modulePath)
{
    QVariantList current = loadRecentModules();
    QStringList updatedPaths;
    for (const QVariant &v : current) {
        QString p = v.toMap().value("path").toString();
        if (!p.isEmpty() && p != modulePath) {
            updatedPaths.append(p);
        }
    }

    QJsonObject root = loadSettingsJson();
    QJsonArray outArr;
    for (const QString &p : updatedPaths) outArr.append(p);
    root["recent_modules"] = outArr;
    saveSettingsJson(root);

    return loadRecentModules();
}

QVariantList PythonModuleRunner::loadRecentCorrelationModules()
{
    QJsonObject root = loadSettingsJson();
    QStringList paths;

    QJsonArray arr = root.value("recent_correlation_modules").toArray();
    for (const QJsonValue &v : arr) {
        QString p = v.toString().trimmed();
        if (!p.isEmpty() && !paths.contains(p)) {
            paths.append(p);
        }
    }

    QStringList builtIns = findBuiltInCorrelationModules();
    for (const QString &b : builtIns) {
        if (!paths.contains(b)) {
            paths.append(b);
        }
    }

    QJsonArray outArr;
    for (const QString &p : paths) outArr.append(p);
    root["recent_correlation_modules"] = outArr;
    saveSettingsJson(root);

    QVariantList result;
    for (const QString &p : paths) {
        QFileInfo fi(p);
        QVariantMap item;
        item["name"] = fi.fileName();
        item["baseName"] = fi.completeBaseName();
        item["path"] = fi.absoluteFilePath();
        item["exists"] = fi.exists();
        result.append(item);
    }
    return result;
}

QVariantList PythonModuleRunner::addRecentCorrelationModule(const QString &modulePath)
{
    QString cleanPath = cleanFileUrlPath(modulePath);
    if (cleanPath.isEmpty()) {
        return loadRecentCorrelationModules();
    }

    QFileInfo fi(cleanPath);
    QString absPath = fi.exists() ? fi.canonicalFilePath() : fi.absoluteFilePath();

    QVariantList current = loadRecentCorrelationModules();
    QStringList updatedPaths;
    updatedPaths.append(absPath);

    for (const QVariant &v : current) {
        QString p = v.toMap().value("path").toString();
        if (!p.isEmpty() && p != absPath && !updatedPaths.contains(p)) {
            updatedPaths.append(p);
        }
    }

    QJsonObject root = loadSettingsJson();
    QJsonArray outArr;
    for (const QString &p : updatedPaths) outArr.append(p);
    root["recent_correlation_modules"] = outArr;
    saveSettingsJson(root);

    return loadRecentCorrelationModules();
}

QVariantList PythonModuleRunner::loadRecentExcelFiles()
{
    QJsonObject root = loadSettingsJson();
    QStringList paths;

    QJsonArray arr = root.value("recent_excel_files").toArray();
    for (const QJsonValue &v : arr) {
        QString p = v.toString().trimmed();
        if (!p.isEmpty() && !paths.contains(p)) {
            paths.append(p);
        }
    }

    QStringList builtIns = findBuiltInExcelFiles();
    for (const QString &b : builtIns) {
        if (!paths.contains(b)) {
            paths.append(b);
        }
    }

    QJsonArray outArr;
    for (const QString &p : paths) outArr.append(p);
    root["recent_excel_files"] = outArr;
    saveSettingsJson(root);

    QVariantList result;
    for (const QString &p : paths) {
        QFileInfo fi(p);
        QVariantMap item;
        item["name"] = fi.fileName();
        item["baseName"] = fi.completeBaseName();
        item["path"] = fi.absoluteFilePath();
        item["exists"] = fi.exists();
        result.append(item);
    }
    return result;
}

QVariantList PythonModuleRunner::addRecentExcelFile(const QString &excelPath)
{
    QString cleanPath = cleanFileUrlPath(excelPath);
    if (cleanPath.isEmpty()) {
        return loadRecentExcelFiles();
    }

    QFileInfo fi(cleanPath);
    QString absPath = fi.exists() ? fi.canonicalFilePath() : fi.absoluteFilePath();

    QVariantList current = loadRecentExcelFiles();
    QStringList updatedPaths;
    updatedPaths.append(absPath);

    for (const QVariant &v : current) {
        QString p = v.toMap().value("path").toString();
        if (!p.isEmpty() && p != absPath && !updatedPaths.contains(p)) {
            updatedPaths.append(p);
        }
    }

    QJsonObject root = loadSettingsJson();
    QJsonArray outArr;
    for (const QString &p : updatedPaths) outArr.append(p);
    root["recent_excel_files"] = outArr;
    saveSettingsJson(root);

    return loadRecentExcelFiles();
}

QString PythonModuleRunner::buildSessionInputJson(
    const QString &tleLine1,
    const QString &tleLine2,
    const QVariantList &stations,
    const QString &startUtcIso,
    const QString &endUtcIso,
    double sampleRateHz)
{
    QDateTime startUtc = QDateTime::fromString(startUtcIso, Qt::ISODate);
    if (!startUtc.isValid()) {
        startUtc = QDateTime::fromString(startUtcIso, "yyyy-MM-dd HH:mm:ss 'UTC'");
        if (!startUtc.isValid()) {
            startUtc = QDateTime::fromString(startUtcIso, "yyyy-MM-dd HH:mm:ss");
        }
    }
    startUtc.setTimeZone(QTimeZone::UTC);

    QDateTime endUtc = QDateTime::fromString(endUtcIso, Qt::ISODate);
    if (!endUtc.isValid()) {
        endUtc = QDateTime::fromString(endUtcIso, "yyyy-MM-dd HH:mm:ss 'UTC'");
        if (!endUtc.isValid()) {
            endUtc = QDateTime::fromString(endUtcIso, "yyyy-MM-dd HH:mm:ss");
        }
    }
    endUtc.setTimeZone(QTimeZone::UTC);

    QJsonArray satSessionArray;

    QString satName, l1, l2;
    if (extractTle(tleLine1, tleLine2, satName, l1, l2) && startUtc.isValid() && endUtc.isValid() && startUtc < endUtc) {
        try {
            libsgp4::Tle tle(satName.toStdString(), l1.toStdString(), l2.toStdString());
            libsgp4::SGP4 sgp4(tle);

            double safeRate = (sampleRateHz <= 0.0) ? 1.0 : std::clamp(sampleRateHz, 0.1, 10.0);
            double stepSec = 1.0 / safeRate;
            qint64 stepMs = static_cast<qint64>(std::round(stepSec * 1000.0));
            if (stepMs < 100) stepMs = 1000;

            qint64 totalMs = startUtc.msecsTo(endUtc);
            int numSteps = static_cast<int>(totalMs / stepMs) + 1;
            if (numSteps > 3600) numSteps = 3600;

            for (int i = 0; i < numSteps; ++i) {
                QDateTime sampleDt = startUtc.addMSecs(static_cast<qint64>(i) * stepMs);
                libsgp4::DateTime sgpDt = toSgp4DateTime(sampleDt);
                libsgp4::Eci eci = sgp4.FindPosition(sgpDt);
                libsgp4::CoordGeodetic geo = eci.ToGeodetic();

                double latDeg = libsgp4::Util::RadiansToDegrees(geo.latitude);
                double lonDeg = libsgp4::Util::RadiansToDegrees(geo.longitude);
                double altKm = geo.altitude;

                QJsonObject ptObj;
                ptObj["utc_time"] = sampleDt.toString("dd-MM-yyyy HH:mm:ss");
                ptObj["longitude"] = std::round(lonDeg * 100000.0) / 100000.0;
                ptObj["latitiude"] = std::round(latDeg * 100000.0) / 100000.0;
                ptObj["altitude"] = std::round(altKm * 10.0) / 10.0;
                satSessionArray.append(ptObj);
            }
        } catch (...) {
        }
    }

    StationManager stMgr;
    QJsonArray stationsArray;
    for (const QVariant &stVar : stations) {
        QVariantMap stMap = stVar.toMap();
        QString stJsonStr = stMgr.buildStationJson(stMap);
        QJsonDocument stDoc = QJsonDocument::fromJson(stJsonStr.toUtf8());
        if (stDoc.isObject()) {
            stationsArray.append(stDoc.object());
        }
    }

    QJsonObject root;
    root["satellite_session"] = satSessionArray;
    root["ground_stations_list"] = stationsArray;

    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

QString PythonModuleRunner::buildCorrelationInputJson(
    const QString &groundStationName,
    const QString &stationId,
    int expectedSampleCount,
    const QVariantList &factorModuleOutputs)
{
    QJsonArray factorsList;
    int determinedSamples = expectedSampleCount > 0 ? expectedSampleCount : 0;

    // First pass: parse factor module outputs and determine sample count for this station
    struct ParsedFactor {
        QString factorName;
        QString factorUnits;
        QJsonArray values;
    };
    QList<ParsedFactor> parsedFactors;

    for (const QVariant &v : factorModuleOutputs) {
        QString jsonStr;
        if (v.typeId() == QMetaType::QString) {
            jsonStr = v.toString();
        } else if (v.canConvert<QVariantMap>()) {
            jsonStr = v.toMap().value("outputJson").toString();
        }
        if (jsonStr.trimmed().isEmpty()) continue;

        QJsonParseError err;
        QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8(), &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) continue;

        QJsonObject obj = doc.object();
        QString factorName = obj.value("factor_name").toString().trimmed();
        if (factorName.isEmpty()) continue;

        QString factorUnits = obj.value("units").toString().trimmed();
        if (factorUnits.isEmpty()) {
            factorUnits = obj.value("factor_units").toString().trimmed();
        }

        QJsonArray vals;
        if (obj.contains("ground_stations_session_values") && obj.value("ground_stations_session_values").isArray()) {
            QJsonArray stArr = obj.value("ground_stations_session_values").toArray();
            QJsonObject matchedStationObj;
            bool foundMatch = false;

            // 1. Match by stationId and/or ground_station_name
            for (const QJsonValue &stVal : stArr) {
                if (!stVal.isObject()) continue;
                QJsonObject stObj = stVal.toObject();
                QString candId = stObj.value("stationId").toString().trimmed();
                QString candName = stObj.value("ground_station_name").toString().trimmed();
                if ((!stationId.isEmpty() && candId == stationId) ||
                    (!groundStationName.isEmpty() && candName.compare(groundStationName, Qt::CaseInsensitive) == 0)) {
                    matchedStationObj = stObj;
                    foundMatch = true;
                    break;
                }
            }
            // Fallback to first entry if only one station is present in output
            if (!foundMatch && !stArr.isEmpty() && stArr.first().isObject()) {
                matchedStationObj = stArr.first().toObject();
                foundMatch = true;
            }

            if (foundMatch) {
                QJsonArray sessArr = matchedStationObj.value("session_values").toArray();
                for (const QJsonValue &sv : sessArr) {
                    if (sv.isObject()) {
                        vals.append(sv.toObject().value("value"));
                    } else {
                        vals.append(sv);
                    }
                }
            }
        } else if (obj.contains("session_values") && obj.value("session_values").isArray()) {
            QJsonArray sessArr = obj.value("session_values").toArray();
            for (const QJsonValue &sv : sessArr) {
                if (sv.isObject()) {
                    vals.append(sv.toObject().value("value"));
                } else {
                    vals.append(sv);
                }
            }
        } else if (obj.contains("values") && obj.value("values").isArray()) {
            vals = obj.value("values").toArray();
        }

        if (!vals.isEmpty()) {
            determinedSamples = vals.size();
        }
        parsedFactors.append({factorName, factorUnits, vals});
    }

    for (const ParsedFactor &pf : parsedFactors) {
        QJsonArray normalizedVals;
        for (int i = 0; i < determinedSamples; ++i) {
            if (i < pf.values.size()) {
                normalizedVals.append(pf.values.at(i));
            } else {
                normalizedVals.append(0.0);
            }
        }

        QJsonObject factorObj;
        factorObj["factor_name"] = pf.factorName;
        factorObj["factor_units"] = pf.factorUnits;
        factorObj["values"] = normalizedVals;
        factorsList.append(factorObj);
    }

    QJsonObject root;
    root["ground_station_name"] = groundStationName;
    root["samples_count"] = determinedSamples;
    root["factors_list"] = factorsList;

    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

void PythonModuleRunner::runModuleAsync(
    const QString &runId,
    const QString &modulePath,
    const QString &inputJson)
{
    QString cleanPath = cleanFileUrlPath(modulePath);
    QFileInfo modInfo(cleanPath);
    QString moduleName = modInfo.fileName().isEmpty() ? "module.py" : modInfo.fileName();

    if (!modInfo.exists()) {
        emit moduleFinished(runId, moduleName, cleanPath, false, "",
                            QString("Module file does not exist: %1").arg(cleanPath));
        return;
    }

    bool isVenv = false;
    QString pythonExe = resolvePythonExecutable(&isVenv);
    if (pythonExe.isEmpty()) {
        emit moduleFinished(runId, moduleName, cleanPath, false, "",
                            "Python 3 interpreter was not found on system PATH or in .venv.");
        return;
    }

    if (m_activeRuns.contains(runId)) {
        cancelModuleRun(runId);
    }

    addRecentModule(cleanPath);

    ActiveRun *run = new ActiveRun();
    run->runId = runId;
    run->moduleName = moduleName;
    run->modulePath = modInfo.canonicalFilePath();
    run->currentProgress = 0.08;

    QProcess *proc = new QProcess(this);
    run->process = proc;
    proc->setWorkingDirectory(QDir::currentPath());

    QTimer *timer = new QTimer(this);
    run->progressTimer = timer;
    timer->setInterval(120);

    m_activeRuns.insert(runId, run);

    emit moduleStarted(runId, moduleName, run->modulePath);
    emit moduleProgress(runId, moduleName, run->currentProgress, "Initializing Python & sending session data...");

    connect(timer, &QTimer::timeout, this, [this, runId]() {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.value(runId);
        double remaining = 0.92 - r->currentProgress;
        if (remaining > 0.01) {
            r->currentProgress += remaining * 0.18;
        }
        QString stage = (r->currentProgress < 0.35)
                        ? "Propagating LOS geometry..."
                        : (r->currentProgress < 0.75)
                          ? "Querying weather & computing factor along LOS..."
                          : "Finalizing output JSON...";
        emit moduleProgress(runId, r->moduleName, r->currentProgress, stage);
    });

    connect(proc, &QProcess::started, this, [this, runId, inputJson]() {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.value(runId);
        if (r->process) {
            r->process->write(inputJson.toUtf8());
            r->process->closeWriteChannel();
        }
        if (r->progressTimer) {
            r->progressTimer->start();
        }
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, runId](int exitCode, QProcess::ExitStatus exitStatus) {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.take(runId);

        if (r->progressTimer) {
            r->progressTimer->stop();
            r->progressTimer->deleteLater();
        }

        QString stdOut = QString::fromUtf8(r->process->readAllStandardOutput()).trimmed();
        QString stdErr = QString::fromUtf8(r->process->readAllStandardError()).trimmed();
        r->process->deleteLater();

        QString modName = r->moduleName;
        QString modPath = r->modulePath;
        delete r;

        if (exitStatus == QProcess::NormalExit && exitCode == 0 && !stdOut.isEmpty()) {
            QJsonParseError parseErr;
            QJsonDocument doc = QJsonDocument::fromJson(stdOut.toUtf8(), &parseErr);
            if (parseErr.error == QJsonParseError::NoError) {
                QString prettyJson = QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
                emit moduleProgress(runId, modName, 1.0, "Completed");
                emit moduleFinished(runId, modName, modPath, true, prettyJson, "");
            } else {
                emit moduleProgress(runId, modName, 1.0, "Completed (Raw Output)");
                emit moduleFinished(runId, modName, modPath, true, stdOut, "");
            }
        } else {
            QString errMsg = !stdErr.isEmpty()
                             ? stdErr
                             : QString("Process exited with code %1").arg(exitCode);
            emit moduleProgress(runId, modName, 1.0, "Failed");
            emit moduleFinished(runId, modName, modPath, false, stdOut, errMsg);
        }
    });

    connect(proc, &QProcess::errorOccurred, this, [this, runId](QProcess::ProcessError error) {
        if (!m_activeRuns.contains(runId)) return;
        if (error == QProcess::FailedToStart) {
            ActiveRun *r = m_activeRuns.take(runId);
            if (r->progressTimer) {
                r->progressTimer->stop();
                r->progressTimer->deleteLater();
            }
            QString errStr = r->process->errorString();
            r->process->deleteLater();
            QString modName = r->moduleName;
            QString modPath = r->modulePath;
            delete r;

            emit moduleFinished(runId, modName, modPath, false, "",
                                QString("Failed to start Python process: %1").arg(errStr));
        }
    });

    proc->start(pythonExe, {run->modulePath});
}

void PythonModuleRunner::runCorrelationModuleAsync(
    const QString &runId,
    const QString &modulePath,
    const QString &excelPath,
    const QString &groundStationName,
    const QString &inputJson)
{
    QString cleanModPath = cleanFileUrlPath(modulePath);
    QString cleanExcelPath = cleanFileUrlPath(excelPath);

    QFileInfo modInfo(cleanModPath);
    QString baseModName = modInfo.fileName().isEmpty() ? "step_correlation.py" : modInfo.fileName();
    QString displayLabel = groundStationName.isEmpty()
                           ? baseModName
                           : QString("%1 (%2)").arg(baseModName, groundStationName);

    if (!modInfo.exists()) {
        emit moduleFinished(runId, displayLabel, cleanModPath, false, "",
                            QString("Correlation module file does not exist: %1").arg(cleanModPath));
        return;
    }

    bool isVenv = false;
    QString pythonExe = resolvePythonExecutable(&isVenv);
    if (pythonExe.isEmpty()) {
        emit moduleFinished(runId, displayLabel, cleanModPath, false, "",
                            "Python 3 interpreter was not found on system PATH or in .venv.");
        return;
    }

    if (m_activeRuns.contains(runId)) {
        cancelModuleRun(runId);
    }

    addRecentCorrelationModule(cleanModPath);
    if (!cleanExcelPath.isEmpty()) {
        addRecentExcelFile(cleanExcelPath);
    }

    ActiveRun *run = new ActiveRun();
    run->runId = runId;
    run->moduleName = displayLabel;
    run->modulePath = modInfo.canonicalFilePath();
    run->currentProgress = 0.10;

    QProcess *proc = new QProcess(this);
    run->process = proc;
    proc->setWorkingDirectory(QDir::currentPath());

    if (!cleanExcelPath.isEmpty()) {
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("SATCOMHUB_EXCEL_PATH", cleanExcelPath);
        proc->setProcessEnvironment(env);
    }

    QTimer *timer = new QTimer(this);
    run->progressTimer = timer;
    timer->setInterval(100);

    m_activeRuns.insert(runId, run);

    emit moduleStarted(runId, displayLabel, run->modulePath);
    emit moduleProgress(runId, displayLabel, run->currentProgress,
                        QString("Correlating factors for %1...").arg(groundStationName));

    connect(timer, &QTimer::timeout, this, [this, runId, groundStationName]() {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.value(runId);
        double remaining = 0.92 - r->currentProgress;
        if (remaining > 0.01) {
            r->currentProgress += remaining * 0.22;
        }
        QString stage = (r->currentProgress < 0.45)
                        ? QString("Reading Excel table & factors for %1...").arg(groundStationName)
                        : "Evaluating step-function attenuation (dB)...";
        emit moduleProgress(runId, r->moduleName, r->currentProgress, stage);
    });

    connect(proc, &QProcess::started, this, [this, runId, inputJson]() {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.value(runId);
        if (r->process) {
            r->process->write(inputJson.toUtf8());
            r->process->closeWriteChannel();
        }
        if (r->progressTimer) {
            r->progressTimer->start();
        }
    });

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, runId](int exitCode, QProcess::ExitStatus exitStatus) {
        if (!m_activeRuns.contains(runId)) return;
        ActiveRun *r = m_activeRuns.take(runId);

        if (r->progressTimer) {
            r->progressTimer->stop();
            r->progressTimer->deleteLater();
        }

        QString stdOut = QString::fromUtf8(r->process->readAllStandardOutput()).trimmed();
        QString stdErr = QString::fromUtf8(r->process->readAllStandardError()).trimmed();
        r->process->deleteLater();

        QString modName = r->moduleName;
        QString modPath = r->modulePath;
        delete r;

        if (exitStatus == QProcess::NormalExit && exitCode == 0 && !stdOut.isEmpty()) {
            QJsonParseError parseErr;
            QJsonDocument doc = QJsonDocument::fromJson(stdOut.toUtf8(), &parseErr);
            if (parseErr.error == QJsonParseError::NoError) {
                QString prettyJson = QString::fromUtf8(doc.toJson(QJsonDocument::Indented));
                emit moduleProgress(runId, modName, 1.0, "Completed");
                emit moduleFinished(runId, modName, modPath, true, prettyJson, "");
            } else {
                emit moduleProgress(runId, modName, 1.0, "Completed (Raw Output)");
                emit moduleFinished(runId, modName, modPath, true, stdOut, "");
            }
        } else {
            QString errMsg = !stdErr.isEmpty()
                             ? stdErr
                             : QString("Process exited with code %1").arg(exitCode);
            emit moduleProgress(runId, modName, 1.0, "Failed");
            emit moduleFinished(runId, modName, modPath, false, stdOut, errMsg);
        }
    });

    connect(proc, &QProcess::errorOccurred, this, [this, runId](QProcess::ProcessError error) {
        if (!m_activeRuns.contains(runId)) return;
        if (error == QProcess::FailedToStart) {
            ActiveRun *r = m_activeRuns.take(runId);
            if (r->progressTimer) {
                r->progressTimer->stop();
                r->progressTimer->deleteLater();
            }
            QString errStr = r->process->errorString();
            r->process->deleteLater();
            QString modName = r->moduleName;
            QString modPath = r->modulePath;
            delete r;

            emit moduleFinished(runId, modName, modPath, false, "",
                                QString("Failed to start Python correlation process: %1").arg(errStr));
        }
    });

    QStringList args;
    args.append(run->modulePath);
    if (!cleanExcelPath.isEmpty()) {
        args.append("--excel");
        args.append(cleanExcelPath);
    }
    proc->start(pythonExe, args);
}

void PythonModuleRunner::cancelModuleRun(const QString &runId)
{
    if (!m_activeRuns.contains(runId)) return;
    ActiveRun *r = m_activeRuns.take(runId);
    if (r->progressTimer) {
        r->progressTimer->stop();
        r->progressTimer->deleteLater();
    }
    if (r->process) {
        r->process->disconnect(this);
        if (r->process->state() != QProcess::NotRunning) {
            r->process->kill();
            r->process->waitForFinished(300);
        }
        r->process->deleteLater();
    }
    delete r;
}
