.pragma library
.import "Shared.js" as Shared
.import "Wifi.js" as Wifi

// General networking model: wired and wireless links, addresses, and traffic
// stats. Independent of the VPN models; the only thing shared is the nmcli
// terse splitter. Pure parsing, no QML.

var POLL_SCRIPT = [
  "t() { timeout 5 \"$@\" 2>/dev/null; }",
  "m() { printf '\\n@@%s\\n' \"$1\"; }",
  "m SHOW; t nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.CON-UUID,GENERAL.HWADDR,GENERAL.MTU,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS device show",
  "m WIFI; t nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY,RATE,CHAN,FREQ device wifi list --rescan no",
  "m IW; for w in /sys/class/net/*/wireless; do d=${w#/sys/class/net/}; d=${d%/wireless}; printf '#DEV %s\\n' \"$d\"; t iw dev \"$d\" link; done",
  "m DNSP; t omarchy-dns",
  "m ROUTES; t ip -j route show default",
  "m SPEED; for f in /sys/class/net/*/speed; do d=${f#/sys/class/net/}; printf '%s %s\\n' \"${d%/speed}\" \"$(cat \"$f\" 2>/dev/null)\"; done"
].join("\n")

var STATS_ARGS = ["cat", "/proc/net/dev"]

// ---- nmcli device show ----------------------------------------------------

// Records are separated by blank lines; each line is `KEY[n]:value`.
function parseDeviceShow(text) {
  var out = {}
  var cur = null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var f = Shared.splitTerse(line)
    var key = f[0].replace(/\[\d+\]$/, "")
    var val = f.slice(1).join(":").trim()
    if (key === "GENERAL.DEVICE") {
      cur = { device: val, type: "", state: "", connection: "", uuid: "", hwaddr: "", mtu: 0,
              ip4: [], ip6: [], gateway: "", dns: [] }
      out[val] = cur
      continue
    }
    if (!cur || val === "" || val === "--") continue
    if (key === "GENERAL.TYPE") cur.type = val
    else if (key === "GENERAL.STATE") cur.state = val
    else if (key === "GENERAL.CONNECTION") cur.connection = val
    else if (key === "GENERAL.CON-UUID") cur.uuid = val
    else if (key === "GENERAL.HWADDR") cur.hwaddr = val
    else if (key === "GENERAL.MTU") cur.mtu = parseInt(val, 10) || 0
    else if (key === "IP4.ADDRESS") cur.ip4.push(val)
    else if (key === "IP6.ADDRESS") cur.ip6.push(val)
    else if (key === "IP4.GATEWAY") cur.gateway = val
    else if (key === "IP4.DNS") cur.dns.push(val)
  }
  return out
}

// ---- Wi-Fi ----------------------------------------------------------------

function bandOf(freqMhz) {
  var f = Number(freqMhz)
  if (!f) return ""
  if (f < 3000) return "2.4 GHz"
  if (f < 5925) return "5 GHz"
  return "6 GHz"
}

// The access point we are associated with, or null.
function parseActiveAp(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "") continue
    var f = Shared.splitTerse(lines[i])
    if (f.length < 7 || f[0] !== "*") continue
    var freq = parseInt(f[6], 10) || 0
    return {
      ssid: f[1],
      signal: parseInt(f[2], 10) || 0,
      security: f[3],
      rate: f[4],
      channel: parseInt(f[5], 10) || 0,
      freq: freq,
      band: bandOf(freq)
    }
  }
  return null
}

function signalLabel(pct) {
  if (pct >= 75) return "Excellent"
  if (pct >= 55) return "Good"
  if (pct >= 35) return "Fair"
  return "Weak"
}

// ---- Links ----------------------------------------------------------------

// `/sys/class/net/<dev>/speed` lines, "<dev> <mbit>". -1 or empty: unknown.
function parseSpeeds(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\S+)\s+(\d+)\s*$/)
    if (m && Number(m[2]) > 0) out[m[1]] = Number(m[2])
  }
  return out
}

// Device with the lowest-metric default route carries the traffic.
function primaryDevice(routeJson, allowed) {
  var rows
  try { rows = JSON.parse(routeJson) } catch (e) { return "" }
  if (!(rows instanceof Array)) return ""
  var best = null
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i].dev) continue
    // A VPN with a default route is not the link carrying you to the internet.
    if (allowed && allowed.indexOf(String(rows[i].dev)) === -1) continue
    if (best === null || (rows[i].metric || 0) < (best.metric || 0)) best = rows[i]
  }
  return best ? String(best.dev) : ""
}

