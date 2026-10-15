import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  property var itemData: null
  property int itemIndex: 0
  property real targetScale: 1.0
  property real targetOffsetX: 0
  property real baseSize: 42
  property real iconSize: 34
  property int magnificationDuration: 55
  property bool isDockHovered: false
  property bool isHovered: false
  property bool reduceMotion: false
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string tileShape: "rounded"
  property bool uniformIcons: false
  // Badge: a count reported by the app (Unity LauncherEntry) and/or an
  // urgent window. Count wins; urgent alone shows a dot.
  property int badgeCount: 0
  property bool badgeUrgent: false
  property real badgeScale: 1
  readonly property bool badgeVisible: badgeCount > 0 || badgeUrgent
  property real bounceY: 0
  property real pressScale: (mouseArea.pressed && !root.isBeingDragged) ? 0.94 : 1.0

  // Drag & drop reorder state
  readonly property bool isPinned: root.itemData ? (root.itemData.isPinned === true) : false
  property bool isBeingDragged: false
  property bool isReordering: false
  property real dragVisualX: 0
  property real dragVisualY: 0
  // Keep gesture coordinates in the window scene. The icon itself is scaled
  // and translated while dragging, so item-local coordinates form a feedback
  // loop and make the pointer appear to stutter.
  property real pressSceneX: 0
  property real pressSceneY: 0
  property bool isPressed: false
  property real dragLiftScale: (root.isBeingDragged && !root.reduceMotion) ? 1.16 : 1.0

  Behavior on dragLiftScale {
    NumberAnimation {
      duration: root.reduceMotion ? 0 : 180
      easing.type: Easing.OutCubic
    }
  }

  readonly property bool isRunning: root.itemData ? (root.itemData.isRunning === true) : false
  readonly property bool isFocused: root.itemData ? (root.itemData.isFocused === true) : false
  readonly property string appName: root.itemData ? String(root.itemData.name || "") : ""
  readonly property string appIcon: root.itemData ? String(root.itemData.icon || "") : ""

  function resolveIcon(raw) {
    var str = String(raw || "").trim()
    if (!str) return Quickshell.iconPath("application-x-executable", true)
    if (str.indexOf("file://") === 0 || str.indexOf("image://") === 0) return str
    if (str.charAt(0) === "/") return Util.fileUrl(str)
    var themed = Quickshell.iconPath(str, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  signal clicked(var item)
  signal pinToggleRequested(var item)
  signal closeRequested(var item)
  signal contextMenuRequested(var item, var sourceItem)
  signal hovered(var item, var sourceItem)
  signal unhovered(var sourceItem)
  signal dragStarted(int index, var item, real sceneX, real sceneY)
  signal dragMoved(int index, var item, real sceneX, real sceneY)
  signal dragEnded(int index, var item, var sourceItem)

  function beginLaunchAnimation() {
    if (root.reduceMotion) return
    launchTimeout.restart()
    launchAnimation.restart()
  }

  function settleLaunchAnimation() {
    launchTimeout.stop()
    launchAnimation.stop()
    launchSettle.restart()
  }

  onIsRunningChanged: if (root.isRunning) root.settleLaunchAnimation()

  // SmoothedAnimation is designed to follow a continuously changing target.
  // Unlike a new NumberAnimation per pointer event, it preserves velocity.
  property real animatedScale: targetScale
  Behavior on animatedScale {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  property real animatedOffsetX: targetOffsetX
  Behavior on animatedOffsetX {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : (root.isReordering ? 220 : root.magnificationDuration)
      maximumEasingTime: root.reduceMotion ? 0 : (root.isReordering ? 65 : 28)
    }
  }

  Behavior on pressScale {
    NumberAnimation {
      duration: root.reduceMotion ? 0 : 80
      easing.type: Easing.OutCubic
    }
  }

  // Fixed slots keep the Row out of the pointer hot path. All magnification
  // displacement is rendered as a transform below.
  width: root.baseSize
  height: root.baseSize
  z: (root.isBeingDragged || root.dragLiftScale > 1.01) ? 999 : (root.isHovered ? 10 : root.animatedScale)

  // Bounce while an app is launching, then settle from the current position
  // once a toplevel appears (or after the safety timeout).
  SequentialAnimation {
    id: launchAnimation
    loops: Animation.Infinite
    // Design: dockBounce 0.55s, up 26px by 40%, settle by 70%.
    NumberAnimation {
      target: root
      property: "bounceY"
      to: -26
      duration: 220
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: root
      property: "bounceY"
      to: 0
      duration: 330
      easing.type: Easing.InOutCubic
    }
  }

  NumberAnimation {
    id: launchSettle
    target: root
    property: "bounceY"
    to: 0
    duration: root.reduceMotion ? 0 : 120
    easing.type: Easing.OutCubic
  }

  Timer {
    id: launchTimeout
    interval: 8000
    onTriggered: root.settleLaunchAnimation()
  }

  Item {
    id: iconContainer
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 5
    width: root.iconSize
    height: root.iconSize
    transformOrigin: Item.Bottom
    scale: root.animatedScale * root.pressScale * root.dragLiftScale
    transform: Translate {
      x: (root.isBeingDragged || root.dragVisualX !== 0) ? root.dragVisualX : root.animatedOffsetX
      y: (root.isBeingDragged || root.dragVisualY !== 0) ? root.dragVisualY : root.bounceY
    }

    DockTile {
      id: iconTile
      anchors.fill: parent
      size: root.iconSize
      iconSource: root.resolveIcon(root.appIcon)
      appName: root.appName
      fontFamily: root.fontFamily
      shape: root.tileShape
      uniform: root.uniformIcons
      hovered: root.isHovered
    }

    // macOS-style badge: red pill with the count at the top-right corner,
    // or a plain dot when a window is only flagged urgent.
    Rectangle {
      id: badge
      visible: root.badgeVisible
      readonly property real base: Math.max(12, Math.round(root.iconSize * 0.36 * root.badgeScale))
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: -Math.round(base * 0.28)
      anchors.rightMargin: -Math.round(base * 0.28)
      height: root.badgeCount > 0 ? base : Math.round(base * 0.7)
      width: root.badgeCount > 0 ? Math.max(base, badgeLabel.implicitWidth + Math.round(base * 0.5)) : height
      radius: height / 2
      color: "#ff3b30"
      border.width: Math.max(1, Math.round(root.iconSize * 0.045))
      border.color: Qt.rgba(0.07, 0.08, 0.1, 0.9)
      scale: visible ? 1 : 0.5
      Behavior on scale { NumberAnimation { duration: root.reduceMotion ? 0 : 160; easing.type: Easing.OutBack } }
      Text {
        id: badgeLabel
        anchors.centerIn: parent
        visible: root.badgeCount > 0
        text: root.badgeCount > 999 ? "999+" : String(root.badgeCount)
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Math.round(badge.base * 0.62))
        font.weight: Font.Bold
        color: "#ffffff"
      }
    }

    // Keep hit-testing aligned with the transformed icon. Opening the context
    // menu on press also prevents a hide/hover transition from swallowing the
    // right-button release.
    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.isBeingDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

      onEntered: {
        if (root.isBeingDragged) return
        root.isHovered = true
        root.hovered(root.itemData, root)
      }

      onExited: {
        root.isHovered = false
        root.unhovered(root)
      }

      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          root.contextMenuRequested(root.itemData, root)
          mouse.accepted = true
          return
        }
        if (mouse.button === Qt.LeftButton) {
          var scenePoint = mouseArea.mapToItem(null, mouse.x, mouse.y)
          root.pressSceneX = scenePoint.x
          root.pressSceneY = scenePoint.y
          root.isPressed = true
          root.isBeingDragged = false
        }
      }

      onPositionChanged: function(mouse) {
        if (root.isPressed && (mouse.buttons & Qt.LeftButton) && root.isPinned) {
          var scenePoint = mouseArea.mapToItem(null, mouse.x, mouse.y)
          var dx = scenePoint.x - root.pressSceneX
          var dy = scenePoint.y - root.pressSceneY
          if (!root.isBeingDragged && (Math.abs(dx) > 6 || Math.abs(dy) > 6)) {
            root.isBeingDragged = true
            root.dragStarted(root.itemIndex, root.itemData, scenePoint.x, scenePoint.y)
          }
          if (root.isBeingDragged) {
            root.dragMoved(root.itemIndex, root.itemData, scenePoint.x, scenePoint.y)
          }
        }
      }

      onReleased: function(mouse) {
        if (mouse.button === Qt.LeftButton) {
          if (root.isBeingDragged) {
            root.isBeingDragged = false
            root.isPressed = false
            root.dragEnded(root.itemIndex, root.itemData, root)
            mouse.accepted = true
            return
          }
          if (root.isPressed) {
            root.isPressed = false
            if (!root.isRunning) root.beginLaunchAnimation()
            root.clicked(root.itemData)
          }
        }
      }

      onCanceled: {
        if (root.isBeingDragged) {
          root.isBeingDragged = false
          root.dragEnded(root.itemIndex, root.itemData, root)
        }
        root.isPressed = false
      }

      onClicked: function(mouse) {
        if (mouse.button === Qt.MiddleButton) {
          if (root.isRunning) root.closeRequested(root.itemData)
          else root.pinToggleRequested(root.itemData)
        }
      }
    }
  }

  // macOS-style running indicator: an unobtrusive dot below every open app.
  // Opacity and scale communicate state without changing the Row's geometry.
  Item {
    id: indicatorContainer
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: -1
    width: 6
    height: 5
    transform: Translate {
      // Follow the icon's displacement while retaining the fixed-size running indicator
      x: root.isBeingDragged ? root.dragVisualX : root.animatedOffsetX
    }

    // Glow behind the dot (design: 0 0 6px of the dot color).
    Rectangle {
      anchors.centerIn: parent
      visible: runningIndicator.visible
      opacity: runningIndicator.opacity * 0.35
      width: runningIndicator.width + 8
      height: width
      radius: width / 2
      color: runningIndicator.color
    }

    Rectangle {
      id: runningIndicator
      visible: opacity > 0.01
      anchors.centerIn: parent
      opacity: root.isRunning ? 1 : 0
      scale: root.isRunning ? 1 : 0.6
      width: root.isFocused ? 5 : 4
      height: width
      radius: width / 2
      color: root.isFocused ? root.accent : Qt.rgba(1, 1, 1, 0.75)

      Behavior on opacity {
        NumberAnimation { duration: root.reduceMotion ? 0 : 140; easing.type: Easing.OutCubic }
      }

      Behavior on scale {
        NumberAnimation { duration: root.reduceMotion ? 0 : 160; easing.type: Easing.OutCubic }
      }

      Behavior on color {
        ColorAnimation { duration: root.reduceMotion ? 0 : 140 }
      }
    }
  }

}
