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
    src/satellite/StationManager.cpp
    src/satellite/StationManager.h
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
        qml/components/MapComponent.qml
        qml/components/StationMarker.qml
        qml/components/SatelliteMarker.qml
        qml/components/DraftStationMarker.qml
        qml/components/MercatorMapView.qml
        qml/components/EquirectangularMapView.qml
        qml/components/MapControlsOverlay.qml
        qml/components/PassWindowCalculator.qml
        qml/components/MapUtils.js
        qml/components/CompactDoubleSpinBox.qml
        qml/components/StationDialog.qml
        qml/components/StationJsonViewer.qml
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
