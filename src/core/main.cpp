#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "../satellite/SatellitePropagator.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    qmlRegisterType<SatellitePropagator>("satcomhub", 1, 0, "SatellitePropagator");

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