function formatSpeed(mbit) {
  if (!mbit) return ""
  if (mbit >= 1000) return (mbit / 1000).toFixed(mbit % 1000 === 0 ? 0 : 1) + " Gbit/s"
  return mbit + " Mbit/s"
}

// Only real links: skips loopback, docker/veth/bridges, tunnels, p2p-dev.
function isPhysical(rec) {
  if (rec.type !== "ethernet" && rec.type !== "wifi") return false
  if (/^(veth|docker|br-|virbr)/.test(rec.device)) return false
  if (/unmanaged/.test(rec.state)) return false
  return true
}

function isConnected(rec) {
  return /^100\b/.test(rec.state) || /\(connected/.test(rec.state)
}

// poll text -> { wired: [link], wireless: [link], primary }
// link: { device, connection, connected, ip4, ip6, gateway, dns, hwaddr, mtu,
//         speed, primary, ap }   (ap only on wireless)
function build(text) {
  var sec = Shared.parseSections(text)
  var devs = parseDeviceShow(sec.SHOW || "")
  var speeds = parseSpeeds(sec.SPEED || "")
  var physical = []
  for (var pn in devs) if (isPhysical(devs[pn])) physical.push(pn)
  var primary = primaryDevice(sec.ROUTES || "", physical)
  var ap = parseActiveAp(sec.WIFI || "")
  var iw = Wifi.parseIwSections(sec.IW || "")
  var wired = []
  var wireless = []
  for (var name in devs) {
    var d = devs[name]
    if (!isPhysical(d)) continue
    var link = {
      device: d.device,
      connection: d.connection,
      uuid: d.uuid,
      connected: isConnected(d),
      ip4: d.ip4,
      ip6: d.ip6.filter(function(a) { return !/^fe80:/i.test(a) }),
      gateway: d.gateway,
      dns: d.dns,
      hwaddr: d.hwaddr,
      mtu: d.mtu,
      speed: speeds[d.device] || 0,
      primary: d.device === primary,
      ap: null,
      wifi: iw[d.device] || null
    }
    if (d.type === "wifi") {
      link.ap = isConnected(d) ? ap : null
      wireless.push(link)
    } else {
      wired.push(link)
    }
  }
  return { wired: wired, wireless: wireless, primary: primary, dns: String(sec.DNSP || "").trim().split("\n")[0] }
}

// ---- Traffic stats --------------------------------------------------------

// /proc/net/dev -> { dev: { rx, tx, rxPackets, txPackets, rxErrs, txErrs, rxDrop, txDrop } }
function parseProcNetDev(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([^:\s]+):\s*(.*)$/)
    if (!m) continue
    var n = m[2].trim().split(/\s+/).map(Number)
    if (n.length < 16 || n.some(isNaN)) continue
    out[m[1]] = {
      rx: n[0], rxPackets: n[1], rxErrs: n[2], rxDrop: n[3],
      tx: n[8], txPackets: n[9], txErrs: n[10], txDrop: n[11]
    }
  }
  return out
}

// Bytes per second between two samples. A counter that went backwards (device
// reset) reads as 0 for that interval rather than a huge negative.
function rates(prev, cur, dtSec) {
  var out = {}
  if (!prev || !cur || !(dtSec > 0)) return out
  for (var dev in cur) {
    if (!(dev in prev)) continue
    out[dev] = {
      rx: Math.max(0, (cur[dev].rx - prev[dev].rx) / dtSec),
      tx: Math.max(0, (cur[dev].tx - prev[dev].tx) / dtSec)
    }
  }
  return out
}

// Rolling window for the sparkline.
function pushHistory(history, value, max) {
  var next = (history || []).concat([value])
  return next.length > max ? next.slice(next.length - max) : next
}

