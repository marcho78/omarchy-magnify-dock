import QtQuick
import qs.Commons
import "IconMetrics.js" as IconMetrics

// One app tile as drawn in the Magnify Dock design: a rounded square (24%
// radius) with a two-stop gradient in the app's dominant hue, an inset top
// highlight, a soft drop shadow, and the app icon centred inside. The hue is
// sampled from the icon itself; icons without a saturated colour get the
// design's neutral slate gradient.
//
// shape "none" drops the tile entirely and shows the bare icon. With
// `uniform` on, each icon's visible artwork (measured once, see
// IconMetrics.js) is scaled to a common optical size, so padded, edge-to-edge
// and round icons line up the way they do on macOS.
Item {
  id: root

  property string iconSource: ""
  property string appName: ""
  property real size: 38
  property real iconRatio: 0.66
  property string shape: "rounded"      // rounded | circle | square | none
  property bool uniform: false
  readonly property bool plain: shape === "none"
  readonly property real radiusRatio: shape === "circle" ? 0.5 : (shape === "square" ? 0.12 : 0.24)
  property string fontFamily: Style.font.family
  property bool hovered: false
  onIconSourceChanged: tile.metrics = IconMetrics.get(root.iconSource)

  width: size
  height: size

  // Tile hue: a stable hash of the app name, so each app gets its own colour
  // and keeps it. (Sampling the icon with ColorQuantizer looked closer to the
  // design but crashes Quickshell when a tile is torn down mid-sample.)
  readonly property real hue: {
    var key = String(root.appName || root.iconSource || "")
    if (!key) return -1
    var h = 2166136261
    for (var i = 0; i < key.length; i++) { h ^= key.charCodeAt(i); h = (h * 16777619) >>> 0 }
    return (h % 360) / 360
  }
  readonly property color tileTop: hue >= 0 ? Qt.hsla(hue, 0.72, 0.61, 1) : "#434c5c"
  readonly property color tileBottom: hue >= 0 ? Qt.hsla(hue, 0.74, 0.45, 1) : "#262b34"

  // Soft drop shadow (design: 0 4px 12px rgba(0,0,0,0.32)) built from a few
  // stacked translucent rectangles. MultiEffect would look closer but it
  // segfaults inside Qt when tiles are instantiated at shell startup.
  Repeater {
    model: root.plain ? 0 : 4
    delegate: Rectangle {
      required property int index
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 2 + index * 1.5
      width: root.size + index * 3
      height: root.size + index * 3
      radius: Math.round((root.size + index * 3) * root.radiusRatio)
      color: Qt.rgba(0, 0, 0, 0.09)
    }
  }

  Rectangle {
    id: tile
    anchors.fill: parent
    radius: Math.round(root.size * root.radiusRatio)
    color: "transparent"
    gradient: root.plain ? null : tileGradient

    Gradient {
      id: tileGradient
      GradientStop { position: 0.0; color: root.hovered ? Qt.lighter(root.tileTop, 1.08) : root.tileTop }
      GradientStop { position: 1.0; color: root.hovered ? Qt.lighter(root.tileBottom, 1.08) : root.tileBottom }
    }

    // Inset edge light that follows the rounded shape.
    Rectangle {
      visible: !root.plain
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.32) }
      GradientStop { position: 0.06; color: "transparent" }
      GradientStop { position: 0.94; color: "transparent" }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.18) }
      }
    }

    // Optical sizing: scale the icon's measured visible extent to a common
    // size and centre it. Until measured (or with `uniform` off) the plain
    // iconRatio layout is used.
    property var metrics: IconMetrics.get(root.iconSource)
    readonly property bool sized: root.uniform && metrics !== null
    readonly property real target: root.size * IconMetrics.targetRatio(sized ? metrics.fill : 0.8,
                                                                        root.plain ? 0.86 : root.iconRatio * 0.92)
    readonly property real extent: sized ? Math.max(0.05, Math.max(metrics.x1 - metrics.x0, metrics.y1 - metrics.y0)) : 1
    readonly property real drawSize: sized ? Math.min(target / extent, root.size * 1.6)
                                           : root.size * (root.plain ? 0.92 : root.iconRatio)

    Image {
      id: icon
      width: Math.round(tile.drawSize)
      height: width
      x: Math.round(root.size / 2 - (tile.sized ? (tile.metrics.x0 + tile.metrics.x1) / 2 : 0.5) * width)
      y: Math.round(root.size / 2 - (tile.sized ? (tile.metrics.y0 + tile.metrics.y1) / 2 : 0.5) * height)
      fillMode: Image.PreserveAspectFit
      source: root.iconSource
      sourceSize.width: Math.round(width * 2 * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * 2 * Screen.devicePixelRatio)
      asynchronous: true
      smooth: true
      mipmap: true
      // Hidden until measured so icons don't visibly jump on first load.
      opacity: root.uniform && !tile.metrics ? 0 : (root.plain && !root.hovered ? 0.92 : 1)
    }

    // Offscreen sampler: reads the icon's pixels once and records its
    // metrics in the shared cache. Canvas drawImage() ignores the destination
    // size for provider-backed (image://icon) sources, so the decoded pixels
    // are read directly at natural size instead.
    Loader {
      active: root.uniform && !tile.metrics && root.iconSource.length > 0
      sourceComponent: Canvas {
        id: sampler
        visible: false
        width: 1
        height: 1
        renderStrategy: Canvas.Immediate
        property string src: root.iconSource
        property bool alive: true
        Component.onCompleted: loadImage(src)
        Component.onDestruction: alive = false
        onImageLoaded: if (alive) requestPaint()
        onPaint: {
          if (!alive || !isImageLoaded(src)) return
          var img = getContext("2d").createImageData(src)
          if (!img || !img.width || !img.height) return
          var m = IconMetrics.measure(src, img.data, img.width, img.height)
          if (alive) tile.metrics = m
        }
      }
    }

    // Fallback initial. Driven by opacity rather than `visible`: the icon
    // loads asynchronously, and if the tile is torn down while a load is in
    // flight (closing the drawer), Qt crashes updating `visible` on an item
    // whose window is already gone. Opacity takes a different path.
    Text {
      opacity: icon.status === Image.Ready ? 0 : 1
      anchors.centerIn: parent
      text: root.appName.length > 0 ? root.appName.charAt(0).toUpperCase() : "★"
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Math.round(root.size * 0.42)
      font.weight: Font.DemiBold
      color: Qt.rgba(1, 1, 1, 0.95)
    }
  }
}
