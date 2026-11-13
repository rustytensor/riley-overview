// SPDX-License-Identifier: GPL-3.0-or-later
//
// A test window of one solid colour, for the M2 gate. Run with Qt's qml runtime inside the nest:
//   qml colour.qml -- <name> <#rrggbb> <width> <height> [lifetime-seconds]
// Its Wayland app_id (Hyprland "class") is "<reversed organisation domain>.<program name>"; the domain is set to
// "<name>.ro" before the window exists, so the class is "ro.<name>.<program>" (the gate reads the class back from
// hyprctl and matches on the "ro.<name>." prefix). The title is "ro <name>". It quits by itself after the lifetime
// (default 30 s), so nothing is left behind if the gate dies; the gate also ends it by its saved process ID.
import QtQuick
import QtQuick.Window

QtObject {
    id: root
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string name: args[0] || "x"
    property Window win

    Component.onCompleted: {
        Qt.application.domain = root.name + ".ro";
        Qt.application.name = "ro-" + root.name;
        win = winComponent.createObject(null);
    }

    property Component winComponent: Component {
        Window {
            title: "ro " + root.name
            color: root.args[1] || "#ff00ff"
            width: parseInt(root.args[2] || "400")
            height: parseInt(root.args[3] || "300")
            visible: true
            Timer {
                interval: 1000 * parseInt(root.args[4] || "30")
                running: true
                onTriggered: Qt.quit()
            }
        }
    }
}
