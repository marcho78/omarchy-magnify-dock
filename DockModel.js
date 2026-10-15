// DockModel.js - Core logic for macOS-style dock in Omarchy

var defaultSettings = {
  iconSize: 38, magnification: 1.7, spacing: 8, opacity: 0.72, textScale: 1,
  revealDelay: 0, hideDelay: 220, windowScope: "all",
  dockColor: "#12141a", drawerColor: "#0a0c11", accentColor: "", previewColor: "",
  windowPreviews: true, previewWidth: 220, previewHeight: 220,
  themeColors: true, recentApps: false, recentCount: 4,
  tileShape: "rounded", uniformIcons: false,
  showBackground: true, collapsible: false,
  badges: true, showTrash: false, folders: []
};

// Folder icons by well-known basename; anything else gets the plain folder.
var folderIconByName = {
  "downloads": "folder-download", "documents": "folder-documents", "pictures": "folder-pictures",
  "music": "folder-music", "videos": "folder-videos", "desktop": "user-desktop",
  "public": "folder-publicshare", "templates": "folder-templates", "projects": "folder-development",
  "code": "folder-development", "src": "folder-development"
};

var colorPresets = ["#12141a", "#0a0c11", "#1e1e2e", "#24283b", "#1b2a2f", "#2b1d2e", "#3a2a1a", "#000000"];
var accentPresets = ["#6FA8FF", "#9D8CFF", "#5BD6A9", "#FFB16E"];

function isHexColor(v) {
  return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v);
}

// Layout constants from the Magnify Dock design.
var railPadding = 12;      // horizontal inset of the first/last slot
var separatorWidth = 17;   // width reserved for a divider between groups

function normalizeSettings(input) {
  input = input && typeof input === "object" ? input : {};
  var result = {};
  var ranges = {
    iconSize: [24, 64], magnification: [1, 2], spacing: [2, 16],
    opacity: [0.2, 1], textScale: [0.8, 1.6], previewWidth: [120, 640], previewHeight: [80, 480], recentCount: [1, 8], revealDelay: [0, 1000], hideDelay: [100, 2000]
  };
  for (var key in ranges) {
    var value = input[key];
    result[key] = typeof value === "number" && isFinite(value)
      ? Math.max(ranges[key][0], Math.min(ranges[key][1], value))
      : defaultSettings[key];
  }
  result.windowScope = ["all", "monitor", "workspace"].indexOf(input.windowScope) >= 0
    ? input.windowScope : "all";
  result.dockColor = isHexColor(input.dockColor) ? input.dockColor.toLowerCase() : defaultSettings.dockColor;
  result.drawerColor = isHexColor(input.drawerColor) ? input.drawerColor.toLowerCase() : defaultSettings.drawerColor;
  // Empty accent means "follow the Omarchy theme accent".
  result.accentColor = isHexColor(input.accentColor) ? input.accentColor.toLowerCase() : "";
  result.windowPreviews = typeof input.windowPreviews === "boolean" ? input.windowPreviews : defaultSettings.windowPreviews;
  // Empty preview colour means: same glass as the other popups.
  result.previewColor = isHexColor(input.previewColor) ? input.previewColor.toLowerCase() : "";
  result.themeColors = typeof input.themeColors === "boolean" ? input.themeColors : defaultSettings.themeColors;
  result.recentApps = typeof input.recentApps === "boolean" ? input.recentApps : defaultSettings.recentApps;
  result.tileShape = ["rounded", "circle", "square", "none"].indexOf(input.tileShape) >= 0 ? input.tileShape : "rounded";
  result.showBackground = typeof input.showBackground === "boolean" ? input.showBackground : defaultSettings.showBackground;
  result.uniformIcons = typeof input.uniformIcons === "boolean" ? input.uniformIcons : defaultSettings.uniformIcons;
  result.collapsible = typeof input.collapsible === "boolean" ? input.collapsible : defaultSettings.collapsible;
  result.badges = typeof input.badges === "boolean" ? input.badges : defaultSettings.badges;
  result.showTrash = typeof input.showTrash === "boolean" ? input.showTrash : defaultSettings.showTrash;
  result.folders = normalizeFolders(input.folders);
  return result;
}

