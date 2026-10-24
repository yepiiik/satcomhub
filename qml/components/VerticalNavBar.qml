import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: navBarRoot

    property int currentTab: 0 // 0: Objects, 1: Planning, 2: History
    property bool lightMode: false
    property string currentUtcString: ""

    signal tabSelected(int index)
    signal themeToggleRequested()

    width: 64
    color: lightMode ? "#eef0f3" : "#0d1017"
    border.color: lightMode ? "#dee2e6" : "#1e2230"
    border.width: 1

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 16

        // ================= APP LOGO =================
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 40
            height: 40
            radius: 10
            color: navBarRoot.lightMode ? "#d0ebff" : "#14233c"
            border.color: "#339af0"
            border.width: 1.5

            Text {
                anchors.centerIn: parent
                text: "🛰️"
                font.pixelSize: 20
            }

            ToolTip.visible: logoMouse.containsMouse
            ToolTip.text: "SatComHub v1.0"

            MouseArea {
                id: logoMouse
                anchors.fill: parent
                hoverEnabled: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 10
            Layout.rightMargin: 10
            height: 1
            color: navBarRoot.lightMode ? "#dee2e6" : "#1e2230"
        }

        // ================= NAV ITEMS =================
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            // Tab 0: Objects
            NavItemButton {
                tabIndex: 0
                iconText: "🛰️"
                labelText: qsTr("Objects")
                isActive: navBarRoot.currentTab === 0
                lightMode: navBarRoot.lightMode
                onClicked: navBarRoot.tabSelected(0)
            }

            // Tab 1: Planning
            NavItemButton {
                tabIndex: 1
                iconText: "📅"
                labelText: qsTr("Planning")
                isActive: navBarRoot.currentTab === 1
                lightMode: navBarRoot.lightMode
                onClicked: navBarRoot.tabSelected(1)
            }

            // Tab 2: History
            NavItemButton {
                tabIndex: 2
                iconText: "📜"
                labelText: qsTr("History")
                isActive: navBarRoot.currentTab === 2
                lightMode: navBarRoot.lightMode
                onClicked: navBarRoot.tabSelected(2)
            }
        }

        Item {
            Layout.fillHeight: true
        }

        // ================= BOTTOM ACTIONS =================
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            // Live Pulse / Status
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 10
                height: 10
                radius: 5
                color: "#40c057"

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.3; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                }

                ToolTip.visible: statusMouse.containsMouse
                ToolTip.text: "System Online\n" + navBarRoot.currentUtcString

                MouseArea {
                    id: statusMouse
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }

            // Theme Toggle Button
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 38
                height: 38
                radius: 8
                color: themeBtnMouse.containsMouse ? 
                       (navBarRoot.lightMode ? "#dbe4ee" : "#222736") : 
                       (navBarRoot.lightMode ? "#ffffff" : "#141722")
                border.color: navBarRoot.lightMode ? "#ced4da" : "#2d3345"

                Text {
                    anchors.centerIn: parent
                    text: navBarRoot.lightMode ? "🌙" : "☀️"
                    font.pixelSize: 16
                }

                ToolTip.visible: themeBtnMouse.containsMouse
                ToolTip.text: navBarRoot.lightMode ? qsTr("Switch to Dark Theme") : qsTr("Switch to Light Theme")

                MouseArea {
                    id: themeBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: navBarRoot.themeToggleRequested()
                }
            }
        }
    }

    // Component for Individual Nav Items
    component NavItemButton: Rectangle {
        id: itemRoot
        property int tabIndex: 0
        property string iconText: ""
        property string labelText: ""
        property bool isActive: false
        property bool lightMode: false
        signal clicked()

        Layout.fillWidth: true
        height: 52
        color: isActive ? 
               (lightMode ? "#e3fafc" : "#142338") : 
               (itemMouse.containsMouse ? (lightMode ? "#f1f3f5" : "#161a24") : "transparent")

        // Active left accent bar (CoolerControl / VS Code style)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 3.5
            color: "#339af0"
            visible: itemRoot.isActive
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: itemRoot.iconText
                font.pixelSize: 18
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: itemRoot.labelText
                font.pixelSize: 10
                font.bold: itemRoot.isActive
                color: itemRoot.isActive ? 
                       "#339af0" : 
                       (itemRoot.lightMode ? "#495057" : "#868e96")
            }
        }

        ToolTip.visible: itemMouse.containsMouse && !itemRoot.isActive
        ToolTip.text: itemRoot.labelText

        MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: itemRoot.clicked()
        }
    }
}
