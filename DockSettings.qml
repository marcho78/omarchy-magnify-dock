import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import "DockModel.js" as DockModel

// Settings window: a wide glass card with a page list on the left and one
// page of controls on the right, so nothing stacks into a long scroll.
// Pages: Appearance, Colors, Windows, Dock items, Behavior, Presets.
DockGlass {
  id: root

  property var settings: ({})
  property bool isAutoHide: false
  property bool isReserveSpace: true
  property real maxHeight: 620
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property var presets: []
  property string page: "appearance"
  readonly property real textScale: settings && settings.textScale ? settings.textScale : 1
  readonly property var colorPresets: DockModel.colorPresets
  readonly property var accentPresets: DockModel.accentPresets
  readonly property string homeDir: Quickshell.env("HOME")

  signal preferenceChanged(string key, var value)
  signal autoHideToggled()
  signal reserveSpaceToggled()
  signal dismissed()
  signal presetSaved(string name)
  signal presetApplied(string name)
  signal presetDeleted(string name)

  readonly property real ts: Math.max(1, Math.min(1.25, textScale))
  readonly property var pages: [
    { id: "appearance", label: "Appearance", glyph: "󰃟" },
    { id: "colors", label: "Colors", glyph: "󰏘" },
    { id: "windows", label: "Windows", glyph: "󰖯" },
    { id: "items", label: "Dock items", glyph: "󰀻" },
    { id: "behavior", label: "Behavior", glyph: "󰒓" },
    { id: "presets", label: "Presets", glyph: "󰆓" }
  ]

  open: visible
  width: Math.round(700 * ts)
  height: Math.min(maxHeight, header.height + body.height + footer.height)

  function w(a) { return Qt.rgba(1, 1, 1, a) }
  function folders() { return Array.isArray(root.settings.folders) ? root.settings.folders : [] }
  function addFolder(path) {
    var clean = String(path || "").trim().replace(/\/+$/, "")
    if (clean.indexOf("~") === 0) clean = root.homeDir + clean.substring(1)
    if (clean.charAt(0) !== "/") return false
    var list = root.folders().slice()
    if (list.indexOf(clean) >= 0 || list.length >= 8) return false
    list.push(clean)
    root.preferenceChanged("folders", list)
    return true
  }
  function removeFolder(path) {
    root.preferenceChanged("folders", root.folders().filter(function(f) { return f !== path }))
  }

  // ---------- reusable rows ----------

  component SectionTitle: Text {
    property string title: ""
    text: title.toUpperCase()
    font.family: root.fontFamily
    font.pixelSize: Math.round(10.5 * root.textScale)
    font.weight: Font.DemiBold
    font.letterSpacing: 1.3
    color: root.w(0.38)
    topPadding: 14
    bottomPadding: 6
  }

  component SliderRow: Column {
    id: sliderRow
    property string key: ""
    property string label: ""
    property real min: 0
    property real max: 1
    property real step: 0.1
    property string fmt: "px"
    spacing: 7
    topPadding: 6
    bottomPadding: 4
    function display(v) {
      if (fmt === "%") return Math.round(v * 100) + "%"
      if (fmt === "x") return "×" + Number(v).toFixed(2)
      if (fmt === "") return String(Math.round(v))
      return Math.round(v) + " px"
    }
    Item {
      width: parent.width
      height: 14
      Text {
        anchors.left: parent.left
        anchors.baseline: parent.bottom
        text: sliderRow.label
        font.family: root.fontFamily
        font.pixelSize: Math.round(13 * root.textScale)
        font.weight: Font.Medium
        color: root.w(0.85)
      }
      Text {
        anchors.right: parent.right
        anchors.baseline: parent.bottom
        text: sliderRow.display(control.value)
        font.family: root.fontFamily
        font.pixelSize: Math.round(12 * root.textScale)
        font.weight: Font.Medium
        color: root.w(0.5)
      }
    }
    Slider {
      id: control
      objectName: sliderRow.key
      width: parent.width
      height: 20
      from: sliderRow.min
      to: sliderRow.max
      stepSize: sliderRow.step
      value: Number(root.settings[sliderRow.key])
      Accessible.name: sliderRow.label
      onMoved: root.preferenceChanged(sliderRow.key, value)
      background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: 4
        radius: 2
        color: root.w(0.16)
        Rectangle {
          width: control.visualPosition * parent.width
          height: parent.height
          radius: 2
          color: root.w(0.45)
        }
      }
      handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: 15
        height: 15
        radius: 7.5
        color: "#ffffff"
        border.width: 0
      }
    }
  }

  component ToggleRow: Item {
    id: toggleRow
    property string label: ""
    property string sub: ""
    property bool on: false
    signal toggled()
    height: Math.max(44, labelCol.implicitHeight + 12)
    Column {
      id: labelCol
      anchors.left: parent.left
      anchors.right: track.left
      anchors.rightMargin: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Text {
        text: toggleRow.label
        font.family: root.fontFamily
        font.pixelSize: Math.round(13 * root.textScale)
        font.weight: Font.Medium
        color: root.w(0.85)
      }
      Text {
        width: parent.width
        visible: toggleRow.sub !== ""
        text: toggleRow.sub
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Math.round(11.5 * root.textScale)
        color: root.w(0.42)
      }
    }
    Rectangle {
      id: track
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: 40
      height: 24
      radius: 12
      color: toggleRow.on ? root.accent : root.w(0.16)
      Behavior on color { ColorAnimation { duration: 180 } }
      Rectangle {
        x: toggleRow.on ? 19 : 3
        y: 3
        width: 18
        height: 18
        radius: 9
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: toggleRow.toggled()
    }
  }

  component Segmented: Rectangle {
    id: segmented
    property var options: []      // [{id, label}]
    property string current: ""
    signal chosen(string id)
    height: Math.round(34 * root.textScale)
    radius: 9
    color: root.w(0.08)
    Row {
      anchors.fill: parent
      anchors.margins: 3
      spacing: 0
      Repeater {
        model: segmented.options
        delegate: Rectangle {
          id: seg
          required property var modelData
          readonly property bool selected: segmented.current === modelData.id
          width: parent.width / Math.max(1, segmented.options.length)
          height: parent.height
          radius: 7
          color: selected ? root.w(0.16) : (segMouse.containsMouse ? root.w(0.06) : "transparent")
          Text {
            anchors.centerIn: parent
            text: seg.modelData.label
            font.family: root.fontFamily
            font.pixelSize: Math.round(12.5 * root.textScale)
            font.weight: Font.Medium
            color: seg.selected ? "#ffffff" : root.w(0.55)
          }
          MouseArea {
            id: segMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: segmented.chosen(seg.modelData.id)
          }
        }
      }
    }
  }

  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property bool primary: false
    property bool active: true
    signal clicked()
    width: pillLabel.implicitWidth + 24
    height: Math.round(30 * root.textScale)
    radius: 8
    color: !active ? root.w(0.08)
      : primary ? (pillMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent)
      : (pillMouse.containsMouse ? root.w(0.18) : root.w(0.11))
    Text {
      id: pillLabel
      anchors.centerIn: parent
      text: pill.label
      font.family: root.fontFamily
      font.pixelSize: Math.round(12.5 * root.textScale)
      font.weight: Font.DemiBold
      color: pill.active ? "#ffffff" : root.w(0.4)
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: pill.active ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (pill.active) pill.clicked()
    }
  }

  component TextBox: Rectangle {
    id: box
    property alias text: input.text
    property string placeholder: ""
    signal accepted()
    height: Math.round(34 * root.textScale)
    radius: 9
    color: root.w(0.08)
    border.width: 1
    border.color: input.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7) : root.w(0.10)
    MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 11
      anchors.rightMargin: 11
      verticalAlignment: TextInput.AlignVCenter
      font.family: root.fontFamily
      font.pixelSize: Math.round(13 * root.textScale)
      color: "#ffffff"
      selectionColor: Qt.rgba(1, 1, 1, 0.25)
      clip: true
      Keys.onReturnPressed: box.accepted()
      Keys.onEnterPressed: box.accepted()
      Text {
        visible: input.text.length === 0
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: box.placeholder
        font: input.font
        color: root.w(0.35)
      }
    }
  }

  component ColorBlock: Column {
    id: colorBlock
    property string key: ""
    property string label: ""
    property var swatches: []
    property bool allowTheme: false
    property string hint: "#RRGGBB"
    property color fallback: "#000000"
    readonly property string current: String(root.settings[key] || "")
    spacing: 8
    Text {
      text: colorBlock.label
      font.family: root.fontFamily
      font.pixelSize: Math.round(13 * root.textScale)
      font.weight: Font.Medium
      color: root.w(0.85)
    }
    Flow {
      width: parent.width
      spacing: 7
      Rectangle {
        visible: colorBlock.allowTheme
        width: 24; height: 24; radius: 12
        color: colorBlock.fallback
        border.width: colorBlock.current === "" ? 2 : 1
        border.color: colorBlock.current === "" ? "#ffffff" : root.w(0.25)
        Text {
          anchors.centerIn: parent
          text: "T"
          font.family: root.fontFamily
          font.pixelSize: Math.round(10.5 * root.textScale)
          font.weight: Font.DemiBold
          color: "#ffffff"
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.preferenceChanged(colorBlock.key, "") }
      }
      Repeater {
        model: colorBlock.swatches
        delegate: Rectangle {
          id: swatch
          required property string modelData
          readonly property bool selected: colorBlock.current === modelData.toLowerCase()
          width: 24; height: 24; radius: 12
          color: modelData
          border.width: selected ? 2 : 1
          border.color: selected ? "#ffffff" : root.w(0.25)
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.preferenceChanged(colorBlock.key, swatch.modelData) }
        }
      }
    }
    DockColorPicker {
      width: parent.width
      fontFamily: root.fontFamily
      textScale: root.textScale
      allowEmpty: colorBlock.allowTheme
      emptyHint: colorBlock.hint
      value: colorBlock.current !== "" ? colorBlock.current : colorBlock.fallback
      onPicked: function(hex) { root.preferenceChanged(colorBlock.key, hex) }
    }
  }

  // ---------- frame ----------

  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 46
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 18
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 3
      text: "Dock Settings"
      font.family: root.fontFamily
      font.pixelSize: Math.round(15 * root.textScale)
      font.weight: Font.DemiBold
      color: "#ffffff"
    }
    Rectangle {
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: 3
      width: 24
      height: 24
      radius: 8
      color: closeMouse.containsMouse ? root.w(0.12) : "transparent"
      Text {
        anchors.centerIn: parent
        text: "×"
        font.family: root.fontFamily
        font.pixelSize: Math.round(16 * root.textScale)
        color: closeMouse.containsMouse ? "#ffffff" : root.w(0.55)
      }
      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissed()
      }
    }
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: root.w(0.08) }
  }

  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    height: Math.min(Math.round(430 * root.ts), Math.max(200, root.maxHeight - header.height - footer.height))

    // Page list
    Item {
      id: sidebar
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.round(172 * root.ts)
      Rectangle { anchors.fill: parent; color: root.w(0.03) }
      Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: 1; color: root.w(0.08) }
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        spacing: 2
        Repeater {
          model: root.pages
          delegate: Rectangle {
            id: navRow
            required property var modelData
            readonly property bool selected: root.page === modelData.id
            width: parent.width
            height: Math.round(34 * root.textScale)
            radius: 8
            color: selected ? root.w(0.13) : (navMouse.containsMouse ? root.w(0.06) : "transparent")
            Text {
              id: navGlyph
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: navRow.modelData.glyph
              font.family: Style.font.family
              font.pixelSize: Math.round(15 * root.textScale)
              color: navRow.selected ? root.accent : root.w(0.55)
            }
            Text {
              anchors.left: navGlyph.right
              anchors.leftMargin: 9
              anchors.verticalCenter: parent.verticalCenter
              text: navRow.modelData.label
              font.family: root.fontFamily
              font.pixelSize: Math.round(13 * root.textScale)
              font.weight: navRow.selected ? Font.DemiBold : Font.Medium
              color: navRow.selected ? "#ffffff" : root.w(0.7)
            }
            MouseArea {
              id: navMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.page = navRow.modelData.id; flick.contentY = 0 }
            }
          }
        }
      }
    }

    // Page content
    Flickable {
      id: flick
      anchors.left: sidebar.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      contentHeight: pageColumn.implicitHeight + 24
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

      Column {
        id: pageColumn
        x: 20
        y: 6
        width: flick.width - 40
        spacing: 0
        readonly property real half: (width - 20) / 2

        // ---- Appearance ----
        Column {
          visible: root.page === "appearance"
          width: parent.width
          SectionTitle { title: "Size and motion" }
          Grid {
            columns: 2
            columnSpacing: 20
            rowSpacing: 0
            SliderRow { width: pageColumn.half; key: "iconSize"; label: "Icon size"; min: 24; max: 64; step: 1; fmt: "px" }
            SliderRow { width: pageColumn.half; key: "magnification"; label: "Magnification"; min: 1; max: 2; step: 0.05; fmt: "x" }
            SliderRow { width: pageColumn.half; key: "spacing"; label: "Spacing"; min: 2; max: 16; step: 1; fmt: "px" }
            SliderRow { width: pageColumn.half; key: "textScale"; label: "Text size"; min: 0.8; max: 1.6; step: 0.05; fmt: "%" }
          }
          SectionTitle { title: "Tiles and capsule" }
          Segmented {
            width: parent.width
            options: [{ id: "rounded", label: "Rounded" }, { id: "circle", label: "Circle" }, { id: "square", label: "Square" }, { id: "none", label: "None" }]
            current: root.settings.tileShape || "rounded"
            onChosen: function(id) { root.preferenceChanged("tileShape", id) }
          }
          ToggleRow {
            width: parent.width
            label: "Uniform icon size"
            sub: "Scale each icon's visible artwork to the same optical size"
            on: root.settings.uniformIcons === true
            onToggled: root.preferenceChanged("uniformIcons", !on)
          }
          Item { width: 1; height: 8 }
          SliderRow { width: parent.width; key: "opacity"; label: "Background opacity"; min: 0.2; max: 1; step: 0.02; fmt: "%" }
          ToggleRow {
            width: parent.width
            label: "Dock background"
            sub: "Off: only the tiles float, no capsule behind them"
            on: root.settings.showBackground !== false
            onToggled: root.preferenceChanged("showBackground", !on)
          }
        }

        // ---- Colors ----
        Column {
          visible: root.page === "colors"
          width: parent.width
          SectionTitle { title: "Source" }
          ToggleRow {
            width: parent.width
            label: "Follow Omarchy theme"
            sub: "Dock, drawer and accent take the current theme's colours. Turn off to choose your own."
            on: root.settings.themeColors !== false
            onToggled: root.preferenceChanged("themeColors", !on)
          }
          SectionTitle { visible: root.settings.themeColors === false; title: "Custom colours" }
          Grid {
            visible: root.settings.themeColors === false
            columns: 2
            columnSpacing: 20
            rowSpacing: 18
            ColorBlock { width: pageColumn.half; key: "dockColor"; label: "Dock"; swatches: root.colorPresets; fallback: "#000000" }
            ColorBlock { width: pageColumn.half; key: "drawerColor"; label: "Drawer"; swatches: root.colorPresets; fallback: "#000000" }
            ColorBlock { width: pageColumn.half; key: "accentColor"; label: "Accent"; swatches: root.accentPresets; allowTheme: true; hint: "theme accent, or #RRGGBB"; fallback: root.accent }
            ColorBlock { width: pageColumn.half; key: "previewColor"; label: "Preview window"; swatches: root.colorPresets; allowTheme: true; hint: "same as dock, or #RRGGBB"; fallback: root.glassColor }
          }
        }

        // ---- Windows ----
        Column {
          visible: root.page === "windows"
          width: parent.width
          SectionTitle { title: "Windows shown" }
          Segmented {
            width: parent.width
            options: [{ id: "all", label: "All" }, { id: "monitor", label: "This monitor" }, { id: "workspace", label: "Workspace" }]
            current: root.settings.windowScope || "all"
            onChosen: function(id) { root.preferenceChanged("windowScope", id) }
          }
          SectionTitle { title: "Hover previews" }
          ToggleRow {
            width: parent.width
            label: "Window previews"
            sub: "Live thumbnails in the window list when you hover a running app"
            on: root.settings.windowPreviews !== false
            onToggled: root.preferenceChanged("windowPreviews", !on)
          }
          Grid {
            columns: 2
            columnSpacing: 20
            SliderRow { width: pageColumn.half; key: "previewWidth"; label: "Preview width"; min: 120; max: 640; step: 10; fmt: "px" }
            SliderRow { width: pageColumn.half; key: "previewHeight"; label: "Preview height"; min: 80; max: 480; step: 10; fmt: "px" }
          }
        }

        // ---- Dock items ----
        Column {
          visible: root.page === "items"
          width: parent.width
          SectionTitle { title: "Groups" }
          ToggleRow {
            width: parent.width
            label: "Recent apps"
            sub: "A group with the last few apps you launched that are neither pinned nor running"
            on: root.settings.recentApps === true
            onToggled: root.preferenceChanged("recentApps", !on)
          }
          SliderRow { visible: root.settings.recentApps === true; width: pageColumn.half; key: "recentCount"; label: "Recent apps shown"; min: 1; max: 8; step: 1; fmt: "" }
          ToggleRow {
            width: parent.width
            label: "Badges"
            sub: "Unread counts apps report (Telegram, Thunderbird, Discord…) and a dot on windows asking for attention"
            on: root.settings.badges !== false
            onToggled: root.preferenceChanged("badges", !on)
          }
          ToggleRow {
            width: parent.width
            label: "Trash"
            sub: "A trash tile at the end of the dock: click opens it, right-click empties it"
            on: root.settings.showTrash === true
            onToggled: root.preferenceChanged("showTrash", !on)
          }
          ToggleRow {
            width: parent.width
            label: "Collapse control"
            sub: "An arrow that folds the dock down to the launcher"
            on: root.settings.collapsible === true
            onToggled: root.preferenceChanged("collapsible", !on)
          }

          SectionTitle { title: "Folders" }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Folder tiles open in your file manager; hovering shows the newest entries. Up to eight."
            font.family: root.fontFamily
            font.pixelSize: Math.round(11.5 * root.textScale)
            color: root.w(0.42)
            bottomPadding: 8
          }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: ["Home", "Downloads", "Documents", "Pictures", "Music", "Videos", "Desktop", "Projects"]
              delegate: Rectangle {
                id: chip
                required property string modelData
                readonly property string path: modelData === "Home" ? root.homeDir : root.homeDir + "/" + modelData
                readonly property bool added: root.folders().indexOf(path) >= 0
                width: chipLabel.implicitWidth + 20
                height: Math.round(26 * root.textScale)
                radius: 13
                color: added ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35) : (chipMouse.containsMouse ? root.w(0.14) : root.w(0.09))
                border.width: 1
                border.color: added ? root.accent : root.w(0.12)
                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: (chip.added ? "✓ " : "+ ") + chip.modelData
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(12 * root.textScale)
                  font.weight: Font.Medium
                  color: "#ffffff"
                }
                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: chip.added ? root.removeFolder(chip.path) : root.addFolder(chip.path)
                }
              }
            }
          }
          Item { width: 1; height: 10 }
          Row {
            width: parent.width
            spacing: 8
            TextBox {
              id: folderInput
              width: parent.width - addFolderButton.width - 8
              placeholder: "Any other path, e.g. ~/work"
              onAccepted: addFolderButton.clicked()
            }
            PillButton {
              id: addFolderButton
              label: "Add"
              primary: true
              active: folderInput.text.trim().length > 0
              height: folderInput.height
              onClicked: { if (root.addFolder(folderInput.text)) folderInput.text = "" }
            }
          }
          Item { width: 1; height: 8 }
          Repeater {
            model: root.folders()
            delegate: Rectangle {
              id: folderRow
              required property string modelData
              width: pageColumn.width
              height: Math.round(36 * root.textScale)
              radius: 8
              color: folderHover.hovered ? root.w(0.07) : "transparent"
              HoverHandler { id: folderHover }
              Text {
                id: folderGlyph
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "󰉋"
                font.family: Style.font.family
                font.pixelSize: Math.round(14 * root.textScale)
                color: root.accent
              }
              Text {
                anchors.left: folderGlyph.right
                anchors.leftMargin: 9
                anchors.right: removeFolderButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: folderRow.modelData.indexOf(root.homeDir) === 0 ? "~" + folderRow.modelData.substring(root.homeDir.length) : folderRow.modelData
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Math.round(12.5 * root.textScale)
                color: root.w(0.88)
              }
              Rectangle {
                id: removeFolderButton
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(26 * root.textScale)
                height: width
                radius: 7
                color: removeMouse.containsMouse ? Qt.rgba(1, 0.35, 0.35, 0.28) : "transparent"
                Text {
                  anchors.centerIn: parent
                  text: "×"
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(15 * root.textScale)
                  color: removeMouse.containsMouse ? "#ffffff" : root.w(0.5)
                }
                MouseArea {
                  id: removeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.removeFolder(folderRow.modelData)
                }
              }
            }
          }
        }

        // ---- Behavior ----
        Column {
          visible: root.page === "behavior"
          width: parent.width
          SectionTitle { title: "Visibility" }
          ToggleRow {
            width: parent.width
            label: "Auto-hide"
            sub: "Slide off-screen; reveal by touching the bottom edge"
            on: root.isAutoHide
            onToggled: root.autoHideToggled()
          }
          ToggleRow {
            width: parent.width
            label: "Reserve space"
            sub: "Tiled windows stop above the dock instead of running underneath it"
            on: root.isReserveSpace
            onToggled: root.reserveSpaceToggled()
          }
          SectionTitle { title: "Keyboard" }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Bind the drawer in ~/.config/hypr/bindings.lua:\no.bind(\"SUPER + A\", \"App drawer\", \"omarchy-shell magnify-dock drawer\")"
            font.family: root.fontFamily
            font.pixelSize: Math.round(12 * root.textScale)
            lineHeight: 1.25
            color: root.w(0.5)
          }
        }

        // ---- Presets ----
        Column {
          visible: root.page === "presets"
          width: parent.width
          SectionTitle { title: "Save current setup" }
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "A preset holds every setting, auto-hide, reserve space, folders and your pinned apps. Saving under an existing name replaces it."
            font.family: root.fontFamily
            font.pixelSize: Math.round(11.5 * root.textScale)
            color: root.w(0.42)
            bottomPadding: 10
          }
          Row {
            width: parent.width
            spacing: 8
            TextBox {
              id: nameInput
              width: parent.width - savePresetButton.width - 8
              placeholder: "Preset name"
              onAccepted: savePresetButton.clicked()
            }
            PillButton {
              id: savePresetButton
              label: "Save"
              primary: true
              active: nameInput.text.trim().length > 0
              height: nameInput.height
              onClicked: { root.presetSaved(nameInput.text.trim()); nameInput.text = "" }
            }
          }
          SectionTitle { title: "Saved presets" }
          Text {
            visible: root.presets.length === 0
            text: "No presets saved yet."
            font.family: root.fontFamily
            font.pixelSize: Math.round(12 * root.textScale)
            color: root.w(0.35)
          }
          Repeater {
            model: root.presets
            delegate: Rectangle {
              id: presetRow
              required property var modelData
              width: pageColumn.width
              height: Math.round(40 * root.textScale)
              radius: 9
              color: presetHover.hovered ? root.w(0.07) : "transparent"
              HoverHandler { id: presetHover }
              Column {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: applyButton.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  width: parent.width
                  text: presetRow.modelData.name
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(13 * root.textScale)
                  font.weight: Font.Medium
                  color: root.w(0.88)
                }
                Text {
                  width: parent.width
                  text: presetRow.modelData.savedAt ? "Saved " + String(presetRow.modelData.savedAt).substring(0, 10) : ""
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(11 * root.textScale)
                  color: root.w(0.4)
                }
              }
              PillButton {
                id: applyButton
                anchors.right: deleteButton.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                label: "Apply"
                height: Math.round(26 * root.textScale)
                onClicked: root.presetApplied(presetRow.modelData.name)
              }
              Rectangle {
                id: deleteButton
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(26 * root.textScale)
                height: width
                radius: 7
                color: deleteMouse.containsMouse ? Qt.rgba(1, 0.35, 0.35, 0.28) : "transparent"
                Text {
                  anchors.centerIn: parent
                  text: "×"
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(15 * root.textScale)
                  color: deleteMouse.containsMouse ? "#ffffff" : root.w(0.5)
                }
                MouseArea {
                  id: deleteMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.presetDeleted(presetRow.modelData.name)
                }
              }
            }
          }
        }
      }
    }
  }

  Item {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: body.bottom
    height: footerText.implicitHeight + 18
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: root.w(0.08) }
    Text {
      id: footerText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: 18
      rightPadding: 18
      wrapMode: Text.WordWrap
      text: "Changes apply live and save to ~/.config/omarchy/dock-pinned-macos.json. Presets live in dock-presets.json."
      font.family: root.fontFamily
      font.pixelSize: Math.round(11 * root.textScale)
      color: root.w(0.35)
    }
  }
}