// Folder tiles: absolute paths, trimmed, no duplicates, at most eight.
function normalizeFolders(list) {
  if (!Array.isArray(list)) return [];
  var out = [];
  for (var i = 0; i < list.length && out.length < 8; i++) {
    var p = String(list[i] || "").trim().replace(/\/+$/, "");
    if (p.charAt(0) !== "/" || out.indexOf(p) >= 0) continue;
    out.push(p);
  }
  return out;
}

function folderName(path, home) {
  var clean = String(path || "").replace(/\/+$/, "");
  if (home && clean === String(home).replace(/\/+$/, "")) return "Home";
  var base = clean.substring(clean.lastIndexOf("/") + 1);
  return base || "/";
}

function folderIcon(path, home) {
  var clean = String(path || "").replace(/\/+$/, "");
  if (home && clean === String(home).replace(/\/+$/, "")) return "user-home";
  var base = clean.substring(clean.lastIndexOf("/") + 1).toLowerCase();
  return folderIconByName[base] || "folder";
}

// The rail's last group: pinned folders, then the trash. Built like app
// items so DockItem can render them; "kind" tells the click handler apart.
function buildExtraItems(folders, showTrash, trashFull, home) {
  var out = [];
  var list = normalizeFolders(folders);
  for (var i = 0; i < list.length; i++) {
    out.push({
      kind: "folder", id: "folder:" + list[i], key: "folder:" + list[i], path: list[i],
      name: folderName(list[i], home), icon: folderIcon(list[i], home),
      isPinned: false, isRunning: false, isFocused: false, windows: []
    });
  }
  if (showTrash) {
    out.push({
      kind: "trash", id: "trash", key: "trash", path: "trash:///",
      name: trashFull ? "Trash (full)" : "Trash", icon: trashFull ? "user-trash-full" : "user-trash",
      isPinned: false, isRunning: false, isFocused: false, windows: []
    });
  }
  return out;
}

// ---------- badges ----------

// com.canonical.Unity.LauncherEntry addresses apps as application://x.desktop.
function badgeKey(appUri) {
  return String(appUri || "").replace(/^application:\/\//, "").replace(desktopSuffixRe, "").toLowerCase();
}

// Find the badge an app reported, matching the same way pins match windows.
function badgeForItem(badgeMap, item) {
  if (!badgeMap || !item) return null;
  var ids = [item.id];
  if (item.desktopEntry && item.desktopEntry.id) ids.push(item.desktopEntry.id);
  for (var key in badgeMap) {
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] && (badgeKey(ids[i]) === key || matchApp(ids[i], key))) return badgeMap[key];
    }
  }
  return null;
}

function hasUrgentWindow(item, urgentWindows) {
  if (!item || !Array.isArray(urgentWindows) || urgentWindows.length === 0) return false;
  var wins = toArray(item.windows);
  for (var i = 0; i < wins.length; i++) {
    if (urgentWindows.indexOf(wins[i]) >= 0) return true;
  }
  return false;
}

function windowMetadata(win, metadata) {
  for (var i = 0; i < metadata.length; i++) {
    if (metadata[i].window === win) return metadata[i];
  }
  return null;
}

// Keep the original Wayland handles so focus and close always target one window.
function filterWindows(windows, metadata, scope, monitorName, workspaceId) {
  var list = toArray(windows);
  if (scope !== "monitor" && scope !== "workspace") return list;
  return list.filter(function(win) {
    var info = windowMetadata(win, metadata);
    if (!info || !monitorName || info.monitorName !== monitorName) return false;
    return scope === "monitor" || (workspaceId !== null && workspaceId !== undefined
      && info.workspaceId === workspaceId);
  });
}

function pickerRows(item, metadata) {
  return toArray(item ? item.windows : []).filter(function(win) { return !!win; }).map(function(win) {
    var info = windowMetadata(win, metadata);
    return {
      window: win,
      title: String(win.title || (item && item.name) || "Untitled window"),
      location: info ? ((info.workspaceName ? "Workspace " + info.workspaceName : "")
        + (info.monitorName ? " · " + info.monitorName : "")) : "",
      active: !!win.activated
    };
  });
}

function activateWindow(win) {
  if (!win || typeof win.activate !== "function") return;
  try { win.activate(); } catch (e) {}
}

