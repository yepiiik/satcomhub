cmake_minimum_required(VERSION 3.16)

set(SGP4_SOURCES
    CoordGeodetic.cpp
    CoordTopocentric.cpp
    CsvTleLoader.cpp
    DateTime.cpp
    DecayedException.cpp
    Eci.cpp
    Globals.cpp
    Observer.cpp
    OrbitalElements.cpp
    SGP4.cpp
    SatelliteException.cpp
    SolarPosition.cpp
    TimeSpan.cpp
    Tle.cpp
    TleException.cpp
    Util.cpp
    Vector.cpp
)

set(SGP4_HEADERS
    CoordGeodetic.h
    CoordTopocentric.h
    CsvTleLoader.h
    DateTime.h
    DecayedException.h
    Eci.h
    Globals.h
    Observer.h
    OrbitalElements.h
    SatelliteException.h
    SGP4.h
    SolarPosition.h
    TimeSpan.h
    TleException.h
    Tle.h
    Util.h
    Vector.h
)

add_library(sgp4 SHARED ${SGP4_SOURCES} ${SGP4_HEADERS})

target_include_directories(sgp4
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/..>
)

target_compile_features(sgp4 PUBLIC cxx_std_17)

set_target_properties(sgp4 PROPERTIES
    WINDOWS_EXPORT_ALL_SYMBOLS ON
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)
