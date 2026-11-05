.pragma library

// Made-up machine for screenshots and development: no real names, addresses
// or networks. Switched on from the state file (see StateStore, Panel); with
// it on, the widget shows this instead of polling and does nothing when
// clicked. Addresses are from the documentation ranges (RFC 5737, RFC 3849).

var NETWORK_POLL = [
  "@@SHOW",
  "GENERAL.DEVICE:enp5s0",
  "GENERAL.TYPE:ethernet",
  "GENERAL.STATE:100 (connected)",
  "GENERAL.CONNECTION:Wired connection 1",
  "GENERAL.CON-UUID:00000000-0000-4000-8000-000000000001",
  "GENERAL.HWADDR:02:00:5E:10:00:01",
  "GENERAL.MTU:1500",
  "IP4.ADDRESS[1]:192.168.1.20/24",
  "IP4.GATEWAY:192.168.1.1",
  "IP4.DNS[1]:192.168.1.1",
  "IP6.ADDRESS[1]:fd00:1234:5678:1::20/64",
  "",
  "GENERAL.DEVICE:wlan0",
  "GENERAL.TYPE:wifi",
  "GENERAL.STATE:100 (connected)",
  "GENERAL.CONNECTION:Home WiFi",
  "GENERAL.CON-UUID:00000000-0000-4000-8000-000000000002",
  "GENERAL.HWADDR:02:00:5E:10:00:02",
  "GENERAL.MTU:1500",
  "IP4.ADDRESS[1]:192.168.1.21/24",
  "IP4.GATEWAY:192.168.1.1",
  "IP4.DNS[1]:192.168.1.1",
  "IP6.ADDRESS[1]:fd00:1234:5678:1::21/64",
  "@@WIFI",
  "*:Home WiFi:78:WPA2 WPA3:866 Mbit/s:36:5180 MHz",
  "@@IW",
  "#DEV wlan0",
  "Connected to 02:00:5e:10:00:03 (on wlan0)",
  "\tfreq: 5180.0",
  "\tsignal: -52 dBm",
  "\ttx bitrate: 866.7 MBit/s 80MHz HE-MCS 9 HE-NSS 2 HE-GI 0 HE-DCM 0",
  "@@DNSP",
  "DHCP",
  "@@ROUTES",
  "[{\"dst\":\"default\",\"dev\":\"enp5s0\",\"metric\":100},{\"dst\":\"default\",\"dev\":\"wlan0\",\"metric\":600}]",
  "@@SPEED",
  "enp5s0 2500",
  ""
].join("\n")

var NETBIRD = JSON.stringify({
  daemonStatus: "Connected", netbirdIp: "100.64.1.10/16", fqdn: "demo-laptop.netbird.example",
  management: { url: "https://netbird.example.com:443", connected: true },
  peers: { total: 5, connected: 3, details: [
    { fqdn: "nas.netbird.example", netbirdIp: "100.64.1.21", status: "Connected", connectionType: "P2P", latency: 4000000 },
    { fqdn: "raspberrypi.netbird.example", netbirdIp: "100.64.1.22", status: "Connected", connectionType: "P2P", latency: 9000000 },
    { fqdn: "homeserver.netbird.example", netbirdIp: "100.64.1.23", status: "Connected", connectionType: "Relayed", latency: 38000000 },
    { fqdn: "desktop.netbird.example", netbirdIp: "100.64.1.24", status: "Idle", connectionType: "-", latency: 0 },
    { fqdn: "phone.netbird.example", netbirdIp: "100.64.1.25", status: "Idle", connectionType: "-", latency: 0 }
  ] }
})

var TAILSCALE = JSON.stringify({
  BackendState: "Running", AuthURL: "",
  TailscaleIPs: ["100.101.102.103"],
  Self: { HostName: "demo-laptop", DNSName: "demo-laptop.tail-demo.ts.net.", OS: "linux", TailscaleIPs: ["100.101.102.103"] },
  CurrentTailnet: { Name: "demo@example.com" },
  Peer: {
    "nodekey:1": { HostName: "nas", DNSName: "nas.tail-demo.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.1"], Online: true, CurAddr: "203.0.113.5:41641", ExitNodeOption: false },
    "nodekey:2": { HostName: "vps-frankfurt", DNSName: "vps-frankfurt.tail-demo.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.2"], Online: true, Relay: "fra", ExitNodeOption: true, ExitNode: false },
    "nodekey:3": { HostName: "vps-singapore", DNSName: "vps-singapore.tail-demo.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.3"], Online: true, CurAddr: "203.0.113.9:41641", ExitNodeOption: true, ExitNode: false },
    "nodekey:4": { HostName: "phone", DNSName: "phone.tail-demo.ts.net.", OS: "android", TailscaleIPs: ["100.100.1.4"], Online: false }
  }
})

var MULLVAD = JSON.stringify({
  state: "connected",
  details: { location: { city: "Gothenburg", country: "Sweden", ipv4: "203.0.113.7" }, locked_down: false }
})