var defaultPinnedApps = [
  "vivaldi-stable",
  "Alacritty",
  "org.gnome.Nautilus",
  "dev.zed.Zed",
  "elecwhat",
  "Discord",
  "obsidian"
];

// Qt exposes QQmlListProperty/QList values as array-like sequences. They are
// indexable from QML JavaScript but Array.isArray() returns false, so treating
// only native arrays as valid silently drops every open window.
function toArray(values) {
  if (!values) return [];
  if (Array.isArray(values)) return values;

  var result = [];
  var length = Number(values.length);
  if (!isNaN(length) && length >= 0) {
    for (var i = 0; i < length; i++) result.push(values[i]);
  }
  return result;
}

// Preserve release channels: separate installations must not share windows or pins.
var commonSuffixes = /-(stable|bin|git|oss|browser|desktop|electron|community)$/i;

var desktopSuffixRe = /\.desktop$/i;
var nonAlnumRe = /[^a-z0-9]/g;

function cleanAppId(id) {
  if (!id) return "";
  var s = String(id).trim().toLowerCase().replace(desktopSuffixRe, "");
  // For reverse-DNS identifiers (e.g. org.gnome.Nautilus, io.github.user.app, dev.zed.Zed, com.spotify.Client)
  if (s.indexOf(".") !== -1) {
    var parts = s.split(".");
    var last = parts[parts.length - 1];
    if ((last === "client" || last === "desktop" || last === "app" || last === "ui") && parts.length > 2) {
      s = parts[parts.length - 2];
    } else {
      s = last;
    }
  }
  return s.replace(commonSuffixes, "").replace(nonAlnumRe, "");
}

function normalizeId(id) {
  if (!id) return "";
  return cleanAppId(id) || String(id).toLowerCase().replace(nonAlnumRe, "");
}

function matchApp(appIdA, appIdB) {
  if (!appIdA || !appIdB) return false;
  var a = normalizeId(appIdA);
  var b = normalizeId(appIdB);
  if (!a || !b) return false;
  if (a === b) return true;

  // Exact raw compare without .desktop
  var rawA = String(appIdA).toLowerCase().replace(desktopSuffixRe, "");
  var rawB = String(appIdB).toLowerCase().replace(desktopSuffixRe, "");
  if (rawA === rawB) return true;

  // Terminal aliases & generic fallback
  var termNames = ["alacritty", "kitty", "ghostty", "foot", "terminal", "orgomarchyagent", "agent"];
  if ((a === "terminal" && termNames.indexOf(b) !== -1) || (b === "terminal" && termNames.indexOf(a) !== -1)) return true;
  if ((a === "orgomarchyagent" || a === "agent") && b === "foot") return true;
  if ((b === "orgomarchyagent" || b === "agent") && a === "foot") return true;

  // Browser fallbacks
  var browserNames = ["vivaldistable", "vivaldi", "chromium", "googlechrome", "firefox", "brave"];
  if (a === "browser" && browserNames.indexOf(b) !== -1) return true;
  if (b === "browser" && browserNames.indexOf(a) !== -1) return true;

  return false;
}

