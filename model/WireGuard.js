.pragma library
.import "Shared.js" as Shared

// Plain WireGuard backend model: interfaces brought up with wg-quick, outside
// NetworkManager. Lists only what is *unowned*: interfaces another backend
// manages (NM profiles, NetBird's wt0, Mullvad) are not duplicated here.
//
// /etc/wireguard is root-only (0700), so configs are discovered through
// `systemctl list-unit-files`-style instance names the user keeps, or through
// interfaces already up. Bringing one up/down needs root: pkexec.

var LINKS_ARGS = ["ip", "-j", "link", "show", "type", "wireguard"]

function upArgs(iface) { return ["pkexec", "wg-quick", "up", iface] }
function downArgs(iface) { return ["pkexec", "wg-quick", "down", iface] }

// Interface names are passed to wg-quick and pkexec: never trust them.
function validInterface(name) {
  return /^[A-Za-z0-9_=+.-]{1,15}$/.test(String(name || ""))
}

// `ip -j link show type wireguard` -> interface names.
function parseLinks(json) {
  var rows
  try { rows = JSON.parse(json) } catch (e) { return [] }
  if (!(rows instanceof Array)) return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var name = String(rows[i].ifname || "")
    if (validInterface(name)) out.push(name)
  }
  return out
}

// Build unified tunnels for interfaces that are up and not owned elsewhere.
// `owned` is the list of devices the other backends already report.
function fromLinks(names, owned) {
  var out = []
  for (var i = 0; i < names.length; i++) {
    var n = names[i]
    if (owned.indexOf(n) !== -1 || Shared.isForeignDevice(n)) continue
    out.push({
      id: "wg:" + n,
      backend: "wireguard",
      label: n,
      kind: "wireguard",
      up: true,
      connecting: false,
      device: n,
      routes: [],
      fullTunnel: false,
      detail: ""
    })
  }
  return out
}

// Same shape as NetworkManager.withRoutes.
function withRoutes(tunnel, routeJson) {
  var routes = Shared.asRoutes(routeJson)
  var full = Shared.isFullTunnel(routes)
  var copy = {}
  for (var k in tunnel) copy[k] = tunnel[k]
  copy.routes = routes
  copy.fullTunnel = full
  copy.detail = Shared.routeSummary(routes, full)
  return copy
}