function formatBytes(n) {
  var v = Number(n) || 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return (i === 0 ? String(Math.round(v)) : v.toFixed(v >= 100 ? 0 : 1)) + " " + units[i]
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

// ---- Wi-Fi sharing --------------------------------------------------------

function validDevice(name) { return /^[A-Za-z0-9_.-]{1,15}$/.test(String(name || "")) }

// `omarchy-network-qr --meta <dev>`:
//   meta<TAB>iface<TAB>security<TAB>ssid
//   0101...        (one row of modules per line, 1 = dark)
// -> { iface, security, ssid, rows } or null if it is not a square matrix.
function parseQr(text) {
  var lines = String(text || "").split("\n")
  var meta = null
  var rows = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "")
    if (line.indexOf("meta\t") === 0) {
      var f = line.split("\t")
      meta = { iface: f[1] || "", security: f[2] || "", ssid: f.slice(3).join("\t") }
    } else if (/^[01]+$/.test(line)) {
      rows.push(line)
    }
  }
  if (!meta || rows.length < 21) return null
  for (var r = 0; r < rows.length; r++) if (rows[r].length !== rows.length) return null
  meta.rows = rows
  return meta
}

// ---- Wi-Fi band -----------------------------------------------------------
//
// `omarchy-network-band`:
//   band<TAB>5
//   available<TAB>2.4 5
//   selected<TAB>auto

function parseBand(text) {
  var out = { band: "", available: [], selected: "auto" }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f[0] === "band") out.band = (f[1] || "").trim()
    else if (f[0] === "available") out.available = (f[1] || "").trim().split(/\s+/).filter(function(x) { return /^(2\.4|5|6)$/.test(x) })
    else if (f[0] === "selected") out.selected = (f[1] || "").trim() || "auto"
  }
  return out
}

function bandCommands(value) {
  if (!/^(auto|2\.4|5|6)$/.test(String(value))) return []
  return [["omarchy-network-band", String(value)]]
}

function bandLabel(v) { return v === "auto" ? "Auto" : v + " GHz" }

// ---- Speed test -----------------------------------------------------------

var PING_ARGS = ["ping", "-c", "8", "-i", "0.2", "-W", "2", "-q", "1.1.1.1"]
// The helper measures until it is killed; give each direction a fixed window.
function speedArgs(direction) {
  if (direction !== "down" && direction !== "up") return []
  return ["timeout", "-s", "TERM", "9", "omarchy-network-speedtest", direction]
}

// -> { loss, min, avg, max, jitter } in percent / ms, or null when nothing came back.
function parsePing(text) {
  var t = String(text || "")
  var loss = /([\d.]+)% packet loss/.exec(t)
  var rtt = /rtt min\/avg\/max\/mdev = ([\d.]+)\/([\d.]+)\/([\d.]+)\/([\d.]+)/.exec(t)
  if (!loss) return null
  if (!rtt) return { loss: Number(loss[1]), min: 0, avg: 0, max: 0, jitter: 0 }
  return { loss: Number(loss[1]), min: Number(rtt[1]), avg: Number(rtt[2]), max: Number(rtt[3]), jitter: Number(rtt[4]) }
}

// One Mbit/s figure per second. The first seconds are ramp-up, so they are
// dropped; the rest are averaged. Returns { mbps, peak } or null.
function speedFromSamples(text) {
  var nums = String(text || "").split("\n").map(function(l) { return parseFloat(l) }).filter(function(n) { return !isNaN(n) })
  if (nums.length === 0) return null
  var steady = nums.length > 3 ? nums.slice(2) : nums
  var sum = steady.reduce(function(a, b) { return a + b }, 0)
  return { mbps: sum / steady.length, peak: Math.max.apply(null, nums) }
}

function formatMbps(v) {
  var n = Number(v) || 0
  if (n >= 1000) return (n / 1000).toFixed(2) + " Gbit/s"
  return (n < 10 ? n.toFixed(1) : Math.round(n)) + " Mbit/s"
}

// ---- DNS presets ----------------------------------------------------------
//
// Omarchy's own helper knows DHCP, Cloudflare, Google and Custom. Quad9 and
// OpenDNS go through Custom, which writes the same configuration; they are
// told apart again by the servers the primary link ends up with.

var DNS_PRESETS = {
  Quad9: {
    v4: ["9.9.9.9", "149.112.112.112"],
    servers: ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"]
  },
  OpenDNS: {
    v4: ["208.67.222.222", "208.67.220.220"],
    servers: ["208.67.222.222", "208.67.220.220", "2620:119:35::35", "2620:119:53::53"]
  }
}

// The provider to show: Omarchy's word, unless it says Custom and the active
// IPv4 servers are exactly one of ours.
function resolveDnsProvider(reported, activeV4) {
  if (reported !== "Custom") return reported
  var active = (activeV4 || []).slice().sort().join(",")
  for (var name in DNS_PRESETS)
    if (DNS_PRESETS[name].v4.slice().sort().join(",") === active) return name
  return "Custom"
}
