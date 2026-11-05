.pragma library
.import "Shared.js" as Shared
.import "NetworkManager.js" as NM
.import "NetBird.js" as NetBird
.import "Mullvad.js" as Mullvad
.import "WireGuard.js" as WG
.import "Tailscale.js" as Tailscale

// One shell invocation gathers every backend's state, so a poll is one process
// instead of seven and every section describes the same instant. Each command
// is time-limited: a wedged daemon must not wedge the widget.
var POLL_SCRIPT = [
  "t() { timeout 5 \"$@\" 2>/dev/null; }",
  // Leading newline: some tools end their output without one.
  "m() { printf '\\n@@%s\\n' \"$1\"; }",
  "m NM; t nmcli -t -f NAME,UUID,TYPE,DEVICE,STATE,FILENAME connection show",
  "m NB; t netbird status --json",
  "m NBN; t netbird networks list",
  "m TS; t tailscale status --json",
  "m INST; for c in netbird tailscale mullvad nmcli; do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done",
  "m MV; t mullvad status --json",
  "m MVR; t mullvad relay get",
  "m MVS; { t mullvad lockdown-mode get; t mullvad lan get; t mullvad auto-connect get; }",
  "m LINKS; t ip -j link show type wireguard",
  "m R4; t ip -j route show table all",
  "m R6; t ip -j -6 route show table all"
].join("\n")

var MULLVAD_NOTE = "Mullvad blocks traffic outside its tunnel, including other VPNs' endpoints. Exclude them with `mullvad split-tunnel`."

function parseSections(text) { return Shared.parseSections(text) }

// poll text -> { tunnels, networks, warning, note }
function build(text) {
  var sec = parseSections(text)
  var routes = Shared.routesByDevice(sec.R4 || "", sec.R6 || "")
  function routesOf(t) { return t.device ? (routes[t.device] || []) : [] }

  var networks = NetBird.parseNetworks(sec.NBN || "")
  var tunnels = NM.parseProfiles(sec.NM || "").map(function(t) {
    return NM.withRoutes(t, routesOf(t))
  })

  var nb = NetBird.parseStatus(sec.NB || "")
  if (nb) tunnels.push(NetBird.withNetworks(NetBird.withRoutes(nb, routesOf(nb)), networks))

  var ts = Tailscale.parseStatus(sec.TS || "")
  if (ts) tunnels.push(Tailscale.withRoutes(ts, routesOf(ts)))

  var mv = Mullvad.parseStatus(sec.MV || "")
  if (mv) {
    mv.location = Mullvad.parseRelayGet(sec.MVR || "")
    mv.settings = Mullvad.parseSettings(sec.MVS || "")
    tunnels.push(mv)
  }

  var owned = tunnels.map(function(t) { return t.device }).filter(function(d) { return d !== "" })
  WG.fromLinks(WG.parseLinks(sec.LINKS || ""), owned).forEach(function(t) {
    tunnels.push(WG.withRoutes(t, routes[t.device] || []))
  })

  var installed = {}
  String(sec.INST || "").split("\n").forEach(function(n) { if (n.trim() !== "") installed[n.trim()] = true })

  return {
    installed: installed,
    tunnels: Shared.sortTunnels(tunnels),
    networks: networks,
    warning: Shared.conflictWarning(tunnels),
    note: Shared.mullvadShadowsOthers(tunnels) ? MULLVAD_NOTE : ""
  }
}

// Command sequence (argv arrays) for flipping one tunnel. `networks` is the
// last NetBird network list, needed only for exit-node changes.
function mullvadCommands(country, city) { return Mullvad.connectToCommands(country, city) }
function mullvadSettingCommands(key, on) { return Mullvad.settingCommands(key, on) }

function toggleCommands(tunnel) {
  var up = tunnel.up || tunnel.connecting
  if (tunnel.backend === "networkmanager") {
    var uuid = tunnel.id.slice(3)
    return [up ? NM.downArgs(uuid) : NM.upArgs(uuid)]
  }
  if (tunnel.backend === "netbird") return [up ? NetBird.DOWN_ARGS : NetBird.UP_ARGS]
  if (tunnel.backend === "tailscale") return [up ? Tailscale.DOWN_ARGS : Tailscale.UP_ARGS]
  if (tunnel.backend === "mullvad") return [up ? Mullvad.DISCONNECT_ARGS : Mullvad.CONNECT_ARGS]
  if (tunnel.backend === "wireguard") {
    var iface = tunnel.device
    if (!WG.validInterface(iface)) return []
    return [up ? WG.downArgs(iface) : WG.upArgs(iface)]
  }
  return []
}

// Toggle a NetBird exit node: picking the selected one clears it.
function exitCommands(networks, tunnel, exitId) {
  if (tunnel.backend === "tailscale") return Tailscale.exitCommands(tunnel, exitId)
  if (tunnel.currentExit === exitId) return NetBird.clearExitCommands(networks)
  return NetBird.selectExitCommands(networks, exitId)
}
