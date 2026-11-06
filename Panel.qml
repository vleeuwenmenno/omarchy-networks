import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import Quickshell.Io
import "components"
import "sections"
import "model/Network.js" as Network
import "model/Tools.js" as Tools
import "model/Demo.js" as Demo

// Bar button plus a panel split into sections. The panel owns only what is
// shared: the hero, the tab row, the cursor, and keys. Everything a section
// shows lives in sections/, and each section talks to its own controller:
//
//   Network  -> NetworkController   (links, addressing, traffic)
//   VPN      -> NetworksController  (NetworkManager, Mullvad, WireGuard)
//   NetBird  -> NetworksController  (the same controller; its own concepts)
//
// A new feature is a new section file and one entry in `sections` below.
Panel {
  id: root
  moduleName: "io.github.vleeuwenmenno.networks"
  ipcTarget: "io.github.vleeuwenmenno.networks"

  // The bar sizes the slot from these; without them the widget is 0x0.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string currentId: "network"
  property int cursor: 0
  property bool cursorActive: false
  // Open dropdowns, key -> true. Everything starts folded so the panel stays
  // short enough to never need scrolling.
  property var expanded: ({})

  function toggleGroup(key) {
    var next = {}
    for (var k in expanded) next[k] = expanded[k]
    if (next[key]) delete next[key]
    else next[key] = true
    expanded = next
  }

  readonly property QtObject theme: QtObject {
    readonly property color foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
    readonly property color urgent: root.bar ? root.bar.urgent : Commons.Color.urgent
    readonly property color background: Commons.Color.popups.background
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    readonly property color hoverFill: root.bar ? Style.hoverFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
    readonly property color selectedFill: root.bar ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
    // Nerd Font glyphs.
    readonly property var glyphs: ({
      wireguard: "",
      vpn: "",
      mesh: "",
      mullvad: "",
      exit: "\uf0ac",
      wifi: "\uf1eb",
      ethernet: String.fromCodePoint(0xF0200),
      wifiOff: String.fromCodePoint(0xF092E),
      offline: String.fromCodePoint(0xF0C9B),
      eye: String.fromCodePoint(0xF0208),
      eyeOff: String.fromCodePoint(0xF0209),
      gear: "\uf013",
      back: "\uf053",
      trash: "\uf1f8",
      check: "\uf00c",
      refresh: "\uf021",
      key: "\uf084",
      qr: "\uf029",
      speed: "\uf0e4",
      close: "\uf00d"
    })
  }

  // ---- Sections ----------------------------------------------------------

  function vpnTunnels() {
    return vpnState.view.filter(function(t) { return t.kind !== "mesh" && t.backend !== "mullvad" })
  }
  function mullvadTunnel() {
    var l = vpnState.view.filter(function(t) { return t.backend === "mullvad" })
    return l.length > 0 ? l[0] : null
  }
  function meshTunnel(backend) {
    var l = vpnState.view.filter(function(t) { return t.backend === backend })
    return l.length > 0 ? l[0] : null
  }

  // What each optional tab has to show right now.
  readonly property var tabContent: ({
    vpn: vpnTunnels().length > 0,
    mullvad: mullvadTunnel() !== null,
    netbird: meshTunnel("netbird") !== null,
    tailscale: meshTunnel("tailscale") !== null
  })

  // Tabs follow the settings: shown when there is something (auto), always
  // (show, with install help while empty), or never (hide).
  readonly property var sections: {
    var modes = activeStore.get("tabs", {})
    var out = [{ id: "network", label: "Network", badge: "", component: networkSection }]

    function add(id, label, badge, urgent, real) {
      if (!Tools.tabVisible(Tools.tabMode(modes, id), tabContent[id])) return
      out.push({ id: id, label: label, badge: tabContent[id] ? badge : "", badgeUrgent: urgent,
                 component: tabContent[id] ? real : installSection })
    }

    var vpn = vpnTunnels()
    var up = vpn.filter(function(t) { return t.up }).length
    add("vpn", "VPN", up > 0 ? String(up) : "", vpnState.warning !== "", vpnSection)
    var mv = mullvadTunnel()
    add("mullvad", "Mullvad", mv && mv.up ? "on" : "", false, mullvadSection)
    var nb = meshTunnel("netbird")
    add("netbird", "NetBird", nb && nb.up ? "on" : "", false, netbirdSection)
    var ts = meshTunnel("tailscale")
    add("tailscale", "Tailscale", ts && ts.up ? "on" : "", false, tailscaleSection)
    return out
  }

  // The settings screen takes the place of whichever tab was showing.
  property bool settingsOpen: false

  function toggleSettings() {
    settingsOpen = !settingsOpen
    cursor = 0
    cursorActive = false
  }

  readonly property var currentSection: {
    if (settingsOpen) return { id: "settings", component: settingsSection }
    for (var i = 0; i < sections.length; i++) if (sections[i].id === currentId) return sections[i]
    return sections[0]
  }

  readonly property int rowCount: host.item ? host.item.rowCount : 0
  onRowCountChanged: clampCursor()
  onOpenedChanged: {
    if (!opened) return
    cursor = 0
    cursorActive = false
  }

  function clampCursor() {
    cursor = rowCount === 0 ? 0 : Math.max(0, Math.min(cursor, rowCount - 1))
  }

  function selectSection(id) {
    if (id === currentId) return
    currentId = id
    cursor = 0
    cursorActive = false
  }

  function stepSection(delta) {
    var idx = 0
    for (var i = 0; i < sections.length; i++) if (sections[i].id === currentSection.id) idx = i
    if (settingsOpen) return
    var next = Math.max(0, Math.min(idx + delta, sections.length - 1))
    selectSection(sections[next].id)
  }

  function ensureVisible() {
    if (!host.item || !cursorActive) return
    var g = host.item.cursorGeometry()
    if (!g) return
    var top = host.y + g.y
    var bottom = top + g.h
    if (top < flick.contentY) flick.contentY = top
    else if (bottom > flick.contentY + flick.height) flick.contentY = bottom - flick.height
  }
  onCursorChanged: Qt.callLater(ensureVisible)

  readonly property string metaText: {
    var parts = []
    if (netState.primary !== "") parts.push(netState.primary)
    if (vpnState.upCount > 0) parts.push(vpnState.upCount + (vpnState.upCount === 1 ? " tunnel" : " tunnels"))
    return parts.length > 0 ? parts.join(" · ") : (netState.loaded ? "Offline" : "Checking")
  }

  // The link carrying traffic: what the bar icon is about.
  readonly property var primaryLink: {
    var all = netState.wired.concat(netState.wireless)
    for (var i = 0; i < all.length; i++) if (all[i].device === netState.primary && all[i].connected) return all[i]
    return null
  }
  readonly property bool primaryIsWifi: primaryLink !== null && primaryLink.ap !== null
  readonly property string barGlyph: primaryLink === null ? theme.glyphs.offline
    : (primaryIsWifi ? theme.glyphs.wifi : theme.glyphs.ethernet)
  // "4", "5", "6", "6E", "7": which Wi-Fi generation this connection is.
  readonly property string barGeneration: primaryIsWifi && primaryLink.wifi ? primaryLink.wifi.short : ""

  readonly property string tooltip: {
    var lines = []
    var l = primaryLink
    if (l === null) lines.push("Offline")
    else if (primaryIsWifi) {
      var w = [l.connection]
      if (l.wifi && l.wifi.label !== "") w.push(l.wifi.label)
      if (l.ap && l.ap.band !== "") w.push(l.ap.band)
      lines.push(w.join(" · "))
    } else {
      lines.push("Ethernet" + (l.speed > 0 ? " · " + Network.formatSpeed(l.speed) : ""))
    }
    if (wifiState.connecting) lines.unshift("Connecting to " + wifiState.attemptSsid + "…")
    else if (wifiState.attemptPhase === "failed" && wifiState.failure !== "") lines.unshift(wifiState.failure)
    var names = vpnState.view.filter(function(t) { return t.up }).map(function(t) { return t.label })
    if (names.length > 0) lines.push("VPN: " + names.join(", "))
    return lines.join("\n")
  }

  // ---- State -------------------------------------------------------------

  NetworksController {
    id: vpnState
    demo: root.demo
    settings: root.settings
  }

  StateStore {
    id: stateStore
  }

  // Demo mode (for screenshots): a flag file turns it on, and everything the
  // widget shows then comes from model/Demo.js. Settings live in memory.
  StateStore {
    id: demoFlag
    name: "menno-networks-demo.json"
  }

  StateStore {
    id: demoStore
    persist: false
  }

  readonly property bool demo: demoFlag.get("demo", false) === true
  readonly property var activeStore: demo ? demoStore : stateStore
  onDemoChanged: if (demo) demoStore.data = Demo.STORE

  // Development hooks, for the screenshots in the README: pick what is on
  // screen, then save the panel to a PNG. Harmless otherwise.
  IpcHandler {
    target: root.ipcTarget + ".dev"
    function view(tab: string, open: string, page: string): string {
      root.settingsOpen = tab === "settings"
      if (tab !== "settings") root.currentId = tab
      var map = {}
      if (open === "-") open = ""
      if (page === "-") page = ""
      open.split(",").forEach(function(k) { if (k !== "") map[k] = true })
      root.expanded = map
      root.cursor = 0
      root.cursorActive = false
      if (host.item && typeof host.item.devPage === "function") host.item.devPage(page)
      return "ok"
    }
    function snapshot(path: string): string {
      keyCatcher.parent.parent.grabToImage(function(result) { result.saveToFile(path) })
      return "ok"
    }
  }

  WifiController {
    id: wifiState
    demo: root.demo
  }

  SpeedTestController {
    id: speedState
    demo: root.demo
  }

  NetworkController {
    id: netState
    demo: root.demo
    settings: root.settings
    // One-second sampling only while the numbers are on screen.
    statsActive: root.opened && root.currentSection.id === "network"
  }

  Component {
    id: networkSection
    NetworkSection {
      theme: root.theme
      general: netState
      wifi: wifiState
      speed: speedState
      store: activeStore
      panelOpen: root.opened
      cursor: root.cursor
      cursorActive: root.cursorActive
      expanded: root.expanded
      onGroupToggled: function(key) { root.toggleGroup(key) }
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  Component {
    id: vpnSection
    VpnSection {
      theme: root.theme
      panelOpen: root.opened
      vpn: vpnState
      cursor: root.cursor
      cursorActive: root.cursorActive
      expanded: root.expanded
      onGroupToggled: function(key) { root.toggleGroup(key) }
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  Component {
    id: mullvadSection
    MullvadSection {
      theme: root.theme
      store: activeStore
      panelOpen: root.opened
      vpn: vpnState
      cursor: root.cursor
      cursorActive: root.cursorActive
      expanded: root.expanded
      onGroupToggled: function(key) { root.toggleGroup(key) }
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  Component {
    id: settingsSection
    SettingsSection {
      theme: root.theme
      panelOpen: root.opened
      vpn: vpnState
      general: netState
      store: activeStore
      hasContent: root.tabContent
      cursor: root.cursor
      cursorActive: root.cursorActive
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  Component {
    id: installSection
    InstallSection {
      theme: root.theme
      panelOpen: root.opened
      vpn: vpnState
      tabId: root.currentSection.id
      cursor: root.cursor
      cursorActive: root.cursorActive
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  // NetBird and Tailscale are one section with two instances.
  Component {
    id: netbirdSection
    MeshSection {
      backend: "netbird"
      theme: root.theme
      panelOpen: root.opened
      vpn: vpnState
      cursor: root.cursor
      cursorActive: root.cursorActive
      expanded: root.expanded
      onGroupToggled: function(key) { root.toggleGroup(key) }
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  Component {
    id: tailscaleSection
    MeshSection {
      backend: "tailscale"
      theme: root.theme
      panelOpen: root.opened
      vpn: vpnState
      cursor: root.cursor
      cursorActive: root.cursorActive
      expanded: root.expanded
      onGroupToggled: function(key) { root.toggleGroup(key) }
      onCursorRequested: function(o) { root.cursorActive = true; root.cursor = o }
      onCloseRequested: root.close()
    }
  }

  // ---- Bar button --------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip
    iconComponent: Component {
      Item {
        readonly property color ink: root.primaryLink !== null ? root.barForeground : Qt.darker(root.barForeground, 1.55)

        // Connection type: wired, Wi-Fi, or offline.
        Text {
          anchors.centerIn: parent
          // Leave room on the right for the generation number.
          anchors.horizontalCenterOffset: root.barGeneration !== "" ? -Style.space(5) : 0
          text: root.barGlyph
          color: parent.ink
          font.family: root.theme.fontFamily
          font.pixelSize: Style.bar.iconFont
        }

        // Wi-Fi generation, tucked into the corner: 4, 5, 6, 6E, 7.
        Text {
          visible: root.barGeneration !== ""
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(8)
          anchors.topMargin: -Style.space(2)
          text: root.barGeneration
          color: parent.ink
          font.family: root.theme.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // Joining a Wi-Fi network: keeps turning after the panel is closed.
        Spinner {
          running: wifiState.connecting
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.leftMargin: -Style.space(4)
          anchors.bottomMargin: -Style.space(3)
          size: Style.space(9)
          thickness: 1.5
          color: parent.ink
        }

        // A VPN is up.
        Rectangle {
          visible: vpnState.anyUp
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          width: Style.space(6)
          height: width
          radius: width / 2
          color: vpnState.warning !== "" ? root.theme.urgent : parent.ink
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) { vpnState.refresh(); netState.refresh() }
      else root.toggle()
    }
  }

  // ---- Panel -------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // A text field has focus: it owns every key until Enter or Esc.
      blocked: host.item ? host.item.editing : false
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) { root.stepSection(dx); return }
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursor = Math.max(0, Math.min(root.cursor + dy, root.rowCount - 1))
      }
      onActivateRequested: if (root.cursorActive && host.item) host.item.activateCursor()
      onCloseRequested: {
        // Esc steps back one level: a sub-page, then settings, then the panel.
        if (host.item && host.item.hasSubPage) host.item.backRequested()
        else if (root.settingsOpen) root.toggleSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (host.item) host.item.textKey(t)
        if (host.item && host.item.hasSubPage) return
        if (t === "s" || t === "S") { root.toggleSettings(); return }
        if (t === "r" || t === "R") { vpnState.refresh(); netState.refresh() }
        else if (!root.settingsOpen && t >= "1" && t <= "9") {
          var s = root.sections[Number(t) - 1]
          if (s) root.selectSection(s.id)
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: root.settingsOpen ? "Settings" : "Networks"
            meta: root.settingsOpen ? "Tabs and adapters" : root.metaText
            foreground: root.theme.foreground
            fontFamily: root.theme.fontFamily
            iconOpacity: netState.primary !== "" || vpnState.anyUp ? 1.0 : 0.5
            trailingControl: Component {
              Item {
                implicitWidth: Style.space(30)
                implicitHeight: Style.space(30)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: cogMouse.containsMouse ? root.theme.hoverFill : "transparent"
                  border.width: cogMouse.containsMouse ? 1 : 0
                  border.color: root.theme.dim
                }

                Text {
                  anchors.centerIn: parent
                  text: root.settingsOpen ? root.theme.glyphs.close : root.theme.glyphs.gear
                  color: root.settingsOpen ? root.theme.foreground : root.theme.dim
                  font.family: root.theme.fontFamily
                  font.pixelSize: Style.font.heading
                }

                MouseArea {
                  id: cogMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSettings()
                }
              }
            }
            iconComponent: Component {
              Text {
                text: ""
                color: root.theme.foreground
                font.family: root.theme.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          SectionTabs {
            visible: !root.settingsOpen
            theme: root.theme
            sections: root.sections
            currentId: root.currentSection.id
            onSelected: function(sectionId) { root.selectSection(sectionId) }
          }

          Loader {
            id: host
            width: parent.width
            sourceComponent: root.currentSection.component
          }
        }
      }
    }
  }
}
