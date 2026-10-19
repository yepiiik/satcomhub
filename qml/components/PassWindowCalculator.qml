import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: passCalcRoot

    property var satellitesModel: null
    property var stationsModel: null
    property string selectedSatelliteId: ""
    property string selectedStationId: ""
    property var propagator: null
    property bool lightMode: false

    // Calculation settings
    property int forecastHours: 24

    // Calculation result state
    property var passResult: null
    property bool isCalculating: false

    signal passSelected(var passEvent)
    signal satelliteSelected(string satId, string satName)
    signal stationSelected(string stationId, string stationName)

    color: lightMode ? "#ffffff" : "#1a1b1e"
    radius: 10
    border.color: lightMode ? "#dee2e6" : "#2c2e33"
    border.width: 1

    function getSelectedSatellite() {
        if (!satellitesModel || satellitesModel.count === 0) return null
        if (selectedSatelliteId !== "") {
            for (var i = 0; i < satellitesModel.count; i++) {
                if (satellitesModel.get(i).satId === selectedSatelliteId) {
                    return satellitesModel.get(i)
                }
            }
        }
        return satellitesModel.get(0)
    }

    function getActiveStationCount() {
        var c = 0
        if (stationsModel) {
            for (var i = 0; i < stationsModel.count; i++) {
                if (stationsModel.get(i).active !== false) c++
            }
        }
        return c
    }

    function getActiveStations() {
        var list = []
        if (stationsModel) {
            for (var s = 0; s < stationsModel.count; s++) {
                var item = stationsModel.get(s)
                if (item.active !== false) {
                    list.push({
                        stationId: item.stationId,
                        name: item.name,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        altitude: item.altitude || 0,
                        minElevation: item.minElevation !== undefined ? item.minElevation : 5.0
                    })
                }
            }
        }
        return list
    }

    function calculatePasses() {
        if (!propagator) return
        var sat = getSelectedSatellite()
        if (!sat || !sat.tle1 || !sat.tle2) {
            passResult = null
            return
        }

        var stationsToCalc = getActiveStations()
        if (stationsToCalc.length === 0) {
            passResult = { totalPasses: 0, multiStationPasses: 0, passes: [] }
            return
        }

        isCalculating = true
        var res = propagator.calculatePassWindows(sat.tle1, sat.tle2, stationsToCalc, forecastHours, 20.0)
        passResult = res
        isCalculating = false
    }

    // Auto-recalculate whenever satellite or horizon changes
    onSelectedSatelliteIdChanged: calculatePasses()
    onForecastHoursChanged: calculatePasses()

    Component.onCompleted: calculatePasses()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        // --- HEADER ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 32
                height: 32
                radius: 8
                color: "#182842"
                Text {
                    anchors.centerIn: parent
                    text: "📅"
                    font.pixelSize: 16
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    text: qsTr("Future Satellite Pass Windows (F5)")
                    font.bold: true
                    font.pixelSize: 14
                    color: passCalcRoot.lightMode ? "#1971c2" : "#4dabf7"
                }

                Label {
                    text: qsTr("Communication windows & multi-station diversity")
                    font.pixelSize: 11
                    color: passCalcRoot.lightMode ? "#868e96" : "#909296"
                }
            }

            Button {
                id: refreshBtn
                text: "🔄"
                width: 32
                height: 32
                background: Rectangle {
                    radius: 6
                    color: passCalcRoot.lightMode ? "#f1f3f5" : "#25262b"
                    border.color: passCalcRoot.lightMode ? "#ced4da" : "#373a40"
                }
                onClicked: passCalcRoot.calculatePasses()
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Recalculate Pass Windows")
            }
        }

        // --- SATELLITE SELECTION ROW ---
        Rectangle {
            Layout.fillWidth: true
            height: 38
            radius: 6
            color: passCalcRoot.lightMode ? "#f8f9fa" : "#25262b"
            border.color: passCalcRoot.lightMode ? "#e9ecef" : "#373a40"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                    text: "🛰️"
                    font.pixelSize: 14
                }

                Label {
                    text: qsTr("Satellite:")
                    font.pixelSize: 11
                    color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                }

                ComboBox {
                    id: satCombo
                    Layout.fillWidth: true
                    model: passCalcRoot.satellitesModel
                    textRole: "name"
                    currentIndex: {
                        if (!passCalcRoot.satellitesModel) return 0
                        for (var i = 0; i < passCalcRoot.satellitesModel.count; i++) {
                            if (passCalcRoot.satellitesModel.get(i).satId === passCalcRoot.selectedSatelliteId) return i
                        }
                        return 0
                    }
                    onActivated: (index) => {
                        if (passCalcRoot.satellitesModel && index >= 0 && index < passCalcRoot.satellitesModel.count) {
                            var item = passCalcRoot.satellitesModel.get(index)
                            passCalcRoot.selectedSatelliteId = item.satId
                            passCalcRoot.satelliteSelected(item.satId, item.name)
                        }
                    }
                    background: Rectangle {
                        implicitHeight: 28
                        color: "transparent"
                    }
                    contentItem: Text {
                        text: satCombo.displayText
                        font.bold: true
                        font.pixelSize: 12
                        color: "#f59f00"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    popup: Popup {
                        y: satCombo.height
                        width: satCombo.width
                        implicitHeight: contentItem.implicitHeight
                        padding: 1
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: satCombo.popup.visible ? satCombo.delegateModel : null
                            currentIndex: satCombo.highlightedIndex
                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                        background: Rectangle {
                            color: passCalcRoot.lightMode ? "#ffffff" : "#25262b"
                            border.color: passCalcRoot.lightMode ? "#dee2e6" : "#373a40"
                            radius: 6
                        }
                    }
                    delegate: ItemDelegate {
                        width: satCombo.width
                        highlighted: satCombo.highlightedIndex === index
                        contentItem: Text {
                            text: model.name
                            color: passCalcRoot.lightMode ? "#212529" : "#ffffff"
                            font.pixelSize: 12
                            font.bold: satCombo.currentIndex === index
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: satCombo.highlightedIndex === index
                                   ? (passCalcRoot.lightMode ? "#e7f5ff" : "#182842")
                                   : "transparent"
                        }
                    }
                }
            }
        }

        // --- PARTICIPATING GROUND STATIONS (Active vs Passive) ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: stCol.implicitHeight + 14
            radius: 6
            color: passCalcRoot.lightMode ? "#f8f9fa" : "#25262b"
            border.color: passCalcRoot.lightMode ? "#e9ecef" : "#373a40"

            ColumnLayout {
                id: stCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "📡"
                        font.pixelSize: 13
                    }

                    Label {
                        text: qsTr("Stations (%1 active):").arg(passCalcRoot.getActiveStationCount())
                        font.bold: true
                        font.pixelSize: 11
                        color: passCalcRoot.lightMode ? "#212529" : "#ffffff"
                        Layout.fillWidth: true
                    }

                    // Quick Toggle All Active
                    Button {
                        height: 20
                        implicitWidth: 32
                        text: qsTr("All")
                        background: Rectangle {
                            radius: 3
                            color: passCalcRoot.lightMode ? "#e9ecef" : "#373a40"
                        }
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 9
                            font.bold: true
                            color: passCalcRoot.lightMode ? "#1971c2" : "#74c0fc"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (passCalcRoot.stationsModel) {
                                for (var i = 0; i < passCalcRoot.stationsModel.count; i++) {
                                    passCalcRoot.stationsModel.setProperty(i, "active", true)
                                }
                                passCalcRoot.calculatePasses()
                            }
                        }
                    }

                    // Quick Toggle None Active
                    Button {
                        height: 20
                        implicitWidth: 38
                        text: qsTr("None")
                        background: Rectangle {
                            radius: 3
                            color: passCalcRoot.lightMode ? "#e9ecef" : "#373a40"
                        }
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 9
                            font.bold: true
                            color: passCalcRoot.lightMode ? "#868e96" : "#adb5bd"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            if (passCalcRoot.stationsModel) {
                                for (var i = 0; i < passCalcRoot.stationsModel.count; i++) {
                                    passCalcRoot.stationsModel.setProperty(i, "active", false)
                                }
                                passCalcRoot.calculatePasses()
                            }
                        }
                    }
                }

                // Station Pills Flow
                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: passCalcRoot.stationsModel
                        delegate: Rectangle {
                            property bool isActive: model.active !== false
                            height: 24
                            implicitWidth: chipRow.implicitWidth + 12
                            radius: 12
                            color: isActive
                                   ? (passCalcRoot.lightMode ? "#d3f9d8" : "#143a1e")
                                   : (passCalcRoot.lightMode ? "#f1f3f5" : "#1a1b1e")
                            border.color: isActive ? "#40c057" : (passCalcRoot.lightMode ? "#ced4da" : "#373a40")
                            border.width: 1

                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: isActive ? "🟢" : "⚪"
                                    font.pixelSize: 8
                                }

                                Text {
                                    text: model.name
                                    font.bold: isActive
                                    font.pixelSize: 10
                                    color: isActive
                                           ? (passCalcRoot.lightMode ? "#2b8a3e" : "#51cf66")
                                           : (passCalcRoot.lightMode ? "#868e96" : "#adb5bd")
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    passCalcRoot.stationsModel.setProperty(index, "active", !parent.isActive)
                                    passCalcRoot.calculatePasses()
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- FORECAST HORIZON SELECTOR (24h, 48h, 72h) ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label {
                text: qsTr("Forecast:")
                font.pixelSize: 11
                color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
            }

            Repeater {
                model: [24, 48, 72]
                Button {
                    Layout.fillWidth: true
                    height: 26
                    text: modelData + "h"
                    background: Rectangle {
                        radius: 4
                        color: passCalcRoot.forecastHours === modelData ? (passCalcRoot.lightMode ? "#1971c2" : "#1864ab") : "transparent"
                        border.color: passCalcRoot.forecastHours === modelData ? "transparent" : (passCalcRoot.lightMode ? "#ced4da" : "#373a40")
                    }
                    contentItem: Text {
                        text: parent.text
                        color: passCalcRoot.forecastHours === modelData ? "#ffffff" : (passCalcRoot.lightMode ? "#495057" : "#adb5bd")
                        font.bold: passCalcRoot.forecastHours === modelData
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: passCalcRoot.forecastHours = modelData
                }
            }
        }

        // --- ACTION BUTTON: CALCULATE FUTURE SESSIONS ---
        Button {
            id: calcNowBtn
            Layout.fillWidth: true
            height: 36
            property int activeCount: passCalcRoot.getActiveStationCount()
            enabled: activeCount > 0 && !passCalcRoot.isCalculating

            background: Rectangle {
                radius: 6
                color: calcNowBtn.enabled
                       ? (calcNowBtn.down ? "#1864ab" : (passCalcRoot.lightMode ? "#228be6" : "#1c7ed6"))
                       : (passCalcRoot.lightMode ? "#e9ecef" : "#2c2e33")
                border.color: calcNowBtn.enabled ? "transparent" : (passCalcRoot.lightMode ? "#ced4da" : "#373a40")
            }

            contentItem: RowLayout {
                spacing: 8
                anchors.centerIn: parent
                Text {
                    text: passCalcRoot.isCalculating ? "⏳" : "🚀"
                    font.pixelSize: 14
                }
                Text {
                    text: passCalcRoot.isCalculating
                          ? qsTr("Calculating SGP4 Session Windows...")
                          : (calcNowBtn.activeCount > 0
                             ? qsTr("Calculate Future Sessions (%1 active station%2)").arg(calcNowBtn.activeCount).arg(calcNowBtn.activeCount > 1 ? "s" : "")
                             : qsTr("Select at least 1 active station"))
                    color: calcNowBtn.enabled ? "#ffffff" : (passCalcRoot.lightMode ? "#adb5bd" : "#5c5f66")
                    font.bold: true
                    font.pixelSize: 12
                }
            }
            onClicked: passCalcRoot.calculatePasses()
        }

        // --- SUMMARY METRICS BAR ---
        Rectangle {
            Layout.fillWidth: true
            height: 32
            radius: 6
            color: passCalcRoot.lightMode ? "#e7f5ff" : "#10233b"
            border.color: passCalcRoot.lightMode ? "#a5d8ff" : "#1c7ed6"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 12

                Label {
                    text: "📊 " + (passCalcRoot.passResult ? (passCalcRoot.passResult.totalPasses + " passes") : "0 passes")
                    font.bold: true
                    font.pixelSize: 11
                    color: passCalcRoot.lightMode ? "#1971c2" : "#74c0fc"
                }

                Label {
                    visible: passCalcRoot.passResult && passCalcRoot.passResult.multiStationPasses > 0
                    text: "🤝 " + (passCalcRoot.passResult ? passCalcRoot.passResult.multiStationPasses : 0) + " joint/diversity"
                    font.bold: true
                    font.pixelSize: 11
                    color: "#51cf66"
                    Layout.fillWidth: true
                }

                Label {
                    visible: passCalcRoot.getActiveStationCount() === 1 && passCalcRoot.passResult && passCalcRoot.passResult.totalPasses > 0
                    text: "🎯 Single station session"
                    font.bold: true
                    font.pixelSize: 11
                    color: passCalcRoot.lightMode ? "#1971c2" : "#74c0fc"
                    Layout.fillWidth: true
                }

                Item {
                    visible: !passCalcRoot.passResult || (passCalcRoot.passResult.multiStationPasses === 0 && passCalcRoot.getActiveStationCount() !== 1)
                    Layout.fillWidth: true
                }
            }
        }

        // --- PASSES LIST VIEW ---
        ListView {
            id: passesListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: (passCalcRoot.passResult && passCalcRoot.passResult.passes) ? passCalcRoot.passResult.passes : []

            delegate: Rectangle {
                id: passCard
                width: passesListView.width
                implicitHeight: passCardLayout.implicitHeight + 16
                radius: 8
                color: passCalcRoot.lightMode ? "#f8f9fa" : "#25262b"
                border.color: modelData.isMultiStation
                              ? "#2f9e44"
                              : (modelData.maxElevationDeg >= 50.0 ? "#f59f00" : (passCalcRoot.lightMode ? "#dee2e6" : "#373a40"))
                border.width: modelData.isMultiStation ? 2 : 1

                property bool expanded: false

                ColumnLayout {
                    id: passCardLayout
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    // Top Row: Pass # + Relative Time + Duration
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 24
                            height: 20
                            radius: 4
                            color: passCalcRoot.lightMode ? "#e9ecef" : "#2c2e33"
                            Text {
                                anchors.centerIn: parent
                                text: "#" + modelData.passIndex
                                font.bold: true
                                font.pixelSize: 10
                                color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                            }
                        }

                        Label {
                            text: modelData.relativeAos
                            font.bold: true
                            font.pixelSize: 12
                            color: passCalcRoot.lightMode ? "#212529" : "#ffffff"
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            height: 22
                            width: durText.implicitWidth + 12
                            radius: 11
                            color: passCalcRoot.lightMode ? "#e7f5ff" : "#182842"
                            Text {
                                id: durText
                                anchors.centerIn: parent
                                text: "⏱️ " + modelData.combinedDurationFormatted
                                font.bold: true
                                font.pixelSize: 11
                                color: "#339af0"
                            }
                        }
                    }

                    // Multi-Station Diversity Badge (if applicable)
                    Rectangle {
                        visible: modelData.isMultiStation
                        Layout.fillWidth: true
                        height: 24
                        radius: 4
                        color: passCalcRoot.lightMode ? "#ebfbee" : "#12281a"
                        border.color: "#40c057"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                text: "🤝 Multi-Station Diversity: " + modelData.stationCount + " Stations" + (modelData.windowGainPercent > 0 ? " (+" + modelData.windowGainPercent + "% duration gain)" : "")
                                font.bold: true
                                font.pixelSize: 10
                                color: "#40c057"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Concurrent High-SNR Overlap Pill (if stations see satellite simultaneously)
                    Rectangle {
                        visible: modelData.hasConcurrentOverlap
                        Layout.fillWidth: true
                        height: 20
                        radius: 4
                        color: passCalcRoot.lightMode ? "#fff9db" : "#372c15"
                        border.color: "#f59f00"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 4

                            Text {
                                text: "⚡ High-SNR Overlap Window: " + modelData.overlapDurationFormatted + " concurrent visibility"
                                font.bold: true
                                font.pixelSize: 10
                                color: "#f59f00"
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Station Names
                    Label {
                        text: "📡 " + modelData.stationNames
                        font.pixelSize: 11
                        color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Metrics Row (Peak Elevation & Range)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            height: 20
                            width: elBadgeText.implicitWidth + 10
                            radius: 4
                            color: modelData.maxElevationDeg >= 50.0
                                   ? "#2f9e44"
                                   : (modelData.maxElevationDeg >= 20.0 ? "#f59f00" : (passCalcRoot.lightMode ? "#adb5bd" : "#495057"))
                            Text {
                                id: elBadgeText
                                anchors.centerIn: parent
                                text: "Peak " + modelData.maxElevationDeg + "°" + (modelData.maxElevationDeg >= 50 ? " (High/Overhead)" : "")
                                color: "#ffffff"
                                font.bold: true
                                font.pixelSize: 10
                            }
                        }

                        Label {
                            text: "AOS: " + modelData.combinedAosUtc.substring(11, 19) + " → LOS: " + modelData.combinedLosUtc.substring(11, 19)
                            font.pixelSize: 10
                            font.family: "monospace"
                            color: passCalcRoot.lightMode ? "#868e96" : "#909296"
                            Layout.fillWidth: true
                        }
                    }

                    // Expand / Collapse Details Button
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Button {
                            height: 24
                            Layout.fillWidth: true
                            text: passCard.expanded ? qsTr("▲ Hide Station Breakdown") : qsTr("▼ Show Station Breakdown (" + (modelData.stationPasses ? modelData.stationPasses.length : 0) + ")")
                            background: Rectangle {
                                radius: 4
                                color: "transparent"
                                border.color: passCalcRoot.lightMode ? "#dee2e6" : "#373a40"
                            }
                            contentItem: Text {
                                text: parent.text
                                color: passCalcRoot.lightMode ? "#1971c2" : "#74c0fc"
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: passCard.expanded = !passCard.expanded
                        }

                        Button {
                            height: 24
                            width: 60
                            text: qsTr("Select")
                            background: Rectangle {
                                radius: 4
                                color: passCalcRoot.lightMode ? "#228be6" : "#1c7ed6"
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#ffffff"
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: passCalcRoot.passSelected(modelData)
                        }
                    }

                    // Expanded Breakdown List
                    ColumnLayout {
                        visible: passCard.expanded
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: passCalcRoot.lightMode ? "#dee2e6" : "#373a40"
                        }

                        Repeater {
                            model: modelData.stationPasses || []
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: spCol.implicitHeight + 8
                                radius: 4
                                color: passCalcRoot.lightMode ? "#f1f3f5" : "#1a1b1e"

                                ColumnLayout {
                                    id: spCol
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: "📡 " + modelData.stationName
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: passCalcRoot.lightMode ? "#212529" : "#ffffff"
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "Peak: " + modelData.maxElevationDeg + "°"
                                            font.bold: true
                                            font.pixelSize: 11
                                            color: "#f59f00"
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: "AOS " + modelData.aosUtc + " (" + modelData.aosAzimuthCompass + ")"
                                            font.pixelSize: 10
                                            color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "LOS " + modelData.losUtc + " (" + modelData.losAzimuthCompass + ")"
                                            font.pixelSize: 10
                                            color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            text: "TCA Range: " + modelData.tcaRangeKm + " km • Duration: " + modelData.durationFormatted
                                            font.pixelSize: 10
                                            color: passCalcRoot.lightMode ? "#868e96" : "#909296"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state / calculating placeholder
            Item {
                anchors.fill: parent
                visible: passesListView.count === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: passCalcRoot.isCalculating ? "⏳" : "📡"
                        font.pixelSize: 32
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: passCalcRoot.isCalculating
                              ? qsTr("Calculating SGP4 session passes...")
                              : (passCalcRoot.getActiveStationCount() === 0
                                 ? qsTr("No active stations selected")
                                 : qsTr("No pass windows found"))
                        font.bold: true
                        font.pixelSize: 13
                        color: passCalcRoot.lightMode ? "#495057" : "#adb5bd"
                    }

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: passCalcRoot.isCalculating
                              ? qsTr("Propagating orbit against active ground stations")
                              : (passCalcRoot.getActiveStationCount() === 0
                                 ? qsTr("Click station chips above to make them active")
                                 : qsTr("Try expanding the forecast horizon (48h/72h)"))
                        font.pixelSize: 11
                        color: passCalcRoot.lightMode ? "#868e96" : "#6c757d"
                    }
                }
            }
        }
    }
}
