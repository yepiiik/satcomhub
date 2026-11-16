cmake_minimum_required(VERSION 3.16)

project(satcomhub VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED
    COMPONENTS
        Quick
        Positioning
        Location
)

qt_standard_project_setup(REQUIRES 6.8)

add_subdirectory(third_party/libsgp4)

if (EXISTS "${CMAKE_CURRENT_LIST_DIR}/importedcontent/CMakeLists.txt")
    add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/importedcontent)
endif()

qt_add_executable(appsatcomhub
    src/core/main.cpp
    src/satellite/SatellitePropagator.cpp
    src/satellite/SatellitePropagator.h
    src/satellite/SignalLossModel.cpp
    src/satellite/SignalLossModel.h
    src/satellite/StationManager.cpp
    src/satellite/StationManager.h
    src/satellite/PythonModuleRunner.cpp
    src/satellite/PythonModuleRunner.h
)

target_include_directories(appsatcomhub PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/core
    ${CMAKE_CURRENT_SOURCE_DIR}/src/satellite
)

qt_add_qml_module(appsatcomhub
    URI satcomhub
    VERSION 1.0
    QML_FILES
        qml/views/Main.qml

        # Common UI Components
        qml/components/common/VerticalNavBar.qml
        qml/components/common/CompactDoubleSpinBox.qml
        qml/components/common/ToastStackOverlay.qml
        qml/components/common/SessionOverviewBlock.qml

        # Map & Geospatial Views
        qml/components/map/MapComponent.qml
        qml/components/map/MercatorMapView.qml
        qml/components/map/EquirectangularMapView.qml
        qml/components/map/MapControlsOverlay.qml
        qml/components/map/MapUtils.js
        qml/components/map/StationMarker.qml
        qml/components/map/SatelliteMarker.qml
        qml/components/map/DraftStationMarker.qml

        # Objects (Ground Stations & Satellites)
        qml/components/objects/ObjectsListSidebar.qml
        qml/components/objects/StationDialog.qml
        qml/components/objects/SatelliteDialog.qml
        qml/components/objects/StationJsonViewer.qml

        # Planning (Pass Prediction & Session Plans)
        qml/components/planning/PlanningListSidebar.qml
        qml/components/planning/PlanningSessionDetailsView.qml
        qml/components/planning/PassWindowCalculator.qml
        qml/components/planning/PassSnrPlotModal.qml
        qml/components/planning/SessionPlanYamlViewer.qml

        # History (Saved & Manual Session Logs)
        qml/components/history/HistoryListSidebar.qml
        qml/components/history/HistoryDetailsView.qml
    RESOURCES
        resources/marker.svg
        resources/earth_equirectangular.jpg
        README.md
)

set_target_properties(appsatcomhub PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appsatcomhub
    PRIVATE
        sgp4
        Qt6::Quick
        Qt6::Core
        Qt6::Positioning
        Qt6::Location
)

if (WIN32)
    add_custom_command(TARGET appsatcomhub POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:sgp4>
            $<TARGET_FILE_DIR:appsatcomhub>
    )
endif()

install(TARGETS appsatcomhub sgp4
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