// Omarchy web apps run in Chromium with a window class such as
// "chrome-youtube.com__-Default"; their desktop entry runs
// "omarchy-launch-webapp https://youtube.com/". Match the two by site host.
// All regular expressions live at module level: rebuildDock runs on every
// window event, and allocating fresh RegExp objects inside those loops churns
// the QML JavaScript heap (a QV4 GC crash was traced to exactly that).
var webAppClassRe = /^(?:chrome|chromium|brave|msedge|vivaldi|google-chrome)-([^_]+)__/i;
var urlHostRe = /^[a-z][a-z0-9+.-]*:\/\/([^\/:?#]+)/i;
var wwwPrefixRe = /^www\./;
var webappExecRe = /omarchy-launch-webapp\s+["']?([^\s"']+)/;
var appFlagRe = /--app=["']?([^\s"']+)/;

function hostFromUrl(url) {
  var m = String(url || "").match(urlHostRe);
  return m ? m[1].toLowerCase().replace(wwwPrefixRe, "") : "";
}

function webAppHostFromClass(cls) {
  var m = String(cls || "").match(webAppClassRe);
  return m ? m[1].toLowerCase().replace(wwwPrefixRe, "") : "";
}

// Cache: desktop entry id -> web-app host ("" when it is not a web app).
var entryHostCache = Object.create(null);

function webAppHostFromEntry(entry) {
  if (!entry) return "";
  var key = String(entry.id || "");
  if (key && key in entryHostCache) return entryHostCache[key];
  var exec = String(entry.execString || "");
  var host = "";
  var m = exec.match(webappExecRe);
  if (m) host = hostFromUrl(m[1]);
  else {
    m = exec.match(appFlagRe);
    if (m) host = hostFromUrl(m[1]);
  }
  if (key) entryHostCache[key] = host;
  return host;
}

function findWebAppEntry(desktopEntries, cls) {
  var host = webAppHostFromClass(cls);
  if (!host || !desktopEntries || !desktopEntries.applications) return null;
  var apps = toArray(desktopEntries.applications.values);
  for (var i = 0; i < apps.length; i++) {
    if (apps[i] && webAppHostFromEntry(apps[i]) === host) return apps[i];
  }
  return null;
}

var dirPrefixRe = /^.*\//;
var whitespaceRe = /\s+/;
var genericExes = ["python", "python3", "bash", "sh", "flatpak", "uwsm", "uwsm-app", "electron"];

function entryAliases(entry, fallbackId) {
  var aliases = [fallbackId];
  if (!entry) return aliases;

  aliases.push(entry.id || "");
  aliases.push(entry.startupClass || "");
  aliases.push(entry.name || "");

  var command = toArray(entry.command);
  if (command.length > 0) {
    var cmdExe = String(command[0]).replace(dirPrefixRe, "");
    if (genericExes.indexOf(cmdExe) === -1) aliases.push(cmdExe);
  }
  if (entry.execString) {
    var rawExe = String(entry.execString).split(whitespaceRe)[0].replace(dirPrefixRe, "");
    if (genericExes.indexOf(rawExe) === -1) aliases.push(rawExe);
  }
  return aliases;
}

function windowAliases(win) {
  if (!win) return [];
  return [
    win.appId || "",
    win.initialClass || "",
    win.class || ""
  ];
}

function entryMatchesWindow(entry, fallbackId, win) {
  var appAliases = entryAliases(entry, fallbackId);
  var winAliases = windowAliases(win);
  var host = webAppHostFromEntry(entry);
  if (host) {
    for (var h = 0; h < winAliases.length; h++) {
      if (webAppHostFromClass(winAliases[h]) === host) return true;
    }
  }
  for (var a = 0; a < appAliases.length; a++) {
    for (var w = 0; w < winAliases.length; w++) {
      if (matchApp(appAliases[a], winAliases[w])) return true;
    }
  }
  return false;
}

function findDesktopEntry(desktopEntries, appId) {
  if (!desktopEntries || !appId) return null;
  var id = String(appId);

  var web = findWebAppEntry(desktopEntries, id);
  if (web) return web;

  var entry = desktopEntries.byId ? desktopEntries.byId(id) : null;
  if (entry) return entry;

  entry = desktopEntries.byId ? desktopEntries.byId(id.toLowerCase()) : null;
  if (entry) return entry;

  if (desktopEntries.heuristicLookup) {
    entry = desktopEntries.heuristicLookup(id);
    if (entry) return entry;
  }

  if (desktopEntries.applications) {
    var apps = toArray(desktopEntries.applications.values);
    for (var i = 0; i < apps.length; i++) {
      var item = apps[i];
      if (item && item.id && matchApp(item.id, id)) {
        return item;
      }
    }
  }

  return null;
}

function resolveIcon(iconName, appLibrary, Quickshell) {
  var name = String(iconName || "").trim();
  if (!name) {
    return (Quickshell && typeof Quickshell.iconPath === "function")
      ? Quickshell.iconPath("application-x-executable", true)
      : "";
  }
  if (name.indexOf("file://") === 0 || name.indexOf("image://") === 0) {
    return name;
  }
  if (name.charAt(0) === "/") {
    return "file://" + name;
  }
  if (appLibrary && typeof appLibrary.iconSource === "function") {
    var src = appLibrary.iconSource(name);
    if (src && src.length > 0) return src;
  }
  if (Quickshell && typeof Quickshell.iconPath === "function") {
    var themed = Quickshell.iconPath(name, true);
    if (themed && themed.length > 0) return themed;
    return Quickshell.iconPath("application-x-executable", true);
  }
  return name;
}

function buildDockItems(toplevels, desktopEntries, appLibrary, Quickshell, customPinned) {
  var pinnedConfig = Array.isArray(customPinned)
    ? customPinned
    : defaultPinnedApps;

  var windowList = toArray(toplevels);
  var matchedWindows = {};

  var pinnedList = [];
  for (var i = 0; i < pinnedConfig.length; i++) {
    var pin = pinnedConfig[i];
    var pinId = typeof pin === "string" ? pin : (pin.id || "");
    if (!pinId) continue;

    var entry = findDesktopEntry(desktopEntries, pinId);
    var displayName = (entry && entry.name) ? entry.name : (pin.name || pinId);
    var rawIcon = (entry && entry.icon) ? entry.icon : (pin.icon || pinId);
    var resolvedIcon = resolveIcon(rawIcon, appLibrary, Quickshell);

    var appWindows = [];
    var isFocused = false;

    for (var w = 0; w < windowList.length; w++) {
      if (matchedWindows[w]) continue;
      var win = windowList[w];
      if (!win) continue;
      if (entryMatchesWindow(entry, pinId, win)) {
        appWindows.push(win);
        matchedWindows[w] = true;
        if (win.activated) {
          isFocused = true;
        }
      }
    }

    pinnedList.push({
      key: "pin_" + pinId,
      id: (entry && entry.id) ? entry.id : pinId,
      name: displayName,
      icon: resolvedIcon,
      desktopEntry: entry,
      isPinned: true,
      isRunning: appWindows.length > 0,
      isFocused: isFocused,
      windowCount: appWindows.length,
      windows: appWindows
    });
  }

  // Group remaining unpinned running windows
  var runningMap = Object.create(null);
  var runningOrder = [];

  for (var k = 0; k < windowList.length; k++) {
    if (matchedWindows[k]) continue;
    var toplevel = windowList[k];
    if (!toplevel) continue;
    if (toplevel.parent) continue;

    var rawAppId = String(toplevel.appId || toplevel.initialClass || toplevel.class || "").trim();
    if (!rawAppId) continue;
    var dEntry = findDesktopEntry(desktopEntries, rawAppId);
    var normKey = normalizeId((dEntry && dEntry.id) ? dEntry.id : rawAppId);
    if (!normKey) normKey = rawAppId || ("win_" + k);

    if (!runningMap[normKey]) {
      var name = (dEntry && dEntry.name) ? dEntry.name : (toplevel.title || rawAppId);
      var icn = (dEntry && dEntry.icon) ? dEntry.icon : rawAppId;
      var iconPath = resolveIcon(icn, appLibrary, Quickshell);

      runningMap[normKey] = {
        key: "run_" + normKey,
        id: (dEntry && dEntry.id) ? dEntry.id : rawAppId,
        name: name,
        icon: iconPath,
        desktopEntry: dEntry,
        isPinned: false,
        isRunning: true,
        isFocused: false,
        windowCount: 0,
        windows: []
      };
      runningOrder.push(normKey);
    }

    runningMap[normKey].windows.push(toplevel);
    runningMap[normKey].windowCount++;
    if (toplevel.activated) {
      runningMap[normKey].isFocused = true;
    }
  }

  var unpinnedList = [];
  for (var r = 0; r < runningOrder.length; r++) {
    unpinnedList.push(runningMap[runningOrder[r]]);
  }

  return {
    pinned: pinnedList,
    unpinned: unpinnedList,
    totalItems: pinnedList.length + unpinnedList.length
  };
}

function resolveLaunchId(item, desktopEntries) {
  if (!item) return "";
  if (item.desktopEntry && item.desktopEntry.id) {
    return String(item.desktopEntry.id).replace(desktopSuffixRe, "");
  }
  var rawId = String(item.id || "").replace(desktopSuffixRe, "");
  if (!rawId) return "";
  if (desktopEntries) {
    var entry = findDesktopEntry(desktopEntries, rawId);
    if (entry && entry.id) {
      return String(entry.id).replace(desktopSuffixRe, "");
    }
  }
  return rawId;
}

function handleItemClick(item, qs, appLibrary, desktopEntries) {
  if (!item) return;

  if (item.isRunning && item.windows && item.windows.length > 0) {
    var windows = item.windows;
    var activeIdx = -1;
    for (var i = 0; i < windows.length; i++) {
      if (windows[i] && windows[i].activated) {
        activeIdx = i;
        break;
      }
    }
    // If one of its windows is already active:
    // - If multiple windows exist, cycle to the next window.
    // - If only 1 window exists, leave it in place.
    if (activeIdx !== -1) {
      if (windows.length > 1) {
        var nextIdx = (activeIdx + 1) % windows.length;
        if (windows[nextIdx] && typeof windows[nextIdx].activate === "function") {
          windows[nextIdx].activate();
        }
      }
      return;
    }
    for (var j = 0; j < windows.length; j++) {
      if (windows[j] && typeof windows[j].activate === "function") {
        windows[j].activate();
        return;
      }
    }
    return;
  }

  var launchId = resolveLaunchId(item, desktopEntries);
  if (!launchId) return;

  var appName = item.name || launchId;

  if (appLibrary && typeof appLibrary.launch === "function") {
    try {
      appLibrary.launch(launchId, appName);
      return;
    } catch (e) {}
  }

  if (qs && typeof qs.execDetached === "function") {
    qs.execDetached(["/usr/bin/uwsm-app", "--", "/usr/bin/gtk-launch", launchId + ".desktop"]);
  }
}

function closeAppWindow(item) {
  if (!item || !item.windows || item.windows.length === 0) return;
  var target = null;
  for (var i = 0; i < item.windows.length; i++) {
    var win = item.windows[i];
    if (win && typeof win.close === "function") {
      if (!target) target = win;
      if (win.activated) {
        target = win;
        break;
      }
    }
  }
  // Close the focused window, or the first available window if this app is
  // unfocused. A failed close must never cascade into closing other windows.
  if (target) {
    try { target.close(); } catch (e) {}
  }
}

// Raised cosine bell: continuous slope at both ends, with a wider shoulder
// than smoothstep. It makes adjacent icons participate in the magnification
// wave instead of snapping between a large icon and nearly resting neighbors.
function scaleFromDistance(dist, maxScale, radius) {
  var limit = radius || 140;
  var topScale = maxScale || 1.6;
  if (dist >= limit) return 1.0;
  var norm = dist / limit;
  var cosine = Math.cos(norm * Math.PI / 2);
  return 1.0 + (topScale - 1.0) * cosine * cosine;
}

// Return transform-only horizontal offsets for a centered row of fixed slots.
// Each magnified icon contributes visual width; half is distributed to either
// side so the wave stays centered and neighboring icons never collide.
function computeMagnifiedOffsets(scales, baseSize, expansionRatio) {
  var values = Array.isArray(scales) ? scales : [];
  var ratio = typeof expansionRatio === "number" ? expansionRatio : 0.82;
  var extras = [];
  var totalExtra = 0;

  for (var i = 0; i < values.length; i++) {
    var extra = Math.max(0, (Number(values[i]) - 1.0) * baseSize * ratio);
    extras.push(extra);
    totalExtra += extra;
  }

  var offsets = [];
  var cursor = -totalExtra / 2;
  for (var j = 0; j < extras.length; j++) {
    offsets.push(cursor + extras[j] / 2);
    cursor += extras[j];
  }
  offsets.totalExtra = totalExtra;
  return offsets;
}

// Calculate fixed unmagnified baseline coordinates
function computeBaselineCenters(baseSize, spacing, pad, pinnedCount, unpinnedCount, sepWidth, recentCount, extraCount) {
  recentCount = typeof recentCount === "number" ? recentCount : 0;
  extraCount = typeof extraCount === "number" ? extraCount : 0;
  var curX = pad;
  // A divider occupies its own width plus one spacing gap on its far side.
  sepWidth = (typeof sepWidth === "number" ? sepWidth : separatorWidth) + spacing;

  // Applications launcher and its following separator
  var launcherCenter = curX + baseSize / 2;
  curX += baseSize + spacing + sepWidth;

  // Pinned items
  var pinnedCenters = [];
  for (var p = 0; p < pinnedCount; p++) {
    pinnedCenters.push(curX + baseSize / 2);
    curX += baseSize + spacing;
  }

  // Unpinned items
  var unpinnedCenters = [];
  if (unpinnedCount > 0) {
    if (pinnedCount > 0) {
      curX += sepWidth;
    }
    for (var u = 0; u < unpinnedCount; u++) {
      unpinnedCenters.push(curX + baseSize / 2);
      curX += baseSize + spacing;
    }
  }

  // Recent apps (neither pinned nor running), after their own divider
  var recentCenters = [];
  if (recentCount > 0) {
    if (pinnedCount + unpinnedCount > 0) {
      curX += sepWidth;
    }
    for (var r = 0; r < recentCount; r++) {
      recentCenters.push(curX + baseSize / 2);
      curX += baseSize + spacing;
    }
  }

  // Folders and the trash, after their own divider
  var extraCenters = [];
  if (extraCount > 0) {
    if (pinnedCount + unpinnedCount + recentCount > 0) {
      curX += sepWidth;
    }
    for (var x = 0; x < extraCount; x++) {
      extraCenters.push(curX + baseSize / 2);
      curX += baseSize + spacing;
    }
  }

  var totalBaseWidth = curX - spacing + pad;

  return {
    launcher: launcherCenter,
    pinned: pinnedCenters,
    unpinned: unpinnedCenters,
    recent: recentCenters,
    extras: extraCenters,
    totalBaseWidth: totalBaseWidth
  };
}

// ---------- app drawer ----------

function drawerApps(desktopEntries, appLibrary, Quickshell, query) {
  var q = String(query || "").trim().toLowerCase();
  var apps = desktopEntries && desktopEntries.applications ? toArray(desktopEntries.applications.values) : [];
  var out = [];
  for (var i = 0; i < apps.length; i++) {
    var e = apps[i];
    if (!e || e.noDisplay) continue;
    var name = String(e.name || "");
    if (!name) continue;
    if (q) {
      var hay = (name + " " + String(e.genericName || "") + " " + String(e.comment || "")).toLowerCase();
      if (hay.indexOf(q) < 0) continue;
    }
    out.push({
      id: e.id,
      name: name,
      icon: resolveIcon(e.icon, appLibrary, Quickshell),
      desktopEntry: e,
      isRunning: false,
      windows: []
    });
  }
  out.sort(function(a, b) {
    var an = a.name.toLowerCase(), bn = b.name.toLowerCase();
    if (q) {
      var ap = an.indexOf(q) === 0 ? 0 : 1, bp = bn.indexOf(q) === 0 ? 0 : 1;
      if (ap !== bp) return ap - bp;
    }
    return an < bn ? -1 : an > bn ? 1 : 0;
  });
  return out;
}

// ---------- recent apps ----------

// Items for the "recent" group: recently launched apps that are neither
// pinned nor currently running, most recent first, at most `max`.
function buildRecentItems(recentIds, data, desktopEntries, appLibrary, Quickshell, max) {
  var out = [];
  var ids = Array.isArray(recentIds) ? recentIds : [];
  var taken = [].concat(data.pinned || [], data.unpinned || []);
  for (var i = 0; i < ids.length && out.length < max; i++) {
    var id = String(ids[i] || "");
    if (!id) continue;
    var clash = false;
    for (var t = 0; t < taken.length; t++) {
      if (taken[t] && (taken[t].id === id || matchApp(taken[t].id, id))) { clash = true; break; }
    }
    if (clash) continue;
    var entry = findDesktopEntry(desktopEntries, id);
    if (!entry) continue;
    out.push({
      key: "recent_" + id,
      id: entry.id || id,
      name: entry.name || id,
      icon: resolveIcon(entry.icon, appLibrary, Quickshell),
      desktopEntry: entry,
      isPinned: false,
      isRunning: false,
      isFocused: false,
      windowCount: 0,
      windows: []
    });
  }
  return out;
}

// Put `id` at the front of the recent list, dropping earlier duplicates.
function pushRecent(recentIds, id, cap) {
  var list = [String(id)];
  var ids = Array.isArray(recentIds) ? recentIds : [];
  for (var i = 0; i < ids.length && list.length < cap; i++) {
    if (ids[i] !== id && !matchApp(ids[i], id)) list.push(ids[i]);
  }
  return list;
}

// Corner radius ratio for a tile shape.
function tileRadiusRatio(shape) {
  if (shape === "circle") return 0.5;
  if (shape === "square") return 0.12;
  return 0.24;
}
