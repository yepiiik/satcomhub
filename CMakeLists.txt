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

if (EXISTS "${CMAKE_CURRENT_LIST_DIR}/importedcontent/CMakeLists.txt")
    add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/importedcontent)
endif()

qt_add_executable(appsatcomhub
    src/core/main.cpp
    src/satellite/SatellitePropagator.cpp
    src/satellite/SatellitePropagator.h
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
    RESOURCES
        resources/marker.svg
        resources/earth_equirectangular.jpg
)

set_target_properties(appsatcomhub PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appsatcomhub
    PRIVATE
        Qt6::Quick
        Qt6::Core
        Qt6::Positioning
        Qt6::Location
)

install(TARGETS appsatcomhub
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
