.pragma library
.import "Shared.js" as Shared

// Tailscale backend model. Same shape as NetBird: one tunnel (the daemon's own,
// interface tailscale0), peers, and exit nodes. By default Tailscale carries
// only the 100.64.0.0/10 overlay, so it coexists with everything; it becomes a
// full tunnel when an exit node is chosen.

var STATUS_ARGS = ["tailscale", "status", "--json"]
// `tailscale up` waits for a login when there is none; never let it hang the
// panel. A logged-out tunnel is sent to its login page instead (see MeshSection).
var UP_ARGS = ["timeout", "30", "tailscale", "up"]
var DOWN_ARGS = ["tailscale", "down"]
var DEVICE = "tailscale0"

function cleanDns(name) {
  var v = String(name || "")
  return v.charAt(v.length - 1) === "." ? v.slice(0, -1) : v
}

function v4(ips) {
  return (ips instanceof Array ? ips : []).filter(function(ip) { return /^100\.\d+\.\d+\.\d+$/.test(String(ip)) })
}

function displayName(peer) {
  var host = String(peer.HostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return cleanDns(peer.DNSName).split(".")[0] || "Unknown"
}

// Peers an exit node can be picked from, and the one currently picked, are
// told apart by this id: the node's tailnet IPv4, which `tailscale set
// --exit-node=` accepts and which never needs quoting.
function isExitId(id) { return /^100\.\d+\.\d+\.\d+$/.test(String(id || "")) }

// `tailscale status --json` -> unified tunnel, or null when the daemon is not
// reachable (not installed, or tailscaled is not running).
function parseStatus(json) {
  var s
  try { s = JSON.parse(json) } catch (e) { return null }
  if (!s || typeof s !== "object" || !s.BackendState) return null

  var state = String(s.BackendState)
  var up = state === "Running"
  var connecting = state === "Starting"
  var needsLogin = state === "NeedsLogin" || state === "NeedsMachineAuth"
  var self = s.Self || {}
  var selfIps = v4(self.TailscaleIPs || s.TailscaleIPs)

  var rawPeers = s.Peer || {}
  var peers = []
  var exits = []
  for (var id in rawPeers) {
    var p = rawPeers[id] || {}
    var ips = v4(p.TailscaleIPs)
    var peer = {
      name: displayName(p),
      fqdn: cleanDns(p.DNSName),
      ip: ips.length > 0 ? ips[0] : "",
      connected: p.Online === true,
      status: p.Online === true ? "Online" : "Offline",
      relayed: p.Online === true && String(p.CurAddr || "") === "" && String(p.Relay || "") !== "",
      connectionType: p.Online !== true ? "" : (String(p.CurAddr || "") !== "" ? "direct" : (String(p.Relay || "") !== "" ? "relay" : "")),
      latencyMs: 0,
      os: String(p.OS || "")
    }
    peers.push(peer)
    if (p.ExitNodeOption === true && peer.ip !== "")
      exits.push({ id: peer.ip, label: peer.name, selected: p.ExitNode === true, online: peer.connected })
  }
  peers.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  // Online exit nodes first; an offline one is only worth showing if selected.
  exits = exits.filter(function(e) { return e.online || e.selected })
  exits.sort(function(a, b) {
    if (a.online !== b.online) return a.online ? -1 : 1
    return a.label.localeCompare(b.label)
  })
  var chosen = exits.filter(function(e) { return e.selected })

  var online = peers.filter(function(p) { return p.connected }).length
  var detail = ""
  if (up) {
    detail = (selfIps[0] || "") + (selfIps[0] ? " · " : "") + online + "/" + peers.length + " peers"
    if (chosen.length > 0) detail = "exit: " + chosen[0].label + " · " + detail
  } else if (needsLogin) {
    detail = "Login required"
  } else if (state === "Stopped") {
    detail = "Stopped"
  } else if (state !== "") {
    detail = state
  }

  return {
    id: "tailscale",
    backend: "tailscale",
    label: "Tailscale",
    kind: "mesh",
    up: up,
    connecting: connecting,
    device: up ? DEVICE : "",
    routes: [],
    fullTunnel: up && chosen.length > 0,
    detail: detail,
    needsLogin: needsLogin,
    authUrl: /^https:\/\//.test(String(s.AuthURL || "")) ? String(s.AuthURL) : "",
    ip: selfIps[0] || "",
    fqdn: cleanDns(self.DNSName),
    tailnet: String((s.CurrentTailnet && s.CurrentTailnet.Name) || ""),
    managementUrl: "",
    managementOk: true,
    peers: peers,
    peersConnected: online,
    peersTotal: peers.length,
    exitNodes: exits,
    currentExit: chosen.length > 0 ? chosen[0].id : ""
  }
}

// Same shape as NetBird.withRoutes.
function withRoutes(tunnel, routes) {
  var r = tunnel.up ? Shared.asRoutes(routes) : []
  var full = Shared.isFullTunnel(r) || tunnel.fullTunnel
  var copy = {}
  for (var k in tunnel) copy[k] = tunnel[k]
  copy.routes = r
  copy.fullTunnel = full
  return copy
}

// Pick an exit node, or clear it by picking the selected one again. Tailscale
// has one exit node at a time, so a single `set` is enough either way.
function exitCommands(tunnel, exitId) {
  if (tunnel.currentExit === exitId) return [["tailscale", "set", "--exit-node="]]
  if (!isExitId(exitId)) return []
  return [["tailscale", "set", "--exit-node=" + exitId]]
}

// `tailscale up` as an ordinary user needs the operator role. The daemon says
// so in words, which is all there is to match on.
function needsOperator(stderr) {
  return /access denied|operator|sudo tailscale|permission denied/i.test(String(stderr || ""))
}

function operatorCommand(user) {
  if (!/^[a-z_][a-z0-9_-]{0,31}$/i.test(String(user || ""))) return []
  return [["pkexec", "tailscale", "set", "--operator=" + user]]
}
