import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "oma.razer"
  ipcTarget: "oma.razer"
  manageIpc: false

  readonly property string scriptPath: Qt.resolvedUrl(".").toString().replace("file://", "") + "/razer_ctl.py"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Settings
  readonly property bool showDpiInBar: setting("showDpiInBar", true) !== false
  readonly property bool onlyWhenConnected: setting("onlyWhenConnected", false) !== false
  readonly property bool notifyOnConnect: setting("notifyOnConnect", true) !== false
  readonly property string languageSetting: setting("language", "en")
  readonly property string currentLang: {
    var l = (root.languageSetting || "en").toLowerCase()
    if (l === "auto") {
      var sys = Qt.locale().name.toLowerCase()
      return sys.startsWith("es") ? "es" : "en"
    }
    return (l === "es") ? "es" : "en"
  }

  function t(key) {
    return Model.t(key, root.currentLang)
  }

  // Device state
  property bool deviceConnected: false
  property string deviceName: "Razer Viper 8KHz"
  property string devicePid: "0x0091"
  property int maxDpi: 20000
  property bool supports8k: true
  property bool hasPermission: false
  property string activeProfileId: "onboard-1"
  property string activeProfileName: "Profile 1"
  property int currentOnboardSlot: 1
  property int currentDpi: 1600
  property var currentDpiStages: [400, 800, 1600, 3200, 6400]
  property int currentActiveStage: 3
  property int currentPollRate: 1000
  property int batteryLevel: -1
  property bool charging: false
  property int currentBrightness: 100
  property string currentEffect: "spectrum"
  property string currentEffectColor: "#00FF00"
  // Lighting zones: "all" holds the profile-wide values, zoneLighting each zone's resolved values
  property var lightingZones: ["logo"]
  property var allLighting: ({ brightness: 100, effect: "spectrum", effect_color: "#00FF00" })
  property var zoneLighting: ({})
  property string selectedZone: "all"
  property var allProfiles: []
  property bool isPolling: false
  property bool initialPollDone: false

  // Profile switching animation & cache state
  property bool isSwitchingProfile: false
  property int switchingToSlot: 0
  property int pendingSwitchSlot: 0

  // Profile settings editor state (dedicated view with draft state)
  property bool showProfileSettings: false
  property int editingProfileSlot: 1
  property int editingStageIdx: 1
  property string draftBadgeColor: "#FFFFFF"
  property var draftDpiStages: [400, 800, 1600, 3200, 6400]
  property int draftActiveStage: 3
  property int draftPollRate: 1000
  property string draftEffect: "spectrum"
  property string draftEffectColor: "#00FF00"
  property int draftBrightness: 100

  visible: !onlyWhenConnected || deviceConnected
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  function open() {
    if (root.onlyWhenConnected && !root.deviceConnected) return
    root.controller.show()
  }

  function toggle() {
    if (root.onlyWhenConnected && !root.deviceConnected) {
      if (root.opened) root.close()
      return
    }
    root.opened ? root.close() : root.open()
  }

  function sendConnectionNotification(name, dpi, pollRate) {
    if (!root.notifyOnConnect) return
    var desc = name || root.t("razerMouse")
    desc += " • " + dpi + " DPI @ " + pollRate + " Hz"
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "oma.razer",
      "-g", "󰍽",
      "-t", "4000",
      root.t("razerMouseDetected"),
      desc,
      "--exec", "omarchy-shell", "oma.razer", "open"
    ])
  }

  property double lastUserActionTime: 0

  function updateCachedProfile(slot, patch) {
    var s = Number(slot) || root.currentOnboardSlot
    var list = []
    var found = false
    for (var i = 0; i < root.allProfiles.length; i++) {
      var p = Object.assign({}, root.allProfiles[i])
      if (Number(p.onboardSlot) === s) {
        Object.assign(p, patch)
        found = true
      }
      list.push(p)
    }
    if (!found) {
      for (var slotIdx = 1; slotIdx <= 5; slotIdx++) {
        var defP = Object.assign({}, Model.profileForSlot(slotIdx, root.allProfiles))
        if (slotIdx === s) Object.assign(defP, patch)
        list.push(defP)
      }
    }
    root.allProfiles = list
  }

  function applyCachedProfileToUi(slotNum) {
    var prof = Model.profileForSlot(slotNum, root.allProfiles)
    root.currentOnboardSlot = slotNum
    root.activeProfileId = prof.id || ("onboard-" + slotNum)
    root.activeProfileName = prof.name || ("Profile " + slotNum)
    root.currentDpi = Number(prof.dpi) || 1600
    root.currentDpiStages = (Array.isArray(prof.dpi_stages) && prof.dpi_stages.length === 5) ? prof.dpi_stages.slice() : [400, 800, 1600, 3200, 6400]
    root.currentActiveStage = Number(prof.active_stage) || 3
    root.currentPollRate = Number(prof.poll_rate) || 1000
    var b = (prof.brightness !== undefined) ? Number(prof.brightness) : 100
    var eff = prof.effect || "spectrum"
    var col = prof.effect_color || "#00FF00"
    root.allLighting = { brightness: b, effect: eff, effect_color: col }
    var zMap = {}
    for (var i = 0; i < root.lightingZones.length; i++) {
      var zName = root.lightingZones[i]
      var zOverride = (prof.zones && prof.zones[zName]) ? prof.zones[zName] : {}
      zMap[zName] = {
        brightness: (zOverride.brightness !== undefined) ? zOverride.brightness : b,
        effect: zOverride.effect || eff,
        effect_color: zOverride.effect_color || col
      }
    }
    root.zoneLighting = zMap
    root.showZone(root.isZone(root.selectedZone) ? root.selectedZone : "all")
  }

  function refresh() {
    if (pollProc.running) return
    isPolling = true
    pollProc.running = true
  }

  function applyDpi(val) {
    val = Math.max(100, Math.min(root.maxDpi, Math.round(val / 50) * 50))
    root.lastUserActionTime = Date.now()
    root.currentDpi = val
    var patch = { dpi: val }
    if (root.currentDpiStages && root.currentDpiStages.indexOf(val) !== -1) {
      root.currentActiveStage = root.currentDpiStages.indexOf(val) + 1
      patch.active_stage = root.currentActiveStage
    }
    root.updateCachedProfile(root.currentOnboardSlot, patch)
    Quickshell.execDetached([root.scriptPath, "set-dpi", String(val)])
  }

  function applyStage(idx) {
    idx = Math.max(1, Math.min(5, idx))
    root.lastUserActionTime = Date.now()
    root.currentActiveStage = idx
    if (root.currentDpiStages && root.currentDpiStages.length >= idx) {
      root.currentDpi = root.currentDpiStages[idx - 1]
    }
    root.updateCachedProfile(root.currentOnboardSlot, { active_stage: idx, dpi: root.currentDpi })
    Quickshell.execDetached([root.scriptPath, "set-stage", String(idx)])
  }

  function applyPollRate(hz) {
    hz = parseInt(hz)
    root.lastUserActionTime = Date.now()
    root.currentPollRate = hz
    root.updateCachedProfile(root.currentOnboardSlot, { poll_rate: hz })
    Quickshell.execDetached([root.scriptPath, "set-poll-rate", String(hz)])
  }

  function isZone(zone) {
    return zone === "all" || root.lightingZones.indexOf(zone) !== -1
  }

  function lightingFor(zone) {
    return (zone !== "all" && root.zoneLighting[zone]) ? root.zoneLighting[zone] : root.allLighting
  }

  // True when the zones no longer share the same value for key (shown as mixed under "All")
  function zonesDiffer(key) {
    for (var i = 0; i < root.lightingZones.length; i++) {
      var z = root.zoneLighting[root.lightingZones[i]]
      if (z && String(z[key]).toUpperCase() !== String(root.allLighting[key]).toUpperCase()) return true
    }
    return false
  }

  function showZone(zone) {
    root.selectedZone = zone
    var l = root.lightingFor(zone)
    root.currentBrightness = l.brightness
    root.currentEffect = l.effect
    root.currentEffectColor = l.effect_color
  }

  function storeLighting(zone, change) {
    var all = Object.assign({}, root.allLighting)
    var zones = Object.assign({}, root.zoneLighting)
    var targets = (zone === "all") ? root.lightingZones : [zone]
    if (zone === "all") Object.assign(all, change)
    for (var i = 0; i < targets.length; i++) {
      zones[targets[i]] = Object.assign({}, zones[targets[i]] || root.allLighting, change)
    }
    root.allLighting = all
    root.zoneLighting = zones
    root.showZone(root.selectedZone)
    if (zone === "all") {
      root.updateCachedProfile(root.currentOnboardSlot, change)
    }
  }

  function applyBrightness(val, zone) {
    zone = zone || root.selectedZone
    if (!root.isZone(zone)) return
    val = Math.max(0, Math.min(100, Math.round(val)))
    root.lastUserActionTime = Date.now()
    root.storeLighting(zone, { brightness: val })
    Quickshell.execDetached([root.scriptPath, "set-brightness", String(val), "--zone", zone])
  }

  function applyEffect(eff, color, zone) {
    zone = zone || root.selectedZone
    if (!root.isZone(zone)) return
    root.lastUserActionTime = Date.now()
    var current = root.lightingFor(zone)
    var change = { effect: eff, effect_color: color || current.effect_color }
    if (eff !== "off" && current.brightness === 0) {
      change.brightness = 100
    }
    root.storeLighting(zone, change)
    Quickshell.execDetached([root.scriptPath, "set-effect", eff, "--color", change.effect_color, "--zone", zone])
  }

  function switchProfile(target) {
    if (String(target) === "settings") {
      root.open()
      root.openProfileSettings(root.currentOnboardSlot)
      return
    }
    var slotNum = parseInt(target) || 1
    root.lastUserActionTime = Date.now()
    // 1. Apply cached profile settings immediately to UI so there is zero lag
    root.applyCachedProfileToUi(slotNum)
    root.editingProfileSlot = slotNum
    root.editingStageIdx = root.currentActiveStage

    // 2. Start animated hardware switch process
    root.switchingToSlot = slotNum
    root.isSwitchingProfile = true
    if (switchProc.running) {
      root.pendingSwitchSlot = slotNum
    } else {
      root.pendingSwitchSlot = 0
      switchProc.targetSlot = String(slotNum)
      switchProc.running = true
    }
  }

  function saveToOnboard(slot) {
    var slotNum = parseInt(slot) || root.currentOnboardSlot
    root.lastUserActionTime = Date.now()
    root.switchingToSlot = slotNum
    root.isSwitchingProfile = true
    Quickshell.execDetached([root.scriptPath, "profile", "save", "--slot", String(slotNum)])
    profileRefreshTimer.restart()
  }

  // Dedicated Profile Settings View Functions
  function loadDraftForSlot(slotNum) {
    var s = Number(slotNum) || root.currentOnboardSlot
    var prof = Model.profileForSlot(s, root.allProfiles)
    root.editingProfileSlot = s
    root.draftBadgeColor = Model.badgeColorForSlot(s, root.allProfiles)
    root.draftDpiStages = (Array.isArray(prof.dpi_stages) && prof.dpi_stages.length === 5)
      ? prof.dpi_stages.slice()
      : [400, 800, 1600, 3200, 6400]
    root.draftActiveStage = Math.max(1, Math.min(5, Number(prof.active_stage) || 3))
    root.editingStageIdx = root.draftActiveStage
    root.draftPollRate = Number(prof.poll_rate) || 1000
    root.draftEffect = prof.effect || "static"
    root.draftEffectColor = prof.effect_color || "#00FF00"
    root.draftBrightness = (prof.brightness !== undefined) ? Number(prof.brightness) : 100
  }

  function openProfileSettings(slotNum) {
    root.loadDraftForSlot(slotNum || root.currentOnboardSlot)
    root.showProfileSettings = true
  }

  function setDraftStageDpi(stageIdx, newDpi) {
    var idx = Math.max(1, Math.min(5, Number(stageIdx) || root.editingStageIdx))
    var val = Math.max(100, Math.min(root.maxDpi, Math.round(Number(newDpi) / 50) * 50))
    var nextStages = root.draftDpiStages.slice()
    nextStages[idx - 1] = val
    root.draftDpiStages = nextStages
  }

  function saveDraftProfile() {
    var s = Number(root.editingProfileSlot) || root.currentOnboardSlot
    var stages = root.draftDpiStages.slice()
    var activeSt = Math.max(1, Math.min(5, Number(root.draftActiveStage) || 3))
    var activeDpi = stages[activeSt - 1]
    var nextBright = (root.draftEffect !== "off" && root.draftBrightness === 0) ? 100 : root.draftBrightness

    root.lastUserActionTime = Date.now()
    root.updateCachedProfile(s, {
      badgeColor: root.draftBadgeColor,
      dpi_stages: stages,
      active_stage: activeSt,
      dpi: activeDpi,
      poll_rate: root.draftPollRate,
      effect: root.draftEffect,
      effect_color: root.draftEffectColor,
      brightness: nextBright
    })

    root.applyCachedProfileToUi(s)
    root.switchingToSlot = s
    root.isSwitchingProfile = true
    profileRefreshTimer.restart()

    Quickshell.execDetached([
      root.scriptPath, "profile", "update",
      "--slot", String(s),
      "--badge-color", root.draftBadgeColor,
      "--dpi-stages", stages.join(","),
      "--active-stage", String(activeSt),
      "--poll-rate", String(root.draftPollRate),
      "--effect", root.draftEffect,
      "--color", root.draftEffectColor,
      "--brightness", String(nextBright)
    ])

    root.showProfileSettings = false
  }

  Process {
    id: switchProc
    property string targetSlot: "1"
    command: [root.scriptPath, "profile", "switch", switchProc.targetSlot]
    onExited: function(code) {
      if (root.pendingSwitchSlot > 0 && String(root.pendingSwitchSlot) !== switchProc.targetSlot) {
        var nextSlot = root.pendingSwitchSlot
        root.pendingSwitchSlot = 0
        switchProc.targetSlot = String(nextSlot)
        switchProc.running = true
        return
      }
      root.pendingSwitchSlot = 0
      root.isSwitchingProfile = false
      root.switchingToSlot = 0
    }
  }

  Timer {
    id: profileRefreshTimer
    interval: 450
    repeat: false
    onTriggered: {
      root.isSwitchingProfile = false
      root.switchingToSlot = 0
      root.refresh()
    }
  }

  function runSetupPermissions() {
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      Qt.resolvedUrl(".").toString().replace("file://", "") + "/setup.sh"
    ])
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.showProfileSettings = false; root.open() }
    function settings(): void { root.open(); root.openProfileSettings(root.currentOnboardSlot) }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function dpi(val: string): void { root.applyDpi(parseInt(val)) }
    function stage(val: string): void { root.applyStage(parseInt(val)) }
    function poll(val: string): void { root.applyPollRate(parseInt(val)) }
    function profile(val: string): void { root.switchProfile(val) }
    function brightness(val: string): void { root.applyBrightness(parseInt(val), "all") }
    function effect(val: string): void { root.applyEffect(val, root.allLighting.effect_color, "all") }
    function color(val: string): void { root.applyEffect((root.allLighting.effect === "breathing") ? "breathing" : "static", val, "all") }
    function zoneBrightness(zone: string, val: string): void { root.applyBrightness(parseInt(val), zone) }
    function zoneEffect(zone: string, val: string): void { root.applyEffect(val, root.lightingFor(zone).effect_color, zone) }
    function zoneColor(zone: string, val: string): void { root.applyEffect((root.lightingFor(zone).effect === "breathing") ? "breathing" : "static", val, zone) }
  }

  IpcHandler {
    target: "oma.razercontrol"
    function open(): void { root.showProfileSettings = false; root.open() }
    function settings(): void { root.open(); root.openProfileSettings(root.currentOnboardSlot) }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function dpi(val: string): void { root.applyDpi(parseInt(val)) }
    function stage(val: string): void { root.applyStage(parseInt(val)) }
    function poll(val: string): void { root.applyPollRate(parseInt(val)) }
    function profile(val: string): void { root.switchProfile(val) }
    function brightness(val: string): void { root.applyBrightness(parseInt(val), "all") }
    function effect(val: string): void { root.applyEffect(val, root.allLighting.effect_color, "all") }
    function color(val: string): void { root.applyEffect((root.allLighting.effect === "breathing") ? "breathing" : "static", val, "all") }
    function zoneBrightness(zone: string, val: string): void { root.applyBrightness(parseInt(val), zone) }
    function zoneEffect(zone: string, val: string): void { root.applyEffect(val, root.lightingFor(zone).effect_color, zone) }
    function zoneColor(zone: string, val: string): void { root.applyEffect((root.lightingFor(zone).effect === "breathing") ? "breathing" : "static", val, zone) }
  }

  Process {
    id: pollProc
    command: [root.scriptPath, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isPolling = false
        var state = Model.parseOutput(text)
        var wasConnected = root.deviceConnected
        var newlyConnected = state.connected

        root.deviceConnected = state.connected
        root.deviceName = state.name
        root.devicePid = state.pid
        root.maxDpi = state.max_dpi || 20000
        root.supports8k = state.supports_8k
        root.hasPermission = state.has_permission
        root.batteryLevel = (state.battery === undefined || state.battery === null) ? -1 : state.battery
        root.charging = state.charging === true

        var now = Date.now()
        if (!root.isSwitchingProfile && (now - root.lastUserActionTime > 1500 || !root.initialPollDone)) {
          root.activeProfileId = state.activeProfile
          root.activeProfileName = state.activeProfileName
          root.currentOnboardSlot = state.onboardSlot
          root.currentDpi = state.dpi
          root.currentDpiStages = state.dpi_stages
          root.currentActiveStage = state.active_stage
          root.currentPollRate = state.poll_rate
          root.lightingZones = state.lighting_zones
          root.allLighting = { brightness: state.brightness, effect: state.effect, effect_color: state.effect_color }
          root.zoneLighting = state.zones
          root.showZone(root.isZone(root.selectedZone) ? root.selectedZone : "all")
          if (!root.initialPollDone) {
            root.editingProfileSlot = state.onboardSlot
            root.editingStageIdx = state.active_stage
          }
          root.allProfiles = state.profiles
        } else if (!root.initialPollDone) {
          root.allProfiles = state.profiles
        }

        if (root.initialPollDone) {
          if (!wasConnected && newlyConnected) {
            root.sendConnectionNotification(state.name, state.dpi, state.poll_rate)
          }
        }
        root.initialPollDone = true
      }
    }
    onExited: function(code) {
      root.isPolling = false
    }
  }

  Timer {
    id: pollTimer
    interval: panel.open ? 3000 : (root.deviceConnected ? 15000 : 8000)
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    root.refresh()
  }

  // Omarchy Status Bar Widget
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    visible: root.visible
    text: {
      if (root.showDpiInBar && root.deviceConnected && !vertical) {
        var label = "󰍽 " + root.currentDpi
        if (root.batteryLevel >= 0) {
          label += " " + root.batteryLevel + "%"
        }
        return label
      }
      return "󰍽"
    }
    slotSize: Style.bar.iconSlot * (root.showDpiInBar && root.deviceConnected && !vertical ? (root.batteryLevel >= 0 ? 2.9 : 2.0) : 1.0)
    tooltipText: root.deviceName + (root.deviceConnected ? (" (" + root.currentDpi + " DPI @ " + root.currentPollRate + " Hz" + (root.batteryLevel >= 0 ? ", batteri " + root.batteryLevel + " %" + (root.charging ? " (laddar)" : "") : "") + ")") : (" " + root.t("disconnected")))
    active: root.deviceConnected
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  // Interactive Popup Panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(
      panelColumn.implicitHeight + (settingsFooter.visible ? settingsFooter.implicitHeight + Style.space(10) : 0),
      Style.space(620)
    )

    onOpenChanged: if (open) {
      root.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: settingsFooter.visible ? settingsFooter.top : parent.bottom
        anchors.bottomMargin: settingsFooter.visible ? Style.space(10) : 0
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: panelFlick.width
          spacing: Style.space(14)

          // 1. Cabecera Hero: Dispositivo y Estado
          PanelHero {
            id: hero
            width: parent.width
            title: root.deviceName
            meta: root.deviceConnected ? (root.currentDpi + " DPI • " + Model.pollRateLabel(root.currentPollRate) + (root.batteryLevel >= 0 ? " • " + root.batteryLevel + " %" : "")) : root.t("deviceNotDetected")
            detail: root.deviceConnected ? (root.hasPermission ? root.t("onboardStatus") : root.t("udevPermissionsStatus")) : root.t("disconnectedStatus")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.deviceConnected ? 1.0 : 0.4

            iconComponent: Component {
              Text {
                text: "󰍽"
                color: (root.deviceConnected && root.currentEffect !== "off" && root.currentBrightness > 0) ? (root.currentEffectColor || Color.accent) : Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              Item {
                width: Style.space(26)
                height: Style.space(26)
                Text {
                  anchors.centerIn: parent
                  text: "󰑐"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: refreshArea.containsMouse ? Color.accent : Qt.darker(root.foreground, 1.4)
                  rotation: root.isPolling ? 360 : 0
                  Behavior on rotation { NumberAnimation { duration: 600 } }
                }
                MouseArea {
                  id: refreshArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refresh()
                }
              }
            }
          }

          // Banner de Permisos si no tiene acceso a /dev/hidraw
          Rectangle {
            id: permBanner
            width: parent.width
            implicitHeight: permRow.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            visible: root.deviceConnected && !root.hasPermission
            color: Qt.rgba(1.0, 0.2, 0.2, 0.12)
            border.color: Qt.rgba(1.0, 0.2, 0.2, 0.3)
            border.width: 1

            RowLayout {
              id: permRow
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Text {
                text: "󰀦"
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                color: "#FF4444"
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  text: root.t("udevRequiredTitle")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: "#FFAAAA"
                }
                Text {
                  text: root.t("udevRequiredDesc")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.foreground, 1.2)
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }

              Rectangle {
                implicitWidth: fixText.implicitWidth + Style.space(16)
                implicitHeight: Style.space(28)
                radius: Style.cornerRadius
                color: fixMouse.containsMouse ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                Text {
                  id: fixText
                  anchors.centerIn: parent
                  text: root.t("activateBtn")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: fixMouse.containsMouse ? Color.background : root.foreground
                }

                MouseArea {
                  id: fixMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runSetupPermissions()
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
          }

          // =========================================================================
          // VISTA DE AJUSTES DE PERFILES (Solo se renderiza cuando estás en Ajustes)
          // =========================================================================
          Column {
            id: settingsViewCol
            visible: root.showProfileSettings
            width: parent.width
            spacing: Style.space(12)

            readonly property int currentDraftStageDpi: (root.draftDpiStages && root.draftDpiStages.length === 5)
              ? root.draftDpiStages[Math.max(0, Math.min(4, root.editingStageIdx - 1))]
              : 1600

            // Cabecera de Ajustes + Botón Volver
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "󰒓 " + root.t("profileSettingsTitle")
                foreground: root.foreground
              }

              Item { Layout.fillWidth: true; height: 1 }

              Rectangle {
                implicitWidth: backRow.implicitWidth + Style.space(12)
                implicitHeight: Style.space(24)
                radius: Style.cornerRadius
                color: backMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1) : "transparent"
                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
                border.width: 1

                Row {
                  id: backRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    text: "← " + root.t("closeSettingsBtn")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    color: root.foreground
                  }
                }
                MouseArea {
                  id: backMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showProfileSettings = false
                }
              }
            }

            // Selector del Perfil a editar (P1 a P5)
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: root.t("editingProfileLabel")
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.2)
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [1, 2, 3, 4, 5]
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(34)
                    radius: Style.cornerRadius
                    readonly property int sNum: modelData
                    readonly property bool isEd: root.editingProfileSlot === sNum
                    readonly property color bCol: isEd ? root.draftBadgeColor : Model.badgeColorForSlot(sNum, root.allProfiles)

                    color: isEd
                      ? Qt.rgba(bCol.r, bCol.g, bCol.b, 0.22)
                      : (edProfMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
                    border.color: isEd ? bCol : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                    border.width: isEd ? 2 : 1

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: Style.space(6)
                      Rectangle {
                        width: Style.space(8)
                        height: Style.space(8)
                        radius: Style.cornerRadius
                        color: parent.parent.bCol
                      }
                      Text {
                        text: "P" + parent.parent.sNum
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.isEd
                        color: parent.parent.isEd ? root.foreground : Qt.darker(root.foreground, 1.3)
                      }
                    }

                    MouseArea {
                      id: edProfMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.loadDraftForSlot(parent.sNum)
                      }
                    }
                  }
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // A. Color identificador del perfil (badgeColor)
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: root.t("profileBadgeColorLabel") + " (P" + root.editingProfileSlot + ")"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.2)
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: ["#FFFFFF", "#FF0000", "#00FF00", "#0066FF", "#00FFFF", "#9900FF", "#FF6600", "#FFFF00", "#FF00AA"]
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(26)
                    radius: Style.cornerRadius
                    readonly property string hexVal: modelData
                    readonly property bool isChosen: String(root.draftBadgeColor).toUpperCase() === hexVal.toUpperCase()
                    color: hexVal
                    border.color: isChosen ? root.foreground : Qt.rgba(0, 0, 0, 0.45)
                    border.width: isChosen ? 2 : 1

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.draftBadgeColor = parent.hexVal
                    }
                  }
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // B. Editor de DPI de cada Stage (Stages 1 a 5)
            Column {
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                Text {
                  text: root.t("dpiStagesEditorLabel")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(root.foreground, 1.2)
                }
                Item { Layout.fillWidth: true; height: 1 }
                Text {
                  text: root.t("stageLabel") + " " + root.editingStageIdx + ": " + settingsViewCol.currentDraftStageDpi + " DPI"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Color.accent
                }
              }

              // Los 5 stages seleccionables para editar
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: root.draftDpiStages
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(36)
                    radius: Style.cornerRadius
                    readonly property int stIdx: index + 1
                    readonly property int stVal: modelData
                    readonly property bool isEditingSt: root.editingStageIdx === stIdx

                    color: isEditingSt
                      ? Style.selectedFillFor(root.foreground, Color.accent)
                      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                    border.color: isEditingSt ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                    border.width: isEditingSt ? 1.5 : 1

                    Column {
                      anchors.centerIn: parent
                      spacing: 0
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "S" + parent.parent.stIdx
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption - 2
                        color: parent.parent.isEditingSt ? Color.accent : Qt.darker(root.foreground, 1.4)
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.parent.stVal
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: parent.parent.isEditingSt
                        color: parent.parent.isEditingSt ? Color.accent : root.foreground
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.editingStageIdx = parent.stIdx
                        root.draftActiveStage = parent.stIdx
                      }
                    }
                  }
                }
              }

              // Controles rápidos (-100, -50, Input directo, +50, +100) para el Stage seleccionado
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [-100, -50]
                  Rectangle {
                    implicitWidth: Style.space(44)
                    implicitHeight: Style.space(28)
                    radius: Style.cornerRadius
                    color: stepDownMouse.containsMouse
                      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                    border.width: 1
                    Text {
                      anchors.centerIn: parent
                      text: String(modelData)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.foreground
                    }
                    MouseArea {
                      id: stepDownMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var nextVal = Math.max(100, settingsViewCol.currentDraftStageDpi + modelData)
                        root.setDraftStageDpi(root.editingStageIdx, nextVal)
                      }
                    }
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
                  border.width: 1

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(settingsViewCol.currentDraftStageDpi)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      color: root.foreground
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: "DPI"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.fineprint
                      color: Qt.darker(root.foreground, 1.3)
                    }
                  }
                }

                Repeater {
                  model: [50, 100]
                  Rectangle {
                    implicitWidth: Style.space(44)
                    implicitHeight: Style.space(28)
                    radius: Style.cornerRadius
                    color: stepUpMouse.containsMouse
                      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                    border.width: 1
                    Text {
                      anchors.centerIn: parent
                      text: "+" + String(modelData)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.foreground
                    }
                    MouseArea {
                      id: stepUpMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var nextVal = Math.min(root.maxDpi, settingsViewCol.currentDraftStageDpi + modelData)
                        root.setDraftStageDpi(root.editingStageIdx, nextVal)
                      }
                    }
                  }
                }
              }

              // Slider dedicado para ajustar el DPI del Stage seleccionado
              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 100
                maximum: root.maxDpi
                step: 50
                integer: true
                value: settingsViewCol.currentDraftStageDpi
                onMoved: function(v) {
                  var snapped = Math.round(v / 50) * 50
                  root.setDraftStageDpi(root.editingStageIdx, snapped)
                }
                onReleased: function(v) {
                  var snapped = Math.round(v / 50) * 50
                  root.setDraftStageDpi(root.editingStageIdx, snapped)
                }
                MouseArea {
                  anchors.fill: parent
                  z: 10
                  acceptedButtons: Qt.NoButton
                  onWheel: function(wheel) {
                    if (panelFlick.contentHeight > panelFlick.height) {
                      var dy = wheel.angleDelta.y * 0.5
                      panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY - dy))
                    }
                    wheel.accepted = true
                  }
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // C. Polling Rate del Perfil
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                text: root.t("profilePollingLabel") + " (P" + root.editingProfileSlot + ")"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.2)
              }

              ButtonGroup {
                options: Model.pollOptions(root.supports8k)
                value: String(root.draftPollRate)
                fontFamily: root.fontFamily
                foreground: root.foreground
                onChanged: function(val) {
                  root.draftPollRate = parseInt(val) || 1000
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // D. Efecto y Color RGB del Perfil
            Column {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: root.t("profileLightingLabel") + " (P" + root.editingProfileSlot + ")"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Qt.darker(root.foreground, 1.2)
              }

              ButtonGroup {
                options: Model.effectOptions(root.currentLang)
                value: root.draftEffect
                fontFamily: root.fontFamily
                foreground: root.foreground
                onChanged: function(val) {
                  root.draftEffect = val
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                visible: root.draftEffect !== "off"

                Repeater {
                  model: ["#00FF00", "#00FFFF", "#0066FF", "#9900FF", "#FF0000", "#FF6600", "#FFFF00", "#FFFFFF"]
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(26)
                    radius: Style.cornerRadius
                    readonly property string cHex: modelData
                    readonly property bool isChosenCol: String(root.draftEffectColor).toUpperCase() === cHex.toUpperCase()
                    color: cHex
                    border.color: isChosenCol ? root.foreground : Qt.rgba(0, 0, 0, 0.45)
                    border.width: isChosenCol ? 2 : 1

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.draftEffect !== "breathing") {
                          root.draftEffect = "static"
                        }
                        root.draftEffectColor = parent.cHex
                      }
                    }
                  }
                }
              }
            }
          }

          // =========================================================================
          // VISTA PRINCIPAL DEL PANEL (Oculta cuando estás dentro de Ajustes)
          // =========================================================================
          Column {
            id: mainViewCol
            visible: !root.showProfileSettings
            width: parent.width
            spacing: Style.space(14)

            // 2. Perfiles en Memoria On-Board (Slots 1 a 5)
            Column {
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                PanelSectionHeader {
                  text: root.t("onboardProfilesTitle")
                  foreground: root.foreground
                }
                Text {
                  visible: root.isSwitchingProfile
                  text: "󰑐 " + root.t("switchingProfile")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  color: Color.accent
                }
                Item {
                  Layout.fillWidth: true
                  height: 1
                }
                // Botón para entrar a la vista de Ajustes de Perfiles
                Rectangle {
                  id: editProfToggleBtn
                  implicitWidth: editProfToggleRow.implicitWidth + Style.space(12)
                  implicitHeight: Style.space(22)
                  radius: Style.cornerRadius
                  color: editProfToggleMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  border.width: 1

                  Row {
                    id: editProfToggleRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text {
                      text: "󰒓"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      color: Color.accent
                    }
                    Text {
                      text: root.t("profileSettingsBtn")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      color: root.foreground
                    }
                  }
                  MouseArea {
                    id: editProfToggleMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.openProfileSettings(root.currentOnboardSlot)
                    }
                  }
                }
                Rectangle {
                  id: burnBtn
                  implicitWidth: burnRow.implicitWidth + Style.space(12)
                  implicitHeight: Style.space(22)
                  radius: Style.cornerRadius
                  color: burnMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"
                  border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  border.width: 1

                  Row {
                    id: burnRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text {
                      text: "󰆓"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      color: Color.accent
                    }
                    Text {
                      text: root.t("saveToMouseBtn")
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - 1
                      color: root.foreground
                    }
                  }
                  MouseArea {
                    id: burnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.saveToOnboard(root.currentOnboardSlot)
                  }
                }
              }

              // Barra de ranuras de perfiles 1 a 5 con código de color y animación de cambio
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: [1, 2, 3, 4, 5]
                  Rectangle {
                    id: profBtn
                    Layout.fillWidth: true
                    implicitHeight: Style.space(38)
                    radius: Style.cornerRadius
                    clip: true
                    readonly property int slotNum: modelData
                    readonly property bool isSelected: root.currentOnboardSlot === slotNum
                    readonly property bool isSwitchingThis: root.isSwitchingProfile && root.switchingToSlot === slotNum
                    readonly property color badgeCol: Model.badgeColorForSlot(slotNum, root.allProfiles)

                    color: isSelected ? Qt.rgba(badgeCol.r, badgeCol.g, badgeCol.b, 0.22) : (profMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
                    border.color: isSelected ? badgeCol : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    border.width: isSelected ? 2 : 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      Item {
                        width: Style.space(10)
                        height: Style.space(10)

                        Rectangle {
                          anchors.centerIn: parent
                          width: Style.space(8)
                          height: Style.space(8)
                          radius: Style.cornerRadius
                          color: profBtn.badgeCol
                          visible: !profBtn.isSwitchingThis
                        }

                        Text {
                          id: switchSpinIcon
                          anchors.centerIn: parent
                          visible: profBtn.isSwitchingThis
                          text: "󰑐"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          color: profBtn.badgeCol
                          RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 650
                            loops: Animation.Infinite
                            running: profBtn.isSwitchingThis
                          }
                        }
                      }

                      Text {
                        text: "P" + profBtn.slotNum
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: profBtn.isSelected
                        color: profBtn.isSelected ? root.foreground : Qt.darker(root.foreground, 1.3)
                      }
                    }

                    // Barra animada inferior cuando se está aplicando el perfil al ratón
                    Rectangle {
                      id: switchBar
                      visible: profBtn.isSwitchingThis
                      height: 2
                      width: parent.width * 0.45
                      anchors.bottom: parent.bottom
                      radius: 0
                      color: profBtn.badgeCol
                      SequentialAnimation on x {
                        loops: Animation.Infinite
                        running: profBtn.isSwitchingThis
                        NumberAnimation { from: -profBtn.width * 0.3; to: profBtn.width; duration: 550; easing.type: Easing.InOutQuad }
                      }
                    }

                    MouseArea {
                      id: profMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.switchProfile(profBtn.slotNum)
                    }
                  }
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // 3. Control de Sensibilidad (DPI)
            Column {
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                PanelSectionHeader {
                  text: root.t("sensitivityTitle")
                  foreground: root.foreground
                }
                Item {
                  Layout.fillWidth: true
                  height: 1
                }
                Text {
                  id: dpiValText
                  text: root.currentDpi + " DPI (" + root.t("stageLabel") + " " + root.currentActiveStage + "/5)"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                  font.bold: true
                }
              }

              // Botones de las 5 Etapas (Stages)
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: (root.currentDpiStages && root.currentDpiStages.length === 5) ? root.currentDpiStages : [400, 800, 1600, 3200, 6400]
                  Rectangle {
                    id: stageBtn
                    Layout.fillWidth: true
                    implicitHeight: Style.space(32)
                    radius: Style.cornerRadius
                    readonly property int stageIdx: index + 1
                    readonly property int stageVal: modelData
                    readonly property bool isActive: root.currentActiveStage === stageIdx

                    color: isActive ? Style.selectedFillFor(root.foreground, Color.accent) : (stageMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
                    border.color: isActive ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    border.width: isActive ? 1.5 : 1

                    Text {
                      anchors.centerIn: parent
                      text: stageBtn.stageVal
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: stageBtn.isActive
                      color: stageBtn.isActive ? Color.accent : root.foreground
                    }

                    MouseArea {
                      id: stageMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.applyStage(stageBtn.stageIdx)
                    }
                  }
                }
              }

              // Slider de ajuste continuo de DPI
              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 100
                maximum: root.maxDpi
                step: 50
                integer: true
                value: root.currentDpi
                onMoved: function(v) { root.currentDpi = Math.round(v / 50) * 50 }
                onReleased: function(v) { root.applyDpi(Math.round(v / 50) * 50) }
                MouseArea {
                  anchors.fill: parent
                  z: 10
                  acceptedButtons: Qt.NoButton
                  onWheel: function(wheel) {
                    if (panelFlick.contentHeight > panelFlick.height) {
                      var dy = wheel.angleDelta.y * 0.5
                      panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY - dy))
                    }
                    wheel.accepted = true
                  }
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // 4. Tasa de Sondeo (Polling Rate)
            Column {
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                PanelSectionHeader {
                  text: root.t("pollingRateTitle")
                  foreground: root.foreground
                }
                Item {
                  Layout.fillWidth: true
                  height: 1
                }
                Text {
                  id: pollValText
                  text: Model.pollRateLabel(root.currentPollRate)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                  font.bold: true
                }
              }

              ButtonGroup {
                options: Model.pollOptions(root.supports8k)
                value: String(root.currentPollRate)
                fontFamily: root.fontFamily
                foreground: root.foreground
                onChanged: function(val) { root.applyPollRate(parseInt(val)) }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // 5. Iluminación Chroma RGB
            Column {
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                PanelSectionHeader {
                  text: root.t("chromaLightingTitle")
                  foreground: root.foreground
                }
                Item {
                  Layout.fillWidth: true
                  height: 1
                }
                Text {
                  id: brightValText
                  text: (root.selectedZone === "all" && root.zonesDiffer("brightness")) ? root.t("lightingMixed") : root.currentBrightness + "%"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                  font.bold: true
                }
              }

              // Zonas de iluminación (solo en dispositivos con varias zonas)
              ButtonGroup {
                visible: root.lightingZones.length > 1
                options: Model.zoneOptions(root.lightingZones, root.currentLang)
                value: root.selectedZone
                fontFamily: root.fontFamily
                foreground: root.foreground
                onChanged: function(val) { root.showZone(val) }
              }

              // Slider de brillo
              PanelSlider {
                width: parent.width
                bar: root.bar
                minimum: 0
                maximum: 100
                step: 5
                integer: true
                value: root.currentBrightness
                onMoved: function(v) { root.currentBrightness = Math.round(v) }
                onReleased: function(v) { root.applyBrightness(Math.round(v)) }
                MouseArea {
                  anchors.fill: parent
                  z: 10
                  acceptedButtons: Qt.NoButton
                  onWheel: function(wheel) {
                    if (panelFlick.contentHeight > panelFlick.height) {
                      var dy = wheel.angleDelta.y * 0.5
                      panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, panelFlick.contentY - dy))
                    }
                    wheel.accepted = true
                  }
                }
              }

              // Efectos
              ButtonGroup {
                options: Model.effectOptions(root.currentLang)
                value: (root.selectedZone === "all" && root.zonesDiffer("effect")) ? "" : root.currentEffect
                fontFamily: root.fontFamily
                foreground: root.foreground
                onChanged: function(val) { root.applyEffect(val, root.currentEffectColor) }
              }

              // Paleta de colores rápidos (visible siempre excepto cuando está apagado)
              RowLayout {
                width: parent.width
                spacing: Style.space(6)
                visible: root.currentEffect !== "off" || (root.selectedZone === "all" && root.zonesDiffer("effect"))

                Repeater {
                  model: ["#00FF00", "#00FFFF", "#0066FF", "#9900FF", "#FF0000", "#FF6600", "#FFFF00", "#FFFFFF"]
                  Rectangle {
                    id: colorSwatch
                    Layout.fillWidth: true
                    implicitHeight: Style.space(26)
                    radius: Style.cornerRadius
                    readonly property string swatchHex: modelData
                    readonly property bool isSelected: (root.currentEffect === "static" || root.currentEffect === "breathing") && root.currentEffectColor.toUpperCase() === swatchHex.toUpperCase()
                      && !(root.selectedZone === "all" && (root.zonesDiffer("effect") || root.zonesDiffer("effect_color")))

                    color: swatchHex
                    border.color: isSelected ? root.foreground : Qt.rgba(0, 0, 0, 0.45)
                    border.width: isSelected ? 2 : 1

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var eff = (root.currentEffect === "breathing") ? "breathing" : "static"
                        root.applyEffect(eff, colorSwatch.swatchHex)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Barra inferior fija: SAVE CHANGES / GUARDAR CAMBIOS (siempre visible en Ajustes)
      Column {
        id: settingsFooter
        visible: root.showProfileSettings
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(8)

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        Rectangle {
          id: saveChangesBtn
          width: parent.width
          implicitHeight: Style.space(38)
          radius: Style.cornerRadius
          color: saveChangesMouse.containsMouse
            ? Color.accent
            : Style.selectedFillFor(root.foreground, Color.accent)
          border.color: Color.accent
          border.width: 1.5

          Behavior on color { ColorAnimation { duration: 120 } }

          Row {
            anchors.centerIn: parent
            spacing: Style.space(8)
            Text {
              text: "󰆓"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: saveChangesMouse.containsMouse ? Color.background : Color.accent
            }
            Text {
              text: root.t("saveChangesBtn") + " (P" + root.editingProfileSlot + ")"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              color: saveChangesMouse.containsMouse ? Color.background : root.foreground
            }
          }

          MouseArea {
            id: saveChangesMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.saveDraftProfile()
          }
        }
      }
    }
  }
}
