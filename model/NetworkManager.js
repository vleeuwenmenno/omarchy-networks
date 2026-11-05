.pragma library
.import "Shared.js" as Shared

// NetworkManager backend model: WireGuard and plugin VPN (OpenVPN, OpenConnect,
// VPNC) profiles NetworkManager holds. Each profile is its own independent
// tunnel; bringing one up never touches another.

// Command that lists profiles. Terse, one per line, fixed field order.
var LIST_ARGS = ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE,STATE,FILENAME", "connection", "show"]

function upArgs(uuid) { return ["nmcli", "connection", "up", "uuid", uuid] }
function downArgs(uuid) { return ["nmcli", "connection", "down", "uuid", uuid] }

// Parse the LIST_ARGS output into unified tunnels (routes filled in later by
// withRoutes, because they need a second command per active device).
function parseProfiles(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "") continue
    var f = Shared.splitTerse(lines[i])
    if (f.length < 6) continue
    var name = f[0], uuid = f[1], type = f[2], device = f[3], state = f[4], file = f[5]
    if (type !== "wireguard" && type !== "vpn") continue
    // Volatile profile NM generates for an interface another tool owns
    // (NetBird's wt0, Mullvad's wg0-mullvad): not ours to list or tear down.
    if (file.indexOf("/run/") === 0) continue
    if (Shared.isForeignDevice(device)) continue
    out.push({
      id: "nm:" + uuid,
      backend: "networkmanager",
      label: name,
      kind: type === "wireguard" ? "wireguard" : "vpn",
      up: state === "activated",
      connecting: state === "activating",
      device: state === "activated" ? device : "",
      routes: [],
      fullTunnel: false,
      detail: ""
    })
  }
  return out
}

// Attach installed routes (from `ip -j route show dev <device>`) to a tunnel.
function withRoutes(tunnel, routeJson) {
  var routes = tunnel.up ? Shared.asRoutes(routeJson) : []
  var full = Shared.isFullTunnel(routes)
  var copy = {}
  for (var k in tunnel) copy[k] = tunnel[k]
  copy.routes = routes
  copy.fullTunnel = full
  copy.detail = tunnel.up ? Shared.routeSummary(routes, full) : ""
  return copy
}

// nmcli exits non-zero with these when the profile lacks stored secrets.
function needsSecrets(stderr) {
  return /secrets were required|no secrets|password.*required/i.test(String(stderr || ""))
}
