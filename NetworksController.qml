import QtQuick
import Quickshell.Io
import "model/Compose.js" as Compose
import "model/Mullvad.js" as Mullvad
import "model/Demo.js" as Demo

// Owns tunnel state and every command that changes it. The panel talks to this
// and knows nothing about nmcli, netbird, mullvad or wg-quick.
//
// Tunnels are independent: toggling one never touches another. That is the
// whole point, because split-tunnel VPNs are meant to run side by side.
Item {
  id: root
  visible: false

  property var settings: ({})
  // Made-up data instead of the real machine; see model/Demo.js.
  property bool demo: false

  // Last poll, straight from model/Compose.js.
  property var tunnels: []
  property var networks: []
  property string warning: ""
  property string note: ""
  property bool loaded: false
  // Tool name -> true, for every tool on this machine (even with no daemon).
  property var installed: ({})

  property string lastError: ""
  // id -> desired `up`, until a poll agrees or the expiry timer gives up. Makes
  // the switch throw the instant it is clicked instead of after the next poll.
  property var pending: ({})
  // NetBird exit-node change in flight.
  property bool exitBusy: false
  property string exitTarget: ""
  // exit id -> desired `selected`, until a poll agrees. Keeps the spinner on the
  // row from the click until NetBird really reports the change.
  property var exitPending: ({})

  // Mullvad: the relay list (loaded once) and the row being switched to.
  property var relays: []
  property bool relaysLoaded: false
  // Mullvad setting key -> desired value, until a poll agrees.
  property var settingPending: ({})
  property string mullvadTarget: ""
  property bool mullvadSwitching: false

  readonly property int refreshIntervalSec: {
    var v = Number(settings ? settings.refreshIntervalSec : 10)
    return isNaN(v) ? 10 : Math.max(5, Math.min(600, Math.round(v)))
  }

  // What the panel draws: the last poll with optimistic overrides applied.
  readonly property var view: tunnels.map(function(t) {
    var copy = t
    if (t.id in pending) {
      var want = pending[t.id]
      copy = {}
      for (var k in t) copy[k] = t[k]
      copy.connecting = want !== t.up
      copy.up = want
    }
    if (t.settings && Object.keys(settingPending).length > 0) {
      if (copy === t) { copy = {}; for (var m in t) copy[m] = t[m] }
      var overlay = {}
      for (var sk in t.settings) overlay[sk] = t.settings[sk]
      for (var pk in settingPending) overlay[pk] = settingPending[pk]
      copy.settings = overlay
      copy.settingsPending = Object.keys(settingPending)
    }
    if (t.exitNodes && Object.keys(exitPending).length > 0) {
      if (copy === t) { copy = {}; for (var j in t) copy[j] = t[j] }
      copy.exitNodes = t.exitNodes.map(function(e) {
        if (!(e.id in exitPending)) return e
        return { id: e.id, label: e.label, selected: exitPending[e.id], pending: true }
      })
    }
    return copy
  })
  readonly property int upCount: view.filter(function(t) { return t.up }).length
  readonly property bool anyUp: upCount > 0
  readonly property bool busy: actionProcess.running || exitBusy

  property var _queue: []
  property var _queueDone: null

  function refresh() {
    if (demo) { _applyPoll(Demo.VPN_POLL); return }
    if (!pollProcess.running) pollProcess.running = true
  }

  function toggle(tunnel) {
    if (demo) return
    if (!tunnel || actionProcess.running) return
    var cmds = Compose.toggleCommands(tunnel)
    if (cmds.length === 0) return
    var next = {}
    for (var k in pending) next[k] = pending[k]
    next[tunnel.id] = !(tunnel.up || tunnel.connecting)
    pending = next
    pendingExpiry.restart()
    lastError = ""
    _run(cmds)
  }

  // Pick (or, if already selected, clear) a NetBird exit node.
  function toggleExit(tunnel, exitId) {
    if (demo) return
    if (!tunnel || actionProcess.running || Object.keys(exitPending).length > 0) return
    var cmds = Compose.exitCommands(networks, tunnel, exitId)
    if (cmds.length === 0) return
    lastError = ""
    exitBusy = true
    exitTarget = exitId
    // Selecting one exit node deselects the others; each of them spins too.
    var wasSelected = tunnel.currentExit === exitId
    var want = {}
    var exits = tunnel.exitNodes || []
    for (var i = 0; i < exits.length; i++) {
      if (exits[i].id === exitId) want[exitId] = !wasSelected
      else if (!wasSelected && exits[i].selected) want[exits[i].id] = false
    }
    exitPending = want
    pendingExpiry.restart()
    _run(cmds)
  }

  // Pick a Mullvad location and connect to it. Clicking the current one
  // disconnects instead, like any other switch.
  function connectMullvad(tunnel, country, city) {
    if (demo) return
    if (!tunnel || actionProcess.running) return
    var key = country + "/" + (city || "")
    var here = tunnel.up && tunnel.location && tunnel.location.country === country
      && (tunnel.location.city || "") === (city || "")
    var cmds = here ? Compose.toggleCommands(tunnel) : Compose.mullvadCommands(country, city)
    if (cmds.length === 0) return
    var next = {}
    for (var k in pending) next[k] = pending[k]
    next[tunnel.id] = !here
    pending = next
    pendingExpiry.restart()
    lastError = ""
    mullvadTarget = key
    mullvadSwitching = true
    _run(cmds)
  }

  // Run commands that are not a switch: authorising an operator, and the like.
  function runAction(cmds) {
    if (demo) return
    if (actionProcess.running || cmds.length === 0) return
    lastError = ""
    _run(cmds)
  }

  function setMullvadSetting(key, on) {
    if (demo) return
    if (actionProcess.running) return
    var cmds = Compose.mullvadSettingCommands(key, on)
    if (cmds.length === 0) return
    var next = {}
    for (var k in settingPending) next[k] = settingPending[k]
    next[key] = on
    settingPending = next
    pendingExpiry.restart()
    lastError = ""
    _run(cmds)
  }

  function loadRelays() {
    if (demo) { relays = Mullvad.parseRelays(Demo.RELAY_LIST); relaysLoaded = true; return }
    if (relaysLoaded || relaysProcess.running) return
    relaysProcess.running = true
  }

  function _run(cmds) {
    if (demo) return
    _queue = cmds.slice()
    _next()
  }

  function _next() {
    if (_queue.length === 0) {
      mullvadSwitching = false
      exitBusy = false
      settle.restart()
      return
    }
    var cmd = _queue[0]
    _queue = _queue.slice(1)
    actionProcess.command = cmd
    actionProcess.running = true
  }

  function _applyPoll(text) {
    var b = Compose.build(text)
    tunnels = b.tunnels
    networks = b.networks
    installed = b.installed
    warning = b.warning
    note = b.note
    loaded = true

    var keep = {}
    var changed = false
    for (var id in pending) {
      var t = b.tunnels.filter(function(x) { return x.id === id })[0]
      // Settled when the real state matches what was asked for, or the tunnel
      // is gone altogether.
      if (t && t.up !== pending[id]) keep[id] = pending[id]
      else changed = true
    }
    if (changed) pending = keep

    var exits = {}
    var mvNow = b.tunnels.filter(function(x) { return x.settings })[0]
    var keepSettings = {}
    var settingsChanged = false
    for (var sk in settingPending) {
      if (mvNow && mvNow.settings[sk] !== settingPending[sk]) keepSettings[sk] = settingPending[sk]
      else settingsChanged = true
    }
    if (settingsChanged) settingPending = keepSettings

    var allExits = []
    b.tunnels.forEach(function(x) { if (x.exitNodes) allExits = allExits.concat(x.exitNodes) })
    var exitChanged = false
    for (var eid in exitPending) {
      var e = allExits.filter(function(x) { return x.id === eid })[0]
      if (e && e.selected !== exitPending[eid]) exits[eid] = exitPending[eid]
      else exitChanged = true
    }
    if (exitChanged) exitPending = exits
  }

  function _firstLine(text) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i].trim()
      if (l !== "") return l
    }
    return ""
  }

  Process {
    id: pollProcess
    running: false
    command: ["sh", "-c", Compose.POLL_SCRIPT]
    stdout: StdioCollector { id: pollOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root._applyPoll(String(pollOut.text || ""))
    }
  }

  Process {
    id: relaysProcess
    running: false
    command: Mullvad.RELAY_LIST_ARGS
    stdout: StdioCollector { id: relaysOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.relays = Mullvad.parseRelays(String(relaysOut.text || ""))
      root.relaysLoaded = true
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var why = root._firstLine(actionErr.text) || root._firstLine(actionOut.text)
        root.lastError = why !== "" ? why : ("Command failed (" + exitCode + ")")
        // Stop the chain, and let the next poll show what is really up.
        root._queue = []
        root.pending = ({})
        root.exitPending = ({})
        root.settingPending = ({})
        root.exitBusy = false
        root.mullvadSwitching = false
        settle.restart()
        return
      }
      root._next()
    }
  }

  // Daemons answer "up" before the interface and routes exist; poll shortly
  // after a command and again a little later to catch the slow ones.
  Timer {
    id: settle
    interval: 1200
    repeat: false
    property int round: 0
    onTriggered: {
      root.refresh()
      if (round < 1) { round += 1; settle.start() } else round = 0
    }
  }

  // A command that "succeeded" but never changed state must not leave the
  // switch lying forever.
  Timer {
    id: pendingExpiry
    interval: 12000
    repeat: false
    onTriggered: { root.pending = ({}); root.exitPending = ({}); root.settingPending = ({}) }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