var VPN_POLL = [
  "@@NM",
  "Wired connection 1:00000000-0000-4000-8000-000000000001:802-3-ethernet:enp5s0:activated:/run/NetworkManager/system-connections/Wired connection 1.nmconnection",
  "Office WireGuard:00000000-0000-4000-8000-000000000010:wireguard:wg-office:activated:/etc/NetworkManager/system-connections/office.nmconnection",
  "Travel WireGuard:00000000-0000-4000-8000-000000000011:wireguard:::/etc/NetworkManager/system-connections/travel.nmconnection",
  "Home OpenVPN:00000000-0000-4000-8000-000000000012:vpn:::/etc/NetworkManager/system-connections/home.nmconnection",
  "@@TS", TAILSCALE,
  "@@NB", NETBIRD,
  "@@NBN",
  "Available Networks:",
  "",
  "  - ID: Exit Node (exit-amsterdam)",
  "    Network: 0.0.0.0/0, ::/0",
  "    Status: Not Selected",
  "",
  "  - ID: Exit Node (exit-tokyo)",
  "    Network: 0.0.0.0/0, ::/0",
  "    Status: Not Selected",
  "",
  "@@INST", "netbird", "tailscale", "mullvad", "nmcli",
  "@@MV", MULLVAD,
  "@@MVR", "Generic constraints", "    Location:               city got, se",
  "@@MVS",
  "Block traffic when the VPN is disconnected: off",
  "Local network sharing setting: block",
  "Autoconnect: off",
  "@@LINKS",
  "[{\"ifname\":\"wg-office\"}]",
  "@@R4",
  "[{\"dst\":\"10.20.0.0/16\",\"dev\":\"wg-office\"},{\"dst\":\"100.64.0.0/16\",\"dev\":\"wt0\"},{\"dst\":\"100.64.0.0/10\",\"dev\":\"tailscale0\"}]",
  "@@R6", "[]",
  ""
].join("\n")

// Countries as [name, code, [[city, code, relays]]]; the relay list is the
// format `mullvad relay list` prints.
var COUNTRIES = [
  ["Australia", "au", [["Melbourne", "mel", 3], ["Sydney", "syd", 4]]],
  ["Austria", "at", [["Vienna", "vie", 3]]],
  ["Belgium", "be", [["Brussels", "bru", 2]]],
  ["Canada", "ca", [["Montreal", "yul", 3], ["Toronto", "yyz", 4], ["Vancouver", "van", 2]]],
  ["Denmark", "dk", [["Copenhagen", "cph", 3]]],
  ["Finland", "fi", [["Helsinki", "hel", 2]]],
  ["France", "fr", [["Paris", "par", 5]]],
  ["Germany", "de", [["Berlin", "ber", 3], ["Frankfurt", "fra", 6]]],
  ["Japan", "jp", [["Osaka", "osa", 3], ["Tokyo", "tyo", 4]]],
  ["Netherlands", "nl", [["Amsterdam", "ams", 8]]],
  ["Norway", "no", [["Oslo", "osl", 3]]],
  ["Sweden", "se", [["Gothenburg", "got", 3], ["Malmo", "mma", 2], ["Stockholm", "sto", 5]]],
  ["Switzerland", "ch", [["Zurich", "zrh", 4]]],
  ["United Kingdom", "gb", [["London", "lon", 7], ["Manchester", "mnc", 2]]]
]

var RELAY_LIST = COUNTRIES.map(function(c) {
  return c[0] + " (" + c[1] + ")\n" + c[2].map(function(city) {
    var lines = ["\t" + city[0] + " (" + city[1] + ") @ 0.0°N, 0.0°E"]
    for (var i = 1; i <= city[2]; i++)
      lines.push("\t\t" + c[1] + "-" + city[1] + "-wg-00" + i + " (203.0.113." + i + ", 2001:db8::" + i + ") - hosted by Example (rented)")
    return lines.join("\n")
  }).join("\n")
}).join("\n\n") + "\n"

var WIFI_NETWORKS = [
  { ssid: "Home WiFi", signal: 78, security: "Wpa2Psk", secured: true, enterprise: false, known: true, connected: true, busy: false },
  { ssid: "Cafe Guest", signal: 64, security: "Open", secured: false, enterprise: false, known: false, connected: false, busy: false },
  { ssid: "Neighbour 5G", signal: 51, security: "Wpa2Psk", secured: true, enterprise: false, known: false, connected: false, busy: false },
  { ssid: "Office Guest", signal: 44, security: "Wpa2Psk", secured: true, enterprise: false, known: true, connected: false, busy: false },
  { ssid: "Library", signal: 31, security: "Wpa2Eap", secured: true, enterprise: true, known: false, connected: false, busy: false }
]

// A gentle wave, so the sparklines have something to draw.
function wave(base, swing, n) {
  var out = []
  for (var i = 0; i < n; i++) out.push(Math.max(0, base + swing * Math.sin(i / 3.2) * Math.cos(i / 7)))
  return out
}

var STATS = {
  counters: {
    enp5s0: { rx: 9.6e9, tx: 2.4e8, rxPackets: 6000000, txPackets: 800000, rxErrs: 0, txErrs: 0, rxDrop: 0, txDrop: 0 },
    wlan0: { rx: 1.6e9, tx: 6.4e7, rxPackets: 1000000, txPackets: 90000, rxErrs: 0, txErrs: 0, rxDrop: 0, txDrop: 0 }
  },
  rates: { enp5s0: { rx: 2.4e6, tx: 1.9e5 }, wlan0: { rx: 3.2e4, tx: 2.1e3 } },
  history: {
    enp5s0: { rx: wave(2.2e6, 1.5e6, 40), tx: wave(1.8e5, 1.2e5, 40) },
    wlan0: { rx: wave(3.0e4, 2.0e4, 40), tx: wave(2.0e3, 1.5e3, 40) }
  }
}

var BAND = { band: "5", available: ["2.4", "5", "6"], selected: "auto" }

var STORE = {
  linkOpen: { enp5s0: true, wlan0: true },
  mullvadFavorites: ["se", "nl"]
}
