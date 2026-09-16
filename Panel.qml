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

  // Device state
  property bool deviceConnected: false
  property string deviceName: "Razer Viper 8KHz"
  property string devicePid: "0x0091"
  property bool supports8k: true
  property bool hasPermission: false
  property string activeProfileId: "onboard-1"
  property string activeProfileName: "Profile 1"
  property int currentOnboardSlot: 1
  property int currentDpi: 1600
  property var currentDpiStages: [400, 800, 1600, 3200, 6400]
  property int currentActiveStage: 3
  property int currentPollRate: 1000
  property int currentBrightness: 100
  property string currentEffect: "spectrum"
  property string currentEffectColor: "#00FF66"
  property var allProfiles: []
  property bool isPolling: false
  property bool initialPollDone: false

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
    var desc = name || "Ratón Razer"
    desc += " • " + dpi + " DPI @ " + pollRate + " Hz"
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "oma.razer",
      "-g", "󰍽",
      "-t", "4000",
      "Ratón Razer detectado",
      desc,
      "--exec", "omarchy-shell", "oma.razer", "open"
    ])
  }

  function refresh() {
    if (pollProc.running) return
    isPolling = true
    pollProc.running = true
  }

  function applyDpi(val) {
    val = Math.max(100, Math.min(30000, Math.round(val)))
    root.currentDpi = val
    Quickshell.execDetached([root.scriptPath, "set-dpi", String(val)])
    Qt.callLater(function() { root.refresh() })
  }

  function applyStage(idx) {
    idx = Math.max(1, Math.min(5, idx))
    root.currentActiveStage = idx
    if (root.currentDpiStages && root.currentDpiStages.length >= idx) {
      root.currentDpi = root.currentDpiStages[idx - 1]
    }
    Quickshell.execDetached([root.scriptPath, "set-stage", String(idx)])
    Qt.callLater(function() { root.refresh() })
  }

  function applyPollRate(hz) {
    hz = parseInt(hz)
    root.currentPollRate = hz
    Quickshell.execDetached([root.scriptPath, "set-poll-rate", String(hz)])
    Qt.callLater(function() { root.refresh() })
  }

  function applyBrightness(val) {
    val = Math.max(0, Math.min(100, Math.round(val)))
    root.currentBrightness = val
    Quickshell.execDetached([root.scriptPath, "set-brightness", String(val)])
    Qt.callLater(function() { root.refresh() })
  }

  function applyEffect(eff, color) {
    root.currentEffect = eff
    if (color) root.currentEffectColor = color
    Quickshell.execDetached([root.scriptPath, "set-effect", eff, "--color", root.currentEffectColor])
    Qt.callLater(function() { root.refresh() })
  }

  function switchProfile(target) {
    Quickshell.execDetached([root.scriptPath, "profile", "switch", String(target)])
    Qt.callLater(function() { root.refresh() })
  }

  function saveToOnboard(slot) {
    Quickshell.execDetached([root.scriptPath, "profile", "save", "--slot", String(slot)])
    Qt.callLater(function() { root.refresh() })
  }

  function runSetupPermissions() {
    Quickshell.execDetached([
      "omarchy-launch-floating-terminal-with-presentation",
      Qt.resolvedUrl(".").toString().replace("file://", "") + "/setup.sh"
    ])
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function dpi(val: string): void { root.applyDpi(parseInt(val)) }
    function stage(val: string): void { root.applyStage(parseInt(val)) }
    function poll(val: string): void { root.applyPollRate(parseInt(val)) }
    function profile(val: string): void { root.switchProfile(val) }
    function brightness(val: string): void { root.applyBrightness(parseInt(val)) }
  }

  IpcHandler {
    target: "oma.razercontrol"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function dpi(val: string): void { root.applyDpi(parseInt(val)) }
    function stage(val: string): void { root.applyStage(parseInt(val)) }
    function poll(val: string): void { root.applyPollRate(parseInt(val)) }
    function profile(val: string): void { root.switchProfile(val) }
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
        root.supports8k = state.supports_8k
        root.hasPermission = state.has_permission
        root.activeProfileId = state.activeProfile
        root.activeProfileName = state.activeProfileName
        root.currentOnboardSlot = state.onboardSlot
        root.currentDpi = state.dpi
        root.currentDpiStages = state.dpi_stages
        root.currentActiveStage = state.active_stage
        root.currentPollRate = state.poll_rate
        root.currentBrightness = state.brightness
        root.currentEffect = state.effect
        root.currentEffectColor = state.effect_color
        root.allProfiles = state.profiles

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
        return "󰍽 " + root.currentDpi
      }
      return "󰍽"
    }
    slotSize: Style.bar.iconSlot * (root.showDpiInBar && root.deviceConnected && !vertical ? 2.0 : 1.0)
    tooltipText: root.deviceName + (root.deviceConnected ? (" (" + root.currentDpi + " DPI @ " + root.currentPollRate + " Hz)") : " (desconectado)")
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

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
        anchors.fill: parent
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
            meta: root.deviceConnected ? (root.currentDpi + " DPI • " + Model.pollRateLabel(root.currentPollRate)) : "Dispositivo no detectado"
            detail: root.deviceConnected ? (root.hasPermission ? "Comunicación HID activa • Memoria On-Board" : "Requiere permisos udev") : "Conecta tu ratón Razer por USB"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.deviceConnected ? 1.0 : 0.4

            iconComponent: Component {
              Text {
                text: "󰍽"
                color: root.deviceConnected ? (root.currentEffectColor || Color.accent) : Qt.darker(root.foreground, 1.5)
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
            radius: Style.space(8)
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
                  text: "Permisos udev requeridos"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: "#FFAAAA"
                }
                Text {
                  text: "Para aplicar cambios de hardware al ratón, instala la regla de acceso de usuario."
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
                radius: height / 2
                color: fixMouse.containsMouse ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                Text {
                  id: fixText
                  anchors.centerIn: parent
                  text: "Activar"
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

          // 2. Perfiles en Memoria On-Board (Slots 1 a 5)
          Column {
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              PanelSectionHeader {
                text: "PERFILES EN MEMORIA (ON-BOARD)"
                foreground: root.foreground
              }
              Item {
                Layout.fillWidth: true
                height: 1
              }
              Rectangle {
                id: burnBtn
                implicitWidth: burnRow.implicitWidth + Style.space(12)
                implicitHeight: Style.space(22)
                radius: height / 2
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
                    text: "Guardar en ratón"
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

            // Barra de ranuras de perfiles 1 a 5 con código de color
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [1, 2, 3, 4, 5]
                Rectangle {
                  id: profBtn
                  Layout.fillWidth: true
                  implicitHeight: Style.space(38)
                  radius: Style.space(6)
                  readonly property int slotNum: modelData
                  readonly property bool isSelected: root.currentOnboardSlot === slotNum
                  readonly property color badgeCol: Model.badgeColorForSlot(slotNum)

                  color: isSelected ? Qt.rgba(badgeCol.r, badgeCol.g, badgeCol.b, 0.22) : (profMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03))
                  border.color: isSelected ? badgeCol : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  border.width: isSelected ? 2 : 1

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: width / 2
                      color: profBtn.badgeCol
                    }

                    Text {
                      text: "P" + profBtn.slotNum
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: profBtn.isSelected
                      color: profBtn.isSelected ? root.foreground : Qt.darker(root.foreground, 1.3)
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
                text: "SENSIBILIDAD (DPI)"
                foreground: root.foreground
              }
              Item {
                Layout.fillWidth: true
                height: 1
              }
              Text {
                id: dpiValText
                text: root.currentDpi + " DPI (Etapa " + root.currentActiveStage + "/5)"
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
                  radius: Style.space(6)
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
              maximum: 20000
              step: 50
              integer: true
              value: root.currentDpi
              onMoved: function(v) { root.currentDpi = Math.round(v) }
              onReleased: function(v) { root.applyDpi(Math.round(v)) }
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
                text: "TASA DE SONDEO (POLLING RATE)"
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
                text: "ILUMINACIÓN CHROMA RGB"
                foreground: root.foreground
              }
              Item {
                Layout.fillWidth: true
                height: 1
              }
              Text {
                id: brightValText
                text: root.currentBrightness + "%"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Color.accent
                font.bold: true
              }
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
            }

            // Efectos
            ButtonGroup {
              options: [
                { value: "spectrum", label: "Espectro" },
                { value: "static", label: "Estático" },
                { value: "breathing", label: "Respiración" },
                { value: "off", label: "Off" }
              ]
              value: root.currentEffect
              fontFamily: root.fontFamily
              foreground: root.foreground
              onChanged: function(val) { root.applyEffect(val, root.currentEffectColor) }
            }

            // Paleta de colores rápidos (visible para estático y respiración)
            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              visible: root.currentEffect === "static" || root.currentEffect === "breathing"

              Repeater {
                model: ["#00FF66", "#00FFFF", "#0088FF", "#8800FF", "#FF0055", "#FFFFFF"]
                Rectangle {
                  id: colorSwatch
                  Layout.fillWidth: true
                  implicitHeight: Style.space(24)
                  radius: Style.space(4)
                  readonly property string swatchHex: modelData
                  readonly property bool isSelected: root.currentEffectColor.toUpperCase() === swatchHex.toUpperCase()

                  color: swatchHex
                  border.color: isSelected ? root.foreground : "transparent"
                  border.width: isSelected ? 2 : 0

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyEffect(root.currentEffect, colorSwatch.swatchHex)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
