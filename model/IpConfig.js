.pragma library

// IPv4 settings for a NetworkManager connection: validate what the user typed
// and build the nmcli commands. Pure functions. Every value that reaches an
// argv is validated here first; nothing is ever passed through a shell.

function isIPv4(s) {
  var m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(String(s || "").trim())
  if (!m) return false
  for (var i = 1; i <= 4; i++) {
    // "010" is octal to some parsers and decimal to others: refuse it.
    if (m[i].length > 1 && m[i].charAt(0) === "0") return false
    if (Number(m[i]) > 255) return false
  }
  return true
}

function toInt(s) {
  var p = String(s).trim().split(".").map(Number)
  return ((p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]) >>> 0
}

// "255.255.255.0", "24" or "/24" -> prefix length 1..32, or -1.
function parseNetmask(s) {
  var t = String(s || "").trim()
  if (/^\/?\d{1,2}$/.test(t)) {
    var p = Number(t.replace("/", ""))
    return p >= 1 && p <= 32 ? p : -1
  }
  if (!isIPv4(t)) return -1
  var inv = (~toInt(t)) >>> 0
  if (((inv + 1) & inv) !== 0) return -1 // holes in the mask
  var n = 32
  while (inv > 0) { inv = inv >>> 1; n-- }
  return n >= 1 ? n : -1
}

function prefixToNetmask(prefix) {
  var p = Number(prefix)
  if (!(p >= 0 && p <= 32)) return ""
  var mask = p === 0 ? 0 : ((0xFFFFFFFF << (32 - p)) >>> 0)
  return [mask >>> 24, (mask >>> 16) & 255, (mask >>> 8) & 255, mask & 255].join(".")
}

function sameSubnet(a, b, prefix) {
  var mask = prefix === 0 ? 0 : ((0xFFFFFFFF << (32 - prefix)) >>> 0)
  return ((toInt(a) & mask) >>> 0) === ((toInt(b) & mask) >>> 0)
}

function parseDnsList(s) {
  return String(s || "").split(/[\s,;]+/).filter(function(x) { return x !== "" })
}

// form: { address, netmask, gateway, dns }  (all strings, as typed)
// -> { ok, errors: { field: message }, value: { address, prefix, gateway, dns[] } }
function validateStatic(form) {
  var errors = {}
  var address = String(form.address || "").trim()
  var gateway = String(form.gateway || "").trim()
  var prefix = parseNetmask(form.netmask)
  var dns = parseDnsList(form.dns)

  if (address === "") errors.address = "Enter an IP address"
  else if (!isIPv4(address)) errors.address = "Not a valid IPv4 address"
  else {
    var first = Number(address.split(".")[0])
    if (first === 0 || first === 127 || first >= 224) errors.address = "Not a usable host address"
  }

  if (String(form.netmask || "").trim() === "") errors.netmask = "Enter a netmask, like 255.255.255.0 or 24"
  else if (prefix < 0) errors.netmask = "Not a valid netmask"

  if (gateway === "") errors.gateway = "Enter a default gateway"
  else if (!isIPv4(gateway)) errors.gateway = "Not a valid IPv4 address"
  else if (gateway === address) errors.gateway = "Gateway cannot be this machine"

  if (!errors.address && !errors.netmask) {
    var bits = 32 - prefix
    var host = toInt(address) & (bits === 0 ? 0 : ((1 << bits) - 1) >>> 0)
    var allOnes = bits === 0 ? 0 : (((1 << bits) - 1) >>> 0)
    if (prefix < 31 && (host === 0 || host === allOnes)) errors.address = "That is the network or broadcast address"
  }
  if (!errors.gateway && !errors.address && !errors.netmask && !sameSubnet(address, gateway, prefix))
    errors.gateway = "Gateway is outside " + address + "/" + prefix

  if (dns.length === 0) errors.dns = "Add at least one DNS server"
  else if (dns.length > 3) errors.dns = "At most three DNS servers"
  else if (!dns.every(isIPv4)) errors.dns = "Every DNS server must be an IPv4 address"

  var ok = Object.keys(errors).length === 0
  return {
    ok: ok,
    errors: errors,
    value: ok ? { address: address, prefix: prefix, gateway: gateway, dns: dns } : null
  }
}

// Commands (argv arrays, run in order) that apply the settings and
// re-activate the connection so they take effect now.
function applyCommands(uuid, method, value) {
  var base = ["nmcli", "connection", "modify", "uuid", uuid]
  var modify = method === "manual"
    ? base.concat(["ipv4.method", "manual",
        "ipv4.addresses", value.address + "/" + value.prefix,
        "ipv4.gateway", value.gateway,
        "ipv4.dns", value.dns.join(","),
        "ipv4.ignore-auto-dns", "yes"])
    : base.concat(["ipv4.method", "auto",
        "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", "",
        "ipv4.ignore-auto-dns", "no"])
  return [modify, ["nmcli", "connection", "up", "uuid", uuid]]
}

var SHOW_ARGS = function(uuid) {
  return ["nmcli", "-t", "-f", "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns", "connection", "show", "uuid", uuid]
}

// `nmcli -t -f ipv4.method,... connection show` -> current settings.
function parseSettings(text) {
  var out = { method: "auto", address: "", prefix: 0, gateway: "", dns: [] }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf(":")
    if (idx < 0) continue
    var key = lines[i].slice(0, idx)
    var val = lines[i].slice(idx + 1).replace(/\\:/g, ":").trim()
    if (val === "" || val === "--") continue
    if (key === "ipv4.method") out.method = val === "manual" ? "manual" : "auto"
    else if (key === "ipv4.addresses") {
      var m = /^(\d+\.\d+\.\d+\.\d+)\/(\d+)/.exec(val.split(",")[0].trim())
      if (m) { out.address = m[1]; out.prefix = Number(m[2]) }
    }
    else if (key === "ipv4.gateway") out.gateway = val
    else if (key === "ipv4.dns") out.dns = parseDnsList(val)
  }
  return out
}

// ---- DNS servers ----------------------------------------------------------

function isIPv6(s) {
  var t = String(s || "").trim()
  if (!/^[0-9a-fA-F:]+$/.test(t) || t.indexOf(":") === -1) return false
  if (t.split("::").length > 2 || /:::/.test(t)) return false
  var groups = t.split(":")
  if (groups.length > 8) return false
  if (t.indexOf("::") === -1 && groups.length !== 8) return false
  return groups.every(function(g) { return g.length <= 4 })
}

// Free text -> { ok, servers, error }. IPv4 or IPv6, up to four.
function parseDnsServers(text) {
  var list = parseDnsList(text)
  if (list.length === 0) return { ok: false, servers: [], error: "Enter at least one DNS server" }
  if (list.length > 4) return { ok: false, servers: [], error: "At most four DNS servers" }
  for (var i = 0; i < list.length; i++)
    if (!isIPv4(list[i]) && !isIPv6(list[i])) return { ok: false, servers: [], error: list[i] + " is not an IP address" }
  return { ok: true, servers: list, error: "" }
}
