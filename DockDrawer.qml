import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

// Full-screen application drawer opened from the dock's launcher tile, per
// the design: dimmed backdrop, a wide search field with an ESC badge, an
// uppercase heading, and a grid of 62px icons with labels. Escape or a click
// on the backdrop closes it; Enter launches the first match.
PanelWindow {
  id: root

  property bool open: false
  property var dockScreen: null
  property var appLibrary: null
  property real textScale: 1
  property string fontFamily: Style.font.family
  property string tileShape: "rounded"
  property bool uniformIcons: false
  // Follows the dock's "Background opacity" setting: a solid backdrop at
  // 100%, more see-through as it is lowered.
  property real backdropOpacity: 0.9
  property color backdropColor: "#0a0c11"
  // Height of the dock's own window; the drawer stops above it so the dock
  // stays visible and clickable while the drawer is open, as in the design.
  property real bottomInset: 0
  property string query: ""

  signal drawerClosed()
  signal pinToggleRequested(var app)
  signal launched(var app)
  // Drag a tile toward the dock. Positions are in this window's coordinates;
  // the dock sits directly below this window's bottom edge.
  signal dragMoved(var app, real x, real y)
  signal dragEnded(var app, real x, real y)

  property var dragApp: null
  property real dragX: 0
  property real dragY: 0
  readonly property bool dragging: dragApp !== null

  // Ids of apps currently pinned, so the menu can say Keep or Remove.
  property var pinnedIds: []
  property var menuApp: null
  property real menuX: 0
  property real menuY: 0
  function isPinned(app) {
    if (!app) return false
    for (var i = 0; i < root.pinnedIds.length; i++) {
      if (DockModel.matchApp(root.pinnedIds[i], app.id)) return true
    }
    return false
  }
  function openMenu(app, x, y) {
    root.menuApp = app
    root.menuX = Math.min(x, root.width - 200)
    root.menuY = Math.min(y, root.height - root.bottomInset - 110)
  }
  function closeMenu() { root.menuApp = null }

  // Only computed while open: the grid instantiates a tile per app.
  readonly property var apps: root.open ? DockModel.drawerApps(DesktopEntries, root.appLibrary, Quickshell, root.query) : []

  function launch(app) {
    root.close()
    root.launched(app)
    DockModel.handleItemClick(app, Quickshell, root.appLibrary, DesktopEntries)
  }
  function close() {
    if (!root.open) return
    root.open = false
    root.drawerClosed()
  }

  onOpenChanged: {
    if (open) {
      root.query = ""
      searchInput.text = ""
      Qt.callLater(function() { searchInput.forceActiveFocus() })
    }
  }

  visible: open
  screen: dockScreen
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  margins { bottom: root.bottomInset }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-dock-drawer"
  WlrLayershell.layer: WlrLayer.Overlay
  // OnDemand rather than Exclusive: an exclusive overlay grab keeps pointer
  // input from reaching the dock below, so the launcher tile could not close
  // the drawer. OnDemand still gives the search field the keyboard on open.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  Rectangle {
    id: backdrop
    anchors.fill: parent
    color: Qt.rgba(root.backdropColor.r, root.backdropColor.g, root.backdropColor.b, root.backdropOpacity)
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: { if (root.menuApp) root.closeMenu(); else root.close() }
    }

    Keys.onEscapePressed: { if (root.menuApp) root.closeMenu(); else root.close() }

    // Search
    Rectangle {
      id: searchBox
      anchors.top: parent.top
      anchors.topMargin: Math.round(parent.height * 0.07)
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(560, parent.width * 0.8)
      height: Math.round(54 * Math.max(1, root.textScale))
      radius: 14
      color: Qt.rgba(1, 1, 1, 0.09)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.14)

      // Inset edge light that follows the rounded shape.
      Rectangle {
        anchors.fill: parent
        radius: 14
        gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
        GradientStop { position: 0.06; color: "transparent" }
        }
      }

      MouseArea { anchors.fill: parent; onClicked: searchInput.forceActiveFocus() }

      Text {
        id: searchGlyph
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        text: "󰍉"
        font.family: root.fontFamily
        font.pixelSize: 19
        color: "#ffffff"
        opacity: 0.55
      }

      TextInput {
        id: searchInput
        anchors.left: searchGlyph.right
        anchors.leftMargin: 12
        anchors.right: escBadge.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        font.family: root.fontFamily
        font.pixelSize: Math.round(20 * root.textScale)
        color: "#ffffff"
        selectionColor: Qt.rgba(1, 1, 1, 0.25)
        clip: true
        onTextChanged: root.query = text
        Keys.onEscapePressed: root.close()
        Keys.onReturnPressed: if (root.apps.length > 0) root.launch(root.apps[0])
        Keys.onEnterPressed: if (root.apps.length > 0) root.launch(root.apps[0])
        Text {
          visible: searchInput.text.length === 0
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          text: "Search applications"
          font: searchInput.font
          color: Qt.rgba(1, 1, 1, 0.38)
        }
      }

      Rectangle {
        id: escBadge
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        width: escLabel.implicitWidth + 14
        height: 21
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        Text {
          id: escLabel
          anchors.centerIn: parent
          text: "ESC"
          font.family: root.fontFamily
          font.pixelSize: 11
          font.weight: Font.Medium
          font.letterSpacing: 0.5
          color: Qt.rgba(1, 1, 1, 0.5)
        }
      }
    }

    // Grid
    Item {
      id: gridArea
      anchors.top: searchBox.bottom
      anchors.topMargin: Math.round(parent.height * 0.05)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(880, parent.width * 0.92)
      opacity: root.open ? 1 : 0
      scale: root.open ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

      MouseArea { anchors.fill: parent }  // clicks inside do not close

      Text {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: 10
        text: root.query.trim().length > 0 ? "RESULTS" : "ALL APPLICATIONS"
        font.family: root.fontFamily
        font.pixelSize: Math.round(11 * root.textScale)
        font.weight: Font.DemiBold
        font.letterSpacing: 1.5
        color: Qt.rgba(1, 1, 1, 0.42)
      }

      GridView {
        id: grid
        anchors.top: heading.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: root.apps
        readonly property int columns: Math.max(1, Math.floor(width / 100))
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.round(62 + 9 + 22 + 16 * root.textScale)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: grid.contentHeight > grid.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        delegate: Item {
          id: cell
          required property var modelData
          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 14
            color: cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            spacing: 9
            DockTile {
              anchors.horizontalCenter: parent.horizontalCenter
              size: 62
              iconSource: cell.modelData.icon
              appName: cell.modelData.name
              fontFamily: root.fontFamily
              shape: root.tileShape
              uniform: root.uniformIcons
              hovered: cellMouse.containsMouse
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              width: 92
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: cell.modelData.name
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Math.round(12.5 * root.textScale)
              font.weight: Font.Medium
              color: Qt.rgba(1, 1, 1, 0.88)
            }
          }

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            property real pressX: 0
            property real pressY: 0
            property bool armed: false
            property bool didDrag: false
            onPressed: function(mouse) {
              if (mouse.button !== Qt.LeftButton) return
              var p = cellMouse.mapToItem(backdrop, mouse.x, mouse.y)
              pressX = p.x; pressY = p.y; armed = true; didDrag = false
            }
            onPositionChanged: function(mouse) {
              if (!armed || !(mouse.buttons & Qt.LeftButton)) return
              var p = cellMouse.mapToItem(backdrop, mouse.x, mouse.y)
              if (!root.dragging) {
                if (Math.abs(p.x - pressX) < 8 && Math.abs(p.y - pressY) < 8) return
                root.dragApp = cell.modelData
                root.closeMenu()
                didDrag = true
              }
              root.dragX = p.x; root.dragY = p.y
              root.dragMoved(cell.modelData, p.x, p.y)
            }
            onReleased: function(mouse) {
              if (mouse.button !== Qt.LeftButton) return
              armed = false
              if (root.dragging) {
                var p = cellMouse.mapToItem(backdrop, mouse.x, mouse.y)
                var app = root.dragApp
                root.dragApp = null
                root.dragEnded(app, p.x, p.y)
              }
            }
            onCanceled: { armed = false; if (root.dragging) { var app = root.dragApp; root.dragApp = null; root.dragEnded(app, -1, -1) } }
            onClicked: function(mouse) {
              if (didDrag) { didDrag = false; return }
              if (mouse.button === Qt.RightButton) {
                var p = cellMouse.mapToItem(backdrop, mouse.x, mouse.y)
                root.openMenu(cell.modelData, p.x, p.y)
              } else if (mouse.button === Qt.MiddleButton) {
                root.pinToggleRequested(cell.modelData)
              } else if (root.menuApp) {
                root.closeMenu()
              } else {
                root.launch(cell.modelData)
              }
            }
          }
        }
      }

      Item { id: menuAnchorDummy; width: 0; height: 0 }

      Text {
        visible: root.apps.length === 0
        anchors.top: heading.bottom
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        text: "No applications match “" + root.query + "”"
        font.family: root.fontFamily
        font.pixelSize: Math.round(15 * root.textScale)
        color: Qt.rgba(1, 1, 1, 0.45)
      }
    }

    // Ghost of the tile being dragged, following the pointer (clamped to the
    // bottom edge once the pointer is over the dock).
    DockTile {
      visible: root.dragging
      z: 100
      size: 62
      x: root.dragX - 31
      y: Math.min(root.dragY - 31, backdrop.height - 62)
      opacity: 0.92
      scale: 1.06
      iconSource: root.dragApp ? root.dragApp.icon : ""
      appName: root.dragApp ? root.dragApp.name : ""
      fontFamily: root.fontFamily
      shape: root.tileShape
      uniform: root.uniformIcons
    }

    // Right-click menu for a tile: Open, Keep in Dock / Remove from Dock.
    DockGlass {
      id: tileMenu
      visible: root.menuApp !== null
      open: visible
      x: root.menuX
      y: root.menuY
      width: Math.round(200 * Math.max(1, Math.min(1.3, root.textScale)))
      height: menuColumn.implicitHeight + 10
      glassOpacity: Math.max(0.9, root.backdropOpacity)
      glassColor: Qt.lighter(root.backdropColor, 1.6)

      Column {
        id: menuColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 5

        Text {
          width: parent.width
          leftPadding: 14; rightPadding: 14; topPadding: 7; bottomPadding: 5
          elide: Text.ElideRight
          text: root.menuApp ? String(root.menuApp.name || "").toUpperCase() : ""
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Math.round(11 * root.textScale)
          font.weight: Font.DemiBold
          font.letterSpacing: 1.1
          color: Qt.rgba(1, 1, 1, 0.4)
        }
        Repeater {
          model: [
            { label: "Open", action: "open" },
            { label: root.isPinned(root.menuApp) ? "Remove from Dock" : "Keep in Dock", action: "pin" }
          ]
          delegate: Rectangle {
            id: menuRow
            required property var modelData
            width: menuColumn.width - 10
            x: 5
            height: Math.round(30 * root.textScale)
            radius: 8
            color: menuRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
            Text {
              anchors.left: parent.left
              anchors.leftMargin: 9
              anchors.verticalCenter: parent.verticalCenter
              text: menuRow.modelData.label
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Math.round(13.5 * root.textScale)
              color: Qt.rgba(1, 1, 1, 0.92)
            }
            MouseArea {
              id: menuRowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var app = root.menuApp
                root.closeMenu()
                if (menuRow.modelData.action === "open") root.launch(app)
                else root.pinToggleRequested(app)
              }
            }
          }
        }
      }
    }

  }
}
