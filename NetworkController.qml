import QtQuick
import Quickshell.Io
import "model/Network.js" as Network
import "model/IpConfig.js" as IpConfig
import "model/Demo.js" as Demo

// General networking state: wired and wireless links, plus live traffic stats.
// Separate from NetworksController (VPN) on purpose: they poll different
// things at different speeds and a section only needs the one it shows.
Item {
  id: root
  visible: false

  property var settings: ({})

  // Sample /proc/net/dev every second. The panel turns this on only while the
  // stats are on screen; a closed panel costs one slow poll and nothing else.
  property bool statsActive: false
  // Made-up data instead of the real machine; see model/Demo.js.
  property bool demo: false

  property var wired: []
  property var wireless: []
  property string primary: ""
  property bool loaded: false

  // dev -> latest counters / bytes-per-second / rolling history.
  property var counters: ({})
  property var rates: ({})
  property var history: ({})
  readonly property int historyLength: 40

  readonly property int refreshIntervalSec: {
    var v = Number(settings ? settings.refreshIntervalSec : 10)
    return isNaN(v) ? 10 : Math.max(5, Math.min(600, Math.round(v)))
  }

  property var _prev: null
  property real _prevAt: 0

  // ---- Actions on a link --------------------------------------------------

  property string actionError: ""
  property string actionNote: ""
  // device -> desired enabled, until a poll agrees. Throws the switch at once.
  property var pendingLinks: ({})
  readonly property bool actionBusy: actionProcess.running || _queue.length > 0
  property var _queue: []
  property string _queueNote: ""

  function _run(cmds, note) {
    if (demo) return
    actionError = ""
    actionNote = ""
    _queue = cmds.slice()
    _queueNote = note || ""
    _next()
  }

  function _next() {
    if (_queue.length === 0) {
      actionNote = _queueNote
      settle.restart()
      return
    }
    var cmd = _queue[0]
    _queue = _queue.slice(1)
    actionProcess.command = cmd
    actionProcess.running = true
  }

  // Wired links: nmcli connects and disconnects the device itself.
  function setLinkEnabled(device, on) {
    var next = {}
    for (var k in pendingLinks) next[k] = pendingLinks[k]
    next[device] = on
    pendingLinks = next
    pendingExpiry.restart()
    _run([["nmcli", "device", on ? "connect" : "disconnect", device]], "")
  }

  // The current IPv4 settings of a connection, for the form. Result arrives on
  // `ipSettingsLoaded`; the form never reads live link state, which changes
  // under the user's fingers while they type.
  signal ipSettingsLoaded(string uuid, var settings)
  property string _loadingUuid: ""
  function loadIpSettings(uuid) {
    if (demo) { ipSettingsLoaded(uuid, { method: "auto", address: "", prefix: 0, gateway: "", dns: [] }); return }
    if (!uuid || loadProcess.running) return
    _loadingUuid = uuid
    loadProcess.command = IpConfig.SHOW_ARGS(uuid)
    loadProcess.running = true
  }

  // DNS provider (global: Omarchy writes it for every connection).
  property string dnsProvider: ""
  property string dnsError: ""
  property string _dnsPending: ""
  readonly property bool dnsBusy: dnsProcess.running

  function setDns(provider) {
    if (demo) return
    if (dnsProcess.running || ["DHCP", "Cloudflare", "Google"].indexOf(provider) === -1) return
    dnsError = ""
    _dnsPending = provider
    dnsProcess.command = ["omarchy-dns", provider]
    dnsProcess.running = true
  }

  // Custom servers reach the helper on stdin, which is how it asks for them.
  function setCustomDns(servers, label) {
    if (demo) return
    if (dnsProcess.running || servers.length === 0) return
    dnsError = ""
    _dnsPending = label || "Custom"
    dnsProcess.command = ["omarchy-dns", "Custom"]
    dnsProcess.running = true
    dnsProcess.write(servers.join(" ") + "\n")
  }

  // Quad9 and OpenDNS ride on the helper's Custom mode.
  function setDnsPreset(name) {
    var preset = Network.DNS_PRESETS[name]
    if (preset) setCustomDns(preset.servers, name)
  }

  // The Wi-Fi band: what we are on, what the access point offers, what is pinned.
  property var band: ({ band: "", available: [], selected: "auto" })
  property string bandPending: ""
  function loadBand() {
    if (demo) { band = Demo.BAND; return }
    if (!bandProcess.running) bandProcess.running = true
  }
  function setBand(value) {
    var cmds = Network.bandCommands(value)
    if (cmds.length === 0 || actionProcess.running) return
    bandPending = value
    _run(cmds, "")
  }

  // A short-lived "that worked" mark, keyed by what was done. Rows read it to
  // show a check where their label was.
  property string flashKey: ""
  function flash(key) {
    flashKey = key
    flashTimer.restart()
  }

  // The password goes straight from the Omarchy helper into the clipboard
  // through a pipe: it is never an argument, and never held here. paste-once
  // clears it after the first paste.
  function copyWifiPassword(device) {
    if (demo) { flash("wifi-password"); return }
    if (!Network.validDevice(device) || passwordProcess.running) return
    actionError = ""
    passwordProcess.command = ["bash", "-c", "set -o pipefail; omarchy-network-password \"$1\" | wl-copy --paste-once", "_", device]
    passwordProcess.running = true
  }

  // The QR matrix of the connected Wi-Fi, for the share page.
  property var qr: null
  property string qrError: ""
  readonly property bool qrLoading: qrProcess.running
  function loadQr(device) {
    if (demo) { qrError = "Hidden in demo mode"; return }
    if (!Network.validDevice(device) || qrProcess.running) return
    qr = null
    qrError = ""
    qrProcess.command = ["omarchy-network-qr", "--meta", device]
    qrProcess.running = true
  }
  function clearQr() { qr = null; qrError = "" }

  function applyIp(uuid, method, value) {
    _run(IpConfig.applyCommands(uuid, method, value),
      method === "manual" ? "Static address applied" : "Now using DHCP")
  }

  function refresh() {
    if (demo) { _applyPoll(Demo.NETWORK_POLL); return }
    if (!pollProcess.running) pollProcess.running = true
  }

  function _applyPoll(text) {
    var b = Network.build(text)
    wired = b.wired
    wireless = b.wireless
    primary = _settledPrimary(b)
    if (!dnsProcess.running && b.dns !== "") {
      var all = b.wired.concat(b.wireless)
      var main = all.filter(function(l) { return l.device === b.primary })[0]
      var v4 = main ? main.dns.filter(function(d) { return d.indexOf(":") === -1 }) : []
      dnsProvider = Network.resolveDnsProvider(b.dns, v4)
    }
    loaded = true

    var keep = {}
    var changed = false
    var all = b.wired.concat(b.wireless)
    for (var dev in pendingLinks) {
      var l = all.filter(function(x) { return x.device === dev })[0]
      if (l && l.connected !== pendingLinks[dev]) keep[dev] = pendingLinks[dev]
      else changed = true
    }
    if (changed) pendingLinks = keep
  }

  // The default route flickers while tunnels and exit nodes reshuffle routes,
  // and one bad sample would swap the bar icon for ten seconds. A different
  // primary link must show up on two polls in a row, unless the old one is gone.
  property string _candidate: ""
  function _settledPrimary(b) {
    if (primary === "" || b.primary === primary) { _candidate = ""; return b.primary }
    var all = b.wired.concat(b.wireless)
    var stillUp = all.some(function(l) { return l.device === primary && l.connected })
    if (!stillUp) { _candidate = ""; return b.primary }
    if (_candidate === b.primary) { _candidate = ""; return b.primary }
    _candidate = b.primary
    return primary
  }

  function _applyStats(text) {
    var now = Date.now()
    var cur = Network.parseProcNetDev(text)
    var r = Network.rates(_prev, cur, (now - _prevAt) / 1000)
    var h = {}
    for (var dev in cur) {
      var old = history[dev] || { rx: [], tx: [] }
      var rate = r[dev]
      h[dev] = rate ? {
        rx: Network.pushHistory(old.rx, rate.rx, historyLength),
        tx: Network.pushHistory(old.tx, rate.tx, historyLength)
      } : old
    }
    counters = cur
    rates = r
    history = h
    _prev = cur
    _prevAt = now
  }

  onStatsActiveChanged: {
    if (statsActive) {
      // First sample after a pause would average over the whole gap.
      _prev = null
      statsTimer.restart()
      sample()
    } else {
      statsTimer.stop()
    }
  }

  function sample() {
    if (demo) {
      counters = Demo.STATS.counters
      rates = Demo.STATS.rates
      history = Demo.STATS.history
      return
    }
    if (!statsProcess.running) statsProcess.running = true
  }

  Process {
    id: pollProcess
    running: false
    command: ["sh", "-c", Network.POLL_SCRIPT]
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root._applyPoll(String(pollOut.text || ""))
    }
  }

  Process {
    id: statsProcess
    running: false
    command: Network.STATS_ARGS
    stdout: StdioCollector { id: statsOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root._applyStats(String(statsOut.text || ""))
    }
  }

  Process {
    id: dnsProcess
    running: false
    command: []
    stdinEnabled: true
    stderr: StdioCollector { id: dnsErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.dnsProvider = root._dnsPending
      else root.dnsError = String(dnsErr.text || "").trim().split("\n")[0] || "Could not change DNS"
      root.refresh()
    }
  }

  Process {
    id: bandProcess
    running: false
    command: ["omarchy-network-band"]
    stdout: StdioCollector { id: bandOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.band = Network.parseBand(String(bandOut.text || ""))
      root.bandPending = ""
    }
  }

  Process {
    id: passwordProcess
    running: false
    command: []
    stderr: StdioCollector { id: passwordErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.flash("wifi-password")
      else root.actionError = String(passwordErr.text || "").trim().split("\n")[0] || "Could not read the Wi-Fi password"
    }
  }

  Process {
    id: qrProcess
    running: false
    command: []
    stdout: StdioCollector { id: qrOut; waitForEnd: true }
    stderr: StdioCollector { id: qrErr; waitForEnd: true }
    onExited: function(exitCode) {
      var parsed = exitCode === 0 ? Network.parseQr(String(qrOut.text || "")) : null
      if (parsed) { root.qr = parsed; root.qrError = "" }
      else root.qrError = String(qrErr.text || "").trim().split("\n")[0] || "Could not make a QR code for this network"
    }
  }

  Timer {
    id: flashTimer
    interval: 1600
    repeat: false
    onTriggered: root.flashKey = ""
  }

  Process {
    id: loadProcess
    running: false
    command: []
    stdout: StdioCollector { id: loadOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.ipSettingsLoaded(root._loadingUuid,
        exitCode === 0 ? IpConfig.parseSettings(String(loadOut.text || "")) : null)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var text = String(actionErr.text || "") + "\n" + String(actionOut.text || "")
        var line = text.split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })[0]
        root.actionError = line || ("Command failed (" + exitCode + ")")
        root._queue = []
        root.pendingLinks = ({})
        settle.restart()
        return
      }
      root._next()
    }
  }

  Timer {
    id: settle
    interval: 1500
    repeat: false
    onTriggered: { root.refresh(); root.loadBand() }
  }

  Timer {
    id: pendingExpiry
    interval: 10000
    repeat: false
    onTriggered: root.pendingLinks = ({})
  }

  Timer {
    id: statsTimer
    interval: 1000
    repeat: true
    running: false
    onTriggered: root.sample()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
