.pragma library

// Wi-Fi generation from `iw dev <dev> link`. The kernel reports the PHY mode
// in the bitrate line: EHT = Wi-Fi 7, HE = 6 (6E on the 6 GHz band),
// VHT = 5, plain MCS = 4. Anything older has no marker and reads as 0.

function parseIwLink(text) {
  var t = String(text || "")
  if (t === "" || /Not connected/i.test(t)) return null
  var freq = Number((/freq:\s*([\d.]+)/.exec(t) || [])[1]) || 0
  var dbm = Number((/signal:\s*(-?\d+)/.exec(t) || [])[1])
  var tx = (/tx bitrate:\s*(.+)/.exec(t) || [])[1] || ""
  var rx = (/rx bitrate:\s*(.+)/.exec(t) || [])[1] || ""

  function gen(line) {
    if (/EHT-MCS/.test(line)) return 7
    if (/HE-MCS/.test(line)) return 6
    if (/VHT-MCS/.test(line)) return 5
    if (/\bMCS\s+\d/.test(line)) return 4
    return 0
  }
  var g = Math.max(gen(tx), gen(rx))
  var six = g === 6 && freq >= 5925
  return {
    gen: g,
    short: g === 0 ? "" : (six ? "6E" : String(g)),
    label: g === 0 ? "" : "Wi-Fi " + (six ? "6E" : g),
    freq: freq,
    signalDbm: isNaN(dbm) ? 0 : dbm,
    txRate: tx.split(/\s+MCS|\s+\w+-MCS/)[0].replace(/\s+\d+MHz.*$/, "").trim()
  }
}

// `#DEV <name>` marker lines, each followed by that device's `iw` output.
function parseIwSections(text) {
  var out = {}
  var name = null
  var buf = []
  function flush() { if (name !== null) out[name] = parseIwLink(buf.join("\n")) }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^#DEV (\S+)$/.exec(lines[i])
    if (m) { flush(); name = m[1]; buf = [] } else buf.push(lines[i])
  }
  flush()
  return out
}

// ---- Hidden networks ------------------------------------------------------

// 1 to 32 bytes, no control characters: what an SSID may be.
function validSsid(ssid) {
  var t = String(ssid || "")
  if (t.length === 0 || t.length > 32) return false
  return !/[\u0000-\u001f\u007f]/.test(t)
}

// ---- Enterprise trust -----------------------------------------------------
//
// PEAP/MSCHAPv2 sends a password-equivalent to whatever answers as the
// network. A profile is only safe when it pins the RADIUS server: its
// certificate name must match, and it must chain to a known CA.

// Host name (or suffix) the RADIUS certificate must match, e.g.
// "radius.example.edu". Letters, digits, dots and hyphens only.
function validServerName(name) {
  var t = String(name || "").trim()
  if (t.length === 0 || t.length > 253) return false
  return /^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$/.test(t)
}

// Optional CA certificate file. Empty means "the system CA bundle". Otherwise
// an absolute path to a certificate file, with no shell or control characters.
function validCaPath(path) {
  var t = String(path || "")
  if (t === "") return true
  if (t.length > 4096) return false
  return /^\/[A-Za-z0-9._\/+@~-]+\.(pem|crt|cer|der)$/.test(t) && t.indexOf("..") === -1
}

var HIDDEN_SECURITY = ["wpa-psk", "sae", "open"]

// WifiSecurityType names -> what people call them.
function securityLabel(name) {
  var labels = {
    Open: "Open", Owe: "Enhanced Open", StaticWep: "WEP", DynamicWep: "WEP",
    WpaPsk: "WPA", Wpa2Psk: "WPA2", Sae: "WPA3", WpaEap: "WPA Enterprise",
    Wpa2Eap: "WPA2 Enterprise", Wpa3SuiteB192: "WPA3 Enterprise"
  }
  return labels[name] || ""
}

// Saved profiles for one SSID, read back from nmcli. Input is the output of
// the script in WifiController: per profile a `uuid=<uuid>` line, then
// `field:value` lines (nmcli -t), then `--`.
function parseProfiles(text) {
  var out = []
  var cur = null
  String(text || "").split("\n").forEach(function(line) {
    if (line.indexOf("uuid=") === 0) { cur = { uuid: line.slice(5).trim(), f: {} }; return }
    if (line === "--") { if (cur) out.push(cur); cur = null; return }
    if (!cur) return
    var i = line.indexOf(":")
    if (i > 0) cur.f[line.slice(0, i)] = line.slice(i + 1).trim()
  })
  return out
}

// EAP methods that hand a password-equivalent to the server.
var PASSWORD_EAP = ["peap", "ttls", "fast", "leap", "pwd", "md5"]

// True when activating this profile would send credentials to whoever answers
// as the network: a password EAP method with no CA to chain to, or no expected
// server name. Profiles that are not 802.1x password profiles are fine.
function profileUnpinned(p) {
  var f = p.f || {}
  var methods = String(f["802-1x.eap"] || "").split(";").map(function(m) { return m.trim().toLowerCase() }).filter(Boolean)
  if (!methods.some(function(m) { return PASSWORD_EAP.indexOf(m) !== -1 })) return false
  var hasCa = String(f["802-1x.ca-cert"] || "") !== "" || f["802-1x.system-ca-certs"] === "yes"
  var hasName = ["802-1x.domain-suffix-match", "802-1x.domain-match", "802-1x.altsubject-matches", "802-1x.subject-match"]
    .some(function(k) { return String(f[k] || "") !== "" })
  return !(hasCa && hasName)
}

// uuids safe to hand to nmcli as arguments
function validUuid(u) {
  return /^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(String(u || ""))
}
