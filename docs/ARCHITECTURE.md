# SatComHub Developer Architecture & Functionality Guide

## 1. Directory Structure

```text
satcomhub/
├── CMakeLists.txt                     # Qt 6.8+ CMake & qt_add_qml_module (URI: satcomhub)
├── Doxyfile                           # Doxygen configuration (C++ + Markdown + Graphviz)
├── docs/
│   └── ARCHITECTURE.md                # This developer guide (also Doxygen mainpage)
├── src/
│   ├── core/
│   │   └── main.cpp                   # QGuiApplication entry point, QML type registration
│   └── satellite/
│       ├── StationManager.{h,cpp}     # Ground station, satellite & history JSON persistence + Friis RF math
│       ├── SatellitePropagator.{h,cpp}# libsgp4 wrapper, pass prediction, SNR profile & YAML export
│       ├── SignalLossModel.{h,cpp}    # FSPL, atmospheric loss, Doppler shift & link-budget SNR
│       └── PythonModuleRunner.{h,cpp} # Async QProcess runner for external Python RF modules
└── qml/
    ├── views/
    │   └── Main.qml                   # Root ApplicationWindow, global state, models & tab orchestration
    └── components/
        ├── common/                    # Shared UI primitives
        │   ├── VerticalNavBar.qml     # Left navigation rail (Objects, Planning, History, theme toggle)
        │   ├── CompactDoubleSpinBox.qml
        │   └── ToastStackOverlay.qml  # Non-blocking notification toasts
        ├── map/                       # Geospatial & orbital visualization
        │   ├── MapComponent.qml       # Map wrapper toggling Mercator / Equirectangular projections
        │   ├── MercatorMapView.qml    # QtLocation OSM/satellite interactive map
        │   ├── EquirectangularMapView.qml # 2D equirectangular projection with canvas tracks
        │   ├── MapControlsOverlay.qml # Zoom, projection & overlay controls
        │   ├── MapUtils.js            # Projection math & geodesic visibility footprint polygons
        │   ├── StationMarker.qml      # Ground station map pin
        │   ├── SatelliteMarker.qml    # Live satellite marker
        │   └── DraftStationMarker.qml # Pick-on-map preview pin
        ├── objects/                   # Objects tab: Ground Stations & Satellites management
        │   ├── ObjectsListSidebar.qml # Sidebar list with active toggles, edit & delete
        │   ├── StationDialog.qml      # Ground station RF/LNA/coordinates modal + JSON import/export
        │   ├── SatelliteDialog.qml    # Satellite TLE/RF/modulation/code-rate modal
        │   └── StationJsonViewer.qml  # Modal JSON inspector & exporter (`showJson(title, content)`)
        ├── planning/                  # Planning tab: Pass windows, SNR/Loss plots & AMC
        │   ├── PlanningListSidebar.qml        # Future pass windows list & forecast horizon selector
        │   ├── PlanningSessionDetailsView.qml # SNR/FSPL/Loss/El plots, AMC table, Python modules, Save to History
        │   ├── PassWindowCalculator.qml       # Pass calculation helper
        │   ├── PassSnrPlotModal.qml           # Expanded SNR plot modal
        │   └── SessionPlanYamlViewer.qml      # YAML/JSON session plan preview & export
        └── history/                   # History tab: Saved & manual session logs
            ├── HistoryListSidebar.qml # Saved/manual sessions list (`+` creates blank session)
            └── HistoryDetailsView.qml # Isolated session view: telemetry plot, editable sat & stations
```

> **Note on Qt 6 QML Module (`URI satcomhub`)**: All QML files under `qml/components/*/` are registered in `qt_add_qml_module(appsatcomhub URI satcomhub)` in `CMakeLists.txt`. Therefore `Main.qml` and components import `satcomhub` and instantiate types directly by component name without relative path imports (except `MapUtils.js`, which stays alongside the map views in `qml/components/map/`).

---

## 2. C++ Backend Classes Exposed to QML

