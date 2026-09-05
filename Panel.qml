import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.andreasdellrud.gamedacctl"
  ipcTarget: "io.github.andreasdellrud.gamedacctl"
  manageIpc: false

  property string deviceState: "unknown"
  property string deviceMessage: "Open to check the controller"
  property var profiles: []
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool actionRunning: false
  property bool lightingEnabled: true
  property string actionKind: ""
  property string actionMessage: ""
  property string pendingStatusOutput: ""
  property string pendingStatusError: ""
  property string pendingActionError: ""

  readonly property bool ready: deviceState === "ready"
  readonly property color dimForeground: Qt.darker(root.bar.foreground, 1.45)
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") !== ""
    ? Quickshell.env("XDG_CONFIG_HOME")
    : Quickshell.env("HOME") + "/.config"

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateStatus(raw) {
    try {
      var response = JSON.parse(String(raw || ""))
      if (Number(response.schema_version) !== 1 || !response.device || !Array.isArray(response.profiles))
        throw new Error("unsupported response")

      deviceState = String(response.device.state || "error")
      deviceMessage = String(response.device.message || "Controller returned no status")
      lightingEnabled = response.lighting_enabled !== false
      profiles = response.profiles
      var activeIndex = profiles.findIndex(function(profile) { return profile.selected === true })
      selectedIndex = activeIndex >= 0 ? activeIndex : 0
    } catch (error) {
      deviceState = "controller-error"
      deviceMessage = "Could not understand gamedacctl status"
      profiles = []
    }
  }

  function selectByDelta(delta) {
    if (profiles.length === 0) return
    selectedIndex = ((selectedIndex + delta) % profiles.length + profiles.length) % profiles.length
  }

  function applyProfile(name) {
    if (actionProc.running || String(name || "") === "") return
    actionMessage = "Applying " + name + "…"
    actionKind = "profile"
    pendingActionError = ""
    actionProc.command = ["gamedacctl", "profile", "apply", String(name), "--json"]
    actionProc.running = true
  }

  function setLighting(enabled) {
    if (actionProc.running) return
    actionMessage = enabled ? "Restoring selected profile…" : "Turning lighting off…"
    actionKind = enabled ? "lighting-on" : "lighting-off"
    pendingActionError = ""
    actionProc.command = ["gamedacctl", "profile", "lighting", enabled ? "on" : "off", "--json"]
    actionProc.running = true
  }

  function activateSelectedProfile() {
    if (selectedIndex < 0 || selectedIndex >= profiles.length) return
    applyProfile(profiles[selectedIndex].name)
  }

  function launchController() {
    Quickshell.execDetached(["gamedacctl-gui"])
    root.close()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      refresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProc
    command: ["gamedacctl", "status", "--json"]
    onStarted: {
      root.pendingStatusOutput = ""
      root.pendingStatusError = ""
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pendingStatusOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pendingStatusError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingStatusOutput !== "") {
        root.updateStatus(root.pendingStatusOutput)
      } else {
        root.deviceState = "controller-error"
        root.deviceMessage = root.pendingStatusError !== ""
          ? root.pendingStatusError
          : "gamedacctl is unavailable"
        root.profiles = []
      }
    }
  }

  Process {
    id: actionProc
    onStarted: {
      root.actionRunning = true
      root.pendingActionError = ""
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pendingActionError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.actionRunning = false
      root.actionMessage = exitCode === 0
        ? (root.actionKind === "lighting-off"
            ? "Lighting turned off"
            : (root.actionKind === "lighting-on" ? "Selected profile restored" : "Profile applied"))
        : (root.pendingActionError !== "" ? root.pendingActionError : "Could not apply profile")
      root.refresh()
    }
  }

  // ProfileStore writes atomically, so reload the FileView after each change
  // to follow the replacement inode. The short debounce coalesces a burst into
  // one status query; it is event-driven and does not poll while idle.
  FileView {
    path: root.configHome + "/gamedacctl/profiles.json"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      profileRefreshDebounce.restart()
    }
  }

  Timer {
    id: profileRefreshDebounce
    interval: 100
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function apply(profileName: string): string { root.applyProfile(profileName); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋋"
    active: root.ready
    tooltipText: "GameDAC Controls"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchController()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.cursorActive = true
        root.selectByDelta(dy !== 0 ? dy : dx)
      }
      onActivateRequested: root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(keyText) {
        if (keyText === "r" || keyText === "R") root.refresh()
        if (keyText === "o" || keyText === "O") root.launchController()
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(panelTitle.implicitHeight, lightingSwitch.implicitHeight)

          Text {
            id: panelTitle
            anchors.left: parent.left
            anchors.right: lightingSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Original GameDAC"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Rectangle {
            id: lightingSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(42)
            height: Style.space(24)
            radius: height / 2
            color: root.lightingEnabled ? Color.accent : Qt.darker(root.bar.background, 1.35)
            border.width: 1
            border.color: root.lightingEnabled ? Color.accent : root.dimForeground
            enabled: root.ready && !root.actionRunning
            opacity: enabled ? 1.0 : 0.5
            Accessible.name: "Headset lighting"
            Accessible.description: root.lightingEnabled ? "Lighting is on" : "Lighting is off"
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.lightingEnabled

            Rectangle {
              width: Style.space(18)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              x: root.lightingEnabled
                ? parent.width - width - Style.space(3)
                : Style.space(3)
              color: root.lightingEnabled ? "white" : root.dimForeground

              Behavior on x {
                NumberAnimation { duration: 120 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setLighting(!root.lightingEnabled)
            }
          }
        }

        Text {
          text: root.deviceMessage
          color: root.dimForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          width: parent.width
        }

        Text {
          visible: root.profiles.length === 0
          text: root.profiles.length === 0
            ? "No saved profiles"
            : String(root.profiles.length) + " saved profile" + (root.profiles.length === 1 ? "" : "s")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.profiles

          Button {
            required property var modelData
            required property int index
            width: content.width
            text: String(modelData.name)
            iconText: String(modelData.icon || "") !== ""
              ? String(modelData.icon)
              : (String(modelData.effect) === "breathe"
                  || String(modelData.effect) === "multi-color-breathe"
                ? "󰖙"
                : "󰏘")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            active: modelData.selected === true
            enabled: root.ready && !root.actionRunning
            hasCursor: root.cursorActive && root.selectedIndex === index
            onClicked: root.applyProfile(modelData.name)
            onHovered: function(hovered) {
              if (hovered) {
                root.cursorActive = true
                root.selectedIndex = index
              }
            }
          }
        }

        Text {
          visible: root.actionMessage !== ""
          text: root.actionMessage
          color: root.dimForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          width: parent.width
        }
      }
    }
  }
}
