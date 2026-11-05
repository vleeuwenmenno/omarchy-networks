.pragma library
.import "Shared.js" as Shared

// NetBird backend model. One tunnel (the daemon's own), interface wt0.
// NetBird is a mesh: by default it carries only its overlay range, so it
// coexists with anything. It only becomes a full tunnel when an exit-node
// network is selected, which `ip route` shows and `status --json` does not
// (its "networks" field lists what is *available*, not what is selected).

var STATUS_ARGS = ["netbird", "status", "--json"]
var UP_ARGS = ["netbird", "up"]
var DOWN_ARGS = ["netbird", "down"]
var DEVICE = "wt0"
var NETWORKS_ARGS = ["netbird", "networks", "list"]

// -> unified tunnel, or null when the daemon is unreachable / not installed.
function parseStatus(json) {
  var s
  try { s = JSON.parse(json) } catch (e) { return null }
  if (!s || typeof s !== "object") return null
  var state = String(s.daemonStatus || "")
  var up = state === "Connected"
  var connecting = state === "Connecting"
  var peers = s.peers || {}
  var detail = ""
  if (up) {
    detail = (peers.connected || 0) + "/" + (peers.total || 0) + " peers"
    if (s.netbirdIp) detail = String(s.netbirdIp).replace(/\/\d+$/, "") + " · " + detail
  } else if (state === "NeedsLogin" || state === "LoginFailed" || state === "SessionExpired") {
    detail = "Login required: netbird up"
  } else if (state !== "") {
    detail = state
  }
  var peerList = ((peers.details instanceof Array) ? peers.details : []).map(function(d) {
    return {
      // First label of the name: the machine, not the domain it lives under.
      name: String(d.fqdn || "").split(".")[0] || String(d.fqdn || ""),
      fqdn: String(d.fqdn || ""),
      ip: String(d.netbirdIp || ""),
      connected: d.status === "Connected",
      status: String(d.status || ""),
      relayed: d.connectionType === "Relayed",
      connectionType: d.connectionType === "-" ? "" : String(d.connectionType || ""),
      latencyMs: Math.round(Number(d.latency || 0) / 1e6)
    }
  }).sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  return {
    id: "netbird",
    backend: "netbird",
    label: "NetBird",
    kind: "mesh",
    up: up,
    connecting: connecting,
    device: up ? DEVICE : "",
    routes: [],
    fullTunnel: false,
    detail: detail,
    needsLogin: /NeedsLogin|LoginFailed|SessionExpired/.test(state),
    ip: String(s.netbirdIp || "").replace(/\/\d+$/, ""),
    fqdn: String(s.fqdn || ""),
    managementUrl: (s.management && s.management.url) || "",
    managementOk: !!(s.management && s.management.connected),
    peers: peerList,
    peersConnected: peers.connected || 0,
    peersTotal: peers.total || 0
  }
}

// Same shape as NetworkManager.withRoutes. The overlay range is always there
// while up; exit-node routes show up alongside it.
function withRoutes(tunnel, routeJson) {
  var routes = tunnel.up ? Shared.asRoutes(routeJson) : []
  var full = Shared.isFullTunnel(routes)
  var copy = {}
  for (var k in tunnel) copy[k] = tunnel[k]
  copy.routes = routes
  copy.fullTunnel = full
  if (tunnel.up && full) copy.detail = "exit node · " + tunnel.detail
  return copy
}

// ---- Exit nodes -----------------------------------------------------------
//
// NetBird calls them "networks"; an exit node is a network that carries the
// default route. `netbird networks list` has no JSON mode, so parse its text:
//
//   - ID: Exit Node (exit-amsterdam)
//     Network: 0.0.0.0/0, ::/0
//     Status: Not Selected

function parseNetworks(text) {
  var out = []
  var cur = null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var id = line.match(/^\s*-\s*ID:\s*(.+?)\s*$/)
    if (id) {
      cur = { id: id[1], label: id[1], ranges: [], selected: false, exitNode: false }
      out.push(cur)
      continue
    }
    if (!cur) continue
    var net = line.match(/^\s*(?:Network|Domains):\s*(.*?)\s*$/)
    if (net) {
      cur.ranges = net[1].split(/\s*,\s*/).filter(function(x) { return x !== "" })
      cur.exitNode = Shared.isFullTunnel(cur.ranges)
      continue
    }
    var st = line.match(/^\s*Status:\s*(.+?)\s*$/)
    if (st) cur.selected = st[1] === "Selected"
  }
  for (var j = 0; j < out.length; j++) {
    var name = out[j].id.match(/^Exit Node \((.*)\)$/)
    if (name) out[j].label = name[1]
  }
  return out
}

function exitNodes(networks) {
  return (networks || []).filter(function(n) { return n.exitNode })
}

// Commands to make `id` the one active exit node. Exit nodes are exclusive:
// two default routes through one mesh make no sense, so drop the others first.
// Other (non-exit) networks are left alone, which is why this does not use the
// replace-all form of `select`. "--" keeps an id that starts with "-" from
// being read as a flag.
function selectExitCommands(networks, id) {
  var cmds = []
  exitNodes(networks).forEach(function(n) {
    if (n.selected && n.id !== id) cmds.push(["netbird", "networks", "deselect", "--", n.id])
  })
  cmds.push(["netbird", "networks", "select", "-a", "--", id])
  return cmds
}

function clearExitCommands(networks) {
  return exitNodes(networks)
    .filter(function(n) { return n.selected })
    .map(function(n) { return ["netbird", "networks", "deselect", "--", n.id] })
}

// Fold the network list into the tunnel: exit-node choices, and full-tunnel
// status taken from the selection when `ip route` has not caught up yet.
function withNetworks(tunnel, networks) {
  var exits = exitNodes(networks).map(function(n) {
    return { id: n.id, label: n.label, selected: n.selected }
  })
  var chosen = exits.filter(function(e) { return e.selected })
  var copy = {}
  for (var k in tunnel) copy[k] = tunnel[k]
  copy.exitNodes = exits
  copy.currentExit = chosen.length > 0 ? chosen[0].id : ""
  if (tunnel.up && chosen.length > 0) {
    copy.fullTunnel = true
    copy.detail = "exit: " + chosen[0].label + " · " + tunnel.detail.replace(/^exit node · /, "")
  }
  return copy
}
