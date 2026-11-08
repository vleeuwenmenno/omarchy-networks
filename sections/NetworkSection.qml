import QtQuick
import Quickshell
import "../model/Network.js" as Network
import "../model/IpConfig.js" as IpConfig
import "../model/Wifi.js" as Wifi
import "../model/Tools.js" as Tools

// Wired and wireless links. Overview first: status, addressing, live traffic,
// an on/off switch per link. Two sub-pages hang off it:
//
//   wifi      pick a network (and forget saved ones)
//   connect   passphrase prompt for the network just picked
//   settings  DHCP or static IPv4 for a link
//
// Pages that hold text fields never read live link state. Their items would
// rebuild on every poll and take the keyboard focus with them, so they work
// from a snapshot taken when the page opened.
SectionBase {
  id: root

  required property var general
  required property var wifi
  required property var speed
  required property var store

  property string page: ""
  hasSubPage: page !== ""

  // connect page
  property string connectSsid: ""
  property bool connectEnterprise: false
  property bool pinNotice: false
  property string connectSecurity: ""
  property string connectError: ""
  property string serverError: ""
  property string caError: ""
  property var secrets: ({})            // typed text; mutated in place, never bound

  // DNS (overview)
  property bool dnsCustom: false
  property string dnsFieldError: ""
  property var dns: ({ servers: "" })   // typed text; mutated in place, never bound

  // hidden-network page
  property string hiddenSecurity: "wpa-psk"
  property string hiddenError: ""
  property var hidden: ({})             // typed text; mutated in place, never bound

  // settings page
  property var pageLink: null
  property bool formLoaded: false
  property string formMethod: "auto"
  property var formErrors: ({})
  property var form: ({})               // typed text; mutated in place, never bound

  readonly property int visibleNetworks: 7

  function stripPrefix(addr) { return String(addr || "").replace(/\/\d+$/, "") }

  function go(next) {
    page = next
    if (next !== "connect") pinNotice = false
    // Keep scanning on the password form: the join needs the access point in view.
    wifi.scanning = next === "wifi" || next === "connect"
    root.cursorRequested(0)
  }

  // ---- Overview ----------------------------------------------------------

  // Links start compact: a header with a one-line summary. The choice is
  // remembered between sessions, per interface.
  function linkOpen(device) {
    var map = store.get("linkOpen", {})
    return map[device] === true
  }

  function toggleLinkOpen(device) {
    var map = {}
    var cur = store.get("linkOpen", {})
    for (var k in cur) map[k] = cur[k]
    if (map[device]) delete map[device]
    else map[device] = true
    store.set("linkOpen", map)
  }

  function compactSummary(link, wireless) {
    if (!link.connected) return "Not connected"
    var parts = []
    if (wireless) {
      if (link.connection !== "") parts.push(link.connection)
      if (link.ap) parts.push(link.ap.signal + "%")
      if (link.wifi && link.wifi.label !== "") parts.push(link.wifi.label)
    } else {
      if (link.primary) parts.push("Default route")
      if (link.speed > 0) parts.push(Network.formatSpeed(link.speed))
    }
    if (link.ip4.length > 0) parts.push(stripPrefix(link.ip4[0]))
    return parts.join(" · ")
  }

  function linkEnabled(link, wireless) {
    if (wireless) return wifi.radioOn
    var pending = general.pendingLinks[link.device]
    return pending === undefined ? link.connected : pending
  }

  function linkItems(link, wireless) {
    return tagged(buildLink(link, wireless), link.device)
  }

  function tagged(list, device) {
    list.forEach(function(item) { if (item.device === undefined) item.device = device })
    return list
  }

  function buildLink(link, wireless) {
    var out = []
    var key = "net." + link.device
    var on = linkEnabled(link, wireless)
    var open = linkOpen(link.device)
    var pending = !wireless && general.pendingLinks[link.device] !== undefined

    out.push({
      // Clicking the row folds it; the switch alone turns the link on or off.
      type: "toggle", action: "link-collapse", link: link, wireless: wireless,
      switchClickable: true, switchAction: "link", neutral: true,
      glyph: wireless ? theme.glyphs.wifi : theme.glyphs.ethernet,
      title: (wireless ? "Wi-Fi" : "Wired") + " · " + link.device,
      detail: !on ? "Off" : (open ? (link.connected ? (link.primary ? "Default route" : "") : "Not connected") : compactSummary(link, wireless)),
      checked: on, busy: pending,
      secondary: on ? (open ? "\uf078" : "\uf054") : "", secondaryAction: "link-collapse"
    })
    if (!on || !open) return out

    out.push({
      type: "info", label: "Status", bad: !link.connected,
      value: link.connected ? (link.connection !== "" ? link.connection : "Connected") : "Disconnected"
    })

    if (link.connected) {
      if (link.ap) {
        out.push({ type: "info", label: "Signal", value: link.ap.signal + "% · " + Network.signalLabel(link.ap.signal) })
        var parts = []
        if (link.wifi && link.wifi.label !== "") parts.push(link.wifi.label)
        if (link.ap.band !== "") parts.push(link.ap.band)
        if (link.ap.rate !== "") parts.push(link.ap.rate)
        if (parts.length > 0) out.push({ type: "info", label: "Link", value: parts.join(" · ") })
      } else if (link.speed > 0) {
        out.push({ type: "info", label: "Link speed", value: Network.formatSpeed(link.speed) })
      }
      if (link.ip4.length > 0)
        out.push({ type: "info", label: "IPv4", value: link.ip4.join(", "), copy: stripPrefix(link.ip4[0]) })
      var rate = general.rates[link.device]
      out.push({
        type: "info", label: "Traffic",
        value: "↓ " + Network.formatRate(rate ? rate.rx : 0) + "   ↑ " + Network.formatRate(rate ? rate.tx : 0)
      })
    }

    if (wireless)
      out.push({ type: "button", action: "wifi-page", glyph: theme.glyphs.wifi, title: "Wi-Fi networks" })
    out.push({ type: "button", action: "settings", link: link, glyph: theme.glyphs.gear, title: "IP settings",
               detail: "" })
    // The test measures whichever link carries your traffic.
    if (link.primary && link.connected)
      out.push({ type: "button", action: "speed", glyph: theme.glyphs.speed, title: "Speed test" })

    if (!link.connected) return out

    out.push({ type: "group", key: key + ".details", text: "Details", summary: link.gateway !== "" ? "gateway " + link.gateway : "" })
    if (isOpen(key + ".details")) {
      if (link.ap) {
        // Pin the band: stay on 5 GHz instead of drifting to 2.4, say.
        var bands = general.band.available
        if (bands.length > 1) {
          var opts = [{ id: "auto", label: "Auto" }]
          bands.forEach(function(b) { opts.push({ id: b, label: Network.bandLabel(b) }) })
          out.push({ type: "choice", key: "band", label: "Band", options: opts, value: general.band.selected })
          if (general.bandPending !== "") out.push({ type: "status", text: "Switching band…" })
        }
        if (link.ap.channel) out.push({ type: "info", label: "Channel", value: String(link.ap.channel) })
        if (link.ap.security !== "") out.push({ type: "info", label: "Security", value: link.ap.security })
      }
      if (link.ip6.length > 0)
        out.push({ type: "info", label: "IPv6", value: link.ip6[0], copy: stripPrefix(link.ip6[0]) })
      if (link.gateway !== "")
        out.push({ type: "info", label: "Gateway", value: link.gateway, copy: link.gateway })
      if (link.dns.length > 0)
        out.push({ type: "info", label: "DNS", value: link.dns.join(", "), copy: link.dns[0] })
      if (link.hwaddr !== "")
        out.push({ type: "info", label: "MAC", value: link.hwaddr, copy: link.hwaddr })
      // Sharing a network: the password itself, or a code a phone can scan.
      // Enterprise networks have neither; the helper says so if you try.
      if (link.ap) {
        out.push({
          type: "button", action: "wifi-password", link: link, glyph: theme.glyphs.key,
          title: general.flashKey === "wifi-password" ? "\uf00c  Copied" : "Copy Wi-Fi password",
          detail: general.flashKey === "wifi-password" ? "Clears after you paste it" : ""
        })
        out.push({ type: "button", action: "wifi-qr", link: link, glyph: theme.glyphs.qr, title: "Show QR code" })
      }
    }

    var counters = general.counters[link.device] || null
    out.push({
      type: "group", key: key + ".traffic", text: "Traffic history",
      summary: counters ? Network.formatBytes(counters.rx) + " down · " + Network.formatBytes(counters.tx) + " up" : ""
    })
    if (isOpen(key + ".traffic")) {
      var hist = general.history[link.device]
      var r = general.rates[link.device]
      out.push({
        type: "stats", rx: r ? r.rx : 0, tx: r ? r.tx : 0,
        rxHistory: hist ? hist.rx : [], txHistory: hist ? hist.tx : [], counters: counters
      })
    }
    return out
  }

  // DNS is one setting for the whole machine (Omarchy writes it for every
  // connection), so it sits below the links rather than inside one.
  function primaryDns() {
    var all = general.wired.concat(general.wireless)
    for (var i = 0; i < all.length; i++) if (all[i].device === general.primary) return all[i].dns.join(", ")
    return ""
  }

  function dnsItems() {
    var current = general.dnsProvider
    var out = [{ type: "group", key: "net.dns", text: "DNS", summary: current !== "" ? current : "" }]
    if (!isOpen("net.dns")) return out
    out.push({
      type: "choice", key: "dns", label: "Provider",
      options: [{ id: "DHCP", label: "DHCP" }, { id: "Quad9", label: "Quad9" }, { id: "OpenDNS", label: "OpenDNS" },
                { id: "Google", label: "Google" }, { id: "Custom", label: "Custom" }],
      // Anything that is not one of the buttons (Cloudflare, say) is custom
      // servers as far as this row goes; its addresses show in the field.
      value: dnsCustom || ["DHCP", "Quad9", "OpenDNS", "Google"].indexOf(current) === -1 ? "Custom" : current
    })
    if (general.dnsBusy) out.push({ type: "status", text: "Applying DNS…" })
    if (dnsCustom || ["DHCP", "Quad9", "OpenDNS", "Google"].indexOf(current) === -1) {
      out.push({
        type: "field", key: "dnsServers", label: "DNS servers",
        initial: dns.servers !== "" ? dns.servers : primaryDns(), placeholder: "1.1.1.1, 9.9.9.9", error: dnsFieldError
      })
      out.push({ type: "button", action: "dns-apply", glyph: theme.glyphs.check, title: "Apply DNS servers",
                 busy: general.dnsBusy, detail: general.dnsBusy ? "" : "Asks for your password" })
    }
    if (general.dnsError !== "") out.push({ type: "text", tone: "urgent", text: general.dnsError })
    return out
  }

  function applyCustomDns() {
    var r = IpConfig.parseDnsServers(dns.servers !== "" ? dns.servers : primaryDns())
    dnsFieldError = r.ok ? "" : r.error
    if (r.ok) general.setCustomDns(r.servers)
  }

  function overviewItems() {
    var out = []
    var hiddenAdapters = store.get("hiddenAdapters", [])
    var wired = Tools.visibleLinks(general.wired, hiddenAdapters)
    var wireless = Tools.visibleLinks(general.wireless, hiddenAdapters)
    var anyAdapter = general.wired.length + general.wireless.length > 0
    for (var i = 0; i < wired.length; i++) out = out.concat(linkItems(wired[i], false))
    for (var j = 0; j < wireless.length; j++) out = out.concat(linkItems(wireless[j], true))
    if (general.actionError !== "") out.push({ type: "text", tone: "urgent", text: general.actionError })
    if (wired.length > 0 || wireless.length > 0) out = out.concat(dnsItems())
    if (wired.length === 0 && wireless.length === 0) {
      if (!general.loaded) out.push({ type: "status", text: "Checking…" })
      else if (anyAdapter) out.push({ type: "text", text: "Every adapter is hidden. Turn some back on in settings (the cog, top right)." })
      else out.push({ type: "text", text: "No network adapters found." })
    }
    return out
  }

  // ---- Speed test ----------------------------------------------------------

  function speedItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    out.push({ type: "header", text: "Speed test" })
    var p = speed.ping
    var d = speed.down
    var u = speed.up
    out.push({ type: "info", label: "Latency", value: p && p.avg > 0 ? p.avg.toFixed(1) + " ms" : "—" })
    out.push({ type: "info", label: "Jitter", value: p && p.avg > 0 ? p.jitter.toFixed(1) + " ms" : "—" })
    out.push({ type: "info", label: "Packet loss", value: p ? p.loss + "%" : "—", bad: p !== null && p.loss > 2 })
    out.push({ type: "info", label: "Download", value: d ? Network.formatMbps(d.mbps) : "—" })
    out.push({ type: "info", label: "Upload", value: u ? Network.formatMbps(u.mbps) : "—" })
    if (speed.phase === "error") out.push({ type: "text", tone: "urgent", text: speed.error })
    var doing = { latency: "Measuring latency…", down: "Measuring download…", up: "Measuring upload…" }
    out.push({
      type: "button", action: "speed-run", glyph: theme.glyphs.speed,
      title: speed.running ? doing[speed.phase] : (speed.phase === "done" || speed.phase === "error" ? "Run again" : "Run test"),
      busy: speed.running,
      detail: speed.running ? "" : "Uses a lot of bandwidth for about 20 seconds"
    })
    return out
  }

  // ---- Share ---------------------------------------------------------------

  function qrItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    if (general.qr) {
      out.push({ type: "header", text: "Join " + general.qr.ssid })
      out.push({ type: "qr", rows: general.qr.rows })
      out.push({ type: "text", text: "Point a phone camera at the code. It contains the password, so close this when done." })
    } else if (general.qrError !== "") {
      out.push({ type: "text", tone: "urgent", text: general.qrError })
    } else {
      out.push({ type: "status", text: "Making the code…" })
    }
    return out
  }

  // ---- Wi-Fi networks ----------------------------------------------------

  function networkDetail(n) {
    var state = n.connected ? "Connected" : (n.known ? "Saved" : (n.secured ? (Wifi.securityLabel(n.security) || "Secured") : "Open"))
    return state + " · " + n.signal + "%"
  }

  function networkItem(n) {
    return {
      type: "toggle", action: "network", net: n, glyph: theme.glyphs.wifi,
      title: n.ssid, detail: networkDetail(n), checked: n.connected, busy: n.busy,
      secondary: n.known && !n.connected ? theme.glyphs.trash : "", secondaryAction: "forget"
    }
  }

  function wifiItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    if (wifi.radioOn)
      out.push({
        type: "button", action: "scan", glyph: theme.glyphs.refresh,
        title: wifi.refreshing ? "Scanning…" : "Scan for networks", busy: wifi.refreshing
      })
    out.push({ type: "header", text: "Wi-Fi networks" })
    if (!wifi.radioOn) {
      out.push({ type: "text", text: "Wi-Fi is off. Turn it on from the overview." })
      return out
    }
    if (wifi.failure !== "") out.push({ type: "text", tone: "urgent", text: wifi.failure })

    var nets = wifi.networks
    for (var i = 0; i < nets.length && i < visibleNetworks; i++) out.push(networkItem(nets[i]))
    if (nets.length > visibleNetworks) {
      out.push({ type: "group", key: "wifi.more", text: "More networks", summary: (nets.length - visibleNetworks) + " weaker" })
      if (isOpen("wifi.more"))
        for (var j = visibleNetworks; j < nets.length; j++) out.push(networkItem(nets[j]))
    }
    out.push({ type: "button", action: "hidden-page", glyph: theme.glyphs.wifi, title: "Hidden network",
               detail: "Join a network that does not show up in the list" })
    if (nets.length === 0 && !wifi.device) out.push({ type: "text", text: "No Wi-Fi adapter found." })
    else if (nets.length === 0 && !wifi.refreshing) out.push({ type: "text", text: "No networks found. Try scanning again." })
    if (nets.length > 0) out.push({ type: "text", text: "Enter connects or disconnects. f forgets a saved network." })
    return out
  }

  // ---- Hidden network ------------------------------------------------------

  function hiddenItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    out.push({ type: "header", text: "Hidden network" })
    out.push({ type: "field", key: "hiddenSsid", label: "Network name", initial: hidden.ssid || "", placeholder: "Exactly as the network spells it", error: hiddenError })
    out.push({
      type: "choice", key: "hiddenSecurity", label: "Security", value: hiddenSecurity,
      options: [{ id: "wpa-psk", label: "WPA / WPA2" }, { id: "sae", label: "WPA3" }, { id: "open", label: "Open" }]
    })
    if (hiddenSecurity !== "open")
      out.push({ type: "field", key: "hiddenPassword", label: "Passphrase", initial: hidden.password || "", password: true, submit: "hidden-connect" })
    if (wifi.connecting) out.push({ type: "status", text: "Connecting to " + (hidden.ssid || "the network") + "…" })
    else if (wifi.failure !== "") out.push({ type: "text", tone: "urgent", text: wifi.failure })
    out.push({ type: "button", action: "hidden-connect", glyph: theme.glyphs.wifi,
               title: wifi.connecting ? "Connecting…" : "Connect", busy: wifi.connecting })
    return out
  }

  function submitHidden() {
    if (wifi.connecting) return
    var ssid = hidden.ssid || ""
    if (!Wifi.validSsid(ssid)) { hiddenError = "Enter the network name (up to 32 characters)"; return }
    var pw = hidden.password || ""
    if (hiddenSecurity !== "open" && (pw.length < 8 || pw.length > 63)) { hiddenError = "The passphrase must be 8 to 63 characters"; return }
    hiddenError = ""
    wifi.connectHidden(ssid, hiddenSecurity, hiddenSecurity === "open" ? "" : pw)
  }

  // ---- Passphrase prompt -------------------------------------------------

  function connectItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    out.push({ type: "header", text: "Connect to " + connectSsid })
    if (connectEnterprise) {
      out.push({ type: "field", key: "identity", label: "Username", initial: secrets.identity || "", placeholder: "user@example.com" })
      out.push({ type: "field", key: "server", label: "Server name", initial: secrets.server || "", placeholder: "radius.example.com", error: serverError })
      out.push({ type: "field", key: "ca", label: "CA certificate (optional)", initial: secrets.ca || "", placeholder: "/path/ca.pem, blank = system CAs", error: caError })
      if (pinNotice) out.push({ type: "text", tone: "urgent", text: "The saved profile for " + connectSsid + " does not check the server's identity. Enter the details again to replace it." })
      out.push({ type: "text", text: "Enterprise Wi-Fi sends your password to the network. The server name must match its certificate, so a fake network cannot collect it." })
    }
    out.push({
      type: "field", key: "password", label: connectEnterprise ? "Password" : "Passphrase",
      initial: secrets.password || "", password: true, error: connectError, submit: "connect"
    })
    var mine = wifi.attemptSsid === connectSsid
    if (mine && wifi.attemptPhase === "connecting")
      out.push({ type: "status", text: "Connecting to " + connectSsid + ", checking the password…" })
    else if (wifi.failure !== "") out.push({ type: "text", tone: "urgent", text: wifi.failure })
    out.push({
      type: "button", action: "connect", glyph: theme.glyphs.wifi,
      title: wifi.connecting ? "Connecting…" : "Connect", busy: wifi.connecting
    })
    return out
  }

  // ---- IPv4 settings -----------------------------------------------------

  function openSettings(link) {
    pageLink = link
    form = {}
    formErrors = ({})
    formLoaded = false
    formMethod = "auto"
    go("settings")
    if (link.uuid) general.loadIpSettings(link.uuid)
  }

  function populateForm(stored) {
    var link = pageLink
    var live = link.ip4.length > 0 ? link.ip4[0] : ""
    var livePrefix = Number(live.split("/")[1]) || 24
    if (stored && stored.method === "manual") {
      form = {
        address: stored.address, netmask: IpConfig.prefixToNetmask(stored.prefix),
        gateway: stored.gateway, dns: stored.dns.join(", ")
      }
      formMethod = "manual"
    } else {
      // On DHCP the form starts from what the link has now: a sensible
      // starting point for someone switching to a fixed address.
      form = {
        address: stripPrefix(live), netmask: live !== "" ? IpConfig.prefixToNetmask(livePrefix) : "",
        gateway: link.gateway, dns: link.dns.join(", ")
      }
      formMethod = "auto"
    }
    formLoaded = true
  }

  function settingsItems() {
    var out = [{ type: "button", action: "back", glyph: theme.glyphs.back, title: "Back" }]
    out.push({ type: "header", text: "IPv4 · " + (pageLink ? pageLink.device : "") })
    if (!pageLink || pageLink.uuid === "") {
      out.push({ type: "text", text: "This link has no active connection. Connect it first, then come back." })
      return out
    }
    if (!formLoaded) {
      out.push({ type: "status", text: "Loading current settings…" })
      return out
    }
    out.push({
      type: "choice", key: "method", value: formMethod,
      options: [{ id: "auto", label: "DHCP" }, { id: "manual", label: "Static" }]
    })
    if (formMethod === "manual") {
      var e = formErrors
      out.push({ type: "field", key: "address", label: "IP address", initial: form.address || "", placeholder: "192.168.1.50", error: e.address || "" })
      out.push({ type: "field", key: "netmask", label: "Netmask", initial: form.netmask || "", placeholder: "255.255.255.0", error: e.netmask || "" })
      out.push({ type: "field", key: "gateway", label: "Default gateway", initial: form.gateway || "", placeholder: "192.168.1.1", error: e.gateway || "" })
      out.push({ type: "field", key: "dns", label: "DNS servers", initial: form.dns || "", placeholder: "1.1.1.1, 8.8.8.8", error: e.dns || "" })
    } else {
      out.push({ type: "text", text: "Address, gateway and DNS come from the router." })
    }
    if (general.actionError !== "") out.push({ type: "text", tone: "urgent", text: general.actionError })
    else if (general.actionNote !== "") out.push({ type: "text", text: general.actionNote })
    out.push({
      type: "button", action: "apply", glyph: theme.glyphs.check,
      title: general.actionBusy ? "Applying…" : "Apply", busy: general.actionBusy,
      detail: general.actionBusy ? "" : "Reconnects this link briefly"
    })
    return out
  }

  function applySettings() {
    if (general.actionBusy || !pageLink || !pageLink.uuid) return
    if (formMethod === "manual") {
      var r = IpConfig.validateStatic(form)
      formErrors = r.errors
      if (!r.ok) return
      general.applyIp(pageLink.uuid, "manual", r.value)
    } else {
      formErrors = ({})
      general.applyIp(pageLink.uuid, "auto", null)
    }
  }

  function submitConnect() {
    if (wifi.connecting) return
    var pw = secrets.password || ""
    if (!connectEnterprise && /^(Wpa|Sae)/.test(connectSecurity) && (pw.length < 8 || pw.length > 63)) {
      connectError = "Passphrase must be 8 to 63 characters"
      return
    }
    if (pw === "") { connectError = "Enter the password"; return }
    connectError = ""
    serverError = ""
    caError = ""
    if (connectEnterprise) {
      var server = String(secrets.server || "").trim()
      var ca = String(secrets.ca || "").trim()
      if (!Wifi.validServerName(server)) { serverError = "Enter the RADIUS server name, e.g. radius.example.com"; return }
      if (!Wifi.validCaPath(ca)) { caError = "Use an absolute path ending in .pem, .crt, .cer or .der"; return }
      wifi.connectEnterprise(connectSsid, secrets.identity || "", pw, server, ca)
    }
    else wifi.connectPsk(connectSsid, pw)
  }

  // ---- Wiring ------------------------------------------------------------

  // Used by the screenshot tooling to open a sub-page directly.
  function devPage(name) {
    if (name === "wifi") go("wifi")
    else if (name === "connect" || name === "connect-busy") {
      connectSsid = "Neighbour 5G"; connectEnterprise = false; connectSecurity = "Wpa2Psk"
      connectError = ""; secrets = ({ password: "hunter2hunter2" }); wifi.failure = ""
      wifi.attemptSsid = name === "connect-busy" ? "Neighbour 5G" : ""
      wifi.attemptPhase = name === "connect-busy" ? "connecting" : ""
      go("connect")
    }
    else go("")
  }

  Component.onCompleted: general.loadBand()

  onPanelOpenChanged: {
    if (panelOpen) { general.loadBand(); return }
    page = ""
    secrets = ({})
    hidden = ({})
    connectError = ""
    wifi.scanning = false
    general.clearQr()
    speed.stop()
  }

  items: page === "hidden" ? hiddenItems()
       : page === "speed" ? speedItems()
       : page === "qr" ? qrItems()
       : page === "wifi" ? wifiItems()
       : page === "connect" ? connectItems()
       : page === "settings" ? settingsItems()
       : overviewItems()

  onFieldEdited: function(key, text) {
    if (page === "connect") secrets[key] = text
    else if (page === "settings") form[key] = text
    else if (page === "hidden") hidden[key === "hiddenSsid" ? "ssid" : "password"] = text
    else if (key === "dnsServers") dns.servers = text
  }

  onChoiceSelected: function(key, optionId) {
    if (key === "band") { general.setBand(optionId); return }
    if (key === "hiddenSecurity") { hiddenSecurity = optionId; return }
    if (key === "dns") {
      if (optionId === "Custom") { dnsCustom = true; return }
      dnsCustom = false
      if (optionId === general.dnsProvider) return
      if (optionId === "Quad9" || optionId === "OpenDNS") general.setDnsPreset(optionId)
      else general.setDns(optionId)
      return
    }
    if (key === "method" && optionId !== formMethod) {
      formErrors = ({})
      formMethod = optionId
    }
  }

  onBackRequested: {
    if (page === "speed") speed.stop()
    if (page === "qr") general.clearQr()
    if (page === "connect") { secrets = ({}); connectError = ""; go("wifi") }
    else if (page === "hidden") { hidden = ({}); go("wifi") }
    else go("")
  }

  onTextKeyPressed: function(t) {
    if (page === "" && (t === "t" || t === "T")) {
      var row = itemAtCursor()
      if (row && row.link) {
        if (row.wireless) wifi.setRadio(!wifi.radioOn)
        else general.setLinkEnabled(row.link.device, !linkEnabled(row.link, false))
      }
      return
    }
    if (page === "" && (t === "c" || t === "C")) {
      var current = itemAtCursor()
      if (current && current.device) toggleLinkOpen(current.device)
      return
    }
    if (page !== "wifi" || (t !== "f" && t !== "F")) return
    var item = itemAtCursor()
    if (item && item.action === "network" && item.net.known && !item.net.connected) wifi.forget(item.net.ssid)
  }

  onItemActivated: function(item) {
    switch (item.action) {
    case "link":
      if (item.wireless) wifi.setRadio(!wifi.radioOn)
      else general.setLinkEnabled(item.link.device, !linkEnabled(item.link, false))
      break
    case "link-collapse": toggleLinkOpen(item.link.device); break
    case "wifi-page": go("wifi"); break
    case "speed": go("speed"); break
    case "dns-apply": applyCustomDns(); break
    case "hidden-page": hidden = ({}); hiddenError = ""; hiddenSecurity = "wpa-psk"; wifi.failure = ""; go("hidden"); break
    case "hidden-connect": submitHidden(); break
    case "speed-run": speed.start(); break
    case "wifi-password": general.copyWifiPassword(item.link.device); break
    case "wifi-qr": general.loadQr(item.link.device); go("qr"); break
    case "scan": wifi.rescan(); break
    case "settings": openSettings(item.link); break
    case "back": backRequested(); break
    case "apply": applySettings(); break
    case "connect": submitConnect(); break
    case "network":
      var n = item.net
      if (n.connected) wifi.disconnect(n.ssid)
      else if (n.known || !n.secured) wifi.connectKnown(n.ssid)
      else {
        connectSsid = n.ssid
        connectEnterprise = n.enterprise
        pinNotice = false
        connectSecurity = n.security
        connectError = ""
        serverError = ""
        caError = ""
        secrets = ({})
        wifi.failure = ""
        go("connect")
      }
      break
    case "forget": wifi.forget(item.net.ssid); break
    }
  }

  Connections {
    target: root.general
    function onIpSettingsLoaded(uuid, stored) {
      if (root.page === "settings" && root.pageLink && uuid === root.pageLink.uuid) root.populateForm(stored)
    }
  }

  // A saved enterprise profile that trusts any server is not reused: ask for
  // the server name and replace it.
  Connections {
    target: root.wifi
    function onNeedsPinning(ssid) {
      root.connectSsid = ssid
      root.connectEnterprise = true
      root.connectSecurity = "Wpa2Eap"
      root.connectError = ""
      root.serverError = ""
      root.caError = ""
      root.secrets = ({})
      root.wifi.failure = ""
      root.pinNotice = true
      root.go("connect")
    }
  }

  // A successful connection ends the prompt.
  Connections {
    target: root.wifi
    function onNetworksChanged() {
      var target = root.page === "connect" ? root.connectSsid : (root.page === "hidden" ? (root.hidden.ssid || "") : "")
      if (target === "") return
      var done = root.wifi.networks.some(function(n) { return n.ssid === target && n.connected })
      if (done) { root.secrets = ({}); root.hidden = ({}); root.go("") }
    }
  }
}
