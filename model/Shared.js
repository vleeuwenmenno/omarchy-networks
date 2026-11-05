.pragma library

// Pure helpers shared by every backend model. No QML, no side effects.
//
// Unified tunnel row, produced by every backend model:
//   {
//     id:         "<backend>:<stable key>"   e.g. "nm:<uuid>", "netbird", "mullvad", "wg:<iface>"
//     backend:    "networkmanager" | "netbird" | "mullvad" | "wireguard"
//     label:      display name
//     kind:       "wireguard" | "vpn" | "mesh" | "mullvad"
//     up:         boolean, tunnel is carrying traffic
//     connecting: boolean, activation in flight
//     device:     kernel interface name when up, "" otherwise
//     routes:     [cidr] actually installed while up, [] otherwise
//     fullTunnel: boolean, routes steal the default route
//     detail:     one short line for the row
//   }

var GLYPH_VPN = ""
var GLYPH_UP = ""

// Interfaces owned by a tool other than NetworkManager, even though NM adopts
// them and lists a volatile profile. They belong on their own backend.
function isForeignDevice(device) {
  var d = String(device || "")
  return d === "wt0" || d === "tailscale0" || /-mullvad$/.test(d) || /^wg\d*-mullvad/.test(d)
}

// nmcli -t escapes ":" and "\" inside a field with a backslash.
function splitTerse(line) {
  var fields = []
  var cur = ""
  for (var i = 0; i < line.length; i++) {
    var ch = line.charAt(i)
    if (ch === "\\" && i + 1 < line.length) {
      cur += line.charAt(i + 1)
      i++
    } else if (ch === ":") {
      fields.push(cur)
      cur = ""
    } else {
      cur += ch
    }
  }
  fields.push(cur)
  return fields
}

// `ip -j route show dev X` / `ip -j route show` -> destination list.
// "default" is normalised to 0.0.0.0/0.
function routeDestinations(json) {
  var rows
  try { rows = JSON.parse(json) } catch (e) { return [] }
  if (!(rows instanceof Array)) return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var dst = String(rows[i].dst || "")
    if (dst === "") continue
    if (dst === "default") dst = "0.0.0.0/0"
    if (out.indexOf(dst) === -1) out.push(dst)
  }
  return out
}

// A tunnel takes all traffic when it owns the default route, or the
// 0.0.0.0/1 + 128.0.0.0/1 pair (wg-quick, OpenVPN redirect-gateway) that
// outranks it without replacing it. Same for IPv6 (::/0, ::/1 + 8000::/1).
function isFullTunnel(routes) {
  var r = routes || []
  function has(x) { return r.indexOf(x) !== -1 }
  if (has("0.0.0.0/0") || has("::/0")) return true
  if (has("0.0.0.0/1") && has("128.0.0.0/1")) return true
  if (has("::/1") && has("8000::/1")) return true
  return false
}

// Short route description for a row: what this tunnel actually carries.
function routeSummary(routes, fullTunnel) {
  var r = routes || []
  if (fullTunnel) return "all traffic"
  if (r.length === 0) return ""
  if (r.length <= 2) return r.join(", ")
  return r.slice(0, 2).join(", ") + " +" + (r.length - 2)
}

// Tunnels may be combined freely. Only two *full* tunnels at once is worth a
// word: they fight over the default route. Returns "" when all is well.
function conflictWarning(tunnels) {
  var full = (tunnels || []).filter(function(t) { return t.up && t.fullTunnel })
  if (full.length < 2) return ""
  return full.map(function(t) { return t.label }).join(" and ") + " both route all traffic"
}

// Mullvad's firewall drops everything that is not the Mullvad tunnel, which
// includes the handshake packets another VPN sends to its own endpoint.
function mullvadShadowsOthers(tunnels) {
  var list = tunnels || []
  var mullvadUp = list.some(function(t) { return t.backend === "mullvad" && t.up })
  var othersUp = list.some(function(t) { return t.backend !== "mullvad" && t.up })
  return mullvadUp && othersUp
}

function sortTunnels(tunnels) {
  return (tunnels || []).slice().sort(function(a, b) {
    if (a.up !== b.up) return a.up ? -1 : 1
    return String(a.label).localeCompare(String(b.label))
  })
}

// Accept routes as an array of cidrs or as `ip -j route` JSON text.
function asRoutes(x) {
  return x instanceof Array ? x : routeDestinations(x)
}

// `ip -j [-6] route show table all` -> { device: [cidr] }.
// Only unicast routes count: `table all` also lists local/broadcast/multicast
// entries and link-local noise that say nothing about where traffic goes.
function routesByDevice(json4, json6) {
  var out = {}
  function add(json, family) {
    var rows
    try { rows = JSON.parse(json) } catch (e) { return }
    if (!(rows instanceof Array)) return
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      if (r.type && r.type !== "unicast") continue
      var dev = String(r.dev || "")
      var dst = String(r.dst || "")
      if (dev === "" || dst === "") continue
      if (dst === "default") dst = family === 6 ? "::/0" : "0.0.0.0/0"
      if (/^(fe80:|ff00:)/i.test(dst)) continue
      if (!out[dev]) out[dev] = []
      if (out[dev].indexOf(dst) === -1) out[dev].push(dst)
    }
  }
  add(json4, 4)
  add(json6, 6)
  return out
}

// Poll output is `@@NAME` marker lines followed by that command's output.
function parseSections(text) {
  var out = {}
  var name = null
  var buf = []
  var lines = String(text || "").split("\n")
  function flush() { if (name !== null) out[name] = buf.join("\n") }
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^@@(\w+)\s*$/)
    if (m) { flush(); name = m[1]; buf = [] }
    else buf.push(lines[i])
  }
  flush()
  return out
}