All backend classes are registered in `src/core/main.cpp` under `satcomhub 1.0` and instantiated inside `Main.qml`:

| C++ Class | QML ID | Responsibilities |
| :--- | :--- | :--- |
| `StationManager` | `stationManager` | Friis noise & $G/T$ calculations; JSON serialization & disk persistence for **stations**, **satellites**, and **history sessions**; native file dialogs. |
| `SatellitePropagator` | `propagator` | Live SGP4 TLE propagation; multi-orbit ground tracks; single & multi-station pass window prediction; joint SNR/loss profile generation; AMC $r_{\max}$ formula; YAML session plan export. |
| `SignalLossModel` | *(static C++ helper)* | Core RF physics: Free Space Path Loss (FSPL), atmospheric attenuation, link-budget SNR ($C/N$), Doppler shift, and multi-station diversity combining. |
| `PythonModuleRunner` | `pythonModuleRunner` | Discovers `.venv` Python environment, builds JSON payloads, runs external `.py` factor & `.xlsx`/`.py` correlation scripts asynchronously via `QProcess`. |

---

## 3. Data Persistence Layout

By default, data is stored in `QStandardPaths::AppDataLocation` (e.g., `~/.local/share/satcomhub/` on Linux or `%APPDATA%/satcomhub/` on Windows), or in portable folders next to the executable if present:

```text
<AppData>/satcomhub/
├── stations/
│   ├── GS-01.json                     # Individual ground station configs
│   └── stations.json                  # Aggregate station list
├── satellites/
│   ├── SAT-01.json                    # Individual satellite configs (seeded with ISS & POLYITAN-3-PUT)
│   └── satellites.json                # Aggregate satellite list
└── history/
    └── SESSION_YYYYMMDD_HHMMSS_<Sat>/ # One folder per saved or manual history entry
        ├── session.json               # Session metadata (dates, duration, max SNR, status, notes)
        ├── satellite.json             # Isolated copy of target satellite config for this session
        ├── telemetry.json             # Optional saved SNR/FSPL/Elevation curves from Planning
        └── stations/
            └── <stationId>.json       # Isolated copies of participating ground station configs
```

---

## 4. Key Functional Flows

### 4.1 Planning & Saving to History
1. `PlanningListSidebar` triggers `calculateFuturePasses()` in `Main.qml`, calling `propagator.calculatePassWindows(...)`.
2. Selecting a pass computes `propagator.calculatePassSnrProfile(...)` and renders curves in `PlanningSessionDetailsView`.
3. Clicking **`💾 Save to History`** emits `saveToHistoryRequested()`, which packages the pass metadata, active target satellite, participating ground stations, and SNR telemetry into `stationManager.saveHistorySession(...)`.

### 4.2 History Session Isolation & Manual Entries
- **Editing in History is strictly isolated**: `Main.qml` sets `activeHistoryEditingSessionId` before opening `SatelliteDialog` or `StationDialog`. On commit, `onSatelliteCommitted` / `onStationCommitted` writes only to `history/<sessionId>/satellite.json` or `history/<sessionId>/stations/<stationId>.json`, leaving global `satellitesModel` and `stationsModel` untouched.
- **Manual History Entry (`+` button)**: `HistoryListSidebar` calls `stationManager.createBlankHistorySession()`. `HistoryDetailsView` renders empty Target Satellite and Ground Stations cards at the same positions, each offering a **`📋 Copy Reference`** dropdown (copying from existing app objects) and **`➕ Add ...`** (creating a new object via `SatelliteDialog` / `StationDialog`).

---

## 5. Generating Doxygen Documentation

To generate the browsable HTML API documentation (with Graphviz call/collaboration diagrams):

```bash
# Install doxygen (if not already installed)
sudo apt-get install -y doxygen

# Generate HTML docs into docs/doxygen/
doxygen Doxyfile
```

Then open `docs/doxygen/html/index.html` in a browser.

