#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "../satellite/SatellitePropagator.h"
#include "../satellite/StationManager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName("satcomhub");
    app.setApplicationName("satcomhub");

    qmlRegisterType<SatellitePropagator>("satcomhub", 1, 0, "SatellitePropagator");
    qmlRegisterType<StationManager>("satcomhub", 1, 0, "StationManager");

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("satcomhub", "Main");

    return QGuiApplication::exec();
}
