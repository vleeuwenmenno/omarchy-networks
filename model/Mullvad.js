.pragma library
.import "Shared.js" as Shared

// Mullvad backend model. Mullvad is a full tunnel by design, so it is the one
// backend where "connect alongside others" needs a caveat: its firewall blocks
// anything outside the tunnel (see Shared.mullvadShadowsOthers).

var STATUS_ARGS = ["mullvad", "status", "--json"]
var CONNECT_ARGS = ["mullvad", "connect"]
var DISCONNECT_ARGS = ["mullvad", "disconnect"]
var DEVICE = "wg0-mullvad"
var RELAY_LIST_ARGS = ["mullvad", "relay", "list"]
var RELAY_GET_ARGS = ["mullvad", "relay", "get"]

// -> unified tunnel, or null when the daemon is unreachable.
function parseStatus(json) {
  var s
  try { s = JSON.parse(json) } catch (e) { return null }
  if (!s || typeof s !== "object") return null
  var state = String(s.state || "")
  var up = state === "connected"
  var connecting = state === "connecting"
  var loc = (s.details && s.details.location) || {}
  var detail = ""
  if (up) {
    detail = [loc.city, loc.country].filter(function(x) { return x }).join(", ")
    if (loc.ipv4) detail += (detail ? " · " : "") + loc.ipv4
  } else if (connecting) {
    detail = "Connecting"
  } else if (state === "error") {
    detail = "Blocked (error state)"
  }
  return {
    id: "mullvad",
    backend: "mullvad",
    label: "Mullvad",
    kind: "mullvad",
    up: up,
    connecting: connecting,
    device: up ? DEVICE : "",
    // Mullvad installs the default route itself; no need to ask ip.
    routes: up ? ["0.0.0.0/0"] : [],
    fullTunnel: up,
    detail: detail,
    lockedDown: !!(s.details && s.details.locked_down)
  }
}

// ---- Locations ------------------------------------------------------------
//
// `mullvad relay list`:
//
//   Albania (al)
//   <tab>Tirana (tia) @ 41.3°N, 19.8°W
//   <tab><tab>al-tia-wg-001 (45.142.26.2, ...) - hosted by iRegister (rented)

// -> [{ code, name, relays, cities: [{ code, name, relays }] }], by name.
function parseRelays(text) {
  var out = []
  var country = null
  var city = null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    var c = /^(\S.*?) \(([a-z0-9-]+)\)\s*$/.exec(line)
    if (c) {
      country = { code: c[2], name: c[1], relays: 0, cities: [] }
      out.push(country)
      city = null
      continue
    }
    var t = /^\t([^\t].*?) \(([a-z0-9-]+)\) @ /.exec(line)
    if (t && country) {
      city = { code: t[2], name: t[1], relays: 0 }
      country.cities.push(city)
      continue
    }
    if (/^\t\t\S/.test(line) && country && city) {
      city.relays++
      country.relays++
    }
  }
  out.sort(function(a, b) { return a.name.localeCompare(b.name) })
  return out
}

// `mullvad relay get` -> the stored location: { country, city } (codes, "" when
// not constrained), or { hostname } when a single server is pinned.
function parseRelayGet(text) {
  var m = /Location:\s+(.+)/.exec(String(text || ""))
  var out = { country: "", city: "", hostname: "" }
  if (!m) return out
  var v = m[1].trim()
  var city = /^city\s+(\S+),\s*(\S+)$/.exec(v)
  var country = /^country\s+(\S+)$/.exec(v)
  var host = /^hostname\s+(\S+)$/.exec(v)
  if (city) { out.city = city[1]; out.country = city[2] }
  else if (country) out.country = country[1]
  else if (host) {
    out.hostname = host[1]
    var p = /^([a-z]+)-([a-z]+)-/.exec(host[1])
    if (p) { out.country = p[1]; out.city = p[2] }
  }
  return out
}

// Countries matching `query` (name, code, or any city). A country whose own
// name matches keeps all its cities; otherwise only the cities that matched.
// `cityOnly` marks the second case, so the UI can open it for you.
function filterCountries(list, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return (list || []).map(function(c) { return { country: c, cities: c.cities, cityOnly: false } })
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    var own = c.name.toLowerCase().indexOf(q) !== -1 || c.code === q
    if (own) { out.push({ country: c, cities: c.cities, cityOnly: false }); continue }
    var hits = c.cities.filter(function(ci) { return ci.name.toLowerCase().indexOf(q) !== -1 || ci.code === q })
    if (hits.length > 0) out.push({ country: c, cities: hits, cityOnly: true })
  }
  return out
}

function validCode(code) { return /^[a-z0-9][a-z0-9-]{1,7}$/.test(String(code || "")) }

// Set the location, then connect. Mullvad reconnects by itself when the
// location changes while connected; `connect` is then a no-op and still safe.
function connectToCommands(country, city) {
  if (!validCode(country) || (city && !validCode(city))) return []
  var set = ["mullvad", "relay", "set", "location", country]
  if (city) set.push(city)
  return [set, CONNECT_ARGS]
}

// ---- Settings -------------------------------------------------------------
//
//   Block traffic when the VPN is disconnected: off     (lockdown-mode get)
//   Local network sharing setting: block                 (lan get)
//   Autoconnect: off                                     (auto-connect get)

function parseSettings(text) {
  var t = String(text || "")
  function word(re) { var m = re.exec(t); return m ? m[1] : "" }
  return {
    lockdown: word(/disconnected:\s*(on|off)/i) === "on",
    lan: word(/Local network sharing setting:\s*(allow|block)/i) === "allow",
    autoconnect: word(/Autoconnect:\s*(on|off)/i) === "on"
  }
}

var SETTING_KEYS = ["lockdown", "lan", "autoconnect"]

function settingCommands(key, on) {
  if (key === "lockdown") return [["mullvad", "lockdown-mode", "set", on ? "on" : "off"]]
  if (key === "lan") return [["mullvad", "lan", "set", on ? "allow" : "block"]]
  if (key === "autoconnect") return [["mullvad", "auto-connect", "set", on ? "on" : "off"]]
  return []
}
