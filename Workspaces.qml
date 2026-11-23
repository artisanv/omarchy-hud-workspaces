import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Effects
import Qt.labs.folderlistmodel
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  // The bar injects the entry id here on load; set to our own id (not the
  // stock widget's) so nothing keyed on it before then is misrouted.
  moduleName: "swordfish.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Display order, which a pointer drag reorders and `omarchy bar set ... order`
  // persists in shell.json. Saved ids come first; 1-5 are always present (the
  // widget's baseline); any other live workspace lands after them in numeric
  // order. Saved ids above 5 whose workspace no longer exists fall out, so the
  // list self-heals instead of accumulating ghosts.
  function computeWorkspaceIds() {
    var seen = {}
    var ids = []
    var live = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var lid = values[i].id
      if (lid > 0 && lid <= 10) live.push(lid)
    }

    var hidden = root.hiddenSet
    var kept = root.keptSet
    var order = root.localOrder !== null ? root.localOrder : root.setting("order", [])
    // `qs ipc call` expands JSON-array arguments into separate parameters, so
    // persistOrder stores the list as its JSON text in a string; accept both
    // forms.
    if (typeof order === "string") {
      try {
        order = JSON.parse(order)
      } catch (e) {
        order = []
      }
    }
    if (Array.isArray(order)) {
      for (var j = 0; j < order.length; j++) {
        var oid = Number(order[j])
        if (!isFinite(oid) || Math.floor(oid) !== oid || oid < 1 || oid > 10) continue
        if (seen[oid]) continue
        if ((oid > 5 || hidden[oid]) && !kept[oid] && live.indexOf(oid) === -1) continue
        seen[oid] = true
        ids.push(oid)
      }
    }

    for (var d = 1; d <= 5; d++) {
      if (hidden[d] && live.indexOf(d) === -1) continue
      if (!seen[d]) {
        seen[d] = true
        ids.push(d)
      }
    }

    live.sort(function(left, right) { return left - right })
    for (var k = 0; k < live.length; k++) {
      if (!seen[live[k]]) {
        seen[live[k]] = true
        ids.push(live[k])
      }
    }

    return ids
  }

  // The Repeater rebuilds every card whenever its model array is replaced, so
  // `displayIds` is only reassigned when the id list really changes: the
  // config echo of an order the widget already shows (or a labels edit) is a
  // no-op. `localOrder` shows a dropped order immediately, before the
  // persisted value round-trips through shell.json.
  property var localOrder: null

  // Deleted workspaces: kept off the bar unless something is on them
  // (e.g. Super+3 recreates 3). Saved as JSON text under `hidden`.
  property var localHidden: null
  readonly property var savedHidden: {
    var raw = root.setting("hidden", [])
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = []
      }
    }
    return Array.isArray(raw) ? raw.map(Number).filter(function(n) { return n >= 1 && n <= 10 }) : []
  }
  onSavedHiddenChanged: root.localHidden = null
  readonly property var hiddenList: root.localHidden !== null ? root.localHidden : root.savedHidden
  readonly property var hiddenSet: {
    var set = {}
    for (var i = 0; i < root.hiddenList.length; i++) set[root.hiddenList[i]] = true
    return set
  }
  // Closed workspaces: their apps were closed but the card stays on the bar
  // (name, emoji, colour, place) even with nothing on it, until it is
  // deleted. Saved as JSON text under `kept`.
  property var localKept: null
  readonly property var savedKept: {
    var raw = root.setting("kept", [])
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = []
      }
    }
    return Array.isArray(raw) ? raw.map(Number).filter(function(n) { return n >= 1 && n <= 10 }) : []
  }
  onSavedKeptChanged: root.localKept = null
  readonly property var keptList: root.localKept !== null ? root.localKept : root.savedKept
  readonly property var keptSet: {
    var set = {}
    for (var i = 0; i < root.keptList.length; i++) set[root.keptList[i]] = true
    return set
  }

  readonly property var savedOrder: root.setting("order", [])
  onSavedOrderChanged: root.localOrder = null

  readonly property var computedIds: root.computeWorkspaceIds()
  property var displayIds: []
  onComputedIdsChanged: root.syncIds()

  function syncIds() {
    var next = root.computedIds
    var cur = root.displayIds
    if (next.length === cur.length) {
      var same = true
      for (var i = 0; i < next.length && same; i++) same = next[i] === cur[i]
      if (same) return
    }
    root.displayIds = next
  }

  function workspaceIds() {
    return root.displayIds
  }

  // ws-step (next to this file) sets the workspace animation's direction from
  // bar positions before switching; Hyprland would otherwise slide by
  // workspace number, backwards once the bar is reordered.
  readonly property string stepScript: decodeURIComponent(
    String(Qt.resolvedUrl("ws-step")).replace(/^file:\/\//, ""))

  function focusWorkspace(id) {
    if (!root.bar) return
    Quickshell.execDetached([root.stepScript, "goto", String(id)])
  }

  // Workspace transition and swipe settings (applied by ws-step), saved in
  // the widget's shell.json entry. Right-click the + button to change them.
  readonly property var transitions: [
    { key: "glide", name: "Glide", detail: "Slide part-way, fading through" },
    { key: "slide", name: "Slide", detail: "Full slide, like turning pages" },
    { key: "verticalglide", name: "Rise", detail: "Vertical glide with a fade" },
    { key: "vertical", name: "Lift", detail: "Full vertical slide" },
    { key: "fade", name: "Crossfade", detail: "Dissolve, no movement" },
    { key: "none", name: "Instant", detail: "No animation" }
  ]
  readonly property var transitionCurves: [
    { key: "smooth", name: "Smooth" },
    { key: "snappy", name: "Snappy" },
    { key: "bouncy", name: "Bouncy" },
    { key: "gentle", name: "Gentle" },
    { key: "easeinout", name: "Ease in-out" },
    { key: "linear", name: "Linear" }
  ]

  // v1.6 stored "slidefade" and a speed preset; read those as their
  // v1.7 equivalents (the presets as the durations they actually ran at).
  readonly property string transition: {
    var t = String(root.setting("transition", "glide"))
    return t === "slidefade" ? "glide" : t
  }
  readonly property string transitionCurve: String(root.setting("transitionCurve", "smooth"))
  readonly property int transitionDuration: {
    var ms = Number(root.setting("transitionDuration", NaN))
    if (isFinite(ms)) return Math.max(100, Math.min(1500, Math.round(ms)))
    var preset = String(root.setting("transitionSpeed", "normal"))
    return preset === "slow" ? 250 : preset === "fast" ? 700 : 400
  }
  readonly property int transitionDistance: {
    var d = Number(root.setting("transitionDistance", NaN))
    if (isFinite(d)) return Math.max(5, Math.min(100, Math.round(d)))
    return String(root.setting("transition", "glide")) === "slidefade" ? 60 : 20
  }
  readonly property bool usesDistance: root.transition === "glide" || root.transition === "verticalglide"
  readonly property bool swipeNatural: root.setting("swipeNatural", true) !== false
    && root.setting("swipeNatural", true) !== "false"
  readonly property bool wrapSwipe: root.setting("wrapSwipe", false) === true
    || root.setting("wrapSwipe", false) === "true"
  readonly property bool wrapScroll: root.setting("wrapScroll", true) !== false
    && root.setting("wrapScroll", true) !== "false"
  // Super+<n> by bar position (read by ws-step; needs the binds in
  // Hyprland integration, see ws-setup).
  readonly property bool keysFollowBar: root.setting("keysFollowBar", true) !== false
    && root.setting("keysFollowBar", true) !== "false"

  onTransitionChanged: root.applyTransition()
  onTransitionCurveChanged: root.applyTransition()
  onTransitionDurationChanged: root.applyTransition()
  onTransitionDistanceChanged: root.applyTransition()

  function applyTransition() {
    Quickshell.execDetached([root.stepScript, "apply"])
  }

  // ---- Writing shell.json ----
  // Every write goes through this one queue and runs strictly after the
  // previous one, so two quick edits (a label and a reorder, say) can't
  // read-modify-write shell.json at the same time and lose one of them.
  // Settings are written inside the shell (bar.shell.updateEntryInline, as
  // the stock clock does), never as command-line arguments, which other
  // local users can read: names, folders and window titles stay out of
  // `ps`. Shell commands in the queue (ws-step apply, ws-settings) carry no
  // stored data. After the queue drains, the widget's entry is copied to a
  // backup file (see settingsBackup).
  property var writeQueue: []

  // One setting to write; `json` means `value` is JSON text (a number or
  // boolean) rather than a plain string.
  function barSet(key, value, json) {
    var v = String(value)
    if (json) {
      try {
        v = JSON.parse(v)
      } catch (e) {
        v = String(value)
      }
    }
    return { key: String(key), value: v }
  }

  function persist(steps) {
    if (!root.bar) return
    var list = Array.isArray(steps) ? steps : [steps]
    if (list.length === 0) return
    root.writeQueue = root.writeQueue.concat([list])
    root.pumpWrites()
  }

  function pumpWrites() {
    if (shellWriter.running || writeSettle.running) return
    if (root.writeQueue.length === 0) {
      if (root.backupPending) root.writeBackup()
      return
    }
    var steps = root.writeQueue[0]
    root.writeQueue = root.writeQueue.slice(1)
    root.backupPending = true
    var sets = steps.filter(function(x) { return typeof x === "object" })
    var cmds = steps.filter(function(x) { return typeof x === "string" })
    if (sets.length > 0 && !root.writeSettings(sets)) {
      Qt.callLater(root.pumpWrites)
      return
    }
    if (cmds.length === 0) {
      Qt.callLater(root.pumpWrites)
      return
    }
    shellWriter.command = ["bash", "-c", cmds.join(" && ")]
    // Give the shell a moment to save shell.json; ws-step reads the file.
    if (sets.length > 0) writeSettle.restart()
    else shellWriter.running = true
  }

  Timer {
    id: writeSettle
    interval: 250
    onTriggered: shellWriter.running = true
  }

  // Apply settings to the widget's entry: locally first (so the next write
  // builds on it), then through the shell. If this shell has no such API,
  // ws-settings writes them, reading the values from stdin.
  function writeSettings(sets) {
    var entry = {}
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    var changes = {}
    for (var i = 0; i < sets.length; i++) {
      entry[sets[i].key] = sets[i].value
      changes[sets[i].key] = sets[i].value
    }
    root.settings = entry
    var api = root.bar && root.bar.shell
    if (api && typeof api.updateEntryInline === "function") {
      api.updateEntryInline(root.moduleName, entry)
      return true
    }
    root.logLine("shell has no updateEntryInline; writing settings with ws-settings")
    settingsStdin.payload = JSON.stringify(changes)
    settingsStdin.running = true
    return true
  }

  Process {
    id: settingsStdin
    property string payload: ""
    command: [root.settingsScript, "apply"]
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
    onExited: function(code) {
      if (code !== 0) root.logLine("ws-settings apply exited " + code)
    }
  }

  Process {
    id: shellWriter
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text).trim() !== "") root.logLine("shell.json write: " + String(text).trim())
    }
    onExited: function(code) {
      if (code !== 0) root.logLine("shell.json write exited " + code)
      Qt.callLater(root.pumpWrites)
    }
  }

  // One line in $XDG_STATE_HOME/hud-workspaces/log, shared with ws-step and
  // ws-room, so failures leave a trace instead of vanishing.
  readonly property string logFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") +
    "/hud-workspaces/log"

  // The message goes over stdin (never as an argument) to a log only you
  // can read.
  function logLine(msg) {
    var p = logWriterComponent.createObject(root, { payload: String(msg).replace(/[\r\n]+/g, " ").slice(0, 500) })
    if (p) p.running = true
  }

  Component {
    id: logWriterComponent
    Process {
      property string payload: ""
      command: ["sh", "-c",
        'umask 077; d=$(dirname -- "$1"); mkdir -p -- "$d" && chmod 700 -- "$d"; ' +
        'IFS= read -r m; printf "%s widget %s\\n" "$(date "+%F %T")" "$m" >> "$1"; chmod 600 -- "$1"', "sh", root.logFile]
      stdinEnabled: true
      onStarted: {
        write(payload + "\n")
        payload = ""
      }
      onExited: destroy()
    }
  }

  // ---- Backups, integration status, update checks ----
  readonly property string settingsScript: decodeURIComponent(
    String(Qt.resolvedUrl("ws-settings")).replace(/^file:\/\//, ""))
  readonly property string setupScript: decodeURIComponent(
    String(Qt.resolvedUrl("ws-setup")).replace(/^file:\/\//, ""))
  property bool backupPending: false

  function writeBackup() {
    root.backupPending = false
    Quickshell.execDetached([root.settingsScript, "backup"])
  }

  // ws-setup status / ws-settings status / Hyprland version, refreshed when
  // the panel opens and a few seconds after start.
  property var integration: ({})
  property var settingsState: ({})
  property string hyprVersion: ""
  property string integrationNotice: ""
  // Window drop wanted by the next Install (the toggle, before installing).
  property bool dropChoice: true
  readonly property string testedHyprland: "0.56"
  readonly property bool hyprUntested: root.hyprVersion !== "" &&
    root.hyprVersion.replace(/^v/, "").split(".").slice(0, 2).join(".") !== root.testedHyprland
  property bool warnAfterCheck: false

  function refreshStatus(warn) {
    if (statusProc.running) return
    root.warnAfterCheck = warn === true
    statusProc.command = ["bash", "-c",
      '"$1" status; "$2" status; hyprctl version -j 2>/dev/null | jq -r .tag',
      "bash", root.setupScript, root.settingsScript]
    statusProc.running = true
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).split("\n")
        try { root.integration = JSON.parse(lines[0]) } catch (e) { root.integration = ({}) }
        try { root.settingsState = JSON.parse(lines[1]) } catch (e) { root.settingsState = ({}) }
        root.hyprVersion = String(lines[2] || "").trim()
        if (root.warnAfterCheck) root.warnIfBroken()
      }
    }
  }

  Timer {
    id: startupCheck
    interval: 4000
    onTriggered: {
      root.refreshStatus(true)
      root.writeBackup()
    }
  }

  // Once per boot: tell the user if an update undid the Hyprland edits or
  // wiped the settings, instead of things silently behaving differently.
  function warnIfBroken() {
    var msgs = []
    var ig = root.integration
    if (ig.everInstalled === true && ig.ok !== true)
      msgs.push("The Hyprland keys/swipe setup was changed (an update?). Right-click + \u2192 Settings \u2192 Re-apply.")
    if (root.settingsState.looksReset === true)
      msgs.push("Your cards and rooms look reset. Right-click + \u2192 Settings \u2192 Restore backup.")
    if (msgs.length === 0) return
    var flag = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hud-workspaces-warned"
    Quickshell.execDetached(["sh", "-c",
      '[ -e "$1" ] && exit 0; : > "$1"; notify-send -a "HUD Workspaces" "HUD Workspaces" "$2"',
      "sh", flag, msgs.join("\n")])
    root.logLine("warned: " + msgs.join(" | "))
  }

  // Install / re-apply / remove the Hyprland integration (ws-setup).
  function runSetup(args) {
    if (setupProc.running) return
    root.integrationNotice = "Working\u2026"
    setupProc.command = [root.setupScript].concat(args)
    setupProc.running = true
  }

  Process {
    id: setupProc
    stdout: StdioCollector { id: setupOut; waitForEnd: true }
    stderr: StdioCollector { id: setupErr; waitForEnd: true }
    onExited: function(code) {
      var out = String(code === 0 ? setupOut.text : setupErr.text).trim().split("\n")[0]
      root.integrationNotice = out !== "" ? out : (code === 0 ? "Done." : "Failed (see the log).")
      root.refreshStatus(false)
    }
  }

  // Export (reads only) / import and restore (queued writes).
  property string backupNotice: ""

  function exportSettings() {
    if (exportProc.running) return
    exportProc.command = [root.settingsScript, "export"]
    exportProc.running = true
  }

  Process {
    id: exportProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text).trim()
        root.backupNotice = path !== "" ? "Saved to " + path.replace(Quickshell.env("HOME"), "~") : "Export failed."
      }
    }
  }

  function importSettings() {
    // The panel would sit on top of the file chooser.
    root.settingsOpen = false
    root.persist('f=$(omarchy-file-select --title "Import HUD Workspaces settings" --extensions "json") || exit 0; ' +
      Util.shellQuote(root.settingsScript) + ' import "$f" && ' + Util.shellQuote(root.stepScript) + " apply")
  }

  function restoreSettings() {
    root.backupNotice = "Restoring\u2026"
    root.persist(Util.shellQuote(root.settingsScript) + " restore && " + Util.shellQuote(root.stepScript) + " apply")
    Qt.callLater(function() { root.refreshStatus(false) })
  }

  // A Lua string literal. The one escaper for everything sent to
  // `hyprctl dispatch` / `eval` from the widget.
  function luaQuote(value) {
    var out = ""
    var str = String(value)
    for (var i = 0; i < str.length; i++) {
      var ch = str.charAt(i)
      var code = str.charCodeAt(i)
      if (ch === "\\") out += "\\\\"
      else if (ch === '"') out += '\\"'
      else if (ch === "\n") out += "\\n"
      else if (ch === "\r") out += "\\r"
      else if (ch === "\t") out += "\\t"
      else if (code < 32 || code === 127) continue
      else out += ch
    }
    return '"' + out + '"'
  }

  function saveSetting(key, value, json) {
    if (!root.bar) return
    // Apply only after the setting is written, since ws-step reads shell.json.
    root.persist([root.barSet(key, value, json), Util.shellQuote(root.stepScript) + " apply"])
  }

  property bool settingsOpen: false
  onSettingsOpenChanged: if (root.settingsOpen) root.refreshStatus(false)

  // Per-workspace name / emoji / colour, persisted in shell.json under
  // `labels` as JSON text (same `qs ipc` reason as `order`), keyed by id:
  // {"3": {"name": "Web", "emoji": "🌐", "color": "#61afef"}}, or a custom
  // icon instead of the emoji: {"icon": "rocket.svg", "iconTint": true}
  // (a file in `iconDir`, see customIcon). Kept in the
  // widget's config rather than as Hyprland workspace names, which are lost
  // whenever an empty workspace is destroyed. `localLabels` shows an edit
  // immediately, before the saved value round-trips through shell.json.
  readonly property var savedLabels: {
    var raw = root.setting("labels", {})
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = {}
      }
    }
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {}
    // Only workspaces 1-10, with bounded strings: a bloated or hand-edited
    // shell.json can't bog the bar down.
    var out = {}
    for (var key in raw) {
      var n = Number(key)
      var e = raw[key]
      if (!(n >= 1 && n <= 10 && Math.floor(n) === n) || !e || typeof e !== "object") continue
      var clean = {}
      if (e.name) clean.name = String(e.name).slice(0, 40)
      if (e.emoji) clean.emoji = String(e.emoji).slice(0, 16)
      if (e.icon) clean.icon = String(e.icon).slice(0, 255)
      if (e.iconTint === true) clean.iconTint = true
      if (e.color) clean.color = String(e.color).slice(0, 7)
      out[String(n)] = clean
    }
    return out
  }
  property var localLabels: null
  onSavedLabelsChanged: root.localLabels = null
  readonly property var labels: root.localLabels !== null ? root.localLabels : root.savedLabels

  readonly property var swatches: ["#e06c75", "#d19a66", "#e5c07b", "#98c379", "#56b6c2", "#61afef", "#c678dd", "#ff79c6",
    "#ff5555", "#ffb86c", "#f1fa8c", "#50fa7b", "#8be9fd", "#5e81ac", "#bd93f9", "#d8dee9"]

  // Recently used emoji and custom colours (newest first), shown in the
  // editor. JSON text under `recentEmoji` / `recentColors`; the reboot fresh
  // start leaves them alone.
  function jsonList(key) {
    var raw = root.setting(key, [])
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = []
      }
    }
    return Array.isArray(raw) ? raw.slice(0, 32).map(function(v) { return String(v).slice(0, 16) }) : []
  }
  property var localRecentEmoji: null
  property var localRecentColors: null
  readonly property var savedRecentEmoji: root.jsonList("recentEmoji")
  readonly property var savedRecentColors: root.jsonList("recentColors")
  onSavedRecentEmojiChanged: root.localRecentEmoji = null
  onSavedRecentColorsChanged: root.localRecentColors = null
  readonly property var recentEmoji: root.localRecentEmoji !== null ? root.localRecentEmoji : root.savedRecentEmoji
  readonly property var recentColors: root.localRecentColors !== null ? root.localRecentColors : root.savedRecentColors

  function bumpRecent(list, value, max) {
    var out = list.filter(function(v) { return v !== value })
    out.unshift(value)
    return out.slice(0, max)
  }

  function labelFor(id) {
    var entry = root.labels[String(id)]
    return entry && typeof entry === "object" ? entry : ({})
  }

  function customName(id) {
    return String(root.labelFor(id).name || "")
  }

  function customEmoji(id) {
    return String(root.labelFor(id).emoji || "")
  }

  // Custom icons: SVG/PNG files in `iconDir` (default
  // ~/.config/omarchy/hud-icons, outside the plugin so reinstalls keep them).
  // Labels and rooms store just the file name. An icon replaces the emoji;
  // `iconTint` paints it in the card's text colour (for one-colour icons).
  readonly property string iconDir: {
    var dir = String(root.setting("iconDir", "") || "")
    var home = Quickshell.env("HOME")
    if (dir.indexOf("~/") === 0) dir = home + dir.slice(1)
    if (dir === "") dir = (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omarchy/hud-icons"
    return dir.replace(/\/+$/, "")
  }
  readonly property var iconExtensions: /\.(svg|png|jpe?g|webp)$/i

  function validIcon(name) {
    var n = String(name || "")
    return n !== "" && n.indexOf("/") === -1 && root.iconExtensions.test(n) ? n : ""
  }

  function customIcon(id) {
    return root.validIcon(root.labelFor(id).icon)
  }

  function customIconTint(id) {
    return root.labelFor(id).iconTint === true
  }

  function iconUrl(name) {
    var n = root.validIcon(name)
    return n === "" ? "" : "file://" + root.iconDir.split("/").map(encodeURIComponent).join("/") +
      "/" + encodeURIComponent(n)
  }

  // An emoji or icon in front of the name.
  function hasMark(id) {
    return root.customIcon(id) !== "" || root.customEmoji(id) !== ""
  }

  function customColor(id) {
    var c = String(root.labelFor(id).color || "")
    return /^#[0-9a-fA-F]{6}$/.test(c) ? c : ""
  }

  function numberLabel(id) {
    return id === 10 ? "0" : String(id)
  }

  // What the card shows: the emoji when one is set, else the number.
  function displayLabel(id) {
    return root.customEmoji(id) || root.numberLabel(id)
  }

  // Card text: "emoji name" once named (horizontal bars only — a vertical
  // bar has no room), otherwise the emoji or number.
  function cardLabel(id) {
    var name = root.customName(id)
    if (root.vertical || name === "") return root.displayLabel(id)
    var emoji = root.customEmoji(id)
    return emoji !== "" ? emoji + " " + name : name
  }

  // The text part of a card next to its emoji or icon: the name once named
  // (horizontal bars), the number when there is neither, else nothing.
  function cardText(id) {
    var name = root.vertical || root.compactCards ? "" : root.customName(id)
    if (name !== "") return name
    return root.hasMark(id) ? "" : root.numberLabel(id)
  }

  function saveLabel(id, name, emoji, color, icon, iconTint) {
    if (!root.bar) return
    var all = JSON.parse(JSON.stringify(root.labels))
    var entry = {}
    var n = String(name || "").trim()
    var e = String(emoji || "").trim()
    var ic = root.validIcon(icon)
    if (n.length > 0 && n !== root.numberLabel(id)) entry.name = n
    if (ic !== "") {
      entry.icon = ic
      if (iconTint === true) entry.iconTint = true
    } else if (e.length > 0) {
      entry.emoji = e
    }
    if (/^#[0-9a-fA-F]{6}$/.test(String(color || ""))) entry.color = String(color)
    if (Object.keys(entry).length > 0) all[String(id)] = entry
    else delete all[String(id)]

    root.localLabels = all
    var cmds = [root.barSet("labels", JSON.stringify(all))]
    if (entry.emoji) {
      root.localRecentEmoji = root.bumpRecent(root.recentEmoji, entry.emoji, 24)
      cmds.push(root.barSet("recentEmoji", JSON.stringify(root.localRecentEmoji)))
    }
    if (entry.color && root.swatches.indexOf(entry.color.toLowerCase()) === -1) {
      root.localRecentColors = root.bumpRecent(root.recentColors, entry.color.toLowerCase(), 8)
      cmds.push(root.barSet("recentColors", JSON.stringify(root.localRecentColors)))
    }
    root.persist(cmds)

    // v1.1.1 renamed the Hyprland workspace itself; put that back to the
    // number so names live in one place.
    var ws = root.workspaceById(id)
    if (ws && String(ws.name) !== String(id)) root.renameWorkspace(id, String(id))
  }

  function renameWorkspace(id, name) {
    if (!root.bar) return
    var n = String(name || "").trim()
    if (n.length === 0) n = String(id)
    Quickshell.execDetached(["hyprctl", "dispatch",
      "hl.dsp.workspace.rename({ workspace = " + Number(id) + ", name = " + root.luaQuote(n) + " })"])
  }

  // Scrolling over the workspace numbers moves the focus, matching the 3-finger
  // horizontal touchpad gesture. Scroll up goes back, scroll down goes forward.
  function scrollWorkspaces(delta) {
    if (!root.bar || delta === 0) return
    var args = [root.stepScript, delta > 0 ? "prev" : "next"]
    if (root.wrapScroll) args.push("--wrap")
    Quickshell.execDetached(args)
  }

  // Persist the new order. The shell hot-pushes the changed `order` setting
  // back into this widget (same entry ids, so it is a settings-only delta),
  // the Repeater model rebinds, and the delegates that survive the reset
  // slide from their snapshotted positions into the new slots.
  function persistOrder(ids) {
    if (!root.bar) return
    root.persist(root.barSet("order", JSON.stringify(ids)))
  }


  // Slide offset for one chip while a neighbour is lifted: the difference
  // between its start in the would-be order and its resting start, so the
  // cards step aside and open a gap exactly as wide as the held card. Zero
  // whenever nothing is being dragged.
  function chipShift(id) {
    if (root.dragId < 0 || root.dropIndex < 0) return 0

    // Bar cards only; a drop into the stack (an index past the bar) closes
    // the gap the held card leaves.
    var ids = root.barIds
    var from = ids.indexOf(root.dragId)
    var p = Math.min(root.dropIndex, ids.length - 1)
    if (from === -1 || p === from) return 0

    var next = root.reordered(ids, from, p)
    var me = next.indexOf(id)
    if (me === -1) return 0
    return root.startsFor(next)[me] - root.starts[ids.indexOf(id)]
  }

  // The drop slot comes straight from the cursor's position along the row,
  // not from hit-testing cards (which are themselves sliding out of the way,
  // so the hit target used to flip or stick): of every slot the held card
  // could take, pick the one that would put its centre nearest the cursor —
  // cards differ in width once named. The bar is only ~30px thick, so
  // drifting a little off it keeps the drag alive; pulling well away cancels.
  function updateDropIndex(sceneX, sceneY) {
    var ids = root.barIds
    var from = ids.indexOf(root.dragId)
    var local = root.mapFromItem(null, sceneX, sceneY)
    var along = root.vertical ? local.y : local.x
    var across = root.vertical ? local.x : local.y
    var thickness = root.vertical ? root.width : root.height
    var slack = Style.space(40)
    var held = from === -1 ? 0 : root.sizeOf(root.dragId)

    if (from === -1 || ids.length === 0 || across < -slack || across > thickness + slack
        || along < -held || along > root.cardsEnd + held) {
      root.dropIndex = -1
      root.dropTargetId = -1
      return
    }

    // Over the stack chip: the card goes to the end of the order, into the
    // stack (the first stacked card takes its place on the bar if it fits).
    if (root.hasStack && along > root.stackPos - root.rowGap / 2) {
      root.dropIndex = root.displayIds.length - 1
      root.dropTargetId = root.stackTarget
      return
    }

    var best = from
    var bestDist = Infinity
    for (var p = 0; p < ids.length; p++) {
      var centre = root.startsFor(root.reordered(ids, from, p))[p] + held / 2
      var dist = Math.abs(centre - along)
      if (dist < bestDist) {
        bestDist = dist
        best = p
      }
    }
    root.dropIndex = best
    root.dropTargetId = best === from ? -1 : ids[best]
  }

  // The pointer let go after a drag. Visual positions are snapshotted first —
  // the lifted card's snapshot starts at the ghost, so it drops in from the
  // pointer instead of teleporting back to its old slot. The drag state is
  // cleared *before* the new order is applied, so the rebuilt cards carry no
  // leftover slide offset; each one then eases from its snapshot into its slot.
  function finishDrag() {
    var from = root.dragId
    var ids = workspaceIds()
    var fromIdx = ids.indexOf(from)
    var p = root.dropIndex
    if (from === -1 || fromIdx === -1 || p < 0 || p === fromIdx) {
      cancelDrag()
      return
    }

    var snap = {}
    var kids = grid.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (!c || c.modelData === undefined) continue
      var pt = c.modelData === from ? ghost.mapToItem(grid, 0, 0) : c.mapToItem(grid, 0, 0)
      snap[c.modelData] = { x: pt.x, y: pt.y }
    }

    var next = ids.slice()
    next.splice(fromIdx, 1)
    next.splice(p, 0, from)

    root.prevSlots = snap
    cancelDrag()
    root.localOrder = next
    root.syncIds()
    persistOrder(next)
  }

  // Drag aborted, or finished: drop the in-flight state. Cards slide back to
  // their resting slots through the Translate behaviours.
  function cancelDrag() {
    root.dragId = -1
    root.dropTargetId = -1
    root.dropIndex = -1
    root.ghostTilt = 0
  }


  // The bar stacks a slot-level MouseArea (Bar.qml's `modulePointer`) above
  // widget content: it swallows presses and forwards plain clicks back through
  // pressModuleClickTarget. Pointer handlers, however, are only offered events
  // for the item under the cursor and that item's ancestors — never for a
  // sibling subtree — so a DragHandler inside this widget would sit blind while
  // the overlay is on top. Raising our subtree makes our own MouseArea the hit
  // target: clicks then arrive directly (the same onPressed path as before) and
  // the DragHandler joins the delivery chain. Side effect: this widget can no
  // longer be repositioned by dragging it on the bar; `omarchy bar put/move`
  // still can.
  function raiseInputStack() {
    // Depends on the bar slot's internals; if a shell update changes them,
    // log it and carry on (drag-reorder may be affected, nothing else).
    try {
      var host = root.parent
      if (!host || host.children === undefined || host.z === undefined) {
        root.logLine("raiseInputStack: bar slot layout not recognised, skipped")
        return
      }
      root.z = 1
      var kids = host.children
      for (var i = 0; i < kids.length; i++) {
        var kid = kids[i]
        if (kid === root) continue
        // Recognize the slot's overlay MouseArea by its MouseArea-only API.
        if (kid.acceptedButtons !== undefined && kid.propagateComposedEvents !== undefined) return
      }
      host.z = Math.max(Number(host.z) || 0, 1)
    } catch (e) {
      root.logLine("raiseInputStack failed: " + e)
    }
  }

  Component.onCompleted: {
    root.syncIds()
    root.syncBar()
    root.applyTransition()
    raiseInputStack()
    root.ensureIconDir()
    startupCheck.start()
  }

  // A window dragged onto a workspace number. Hyprland can't tell a bar that a
  // drag is happening (it withholds pointer focus from layer surfaces for the
  // whole drag), so the compositor side watches for the drop and emits
  // `custom>>wsdrag,<address>,<x>,<y>`; every button hit-tests the point
  // against its own scene rect and the one under the cursor takes it.
  signal dropAt(string address, real dropX, real dropY)

  property int dropFlash: 0

  // Hover "room" preview: which workspace is previewed, the card delegate it
  // is anchored to, and the in-flight target while an open is still pending.
  // Opens are debounced (160ms, well under the bar's 400ms tooltip delay)
  // and close only after the cursor has been off both the card and the popup
  // for a beat, so crossing the gap between them never blinks it. A move
  // between cards re-anchors instantly instead of re-debouncing.
  property int previewId: -1
  property int pendingPreviewId: -1
  property var previewAnchor: null
  property bool previewPopupHovered: false

  readonly property bool previewFocused: root.previewId >= 0
    && Hyprland.focusedWorkspace !== null
    && Hyprland.focusedWorkspace.id === root.previewId
  readonly property color previewFg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string previewFont: root.bar ? root.bar.fontFamily : Style.font.family

  // The bar coordinates popouts by calling close() on the owner object it is
  // given, so this folds dismissal back into the normal close path.
  QtObject {
    id: previewOwner
    function close() { root.previewCloseNow() }
  }
  // Follows the bar's foreground (e.g. a transparent bar over a light wallpaper).
  readonly property color barFg: root.bar && root.bar.barForeground !== undefined
    ? root.bar.barForeground : Color.foreground

  property int editingId: -1
  property var editingAnchor: null

  // Double-click a card to edit its name, emoji and colour.
  function startRename(id, anchorItem) {
    root.previewCloseNow()
    root.editingId = id
    root.editingAnchor = anchorItem
  }

  // Double-click is detected from the press path: an extra MouseArea over the
  // chip would steal presses from the drag handler (see raiseInputStack).
  property int lastPressId: -1
  property double lastPressTime: 0

  function chipPressed(id, anchorItem, button) {
    root.stackOpen = false
    if (button === Qt.RightButton) {
      root.lastPressId = -1
      root.startRename(id, anchorItem)
      return
    }
    var now = Date.now()
    var isDouble = id === root.lastPressId && now - root.lastPressTime < 400
    root.lastPressId = isDouble ? -1 : id
    root.lastPressTime = isDouble ? 0 : now
    if (isDouble) root.startRename(id, anchorItem)
    else root.focusWorkspace(id)
  }

  function cancelRename() {
    root.editingId = -1
    root.editingAnchor = null
    root.editMode = "edit"
  }

  // ---- Deleting a workspace ----
  // "edit" | "delete" (choose where windows go) | "confirmClose" | "closing"
  // | "closeFailed" (some apps refused to close, e.g. unsaved work)
  // | "moving" (windows sent elsewhere, waiting for the workspace to empty)
  // | "moveFailed" (a window didn't move: the card was kept).
  property string editMode: "edit"
  property var moveTargets: ({})    // window address -> workspace id, or "new"
  // Workspaces whose apps were told to close: id -> time the close was sent.
  // Lives outside the editor, so the card still goes once the last window
  // is gone even if the editor was dismissed meanwhile (e.g. by clicking an
  // app's "save changes?" dialog). Dropped after a few minutes, so an app
  // kept open on purpose doesn't make the card vanish much later.
  property var pendingDeletes: ({})
  readonly property int pendingDeleteMs: 3 * 60 * 1000
  // Deletes waiting on window moves ("Move & delete"): id -> the workspace
  // to land on. A move is quick, so if windows are still there after
  // `moveWaitMs` it failed: the delete is called off and the card kept.
  property var deleteLandings: ({})
  readonly property int moveWaitMs: 5000

  function hexAddress(t) {
    var ipc = t.lastIpcObject || {}
    var raw = String(t.address || ipc.address || "").toLowerCase().replace(/^0x/, "")
    var digits = ""
    for (var i = 0; i < raw.length; i++) {
      var ch = raw.charAt(i)
      if ((ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")) digits += ch
    }
    return digits.length > 0 ? "0x" + digits : ""
  }

  function toplevelsOf(id) {
    var ws = root.workspaceById(id)
    if (ws === null) return []
    var out = []
    var vals = ws.toplevels.values
    for (var i = 0; i < vals.length; i++) {
      if (root.hexAddress(vals[i]) !== "") out.push(vals[i])
    }
    return out
  }

  readonly property var deleteWindows: root.editingId >= 0 && root.editMode !== "edit"
    ? root.toplevelsOf(root.editingId) : []

  // Where windows can go: every other card, plus a fresh workspace.
  readonly property var moveDestinations: {
    var out = []
    var ids = root.displayIds
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] === root.editingId) continue
      var label = root.customName(ids[i]) || ("Workspace " + root.numberLabel(ids[i]))
      var emoji = root.customEmoji(ids[i])
      out.push({ value: String(ids[i]), label: (emoji ? emoji + " " : "") + label })
    }
    out.push({ value: "new", label: "＋ New workspace" })
    return out
  }

  function neighbourOf(id) {
    var ids = root.displayIds
    var i = ids.indexOf(id)
    if (i === -1) return ids.length > 0 ? ids[0] : -1
    if (i + 1 < ids.length) return ids[i + 1]
    return i > 0 ? ids[i - 1] : -1
  }

  function startDelete() {
    root.dropPendingDelete(root.editingId)
    root.dropPendingClose(root.editingId)
    var fallback = root.neighbourOf(root.editingId)
    var targets = {}
    var wins = root.toplevelsOf(root.editingId)
    for (var i = 0; i < wins.length; i++) {
      targets[root.hexAddress(wins[i])] = fallback > 0 ? String(fallback) : "new"
    }
    root.moveTargets = targets
    root.editMode = "delete"
  }

  function setMoveTarget(address, value) {
    var next = JSON.parse(JSON.stringify(root.moveTargets))
    next[address] = value
    root.moveTargets = next
  }

  function setAllMoveTargets(value) {
    var next = {}
    for (var key in root.moveTargets) next[key] = value
    root.moveTargets = next
  }

  // A free workspace number for windows sent to "New workspace": not on the
  // bar, not existing, and not the one being deleted.
  function freeWorkspaceId(excluding) {
    var used = {}
    var ids = root.displayIds
    for (var i = 0; i < ids.length; i++) used[ids[i]] = true
    var values = Hyprland.workspaces.values
    for (var j = 0; j < values.length; j++) used[values[j].id] = true
    used[excluding] = true
    for (var n = 1; n <= 10; n++) {
      if (!used[n]) return n
    }
    return -1
  }

  function dispatch(lua) {
    Quickshell.execDetached(["hyprctl", "dispatch", lua])
  }

  function moveAndDelete() {
    var id = root.editingId
    if (id < 0) return
    var wins = root.toplevelsOf(id)
    var newId = -1
    var landing = -1
    for (var i = 0; i < wins.length; i++) {
      var address = root.hexAddress(wins[i])
      var target = String(root.moveTargets[address] || "new")
      var dest
      if (target === "new") {
        if (newId < 0) newId = root.freeWorkspaceId(id)
        if (newId < 0) newId = root.neighbourOf(id)
        dest = newId
      } else {
        dest = Number(target)
      }
      if (!(dest > 0)) continue
      if (landing < 0) landing = dest
      if (newId > 0 && dest === newId) root.unhideWorkspace(newId)
      root.dispatch("hl.dsp.window.move({ workspace = " + root.luaQuote(String(dest)) + ", window = " +
        root.luaQuote("address:" + address) + ", follow = false })")
    }
    if (wins.length === 0) {
      root.finishDelete(id, landing)
      return
    }
    // The moves are requests to the compositor: the card (and its name,
    // emoji, colour) only goes once the workspace really is empty. If a
    // window stays put, the card stays and the editor says so.
    var pending = JSON.parse(JSON.stringify(root.pendingDeletes))
    pending[String(id)] = Date.now()
    root.pendingDeletes = pending
    var landings = JSON.parse(JSON.stringify(root.deleteLandings))
    landings[String(id)] = landing
    root.deleteLandings = landings
    root.editMode = "moving"
  }

  function closeAndDelete() {
    var id = root.editingId
    if (id < 0) return
    var wins = root.toplevelsOf(id)
    if (wins.length === 0) {
      root.finishDelete(id, -1)
      return
    }
    for (var i = 0; i < wins.length; i++) {
      root.dispatch("hl.dsp.window.close({ window = " + root.luaQuote("address:" + root.hexAddress(wins[i])) + " })")
    }
    // Apps may ask to save first; the card goes as soon as the last one is gone.
    var pending = JSON.parse(JSON.stringify(root.pendingDeletes))
    pending[String(id)] = Date.now()
    root.pendingDeletes = pending
    root.editMode = "closing"
  }

  function dropPendingDelete(id) {
    if (root.deleteLandings[String(id)] !== undefined) {
      var landings = JSON.parse(JSON.stringify(root.deleteLandings))
      delete landings[String(id)]
      root.deleteLandings = landings
    }
    if (root.pendingDeletes[String(id)] === undefined) return
    var pending = JSON.parse(JSON.stringify(root.pendingDeletes))
    delete pending[String(id)]
    root.pendingDeletes = pending
  }

  // ---- Closing a workspace (the card stays) ----
  // Closes every app on it but keeps the card, its name, emoji, colour and
  // place on the bar, empty, until it's deleted. Clicking it later opens the
  // workspace again.
  property var pendingCloses: ({})
  readonly property bool closingMode: root.editMode === "confirmCloseKeep"
    || root.editMode === "closingKeep" || root.editMode === "closeKeepFailed"

  function keepCard(id) {
    if (root.keptSet[id]) return
    var kept = root.keptList.concat([id])
    var hidden = root.hiddenList.filter(function(n) { return n !== id })
    var order = root.displayIds.slice()
    if (order.indexOf(id) === -1) order.push(id)
    root.localKept = kept
    root.localHidden = hidden
    root.localOrder = order
    root.persist([root.barSet("kept", JSON.stringify(kept)), root.barSet("hidden", JSON.stringify(hidden)),
      root.barSet("order", JSON.stringify(order))])
  }

  function closeAndKeep() {
    var id = root.editingId
    if (id < 0) return
    root.dropPendingDelete(id)
    root.keepCard(id)
    var wins = root.toplevelsOf(id)
    if (wins.length === 0) {
      root.cancelRename()
      return
    }
    for (var i = 0; i < wins.length; i++) {
      root.dispatch("hl.dsp.window.close({ window = " + root.luaQuote("address:" + root.hexAddress(wins[i])) + " })")
    }
    var pending = JSON.parse(JSON.stringify(root.pendingCloses))
    pending[String(id)] = Date.now()
    root.pendingCloses = pending
    root.editMode = "closingKeep"
  }

  function dropPendingClose(id) {
    if (root.pendingCloses[String(id)] === undefined) return
    var pending = JSON.parse(JSON.stringify(root.pendingCloses))
    delete pending[String(id)]
    root.pendingCloses = pending
  }

  Timer {
    interval: 300
    repeat: true
    running: Object.keys(root.pendingCloses).length > 0
    onTriggered: {
      var now = Date.now()
      var keys = Object.keys(root.pendingCloses)
      for (var i = 0; i < keys.length; i++) {
        var id = Number(keys[i])
        var started = root.pendingCloses[keys[i]]
        var editing = root.editingId === id
        if (root.toplevelsOf(id).length === 0) {
          root.dropPendingClose(id)
          if (editing && root.closingMode) root.cancelRename()
        } else if (now - started > root.pendingDeleteMs) {
          root.dropPendingClose(id)
        } else if (editing && root.editMode === "closingKeep" && now - started > 6000) {
          root.editMode = "closeKeepFailed"
        }
      }
    }
  }

  Timer {
    id: closeWatch
    interval: 300
    repeat: true
    running: Object.keys(root.pendingDeletes).length > 0
    onTriggered: {
      var now = Date.now()
      var keys = Object.keys(root.pendingDeletes)
      for (var i = 0; i < keys.length; i++) {
        var id = Number(keys[i])
        var started = root.pendingDeletes[keys[i]]
        var landing = root.deleteLandings[keys[i]]
        if (root.toplevelsOf(id).length === 0) {
          root.finishDelete(id, landing !== undefined ? landing : -1)
        } else if (landing !== undefined && now - started > root.moveWaitMs) {
          root.dropPendingDelete(id)
          root.logLine("delete " + id + ": " + root.toplevelsOf(id).length + " window(s) didn't move, card kept")
          if (root.editingId === id && root.editMode === "moving") root.editMode = "moveFailed"
        } else if (now - started > root.pendingDeleteMs) {
          root.dropPendingDelete(id)
        } else if (root.editingId === id && root.editMode === "closing" && now - started > 6000) {
          root.editMode = "closeFailed"
        }
      }
    }
  }

  // Take the card off the bar: drop it from the order, its label, and mark it
  // hidden. If it's the focused workspace, step to `landing` (or a neighbour)
  // so Hyprland can destroy the now-empty workspace.
  function finishDelete(id, landing) {
    root.dropPendingDelete(id)
    root.dropPendingClose(id)
    var focused = Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === id
    var goTo = landing > 0 ? landing : root.neighbourOf(id)

    var order = root.displayIds.filter(function(n) { return n !== id })
    var hidden = root.hiddenList.filter(function(n) { return n !== id })
    hidden.push(id)
    var labels = JSON.parse(JSON.stringify(root.labels))
    delete labels[String(id)]

    root.localHidden = hidden
    root.localOrder = order
    root.localLabels = labels
    if (root.editingId === id) root.cancelRename()

    if (focused && goTo > 0) root.focusWorkspace(goTo)
    root.persistAll(order, hidden, labels)
  }

  // ---- Fresh start after a reboot ----
  // Each boot has its own id. When it differs from the one recorded last
  // time, the cards go back to default: 1-5 in order, no names, emoji or
  // colours, nothing deleted. Shell restarts and reloads keep the same boot id,
  // so they never reset. Transition and swipe preferences are kept. The very
  // first run only records the id, so installing doesn't wipe anything.
  // Active card style: "solid" fills the current workspace's card with its
  // colour (or the accent) and flips its text for contrast; "outline" is the
  // original subtle rim.
  readonly property bool solidActive: String(root.setting("activeStyle", "solid")) !== "outline"

  // Dark or light text, whichever reads better on `c`.
  function contrastOn(c) {
    var lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    return lum > 0.55 ? "#0d0f10" : "#ffffff"
  }

  readonly property bool resetOnBoot: root.setting("resetOnBoot", true) !== false
    && root.setting("resetOnBoot", true) !== "false"

  Process {
    running: true
    command: ["cat", "/proc/sys/kernel/random/boot_id"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkFreshBoot(String(text).trim())
    }
  }

  function checkFreshBoot(bootId) {
    if (!root.bar || bootId === "") return
    var last = String(root.setting("lastBoot", ""))
    if (last === bootId) return

    var cmds = []
    if (last !== "" && root.resetOnBoot) {
      root.localOrder = []
      root.localLabels = ({})
      root.localHidden = []
      root.localKept = []
      cmds.push(root.barSet("order", "[]"))
      cmds.push(root.barSet("labels", "{}"))
      cmds.push(root.barSet("hidden", "[]"))
      cmds.push(root.barSet("kept", "[]"))
    }
    root.localActive = { name: "", ids: [] }
    cmds.push(root.barSet("activeProfile", ""))
    cmds.push(root.barSet("lastBoot", bootId))
    root.persist(cmds)
  }

  function unhideWorkspace(id) {
    var hidden = root.hiddenList.filter(function(n) { return n !== id })
    root.localHidden = hidden
    root.persistAll(null, hidden, null)
  }

  // Several keys in one queued write.
  function persistAll(order, hidden, labels) {
    if (!root.bar) return
    var cmds = []
    if (order !== null) cmds.push(root.barSet("order", JSON.stringify(order)))
    if (hidden !== null) cmds.push(root.barSet("hidden", JSON.stringify(hidden)))
    if (labels !== null) cmds.push(root.barSet("labels", JSON.stringify(labels)))
    // A deleted (hidden) card is no longer a closed one.
    if (hidden !== null) {
      var kept = root.keptList.filter(function(n) { return hidden.indexOf(n) === -1 })
      if (kept.length !== root.keptList.length) {
        root.localKept = kept
        cmds.push(root.barSet("kept", JSON.stringify(kept)))
      }
    }
    root.persist(cmds)
  }

  // ---- Saved rooms ----
  // A room is a card's name, emoji and colour plus the apps that were open on
  // it, so a workspace can be rebuilt in one click (e.g. after the fresh
  // start on reboot, which leaves rooms alone). Saved as JSON text under
  // `rooms`: [{ name, emoji | icon + iconTint, color, apps: [{ class, title, cmd, cwd }] }].
  // ws-room (next to this file) captures and relaunches the apps.
  readonly property string roomScript: decodeURIComponent(
    String(Qt.resolvedUrl("ws-room")).replace(/^file:\/\//, ""))
  property var localRooms: null
  readonly property var savedRooms: {
    var raw = root.setting("rooms", [])
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = []
      }
    }
    if (!Array.isArray(raw)) return []
    // At most 50 rooms of 30 apps each; anything else is dropped on read.
    return raw.filter(function(r) { return r && typeof r === "object" && !Array.isArray(r) })
      .slice(0, root.maxRooms).map(function(r) {
        var room = {}
        for (var k in r) room[k] = r[k]
        room.name = String(r.name || "Room").slice(0, 40)
        var apps = []
        var rawApps = r.apps || []
        for (var i = 0; i < (rawApps.length || 0) && apps.length < 30; i++) {
          if (rawApps[i] && typeof rawApps[i] === "object") apps.push(rawApps[i])
        }
        room.apps = apps
        return room
      })
  }
  readonly property int maxRooms: 50
  onSavedRoomsChanged: root.localRooms = null
  readonly property var rooms: root.localRooms !== null ? root.localRooms : root.savedRooms
  property string roomNotice: ""
  property var pendingRoom: null    // room waiting for its apps to be captured

  function persistRooms(list) {
    root.localRooms = list
    if (!root.bar) return
    root.persist(root.barSet("rooms", JSON.stringify(list)))
  }

  // From the card editor: keep the edits, then snapshot the card as a room.
  // A room with the same name is replaced, which is how a room is updated.
  function saveRoomFromEditor() {
    var id = root.editingId
    if (id < 0 || roomCapture.running) return
    var name = String(nameField.text || "").trim() || ("Workspace " + root.numberLabel(id))
    root.saveLabel(id, nameField.text, root.draftEmoji, root.draftColor, root.draftIcon, root.draftIconTint)
    root.pendingRoom = root.draftIcon !== ""
      ? { name: name, icon: root.draftIcon, iconTint: root.draftIconTint, color: root.draftColor }
      : { name: name, emoji: root.draftEmoji, color: root.draftColor }
    roomCapture.command = [root.roomScript, "capture", String(id)]
    roomCapture.running = true
    root.cancelRename()
  }

  Process {
    id: roomCapture
    stdout: StdioCollector { id: roomCaptureOut; waitForEnd: true }
    onExited: function(code) { root.finishRoomSave(String(roomCaptureOut.text), code) }
  }

  function finishRoomSave(text, code) {
    var room = root.pendingRoom
    root.pendingRoom = null
    if (room === null) return
    var apps = null
    try {
      apps = JSON.parse(text)
    } catch (e) {
      apps = null
    }
    if (code !== 0 || !root.validAppList(apps)) {
      // A failed read is not "no apps": keep any room of that name as it is.
      root.logLine("room capture failed (exit " + code + "), nothing saved")
      root.roomNotice = "Couldn't read the open apps, so \u201c" + room.name + "\u201d wasn't saved. Try again."
      root.panelTab = "rooms"
      root.settingsOpen = true
      return
    }
    room.apps = apps
    var list = root.rooms.filter(function(r) {
      return String(r.name).toLowerCase() !== room.name.toLowerCase()
    })
    var replaced = list.length !== root.rooms.length
    if (list.length >= root.maxRooms) {
      root.roomNotice = "Room limit reached (" + root.maxRooms + "). Delete one first."
      root.panelTab = "rooms"
      root.settingsOpen = true
      return
    }
    list.push(room)
    root.persistRooms(list)
    var n = room.apps.length
    root.roomNotice = (replaced ? "Updated " : "Saved ") + "\u201c" + room.name + "\u201d with " +
      n + (n === 1 ? " app." : " apps.")
    root.panelTab = "rooms"
    root.settingsOpen = true
  }

  // Open a room on a free workspace: label the card, put it last on the bar,
  // switch to it and start its apps there.
  function openRoom(index) {
    var room = root.rooms[index]
    if (!room) return
    var id = root.freeWorkspaceId(-1)
    if (id < 0) {
      root.roomNotice = "No free workspace (all 10 are in use)."
      return
    }
    var labels = JSON.parse(JSON.stringify(root.labels))
    var entry = {}
    if (room.name) entry.name = String(room.name)
    if (root.validIcon(room.icon) !== "") {
      entry.icon = root.validIcon(room.icon)
      if (room.iconTint === true) entry.iconTint = true
    } else if (room.emoji) {
      entry.emoji = String(room.emoji)
    }
    if (/^#[0-9a-fA-F]{6}$/.test(String(room.color || ""))) entry.color = String(room.color)
    labels[String(id)] = entry
    var hidden = root.hiddenList.filter(function(n) { return n !== id })
    var order = root.displayIds.filter(function(n) { return n !== id })
    order.push(id)
    root.localLabels = labels
    root.localHidden = hidden
    root.localOrder = order
    root.persistAll(order, hidden, labels)
    root.roomNotice = ""
    root.settingsOpen = false
    root.launchRooms([{ ws: id, apps: room.apps || [] }])
  }

  function deleteRoom(index) {
    var list = root.rooms.slice()
    var gone = list.splice(index, 1)
    root.persistRooms(list)
    root.roomNotice = gone.length ? "Deleted \u201c" + gone[0].name + "\u201d." : ""
  }

  // "Firefox · Terminal (~/Work) · Files"
  function roomSummary(room) {
    // Repeater modelData hands nested arrays over as list-likes, not JS arrays.
    var apps = []
    var raw = room && room.apps ? room.apps : []
    for (var i = 0; i < (raw.length || 0); i++) apps.push(raw[i])
    if (apps.length === 0) return "No apps, just the card"
    var home = Quickshell.env("HOME")
    return apps.map(function(a) {
      var cls = String(a.class || "app")
      var short = cls.split(".").pop()
      var label = short.charAt(0).toUpperCase() + short.slice(1)
      var cwd = String(a.cwd || "")
      if (cwd && cwd !== home && /term|alacritty|kitty|foot|ghostty|wezterm|konsole/i.test(cls))
        label += " (" + cwd.split("/").pop() + ")"
      return label
    }).join(" \u00b7 ")
  }

  // ---- Profiles ----
  // A profile is a whole deck: the cards you pick from the bar, in bar
  // order, each saved like a room (name, emoji or icon, colour, apps).
  // Opening one replaces the bar with exactly those cards. Saved as JSON
  // text under `profiles`: [{ name, rooms: [room, ...] }]. Like rooms, never
  // cleared by the fresh start on reboot.
  readonly property int maxProfiles: 20
  property var localProfiles: null
  readonly property var savedProfiles: {
    var raw = root.setting("profiles", [])
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw)
      } catch (e) {
        raw = []
      }
    }
    if (!Array.isArray(raw)) return []
    return raw.filter(function(p) { return p && typeof p === "object" && !Array.isArray(p) })
      .slice(0, root.maxProfiles).map(function(p) {
        var rooms = []
        var rawRooms = Array.isArray(p.rooms) ? p.rooms : []
        for (var i = 0; i < rawRooms.length && rooms.length < 10; i++) {
          var r = rawRooms[i]
          if (!r || typeof r !== "object" || Array.isArray(r)) continue
          var room = {}
          for (var k in r) room[k] = r[k]
          room.name = String(r.name || "").slice(0, 40)
          var apps = []
          var rawApps = Array.isArray(r.apps) ? r.apps : []
          for (var j = 0; j < rawApps.length && apps.length < 30; j++) {
            if (rawApps[j] && typeof rawApps[j] === "object") apps.push(rawApps[j])
          }
          room.apps = apps
          rooms.push(room)
        }
        return { name: String(p.name || "Profile").slice(0, 40), rooms: rooms }
      })
  }
  onSavedProfilesChanged: root.localProfiles = null
  readonly property var profiles: root.localProfiles !== null ? root.localProfiles : root.savedProfiles
  property string profileNotice: ""
  property var profilePick: ({})      // workspace id -> picked for the next save
  property var pendingProfile: null   // profile waiting for its apps to be captured
  property int profileConfirm: -1     // profile asking what to do with open apps

  // The profile on the bar now and the workspaces its cards use, so opening
  // it again tops it up instead of opening a second copy. Saved under
  // `activeProfile` as JSON text { name, ids }; dropped on a new boot.
  property var localActive: null
  readonly property var savedActive: {
    var raw = root.setting("activeProfile", "")
    if (typeof raw === "string") {
      try {
        raw = raw === "" ? null : JSON.parse(raw)
      } catch (e) {
        raw = null
      }
    }
    if (!raw || typeof raw !== "object" || !Array.isArray(raw.ids)) return { name: "", ids: [] }
    var ids = raw.ids.map(Number).filter(function(n) { return n >= 1 && n <= 10 }).slice(0, 10)
    return { name: String(raw.name || ""), ids: ids }
  }
  onSavedActiveChanged: root.localActive = null
  readonly property var activeProfile: root.localActive !== null ? root.localActive : root.savedActive

  function sameName(a, b) {
    return String(a).toLowerCase() === String(b).toLowerCase()
  }

  function isActiveProfile(p) {
    return !!p && root.activeProfile.name !== "" && root.sameName(p.name, root.activeProfile.name)
  }

  // The active profile with every one of its cards on the bar: it is open,
  // and Open is locked so it can't be opened a second time. Another profile
  // whose cards happen to be on the bar can still be opened (switched to):
  // it reuses those cards, so nothing is duplicated.
  function profileOnBar(p) {
    var n = p && p.rooms ? (p.rooms.length || 0) : 0
    return n > 0 && root.isActiveProfile(p) && root.reusedIds(p).length === n
  }

  // Active, but some of its cards were deleted since: Open brings back just those.
  function profilePartial(p) {
    return root.isActiveProfile(p) && !root.profileOnBar(p)
  }

  function setActiveProfile(name, ids) {
    root.localActive = { name: String(name), ids: ids.slice() }
    root.persist(root.barSet("activeProfile", JSON.stringify(root.localActive)))
  }

  // Does the card on workspace `id` look like `room` (same name, emoji or
  // icon, colour)? A room with none of those can't be recognised this way.
  function cardMatchesRoom(id, room) {
    var card = root.cardAsRoom(id)
    var keys = ["name", "emoji", "icon", "color"]
    var labelled = false
    for (var i = 0; i < keys.length; i++) {
      var want = String(room[keys[i]] || "")
      if (keys[i] === "emoji" && root.validIcon(room.icon) !== "") want = ""
      if (want !== "") labelled = true
      if (String(card[keys[i]] || "") !== want) return false
    }
    return labelled
  }

  // For each of the profile's cards, the workspace already showing it, or
  // -1, plus the names of cards that are on the bar more than once. The
  // active profile's own workspaces always count as its cards, even after a
  // rename or new colour. Other cards are recognised by their look (same
  // name, emoji or icon, colour); when two cards look the same nothing is
  // guessed: the profile can't open until one copy is deleted.
  function profileMatch(p) {
    var rooms = p && p.rooms ? p.rooms : []
    var n = rooms.length || 0
    var slots = []
    var dupes = []
    var used = {}
    var rec = root.isActiveProfile(p) && root.activeProfile.ids.length === n ? root.activeProfile.ids : []
    var onBar = root.displayIds
    for (var i = 0; i < n; i++) {
      var id = rec.length ? rec[i] : -1
      var ok = id > 0 && onBar.indexOf(id) !== -1 && !used[id]
      slots.push(ok ? id : -1)
      if (ok) used[id] = true
    }
    for (var j = 0; j < n; j++) {
      if (slots[j] > 0) continue
      var found = onBar.filter(function(k) { return !used[k] && root.cardMatchesRoom(k, rooms[j]) })
      if (found.length > 1) {
        dupes.push(String(rooms[j].name || rooms[j].emoji || ("Card " + (j + 1))))
      } else if (found.length === 1) {
        slots[j] = found[0]
        used[found[0]] = true
      }
    }
    return { slots: slots, dupes: dupes }
  }

  function profileSlots(p) {
    return root.profileMatch(p).slots
  }

  function reusedIds(p) {
    return root.profileSlots(p).filter(function(n) { return n > 0 })
  }

  // Apps of a room not already open on workspace `id`, one window per app.
  // `open` is what `ws-room capture-deck` read on that workspace (class,
  // command and folder of each window), or null if it couldn't be read.
  // Apps match by class; a terminal or file manager saved in a folder only
  // counts as open when one is open in that same folder, so a terminal
  // somewhere else never stops the saved one from coming back. Without
  // `open`, folders can't be checked: those apps are always started.
  function missingApps(room, id, open) {
    var have = open !== null && open !== undefined
      ? open.map(function(app) { return { keys: root.savedAppKeys(app), folder: root.appFolder(app) } })
      : root.toplevelsOf(id).map(function(t) { return { keys: root.windowKeys(t), folder: null } })
    var out = []
    var raw = room.apps || []
    for (var i = 0; i < (raw.length || 0); i++) {
      var want = root.savedAppKeys(raw[i])
      var folder = root.appFolder(raw[i])
      var k = -1
      for (var w = 0; w < have.length && k === -1; w++) {
        if (folder !== "" && have[w].folder !== folder) continue
        for (var x = 0; x < want.length; x++) {
          if (have[w].keys.indexOf(want[x]) !== -1) { k = w; break }
        }
      }
      if (k !== -1) have.splice(k, 1)
      else out.push(raw[i])
    }
    return out
  }

  // Terminals and file managers: the folder is what they show, so it is
  // part of what makes a saved one "the same app".
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property var folderApps: /^(org\.gnome\.nautilus|nautilus|org\.gnome\.terminal|gnome-terminal|gnome-terminal-server|org\.gnome\.console|kgx|foot|footclient|alacritty|kitty|ghostty|com\.mitchellh\.ghostty|konsole|org\.kde\.konsole|wezterm|org\.wezfurlong\.wezterm|xterm|st|thunar|nemo|dolphin|org\.kde\.dolphin|pcmanfm)$/

  // The folder a saved or captured app was in, if it is folder-bound (see
  // folderApps), else "". Read from its command first (Nautilus
  // `--new-window <dir>`, `--working-directory=<dir>`), then its cwd.
  function appFolder(app) {
    if (!app || typeof app !== "object") return ""
    var argv = Array.isArray(app.argv) ? app.argv.map(String) : []
    for (var i = 0; i < argv.length; i++) {
      if (argv[i].indexOf("--working-directory=") === 0) return root.cleanFolder(argv[i].slice(20))
    }
    var prog = argv.length > 0 ? argv[0].split("/").pop().toLowerCase() : ""
    var n = argv.indexOf("--new-window")
    if (prog === "nautilus" && n !== -1 && n + 1 < argv.length) return root.cleanFolder(argv[n + 1])
    if (!root.folderApps.test(String(app["class"] || "").toLowerCase()) && !root.folderApps.test(prog)) return ""
    return root.cleanFolder(app.cwd)
  }

  function cleanFolder(path) {
    var f = String(path || "")
    if (f === "~" || f.indexOf("~/") === 0) f = root.homeDir + f.slice(1)
    while (f.length > 1 && f.charAt(f.length - 1) === "/") f = f.slice(0, -1)
    return f
  }

  // Names an app goes by, lower-cased: "org.gnome.Nautilus" also as
  // "nautilus", so an app that reports its window a little differently from
  // when it was saved (some flatpaks, wrappers) still counts as open.
  function appNames(name) {
    var n = String(name || "").toLowerCase().replace(/\.desktop$/, "")
    if (n === "") return []
    var out = [n]
    var last = n.split(/[.\/]/).pop()
    if (last && last !== n) out.push(last)
    return out
  }

  function windowKeys(t) {
    var ipc = t.lastIpcObject || {}
    var keys = []
    var names = [t.wayland ? t.wayland.appId : "", ipc["class"], ipc.initialClass]
    for (var i = 0; i < names.length; i++) keys = keys.concat(root.appNames(names[i]))
    return keys
  }

  function savedAppKeys(app) {
    var keys = root.appNames(app["class"])
    var argv = Array.isArray(app.argv) ? app.argv : []
    if (argv.length >= 3 && String(argv[0]).split("/").pop() === "flatpak") keys = keys.concat(root.appNames(argv[2]))
    else if (argv.length > 0) keys = keys.concat(root.appNames(String(argv[0]).split("/").pop()))
    return keys
  }

  // Cards with windows that the profile doesn't own.
  function otherBusyIds(p) {
    var mine = root.reusedIds(p)
    return root.busyIds().filter(function(n) { return mine.indexOf(n) === -1 })
  }

  function persistProfiles(list) {
    root.localProfiles = list
    if (!root.bar) return
    root.persist(root.barSet("profiles", JSON.stringify(list)))
  }

  // Cards with windows or a label start picked; empty plain cards don't.
  function resetProfilePick() {
    var pick = {}
    var ids = root.displayIds
    for (var i = 0; i < ids.length; i++) {
      var l = root.labelFor(ids[i])
      pick[ids[i]] = root.toplevelsOf(ids[i]).length > 0 || Object.keys(l).length > 0
    }
    root.profilePick = pick
  }

  function toggleProfilePick(id) {
    var pick = JSON.parse(JSON.stringify(root.profilePick))
    pick[id] = !pick[id]
    root.profilePick = pick
  }

  readonly property var pickedIds: root.displayIds.filter(function(id) { return root.profilePick[id] === true })

  // What a card would be saved as, without its apps.
  function cardAsRoom(id) {
    var room = {}
    var name = root.customName(id)
    if (name !== "") room.name = name
    if (root.customIcon(id) !== "") {
      room.icon = root.customIcon(id)
      if (root.customIconTint(id)) room.iconTint = true
    } else if (root.customEmoji(id) !== "") {
      room.emoji = root.customEmoji(id)
    }
    if (root.customColor(id) !== "") room.color = root.customColor(id)
    return room
  }

  function saveProfile(name) {
    var ids = root.pickedIds
    if (ids.length === 0 || profileCapture.running) {
      root.profileNotice = ids.length === 0 ? "Pick at least one card." : ""
      return
    }
    name = String(name || "").trim().slice(0, 40) || ("Profile " + (root.profiles.length + 1))
    root.pendingProfile = { name: name, ids: ids, rooms: ids.map(root.cardAsRoom) }
    profileCapture.command = [root.roomScript, "capture-deck"].concat(ids.map(String))
    profileCapture.running = true
    root.profileNotice = "Saving…"
  }

  // Rooms go to ws-room on stdin, not as arguments, so their folders and
  // commands never show up in `ps`. While it runs (until the apps are up or
  // it gives up), profiles can't be opened again.
  function launchRooms(deck) {
    if (profileLauncher.running) {
      // A room opened while a profile is still starting: run it on its own.
      var extra = launcherComponent.createObject(root, { payload: JSON.stringify(deck) })
      if (extra) extra.running = true
      return
    }
    profileLauncher.payload = JSON.stringify(deck)
    profileLauncher.running = true
  }

  component RoomLauncher: Process {
    property string payload: ""
    command: [root.roomScript, "launch-deck", "-"]
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
  }

  RoomLauncher {
    id: profileLauncher
    onExited: function(code) {
      if (code !== 0) root.logLine("room launch exited " + code)
    }
  }

  Component {
    id: launcherComponent
    RoomLauncher {
      onExited: destroy()
    }
  }

  Process {
    id: profileCapture
    stdout: StdioCollector { id: profileCaptureOut; waitForEnd: true }
    onExited: function(code) { root.finishProfileSave(String(profileCaptureOut.text), code) }
  }

  // ws-room capture-deck output: {"<ws>": [app, ...]} with one list for
  // every id asked for. Returns that map, or null if ws-room failed, the
  // JSON is broken, or any card's list is missing or malformed, so a
  // failed read can never be saved as "no apps".
  function readDeck(text, code, ids) {
    if (code !== 0) return null
    var deck
    try {
      deck = JSON.parse(text)
    } catch (e) {
      return null
    }
    if (deck === null || typeof deck !== "object" || Array.isArray(deck)) return null
    for (var i = 0; i < ids.length; i++) {
      if (!root.validAppList(deck[String(ids[i])])) return null
    }
    return deck
  }

  // A captured app list as ws-room writes it: [{class, argv: [...], ...}].
  function validAppList(list) {
    if (!Array.isArray(list)) return false
    for (var j = 0; j < list.length; j++) {
      var app = list[j]
      if (app === null || typeof app !== "object" || Array.isArray(app)
          || typeof app["class"] !== "string" || !Array.isArray(app.argv)) return false
    }
    return true
  }

  // The typed name matches a saved profile: saving replaces it.
  function profileNamed(name) {
    var n = String(name || "").trim().toLowerCase()
    if (n === "") return null
    for (var i = 0; i < root.profiles.length; i++) {
      if (String(root.profiles[i].name).toLowerCase() === n) return root.profiles[i]
    }
    return null
  }

  function finishProfileSave(text, code) {
    var p = root.pendingProfile
    root.pendingProfile = null
    if (p === null) return
    var deck = root.readDeck(text, code, p.ids)
    if (deck === null) {
      // Nothing saved; a profile of the same name keeps its apps.
      root.logLine("profile capture failed (exit " + code + "), nothing saved")
      root.profileNotice = "Couldn't read the open apps, so nothing was saved" +
        (root.profileNamed(p.name) !== null ? " and \u201c" + p.name + "\u201d is unchanged." : ".") + " Try again."
      return
    }
    var apps = 0
    for (var i = 0; i < p.ids.length; i++) {
      p.rooms[i].apps = deck[String(p.ids[i])].slice(0, 30)
      apps += p.rooms[i].apps.length
    }
    var list = root.profiles.filter(function(q) {
      return String(q.name).toLowerCase() !== p.name.toLowerCase()
    })
    var replaced = list.length !== root.profiles.length
    if (list.length >= root.maxProfiles) {
      root.profileNotice = "Profile limit reached (" + root.maxProfiles + "). Delete one first."
      return
    }
    list.push({ name: p.name, rooms: p.rooms })
    root.persistProfiles(list)
    // The bar is this profile now: opening it again only tops it up.
    root.setActiveProfile(p.name, p.ids)
    root.profileNotice = (replaced ? "Updated " : "Saved ") + "“" + p.name + "”: " +
      p.rooms.length + (p.rooms.length === 1 ? " card, " : " cards, ") + apps + (apps === 1 ? " app." : " apps.")
    profileNameField.text = ""
  }

  // Workspaces 1-10 that have windows right now.
  function busyIds() {
    var out = []
    for (var n = 1; n <= 10; n++) {
      if (root.toplevelsOf(n).length > 0) out.push(n)
    }
    return out
  }

  // Open from the list: ask first when other cards still have apps open.
  function requestProfile(index) {
    var p = root.profiles[index]
    if (!p) return
    root.profileNotice = ""
    if (root.profileOnBar(p)) {
      root.profileNotice = "\u201c" + p.name + "\u201d is already open."
      return
    }
    if (root.profileBusy) {
      root.profileNotice = "Still opening the last profile\u2026 wait until its apps are up."
      return
    }
    var dupes = root.profileMatch(p).dupes
    if (dupes.length > 0) {
      root.profileNotice = "\u26a0 " + dupes.map(function(d) { return "\u201c" + d + "\u201d" }).join(", ") +
        (dupes.length === 1 ? " is" : " are") + " on the bar twice. Delete the copy you don't want, then open the profile."
      return
    }
    if (root.otherBusyIds(p).length > 0) root.profileConfirm = index
    else root.openProfile(index, "close")
  }

  // Replace the bar with the profile's cards. `others` says what happens to
  // cards that still have windows: "close" closes their apps (each card goes
  // once its last window is gone, as with Delete), "keep" leaves them after
  // the profile's cards. Empty cards not in the profile are removed.
  function openProfile(index, others) {
    root.profileConfirm = -1
    var p = root.profiles[index]
    if (!p || root.profileBusy || root.profileOnBar(p) || root.profileMatch(p).dupes.length > 0) return
    var rooms = []
    for (var r = 0; r < (p.rooms.length || 0); r++) rooms.push(p.rooms[r])
    // Cards already on the bar are reused (only their missing apps start);
    // the rest get free workspaces.
    var slots = root.profileSlots(p)
    var busy = root.otherBusyIds(p)
    var free = []
    for (var n = 1; n <= 10; n++) {
      if (busy.indexOf(n) === -1 && slots.indexOf(n) === -1) free.push(n)
    }
    var need = slots.filter(function(x) { return x < 0 }).length
    if (free.length < need) {
      root.profileNotice = "Needs " + need + " free workspaces, only " + free.length +
        " have no windows. Close some apps first."
      return
    }
    var ids = slots.map(function(x) { return x > 0 ? x : free.shift() })

    var labels = {}
    var order = ids.slice()
    if (others === "keep") {
      var kept = root.displayIds.filter(function(id) { return busy.indexOf(id) !== -1 })
      for (var b = 0; b < busy.length; b++) {
        if (kept.indexOf(busy[b]) === -1) kept.push(busy[b])
      }
      for (var k = 0; k < kept.length; k++) {
        order.push(kept[k])
        if (root.labels[String(kept[k])]) labels[String(kept[k])] = root.labels[String(kept[k])]
      }
    }
    for (var i = 0; i < ids.length; i++) {
      var room = rooms[i]
      var entry = {}
      if (room.name) entry.name = String(room.name)
      if (root.validIcon(room.icon) !== "") {
        entry.icon = root.validIcon(room.icon)
        if (room.iconTint === true) entry.iconTint = true
      } else if (room.emoji) {
        entry.emoji = String(room.emoji)
      }
      if (/^#[0-9a-fA-F]{6}$/.test(String(room.color || ""))) entry.color = String(room.color)
      if (Object.keys(entry).length > 0) labels[String(ids[i])] = entry
    }
    var hidden = []
    for (var h = 1; h <= 10; h++) {
      if (order.indexOf(h) === -1) hidden.push(h)
    }

    if (others !== "keep" && busy.length > 0) {
      var pending = JSON.parse(JSON.stringify(root.pendingDeletes))
      for (var c = 0; c < busy.length; c++) {
        var wins = root.toplevelsOf(busy[c])
        for (var w = 0; w < wins.length; w++) {
          root.dispatch("hl.dsp.window.close({ window = " + root.luaQuote("address:" + root.hexAddress(wins[w])) + " })")
        }
        pending[String(busy[c])] = Date.now()
      }
      root.pendingDeletes = pending
    }

    root.localLabels = labels
    root.localHidden = hidden
    root.localOrder = order
    root.persistAll(order, hidden, labels)
    root.settingsOpen = false
    root.setActiveProfile(p.name, ids)
    // Reused cards that have windows: read what is open there (and in which
    // folder) before deciding what to start. Open stays locked meanwhile and
    // until ws-room has placed the apps (or given up), so a second click
    // can't start them again.
    var plan = { ids: ids, rooms: rooms, slots: slots, probe: [] }
    for (var d = 0; d < ids.length; d++) {
      if (slots[d] > 0 && root.toplevelsOf(ids[d]).length > 0 && (rooms[d].apps || []).length > 0)
        plan.probe.push(ids[d])
    }
    if (plan.probe.length === 0) {
      root.launchProfile(plan, null)
      return
    }
    root.pendingOpen = plan
    openCapture.command = [root.roomScript, "capture-deck"].concat(plan.probe.map(String))
    openCapture.running = true
  }

  property var pendingOpen: null   // profile waiting for its reused cards to be read
  readonly property bool profileBusy: profileLauncher.running || openCapture.running

  Process {
    id: openCapture
    stdout: StdioCollector { id: openCaptureOut; waitForEnd: true }
    onExited: function(code) {
      var plan = root.pendingOpen
      root.pendingOpen = null
      if (plan === null) return
      var open = root.readDeck(String(openCaptureOut.text), code, plan.probe)
      if (open === null) root.logLine("profile open: couldn't read the open apps (exit " + code + "); folder apps started anyway")
      root.launchProfile(plan, open)
    }
  }

  function launchProfile(plan, open) {
    var deck = []
    for (var d = 0; d < plan.ids.length; d++) {
      var id = plan.ids[d]
      deck.push({ ws: id, apps: plan.slots[d] > 0
        ? root.missingApps(plan.rooms[d], id, open !== null && plan.probe.indexOf(id) !== -1 ? open[String(id)] : null)
        : (plan.rooms[d].apps || []) })
    }
    if (deck.length > 0) root.launchRooms(deck)
  }

  function deleteProfile(index) {
    var list = root.profiles.slice()
    var gone = list.splice(index, 1)
    root.persistProfiles(list)
    if (gone.length && root.isActiveProfile(gone[0])) root.setActiveProfile("", [])
    root.profileConfirm = -1
    root.profileNotice = gone.length ? "Deleted “" + gone[0].name + "”." : ""
  }

  // "💻 Code · 🎵 Music · 3" and the app count.
  function profileSummary(p) {
    var rooms = []
    var raw = p && p.rooms ? p.rooms : []
    for (var i = 0; i < (raw.length || 0); i++) rooms.push(raw[i])
    var apps = 0
    var parts = rooms.map(function(r, i) {
      var a = r.apps ? (r.apps.length || 0) : 0
      apps += a
      var name = String(r.name || "") || ("Card " + (i + 1))
      return (r.emoji && !r.icon ? r.emoji + " " : "") + name
    })
    return parts.join(" · ") + "  —  " + apps + (apps === 1 ? " app" : " apps")
  }

  // Panel tabs (right-click +): settings | rooms | profiles | guide | about
  property string panelTab: "settings"
  onPanelTabChanged: if (root.panelTab === "profiles") root.resetProfilePick()

  property string draftColor: ""
  property string draftEmoji: ""
  property string draftIcon: ""
  property bool draftIconTint: false

  // Picking an emoji drops the icon and the other way round: a card shows one.
  function pickEmoji(e) {
    root.draftEmoji = e
    if (e !== "") root.draftIcon = ""
  }

  function pickIcon(name) {
    root.draftIcon = name
    if (name !== "") root.draftEmoji = ""
  }

  // Files in iconDir. The folder model watches the directory, so icons added
  // or removed in a file manager show up in the editor straight away.
  property var customIcons: []
  property bool emojiIconTab: false

  FolderListModel {
    id: iconFolder
    folder: "file://" + root.iconDir.split("/").map(encodeURIComponent).join("/")
    nameFilters: ["*.svg", "*.png", "*.jpg", "*.jpeg", "*.webp"]
    caseSensitive: false
    showDirs: false
    sortField: FolderListModel.Name
    sortCaseSensitive: false
    onCountChanged: root.rebuildIcons()
    onStatusChanged: root.rebuildIcons()
  }

  function rebuildIcons() {
    var out = []
    for (var i = 0; i < iconFolder.count; i++) {
      var n = root.validIcon(iconFolder.get(i, "fileName"))
      if (n !== "") out.push(n)
    }
    root.customIcons = out
  }

  // The folder model can't watch a folder that doesn't exist yet.
  function ensureIconDir() {
    Quickshell.execDetached(["mkdir", "-p", "--", root.iconDir])
  }

  function openIconFolder() {
    Quickshell.execDetached(["sh", "-c", 'mkdir -p -- "$1" && xdg-open "$1"', "sh", root.iconDir])
  }

  // ---- Adding icons ----
  // Copies image files into iconDir and prints the names they ended up with.
  // A file already there is reused; a different file with the same name gets
  // "-2", "-3"… so nothing is overwritten.
  readonly property string importScript:
    'dir=$1; shift; mkdir -p -- "$dir" || exit 1\n' +
    'for f in "$@"; do\n' +
    '  [ -f "$f" ] || continue\n' +
    '  b=$(basename -- "$f"); t="$dir/$b"\n' +
    '  if [ -e "$t" ] && ! cmp -s -- "$f" "$t"; then\n' +
    '    stem=${b%.*}; ext=${b##*.}; n=2\n' +
    '    while [ -e "$dir/$stem-$n.$ext" ] && ! cmp -s -- "$f" "$dir/$stem-$n.$ext"; do n=$((n+1)); done\n' +
    '    t="$dir/$stem-$n.$ext"\n' +
    '  fi\n' +
    '  [ -e "$t" ] || cp -- "$f" "$t" || continue\n' +
    '  basename -- "$t"\n' +
    'done\n'

  // What to do with the imported names: { mode: "library" }.
  property var importThen: null

  Process {
    id: iconImport
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishImport(String(text).split("\n").filter(function(n) {
        return root.validIcon(n) !== ""
      }))
    }
  }

  function imagePathsFromUrls(urls) {
    var out = []
    for (var i = 0; i < (urls ? urls.length : 0); i++) {
      var u = String(urls[i])
      if (u.indexOf("file://") !== 0) continue
      var path = decodeURIComponent(u.slice(7).replace(/^[^\/]*/, ""))
      if (root.iconExtensions.test(path)) out.push(path)
    }
    return out
  }

  // ---- Icon library window ----
  // A normal app window, not a panel: panels close on any click outside
  // them, so you couldn't drag files from a file manager into one. This one
  // stays open beside the file manager and takes drops. Opened from the
  // card editor; clicking an icon takes it back to the editor with that icon.
  property bool libraryOpen: false
  property int libraryForId: -1
  property var libraryDraft: null
  property var libraryNew: []         // names just added, highlighted
  property string libraryNotice: ""
  property bool libraryDragOver: false

  function editorDraft() {
    return { name: nameField.text, emoji: root.draftEmoji, icon: root.draftIcon,
      tint: root.draftIconTint, color: root.draftColor }
  }

  function openIconLibrary() {
    root.libraryForId = root.editingId
    root.libraryDraft = root.editingId >= 0 ? root.editorDraft() : null
    root.libraryNew = []
    root.libraryNotice = ""
    root.cancelRename()
    root.ensureIconDir()
    root.libraryOpen = true
  }

  // Back to the card editor (with `icon` picked, if given).
  function closeIconLibrary(icon) {
    var id = root.libraryForId
    var draft = root.libraryDraft
    root.libraryOpen = false
    root.libraryForId = -1
    root.libraryDraft = null
    if (id < 0 || draft === null) return
    var item = root.cardItem(id)
    if (item === null) return
    if (icon) {
      draft.icon = icon
      draft.emoji = ""
    }
    root.resumeDraft = { id: id, draft: draft, iconTab: true }
    root.startRename(id, item)
  }

  function importToLibrary(paths) {
    if (paths.length === 0 || iconImport.running) return false
    root.importThen = { mode: "library" }
    iconImport.command = ["bash", "-c", root.importScript, "bash", root.iconDir].concat(paths)
    iconImport.running = true
    return true
  }

  // "Add images…": the desktop file chooser, then the same import.
  function pickIconFiles() {
    if (iconImport.running) return
    root.importThen = { mode: "library" }
    iconImport.command = ["bash", "-c",
      'mapfile -t files < <(omarchy-file-select --title "Add icons to HUD Workspaces" --multiple ' +
      '--extensions "svg png jpg jpeg webp")\n' +
      'set -- "$1" "${files[@]}"\n' + root.importScript,
      "bash", root.iconDir]
    iconImport.running = true
  }

  // "Add icon from file…" in the card editor: no drag needed. The editor is a
  // panel that closes on any click outside it, so dropping a file onto it
  // can't work. Instead the editor steps aside, the file chooser picks an
  // image, and the editor comes back with that icon set (or unchanged if the
  // chooser was cancelled).
  function pickIconForCard() {
    if (iconImport.running || root.editingId < 0) return
    root.importThen = { mode: "card", id: root.editingId, draft: root.editorDraft() }
    root.cancelRename()
    root.ensureIconDir()
    iconImport.command = ["bash", "-c",
      'mapfile -t files < <(omarchy-file-select --title "Choose an icon for this card" ' +
      '--extensions "svg png jpg jpeg webp")\n' +
      'set -- "$1" "${files[@]}"\n' + root.importScript,
      "bash", root.iconDir]
    iconImport.running = true
  }

  function cardItem(id) {
    for (var i = 0; i < grid.children.length; i++) {
      if (grid.children[i].modelData === id) return grid.children[i]
    }
    // A card in the overflow stack: its editor hangs off the stack chip.
    return root.stackIds.indexOf(id) !== -1 ? stackBtn : null
  }

  property var resumeDraft: null

  function finishImport(names) {
    var then = root.importThen
    root.importThen = null
    if (then === null) return
    // Card editor: reopen it with the chosen icon (draft kept either way).
    if (then.mode === "card") {
      var item = root.cardItem(then.id)
      if (item === null) return
      if (names.length > 0) {
        then.draft.icon = names[0]
        then.draft.emoji = ""
      }
      root.resumeDraft = { id: then.id, draft: then.draft, iconTab: true }
      root.startRename(then.id, item)
      return
    }
    // Library: highlight what came in.
    root.libraryNew = root.libraryNew.filter(function(n) { return names.indexOf(n) === -1 }).concat(names)
    root.libraryNotice = names.length === 0 ? ""
      : "Added " + names.length + (names.length === 1 ? " icon" : " icons") +
        (root.libraryForId >= 0 ? ". Click one to use it." : ".")
  }

  // Full emoji list, shared with the shell's own emoji picker.
  property var allEmojis: []
  property string emojiQuery: ""
  property bool emojiRecentTab: false
  readonly property var emojiResults: {
    var raw = root.emojiQuery.trim()
    var needle = raw.toLowerCase()
    if (root.emojiIconTab) {
      return root.customIcons.filter(function(n) { return n.toLowerCase().indexOf(needle) >= 0 })
        .map(function(n) { return { i: n, k: n } })
    }
    if (needle === "") {
      if (root.emojiRecentTab) return root.recentEmoji.map(function(e) { return { e: e, k: "" } })
      return root.allEmojis
    }
    var out = []
    var exact = false
    for (var i = 0; i < root.allEmojis.length; i++) {
      var item = root.allEmojis[i]
      if (item.e === raw) exact = true
      if (String(item.k || "").toLowerCase().indexOf(needle) >= 0) out.push(item)
    }
    // A pasted emoji (no letters or digits) is offered as-is, so skin tones
    // and emoji newer than the list work too.
    if (!exact && /^[^\x00-\x7f]+$/.test(raw)) out.unshift({ e: raw, k: "pasted" })
    return out
  }

  // Category jump bar. The list is in Unicode order, so each category starts
  // at its first emoji; one missing from the list just drops its tab.
  readonly property var emojiCategoryStarts: [
    { icon: "😀", name: "Smileys", first: "😀" },
    { icon: "👋", name: "People", first: "👋" },
    { icon: "🐵", name: "Animals & nature", first: "🐵" },
    { icon: "🍇", name: "Food & drink", first: "🍇" },
    { icon: "🌍", name: "Travel & places", first: "🌍" },
    { icon: "🎃", name: "Activities", first: "🎃" },
    { icon: "👓", name: "Objects", first: "👓" },
    { icon: "💟", name: "Symbols", first: "🏧" },
    { icon: "🏁", name: "Flags", first: "🏁" }
  ]
  readonly property var emojiCategories: {
    var out = []
    for (var c = 0; c < root.emojiCategoryStarts.length; c++) {
      var cat = root.emojiCategoryStarts[c]
      for (var i = 0; i < root.allEmojis.length; i++) {
        if (root.allEmojis[i].e === cat.first) {
          out.push({ icon: cat.icon, name: cat.name, start: i })
          break
        }
      }
    }
    return out
  }

  // Tab picked by a click; scrolling hands the highlight back to the scroll
  // position (the last categories can't scroll to the top of the grid).
  property int emojiJumpStart: -1

  function jumpToEmojiCategory(start) {
    root.emojiRecentTab = false
    root.emojiIconTab = false
    root.emojiJumpStart = start
    emojiSearch.text = ""
    Qt.callLater(function() { emojiGrid.positionViewAtIndex(start, GridView.Beginning) })
  }

  // ---- Custom colour (picker in the editor) ----
  property bool colorPickerOpen: false
  property real pickHue: 0
  property real pickSat: 0.7
  property real pickVal: 0.9
  property bool pickSyncing: false

  function hexOf(c) {
    function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }

  function setFromPicker() {
    root.pickSyncing = true
    root.draftColor = root.hexOf(Qt.hsva(root.pickHue, root.pickSat, root.pickVal, 1))
    root.pickSyncing = false
  }

  // Move the picker to a colour chosen elsewhere (swatch, hex field).
  onDraftColorChanged: {
    if (root.pickSyncing || !/^#[0-9a-fA-F]{6}$/.test(root.draftColor)) return
    var c = Qt.color(root.draftColor)
    if (c.hsvHue >= 0) root.pickHue = c.hsvHue
    root.pickSat = c.hsvSaturation
    root.pickVal = c.hsvValue
  }

  FileView {
    // The shell's emoji list; if a shell update moves it, the picker says
    // "Emoji list unavailable" (custom icons and pasted emoji still work).
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins/emojis/emojis.json"
    onLoadFailed: function(error) {
      root.allEmojis = []
      root.logLine("emoji list not found at " + path)
    }
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.allEmojis = Array.isArray(data) ? data.filter(function(item) { return item && item.e }) : []
      } catch (e) {
        root.allEmojis = []
      }
    }
  }

  function commitEdit() {
    if (root.editingId >= 0) {
      root.saveLabel(root.editingId, nameField.text, root.draftEmoji, root.draftColor,
        root.draftIcon, root.draftIconTint)
    }
    root.cancelRename()
  }

  function resetEdit() {
    if (root.editingId >= 0) root.saveLabel(root.editingId, "", "", "")
    root.cancelRename()
  }

  function nextWorkspaceId() {
    var ids = root.workspaceIds()
    var used = {}
    for (var i = 0; i < ids.length; i++) used[ids[i]] = true
    for (var n = 1; n <= 10; n++) {
      if (!used[n]) return n
    }
    return ids.length > 0 ? Math.max.apply(null, ids) + 1 : 1
  }



  // Toplevels of the previewed workspace, most-recently-focused first.
  // Hyprland's IPC mirror pushes window opens, closes, focus and title
  // changes through property notifications, so this rebinds with no polling.
  function previewToplevels() {
    if (root.previewId < 0) return []
    var ws = root.workspaceById(root.previewId)
    if (ws === null) return []

    var out = []
    var vals = ws.toplevels.values
    for (var i = 0; i < vals.length; i++) {
      var t = vals[i]
      var ipc = t.lastIpcObject
      if (ipc && (ipc.mapped === false || ipc.hidden === true)) continue
      out.push(t)
    }
    out.sort(function(left, right) {
      var leftIpc = left.lastIpcObject || {}
      var rightIpc = right.lastIpcObject || {}
      var leftFh = Number(leftIpc.focusHistoryID)
      var rightFh = Number(rightIpc.focusHistoryID)
      if (!isFinite(leftFh)) leftFh = 99
      if (!isFinite(rightFh)) rightFh = 99
      if (leftFh !== rightFh) return leftFh - rightFh
      return String(left.title || "").localeCompare(String(right.title || ""))
    })
    return out
  }

  readonly property var previewList: root.previewToplevels()
  readonly property var previewRows: root.previewList.slice(0, 6)
  readonly property int previewOverflow: root.previewList.length - root.previewRows.length

  function previewAppId(t) {
    var ipc = t.lastIpcObject || {}
    return String((t.wayland && t.wayland.appId) || ipc.class || "")
  }

  function previewTitle(t) {
    return String(t.title || "")
  }

  function previewIconSource(t) {
    var name = root.previewAppId(t)
    if (name.length === 0) return ""
    return Quickshell.iconPath(name, true)
  }

  function previewActivate(t) {
    if (t.wayland) t.wayland.activate()
  }

  function previewHoverEnter(id, item) {
    previewCloseTimer.stop()
    if (root.bar) root.bar.hideTooltip(item)
    if (root.dragId >= 0) return

    if (root.previewId >= 0) {
      if (root.previewId !== id) {
        root.previewId = id
        root.previewAnchor = item
      }
      return
    }
    root.previewAnchor = item
    root.pendingPreviewId = id
    previewOpenTimer.restart()
  }

  function previewHoverExit(id) {
    if (root.previewId < 0) {
      if (root.pendingPreviewId === id) {
        previewOpenTimer.stop()
        root.pendingPreviewId = -1
      }
      return
    }
    if (root.previewId === id) previewCloseTimer.restart()
  }

  function previewCloseNow() {
    previewOpenTimer.stop()
    previewCloseTimer.stop()
    root.previewId = -1
    root.pendingPreviewId = -1
    root.previewAnchor = null
  }

  Timer {
    id: previewOpenTimer
    interval: 160
    onTriggered: {
      if (root.dragId >= 0) {
        root.pendingPreviewId = -1
        return
      }
      root.previewId = root.pendingPreviewId
      root.pendingPreviewId = -1
    }
  }

  Timer {
    id: previewCloseTimer
    interval: 260
    onTriggered: {
      if (root.previewPopupHovered) return
      if (root.previewAnchor && root.previewAnchor.tooltipHovered) return
      root.previewId = -1
      root.previewAnchor = null
    }
  }

  // Pointer-drag reorder state: the workspace number being held, the card it
  // is currently hovering (insertion target), the pointer in scene coords,
  // and the ghost card's velocity tilt. `dropIndex` is the slot the held
  // card would land in; `prevSlots` snapshots visual positions for the
  // settle animation of the rebuilt cards.
  property int dragId: -1
  property int dropTargetId: -1
  property real ghostX: 0
  property real ghostY: 0
  property real ghostTilt: 0
  property var prevSlots: ({})
  property int dropIndex: -1

  Behavior on ghostTilt {
    NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      // event.name/data come through as QString, so compare as strings.
      if (String(event.name) === "configreloaded") {
        root.applyTransition()
        return
      }
      if (String(event.name) !== "custom") return

      var parts = String(event.data).split(",")
      if (parts[0] !== "wsdrag" || parts.length < 4) return

      root.dropAt(parts[1], Number(parts[2]), Number(parts[3]))
    }
  }

  function applyWorkspaceDrop(id, address) {
    root.dropFlash = id
    flash.restart()
    dropIndicator.showFor(id)

    // Keep the 0x prefix: Hyprland's `address:` selector does not match
    // without it. Drop anything that isn't hex.
    var hex = String(address).toLowerCase()
    if (hex.indexOf("0x") !== 0) return

    var digits = ""
    for (var i = 2; i < hex.length; i++) {
      var ch = hex.charAt(i)
      if ((ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")) digits += ch
    }
    if (digits.length === 0) return

    // Hyprland 0.56 routes `hyprctl dispatch` through the Lua bindings, so the
    // classic `movetoworkspace N,address:0x...` string is not valid there.
    // This is the Lua equivalent: hl.dsp.window.move{workspace, window}.
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = " + Number(id) +
      ", window = " + root.luaQuote("address:0x" + digits) + " })"])
  }

  Timer {
    id: flash
    interval: 350
    onTriggered: root.dropFlash = 0
  }

  DropIndicator {
    id: dropIndicator
  }

  // The room preview: opens under the hovered card (above it on a bottom
  // bar) and lists what runs inside that workspace. Hover-mode PopupCard
  // skips the focus grab, so the cursor can travel into the popup freely.
  PopupCard {
    id: previewCard
    anchorItem: root.previewAnchor
    owner: previewOwner
    bar: root.bar
    triggerMode: "hover"
    open: root.previewId >= 0 && root.previewAnchor !== null
    contentWidth: previewCard.fittedContentWidth(Style.space(300))
    contentHeight: previewCard.fittedContentHeight(previewColumn.implicitHeight)

    onContainsMouseChanged: {
      root.previewPopupHovered = containsMouse
      if (containsMouse) previewCloseTimer.stop()
      else previewCloseTimer.restart()
    }

    Column {
      id: previewColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Shape {
          id: previewToken
          width: Style.space(20)
          height: Style.space(20)

          ShapePath {
            strokeWidth: 1
            fillColor: root.previewFocused ? Util.alpha(Color.accent, 0.2)
              : Util.alpha(Color.foreground, 0.08)
            strokeColor: root.previewFocused ? Util.alpha(Color.accent, 0.9)
              : Util.alpha(Color.foreground, 0.25)
            PathSvg { path: root.panelPath(previewToken.width, previewToken.height) }
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.previewId < 0 ? "" : root.displayLabel(root.previewId)
            color: root.previewFocused ? Color.accent : root.previewFg
            font.family: root.previewFont
            font.pixelSize: Style.font.body
            font.bold: true
            renderType: Text.NativeRendering
          }
        }

        Column {
          width: parent.width - Style.space(28)
          spacing: 0

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: root.previewId < 0 ? ""
              : (root.customName(root.previewId)
                || "Workspace " + (root.previewId === 10 ? "0" : String(root.previewId)))
            color: root.previewFg
            font.family: root.previewFont
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text.length > 0
            text: root.previewList.length > 0
              ? root.previewList.length + (root.previewList.length === 1 ? " window" : " windows")
              : ""
            color: Qt.darker(root.previewFg, 1.5)
            font.family: root.previewFont
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: root.previewList.length > 0
        color: Util.alpha(root.previewFg, 0.12)
      }

      Text {
        textFormat: Text.PlainText
        visible: root.previewList.length === 0
        text: "No applications running"
        color: Qt.darker(root.previewFg, 1.5)
        font.family: root.previewFont
        font.pixelSize: Style.font.body
        font.italic: true
      }

      Repeater {
        model: root.previewRows

        delegate: Rectangle {
          required property var modelData

          width: parent.width
          height: Style.space(32)
          radius: Style.space(5)
          color: rowMouse.containsMouse
            ? Util.alpha(root.previewFg, 0.07) : "transparent"

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.previewActivate(modelData)
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              radius: Style.space(4)
              color: Style.normalFillFor(root.previewFg, Color.accent)

              Image {
                id: rowIcon
                anchors.fill: parent
                anchors.margins: 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: root.previewIconSource(modelData)
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: rowIcon.source === ""
                text: {
                  var app = root.previewAppId(modelData)
                  return app.length > 0 ? app.charAt(0).toUpperCase() : "?"
                }
                color: root.previewFg
                font.family: root.previewFont
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Column {
              width: parent.width - Style.space(26)
              spacing: 0

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.previewTitle(modelData) || root.previewAppId(modelData)
                color: modelData.activated ? Color.accent : root.previewFg
                font.family: root.previewFont
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: text.length > 0
                text: {
                  var app = root.previewAppId(modelData)
                  return app === root.previewTitle(modelData) ? "" : app
                }
                color: Qt.darker(root.previewFg, 1.6)
                font.family: root.previewFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.previewOverflow > 0
        text: "+" + root.previewOverflow + " more"
        color: Qt.darker(root.previewFg, 1.6)
        font.family: root.previewFont
        font.pixelSize: Style.font.caption
        font.italic: true
      }

      Text {
        textFormat: Text.PlainText
        text: "Drag a card to reorder"
        color: Util.alpha(root.previewFg, 0.55)
        font.family: root.previewFont
        font.pixelSize: Style.font.caption
        font.italic: true
      }
    }
  }

  // Chip geometry. The row is laid out by hand (slot positions + animated
  // translates) instead of by a GridLayout so every move can ease instead of
  // snapping when the order changes.
  // Room between cards so borders, the focus corners and the slide/glide
  // animations never paint over a neighbour.
  readonly property real hGap: Style.space(3)
  readonly property real vGap: Style.space(2)
  readonly property real chipW: root.vertical ? root.barSize : Style.space(20)
  readonly property real chipH: root.barSize
  readonly property int chipCount: root.workspaceIds().length
  // Chamfered HUD panel geometry shared by the chip plate, the drop-target
  // frame and the lifted ghost card: corners cut at top-left and bottom-right.
  function panelCut(w, h) {
    return Math.max(3, Math.min(6, Math.floor(Math.min(w, h) * 0.2)))
  }

  function panelPath(w, h) {
    var c = root.panelCut(w, h)
    return "M" + c + ",0 L" + w + ",0 L" + w + "," + (h - c)
      + " L" + (w - c) + "," + h + " L0," + h + " L0," + c + " Z"
  }
  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // Card sizes along the row. Named cards on a horizontal bar grow to fit
  // "emoji name" (capped, then elided); everything else keeps the fixed chip.
  readonly property real cardPad: Style.space(7)
  readonly property real maxCardW: Style.space(130)
  readonly property real rowGap: root.vertical ? root.vGap : root.hGap

  // Emoji glyphs come from the colour-emoji font: the bar font carries its
  // own monochrome versions of some, which would otherwise win.
  readonly property string emojiFont: "Noto Color Emoji"
  readonly property real emojiSize: Style.font.subtitle + 2
  readonly property real emojiGap: Style.space(3)
  // Colour-emoji glyphs draw wider than their pixel size (and ZWJ / flag /
  // skin-tone sequences wider still), so an emoji gets a fixed box this wide
  // and shrinks to fit it instead of spilling into the next card.
  readonly property real emojiBoxW: Math.ceil(root.emojiSize * 1.25)

  // A custom icon file, as is or (tint) filled with one colour through its
  // alpha, so one-colour icons follow the card text like the number does.
  component MarkIcon: Item {
    id: markIcon
    property string source: ""
    property bool tint: false
    property color tintColor: Color.foreground

    Image {
      id: markImage
      anchors.fill: parent
      source: markIcon.source
      sourceSize: Qt.size(Math.ceil(markIcon.width * 2), Math.ceil(markIcon.height * 2))
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
      visible: !markIcon.tint
      layer.enabled: markIcon.tint
    }

    Rectangle {
      anchors.fill: parent
      visible: markIcon.tint
      color: markIcon.tintColor
      layer.enabled: markIcon.tint
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: markImage
        // Soft edge: coverage ramps with the icon's alpha (0 → 1).
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }
  }

  // The "Your icons" tab mark: a tiny HUD card (the bar's cut-corner shape)
  // holding a mountain-and-sun picture.
  component HudIconGlyph: Shape {
    id: glyph
    property color color: Color.accent
    readonly property real cut: Math.round(height * 0.3)
    width: Math.round(height * 1.3)
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: 1.5
      strokeColor: glyph.color
      fillColor: Util.alpha(Color.accent, 0.35)
      joinStyle: ShapePath.MiterJoin
      PathSvg {
        path: "M" + glyph.cut + ",0.75 L" + (glyph.width - 0.75) + ",0.75 L" + (glyph.width - 0.75) + "," +
          (glyph.height - glyph.cut) + " L" + (glyph.width - glyph.cut) + "," + (glyph.height - 0.75) +
          " L0.75," + (glyph.height - 0.75) + " L0.75," + glyph.cut + " Z"
      }
    }

    // Mountains.
    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: glyph.color
      PathSvg {
        path: "M" + glyph.width * 0.16 + "," + glyph.height * 0.78 + " L" + glyph.width * 0.4 + "," +
          glyph.height * 0.42 + " L" + glyph.width * 0.56 + "," + glyph.height * 0.62 + " L" +
          glyph.width * 0.68 + "," + glyph.height * 0.5 + " L" + glyph.width * 0.86 + "," +
          glyph.height * 0.78 + " Z"
      }
    }

    // Sun.
    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillColor: glyph.color
      PathAngleArc {
        centerX: glyph.width * 0.7
        centerY: glyph.height * 0.3
        radiusX: glyph.height * 0.11
        radiusY: glyph.height * 0.11
        startAngle: 0
        sweepAngle: 360
      }
    }
  }

  // "emoji + text" (or "icon + text") for a card or the drag ghost; the text
  // elides so the whole label always fits `maxWidth`.
  component CardLabel: Row {
    id: cardLabel
    property string emoji: ""
    property string icon: ""        // file:// url
    property bool iconTint: false
    property string label: ""
    property color labelColor: Color.foreground
    property real maxWidth: 0
    property bool nativeText: true
    // Mirrors emojiFont / emojiSize / emojiGap on the widget: an inline
    // component can't see the outer file's ids.
    property string emojiFamily: "Noto Color Emoji"
    property real emojiPixelSize: Style.font.subtitle + 2
    readonly property bool hasMark: icon !== "" || emoji !== ""
    spacing: hasMark && label !== "" ? Style.space(3) : 0

    MarkIcon {
      id: iconMark
      visible: cardLabel.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: cardLabel.emojiPixelSize
      height: cardLabel.emojiPixelSize
      source: cardLabel.icon
      tint: cardLabel.iconTint
      tintColor: cardLabel.labelColor
    }

    // Fixed box (capped by maxWidth) with the glyph shrunk to fit, so a wide
    // or multi-codepoint emoji can never paint past its card.
    Text {
      textFormat: Text.PlainText
      id: emojiText
      visible: cardLabel.icon === "" && cardLabel.emoji !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: cardLabel.maxWidth > 0
        ? Math.min(Math.ceil(cardLabel.emojiPixelSize * 1.25), cardLabel.maxWidth)
        : Math.ceil(cardLabel.emojiPixelSize * 1.25)
      height: cardLabel.emojiPixelSize + 2
      text: cardLabel.emoji
      font.family: cardLabel.emojiFamily
      font.pixelSize: cardLabel.emojiPixelSize
      fontSizeMode: Text.Fit
      minimumPixelSize: 6
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      renderType: Text.QtRendering
    }

    Text {
      textFormat: Text.PlainText
      visible: cardLabel.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, cardLabel.maxWidth
        - (emojiText.visible ? emojiText.width + cardLabel.spacing : 0)
        - (iconMark.visible ? iconMark.width + cardLabel.spacing : 0)))
      elide: Text.ElideRight
      text: cardLabel.label
      color: cardLabel.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
      renderType: cardLabel.nativeText ? Text.NativeRendering : Text.QtRendering
    }
  }

  FontMetrics {
    id: labelMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  // ---- Fitting the bar ----
  // The cards never run into the next thing on the bar (the clock, the
  // centre or right modules). `fitRoom` is the space from the start of this
  // widget to the first module after it that isn't in its own section,
  // minus the widths of the modules that follow it in its own section. It is
  // measured from the bar itself a few times a second (the clock and the
  // indicators change width) and whenever the cards change. When the cards
  // don't fit, named cards first shorten their names (elided, full name in
  // the tooltip) down to a readable length. If that still isn't enough:
  //   overflow "stack" (default): the cards that fit stay, the rest go into
  //     a stack chip that fans them out in a popup on click;
  //   overflow "shrink": names shorten further, then every card becomes a
  //     compact chip showing just its emoji, icon or number.
  property real fitRoom: Infinity
  readonly property bool stackOverflow: String(root.setting("overflow", "stack")) !== "shrink"
  readonly property real stackW: Style.space(40)
  // With more cards than this, every card goes into the stack and the chip
  // shows the active one (0: only the cards that don't fit are stacked).
  readonly property int stackAfter: {
    var n = Number(root.setting("stackAfter", 0))
    return isFinite(n) && n > 0 ? Math.min(10, Math.floor(n)) : 0
  }

  function isModuleSlot(item) {
    return item && item.entry !== undefined && item.region !== undefined && item.moduleName !== undefined
  }

  function collectSlots(item, out) {
    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid) continue
      if (root.isModuleSlot(kid)) out.push(kid)
      else root.collectSlots(kid, out)
    }
  }

  function measureRoom() {
    var room = Infinity
    var revealed = false
    try {
      if (!root.vertical && root.bar && root.visible) {
        var mySlot = root.parent
        while (mySlot && !root.isModuleSlot(mySlot)) mySlot = mySlot.parent
        var top = root
        while (top.parent) top = top.parent
        var start = root.mapToItem(null, 0, 0).x
        var region = mySlot ? String(mySlot.region) : "left"
        var slotStart = mySlot ? mySlot.mapToItem(null, 0, 0).x : start
        var limit = Infinity
        var following = 0
        var slots = []
        root.collectSlots(top, slots)
        for (var i = 0; i < slots.length; i++) {
          var s = slots[i]
          if (s.activeItem && s.activeItem.revealInactiveIndicators === true) revealed = true
          if (s === mySlot || !s.visible || s.width <= 0) continue
          var sx = s.mapToItem(null, 0, 0).x
          if (sx <= slotStart) continue
          if (String(s.region) === region) following += s.width
          else limit = Math.min(limit, sx)
        }
        if (limit < Infinity) room = Math.max(0, limit - start - following - Style.space(12))
      }
    } catch (e) {
      room = Infinity
    }
    root.applyRoom(room, revealed)
  }

  // Hovering the bar makes it reveal its hidden indicators, which widens
  // their section and takes room from the cards, then gives it back when the
  // pointer leaves. Fitting to whatever is there at the moment made the cards
  // re-fit under the pointer on every hover (and cover the indicators until
  // they did). So the cards always leave room for the revealed state:
  // `fitReserve` is how much the reveal takes, learned whenever it happens
  // and kept in the `fitReserve` setting so it is known from the start.
  property var localReserve: null
  readonly property real fitReserve: {
    var saved = Number(root.setting("fitReserve", 0))
    return root.localReserve !== null ? root.localReserve : (isFinite(saved) && saved > 0 ? saved : 0)
  }
  property real calmRoom: Infinity      // room last measured with nothing revealed
  property bool wasRevealed: false
  property bool learnReserve: false
  property double revealFlipAt: 0

  function applyRoom(room, revealed) {
    var now = Date.now()
    if (revealed !== root.wasRevealed) {
      root.wasRevealed = revealed
      root.revealFlipAt = now
      root.learnReserve = revealed
    }
    var fit = room
    if (room !== Infinity) {
      // The reveal animates: keep the last fit until it has settled.
      if (now - root.revealFlipAt < 600) return
      if (revealed) {
        if (root.learnReserve && root.calmRoom !== Infinity) {
          root.learnReserve = false
          var reserve = Math.max(0, Math.round(root.calmRoom - room))
          if (Math.abs(reserve - root.fitReserve) > 1) {
            root.localReserve = reserve
            root.persist(root.barSet("fitReserve", reserve, true))
          }
        }
      } else {
        root.calmRoom = room
        fit = Math.max(0, room - root.fitReserve)
      }
    }
    if (Math.abs(fit - root.fitRoom) > 0.5 || (fit === Infinity) !== (root.fitRoom === Infinity))
      root.fitRoom = fit
  }

  Timer {
    interval: 400
    repeat: true
    running: !root.vertical && root.bar !== null
    triggeredOnStart: true
    onTriggered: root.measureRoom()
  }
  onDisplayIdsChanged: Qt.callLater(root.measureRoom)
  onLabelsChanged: Qt.callLater(root.measureRoom)

  // Room left for the cards themselves, after the "+" button.
  readonly property real rowRoom: root.fitRoom - (root.hGap + root.chipW + root.trailingGap)

  // Natural width of each card: named cards grow to fit "emoji name"
  // (capped at maxCardW), everything else is the fixed chip.
  function naturalSize(id) {
    if (root.vertical) return root.chipH
    if (root.customName(id) === "") return root.chipW
    return Math.ceil(Math.max(root.chipW, Math.min(root.maxCardW, root.markWidth(id)
      + labelMetrics.advanceWidth(root.customName(id)) + 2 * root.cardPad)))
  }

  function markWidth(id) {
    if (root.customIcon(id) !== "") return root.emojiSize + root.emojiGap
    if (root.customEmoji(id) !== "") return root.emojiBoxW + root.emojiGap
    return 0
  }

  // Smallest a named card gets before going compact: its mark plus "Ab…".
  function minNamedSize(id) {
    return Math.min(root.naturalSize(id), Math.ceil(Math.max(root.chipW, root.markWidth(id)
      + labelMetrics.advanceWidth("Ab…") + 2 * root.cardPad)))
  }

  // Smallest a named card gets before cards start moving into the stack:
  // its mark plus a name that can still be read.
  function readableSize(id) {
    return Math.min(root.naturalSize(id), Math.ceil(Math.max(root.chipW, root.markWidth(id)
      + labelMetrics.advanceWidth("Abcdef…") + 2 * root.cardPad)))
  }

  // { sizes: id -> width, compact, shown: how many cards stay on the bar }
  readonly property var cardLayout: {
    var ids = root.displayIds
    var n = ids.length
    var natural = {}
    var total = 0
    for (var i = 0; i < n; i++) {
      natural[ids[i]] = root.naturalSize(ids[i])
      total += natural[ids[i]]
    }
    function gapsOf(count) { return Math.max(0, count - 1) * root.rowGap }
    if (!root.vertical && root.stackOverflow && root.stackAfter > 0 && n > root.stackAfter)
      return { sizes: {}, compact: false, shown: 0 }
    var room = root.rowRoom
    if (root.vertical || room === Infinity || total + gapsOf(n) <= room)
      return { sizes: natural, compact: false, shown: n }

    var floors = {}
    for (var f = 0; f < n; f++)
      floors[ids[f]] = root.stackOverflow ? root.readableSize(ids[f]) : root.minNamedSize(ids[f])

    // The first `count` cards with named ones capped at one width.
    function sizesAt(cap, count) {
      var out = {}
      var sum = 0
      for (var j = 0; j < count; j++) {
        var id = ids[j]
        var w = natural[id]
        if (root.customName(id) !== "") w = Math.max(floors[id], Math.min(w, Math.floor(cap)))
        out[id] = w
        sum += w
      }
      return { sizes: out, total: sum }
    }
    // Sizes for the first `count` cards at the largest cap that fits in
    // `space`, or null when they don't fit even at their smallest.
    function fit(count, space) {
      if (sizesAt(0, count).total + gapsOf(count) > space) return null
      var lo = 0
      var hi = root.maxCardW
      for (var step = 0; step < 16; step++) {
        var mid = (lo + hi) / 2
        if (sizesAt(mid, count).total + gapsOf(count) <= space) lo = mid
        else hi = mid
      }
      return sizesAt(lo, count).sizes
    }

    var all = fit(n, room)
    if (all !== null) return { sizes: all, compact: false, shown: n }

    if (root.stackOverflow) {
      var space = room - root.stackW - root.rowGap
      for (var count = n - 1; count >= 1; count--) {
        var some = fit(count, space)
        if (some !== null) return { sizes: some, compact: false, shown: count }
      }
      return { sizes: {}, compact: false, shown: 0 }
    }

    var chips = {}
    for (var k = 0; k < n; k++) chips[ids[k]] = root.chipW
    return { sizes: chips, compact: true, shown: n }
  }
  readonly property var cardSizes: root.cardLayout.sizes
  readonly property bool compactCards: root.cardLayout.compact

  function sizeOf(id) {
    var size = root.cardSizes[id]
    return size !== undefined ? size : (root.vertical ? root.chipH : root.chipW)
  }

  function startsFor(ids) {
    var out = []
    var pos = 0
    for (var i = 0; i < ids.length; i++) {
      out.push(pos)
      pos += root.sizeOf(ids[i]) + root.rowGap
    }
    return out
  }

  function reordered(ids, from, to) {
    var next = ids.slice()
    var moved = next.splice(from, 1)[0]
    next.splice(to, 0, moved)
    return next
  }

  // The cards on the bar (`barIds`, the first cards in bar order) and the
  // ones in the overflow stack. `barIds` is only reassigned when the list
  // really changes, like `displayIds`, so the cards aren't rebuilt on every
  // layout pass.
  property var barIds: []
  readonly property var stackIds: root.displayIds.filter(function(id) { return root.barIds.indexOf(id) === -1 })
  readonly property bool hasStack: root.stackIds.length > 0
  onCardLayoutChanged: root.syncBar()
  onHasStackChanged: if (!root.hasStack) root.stackOpen = false
  onEditingIdChanged: if (root.editingId < 0) Qt.callLater(root.syncBar)
  onDragIdChanged: if (root.dragId < 0) Qt.callLater(root.syncBar)

  function syncBar() {
    // A change here rebuilds the cards, which would close an open editor
    // (it hangs off a card) and drop a held card; wait until they're done.
    if (root.editingId >= 0 || root.dragId >= 0) return
    var next = root.displayIds.slice(0, root.cardLayout.shown)
    var cur = root.barIds
    if (next.length === cur.length) {
      var same = true
      for (var i = 0; i < next.length && same; i++) same = next[i] === cur[i]
      if (same) return
    }
    root.barIds = next
  }

  readonly property var starts: root.startsFor(root.barIds)
  readonly property real rowLength: {
    var n = root.barIds.length
    if (n === 0) return 0
    var last = root.barIds[n - 1]
    return root.starts[n - 1] + root.sizeOf(last)
  }
  // Where the stack chip sits, and where the cards (stack chip included) end.
  readonly property real stackPos: root.rowLength + (root.barIds.length > 0 ? root.rowGap : 0)
  readonly property real cardsEnd: root.hasStack ? root.stackPos + root.stackChipW : root.rowLength

  // Every card is in the stack: the chip then also names the active card.
  readonly property bool stackAll: root.hasStack && root.barIds.length === 0
  readonly property string stackLabel: {
    var id = root.stackActiveId
    if (!root.stackAll || id < 0) return ""
    return root.customName(id) !== "" ? root.customName(id) : (root.hasMark(id) ? "" : "Workspace " + root.numberLabel(id))
  }
  readonly property real stackGap: Style.space(4)
  readonly property real stackCountW: Math.ceil(labelMetrics.advanceWidth(String(root.stackIds.length)))
    + (root.stackAll ? Style.space(10) : 0)
  // `stackW` is what the fit reserves for the chip; this is what it takes.
  readonly property real stackChipW: {
    var id = root.stackActiveId
    if (!root.stackAll || id < 0) return root.stackW
    var mark = !root.hasMark(id) ? 0 : (root.customIcon(id) !== "" ? root.emojiSize : root.emojiBoxW)
    var text = root.stackLabel !== "" ? labelMetrics.advanceWidth(root.stackLabel) : 0
    var w = mark + (mark > 0 && text > 0 ? root.emojiGap : 0) + text + root.stackGap + root.stackCountW
      + 2 * root.cardPad
    // The name gets as much room as it would on a card.
    var most = root.maxCardW + root.stackGap + root.stackCountW + 2 * root.cardPad
    var cap = root.rowRoom === Infinity ? most : Math.min(most, root.rowRoom)
    return Math.ceil(Math.max(root.stackW, Math.min(w, cap)))
  }

  // ---- Overflow stack ----
  // The focused workspace when its card is in the stack, else -1: the stack
  // chip then wears that card's colour, so the active workspace always shows.
  readonly property int stackActiveId: {
    var fw = Hyprland.focusedWorkspace
    return fw !== null && root.stackIds.indexOf(fw.id) !== -1 ? fw.id : -1
  }
  readonly property bool stackOccupied: {
    for (var i = 0; i < root.stackIds.length; i++) {
      var ws = root.workspaceById(root.stackIds[i])
      if (ws !== null && ws.toplevels.values.length > 0) return true
    }
    return false
  }
  // Drop target id while a dragged card hovers the stack chip.
  readonly property int stackTarget: -2
  property bool stackOpen: false
  // Rows in the popup have room for the whole name (a bar card is capped).
  readonly property real stackRowW: {
    var w = Style.space(120)
    for (var i = 0; i < root.stackIds.length; i++) {
      var id = root.stackIds[i]
      var name = root.customName(id) !== "" ? root.customName(id) : "Workspace " + root.numberLabel(id)
      w = Math.max(w, root.markWidth(id) + labelMetrics.advanceWidth(name) + 2 * root.cardPad)
    }
    return Math.ceil(Math.min(w, Style.space(280)))
  }

  QtObject {
    id: stackOwner
    function close() { root.stackOpen = false }
  }

  function toggleStack() {
    root.cancelRename()
    root.previewCloseNow()
    root.stackOpen = !root.stackOpen
  }

  // Bring a stacked card to the front of the bar, where it is sure to show.
  function moveToFront(id) {
    var next = [id].concat(root.displayIds.filter(function(n) { return n !== id }))
    root.localOrder = next
    root.syncIds()
    root.persistOrder(next)
  }

  // ---- Drag to reorder inside the stack popup ----
  // The held row (its index in stackIds), how far it has been carried along
  // the list, and the slot it would land in. The other rows step aside to
  // open a gap there; on release the held row settles into the gap and the
  // new order is saved, the same `order` the bar drag writes.
  property int stackHeld: -1
  property real stackCarry: 0
  property int stackSlot: -1
  property bool stackSettling: false
  // Rows rebuilt by a drop keep still instead of dealing in again.
  property bool stackNoDeal: false
  readonly property real stackStep: root.chipH + Style.space(6)
  onStackOpenChanged: if (!root.stackOpen) root.cancelStackDrag()
  onStackIdsChanged: if (root.stackHeld >= 0) root.cancelStackDrag()

  // How far a row that isn't held moves to make room.
  function stackShift(index) {
    var from = root.stackHeld
    var to = root.stackSlot
    if (from < 0 || to < 0 || index === from) return 0
    if (from < to && index > from && index <= to) return -root.stackStep
    if (to < from && index >= to && index < from) return root.stackStep
    return 0
  }

  function holdStackRow(index) {
    stackSettle.stop()
    root.stackSettling = false
    root.stackCarry = 0
    root.stackSlot = index
    root.stackHeld = index
  }

  // `dy`: pointer travel since the press, kept within the list.
  function carryStackRow(dy) {
    var n = root.stackIds.length
    var from = root.stackHeld
    if (from < 0 || n < 2) return
    root.stackCarry = Math.max(-from * root.stackStep, Math.min((n - 1 - from) * root.stackStep, dy))
    root.stackSlot = Math.max(0, Math.min(n - 1, from + Math.round(root.stackCarry / root.stackStep)))
  }

  function dropStackRow() {
    var from = root.stackHeld
    if (from < 0) return
    root.stackSettling = true
    root.stackCarry = (root.stackSlot - from) * root.stackStep
    stackSettle.restart()
  }

  function cancelStackDrag() {
    stackSettle.stop()
    root.stackHeld = -1
    root.stackSlot = -1
    root.stackCarry = 0
    root.stackSettling = false
  }

  Timer {
    id: stackSettle
    interval: Math.max(1, Style.duration(150))
    onTriggered: {
      var from = root.stackHeld
      var to = root.stackSlot
      // Clear the drag first: the save below rebuilds the rows, and the new
      // ones must start from rest, not from the held row's offset.
      root.cancelStackDrag()
      if (from < 0 || to < 0 || from === to) return
      root.stackNoDeal = true
      root.moveInStack(from, to)
      Qt.callLater(function() { root.stackNoDeal = false })
    }
  }

  // Move the stack's `from`-th card to its `to`-th place. Cards on the bar
  // keep theirs: only the stack's own positions in the order are reused.
  function moveInStack(from, to) {
    var stack = root.stackIds
    if (from === to || from < 0 || to < 0 || from >= stack.length || to >= stack.length) return
    var moved = root.reordered(stack, from, to)
    var k = 0
    var next = root.displayIds.map(function(id) { return stack.indexOf(id) !== -1 ? moved[k++] : id })
    root.localOrder = next
    root.syncIds()
    root.persistOrder(next)
  }

  function slotPos(i) {
    var v = root.starts[i]
    return v === undefined ? 0 : v
  }

  // The row plus a trailing slot for the "+" button.
  implicitWidth: root.vertical
    ? root.chipW
    : root.cardsEnd + root.hGap + root.chipW + root.trailingGap
  implicitHeight: root.vertical
    ? root.rowLength + root.vGap + root.chipH
    : root.chipH

  QtObject {
    id: renameOwner
    function close() { root.cancelRename() }
  }

  // Card editor: name, emoji (searchable list of every emoji) and colour.
  // A KeyboardPanel, not a PopupCard: popups hang off the bar's surface,
  // which never takes keyboard focus, so a text field in one can't be typed
  // into. Enter in the name field or Save commits; Escape, Cancel or a click
  // outside discards; Reset clears name, emoji and colour.
  KeyboardPanel {
    id: renamePopup
    anchorItem: root.editingAnchor
    owner: renameOwner
    bar: root.bar
    open: root.editingId >= 0 && root.editingAnchor !== null
    focusTarget: nameField
    contentWidth: renamePopup.fittedContentWidth(Style.space(340))
    contentHeight: renamePopup.fittedContentHeight(root.editMode === "edit"
      ? editColumn.implicitHeight : deleteColumn.implicitHeight)

    onOpenChanged: {
      if (!open) return
      // Reopened while its apps are still closing: show that, not the editor.
      root.editMode = root.deleteLandings[String(root.editingId)] !== undefined ? "moving"
        : root.pendingDeletes[String(root.editingId)] !== undefined ? "closing"
        : root.pendingCloses[String(root.editingId)] !== undefined ? "closingKeep" : "edit"
      nameField.text = root.customName(root.editingId)
      root.draftEmoji = root.customEmoji(root.editingId)
      root.draftIcon = root.customIcon(root.editingId)
      root.draftIconTint = root.customIconTint(root.editingId)
      root.draftColor = root.customColor(root.editingId)
      root.emojiQuery = ""
      root.emojiRecentTab = false
      root.emojiIconTab = root.draftIcon !== ""
      var resume = root.resumeDraft
      root.resumeDraft = null
      if (resume !== null && resume.id === root.editingId) {
        nameField.text = resume.draft.name
        root.draftEmoji = resume.draft.emoji
        root.draftIcon = resume.draft.icon
        root.draftIconTint = resume.draft.tint
        root.draftColor = resume.draft.color
        root.emojiIconTab = resume.iconTab
      }
      root.ensureIconDir()
      root.emojiJumpStart = -1
      root.colorPickerOpen = false
      emojiSearch.text = ""
      emojiGrid.positionViewAtBeginning()
      nameField.selectAll()
    }

    Column {
      id: editColumn
      visible: root.editMode === "edit"
      width: parent.width
      spacing: Style.space(8)

      Row {
        spacing: Style.space(8)

        // Live preview of the card being edited.
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(32)
          height: Style.space(32)
          radius: Style.space(4)
          color: root.draftColor !== "" ? Util.alpha(root.draftColor, 0.22) : Util.alpha(root.previewFg, 0.08)
          border.width: 1
          border.color: root.draftColor !== "" ? root.draftColor : Util.alpha(root.previewFg, 0.35)

          MarkIcon {
            anchors.centerIn: parent
            visible: root.draftIcon !== ""
            width: Style.font.title + 2
            height: width
            source: root.iconUrl(root.draftIcon)
            tint: root.draftIconTint
            tintColor: root.draftColor !== "" ? root.draftColor : root.previewFg
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            visible: root.draftIcon === ""
            text: root.draftEmoji !== "" ? root.draftEmoji
              : (root.editingId < 0 ? "" : root.numberLabel(root.editingId))
            color: root.draftColor !== "" ? root.draftColor : root.previewFg
            font.family: root.draftEmoji !== "" ? root.emojiFont : root.previewFont
            font.pixelSize: Style.font.title
            font.bold: true
            renderType: Text.QtRendering
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Workspace " + (root.editingId < 0 ? "" : root.numberLabel(root.editingId))
          color: root.previewFg
          font.family: root.previewFont
          font.pixelSize: Style.font.body
          font.bold: true
          renderType: Text.NativeRendering
        }
      }

      TextField {
        id: nameField
        width: parent.width
        placeholderText: "Name (leave empty for the number)"
        maximumLength: 40
        KeyNavigation.tab: emojiSearch
        onAccepted: root.commitEdit()
        Keys.onEscapePressed: root.cancelRename()
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: emojiSearch
          width: parent.width - clearEmoji.width - parent.spacing
          placeholderText: root.emojiIconTab ? "Search your icons by file name" : "Search emoji — music, code, fire…"
          KeyNavigation.tab: nameField
          onTextChanged: {
            root.emojiQuery = text
            if (text !== "") root.emojiRecentTab = false
          }
          // Enter picks the first match.
          onAccepted: {
            if (root.emojiResults.length === 0) return
            var first = root.emojiResults[0]
            if (first.i) root.pickIcon(first.i)
            else root.pickEmoji(first.e)
          }
          Keys.onEscapePressed: root.cancelRename()
        }

        Button {
          id: clearEmoji
          anchors.verticalCenter: parent.verticalCenter
          text: root.draftIcon !== "" ? "No icon" : "No emoji"
          onClicked: {
            root.draftEmoji = ""
            root.draftIcon = ""
          }
        }
      }

      // Recent + category jump bar.
      Row {
        id: emojiTabs
        width: parent.width
        spacing: 0
        readonly property int tabCount: root.emojiCategories.length + 2
        readonly property real tabW: Math.floor(width / Math.max(1, tabCount))
        // Category under the top of the grid, for the highlight.
        readonly property int topIndex: {
          emojiGrid.contentY
          var cols = Math.max(1, Math.floor(emojiGrid.width / Math.max(1, emojiGrid.cellWidth)))
          return Math.floor(Math.max(0, emojiGrid.contentY - emojiGrid.originY) / emojiGrid.cellHeight) * cols
        }

        Repeater {
          // start -1 = recently used, -2 = your icons.
          model: [{ icon: "🕘", name: "Recently used", start: -1 },
            { icon: "", name: "Your icons (" + root.iconDir.replace(Quickshell.env("HOME"), "~") + ")", start: -2 }]
            .concat(root.emojiCategories)

          Rectangle {
            id: catTab
            required property var modelData
            required property int index
            readonly property bool active: {
              if (modelData.start === -2) return root.emojiIconTab
              if (root.emojiIconTab || root.emojiQuery.trim() !== "") return false
              if (modelData.start < 0) return root.emojiRecentTab
              if (root.emojiRecentTab) return false
              if (root.emojiJumpStart >= 0) return modelData.start === root.emojiJumpStart
              var cats = root.emojiCategories
              var next = index - 1 < cats.length ? cats[index - 1].start : 1e9
              return emojiTabs.topIndex >= modelData.start && emojiTabs.topIndex < next
            }
            width: emojiTabs.tabW
            height: Style.space(26)
            radius: Style.space(4)
            color: active ? Util.alpha(Color.accent, 0.25)
              : catMouse.containsMouse ? Util.alpha(root.previewFg, 0.1) : "transparent"
            opacity: (modelData.start === -1 && root.recentEmoji.length === 0)
              || (modelData.start === -2 && root.customIcons.length === 0) ? 0.35 : 1

            HudIconGlyph {
              visible: catTab.modelData.start === -2
              anchors.centerIn: parent
              height: Math.round(Style.font.body * 1.1)
              color: root.previewFg
            }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: catTab.modelData.start !== -2
              text: catTab.modelData.icon
              font.family: root.emojiFont
              font.pixelSize: Style.font.body
              renderType: Text.QtRendering
            }

            MouseArea {
              id: catMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (catTab.modelData.start === -2) {
                  emojiSearch.text = ""
                  root.emojiRecentTab = false
                  root.emojiIconTab = true
                  emojiGrid.positionViewAtBeginning()
                } else if (catTab.modelData.start === -1) {
                  emojiSearch.text = ""
                  root.emojiIconTab = false
                  root.emojiRecentTab = true
                  emojiGrid.positionViewAtBeginning()
                } else {
                  root.jumpToEmojiCategory(catTab.modelData.start)
                }
              }
            }

            PanelToolTip {
              visible: catMouse.containsMouse
              text: catTab.modelData.name
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(36) * 5

        GridView {
          id: emojiGrid
          anchors.fill: parent
          anchors.rightMargin: Style.space(8)
          clip: true
          model: root.emojiResults
          onMovementStarted: root.emojiJumpStart = -1
          cellWidth: Math.floor(width / Math.max(1, Math.floor(width / Style.space(36))))
          cellHeight: Style.space(36)
          boundsBehavior: Flickable.StopAtBounds
          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: QQC.ScrollBar.AlwaysOn
            parent: emojiGrid.parent
            anchors.top: emojiGrid.top
            anchors.bottom: emojiGrid.bottom
            anchors.left: emojiGrid.right
            anchors.leftMargin: Style.space(2)
          }

          delegate: Rectangle {
            required property var modelData
            width: emojiGrid.cellWidth
            height: emojiGrid.cellHeight
            radius: Style.space(4)
            color: (modelData.i ? root.draftIcon === modelData.i : root.draftEmoji === modelData.e)
              ? Util.alpha(Color.accent, 0.3)
              : cellMouse.containsMouse ? Util.alpha(root.previewFg, 0.12) : "transparent"

            MarkIcon {
              anchors.centerIn: parent
              visible: !!parent.modelData.i
              width: Style.font.title + 2
              height: width
              source: parent.modelData.i ? root.iconUrl(parent.modelData.i) : ""
              tint: root.draftIconTint && root.draftIcon === parent.modelData.i
              tintColor: root.previewFg
            }

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: !parent.modelData.i
              text: parent.modelData.e || ""
              font.family: root.emojiFont
              font.pixelSize: Style.font.title
              renderType: Text.QtRendering
            }

            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (parent.modelData.i) root.pickIcon(parent.modelData.i)
                else root.pickEmoji(parent.modelData.e)
              }
            }

            PanelToolTip {
              visible: cellMouse.containsMouse && !!parent.modelData.i
              text: parent.modelData.i || ""
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: root.emojiResults.length === 0
          width: parent.width - Style.space(16)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.emojiIconTab
            ? (root.customIcons.length === 0
              ? "No icons yet. Click Add icon from file\u2026, or drag image files into the Icon library\u2026 window, or put them in\n" +
                root.iconDir.replace(Quickshell.env("HOME"), "~")
              : "No icon matches")
            : root.allEmojis.length === 0 ? "Emoji list unavailable"
            : root.emojiRecentTab && root.emojiQuery.trim() === "" ? "Emoji you pick show up here"
            : "No matches \u2014 or paste any emoji"
          color: Util.alpha(root.previewFg, 0.6)
          font.family: root.previewFont
          font.pixelSize: Style.font.body
        }
      }

      // Your icons tab: pick a file straight onto this card, the icon library
      // window (drop files in), the folder, tint for one-colour icons. A Flow
      // so the buttons wrap instead of running past the editor's edge.
      Flow {
        visible: root.emojiIconTab
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Add icon from file\u2026"
          onClicked: root.pickIconForCard()
        }

        Button {
          text: "Icon library\u2026"
          onClicked: root.openIconLibrary()
        }

        Button {
          text: "Open folder"
          onClicked: root.openIconFolder()
        }
      }

      Toggle {
        visible: root.emojiIconTab
        width: parent.width
        label: "Tint like text"
        description: "Paint one-colour icons in the card's text colour"
        checked: root.draftIconTint
        onClicked: root.draftIconTint = !root.draftIconTint
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          // "" = no colour (follow the theme); then the palette, then recent
          // custom colours.
          model: [""].concat(root.swatches).concat(root.recentColors.filter(function(c) {
            return root.swatches.indexOf(c) === -1
          }))

          Rectangle {
            required property string modelData
            readonly property bool selected: root.draftColor === modelData
            width: Style.space(22)
            height: Style.space(22)
            radius: width / 2
            color: modelData === "" ? "transparent" : modelData
            border.width: selected ? 2 : 1
            border.color: selected ? root.previewFg : Util.alpha(root.previewFg, 0.35)

            Text {
              textFormat: Text.PlainText
              visible: parent.modelData === ""
              anchors.centerIn: parent
              text: "⊘"
              color: Util.alpha(root.previewFg, 0.7)
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.draftColor = parent.modelData
            }
          }
        }

        // Opens the full colour picker.
        Rectangle {
          readonly property bool custom: root.draftColor !== ""
            && root.swatches.indexOf(root.draftColor.toLowerCase()) === -1
          width: Style.space(22)
          height: Style.space(22)
          radius: width / 2
          border.width: root.colorPickerOpen || custom ? 2 : 1
          border.color: root.colorPickerOpen || custom ? root.previewFg : Util.alpha(root.previewFg, 0.35)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff4d4d" }
            GradientStop { position: 0.33; color: "#4dff88" }
            GradientStop { position: 0.66; color: "#4d9dff" }
            GradientStop { position: 1.0; color: "#e14dff" }
          }

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: "+"
            color: "#ffffff"
            font.pixelSize: Style.font.body
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.colorPickerOpen = !root.colorPickerOpen
              if (root.colorPickerOpen && root.draftColor === "") root.setFromPicker()
            }
          }
        }
      }

      // Full colour picker: saturation (across) and brightness (down) for the
      // chosen hue, a hue strip, and a hex field.
      Column {
        visible: root.colorPickerOpen
        width: parent.width
        spacing: Style.space(6)

        Rectangle {
          id: svBox
          width: parent.width
          height: Style.space(110)
          radius: Style.space(4)
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: Qt.hsva(root.pickHue, 1, 1, 1) }
          }

          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
              GradientStop { position: 0.0; color: "#00000000" }
              GradientStop { position: 1.0; color: "#ff000000" }
            }
          }

          Rectangle {
            x: root.pickSat * svBox.width - width / 2
            y: (1 - root.pickVal) * svBox.height - height / 2
            width: Style.space(12)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.pickVal > 0.5 ? "#000000" : "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            function pick(mouse) {
              root.pickSat = Math.max(0, Math.min(1, mouse.x / width))
              root.pickVal = Math.max(0, Math.min(1, 1 - mouse.y / height))
              root.setFromPicker()
            }
            onPressed: function(mouse) { pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
          }
        }

        Rectangle {
          id: hueStrip
          width: parent.width
          height: Style.space(14)
          radius: height / 2
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff0000" }
            GradientStop { position: 0.167; color: "#ffff00" }
            GradientStop { position: 0.333; color: "#00ff00" }
            GradientStop { position: 0.5; color: "#00ffff" }
            GradientStop { position: 0.667; color: "#0000ff" }
            GradientStop { position: 0.833; color: "#ff00ff" }
            GradientStop { position: 1.0; color: "#ff0000" }
          }

          Rectangle {
            x: root.pickHue * hueStrip.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: hueStrip.height + Style.space(4)
            radius: Style.space(2)
            color: Qt.hsva(root.pickHue, 1, 1, 1)
            border.width: 2
            border.color: "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function pick(mouse) {
              root.pickHue = Math.max(0, Math.min(0.999, mouse.x / width))
              root.setFromPicker()
            }
            onPressed: function(mouse) { pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            height: Style.space(28)
            radius: Style.space(4)
            color: root.draftColor !== "" ? root.draftColor : "transparent"
            border.width: 1
            border.color: Util.alpha(root.previewFg, 0.35)
          }

          TextField {
            id: hexField
            width: parent.width - Style.space(34)
            placeholderText: "Hex, e.g. #1e90ff"
            maximumLength: 7
            // Follows swatches and the picker, except while being typed in.
            Binding on text {
              value: root.draftColor
              when: !hexField.activeFocus
            }
            onTextEdited: {
              var t = text.trim()
              if (t.charAt(0) !== "#") t = "#" + t
              if (/^#[0-9a-fA-F]{6}$/.test(t)) root.draftColor = t.toLowerCase()
            }
            onAccepted: root.commitEdit()
            Keys.onEscapePressed: root.cancelRename()
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "Save"
          onClicked: root.commitEdit()
        }

        Button {
          text: "Reset"
          onClicked: root.resetEdit()
        }

        Button {
          text: "Cancel"
          onClicked: root.cancelRename()
        }

        Button {
          visible: root.editingId >= 0 && root.toplevelsOf(root.editingId).length > 0
          text: "Close…"
          onClicked: root.editMode = "confirmCloseKeep"
        }

        Button {
          text: "Delete…"
          foreground: Color.urgent
          onClicked: root.startDelete()
        }

        Button {
          text: "Save as room"
          onClicked: root.saveRoomFromEditor()
        }
      }
    }

    // Delete flow. Empty: confirm. With windows: pick where each goes (or one
    // destination for all), or close them all.
    Column {
      id: deleteColumn
      visible: root.editMode !== "edit"
      width: parent.width
      spacing: Style.space(8)

      readonly property string title: root.editingId < 0 ? ""
        : (root.customEmoji(root.editingId) ? root.customEmoji(root.editingId) + " " : "")
          + (root.customName(root.editingId) || "Workspace " + root.numberLabel(root.editingId))

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: (root.closingMode ? "Close " : "Delete ") + deleteColumn.title + "?"
        elide: Text.ElideRight
        color: root.closingMode ? root.previewFg : Color.urgent
        font.family: root.previewFont
        font.pixelSize: Style.font.body
        font.bold: true
        renderType: Text.QtRendering
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        color: Util.alpha(root.previewFg, 0.75)
        font.family: root.previewFont
        font.pixelSize: Style.font.caption
        renderType: Text.NativeRendering
        text: {
          var n = root.deleteWindows.length
          if (root.editMode === "confirmCloseKeep") return "Close its " + n + (n === 1 ? " app" : " apps") + "? The card stays on the bar with its name, emoji and colour. Unsaved work may be lost."
          if (root.editMode === "closingKeep") return "Closing " + n + (n === 1 ? " app" : " apps") + "… apps with unsaved work may ask first."
          if (root.editMode === "closeKeepFailed") return n + (n === 1 ? " app is" : " apps are") + " still open. Save or close them yourself; the card stays either way."
          if (root.editMode === "closing") return "Closing " + n + (n === 1 ? " app" : " apps") + "… apps with unsaved work may ask first."
          if (root.editMode === "moving") return "Moving " + n + (n === 1 ? " window" : " windows") + "… the card goes once the workspace is empty."
          if (root.editMode === "moveFailed") return n + (n === 1 ? " window" : " windows") + " didn't move, so the card was kept with its name, emoji and colour. Try again, or close them."
          if (root.editMode === "closeFailed") return n + (n === 1 ? " app is" : " apps are") + " still open. Close or save them yourself and the card goes once they're closed, or move them instead."
          if (root.editMode === "confirmClose") return "Close " + n + (n === 1 ? " app" : " apps") + "? Unsaved work in them may be lost."
          if (n === 0) return "It has no windows. The card will be removed from the bar."
          return "It has " + n + (n === 1 ? " window" : " windows") + ". Choose where each one goes, or close them."
        }
      }

      // Destination for everything at once.
      Row {
        visible: root.editMode === "delete" && root.deleteWindows.length > 1
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Move all to"
          color: root.previewFg
          font.family: root.previewFont
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        Dropdown {
          width: parent.width - Style.space(90)
          showLabel: false
          options: root.moveDestinations
          value: ""
          onChanged: function(value) { root.setAllMoveTargets(value) }
        }
      }

      // One row per window: icon, title, destination.
      Repeater {
        model: root.editMode === "delete" || root.editMode === "closeFailed" || root.editMode === "moveFailed"
          || root.editMode === "confirmCloseKeep" || root.editMode === "closeKeepFailed" ? root.deleteWindows : []

        Item {
          required property var modelData
          readonly property string address: root.hexAddress(modelData)
          width: deleteColumn.width
          height: Math.max(Style.space(30), winDest.implicitHeight)

          Image {
            id: winIcon
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(18)
            height: Style.space(18)
            sourceSize.width: width
            sourceSize.height: height
            source: root.previewIconSource(parent.modelData)
            visible: status === Image.Ready
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(24)
            width: parent.width - x - winDest.width - Style.space(6)
            text: root.previewTitle(parent.modelData) || root.previewAppId(parent.modelData)
            elide: Text.ElideRight
            color: root.previewFg
            font.family: root.previewFont
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Dropdown {
            id: winDest
            visible: root.editMode === "delete"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(150)
            showLabel: false
            options: root.moveDestinations
            value: String(root.moveTargets[parent.address] || "new")
            onChanged: function(value) { root.setMoveTarget(parent.address, value) }
          }
        }
      }

      Row {
        topPadding: Style.space(4)
        spacing: Style.space(6)

        Button {
          visible: root.editMode === "delete"
          text: root.deleteWindows.length > 0 ? "Move & delete" : "Delete"
          foreground: Color.urgent
          onClicked: root.moveAndDelete()
        }

        Button {
          visible: root.editMode === "delete" && root.deleteWindows.length > 0
          text: "Close apps & delete"
          foreground: Color.urgent
          onClicked: root.editMode = "confirmClose"
        }

        Button {
          visible: root.editMode === "confirmClose"
          text: "Yes, close them"
          foreground: Color.urgent
          onClicked: root.closeAndDelete()
        }

        Button {
          visible: root.editMode === "closeFailed"
          text: "Move them instead"
          onClicked: root.startDelete()
        }

        Button {
          visible: root.editMode === "moveFailed"
          text: "Try again"
          onClicked: root.startDelete()
        }

        Button {
          visible: root.editMode === "confirmCloseKeep"
          text: "Yes, close apps"
          onClicked: root.closeAndKeep()
        }

        Button {
          visible: root.editMode === "closeKeepFailed"
          text: "OK"
          onClicked: root.cancelRename()
        }

        Button {
          visible: root.editMode !== "closing" && root.editMode !== "closingKeep"
            && root.editMode !== "closeKeepFailed" && root.editMode !== "moving"
          text: root.editMode === "delete" || root.editMode === "confirmCloseKeep" ? "Back" : "Cancel"
          onClicked: {
            if (root.editMode === "delete" || root.editMode === "confirmCloseKeep") root.editMode = "edit"
            else if (root.editMode === "confirmClose") root.editMode = "delete"
            else {
              // Cancel after a failed close keeps the workspace.
              if (root.editMode === "closeFailed") root.dropPendingDelete(root.editingId)
              root.cancelRename()
            }
          }
        }
      }
    }
  }

  QtObject {
    id: settingsOwner
    function close() { root.settingsOpen = false }
  }

  // Transition settings (right-click the + button). Every change applies at
  // once; Preview hops to a neighbouring card and back to show the effect.
  component SectionTitle: Text {
    textFormat: Text.PlainText
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
    renderType: Text.NativeRendering
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    signal picked()
    width: chipText.implicitWidth + Style.space(18)
    height: chipText.implicitHeight + Style.space(10)
    radius: Style.space(4)
    color: selected ? Util.alpha(Color.accent, 0.22)
      : chipMouse.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
    border.width: 1
    border.color: selected ? Color.accent : Util.alpha(Color.foreground, 0.25)

    Text {
      textFormat: Text.PlainText
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.selected ? Color.accent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.picked()
    }
  }

  KeyboardPanel {
    id: settingsPanel
    anchorItem: addBtn
    owner: settingsOwner
    bar: root.bar
    open: root.settingsOpen
    focusTarget: settingsKeys
    contentWidth: settingsPanel.fittedContentWidth(Style.space(360))
    contentHeight: settingsPanel.fittedContentHeight(panelColumn.implicitHeight)

    Item {
      id: settingsKeys
      focus: true
      Keys.onEscapePressed: root.settingsOpen = false
    }

    Column {
      id: panelColumn
      width: parent.width
      spacing: Style.space(10)

      Flow {
        id: panelTabs
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: [
            { key: "settings", name: "Settings" },
            { key: "rooms", name: "Rooms" },
            { key: "profiles", name: "Profiles" },
            { key: "guide", name: "How to use" },
            { key: "about", name: "About" }
          ]

          Chip {
            required property var modelData
            label: modelData.name
            selected: root.panelTab === modelData.key
            onPicked: root.panelTab = modelData.key
          }
        }
      }

      // Tall tabs scroll inside the panel instead of running off screen.
      Flickable {
        id: panelBody
        width: parent.width
        height: Math.min(contentHeight, Math.max(Style.space(160),
          settingsPanel.availableCardHeight - settingsPanel.verticalContentInset
          - panelTabs.implicitHeight - panelColumn.spacing))
        contentWidth: width
        contentHeight: root.panelTab === "rooms" ? roomsColumn.implicitHeight
          : root.panelTab === "profiles" ? profilesColumn.implicitHeight
          : root.panelTab === "guide" ? guideColumn.implicitHeight
          : root.panelTab === "about" ? aboutColumn.implicitHeight
          : settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar {
          policy: panelBody.contentHeight > panelBody.height ? QQC.ScrollBar.AsNeeded : QQC.ScrollBar.AlwaysOff
        }

    Column {
      id: settingsColumn
      visible: root.panelTab === "settings"
      width: parent.width
      spacing: Style.space(8)

      SectionTitle { text: "Transition" }

      Grid {
        columns: 2
        columnSpacing: Style.space(6)
        rowSpacing: Style.space(6)

        Repeater {
          model: root.transitions

          Rectangle {
            required property var modelData
            readonly property bool selected: root.transition === modelData.key
            width: (settingsColumn.width - Style.space(6)) / 2
            height: tileText.implicitHeight + Style.space(12)
            radius: Style.space(4)
            color: selected ? Util.alpha(Color.accent, 0.22)
              : tileMouse.containsMouse ? Util.alpha(Color.foreground, 0.08) : "transparent"
            border.width: 1
            border.color: selected ? Color.accent : Util.alpha(Color.foreground, 0.2)

            Column {
              id: tileText
              anchors.verticalCenter: parent.verticalCenter
              x: Style.space(8)
              width: parent.width - Style.space(16)

              Text {
                textFormat: Text.PlainText
                text: modelData.name
                color: selected ? Color.accent : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                renderType: Text.NativeRendering
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: modelData.detail
                elide: Text.ElideRight
                color: Util.alpha(Color.foreground, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.saveSetting("transition", parent.modelData.key)
            }
          }
        }
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Motion"
        opacity: root.transition === "none" ? 0.4 : 1
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        enabled: root.transition !== "none"
        opacity: enabled ? 1 : 0.4

        Repeater {
          model: root.transitionCurves

          Chip {
            required property var modelData
            label: modelData.name
            selected: root.transitionCurve === modelData.key
            onPicked: root.saveSetting("transitionCurve", modelData.key)
          }
        }
      }

      // Duration: the slider shows the value live and saves on release.
      Item {
        width: parent.width
        height: durationLabel.implicitHeight + durationSlider.height + Style.space(4)
        enabled: root.transition !== "none"
        opacity: enabled ? 1 : 0.4

        SectionTitle {
          id: durationLabel
          text: "Duration"
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.baseline: durationLabel.baseline
          text: Math.round(durationSlider.liveValue) + " ms"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        PanelSlider {
          id: durationSlider
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(22)
          bar: root.bar
          minimum: 100
          maximum: 1500
          step: 50
          integer: true
          value: root.transitionDuration
          onReleased: function(value) { root.saveSetting("transitionDuration", Math.round(value), true) }
        }
      }

      Item {
        width: parent.width
        height: distanceLabel.implicitHeight + distanceSlider.height + Style.space(4)
        enabled: root.usesDistance
        opacity: enabled ? 1 : 0.4

        SectionTitle {
          id: distanceLabel
          text: "Slide distance"
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.baseline: distanceLabel.baseline
          text: root.usesDistance ? Math.round(distanceSlider.liveValue) + "%" : "Glide / Rise only"
          color: root.usesDistance ? Color.accent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
        }

        PanelSlider {
          id: distanceSlider
          anchors.bottom: parent.bottom
          width: parent.width
          height: Style.space(22)
          bar: root.bar
          minimum: 5
          maximum: 100
          step: 5
          integer: true
          value: root.transitionDistance
          onReleased: function(value) { root.saveSetting("transitionDistance", Math.round(value), true) }
        }
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Navigation"
      }

      Toggle {
        width: parent.width
        label: "Natural swipe"
        description: root.swipeNatural ? "Swipe left → card on the right" : "Swipe right → card on the right"
        checked: root.swipeNatural
        onClicked: root.saveSetting("swipeNatural", !root.swipeNatural, true)
      }

      Toggle {
        width: parent.width
        label: "Swipe wraps around"
        description: "Past the last card, continue from the first"
        checked: root.wrapSwipe
        onClicked: root.saveSetting("wrapSwipe", !root.wrapSwipe, true)
      }

      Toggle {
        width: parent.width
        label: "Scroll wraps around"
        description: "Mouse wheel over the bar loops through the cards"
        checked: root.wrapScroll
        onClicked: root.saveSetting("wrapScroll", !root.wrapScroll, true)
      }

      Toggle {
        width: parent.width
        label: "Keys follow the bar"
        description: root.keysFollowBar ? "Super+1 goes to the first card on the bar"
          : "Super+1 goes to workspace 1"
        checked: root.keysFollowBar
        onClicked: root.saveSetting("keysFollowBar", !root.keysFollowBar, true)
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Appearance"
      }

      Toggle {
        width: parent.width
        label: "Bold active card"
        description: root.solidActive ? "Current workspace is filled with its colour"
          : "Current workspace has a subtle outline"
        checked: root.solidActive
        onClicked: root.saveSetting("activeStyle", root.solidActive ? "outline" : "solid")
      }

      Toggle {
        width: parent.width
        label: "Stack cards that don't fit"
        description: root.stackOverflow ? "Extra cards wait in a stack chip; click it to fan them out"
          : "Cards shrink to compact chips so all of them stay on the bar"
        checked: root.stackOverflow
        onClicked: root.saveSetting("overflow", root.stackOverflow ? "shrink" : "stack")
      }

      BodyText {
        visible: root.stackOverflow
        text: "Stack every card once there are more than:"
      }

      Flow {
        visible: root.stackOverflow
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: [0, 1, 2, 3, 4, 5, 6]

          Chip {
            required property int modelData
            label: modelData === 0 ? "Off" : String(modelData)
            selected: root.stackAfter === modelData
            onPicked: root.saveSetting("stackAfter", modelData, true)
          }
        }
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Startup"
      }

      Toggle {
        width: parent.width
        label: "Fresh start after reboot"
        description: "Back to cards 1-5: no names, emoji, colours or custom order"
        checked: root.resetOnBoot
        onClicked: root.saveSetting("resetOnBoot", !root.resetOnBoot, true)
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Hyprland integration"
      }

      BodyText {
        width: parent.width
        text: {
          var ig = root.integration
          if (ig.installed === undefined) return "Checking\u2026"
          if (ig.ok === true) return "\u2713 Set up: number keys and swipe follow the bar" +
            (ig.drop ? ", window drop on." : ", window drop off.")
          if (ig.legacy === true) return "Set up by hand (older README snippets). Install moves them into one managed file you can undo."
          if (ig.installed === true) return "\u26A0 Changed since it was set up (an update?). Re-apply puts it back."
          return "Not set up: Super+number and swipe use workspace numbers. Install edits ~/.config/hypr (backed up first)."
        }
        color: root.integration.ok === true ? Color.foreground
          : root.integration.installed === true ? Color.urgent : Util.alpha(Color.foreground, 0.75)
      }

      BodyText {
        visible: root.hyprUntested
        width: parent.width
        text: "Tested with Hyprland " + root.testedHyprland + "; you have " + root.hyprVersion + ". If switching or rooms misbehave, check the log (~/.local/state/hud-workspaces/log)."
        color: Color.urgent
      }

      // Installed: switches window drop alone (`ws-setup drop`, which only
      // rewrites the generated file and never installs). Not installed: just
      // the choice Install will use; nothing is changed until Install.
      Toggle {
        width: parent.width
        label: "Window drop"
        description: root.integration.installed === true
          ? "Super+drag a window onto a card to move it there"
          : "Super+drag a window onto a card to move it there (applied when you press Install)"
        checked: root.integration.installed === true ? root.integration.drop === true : root.dropChoice
        onClicked: {
          if (root.integration.installed === true) root.runSetup(["drop", root.integration.drop === true ? "off" : "on", "--quiet"])
          else root.dropChoice = !root.dropChoice
        }
      }

      Row {
        spacing: Style.space(6)

        Button {
          text: root.integration.installed === true && root.integration.ok !== true ? "Re-apply"
            : root.integration.installed === true ? "Reinstall" : "Install"
          onClicked: {
            var drop = root.integration.installed === true ? root.integration.drop !== false : root.dropChoice
            root.runSetup(drop ? ["install"] : ["install", "--no-drop"])
          }
        }

        Button {
          visible: root.integration.installed === true || root.integration.legacy === true
          text: "Remove"
          foreground: Color.urgent
          onClicked: root.runSetup(["remove"])
        }
      }

      BodyText {
        visible: root.integrationNotice !== ""
        width: parent.width
        text: root.integrationNotice
        color: Color.accent
      }

      SectionTitle {
        topPadding: Style.space(4)
        text: "Backup"
      }

      BodyText {
        width: parent.width
        text: (root.settingsState.looksReset === true
            ? "\u26A0 Your cards and rooms look reset. "
            : "") +
          (root.settingsState.backup ? "Last backup with your cards/rooms: " + root.settingsState.backup + ". "
            : "Backed up automatically after every change. ") +
          "Export saves a file you can import on another machine."
        color: root.settingsState.looksReset === true ? Color.urgent : Util.alpha(Color.foreground, 0.75)
      }

      Row {
        spacing: Style.space(6)

        Button {
          visible: !!root.settingsState.backup
          text: "Restore backup"
          onClicked: root.restoreSettings()
        }

        Button {
          text: "Export"
          onClicked: root.exportSettings()
        }

        Button {
          text: "Import\u2026"
          onClicked: root.importSettings()
        }
      }

      BodyText {
        visible: root.backupNotice !== ""
        width: parent.width
        text: root.backupNotice
        color: Color.accent
      }

      Row {
        topPadding: Style.space(4)
        spacing: Style.space(6)

        Button {
          text: "Preview"
          onClicked: {
            root.settingsOpen = false
            Quickshell.execDetached([root.stepScript, "preview"])
          }
        }

        Button {
          text: "Close"
          onClicked: root.settingsOpen = false
        }
      }
    }

    Column {
      id: roomsColumn
      visible: root.panelTab === "rooms"
      width: parent.width
      spacing: Style.space(8)

      BodyText {
        text: "A room is a card plus the apps that were open on it. Save one from the card " +
          "editor (double-click a card \u2192 Save as room); open it here to get the card " +
          "and its apps back on a free workspace."
      }

      BodyText {
        visible: root.roomNotice !== ""
        text: root.roomNotice
        color: Color.accent
      }

      BodyText {
        visible: root.rooms.length === 0
        text: "No rooms yet."
        color: Util.alpha(Color.foreground, 0.6)
      }

      Repeater {
        model: root.rooms

        Rectangle {
          id: roomRow
          required property var modelData
          required property int index
          width: roomsColumn.width
          height: roomInfo.implicitHeight + Style.space(14)
          radius: Style.space(4)
          color: "transparent"
          border.width: 1
          border.color: /^#[0-9a-fA-F]{6}$/.test(String(modelData.color || ""))
            ? Util.alpha(modelData.color, 0.7) : Util.alpha(Color.foreground, 0.2)

          Column {
            id: roomInfo
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(8)
            width: parent.width - Style.space(16) - roomButtons.width - Style.space(6)
            spacing: Style.space(2)

            Row {
              width: parent.width
              spacing: roomIcon.visible ? Style.space(6) : 0

              MarkIcon {
                id: roomIcon
                visible: source !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.body + 2
                height: width
                source: root.iconUrl(roomRow.modelData.icon)
                tint: roomRow.modelData.iconTint === true
                tintColor: Color.foreground
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width - (roomIcon.visible ? roomIcon.width + parent.spacing : 0)
                elide: Text.ElideRight
                text: (!roomIcon.visible && roomRow.modelData.emoji ? roomRow.modelData.emoji + "  " : "") +
                  roomRow.modelData.name
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                renderType: Text.NativeRendering
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              text: root.roomSummary(roomRow.modelData)
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
            }
          }

          Row {
            id: roomButtons
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(4)

            Button {
              text: "Open"
              onClicked: root.openRoom(roomRow.index)
            }

            Button {
              text: "\u2715"
              foreground: Color.urgent
              onClicked: root.deleteRoom(roomRow.index)
            }
          }
        }
      }
    }

    Column {
      id: profilesColumn
      visible: root.panelTab === "profiles"
      width: parent.width
      spacing: Style.space(8)

      BodyText {
        text: "A profile is a whole deck of cards with their names, emoji, colours and apps. " +
          "Opening one replaces the bar with exactly those cards, in the same order."
      }

      BodyText {
        visible: root.profileNotice !== ""
        text: root.profileNotice
        color: Color.accent
      }

      SectionTitle { text: "Save the bar as a profile" }

      BodyText {
        text: "Pick the cards to include:"
        color: Util.alpha(Color.foreground, 0.7)
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.displayIds

          Chip {
            required property var modelData
            label: (root.customEmoji(modelData) ? root.customEmoji(modelData) + " " : "") +
              (root.customName(modelData) || root.numberLabel(modelData)) +
              (root.toplevelsOf(modelData).length > 0 ? "  · " + root.toplevelsOf(modelData).length : "")
            selected: root.profilePick[modelData] === true
            onPicked: root.toggleProfilePick(modelData)
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: profileNameField
          width: parent.width - saveProfileBtn.width - parent.spacing
          placeholderText: "Profile name (same name updates it)"
          maximumLength: 40
          onAccepted: root.saveProfile(text)
          Keys.onEscapePressed: root.settingsOpen = false
        }

        Button {
          id: saveProfileBtn
          anchors.verticalCenter: parent.verticalCenter
          // "Update" when the name is taken: saving replaces that profile.
          text: (root.profileNamed(profileNameField.text) !== null ? "Update " : "Save ") + root.pickedIds.length
          enabled: root.pickedIds.length > 0 && !profileCapture.running
          onClicked: root.saveProfile(profileNameField.text)
        }
      }

      SectionTitle { topPadding: Style.space(4); text: "Your profiles" }

      BodyText {
        visible: root.profiles.length === 0
        text: "No profiles yet."
        color: Util.alpha(Color.foreground, 0.6)
      }

      Repeater {
        model: root.profiles

        Rectangle {
          id: profileRow
          required property var modelData
          required property int index
          readonly property bool asking: root.profileConfirm === index
          width: profilesColumn.width
          height: profileBody.implicitHeight + Style.space(14)
          radius: Style.space(4)
          color: asking ? Util.alpha(Color.accent, 0.08) : "transparent"
          border.width: 1
          border.color: asking ? Color.accent : Util.alpha(Color.foreground, 0.2)

          Column {
            id: profileBody
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(8)
            width: parent.width - Style.space(16)
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: Math.max(profileInfo.implicitHeight, profileButtons.height)

              Column {
                id: profileInfo
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - profileButtons.width - Style.space(6)
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: profileRow.modelData.name +
                    (root.isActiveProfile(profileRow.modelData) ? "   \u25cf Active" : "")
                  color: root.isActiveProfile(profileRow.modelData) ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  renderType: Text.NativeRendering
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  text: root.profileSummary(profileRow.modelData)
                  color: Util.alpha(Color.foreground, 0.6)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  renderType: Text.NativeRendering
                }
              }

              Row {
                id: profileButtons
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                spacing: Style.space(4)

                Button {
                  text: root.profileBusy ? "Opening\u2026"
                    : root.profileOnBar(profileRow.modelData) ? "On"
                    : root.profilePartial(profileRow.modelData) ? "Restore" : "Open"
                  enabled: !root.profileBusy && !root.profileOnBar(profileRow.modelData)
                  tooltipText: root.profileOnBar(profileRow.modelData) ? "Already open on the bar"
                    : root.profilePartial(profileRow.modelData) ? "Brings back only the cards you deleted" : ""
                  onClicked: root.requestProfile(profileRow.index)
                }

                Button {
                  text: "\u2715"
                  foreground: Color.urgent
                  onClicked: root.deleteProfile(profileRow.index)
                }
              }
            }

            BodyText {
              visible: profileRow.asking
              text: "Cards outside this profile still have apps open. Close those apps, or keep those cards after the profile's?"
            }

            Flow {
              visible: profileRow.asking
              width: parent.width
              spacing: Style.space(6)

              Button {
                text: "Close apps"
                enabled: !root.profileBusy
                foreground: Color.urgent
                onClicked: root.openProfile(profileRow.index, "close")
              }

              Button {
                text: "Keep them"
                enabled: !root.profileBusy
                onClicked: root.openProfile(profileRow.index, "keep")
              }

              Button {
                text: "Cancel"
                onClicked: root.profileConfirm = -1
              }
            }
          }
        }
      }
    }

    Column {
      id: guideColumn
      visible: root.panelTab === "guide"
      width: parent.width
      spacing: Style.space(6)

      SectionTitle { text: "On the bar" }
      BodyText {
        text: "\u2022 Click a card to go to it. Hover it to see its windows; click one to focus it.\n" +
          "\u2022 Drag a card to reorder. Drag a window onto a card to move it there.\n" +
          "\u2022 Scroll over the bar or swipe with 3 fingers for the next or previous card.\n" +
          "\u2022 Cards that don't fit wait in the stack chip (a little deck with a count) before +. Click it to fan them out; click one to go there, right-click to edit it, the arrow puts it first on the bar. Drag a card onto the chip to put it in the stack. Settings can stack every card once there are more than a number you pick.\n" +
          "\u2022 + opens a new workspace. Right-click + for this panel."
      }

      SectionTitle { topPadding: Style.space(4); text: "Keyboard" }
      BodyText {
        text: "\u2022 Super+1\u20260: go to the 1st\u202610th card on the bar.\n" +
          "\u2022 Super+Shift+number: take the active window to that card.\n" +
          "\u2022 Super+Shift+Alt+number: send it there and stay put."
      }

      SectionTitle { topPadding: Style.space(4); text: "Card editor (double-click a card)" }
      BodyText {
        text: "\u2022 Name, emoji (search, category tabs, or paste any emoji) and colour (swatches, or the rainbow + for a full picker). Save keeps them; Reset clears them.\n" +
          "\u2022 Your own icons: put SVG/PNG files in " + root.iconDir.replace(Quickshell.env("HOME"), "~") +
          ", or open Icon library\u2026 (the mini-card tab next to \uD83D\uDD58) and drag image files into it from your file manager; it stays open beside it. Click an icon there to use it. Tint like text colours one-colour icons like the card text.\n" +
          "\u2022 Delete\u2026 moves the card's windows to another card, or closes them, and removes the card.\n" +
          "\u2022 Save as room remembers the card and its open apps."
      }

      SectionTitle { topPadding: Style.space(4); text: "Rooms" }
      BodyText {
        text: "\u2022 Open a room from the Rooms tab to get its card and apps back.\n" +
          "\u2022 Saving again under the same name updates the room.\n" +
          "\u2022 Rooms reopen apps in the same folders, not their contents: Files windows and terminals come back in the folder they were in (a terminal as a fresh shell), browsers open a new window."
      }

      SectionTitle { topPadding: Style.space(4); text: "Profiles" }
      BodyText {
        text: "\u2022 Profiles tab \u2192 pick the cards to keep \u2192 name it \u2192 Save. Cards with apps or a label start picked.\n" +
          "\u2022 Open a profile to get exactly those cards back, in order, with their apps. Other empty cards go away; if other cards have apps open you choose: close those apps, or keep those cards at the end.\n" +
          "\u2022 One profile is on at a time (marked Active). While all its cards are on the bar its button says On and is locked, so it can't open twice. Delete one of its cards and the button says Restore: it brings back just that card. Opening another profile replaces it.\n" +
          "\u2022 While a profile's apps are starting the button says Opening\u2026 and can't be clicked. If two identical cards are on the bar, the profile won't open until you delete one copy.\n" +
          "\u2022 Saving again under the same name updates the profile. Profiles are never cleared by the fresh start after reboot."
      }

      SectionTitle { topPadding: Style.space(4); text: "Settings" }
      BodyText {
        text: "Transition style, motion, speed and distance; swipe and scroll wrap-around; " +
          "keys following the bar; bold active card; stack or shrink cards that don't fit; fresh start after reboot."
      }
    }

    Column {
      id: aboutColumn
      visible: root.panelTab === "about"
      width: parent.width
      spacing: Style.space(6)

      // 200bps.ai logo (mark + wordmark), the light-on-dark or dark-on-light
      // set to suit the panel; click opens the site.
      Item {
        id: brandLogo
        readonly property bool darkPanel: root.contrastOn(Color.popups.background) === "#ffffff"
        width: parent.width
        height: Style.space(40)

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Image {
            width: Style.space(36)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: brandLogo.darkPanel ? "assets/200bps-mark-lime.png" : "assets/200bps-mark-black.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
          }

          Image {
            height: Style.space(16)
            width: Math.round(height * 1140 / 120)
            anchors.verticalCenter: parent.verticalCenter
            source: brandLogo.darkPanel ? "assets/200bps-type-white.png" : "assets/200bps-type-black.png"
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openLink("https://200bps.ai")
        }
      }

      Text {
        textFormat: Text.PlainText
        topPadding: Style.space(4)
        text: "HUD Workspaces"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body * 1.3
        font.bold: true
        renderType: Text.NativeRendering
      }

      BodyText {
        text: "Version " + root.pluginVersion + " \u00b7 by Nasser Al-Ostath \u00b7 200bps.ai"
        color: Util.alpha(Color.foreground, 0.6)
      }

      BodyText {
        text: "Built because I wanted workspaces I can name, colour and arrange like cards " +
          "on a desk, and get back to in one click."
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: "200bps.ai"
          onClicked: root.openLink("https://200bps.ai")
        }

        Button {
          text: "Instagram @200bps.ai"
          onClicked: root.openLink("https://instagram.com/200bps.ai")
        }
      }

      BodyText {
        text: "MIT licence: free to use, change and share, as long as the credit stays. " +
          "Made for Omarchy 4 (Hyprland)."
        color: Util.alpha(Color.foreground, 0.6)
      }

      SectionTitle { topPadding: Style.space(6); text: "Questions" }

      Repeater {
        model: [
          { q: "Why did my names and colours disappear?",
            a: "\u201cFresh start after reboot\u201d is on. Turn it off under Settings \u2192 Startup. Saved rooms and profiles are never reset." },
          { q: "Super+1 doesn't go to workspace 1.",
            a: "The number keys follow the bar order. Turn off \u201cKeys follow the bar\u201d under Settings \u2192 Navigation for plain workspace numbers." },
          { q: "Does deleting a card close my apps?",
            a: "Only if you choose \u201cClose apps & delete\u201d. Otherwise the windows move to the card you pick." },
          { q: "A room didn't bring back my tabs or files.",
            a: "Rooms reopen the apps, not what was inside them. Browsers restore their own tabs if set to." },
          { q: "Why can't I click Open on my profile?",
            a: "It says On: the profile is already open, so it's locked to avoid a second copy. It says Opening\u2026: its apps are still starting." },
          { q: "I closed an app inside a profile card. How do I get it back?",
            a: "Start it again yourself: while all the profile's cards are on the bar the profile stays On. Delete the card instead and Restore brings it back with its apps." },
          { q: "Where are my settings kept?",
            a: "In ~/.config/omarchy/shell.json, under the swordfish.workspaces entry, with backups in ~/.config/omarchy/hud-workspaces/backups (Settings \u2192 Backup)." },
          { q: "After an update, Super+number or swipe went back to normal.",
            a: "Updates can rewrite the Hyprland config. Settings \u2192 Hyprland integration \u2192 Re-apply." },
          { q: "Something doesn't work and nothing says why.",
            a: "Look at ~/.local/state/hud-workspaces/log: failures are written there." },
          { q: "How do I remove it?",
            a: "Settings \u2192 Hyprland integration \u2192 Remove, then follow \u201cUninstall\u201d in the README next to the plugin." }
        ]

        Column {
          required property var modelData
          width: aboutColumn.width
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: modelData.q
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            renderType: Text.NativeRendering
          }

          BodyText { text: modelData.a; color: Util.alpha(Color.foreground, 0.7) }
        }
      }
    }
      }
    }
  }

  component BodyText: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    lineHeight: 1.15
    renderType: Text.NativeRendering
  }

  function openLink(url) {
    root.settingsOpen = false
    Quickshell.execDetached(["xdg-open", url])
  }

  // Version from manifest.json, for the About tab.
  property string pluginVersion: ""
  FileView {
    path: decodeURIComponent(String(Qt.resolvedUrl("manifest.json")).replace(/^file:\/\//, ""))
    onLoaded: {
      try {
        root.pluginVersion = String(JSON.parse(text()).version || "")
      } catch (e) {
        root.pluginVersion = ""
      }
    }
  }

  // Cursor-following card shown while a drag is in flight. It lives at the
  // root level so it can float over neighbouring buttons, and the raised
  // input stack (raiseInputStack) keeps this whole subtree above them.
  readonly property point ghostPos: root.mapFromItem(null, root.ghostX, root.ghostY)

  Item {
    id: ghost
    width: root.vertical || root.dragId < 0 ? root.chipW : root.sizeOf(root.dragId)
    height: root.chipH
    x: root.ghostPos.x - width / 2
    y: root.ghostPos.y - height / 2 - Style.space(6)
    z: 10
    opacity: root.dragId >= 0 ? 1 : 0
    visible: opacity > 0.02
    // Lifted from just under card size (never from nothing), and put down
    // a little faster than it was picked up.
    scale: root.dragId >= 0 ? 1.15 : 0.97
    rotation: root.ghostTilt

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(root.dragId >= 0 ? 180 : 120); easing.type: Easing.OutCubic }
    }

    Behavior on scale {
      NumberAnimation {
        duration: Style.duration(root.dragId >= 0 ? 180 : 120)
        easing.type: Easing.Bezier
        easing.bezierCurve: Style.easeOut
      }
    }

    // Same chamfered panel geometry as the chips, held afloat by an offset
    // shadow; one hairline across the top edge stands in for a gloss blob.
    Shape {
      x: 2
      y: 4
      width: parent.width
      height: parent.height

      ShapePath {
        strokeWidth: 0
        fillColor: Util.alpha(Color.background, 0.5)
        PathSvg { path: root.panelPath(ghost.width, ghost.height) }
      }
    }

    Shape {
      anchors.fill: parent

      ShapePath {
        strokeWidth: 1.5
        strokeColor: Color.accent
        fillColor: Color.background
        PathSvg { path: root.panelPath(ghost.width, ghost.height) }
      }
    }

    Rectangle {
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
      }
      anchors.leftMargin: root.panelCut(ghost.width, ghost.height)
      anchors.topMargin: 1
      height: 1
      color: Util.alpha("#ffffff", 0.16)
    }

    CardLabel {
      anchors.centerIn: parent
      emoji: root.dragId < 0 ? "" : root.customEmoji(root.dragId)
      icon: root.dragId < 0 ? "" : root.iconUrl(root.customIcon(root.dragId))
      iconTint: root.dragId >= 0 && root.customIconTint(root.dragId)
      label: root.dragId < 0 ? "" : root.cardText(root.dragId)
      maxWidth: ghost.width - 2 * Style.space(3)
      labelColor: root.dragId >= 0 && root.customColor(root.dragId) !== "" ? root.customColor(root.dragId) : Color.accent
    }
  }

  Item {
    id: grid
    anchors.fill: parent

    Repeater {
      model: root.barIds

      WidgetButton {
        id: button
        required property int modelData
        required property int index

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property bool dropped: root.dropFlash === modelData
        readonly property bool isTarget: root.dragId >= 0 && root.dropTargetId === modelData

        // Resting slot from the model order, plus two animated translates:
        // the live insertion slide while a neighbour is held, and a
        // transient settle offset that FLIPs the card from its pre-persist
        // position (or the cursor, for the lifted card) into its new slot.
        x: root.vertical ? 0 : root.slotPos(index)
        y: root.vertical ? root.slotPos(index) : 0

        transform: [
          Translate {
            x: root.vertical ? 0 : root.chipShift(button.modelData)
            y: root.vertical ? root.chipShift(button.modelData) : 0
            Behavior on x {
              NumberAnimation { duration: Style.duration(170); easing.type: Easing.OutCubic }
            }
            Behavior on y {
              NumberAnimation { duration: Style.duration(170); easing.type: Easing.OutCubic }
            }
          },
          Translate {
            id: settle
            Behavior on x {
              id: settleBx
              NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
            }
            Behavior on y {
              id: settleBy
              NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
            }
          }
        ]

        // Scene-space rect, so a cursor position in global layout coordinates
        // can be tested against it.
        function containsPoint(x, y) {
          var topLeft = mapToItem(null, 0, 0)
          var bottomRight = mapToItem(null, width, height)
          return x >= topLeft.x && x <= bottomRight.x && y >= topLeft.y && y <= bottomRight.y
        }

        bar: root.bar
        readonly property string emoji: root.customEmoji(modelData)
        readonly property string iconSrc: root.iconUrl(root.customIcon(modelData))
        readonly property bool hasMark: emoji !== "" || iconSrc !== ""
        readonly property bool named: !root.vertical && root.customName(modelData) !== ""
        readonly property string tintHex: root.customColor(modelData)
        readonly property color tint: tintHex !== "" ? tintHex : Color.accent
        text: root.cardLabel(modelData)
        labelVisible: false
        tooltipText: root.previewId >= 0 ? ""
          : (root.customName(modelData) || root.numberLabel(modelData)) + " — drag to reorder, double-click to edit"
        active: dropped
        opacity: dropped ? 1 : (root.dragId === modelData ? 0 : (occupied || focused ? 1 : 0.5))
        fixedWidth: root.vertical ? root.chipW : root.sizeOf(modelData)
        fixedHeight: root.chipH
        onPressed: function(mouseButton) { root.chipPressed(modelData, button, mouseButton) }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

        Component.onDestruction: {
          if (root.dragId === button.modelData) root.cancelDrag()
          if (root.previewAnchor === button || root.pendingPreviewId === button.modelData)
            root.previewCloseNow()
        }

        Timer {
          id: settleKick
          interval: 16
          onTriggered: {
            settle.x = 0
            settle.y = 0
          }
        }

        // Shake choreography: a ripple through the row when a card is
        // lifted, a shiver on hover, and a stronger shiver when this card
        // becomes the slot the held card is pushing into.
        SequentialAnimation {
          id: wiggle
          PropertyAnimation {
            target: button
            property: "rotation"
            from: 0
            to: -6
            duration: Style.duration(55)
            easing.type: Easing.OutCubic
          }
          PropertyAnimation {
            target: button
            property: "rotation"
            to: 6
            duration: Style.duration(55)
            easing.type: Easing.OutCubic
          }
          PropertyAnimation {
            target: button
            property: "rotation"
            to: -4
            duration: Style.duration(50)
            easing.type: Easing.OutCubic
          }
          PropertyAnimation {
            target: button
            property: "rotation"
            to: 0
            duration: Style.duration(50)
            easing.type: Easing.OutCubic
          }
        }

        PropertyAnimation {
          id: pop
          target: ring
          property: "scale"
          from: 0.95
          to: 1
          duration: Style.duration(180)
          easing.type: Easing.Bezier
          easing.bezierCurve: Style.easeOut
        }

        onTooltipHoveredChanged: {
          if (tooltipHovered) {
            if (root.dragId < 0) wiggle.restart()
            root.previewHoverEnter(modelData, button)
          } else {
            root.previewHoverExit(modelData)
          }
        }
        onIsTargetChanged: if (isTarget) {
          pop.restart()
          wiggle.restart()
        }

        Connections {
          target: root

          function onDragIdChanged() {
            if (root.dragId < 0 || root.dragId === button.modelData) return
            var ids = root.workspaceIds()
            var from = ids.indexOf(root.dragId)
            var me = ids.indexOf(button.modelData)
            if (from === -1 || me === -1) return
            cascadeDelay.interval = Math.max(0, Math.abs(me - from) - 1) * 45
            cascadeDelay.start()
          }

          function onDropAt(address, dropX, dropY) {
            if (!root.bar) return
            if (!button.containsPoint(dropX, dropY)) return

            root.applyWorkspaceDrop(button.modelData, address)
          }
        }

        Timer {
          id: cascadeDelay
          onTriggered: wiggle.restart()
        }

        // Insertion-gap frame: the same chamfered panel outline lit in
        // accent, pops in on the card being pushed aside during a drag.
        Shape {
          id: ring
          anchors.fill: parent
          z: -1
          transformOrigin: Item.Center
          visible: button.isTarget

          ShapePath {
            strokeWidth: 1
            strokeColor: Color.accent
            fillColor: Util.alpha(Color.accent, 0.18)
            PathSvg { path: root.panelPath(button.width, button.height) }
          }
        }

        // The chip itself: a chamfered HUD panel — hairline frame, accent
        // rim on the focused workspace, corner brackets while focused or
        // hovered, presence/focus ticks along the bottom edge.
        // A custom colour replaces the accent on this card and tints it even
        // when unfocused.
        readonly property bool solid: focused && root.solidActive && !dropped
        readonly property color onTint: root.contrastOn(tint)
        readonly property color plateFill: dropped ? Util.alpha(Color.urgent, 0.32)
          : solid ? Util.alpha(tint, 0.92)
          : focused ? Util.alpha(tint, 0.22)
          : tintHex !== "" ? Util.alpha(tint, occupied ? 0.18 : 0.08)
          : Util.alpha(root.barFg, occupied ? 0.12 : 0.06)
        readonly property color plateStroke: solid ? Qt.lighter(tint, 1.3)
          : focused ? Util.alpha(tint, 0.95)
          : tintHex !== "" ? Util.alpha(tint, occupied ? 0.7 : 0.4)
          : Util.alpha(root.barFg, occupied ? 0.5 : 0.28)
        readonly property color bracketColor: solid ? onTint
          : focused ? tint
          : Util.alpha(root.barFg, 0.7)

        Shape {
          anchors.fill: parent
          z: -2

          // The settle FLIP: seed the translate with the snapshotted offset,
          // then kick it to zero on the next tick so the Behavior eases the
          // card home. This lives on the background plate because an
          // instance-level Component.onCompleted on the WidgetButton delegate
          // would compete with the type's own completion handler.
          Component.onCompleted: {
            var snap = root.prevSlots ? root.prevSlots[button.modelData] : undefined
            if (snap === undefined) return
            delete root.prevSlots[button.modelData]

            var curX = button.x + (root.vertical ? 0 : root.chipShift(button.modelData))
            var curY = button.y + (root.vertical ? root.chipShift(button.modelData) : 0)
            var dx = snap.x - curX
            var dy = snap.y - curY
            if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return

            settleBx.enabled = false
            settleBy.enabled = false
            settle.x = dx
            settle.y = dy
            settleBx.enabled = true
            settleBy.enabled = true
            settleKick.restart()
          }

          ShapePath {
            strokeWidth: button.solid ? 2 : 1
            strokeColor: button.plateStroke
            fillColor: button.plateFill
            PathSvg { path: root.panelPath(button.width, button.height) }
          }
        }

        // Soft glow around the active card.
        Shape {
          anchors.fill: parent
          z: -3
          visible: button.solid
          opacity: 0.45

          ShapePath {
            strokeWidth: 5
            strokeColor: Util.alpha(button.tint, 0.6)
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.panelPath(button.width, button.height) }
          }
        }

        // Targeting brackets on the two sharp corners (top-right and
        // bottom-left — the other two are cut away): snap in while the card
        // is focused or under the cursor.
        Item {
          anchors.fill: parent
          z: -1
          opacity: (button.focused || button.tooltipHovered) ? 1 : 0
          visible: opacity > 0

          Behavior on opacity {
            NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic }
          }

          Rectangle {
            x: parent.width - 8
            y: 2
            width: Style.space(6)
            height: 2
            color: button.bracketColor
          }
          Rectangle {
            x: parent.width - 2
            y: 2
            width: 2
            height: Style.space(6)
            color: button.bracketColor
          }
          Rectangle {
            x: 2
            y: parent.height - 2
            width: Style.space(6)
            height: 2
            color: button.bracketColor
          }
          Rectangle {
            x: 2
            y: parent.height - 8
            width: 2
            height: Style.space(6)
            color: button.bracketColor
          }
        }

        Rectangle {
          visible: button.occupied && !button.focused && !button.dropped
          z: -1
          anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 3
          }
          width: Math.max(5, Math.floor(parent.width * 0.3))
          height: 1.5
          color: Util.alpha(root.barFg, 0.7)
        }

        Rectangle {
          visible: button.focused
          z: -1
          anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 2
          }
          width: Math.max(6, Math.floor(parent.width * 0.4))
          height: 2
          radius: 1
          color: button.solid ? button.onTint : button.tint
        }

        CardLabel {
          z: -1
          anchors.centerIn: parent
          emoji: button.emoji
          icon: button.iconSrc
          iconTint: root.customIconTint(button.modelData)
          label: button.focused && !button.hasMark && !button.named
            ? "\uDB85\uDCFB" : root.cardText(button.modelData)
          maxWidth: button.width - 2 * Style.space(3)
          labelColor: button.dropped ? button.activeColor
            : button.solid ? button.onTint
            : button.focused ? button.tint
            : button.tintHex !== "" ? Util.alpha(button.tint, button.occupied ? 1 : 0.6)
            : Util.alpha(root.barFg, button.occupied ? 1 : 0.6)
          opacity: button.hasMark && !button.occupied && !button.focused ? 0.6 : 1
        }

        // Below the threshold the handler stays inert and the button's own
        // MouseArea delivers the click as always; once crossed, the handler
        // takes an exclusive grab, which cancels the MouseArea so a drag can
        // never double as a focus click.
        DragHandler {
          id: drag
          target: null
          acceptedButtons: Qt.LeftButton
          dragThreshold: Style.space(4)
          grabPermissions: PointerHandler.CanTakeOverFromAnything
          enabled: button.interactive && button.pressable

          onActiveChanged: {
            if (drag.active) {
              root.prevSlots = ({})
              root.dragId = button.modelData
              root.dropTargetId = -1
              root.dropIndex = -1
              root.ghostTilt = 0
              button.hideOwnTooltip()
              root.previewCloseNow()
              var p = drag.centroid.scenePosition
              root.ghostX = p.x
              root.ghostY = p.y
            } else if (root.dragId === button.modelData) {
              root.finishDrag()
            }
          }
        }

        // centroid exposes no change signal, so poll it while the drag runs.
        // The tilt tracks horizontal velocity like a card carried across the
        // deck; the drop slot follows the cursor (see updateDropIndex).
        Timer {
          interval: 16
          repeat: true
          running: drag.active
          onTriggered: {
            var p = drag.centroid.scenePosition
            var moved = p.x - root.ghostX
            root.ghostX = p.x
            root.ghostY = p.y
            root.ghostTilt = Math.max(-9, Math.min(9, moved * 0.7))

            root.updateDropIndex(p.x, p.y)
          }
        }
      }
    }
    // The overflow stack: the cards that don't fit on the bar, behind one
    // chip. Click fans them out in a popup (stackCard). It wears the active
    // card's colour while the focused workspace is inside it, and takes a
    // dragged card (dropped here, the card goes to the end of the order).
    WidgetButton {
      id: stackBtn
      bar: root.bar
      visible: root.hasStack
      text: String(root.stackIds.length)
      labelVisible: false
      tooltipText: root.stackOpen ? ""
        : root.stackIds.length + (root.stackAll ? " workspaces" : root.stackIds.length === 1 ? " more workspace" : " more workspaces")
          + " — click to show"
      fixedWidth: root.stackChipW
      fixedHeight: root.chipH
      x: root.stackPos
      y: 0
      opacity: root.stackOccupied || focused || root.stackOpen || isTarget ? 1 : 0.5
      onPressed: function(mouseButton) { root.toggleStack() }
      onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

      readonly property bool focused: root.stackActiveId >= 0
      readonly property bool isTarget: root.dragId >= 0 && root.dropTargetId === root.stackTarget
      readonly property string tintHex: focused ? root.customColor(root.stackActiveId) : ""
      readonly property color tint: tintHex !== "" ? tintHex : Color.accent
      readonly property bool solid: focused && root.solidActive
      readonly property color onTint: root.contrastOn(tint)
      readonly property color ink: solid ? onTint
        : focused ? tint
        : Util.alpha(root.barFg, root.stackOccupied || root.stackOpen ? 1 : 0.6)
      readonly property string emoji: focused ? root.customEmoji(root.stackActiveId) : ""
      readonly property string iconSrc: focused ? root.iconUrl(root.customIcon(root.stackActiveId)) : ""

      onIsTargetChanged: if (isTarget) stackPop.restart()

      SequentialAnimation {
        id: stackPop
        PropertyAnimation { target: stackRing; property: "scale"; from: 0.95; to: 1; duration: Style.duration(160); easing.type: Easing.OutCubic }
      }

      Shape {
        id: stackRing
        anchors.fill: parent
        z: -1
        transformOrigin: Item.Center
        visible: stackBtn.isTarget

        ShapePath {
          strokeWidth: 1
          strokeColor: Color.accent
          fillColor: Util.alpha(Color.accent, 0.18)
          PathSvg { path: root.panelPath(stackBtn.width, stackBtn.height) }
        }
      }

      Shape {
        anchors.fill: parent
        z: -2

        ShapePath {
          strokeWidth: stackBtn.solid ? 2 : 1
          strokeColor: stackBtn.solid ? Qt.lighter(stackBtn.tint, 1.3)
            : stackBtn.focused ? Util.alpha(stackBtn.tint, 0.95)
            : Util.alpha(root.barFg, root.stackOpen ? 0.8 : (root.stackOccupied ? 0.5 : 0.28))
          fillColor: stackBtn.solid ? Util.alpha(stackBtn.tint, 0.92)
            : stackBtn.focused ? Util.alpha(stackBtn.tint, 0.22)
            : Util.alpha(root.barFg, root.stackOpen ? 0.18 : (root.stackOccupied ? 0.12 : 0.06))
          PathSvg { path: root.panelPath(stackBtn.width, stackBtn.height) }
        }
      }

      // Soft glow while the active workspace is inside.
      Shape {
        anchors.fill: parent
        z: -3
        visible: stackBtn.solid
        opacity: 0.45

        ShapePath {
          strokeWidth: 5
          strokeColor: Util.alpha(stackBtn.tint, 0.6)
          fillColor: "transparent"
          joinStyle: ShapePath.RoundJoin
          PathSvg { path: root.panelPath(stackBtn.width, stackBtn.height) }
        }
      }

      Row {
        z: -1
        anchors.centerIn: parent
        spacing: root.stackGap

        // A little deck of three cards, or the active card's emoji or icon
        // (and its name, once every card is in the stack).
        Item {
          id: deck
          visible: stackBtn.emoji === "" && stackBtn.iconSrc === "" && root.stackLabel === ""
          anchors.verticalCenter: parent.verticalCenter
          readonly property real unit: Math.max(2, Math.round(Style.spaceReal(2)))
          width: unit * 6
          height: unit * 5

          Repeater {
            model: 3

            Rectangle {
              required property int index
              x: (2 - index) * deck.unit
              y: index * deck.unit
              width: deck.unit * 4
              height: deck.unit * 3
              radius: 1
              color: index === 2 ? stackBtn.ink : "transparent"
              border.width: 1
              border.color: Util.alpha(stackBtn.ink, index === 2 ? 1 : (index === 1 ? 0.75 : 0.45))
            }
          }
        }

        CardLabel {
          visible: !deck.visible
          anchors.verticalCenter: parent.verticalCenter
          emoji: stackBtn.emoji
          icon: stackBtn.iconSrc
          iconTint: stackBtn.focused && root.customIconTint(root.stackActiveId)
          label: root.stackLabel
          maxWidth: stackBtn.width - 2 * root.cardPad - root.stackGap - root.stackCountW
          labelColor: stackBtn.ink
        }

        // How many cards are inside; a pill once the chip also carries a name.
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: root.stackCountW
          height: stackCount.implicitHeight + (root.stackAll ? Style.space(2) : 0)
          radius: height / 2
          color: root.stackAll ? Util.alpha(stackBtn.ink, 0.2) : "transparent"

          Text {
            id: stackCount
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: String(root.stackIds.length)
            color: stackBtn.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            renderType: Text.NativeRendering
          }
        }
      }

      Rectangle {
        visible: stackBtn.focused || root.stackOccupied
        z: -1
        anchors {
          horizontalCenter: parent.horizontalCenter
          bottom: parent.bottom
          bottomMargin: stackBtn.focused ? 2 : 3
        }
        width: Math.max(6, Math.floor(parent.width * (stackBtn.focused ? 0.4 : 0.3)))
        height: stackBtn.focused ? 2 : 1.5
        radius: stackBtn.focused ? 1 : 0
        color: stackBtn.focused ? (stackBtn.solid ? stackBtn.onTint : stackBtn.tint) : Util.alpha(root.barFg, 0.7)
      }
    }

    WidgetButton {
      id: addBtn
      text: "+"
      labelVisible: true
      tooltipText: "Add workspace · right-click for settings, rooms & help"
      fixedWidth: root.chipW
      fixedHeight: root.chipH
      x: root.vertical ? 0 : root.cardsEnd + root.hGap
      y: root.vertical ? root.rowLength + root.vGap : 0
      onPressed: function(button) {
        root.stackOpen = false
        if (button === Qt.RightButton) {
          root.cancelRename()
          root.previewCloseNow()
          root.panelTab = "settings"
          root.roomNotice = ""
          root.profileNotice = ""
          root.profileConfirm = -1
          root.settingsOpen = true
          return
        }
        var nid = root.nextWorkspaceId()
        if (root.hiddenSet[nid]) root.unhideWorkspace(nid)
        root.focusWorkspace(nid)
      }
    }
  }

  // The stack fanned out: one row per stacked card, dealt in one after the
  // other from the chip. Click a row to go there, drag it up or down to
  // reorder, right-click to edit it, the arrow moves it to the front of the
  // bar. Click-mode PopupCard, so a click anywhere else closes it.
  PopupCard {
    id: stackCard
    anchorItem: stackBtn
    owner: stackOwner
    bar: root.bar
    open: root.stackOpen && root.hasStack
    contentWidth: stackCard.fittedContentWidth(root.stackRowW + root.chipH + Style.space(6)
      + 2 * stackCard.padding + Style.space(8))
    contentHeight: stackCard.fittedContentHeight(stackColumn.implicitHeight)

    Column {
      id: stackColumn
      anchors.fill: parent
      spacing: Style.space(6)

      Repeater {
        model: root.stackIds

        Item {
          id: stackRow
          required property int modelData
          required property int index

          readonly property var workspace: root.workspaceById(modelData)
          readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
          readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
          readonly property string tintHex: root.customColor(modelData)
          readonly property color tint: tintHex !== "" ? tintHex : Color.accent
          readonly property bool solid: focused && root.solidActive
          readonly property color onTint: root.contrastOn(tint)
          readonly property bool hovered: stackRowMouse.containsMouse
          // 0 → 1 as the row is dealt in: each row fades in and settles
          // down from the chip a beat after the one above it.
          property real reveal: 1
          // Held and carried by a drag, or stepping aside for the held row.
          readonly property bool held: root.stackHeld === stackRow.index
          readonly property real shift: held ? root.stackCarry : root.stackShift(stackRow.index)
          property real shown: shift
          Behavior on shown {
            enabled: !stackRow.held || root.stackSettling
            NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic }
          }

          width: stackColumn.width
          height: root.chipH
          z: held ? 1 : 0
          opacity: reveal
          scale: 0.97 + 0.03 * reveal
          transformOrigin: Item.Top
          transform: Translate {
            y: (1 - stackRow.reveal) * -Style.space(8) + stackRow.shown
          }

          function deal() {
            fanIn.stop()
            stackRow.reveal = 0
            fanIn.restart()
          }

          SequentialAnimation {
            id: fanIn
            PauseAnimation { duration: Style.duration(Math.min(stackRow.index, 4) * 25) }
            NumberAnimation {
              target: stackRow
              property: "reveal"
              to: 1
              duration: Style.duration(180)
              easing.type: Easing.Bezier
              easing.bezierCurve: Style.easeOut
            }
          }

          Connections {
            target: root
            function onStackOpenChanged() { if (root.stackOpen) stackRow.deal() }
          }

          Item {
            id: plate
            width: parent.width - root.chipH - Style.space(6)
            height: parent.height

            Component.onCompleted: if (root.stackOpen && !root.stackNoDeal) stackRow.deal()

            Shape {
              anchors.fill: parent

              ShapePath {
                strokeWidth: stackRow.solid || stackRow.held ? 2 : 1
                strokeColor: stackRow.held && !stackRow.solid ? Color.accent
                  : stackRow.solid ? Qt.lighter(stackRow.tint, 1.3)
                  : stackRow.focused ? Util.alpha(stackRow.tint, 0.95)
                  : stackRow.tintHex !== "" ? Util.alpha(stackRow.tint, stackRow.hovered ? 1 : (stackRow.occupied ? 0.7 : 0.4))
                  : Util.alpha(Color.foreground, stackRow.hovered ? 0.85 : (stackRow.occupied ? 0.5 : 0.28))
                fillColor: stackRow.solid ? Util.alpha(stackRow.tint, 0.92)
                  : stackRow.focused ? Util.alpha(stackRow.tint, 0.22)
                  : stackRow.tintHex !== "" ? Util.alpha(stackRow.tint, stackRow.hovered ? 0.26 : (stackRow.occupied ? 0.18 : 0.08))
                  : Util.alpha(Color.foreground, stackRow.hovered ? 0.18 : (stackRow.occupied ? 0.12 : 0.06))
                PathSvg { path: root.panelPath(plate.width, plate.height) }
              }
            }

            CardLabel {
              x: root.cardPad
              anchors.verticalCenter: parent.verticalCenter
              emoji: root.customEmoji(stackRow.modelData)
              icon: root.iconUrl(root.customIcon(stackRow.modelData))
              iconTint: root.customIconTint(stackRow.modelData)
              label: root.customName(stackRow.modelData) !== "" ? root.customName(stackRow.modelData)
                : "Workspace " + root.numberLabel(stackRow.modelData)
              maxWidth: plate.width - 2 * root.cardPad
              labelColor: stackRow.solid ? stackRow.onTint
                : stackRow.focused ? stackRow.tint
                : stackRow.tintHex !== "" ? Util.alpha(stackRow.tint, stackRow.occupied ? 1 : 0.6)
                : Util.alpha(Color.foreground, stackRow.occupied ? 1 : 0.6)
              opacity: hasMark && !stackRow.occupied && !stackRow.focused ? 0.6 : 1
            }

            Rectangle {
              visible: stackRow.occupied || stackRow.focused
              anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: stackRow.focused ? 2 : 3
              }
              width: Math.max(6, Math.floor(parent.width * (stackRow.focused ? 0.4 : 0.3)))
              height: stackRow.focused ? 2 : 1.5
              color: stackRow.focused ? (stackRow.solid ? stackRow.onTint : stackRow.tint)
                : Util.alpha(Color.foreground, 0.7)
            }

            // Click goes there; press and move past a few pixels picks the
            // row up instead (no click then). Positions are read in the
            // list's coordinates, which the carried row doesn't move.
            MouseArea {
              id: stackRowMouse
              property real pressY: 0
              property bool dragging: false
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              onPressed: function(mouse) {
                dragging = false
                if (mouse.button === Qt.LeftButton) pressY = mapToItem(stackColumn, mouse.x, mouse.y).y
              }
              onPositionChanged: function(mouse) {
                if (!pressed || !(mouse.buttons & Qt.LeftButton) || root.stackSettling) return
                var dy = mapToItem(stackColumn, mouse.x, mouse.y).y - pressY
                if (!dragging) {
                  if (Math.abs(dy) < Style.space(4) || root.stackIds.length < 2) return
                  dragging = true
                  root.holdStackRow(stackRow.index)
                }
                root.carryStackRow(dy)
              }
              onReleased: if (dragging && stackRow.held) root.dropStackRow()
              onCanceled: {
                if (dragging && stackRow.held) root.cancelStackDrag()
                dragging = false
              }
              onClicked: function(mouse) {
                if (dragging) {
                  dragging = false
                  return
                }
                var id = stackRow.modelData
                root.stackOpen = false
                if (mouse.button === Qt.RightButton) root.startRename(id, stackBtn)
                else root.focusWorkspace(id)
              }
            }
          }

          // Move this card to the front of the bar.
          Rectangle {
            anchors.right: parent.right
            width: root.chipH
            height: root.chipH
            radius: Style.space(4)
            color: frontMouse.containsMouse ? Util.alpha(Color.accent, 0.22) : "transparent"
            border.width: 1
            border.color: frontMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.25)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.bar && root.bar.position === "bottom" ? "↓" : "↑"
              color: frontMouse.containsMouse ? Color.accent : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              renderType: Text.NativeRendering
            }

            MouseArea {
              id: frontMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.moveToFront(stackRow.modelData)
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Click: go there · Drag: reorder · Right-click: edit · "
          + (root.bar && root.bar.position === "bottom" ? "↓" : "↑") + (root.stackAll ? ": first in the list" : ": first on the bar")
        color: Util.alpha(Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall !== undefined ? Style.font.bodySmall : Style.font.body
        renderType: Text.NativeRendering
      }
    }
  }

  FloatingWindow {
    id: iconLibrary
    visible: root.libraryOpen
    title: "HUD Workspaces \u2013 Icon library"
    color: Color.background
    implicitWidth: 560
    implicitHeight: 600
    minimumSize: Qt.size(380, 360)

    // Closed by the window manager (Super+W): just stay closed.
    onVisibleChanged: {
      if (!visible && root.libraryOpen) {
        root.libraryOpen = false
        root.libraryForId = -1
        root.libraryDraft = null
      }
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.closeIconLibrary("")

      Column {
        id: libHeader
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 6

        Row {
          spacing: 10

          HudIconGlyph {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.font.title
            color: Color.foreground
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Icon library"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          text: (root.libraryForId >= 0
              ? "For " + (root.customName(root.libraryForId) || "Workspace " + root.numberLabel(root.libraryForId)) +
                ". Click an icon to use it. "
              : "") +
            "Drag image files here from your file manager (SVG, PNG, JPG, WebP)."
          color: Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          visible: root.libraryNotice !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.libraryNotice
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }

      // The drop zone is the whole grid area.
      Rectangle {
        id: libZone
        anchors {
          left: parent.left; right: parent.right; top: libHeader.bottom; bottom: libFooter.top
          margins: 18
        }
        radius: Style.space(4)
        color: root.libraryDragOver ? Util.alpha(Color.accent, 0.12) : Util.alpha(Color.foreground, 0.03)
        border.width: root.libraryDragOver ? 2 : 1
        border.color: root.libraryDragOver ? Color.accent : Util.alpha(Color.foreground, 0.18)

        GridView {
          id: libGrid
          anchors.fill: parent
          anchors.margins: 8
          clip: true
          model: root.customIcons
          cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 92)))
          cellHeight: 92
          boundsBehavior: Flickable.StopAtBounds
          QQC.ScrollBar.vertical: QQC.ScrollBar {}

          delegate: Rectangle {
            id: libCell
            required property string modelData
            readonly property bool isNew: root.libraryNew.indexOf(modelData) >= 0
            readonly property bool current: root.libraryDraft !== null && root.libraryDraft.icon === modelData
            width: libGrid.cellWidth - 4
            height: libGrid.cellHeight - 4
            radius: Style.space(4)
            color: libMouse.containsMouse ? Util.alpha(Color.foreground, 0.1)
              : current ? Util.alpha(Color.accent, 0.22)
              : isNew ? Util.alpha(Color.accent, 0.12) : "transparent"
            border.width: isNew || current ? 1 : 0
            border.color: Color.accent

            MarkIcon {
              anchors.horizontalCenter: parent.horizontalCenter
              y: 12
              width: 40
              height: 40
              source: root.iconUrl(libCell.modelData)
            }

            Text {
              textFormat: Text.PlainText
              anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideMiddle
              text: libCell.modelData
              color: Util.alpha(Color.foreground, 0.75)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: libMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.libraryForId >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: if (root.libraryForId >= 0) root.closeIconLibrary(libCell.modelData)
            }
          }
        }

        Column {
          anchors.centerIn: parent
          visible: root.customIcons.length === 0 || root.libraryDragOver
          spacing: 10

          HudIconGlyph {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 40
            color: root.libraryDragOver ? Color.accent : Util.alpha(Color.foreground, 0.5)
            visible: root.customIcons.length === 0
          }

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.libraryDragOver ? "Drop to add" : "Drag image files here"
            color: root.libraryDragOver ? Color.accent : Util.alpha(Color.foreground, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
        }

        DropArea {
          anchors.fill: parent
          onEntered: function(drag) {
            var ok = drag.hasUrls && root.imagePathsFromUrls(drag.urls).length > 0
            drag.accepted = ok
            root.libraryDragOver = ok
          }
          onExited: root.libraryDragOver = false
          onDropped: function(drop) {
            root.libraryDragOver = false
            if (root.importToLibrary(root.imagePathsFromUrls(drop.urls))) drop.acceptProposedAction()
            else root.libraryNotice = "Only SVG, PNG, JPG and WebP files can be icons."
          }
        }
      }

      Row {
        id: libFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
        spacing: 8
        layoutDirection: Qt.LeftToRight

        Button {
          text: "Add images\u2026"
          onClicked: root.pickIconFiles()
        }

        Button {
          text: "Open folder"
          onClicked: root.openIconFolder()
        }

        Item {
          width: Math.max(0, libFooter.width - x - libBack.width - libFooter.spacing)
          height: 1
        }

        Button {
          id: libBack
          text: root.libraryForId >= 0 ? "Back to editor" : "Close"
          onClicked: root.closeIconLibrary("")
        }
      }
    }
  }
}
