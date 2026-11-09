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

// Reads the 802.1X trust settings of saved profiles, so the panel can refuse
// to activate one that would send a password to an unverified server.
// Arguments, one of:
//   ssid <name>     every Wi-Fi profile for that SSID
//   uuid <uuid>     that one profile
//   active          every active Wi-Fi profile
//   type <type>     every profile of that connection type
//   device <dev>    every profile `nmcli device connect <dev>` could pick
// Output: per profile `nmcli -t` field lines then `--`, and `done` once
// everything was read. Any nmcli failure exits non-zero before `done`.
// SSIDs are compared raw (--escape no), keeping `:` and `\` intact.
var CHECK_FIELDS = "connection.uuid,connection.type,connection.timestamp,connection.autoconnect," +
  "connection.interface-name,802-11-wireless.mode," +
  "802-11-wireless-security.key-mgmt,802-1x.eap,802-1x.domain-suffix-match," +
  "802-1x.domain-match,802-1x.altsubject-matches,802-1x.ca-cert,802-1x.system-ca-certs"

var CHECK_SCRIPT =
  "set -o pipefail\n" +
  "show() { nmcli -t -f " + CHECK_FIELDS + " connection show uuid \"$1\" || exit 1; echo --; }\n" +
  "case \"$1\" in\n" +
  "uuid) show \"$2\" ;;\n" +
  "ssid|active|type|device)\n" +
  "  want=802-11-wireless\n" +
  "  if [ \"$1\" = type ]; then want=$2\n" +
  "  elif [ \"$1\" = device ]; then\n" +
  "    dt=$(nmcli -e no -g GENERAL.TYPE device show \"$2\") || exit 1\n" +
  "    case \"$dt\" in wifi) want=802-11-wireless ;; ethernet) want=802-3-ethernet ;; *) want=$dt ;; esac\n" +
  "  fi\n" +
  "  if [ \"$1\" = active ]; then list=$(nmcli -t -f uuid,type connection show --active) || exit 1\n" +
  "  else list=$(nmcli -t -f uuid,type connection show) || exit 1; fi\n" +
  "  while IFS=: read -r u t; do\n" +
  "    [ -n \"$u\" ] && [ \"$t\" = \"$want\" ] || continue\n" +
  "    if [ \"$1\" = ssid ]; then\n" +
  "      s=$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid \"$u\"; r=$?; printf x; exit $r) || exit 1\n" +
  "      s=${s%x}; s=${s%$'\\n'}\n" +
  "      [ \"$s\" = \"$2\" ] || continue\n" +
  "    fi\n" +
  "    show \"$u\"\n" +
  "  done <<< \"$list\" ;;\n" +
  "*) exit 2 ;;\n" +
  "esac\n" +
  "echo done\n"

// Turns automatic connection off for each UUID given; stops at the first
// failure so the caller never reports it done when it is not.
var AUTOCONNECT_OFF_SCRIPT =
  "for u; do nmcli connection modify uuid \"$u\" connection.autoconnect no >/dev/null || exit 1; done"

// Profiles that NetworkManager could still join on its own.
function autoconnecting(p) { return ((p && p.f) || {})["connection.autoconnect"] !== "no" }

// CHECK_SCRIPT output -> [{ uuid, type, timestamp, f }], or null when the
// output is incomplete or malformed. Callers treat null as "do not connect".
function parseProfiles(text) {
  var lines = String(text || "").split("\n")
  while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
  if (lines.length === 0 || lines[lines.length - 1] !== "done") return null
  lines.pop()
  var out = []
  var cur = {}
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "--") {
      if (!validUuid(cur["connection.uuid"]) || !cur["connection.type"]) return null
      out.push({ uuid: cur["connection.uuid"], type: cur["connection.type"],
                 timestamp: Number(cur["connection.timestamp"]) || 0, f: cur })
      cur = {}
      continue
    }
    var at = line.indexOf(":")
    if (at <= 0) return null
    cur[line.slice(0, at)] = line.slice(at + 1).trim()
  }
  if (Object.keys(cur).length > 0) return null
  return out
}

var EAP_KEY_MGMT = ["wpa-eap", "wpa-eap-suite-b-192", "ieee8021x"]

// EAP methods that authenticate the server with its certificate, and so are
// safe once that certificate is pinned. EAP-TLS sends no password at all.
// EAP-FAST is left out: its PAC provisioning modes can skip the server
// certificate entirely, so CA and name fields do not protect it.
// Anything else (MD5 and LEAP have no server authentication; unknown methods
// are not trusted) makes the profile unpinned whatever else it sets, because
// NetworkManager may fall back to any method the profile allows.
var CERT_EAP = ["peap", "ttls"]

// True when activating this profile could send credentials (or, for EAP-TLS,
// all traffic) to whoever answers as the network. An 802.1X profile is only
// trusted when every method it allows is EAP-TLS, PEAP or TTLS, it checks the
// server (domain-suffix-match, domain-match or altsubject-matches;
// subject-match is a substring test and does not count) and it has a CA to
// chain to. Missing or unreadable 802.1X data is unpinned.
function profileUnpinned(p) {
  var f = (p && p.f) || {}
  var mgmt = String(f["802-11-wireless-security.key-mgmt"] || "").toLowerCase()
  var has8021x = f["802-1x.eap"] !== undefined
  if (!has8021x && EAP_KEY_MGMT.indexOf(mgmt) === -1) return false
  // nmcli lists methods comma-separated; accept `;` too.
  var methods = String(f["802-1x.eap"] || "").split(/[,;]/)
    .map(function(m) { return m.trim().toLowerCase() }).filter(Boolean)
  if (methods.length === 0) return true
  if (!methods.every(function(m) { return m === "tls" || CERT_EAP.indexOf(m) !== -1 })) return true
  var hasCa = String(f["802-1x.ca-cert"] || "") !== "" || f["802-1x.system-ca-certs"] === "yes"
  var hasName = ["802-1x.domain-suffix-match", "802-1x.domain-match", "802-1x.altsubject-matches"]
    .some(function(k) { return String(f[k] || "") !== "" })
  return !(hasCa && hasName)
}

// A profile that logs in with a client certificate (EAP-TLS). The panel's
// form makes PEAP profiles, so it cannot replace one of these; the user has
// to add the CA and server name to it instead.
function usesCertificateLogin(p) {
  return String(((p && p.f) || {})["802-1x.eap"] || "").toLowerCase().split(/[,;]/)
    .some(function(m) { return m.trim() === "tls" })
}

// Of the profiles for one network, the one to activate on `device`: a client
// (infrastructure) profile not bound to another interface, most recently used
// first. Null when there is none. Callers check none is unpinned first.
function pickProfile(list, device) {
  var best = null
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var f = p.f || {}
    var mode = String(f["802-11-wireless.mode"] || "")
    var ifname = String(f["connection.interface-name"] || "")
    if (p.type !== "802-11-wireless") continue
    if (mode !== "" && mode !== "infrastructure") continue
    if (ifname !== "" && ifname !== device) continue
    if (!best || p.timestamp > best.timestamp) best = p
  }
  return best
}

// uuids safe to hand to nmcli as arguments
function validUuid(u) {
  return /^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$/.test(String(u || ""))
}
