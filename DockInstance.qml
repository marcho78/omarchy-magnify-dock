import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQml.Models
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

Item {
  id: root

  // Injected by Omarchy Shell
  property var shell: null
  property var manifest: null
  property var dockScreen: null
  property var appLibrary: shell ? shell.appLibrary : null

  // Geometry from the Magnify Dock design: 12px rail inset, rail height of
  // icon + 26, 17px dividers, magnification radius of 3.4 icon widths.
  property var preferences: DockModel.normalizeSettings(null)
  property real baseIconSize: root.iconPixelSize + 8
  property real iconPixelSize: root.preferences.iconSize
  property real maxMagnification: root.preferences.magnification
  property real magnifyRadius: root.iconPixelSize * 3.4
  property real dockPadding: DockModel.railPadding
  property real separatorWidth: DockModel.separatorWidth
  property real itemSpacing: root.preferences.spacing
  property real capsuleHeight: root.iconPixelSize + 26
  property real dockEdgeMargin: 14
  property real layoutExpansionRatio: 0.82
  property int magnificationDuration: 90
  readonly property real textScale: root.preferences.textScale || 1
  // The opacity slider is mapped through a square-root curve so the low end
  // still leaves the surfaces readable: 100% is solid, 50% is about 0.71
  // alpha, 20% is about 0.45. Fully see-through is deliberately not reachable.
  readonly property real surfaceAlpha: Math.sqrt(Math.max(0, Math.min(1, root.preferences.opacity)))
  readonly property string tileShape: root.preferences.tileShape || "rounded"
  readonly property real tileRadiusRatio: DockModel.tileRadiusRatio(root.tileShape)
  readonly property bool uniformIcons: root.preferences.uniformIcons === true
  readonly property bool themeColors: root.preferences.themeColors !== false
  readonly property color dockColor: root.themeColors ? Color.background : (root.preferences.dockColor || "#12141a")
  readonly property color drawerColor: root.themeColors ? Qt.darker(Color.background, 1.15) : (root.preferences.drawerColor || "#0a0c11")
  // Popups sit a touch lighter than the capsule, as in the design (24,26,33 vs 18,20,26).
  readonly property color glassColor: Qt.lighter(root.dockColor, 1.25)
  readonly property color previewColor: (!root.themeColors && root.preferences.previewColor) ? root.preferences.previewColor : root.glassColor
  readonly property color accent: (!root.themeColors && root.preferences.accentColor) ? root.preferences.accentColor : Color.accent
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  // Instrument Sans (OFL) ships with the plugin; fall back to the shell font.
  FontLoader { id: dockFont; source: Qt.resolvedUrl("fonts/InstrumentSans.ttf") }
  readonly property string fontFamily: dockFont.status === FontLoader.Ready ? dockFont.name : Style.font.family

  readonly property bool environmentReduceMotion: {
    var value = String(Quickshell.env("OMARCHY_REDUCE_MOTION") || "").toLowerCase()
    return value === "1" || value === "true" || value === "yes"
  }
  property bool systemReduceMotion: false
  readonly property bool reduceMotion: root.environmentReduceMotion || root.systemReduceMotion

  // Always visible macOS Mode
  property bool autoHide: false
  property bool reserveSpace: true
  // Folded down to the launcher and the collapse arrow (persisted).
  property bool collapsed: false
  readonly property bool showBackground: root.preferences.showBackground !== false
  readonly property bool collapsible: root.preferences.collapsible === true
  readonly property bool folded: root.collapsed && root.collapsible
  // Badges (Unity LauncherEntry counts keyed by app id) and urgent windows.
  readonly property bool badgesOn: root.preferences.badges !== false
  property var badgeMap: ({})
  property var urgentWindows: []
  function badgeCountFor(item, map) {
    var b = DockModel.badgeForItem(map, item)
    return b && b.visible && b.count > 0 ? b.count : 0
  }
  // Trash tile state and the folder stack popup.
  readonly property string homeDir: Quickshell.env("HOME")
  property bool trashFull: false
  property bool folderOpen: false
  property string folderPath: ""
  property string folderTitle: ""
  property string pendingFolderPath: ""
  property string pendingFolderTitle: ""
  property real folderAnchorX: 0
  property real folderAnchorY: 0
  property string settingsPage: "appearance"
  onSettingsPageChanged: if (settingsPanel.page !== root.settingsPage) settingsPanel.page = root.settingsPage
  function toggleCollapsed() {
    root.collapsed = !root.collapsed
    root.saveConfig()
    root.rebuildDock()
  }
  property bool isDockHovered: false
  property bool edgeHovered: false
  property bool dockPresented: true
  property real hoverCursorX: -1
  property bool settingsOpen: false
  property bool pickerOpen: false
  property string pickerKey: ""
  property string pendingPickerKey: ""
  property string pickerTitle: ""
  property var windowMetadata: []
  property var windowRows: []
  property real pickerAnchorX: 0
  property real pickerAnchorY: 0
  readonly property var hyprMonitor: root.dockScreen ? Hyprland.monitorFor(root.dockScreen) : null
  readonly property var activeWorkspace: root.hyprMonitor ? root.hyprMonitor.activeWorkspace : null
  readonly property bool popupOpen: root.contextMenuOpen || root.pickerOpen || root.settingsOpen || appDrawer.open || root.folderOpen

  onActiveWorkspaceChanged: Qt.callLater(root.rebuildDock)
  onHyprMonitorChanged: Qt.callLater(root.rebuildDock)

  function changePreference(key, value) {
    var next = Object.assign({}, root.preferences)
    next[key] = value
    root.preferences = DockModel.normalizeSettings(next)
    root.rebuildDock()
    settingsSaveTimer.restart()
  }

  function openSettings() {
    root.closeContextMenu()
    root.clearTooltip()
    root.closePicker()
    root.settingsOpen = true
    root.revealDock()
  }

  function closeSettings() {
    root.settingsOpen = false
    root.scheduleDockHide()
  }

  function requestAppTooltip(item, target) {
    if (root.settingsOpen || root.contextMenuOpen || root.draggingPinnedIndex >= 0) return
    if (!item || !item.windows || item.windows.length === 0) {
      root.closePicker()
      root.requestTooltip(target, item ? item.name : "")
      return
    }
    root.clearTooltip()
    pickerHideTimer.stop()
    var point = dockPanel.contentItem.mapFromItem(target,
      target.width / 2 + Number(target.animatedOffsetX || 0), -8)
    root.pickerAnchorX = point.x
    root.pickerAnchorY = point.y
    root.pendingPickerKey = item.key
    if (root.pickerOpen) root.showPicker()
    else pickerShowTimer.restart()
  }

  function releaseAppTooltip(target) {
    root.releaseTooltip(target)
    pickerShowTimer.stop()
    root.pendingPickerKey = ""
    if (root.pickerOpen) pickerHideTimer.restart()
  }

  function showPicker() {
    root.pickerKey = root.pendingPickerKey
    root.pendingPickerKey = ""
    root.refreshPicker()
    root.pickerOpen = root.windowRows.length > 0
    if (root.pickerOpen) root.revealDock()
  }

  function refreshPicker() {
    var items = root.dockData.pinned.concat(root.dockData.unpinned)
    var item = items.find(function(value) { return value.key === root.pickerKey })
    root.pickerTitle = item ? item.name : ""
    root.windowRows = DockModel.pickerRows(item, root.windowMetadata)
    if (root.windowRows.length === 0) root.closePicker()
  }

  function closePicker() {
    pickerShowTimer.stop()
    pickerHideTimer.stop()
    root.pendingPickerKey = ""
    root.pickerKey = ""
    root.pickerOpen = false
    root.scheduleDockHide()
  }

  Timer { id: pickerShowTimer; interval: 380; onTriggered: root.showPicker() }
  Timer {
    id: pickerHideTimer
    interval: 320
    onTriggered: if (!windowPicker.containsPointer) root.closePicker()
  }
  Timer { id: settingsSaveTimer; interval: 300; onTriggered: root.saveConfig() }


  // Fixed invariant baseline geometry to eliminate jitter/shaking
  property var baselineGeometry: null

  // Magnification scales state
  property real launcherScale: 1.0
  property real animatedLauncherScale: root.launcherScale
  property real launcherOffsetX: 0
  property real animatedLauncherOffsetX: root.launcherOffsetX
  property var pinnedScales: []
  property var unpinnedScales: []
  property var recentScales: []
  property var pinnedOffsets: []
  property var unpinnedOffsets: []
  property var recentOffsets: []
  property real extraCapsuleWidth: 0
  property var extraScales: []
  property var extraOffsets: []
  property real animatedExtraCapsuleWidth: root.extraCapsuleWidth

  // Track fast pointer updates without restarting a discrete animation for
  // every event. This keeps the velocity continuous while entering, moving
  // across, and leaving the dock.
  Behavior on animatedLauncherScale {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  Behavior on animatedLauncherOffsetX {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  Behavior on animatedExtraCapsuleWidth {
    SmoothedAnimation {
      velocity: -1
      duration: root.reduceMotion ? 0 : root.magnificationDuration
      maximumEasingTime: root.reduceMotion ? 0 : 28
    }
  }

  // Dock items and pinned apps state
  // null means no saved preference; [] means explicitly no pinned apps.
  property var customPinnedApps: null
  property var dockData: ({ pinned: [], unpinned: [], recent: [], totalItems: 0 })
  // Recently launched app ids, most recent first (persisted in the config file).
  property var recentIds: []

  function noteLaunch(item) {
    if (!item || !item.id) return
    root.recentIds = DockModel.pushRecent(root.recentIds, String(item.id), 12)
    root.saveConfig()
    root.rebuildDock()
  }

  // Drag & drop reorder state
  property int draggingPinnedIndex: -1
  property int dragTargetIndex: -1
  property real dragGrabOffsetX: 0
  property real dragGrabOffsetY: 0
  property real dragVisualX: 0
  property real dragVisualY: 0
  property bool isDropSettling: false
  property real dropSettleStartX: 0
  property real dropSettleStartY: 0
  property real dropSettleTargetX: 0
  property real dropSettleProgress: 0.0

  NumberAnimation {
    id: dropSettleAnimation
    target: root
    property: "dropSettleProgress"
    from: 0.0
    to: 1.0
    duration: root.reduceMotion ? 0 : 180
    easing.type: Easing.OutCubic

    onRunningChanged: {
      if (!running && root.isDropSettling) {
        root.finishDropReorder()
      }
    }
  }

  onDropSettleProgressChanged: {
    if (root.isDropSettling) {
      root.dragVisualX = root.dropSettleStartX + (root.dropSettleTargetX - root.dropSettleStartX) * root.dropSettleProgress
      root.dragVisualY = root.dropSettleStartY * (1.0 - root.dropSettleProgress)
    }
  }

  // Hover Tooltip State
  property string tooltipText: ""
  property bool tooltipVisible: false
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string pendingTooltipText: ""

  // Context menu state is held by the dock so auto-hide remains suspended
  // while the menu is open.
  property bool contextMenuOpen: false
  property var contextTarget: null
  property var contextAnchor: null
  property double contextMenuOpenedAt: 0

  function requestTooltip(target, text) {
    if (root.draggingPinnedIndex >= 0 || root.settingsOpen || root.contextMenuOpen) return
    root.closePicker()
    tooltipHideTimer.stop()
    root.pendingTooltipTarget = target
    root.pendingTooltipText = String(text || "")

    if (root.tooltipVisible) {
      root.tooltipTarget = target
      root.tooltipText = root.pendingTooltipText
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
      Qt.callLater(function() { tooltipWindow.anchor.updateAnchor() })
      return
    }
    tooltipShowTimer.restart()
  }

  function releaseTooltip(target) {
    if (root.pendingTooltipTarget === target) {
      tooltipShowTimer.stop()
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
    }
    if (root.tooltipTarget === target) tooltipHideTimer.restart()
  }

  function clearTooltip() {
    tooltipShowTimer.stop()
    tooltipHideTimer.stop()
    root.tooltipVisible = false
    root.tooltipTarget = null
    root.pendingTooltipTarget = null
    root.pendingTooltipText = ""
  }

  function revealDock() {
    edgeRevealTimer.stop()
    hideDockTimer.stop()
    root.dockPresented = true
  }

  function scheduleDockHide() {
    // The edge is only a reveal trigger. Keeping it in this condition can
    // leave the dock permanently open after the first reveal because a
    // compositor does not always emit an exit while the input mask changes.
    if (root.autoHide && !root.isDockHovered && !root.popupOpen) {
      hideDockTimer.restart()
    }
  }

  // ---- Folder and trash tiles ----
  // Every external program is started by absolute path with an argv list;
  // nothing here goes through a shell or the ambient PATH.
  function openExtra(item) {
    if (!item || !item.kind) return
    Quickshell.execDetached(["/usr/bin/xdg-open", item.kind === "trash" ? "trash:///" : String(item.path)])
  }

  function openPath(path) {
    if (!path) return
    Quickshell.execDetached(["/usr/bin/xdg-open", String(path)])
  }

  function removeFolder(path) {
    var list = (root.preferences.folders || []).filter(function(f) { return f !== path })
    root.changePreference("folders", list)
  }

  function emptyTrash() {
    Quickshell.execDetached(["/usr/bin/gio", "trash", "--empty"])
    trashRecheck.restart()
  }
  Timer { id: trashRecheck; interval: 1200; onTriggered: trashProbe.running = true }

  function extraMenuEntries(item) {
    if (!item || !item.kind) return null
    if (item.kind === "trash") {
      return [{ label: "Open Trash", action: "open" }, { label: "Empty Trash", action: "empty" }]
    }
    return [{ label: "Open Folder", action: "open" }, { label: "Remove from Dock", action: "remove" }]
  }

  function handleExtraAction(action, item) {
    if (!item) return
    if (action === "open") root.openExtra(item)
    else if (action === "empty") root.emptyTrash()
    else if (action === "remove" && item.kind === "folder") root.removeFolder(item.path)
  }

  function requestExtraHover(item, target) {
    if (root.settingsOpen || root.contextMenuOpen || root.draggingPinnedIndex >= 0) return
    if (!item || item.kind !== "folder") {
      root.closeFolderPopup()
      root.requestTooltip(target, item ? item.name : "")
      return
    }
    root.clearTooltip()
    folderHideTimer.stop()
    var point = dockPanel.contentItem.mapFromItem(target,
      target.width / 2 + Number(target.animatedOffsetX || 0), -8)
    root.folderAnchorX = point.x
    root.folderAnchorY = point.y
    root.pendingFolderPath = item.path
    root.pendingFolderTitle = item.name
    if (root.folderOpen) root.showFolderPopup()
    else folderShowTimer.restart()
  }

  function releaseExtraHover(target) {
    root.releaseTooltip(target)
    folderShowTimer.stop()
    root.pendingFolderPath = ""
    if (root.folderOpen) folderHideTimer.restart()
  }

  function showFolderPopup() {
    if (!root.pendingFolderPath) return
    root.folderPath = root.pendingFolderPath
    root.folderTitle = root.pendingFolderTitle
    root.pendingFolderPath = ""
    root.folderOpen = true
    root.revealDock()
  }

  function closeFolderPopup() {
    folderShowTimer.stop()
    folderHideTimer.stop()
    root.pendingFolderPath = ""
    root.folderOpen = false
    root.scheduleDockHide()
  }

  Timer { id: folderShowTimer; interval: 380; onTriggered: root.showFolderPopup() }
  Timer {
    id: folderHideTimer
    interval: 320
    onTriggered: if (!folderPopup.containsPointer) root.closeFolderPopup()
  }

  function openContextMenu(item, target) {
    root.closeFolderPopup()
    root.closePicker()
    root.clearTooltip()
    // Recreate the popup lifecycle for every request. Layer-shell geometry can
    // change after toggling reserve space; reusing an already-true visible
    // state may otherwise leave the compositor with a stale input surface.
    root.contextMenuOpen = false
    root.contextTarget = item
    root.contextAnchor = target
    root.contextMenuOpenedAt = Date.now()
    root.revealDock()
    Qt.callLater(function() {
      if (root.contextAnchor !== target) return
      root.contextMenuOpen = true
      Qt.callLater(function() {
        if (contextWindow && contextWindow.anchor && typeof contextWindow.anchor.updateAnchor === "function") {
          contextWindow.anchor.updateAnchor()
        }
      })
    })
  }

  function closeContextMenu() {
    root.contextMenuOpen = false
    root.contextTarget = null
    root.contextAnchor = null
    root.scheduleDockHide()
  }

  onAutoHideChanged: {
    if (root.autoHide) root.scheduleDockHide()
    else root.revealDock()
  }

  Timer {
    id: tooltipShowTimer
    interval: 380
    onTriggered: {
      if (!root.pendingTooltipTarget || root.pendingTooltipText === "") return
      root.tooltipTarget = root.pendingTooltipTarget
      root.tooltipText = root.pendingTooltipText
      root.pendingTooltipTarget = null
      root.pendingTooltipText = ""
      root.tooltipVisible = true
    }
  }

  Timer {
    id: tooltipHideTimer
    interval: 70
    onTriggered: root.clearTooltip()
  }

  Timer {
    id: edgeRevealTimer
    interval: root.preferences.revealDelay
    onTriggered: root.revealDock()
  }

  Timer {
    id: hideDockTimer
    interval: root.preferences.hideDelay
    onTriggered: {
      if (root.autoHide && !root.isDockHovered && !root.edgeHovered && !root.popupOpen) {
        root.clearTooltip()
        root.hoverCursorX = -1
        root.updateMagnification()
        root.dockPresented = false
      }
    }
  }

  // A popup normally closes through one of its actions or when the pointer
  // leaves it. This watchdog also recovers from a lost popup/input event so a
  // stale contextMenuOpen value can never disable auto-hide indefinitely.
  Timer {
    id: contextMenuDismissTimer
    interval: 180
    repeat: true
    running: root.contextMenuOpen
    onTriggered: {
      var graceElapsed = Date.now() - root.contextMenuOpenedAt > 900
      if (graceElapsed && !root.isDockHovered && !dockContextMenu.containsPointer) {
        root.closeContextMenu()
      }
    }
  }

  Process {
    id: reducedMotionProbe
    running: true
    command: ["/usr/bin/gsettings", "get", "org.gnome.desktop.interface", "enable-animations"]
    stdout: SplitParser {
      onRead: function(line) {
        root.systemReduceMotion = String(line || "").trim() === "false"
      }
    }
  }

  // Muted Apps State Persistence & Audio Control
  readonly property string dockAudioScript: root.pluginDir + "/dock-audio.py"
  property var mutedAppsMap: ({})

  // ---- State files: every read and write goes through dock-state.py, which
  // opens $HOME/.config/omarchy component by component without following
  // symlinks, verifies owner/type/mode on the descriptors, caps sizes and
  // validates the shape. The shell never reads the files by pathname. ----
  readonly property string dockStateScript: root.pluginDir + "/dock-state.py"
  readonly property int stateReadBudget: 1048576
  property var stateReadQueue: []

  function requestState(which) {
    if (root.stateReadQueue.indexOf(which) < 0) root.stateReadQueue.push(which)
    root.pumpStateReads()
  }
  function pumpStateReads() {
    if (stateReader.running || root.stateReadQueue.length === 0) return
    stateReader.which = root.stateReadQueue.shift()
    stateReader.buf = ""
    stateReader.overflowed = false
    stateReader.command = ["/usr/bin/python3", "-I", root.dockStateScript, "read", stateReader.which]
    stateReader.running = true
  }
  function applyState(which, text) {
    if (which === "config") root.loadConfig(text)
    else if (which === "presets") root.loadPresets(text)
    else if (which === "muted") root.loadMutedApps(text)
  }
  Process {
    id: stateReader
    property string which: ""
    property string buf: ""
    property bool overflowed: false
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (stateReader.overflowed) return
        if (stateReader.buf.length + String(chunk).length > root.stateReadBudget) {
          stateReader.overflowed = true
          console.warn("[magnify-dock] state read exceeded budget; discarding")
          stateReader.running = false
          return
        }
        stateReader.buf += String(chunk)
      }
    }
    stderr: SplitParser { onRead: function(line) { console.warn("[magnify-dock] dock-state: " + String(line).slice(0, 300)) } }
    onExited: function(code) {
      var which = stateReader.which
      var text = (!stateReader.overflowed && code === 0) ? stateReader.buf : ""
      stateReader.buf = ""
      root.applyState(which, text)
      root.pumpStateReads()
    }
  }

  property var stateWriteQueue: ({})
  function writeState(which, obj) {
    var q = Object.assign({}, root.stateWriteQueue)
    q[which] = JSON.stringify(obj)
    root.stateWriteQueue = q
    root.pumpStateWrites()
  }
  function pumpStateWrites() {
    if (stateWriter.running) return
    var keys = Object.keys(root.stateWriteQueue)
    if (keys.length === 0) return
    var which = keys[0]
    stateWriter.payload = root.stateWriteQueue[which]
    var q = Object.assign({}, root.stateWriteQueue)
    delete q[which]
    root.stateWriteQueue = q
    stateWriter.command = ["/usr/bin/python3", "-I", root.dockStateScript, "write", which]
    stateWriter.running = true
  }
  Process {
    id: stateWriter
    property string payload: ""
    stdinEnabled: true
    onStarted: { stateWriter.write(stateWriter.payload + "\n"); stateWriter.payload = "" }
    stderr: SplitParser { onRead: function(line) { console.warn("[magnify-dock] dock-state write: " + String(line).slice(0, 300)) } }
    onExited: root.pumpStateWrites()
  }

  // One inotify watcher on the verified directory; each line names a file to re-read.
  Process {
    id: stateWatcher
    running: true
    command: ["/usr/bin/python3", "-I", root.dockStateScript, "watch"]
    stdout: SplitParser {
      onRead: function(line) {
        var which = String(line).trim()
        if (which.length > 16) return
        if (which === "config") configReload.restart()
        else if (which === "presets") presetsReload.restart()
        else if (which === "muted") mutedReload.restart()
      }
    }
    onExited: watcherRestart.restart()
  }
  Timer { id: watcherRestart; interval: 5000; onTriggered: stateWatcher.running = true }
  Timer { id: configReload; interval: 150; onTriggered: root.requestState("config") }
  Timer { id: presetsReload; interval: 150; onTriggered: root.requestState("presets") }
  Timer { id: mutedReload; interval: 150; onTriggered: root.requestState("muted") }

  function loadMutedApps(rawText) {
    try {
      if (rawText && rawText.trim().length > 0 && rawText.trim() !== "null") {
        var parsed = JSON.parse(rawText)
        if (parsed && typeof parsed === "object") {
          root.mutedAppsMap = parsed
          return
        }
      }
    } catch (e) {}
    root.mutedAppsMap = ({})
  }

  function isAppAudioMuted(item) {
    if (!item) return false
    var map = root.mutedAppsMap || {}
    var id = String(item.id || "")
    var name = String(item.name || "")
    if (id && map[id] === true) return true
    if (name && map[name] === true) return true
    for (var k in map) {
      if (!map[k]) continue
      if (id && (k === id || DockModel.matchApp(k, id))) return true
      if (name && (k === name || DockModel.normalizeId(k) === DockModel.normalizeId(name))) return true
    }
    return false
  }

  function toggleAppAudio(item) {
    if (!item) return
    var appId = String(item.id || "")
    var appName = String(item.name || "")
    // Update the intent map before the script runs so the sync timer stops
    // immediately on unmute; otherwise it can re-mute the stream in the gap
    // before the persisted file is reloaded.
    var next = Object.assign({}, root.mutedAppsMap)
    if (root.isAppAudioMuted(item)) {
      if (appId) delete next[appId]
      if (appName) delete next[appName]
    } else {
      if (appId) next[appId] = true
      if (appName) next[appName] = true
    }
    root.mutedAppsMap = next
    Quickshell.execDetached(["/usr/bin/python3", "-I", root.dockAudioScript, "toggle", String(appId || ""), String(appName || "")])
  }

  // A saved mute must also cover streams that appear after the menu action,
  // otherwise muting a silent app (or one that restarts playback) has no effect.
  Timer {
    id: audioSyncTimer
    interval: 1500
    repeat: true
    running: Object.keys(root.mutedAppsMap).length > 0
    onTriggered: audioSyncProc.running = true
  }

  Process {
    id: audioSyncProc
    command: ["/usr/bin/python3", "-I", root.dockAudioScript, "sync"]
  }

  // Badge relay: apps announce unread counts on the session bus through
  // com.canonical.Unity.LauncherEntry; the script prints one JSON line each.
  Process {
    id: badgeRelay
    running: root.badgesOn
    command: ["/usr/bin/python3", "-I", root.pluginDir + "/dock-badges.py"]
    property int linesThisMinute: 0
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).length > 2048) return
        if (++badgeRelay.linesThisMinute > 600) {
          console.warn("[magnify-dock] badge relay is flooding; stopping it for a minute")
          badgeRelay.running = false
          return
        }
        try {
          var msg = JSON.parse(String(line))
          if (!msg || typeof msg.app !== "string" || msg.app.length > 256) return
          var next = Object.assign({}, root.badgeMap)
          if (msg.visible && msg.count > 0) next[msg.app] = msg
          else if (msg.urgent) next[msg.app] = msg
          else delete next[msg.app]
          root.badgeMap = next
        } catch (e) {}
      }
    }
    onRunningChanged: if (!running) root.badgeMap = ({})
    onExited: if (root.badgesOn) badgeRestart.restart()
  }
  Timer { id: badgeRestart; interval: 60000; onTriggered: if (root.badgesOn && !badgeRelay.running) badgeRelay.running = true }
  Timer { interval: 60000; repeat: true; running: true; onTriggered: badgeRelay.linesThisMinute = 0 }

  // Trash tile: full or empty, polled cheaply and re-checked when the dock is hovered.
  Process {
    id: trashProbe
    property bool sawEntry: false
    command: ["/usr/bin/find", root.homeDir + "/.local/share/Trash/files", "-mindepth", "1", "-maxdepth", "1", "-print", "-quit"]
    onStarted: sawEntry = false
    stdout: SplitParser { onRead: function(line) { if (String(line).length > 0) trashProbe.sawEntry = true } }
    onExited: {
      var full = trashProbe.sawEntry
      if (full !== root.trashFull) { root.trashFull = full; root.rebuildDock() }
    }
  }
  Timer {
    interval: 20000
    repeat: true
    running: root.preferences.showTrash === true
    triggeredOnStart: true
    onTriggered: trashProbe.running = true
  }
  onIsDockHoveredChanged: if (isDockHovered && root.preferences.showTrash === true) trashProbe.running = true

  // Settings File Persistence


  function loadConfig(rawText) {
    try {
      if (rawText && rawText.trim().length > 0 && rawText.trim() !== "null") {
        var parsed = JSON.parse(rawText)
        if (parsed.settings && !settingsSaveTimer.running) {
          root.preferences = DockModel.normalizeSettings(parsed.settings)
        }
        if (Array.isArray(parsed.pinned)) {
          root.customPinnedApps = parsed.pinned
        }
        if (Array.isArray(parsed.recent)) {
          root.recentIds = parsed.recent.filter(function(x) { return typeof x === "string" })
        }
        if (typeof parsed.autoHide === "boolean") {
          root.autoHide = parsed.autoHide
        }
        if (typeof parsed.reserveSpace === "boolean") {
          root.reserveSpace = parsed.reserveSpace
        }
        if (typeof parsed.collapsed === "boolean") {
          root.collapsed = parsed.collapsed
        }
      }
    } catch (e) {}
    root.rebuildDock()
  }

  function saveConfig() {
    var payload = {
      version: 1,
      settings: root.preferences,
      autoHide: root.autoHide,
      reserveSpace: root.reserveSpace,
      collapsed: root.collapsed,
      pinned: Array.isArray(root.customPinnedApps) ? root.customPinnedApps : DockModel.defaultPinnedApps,
      recent: root.recentIds
    }
    // Atomic write through Quickshell: a random exclusive temp file next to
    // the target, renamed over it. No shell, no predictable temp name.
    root.writeState("config", payload)
  }

  // Presets: named snapshots of the whole configuration (settings, auto-hide,
  // reserve space, pinned apps) kept in their own file so the live config
  // stays small and a preset survives edits to it.
  property var presets: []


  function loadPresets(rawText) {
    var list = []
    try {
      if (rawText && rawText.trim().length > 0 && rawText.trim() !== "null") {
        var parsed = JSON.parse(rawText)
        var arr = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.presets) ? parsed.presets : [])
        for (var i = 0; i < arr.length; i++) {
          var p = arr[i]
          if (p && typeof p.name === "string" && p.name.trim() !== "" && p.settings && typeof p.settings === "object") list.push(p)
        }
      }
    } catch (e) {}
    root.presets = list
  }

  function writePresets(list) {
    root.presets = list
    root.writeState("presets", { version: 1, presets: list })
  }

  function findPreset(name) {
    var key = String(name || "").trim().toLowerCase()
    for (var i = 0; i < root.presets.length; i++) {
      if (String(root.presets[i].name).trim().toLowerCase() === key) return i
    }
    return -1
  }

  function savePreset(name) {
    var clean = String(name || "").trim()
    if (clean === "") return false
    var entry = {
      name: clean,
      savedAt: new Date().toISOString(),
      settings: root.preferences,
      autoHide: root.autoHide,
      reserveSpace: root.reserveSpace,
      pinned: Array.isArray(root.customPinnedApps) ? root.customPinnedApps : DockModel.defaultPinnedApps
    }
    var list = root.presets.slice()
    var idx = root.findPreset(clean)
    if (idx >= 0) list[idx] = entry; else list.push(entry)
    root.writePresets(list)
    return true
  }

  function applyPreset(name) {
    var idx = root.findPreset(name)
    if (idx < 0) return false
    var p = root.presets[idx]
    settingsSaveTimer.stop()
    root.preferences = DockModel.normalizeSettings(p.settings)
    if (typeof p.autoHide === "boolean") root.autoHide = p.autoHide
    if (typeof p.reserveSpace === "boolean") root.reserveSpace = p.reserveSpace
    if (Array.isArray(p.pinned)) root.customPinnedApps = p.pinned
    root.saveConfig()
    root.rebuildDock()
    return true
  }

  function deletePreset(name) {
    var idx = root.findPreset(name)
    if (idx < 0) return false
    var list = root.presets.slice()
    list.splice(idx, 1)
    root.writePresets(list)
    return true
  }

  function togglePinApp(appId) {
    if (!appId) return
    var currentList = Array.isArray(root.customPinnedApps)
      ? root.customPinnedApps
      : DockModel.defaultPinnedApps
    var list = currentList.slice()
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      var p = typeof list[i] === "string" ? list[i] : (list[i].id || "")
      if (p === appId || DockModel.matchApp(p, appId)) {
        idx = i
        break
      }
    }

    if (idx >= 0) {
      list.splice(idx, 1)
    } else {
      list.push(appId)
    }
    root.customPinnedApps = list
    root.saveConfig()
    root.rebuildDock()
  }

  // Every window event asks for a rebuild; several arrive together (title,
  // activation, handle changes). Coalesce them so the rail's tiles are
  // recreated at most once per burst.
  function rebuildDock() { rebuildTimer.restart() }
  Timer {
    id: rebuildTimer
    interval: 40
    onTriggered: root.rebuildDockNow()
  }

  function rebuildDockNow() {
    var toplevels = []
    try {
      toplevels = ToplevelManager.toplevels.values
    } catch (e) {
      toplevels = []
    }

    root.windowMetadata = DockModel.toArray(Hyprland.toplevels.values).map(function(win) {
      return {
        window: win.wayland,
        monitorName: win.monitor ? win.monitor.name : "",
        workspaceId: win.workspace ? win.workspace.id : null,
        workspaceName: win.workspace ? win.workspace.name : ""
      }
    })
    var visibleWindows = DockModel.filterWindows(toplevels, root.windowMetadata,
      root.preferences.windowScope, root.dockScreen ? root.dockScreen.name : "",
      root.activeWorkspace ? root.activeWorkspace.id : null)
    var data = DockModel.buildDockItems(
      visibleWindows,
      DesktopEntries,
      root.appLibrary,
      Quickshell,
      root.customPinnedApps
    )
    data.recent = root.preferences.recentApps
      ? DockModel.buildRecentItems(root.recentIds, data, DesktopEntries, root.appLibrary, Quickshell, root.preferences.recentCount || 4)
      : []
    data.extras = DockModel.buildExtraItems(root.preferences.folders, root.preferences.showTrash === true, root.trashFull, root.homeDir)
    root.dockData = data
    root.urgentWindows = DockModel.toArray(Hyprland.toplevels.values)
      .filter(function(win) { return win && win.urgent === true && win.wayland })
      .map(function(win) { return win.wayland })
    if (root.pickerOpen) root.refreshPicker()

    var pCount = root.folded ? 0 : (data.pinned ? data.pinned.length : 0)
    var uCount = root.folded ? 0 : (data.unpinned ? data.unpinned.length : 0)
    var rCount = root.folded ? 0 : (data.recent ? data.recent.length : 0)
    var xCount = root.folded ? 0 : (data.extras ? data.extras.length : 0)
    root.baselineGeometry = DockModel.computeBaselineCenters(
      root.baseIconSize,
      root.itemSpacing,
      root.dockPadding,
      pCount,
      uCount,
      root.separatorWidth,
      rCount,
      xCount
    )

    updateMagnification()
  }

  function handleItemDragStarted(index, itemData, sceneX, sceneY) {
    if (dropSettleAnimation.running) {
      dropSettleAnimation.stop()
      root.finishDropReorder()
    }
    root.clearTooltip()
    root.closePicker()
    root.isDropSettling = false
    root.draggingPinnedIndex = index
    root.dragTargetIndex = index

    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || index >= geo.pinned.length) return

    var pt = dockCapsule.mapFromItem(null, sceneX, sceneY)
    var slotCenterX = geo.pinned[index]
    var slotCenterY = root.capsuleHeight - 5 - (root.iconPixelSize / 2)
    root.dragGrabOffsetX = pt.x - slotCenterX
    root.dragGrabOffsetY = pt.y - slotCenterY
    root.dragVisualX = 0
    root.dragVisualY = 0

    // Magnification is suspended for the complete drag. Clearing these once
    // avoids rebuilding arrays on every high-frequency pointer event.
    root.launcherScale = 1.0
    root.launcherOffsetX = 0
    root.pinnedScales = []
    root.unpinnedScales = []
    root.pinnedOffsets = []
    root.unpinnedOffsets = []
    root.recentOffsets = []
    root.extraCapsuleWidth = 0

    root.updateDragState(pt.x - root.dragGrabOffsetX)
  }

  function handleItemDragMoved(index, itemData, sceneX, sceneY) {
    if (root.isDropSettling) return
    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || index >= geo.pinned.length) return

    var pt = dockCapsule.mapFromItem(null, sceneX, sceneY)
    var slotCenterX = geo.pinned[index]
    var slotCenterY = root.capsuleHeight - 5 - (root.iconPixelSize / 2)
    root.dragVisualX = pt.x - slotCenterX - root.dragGrabOffsetX
    root.dragVisualY = Math.max(-20, Math.min(8, pt.y - slotCenterY - root.dragGrabOffsetY))

    root.updateDragState(pt.x - root.dragGrabOffsetX)
  }

  function updateDragState(currentCenterX) {
    var geo = root.baselineGeometry
    if (!geo || !geo.pinned || geo.pinned.length === 0) return

    var fromIdx = root.draggingPinnedIndex
    var pCenters = geo.pinned
    var pCount = pCenters.length

    var currentTarget = root.dragTargetIndex >= 0 ? root.dragTargetIndex : fromIdx
    var slotWidth = root.baseIconSize + root.itemSpacing
    var hysteresisMargin = slotWidth * 0.22 // ~10.5px directional deadzone to eliminate boundary jitter

    var bestIdx = currentTarget
    var bestDist = Math.abs(currentCenterX - pCenters[currentTarget]) - hysteresisMargin

    for (var i = 0; i < pCount; i++) {
      if (i === currentTarget) continue
      var dist = Math.abs(currentCenterX - pCenters[i])
      if (dist < bestDist) {
        bestDist = dist
        bestIdx = i
      }
    }
    // The dragged icon follows the pointer every frame, but neighbor layout
    // only changes when a slot boundary is crossed. Avoiding identical array
    // assignments keeps the QML animation scheduler off the pointer hot path.
    if (bestIdx === currentTarget && root.pinnedOffsets.length === pCount) return
    root.dragTargetIndex = bestIdx

    // Shift neighbor slots to preview the new layout
    var pOffsets = []
    var toIdx = root.dragTargetIndex

    for (var j = 0; j < pCount; j++) {
      if (j === fromIdx) {
        pOffsets.push(0)
      } else if (toIdx > fromIdx && j > fromIdx && j <= toIdx) {
        pOffsets.push(-slotWidth)
      } else if (toIdx < fromIdx && j >= toIdx && j < fromIdx) {
        pOffsets.push(slotWidth)
      } else {
        pOffsets.push(0)
      }
    }
    root.pinnedOffsets = pOffsets
  }

  function handleItemDragEnded(index, itemData, sourceItem) {
    var fromIdx = root.draggingPinnedIndex
    var toIdx = root.dragTargetIndex
    var geo = root.baselineGeometry

    if (fromIdx < 0 || !geo || !geo.pinned || fromIdx >= geo.pinned.length) {
      root.draggingPinnedIndex = -1
      root.dragTargetIndex = -1
      root.dragVisualX = 0
      root.dragVisualY = 0
      root.dragGrabOffsetX = 0
      root.dragGrabOffsetY = 0
      root.pinnedOffsets = []
      root.updateMagnification()
      return
    }

    var targetIdx = (toIdx >= 0 && toIdx < geo.pinned.length) ? toIdx : fromIdx
    root.dropSettleStartX = root.dragVisualX
    root.dropSettleStartY = root.dragVisualY
    // Distance from the starting slot center to the target slot center
    root.dropSettleTargetX = geo.pinned[targetIdx] - geo.pinned[fromIdx]
    root.dropSettleProgress = 0.0
    root.isDropSettling = true
    dropSettleAnimation.restart()
  }

  function finishDropReorder() {
    root.isDropSettling = false
    var fromIdx = root.draggingPinnedIndex
    var toIdx = root.dragTargetIndex

    root.draggingPinnedIndex = -1
    root.dragTargetIndex = -1
    root.dragVisualX = 0
    root.dragVisualY = 0
    root.dragGrabOffsetX = 0
    root.dragGrabOffsetY = 0

    if (fromIdx >= 0 && toIdx >= 0 && fromIdx !== toIdx) {
      root.reorderPinnedApps(fromIdx, toIdx)
    } else {
      root.pinnedOffsets = []
      root.updateMagnification()
    }
  }

  function reorderPinnedApps(fromIndex, toIndex) {
    var currentList = Array.isArray(root.customPinnedApps)
      ? root.customPinnedApps.slice()
      : DockModel.defaultPinnedApps.slice()

    if (fromIndex < 0 || fromIndex >= currentList.length || toIndex < 0 || toIndex >= currentList.length) {
      root.pinnedOffsets = []
      root.updateMagnification()
      return
    }

    var moved = currentList.splice(fromIndex, 1)[0]
    currentList.splice(toIndex, 0, moved)

    root.customPinnedApps = currentList
    root.saveConfig()
    root.rebuildDock()
  }

  function updateMagnification() {
    if (root.draggingPinnedIndex >= 0 || root.dropIndex >= 0) return
    if (!root.isDockHovered || root.hoverCursorX < 0) {
      root.launcherScale = 1.0
      root.launcherOffsetX = 0
      root.pinnedScales = []
      root.unpinnedScales = []
      root.recentScales = []
      root.pinnedOffsets = []
      root.unpinnedOffsets = []
      root.recentOffsets = []
      root.extraScales = []
      root.extraOffsets = []
      root.extraCapsuleWidth = 0
      return
    }

    var geo = root.baselineGeometry
    if (!geo) return

    // Capsule width and item slots stay fixed, so pointer coordinates already
    // map to the invariant resting geometry without feedback compensation.
    var baseCursorX = root.hoverCursorX

    // Applications launcher scale
    root.launcherScale = DockModel.scaleFromDistance(
      Math.abs(baseCursorX - geo.launcher),
      root.maxMagnification,
      root.magnifyRadius
    )

    // Pinned items scales
    var pScales = []
    for (var p = 0; p < geo.pinned.length; p++) {
      pScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - geo.pinned[p]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.pinnedScales = pScales

    // Unpinned items scales
    var uScales = []
    for (var u = 0; u < geo.unpinned.length; u++) {
      uScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - geo.unpinned[u]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.unpinnedScales = uScales

    var rScales = []
    var recentCenters = geo.recent || []
    for (var r = 0; r < recentCenters.length; r++) {
      rScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - recentCenters[r]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.recentScales = rScales

    var xScales = []
    var extraCenters = geo.extras || []
    for (var x = 0; x < extraCenters.length; x++) {
      xScales.push(DockModel.scaleFromDistance(
        Math.abs(baseCursorX - extraCenters[x]),
        root.maxMagnification,
        root.magnifyRadius
      ))
    }
    root.extraScales = xScales

    var allScales = [root.launcherScale].concat(pScales).concat(uScales).concat(rScales).concat(xScales)
    var offsets = DockModel.computeMagnifiedOffsets(
      allScales,
      root.baseIconSize,
      root.layoutExpansionRatio
    )
    root.launcherOffsetX = offsets.length > 0 ? offsets[0] : 0
    root.pinnedOffsets = offsets.slice(1, 1 + pScales.length)
    root.unpinnedOffsets = offsets.slice(1 + pScales.length, 1 + pScales.length + uScales.length)
    root.recentOffsets = offsets.slice(1 + pScales.length + uScales.length, 1 + pScales.length + uScales.length + rScales.length)
    root.extraOffsets = offsets.slice(1 + pScales.length + uScales.length + rScales.length)
    root.extraCapsuleWidth = (typeof offsets.totalExtra === "number") ? offsets.totalExtra : 0
  }

  // Observe each window, including moves that do not change the global list.
  Instantiator {
    model: Hyprland.toplevels
    delegate: Connections {
      required property var modelData
      target: modelData
      function onWorkspaceChanged() { Qt.callLater(root.rebuildDock) }
      function onMonitorChanged() { Qt.callLater(root.rebuildDock) }
      // A title change never moves an app between groups; only the open
      // window list cares. Terminals retitle every second, so keep this cheap.
      function onTitleChanged() { titleRefreshTimer.restart() }
      function onWaylandHandleChanged() { Qt.callLater(root.rebuildDock) }
      function onUrgentChanged() { Qt.callLater(root.rebuildDock) }
    }
  }
  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { Qt.callLater(root.rebuildDock) }
  }
  Timer {
    id: titleRefreshTimer
    interval: 250
    onTriggered: if (root.pickerOpen) root.refreshPicker()
  }

  // Reactive listeners for window and app changes
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuildDock() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.rebuildDock() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuildDock() }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.rebuildDock() }
  }

  // ---- Drop target for tiles dragged out of the app drawer ----
  property int dropIndex: -1      // insertion index into the pinned group, -1 = none
  property var dropApp: null

  function clearDrop() {
    if (root.dropIndex < 0 && !root.dropApp) return
    root.dropIndex = -1
    root.dropApp = null
    root.launcherOffsetX = 0
    root.pinnedOffsets = []
    root.unpinnedOffsets = []
    root.recentOffsets = []
    root.extraCapsuleWidth = 0
    root.updateMagnification()
  }

  function drawerDragMoved(app, x, y) {
    var geo = root.baselineGeometry
    if (!geo) return
    var overDock = y >= appDrawer.height - 6
    var capsuleLeft = (dockPanel.width - dockCapsule.width) / 2
    var localX = x - capsuleLeft
    if (!overDock || localX < -40 || localX > dockCapsule.width + 40) { root.clearDrop(); return }
    var idx = 0
    for (var i = 0; i < geo.pinned.length; i++) if (localX > geo.pinned[i] + root.extraCapsuleWidth / 2) idx = i + 1
    if (idx === root.dropIndex && root.dropApp === app) return
    root.dropApp = app
    root.dropIndex = idx
    root.revealDock()
    var slot = root.baseIconSize + root.itemSpacing
    root.launcherScale = 1
    root.pinnedScales = []
    root.unpinnedScales = []
    root.launcherOffsetX = -slot / 2
    var offs = []
    for (var j = 0; j < geo.pinned.length; j++) offs.push(j < idx ? -slot / 2 : slot / 2)
    root.pinnedOffsets = offs
    var uoffs = []
    for (var u = 0; u < geo.unpinned.length; u++) uoffs.push(slot / 2)
    root.unpinnedOffsets = uoffs
    var roffs = []
    for (var rr = 0; rr < (geo.recent || []).length; rr++) roffs.push(slot / 2)
    root.recentOffsets = roffs
    root.extraCapsuleWidth = slot
  }

  // Centre of the open gap in capsule coordinates.
  readonly property real dropSlotCenterX: {
    var geo = root.baselineGeometry
    if (!geo || root.dropIndex < 0) return 0
    var slot = root.baseIconSize + root.itemSpacing
    var n = geo.pinned.length
    var base = root.dropIndex < n ? geo.pinned[root.dropIndex] - slot / 2
      : (n > 0 ? geo.pinned[n - 1] + slot / 2 : geo.launcher + slot / 2 + root.separatorWidth + root.itemSpacing)
    return base + root.extraCapsuleWidth / 2
  }

  function drawerDragEnded(app, x, y) {
    var idx = root.dropIndex
    var wasOver = idx >= 0
    root.clearDrop()
    if (!wasOver || !app || !app.id) return
    var list = (Array.isArray(root.customPinnedApps) ? root.customPinnedApps : DockModel.defaultPinnedApps).slice()
    for (var i = list.length - 1; i >= 0; i--) {
      var pid = typeof list[i] === "string" ? list[i] : (list[i].id || "")
      if (pid === app.id || DockModel.matchApp(pid, app.id)) {
        list.splice(i, 1)
        if (i < idx) idx--
      }
    }
    idx = Math.max(0, Math.min(list.length, idx))
    list.splice(idx, 0, app.id)
    root.customPinnedApps = list
    root.saveConfig()
    root.rebuildDock()
    appDrawer.close()
  }

  property double drawerToggledAt: 0
  function toggleDrawer() {
    // A press that opens the drawer must not be read again as a close.
    var now = Date.now()
    if (now - root.drawerToggledAt < 250) return
    root.drawerToggledAt = now
    if (appDrawer.open) { appDrawer.close(); return }
    root.closeContextMenu()
    root.closePicker()
    root.clearTooltip()
    root.settingsOpen = false
    root.revealDock()
    appDrawer.open = true
    
  }

  // `omarchy-shell magnify-dock drawer` toggles the app drawer (bind it to a
  // key); `settings` opens the settings card; `status` reports state.
  IpcHandler {
    target: "magnify-dock"
    function drawer(): string { root.toggleDrawer(); return appDrawer.open ? "open" : "closed" }
    function settings(): string { if (root.settingsOpen) root.closeSettings(); else root.openSettings(); return root.settingsOpen ? "open" : "closed" }
    function autoHide(): string { root.autoHide = !root.autoHide; root.saveConfig(); return root.autoHide ? "on" : "off" }
    function settingsPage(name: string): string { root.settingsPage = String(name || "appearance"); root.openSettings(); return root.settingsPage }
    function preset(name: string): string { return root.applyPreset(name) ? "applied" : "no such preset" }
    function savePreset(name: string): string { return root.savePreset(name) ? "saved" : "name required" }
    function deletePreset(name: string): string { return root.deletePreset(name) ? "deleted" : "no such preset" }
    function presets(): string { return JSON.stringify(root.presets.map(function(p) { return p.name })) }
    function status(): string {
      return JSON.stringify({ screen: root.dockScreen ? root.dockScreen.name : "", pinned: root.dockData.pinned.length, running: root.dockData.unpinned.length, autoHide: root.autoHide, reserveSpace: root.reserveSpace, drawer: appDrawer.open, settings: root.settingsOpen, opacitySetting: root.preferences.opacity, surfaceAlpha: root.surfaceAlpha, dockHovered: root.isDockHovered })
    }
  }


  DockDrawer {
    id: appDrawer
    dockScreen: root.dockScreen
    appLibrary: root.appLibrary
    textScale: root.textScale
    fontFamily: root.fontFamily
    backdropOpacity: root.surfaceAlpha
    backdropColor: root.drawerColor
    bottomInset: dockPanel.implicitHeight
    pinnedIds: root.dockData.pinned.map(function(p) { return p.id })
    tileShape: root.tileShape
    uniformIcons: root.uniformIcons
    onDragMoved: function(app, x, y) { root.drawerDragMoved(app, x, y) }
    onDragEnded: function(app, x, y) { root.drawerDragEnded(app, x, y) }
    onPinToggleRequested: function(app) { if (app && app.id) root.togglePinApp(app.id) }
    onLaunched: function(app) { root.noteLaunch(app) }
    onDrawerClosed: root.scheduleDockHide()
  }

  Component.onCompleted: {
    console.log("Magnify Dock instance ready", root.dockScreen ? root.dockScreen.name : "no-screen")
    root.requestState("config")
    root.requestState("presets")
    root.requestState("muted")
    if (root.appLibrary) root.appLibrary.refreshIcons()
    root.rebuildDock()
  }

  // macOS Dock Panel Window
  PanelWindow {
    id: dockPanel
    visible: true
    screen: root.dockScreen

    anchors {
      bottom: true
      left: true
      right: true
    }

    margins {
      bottom: 0
    }

    implicitWidth: 0
    implicitHeight: root.capsuleHeight
      + root.dockEdgeMargin
      + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0))
      + 24
    color: "transparent"

    WlrLayershell.namespace: "omarchy-dock"
    WlrLayershell.layer: WlrLayer.Top
    // Settings hold a text field (preset name); give the layer the keyboard
    // on demand only while the card is open so the dock never steals focus otherwise.
    WlrLayershell.keyboardFocus: root.settingsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    
    // Reserve bottom space so Hyprland windows stop cleanly above the dock
    exclusionMode: root.reserveSpace && !root.autoHide
      ? ExclusionMode.Normal
      : ExclusionMode.Ignore
    exclusiveZone: root.capsuleHeight + root.dockEdgeMargin + 6

    // Single dynamic hit area bound directly to mask so Quickshell updates
    // the Wayland input region on geometry changes without nested region issues.
    Item {
      id: dockHitArea
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: (!root.autoHide || root.dockPresented)
        ? (dockCapsule.width + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0) * 2) + 8)
        : (root.autoHide ? (dockCapsule.width + 160) : 0)
      height: (!root.autoHide || root.dockPresented)
        ? (root.capsuleHeight + root.dockEdgeMargin + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0)) + 14)
        : (root.autoHide ? 4 : 0)
    }

    mask: Region {
      item: dockHitArea
    }

    // A separate popup surface can rise above the layer window without being
    // clipped by its compact exclusive-zone height.
    PopupWindow {
      id: tooltipWindow
      visible: root.tooltipVisible
        && root.tooltipTarget !== null
        && root.tooltipText !== ""
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!target) return
          try {
            var targetOffset = Number(target.animatedOffsetX || 0)
            var localX = target.width / 2 - tooltipWindow.implicitWidth / 2 + targetOffset
            var localY = -tooltipWindow.implicitHeight - Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0)) - 12
            var point = dockPanel.contentItem.mapFromItem(target, localX, localY)
            tooltipWindow.anchor.rect.x = Math.round(point.x)
            tooltipWindow.anchor.rect.y = Math.round(point.y)
          } catch (e) {}
        }
      }

      Rectangle {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 22
        implicitHeight: tooltipLabel.implicitHeight + 10
        radius: 8
        color: Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b, Math.max(0.6, root.surfaceAlpha))
        border.color: Qt.rgba(1, 1, 1, 0.13)
        border.width: 1

        Text {
          id: tooltipLabel
          anchors.centerIn: parent
          text: root.tooltipText
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Math.round(12.5 * root.textScale)
          font.weight: Font.Medium
          color: Qt.rgba(1, 1, 1, 0.95)
        }
      }
    }

    PopupWindow {
      id: pickerWindow
      visible: root.pickerOpen
      color: "transparent"
      implicitWidth: windowPicker.width
      implicitHeight: windowPicker.height
      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.x: Math.round(root.pickerAnchorX - pickerWindow.implicitWidth / 2)
        rect.y: Math.round(root.pickerAnchorY - pickerWindow.implicitHeight)
        rect.width: 1
        rect.height: 1
      }
      DockWindowPicker {
        id: windowPicker
        title: root.pickerTitle
        rows: root.windowRows
        textScale: root.textScale
        accent: root.accent
        fontFamily: root.fontFamily
        previews: root.preferences.windowPreviews !== false
        glassColor: root.previewColor
        previewWidth: root.preferences.previewWidth || 220
        previewHeight: root.preferences.previewHeight || 220
        maxWidth: Math.max(240, (root.dockScreen ? root.dockScreen.width : 1280) - 40)
        glassOpacity: root.surfaceAlpha
        maxHeight: Math.max(120, (root.dockScreen ? root.dockScreen.height : 720) - dockPanel.height - 32)
        onContainsPointerChanged: {
          if (containsPointer) pickerHideTimer.stop()
          else if (root.pickerOpen) pickerHideTimer.restart()
        }
        onWindowActivated: function(win) {
          root.closePicker()
          DockModel.activateWindow(win)
        }
        onWindowClosed: function(win) { DockModel.closeAppWindow({ windows: [win] }) }
        onDismissed: root.closePicker()
      }
    }

    PopupWindow {
      id: settingsWindow
      visible: root.settingsOpen
      color: "transparent"
      implicitWidth: settingsPanel.width
      implicitHeight: settingsPanel.height
      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.x: Math.round((dockPanel.width - settingsWindow.implicitWidth) / 2)
        rect.y: Math.round(dockPanel.height - root.capsuleHeight - settingsWindow.implicitHeight - 12)
        rect.width: 1
        rect.height: 1
      }
      DockSettings {
        id: settingsPanel
        settings: root.preferences
        isAutoHide: root.autoHide
        isReserveSpace: root.reserveSpace
        accent: root.accent
        fontFamily: root.fontFamily
        glassOpacity: root.surfaceAlpha
        glassColor: root.glassColor
        maxHeight: Math.max(180, (root.dockScreen ? root.dockScreen.height : 720) - dockPanel.height - 32)
        onPreferenceChanged: function(key, value) { root.changePreference(key, value) }
        onAutoHideToggled: { root.autoHide = !root.autoHide; root.saveConfig() }
        onReserveSpaceToggled: { root.reserveSpace = !root.reserveSpace; root.saveConfig() }
        presets: root.presets
        Component.onCompleted: page = root.settingsPage
        onPageChanged: if (root.settingsPage !== page) root.settingsPage = page
        onPresetSaved: function(name) { root.savePreset(name) }
        onPresetApplied: function(name) { root.applyPreset(name) }
        onPresetDeleted: function(name) { root.deletePreset(name) }
        onDismissed: root.closeSettings()
      }
    }

    PopupWindow {
      id: contextWindow
      visible: root.contextMenuOpen && root.contextAnchor !== null
      color: "transparent"
      implicitWidth: dockContextMenu.width
      implicitHeight: dockContextMenu.height

      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.contextAnchor
          if (!target) return
          try {
            var targetOffset = Number(target.animatedOffsetX || 0)
            var localX = target.width / 2 - contextWindow.implicitWidth / 2 + targetOffset
            var localY = -contextWindow.implicitHeight - 10
            var point = dockPanel.contentItem.mapFromItem(target, localX, localY)
            contextWindow.anchor.rect.x = Math.round(point.x)
            contextWindow.anchor.rect.y = Math.round(point.y)
          } catch (e) {}
        }
      }

      DockContextMenu {
        id: dockContextMenu
        targetItem: root.contextTarget
        isOpen: root.contextMenuOpen
        isAudioMuted: root.isAppAudioMuted(root.contextTarget)
        textScale: root.textScale
        fontFamily: root.fontFamily
        glassOpacity: root.surfaceAlpha
        glassColor: root.glassColor

        onLaunchClicked: function(item) {
          if (item && !item.isRunning) root.noteLaunch(item)
          DockModel.handleItemClick(item, Quickshell, root.appLibrary, DesktopEntries)
        }
        onPinToggled: function(item) {
          if (item && item.id) root.togglePinApp(item.id)
        }
        onQuitClicked: function(item) {
          DockModel.closeAppWindow(item)
        }
        onMuteAudioToggled: function(item) {
          root.toggleAppAudio(item)
        }
        onSettingsRequested: root.openSettings()
        onMenuClosed: root.closeContextMenu()
        customEntries: root.extraMenuEntries(root.contextTarget)
        onCustomAction: function(action, item) { root.handleExtraAction(action, item) }
      }
    }

    // Folder stack popup, anchored above the hovered folder tile like the window picker.
    PopupWindow {
      id: folderWindow
      visible: root.folderOpen
      color: "transparent"
      implicitWidth: folderPopup.width
      implicitHeight: folderPopup.height
      anchor {
        window: dockPanel
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.x: Math.round(root.folderAnchorX - folderWindow.implicitWidth / 2)
        rect.y: Math.round(root.folderAnchorY - folderWindow.implicitHeight)
        rect.width: 1
        rect.height: 1
      }
      DockFolderPopup {
        id: folderPopup
        folderPath: root.folderPath
        title: root.folderTitle
        textScale: root.textScale
        accent: root.accent
        fontFamily: root.fontFamily
        glassColor: root.glassColor
        glassOpacity: root.surfaceAlpha
        maxHeight: Math.max(120, (root.dockScreen ? root.dockScreen.height : 720) - dockPanel.height - 32)
        onContainsPointerChanged: {
          if (containsPointer) folderHideTimer.stop()
          else if (root.folderOpen) folderHideTimer.restart()
        }
        onEntryActivated: function(path) { root.closeFolderPopup(); root.openPath(path) }
        onFolderActivated: function(path) { root.closeFolderPopup(); root.openPath(path) }
        onDismissed: root.closeFolderPopup()
      }
    }

    Item {
      id: edgeRevealArea
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: dockCapsule.width + 160
      height: root.autoHide ? 4 : 0

      HoverHandler {
        onHoveredChanged: {
          root.edgeHovered = hovered
          if (hovered) {
            if (!root.dockPresented) edgeRevealTimer.restart()
          } else {
            edgeRevealTimer.stop()
            root.scheduleDockHide()
          }
        }
        onPointChanged: {
          if (hovered && root.autoHide && !root.dockPresented && !edgeRevealTimer.running) {
            edgeRevealTimer.start()
          }
        }
      }
    }

    Item {
      id: dockInteractionRegion
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: dockCapsule.width
        + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0) * 2)
        + 8
      height: root.capsuleHeight
        + Math.ceil(root.iconPixelSize * (root.maxMagnification - 1.0))
        + 14

      Item {
        id: dockInputRegion
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: (!root.autoHide || root.dockPresented) ? parent.width : 0
        height: (!root.autoHide || root.dockPresented) ? parent.height : 0
        visible: !root.autoHide || root.dockPresented
      }

      // The capsule and its hit envelope share this parent. When reveal swaps
      // input from the thin edge to the dock, hover ownership transfers inside
      // one subtree instead of briefly exiting the panel.
      HoverHandler {
        id: dockHover
        enabled: !root.autoHide || root.dockPresented
        onHoveredChanged: {
          root.isDockHovered = hovered
          if (hovered) {
            root.revealDock()
          } else {
            root.hoverCursorX = -1
            root.clearTooltip()
            root.updateMagnification()
            root.scheduleDockHide()
          }
        }
        onPointChanged: {
          if (hovered) {
            var centerDelta = point.position.x - (dockInteractionRegion.width / 2)
            var baseWidth = root.baselineGeometry ? root.baselineGeometry.totalBaseWidth : dockCapsule.width
            root.isDockHovered = true
            root.hoverCursorX = (baseWidth / 2) + centerDelta
            root.updateMagnification()
          }
        }
      }

      // Soft drop shadow under the capsule (design: 0 14px 44px rgba(0,0,0,0.45)),
      // stacked translucent rectangles rather than MultiEffect (see DockTile).
      Repeater {
        model: 6
        delegate: Rectangle {
          required property int index
          z: -1
          anchors.centerIn: dockCapsule
          anchors.verticalCenterOffset: 4 + index * 2
          width: dockCapsule.width + index * 6
          height: dockCapsule.height + index * 6
          radius: dockCapsule.radius + index * 3
          visible: root.showBackground
          color: Qt.rgba(0, 0, 0, 0.075 * root.surfaceAlpha)
          transform: Translate { y: capsuleSlide.y }
        }
      }

      // Frosted glass capsule (design tokens: rgba(18,20,26,opacity), 19px
      // radius, 1px white/13% border, white/14% top highlight).
      Rectangle {
        id: dockCapsule
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.dockEdgeMargin

      height: root.capsuleHeight
      width: contentRow.width + root.dockPadding * 2 + root.animatedExtraCapsuleWidth
      radius: 19
      transform: Translate {
        id: capsuleSlide
        y: root.autoHide && !root.dockPresented ? root.capsuleHeight + 30 : 0
        Behavior on y {
          NumberAnimation {
            duration: root.reduceMotion ? 0 : 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.3, 0.8, 0.3, 1, 1, 1]
          }
        }
      }

      color: root.showBackground ? Qt.rgba(root.dockColor.r, root.dockColor.g, root.dockColor.b, root.surfaceAlpha) : "transparent"
      border.color: Qt.rgba(1, 1, 1, 0.13)
      border.width: root.showBackground ? 1 : 0

      // Inset edge light that follows the rounded shape.
      Rectangle {
        visible: root.showBackground
        anchors.fill: parent
        radius: 19
        gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.14) }
        GradientStop { position: 0.06; color: "transparent" }
        }
      }

      // Preview of a tile being dropped in from the drawer, shown in the gap.
      DockTile {
        visible: root.dropIndex >= 0 && root.dropApp !== null
        z: 5
        size: root.iconPixelSize
        x: root.dropSlotCenterX - root.iconPixelSize / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 13
        opacity: 0.75
        iconSource: root.dropApp ? root.dropApp.icon : ""
        appName: root.dropApp ? root.dropApp.name : ""
        fontFamily: root.fontFamily
        shape: root.tileShape
        uniform: root.uniformIcons
      }

      // Main Items Content Row
      Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.itemSpacing

        // Application launcher (same action as SUPER + ALT + SPACE)
        Item {
          id: launcherItem
          width: root.baseIconSize
          height: root.baseIconSize
          z: root.animatedLauncherScale

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            width: root.iconPixelSize
            height: root.iconPixelSize
            transformOrigin: Item.Bottom
            scale: root.animatedLauncherScale
            transform: Translate { x: root.animatedLauncherOffsetX }

            // Launcher tile: white glass gradient, 24% radius, 3×3 dot grid.
            Rectangle {
              anchors.fill: parent
              radius: Math.round(root.iconPixelSize * root.tileRadiusRatio)
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, launcherMouse.containsMouse || appDrawer.open ? 0.28 : 0.2) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, launcherMouse.containsMouse || appDrawer.open ? 0.16 : 0.1) }
              }
              border.width: 0

              // Inset edge light that follows the rounded shape.
              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.06; color: "transparent" }
                }
              }

              Grid {
                anchors.centerIn: parent
                columns: 3
                rows: 3
                spacing: Math.max(2, Math.round(root.iconPixelSize * 0.11))
                Repeater {
                  model: 9
                  delegate: Rectangle {
                    width: Math.max(3, Math.round(root.iconPixelSize * 0.1))
                    height: width
                    radius: width / 2
                    color: Qt.rgba(1, 1, 1, 0.92)
                  }
                }
              }
            }

            MouseArea {
              id: launcherMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton

              onEntered: root.requestTooltip(launcherItem, "Applications")
              onExited: root.releaseTooltip(launcherItem)
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) root.openSettings()
                else root.toggleDrawer()
              }
            }
          }
        }

        Item {
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.folded
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Pinned Apps
        Repeater {
          id: pinnedRepeater
          model: root.dockData.pinned

          delegate: DockItem {
            required property var modelData
            required property int index

            visible: !root.folded
            itemData: modelData
            itemIndex: index
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            tileShape: root.tileShape
            uniformIcons: root.uniformIcons
            badgeCount: root.badgesOn ? root.badgeCountFor(modelData, root.badgeMap) : 0
            badgeUrgent: root.badgesOn && DockModel.hasUrgentWindow(modelData, root.urgentWindows)
            isBeingDragged: root.draggingPinnedIndex === index
            isReordering: root.draggingPinnedIndex >= 0
            dragVisualX: root.draggingPinnedIndex === index ? root.dragVisualX : 0
            dragVisualY: root.draggingPinnedIndex === index ? root.dragVisualY : 0
            targetScale: (Array.isArray(root.pinnedScales) && index < root.pinnedScales.length) ? root.pinnedScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.pinnedOffsets) && index < root.pinnedOffsets.length) ? root.pinnedOffsets[index] : 0

            onClicked: function(item) {
              if (item && !item.isRunning) root.noteLaunch(item)
              DockModel.handleItemClick(item, Quickshell, root.appLibrary, DesktopEntries)
            }

            onPinToggleRequested: function(item) {
              if (item && item.id) {
                root.togglePinApp(item.id)
              }
            }

            onCloseRequested: function(item) {
              DockModel.closeAppWindow(item)
            }

            onContextMenuRequested: function(item, srcItem) {
              root.openContextMenu(item, srcItem)
            }

            onHovered: function(item, srcItem) {
              if (root.draggingPinnedIndex >= 0) return
              root.requestAppTooltip(item, srcItem)
            }

            onUnhovered: function(srcItem) {
              root.releaseAppTooltip(srcItem)
            }

            onDragStarted: function(idx, item, sceneX, sceneY) {
              root.handleItemDragStarted(idx, item, sceneX, sceneY)
            }

            onDragMoved: function(idx, item, sceneX, sceneY) {
              root.handleItemDragMoved(idx, item, sceneX, sceneY)
            }

            onDragEnded: function(idx, item, srcItem) {
              root.handleItemDragEnded(idx, item, srcItem)
            }
          }
        }

        // Separator between pinned and unpinned running apps
        Item {
          visible: !root.folded
            && (root.dockData.pinned && root.dockData.pinned.length > 0)
            && (root.dockData.unpinned && root.dockData.unpinned.length > 0)
          anchors.verticalCenter: parent.verticalCenter
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Unpinned Running Apps
        Repeater {
          id: unpinnedRepeater
          model: root.dockData.unpinned

          delegate: DockItem {
            required property var modelData
            required property int index

            visible: !root.folded
            itemData: modelData
            itemIndex: (root.dockData.pinned ? root.dockData.pinned.length : 0) + index
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            tileShape: root.tileShape
            uniformIcons: root.uniformIcons
            badgeCount: root.badgesOn ? root.badgeCountFor(modelData, root.badgeMap) : 0
            badgeUrgent: root.badgesOn && DockModel.hasUrgentWindow(modelData, root.urgentWindows)
            targetScale: (Array.isArray(root.unpinnedScales) && index < root.unpinnedScales.length) ? root.unpinnedScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.unpinnedOffsets) && index < root.unpinnedOffsets.length) ? root.unpinnedOffsets[index] : 0

            onClicked: function(item) {
              if (item && !item.isRunning) root.noteLaunch(item)
              DockModel.handleItemClick(item, Quickshell, root.appLibrary, DesktopEntries)
            }

            onPinToggleRequested: function(item) {
              if (item && item.id) {
                root.togglePinApp(item.id)
              }
            }

            onCloseRequested: function(item) {
              DockModel.closeAppWindow(item)
            }

            onContextMenuRequested: function(item, srcItem) {
              root.openContextMenu(item, srcItem)
            }

            onHovered: function(item, srcItem) {
              root.requestAppTooltip(item, srcItem)
            }

            onUnhovered: function(srcItem) {
              root.releaseAppTooltip(srcItem)
            }
          }
        }

        // Divider before recent apps
        Item {
          visible: !root.folded
            && root.dockData.recent && root.dockData.recent.length > 0
            && ((root.dockData.pinned && root.dockData.pinned.length > 0) || (root.dockData.unpinned && root.dockData.unpinned.length > 0))
          anchors.verticalCenter: parent.verticalCenter
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Recent apps (launched recently, not pinned, not running)
        Repeater {
          id: recentRepeater
          model: root.dockData.recent || []

          delegate: DockItem {
            required property var modelData
            required property int index

            visible: !root.folded
            itemData: modelData
            itemIndex: (root.dockData.pinned ? root.dockData.pinned.length : 0) + (root.dockData.unpinned ? root.dockData.unpinned.length : 0) + index
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            tileShape: root.tileShape
            uniformIcons: root.uniformIcons
            badgeCount: root.badgesOn ? root.badgeCountFor(modelData, root.badgeMap) : 0
            badgeUrgent: root.badgesOn && DockModel.hasUrgentWindow(modelData, root.urgentWindows)
            targetScale: (Array.isArray(root.recentScales) && index < root.recentScales.length) ? root.recentScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.recentOffsets) && index < root.recentOffsets.length) ? root.recentOffsets[index] : 0

            onClicked: function(item) {
              root.noteLaunch(item)
              DockModel.handleItemClick(item, Quickshell, root.appLibrary, DesktopEntries)
            }
            onPinToggleRequested: function(item) { if (item && item.id) root.togglePinApp(item.id) }
            onContextMenuRequested: function(item, srcItem) { root.openContextMenu(item, srcItem) }
            onHovered: function(item, srcItem) { root.requestAppTooltip(item, srcItem) }
            onUnhovered: function(srcItem) { root.releaseAppTooltip(srcItem) }
          }
        }

        // Divider before folders and the trash
        Item {
          visible: !root.folded
            && Array.isArray(root.dockData.extras) && root.dockData.extras.length > 0
            && ((root.dockData.pinned && root.dockData.pinned.length > 0)
                || (root.dockData.unpinned && root.dockData.unpinned.length > 0)
                || (root.dockData.recent && root.dockData.recent.length > 0))
          anchors.verticalCenter: parent.verticalCenter
          width: root.separatorWidth
          height: root.iconPixelSize - 6
          Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.16) }
        }

        // Folders and the trash
        Repeater {
          id: extrasRepeater
          model: root.dockData.extras || []

          delegate: DockItem {
            required property var modelData
            required property int index

            visible: !root.folded
            itemData: modelData
            itemIndex: 0
            baseSize: root.baseIconSize
            iconSize: root.iconPixelSize
            isDockHovered: root.isDockHovered
            magnificationDuration: root.magnificationDuration
            reduceMotion: root.reduceMotion
            accent: root.accent
            fontFamily: root.fontFamily
            tileShape: root.tileShape
            uniformIcons: root.uniformIcons
            targetScale: (Array.isArray(root.extraScales) && index < root.extraScales.length) ? root.extraScales[index] : 1.0
            targetOffsetX: (Array.isArray(root.extraOffsets) && index < root.extraOffsets.length) ? root.extraOffsets[index] : 0

            onClicked: function(item) { root.openExtra(item) }
            onPinToggleRequested: function(item) { if (item && item.kind === "folder") root.removeFolder(item.path) }
            onContextMenuRequested: function(item, srcItem) { root.openContextMenu(item, srcItem) }
            onHovered: function(item, srcItem) { root.requestExtraHover(item, srcItem) }
            onUnhovered: function(srcItem) { root.releaseExtraHover(srcItem) }
          }
        }

        // Collapse control: folds the rail down to the launcher.
        Item {
          id: collapseControl
          visible: root.collapsible
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(14, Math.round(root.iconPixelSize * 0.4))
          height: root.baseIconSize

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: Math.round(root.iconPixelSize * 0.7)
            radius: Math.min(8, width / 2)
            color: collapseMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
            Text {
              anchors.centerIn: parent
              text: root.collapsed ? "󰅂" : "󰅁"
              font.family: Style.font.family
              font.pixelSize: Math.round(root.iconPixelSize * 0.42)
              color: Qt.rgba(1, 1, 1, collapseMouse.containsMouse ? 0.95 : 0.6)
            }
          }
          MouseArea {
            id: collapseMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.requestTooltip(collapseControl, root.collapsed ? "Expand dock" : "Collapse dock")
            onExited: root.releaseTooltip(collapseControl)
            onClicked: root.toggleCollapsed()
          }
        }
      }

      }
    }
  }
}
