const test = require("node:test")
const strict = require("node:assert/strict")
// vm-sandbox arrays have a different prototype; compare structure via JSON.
const assert = { equal: strict.equal, deepEqual: (a, b) => strict.equal(JSON.stringify(a), JSON.stringify(b)) }
const { load } = require("./harness")

const Shared = load("Shared.js")
const NM = load("NetworkManager.js")
const NetBird = load("NetBird.js")
const Mullvad = load("Mullvad.js")
const WG = load("WireGuard.js")

const NMCLI = [
  "Wired connection 1:cccc3333:802-3-ethernet:enp5s0:activated:/run/NetworkManager/system-connections/Wired connection 1.nmconnection",
  "office:aaaa1111:wireguard:wg-office:activated:/etc/NetworkManager/system-connections/a.nmconnection",
  "lo:0117:loopback:lo:activated:/run/NetworkManager/system-connections/lo.nmconnection",
  "wt0:c136:wireguard:wt0:activated:/run/NetworkManager/system-connections/wt0.nmconnection",
  "travel:bbbb2222:wireguard:::/etc/NetworkManager/system-connections/b.nmconnection",
  "corp\\: vpn:77aa:vpn:tun0:activating:/etc/NetworkManager/system-connections/c.nmconnection",
].join("\n")

test("splitTerse unescapes colons", () => {
  assert.deepEqual(Shared.splitTerse("a\\:b:c"), ["a:b", "c"])
})

test("NM lists only wireguard/vpn profiles, skips volatile /run ones", () => {
  const t = NM.parseProfiles(NMCLI)
  assert.deepEqual(t.map((x) => x.label), ["office", "travel", "corp: vpn"])
  assert.equal(t[0].up, true)
  assert.equal(t[0].device, "wg-office")
  assert.equal(t[1].up, false)
  assert.equal(t[2].connecting, true)
  assert.equal(t[2].kind, "vpn")
})

test("split-tunnel routes are not a full tunnel", () => {
  const up = NM.parseProfiles(NMCLI)[0]
  const t = NM.withRoutes(up, '[{"dst":"10.20.0.0/16"}]')
  assert.equal(t.fullTunnel, false)
  assert.equal(t.detail, "10.20.0.0/16")
})

test("wg-quick style 0/1 + 128/1 pair counts as full tunnel", () => {
  assert.equal(Shared.isFullTunnel(["0.0.0.0/1", "128.0.0.0/1"]), true)
  assert.equal(Shared.isFullTunnel(["0.0.0.0/1"]), false)
  assert.equal(Shared.isFullTunnel(["default"].map(() => "0.0.0.0/0")), true)
})

test("route 'default' normalises", () => {
  assert.deepEqual(Shared.routeDestinations('[{"dst":"default"},{"dst":"10.0.0.0/8"}]'), ["0.0.0.0/0", "10.0.0.0/8"])
  assert.deepEqual(Shared.routeDestinations("garbage"), [])
})

test("NetBird status", () => {
  const t = NetBird.parseStatus(JSON.stringify({
    daemonStatus: "Connected", netbirdIp: "100.64.1.10/16",
    peers: { total: 7, connected: 3 }, networks: ["0.0.0.0/0"],
  }))
  assert.equal(t.up, true)
  assert.equal(t.detail, "100.64.1.10 · 3/7 peers")
  assert.equal(t.fullTunnel, false) // "networks" is availability, not selection
  assert.equal(NetBird.parseStatus("nope"), null)
  assert.equal(NetBird.parseStatus('{"daemonStatus":"NeedsLogin"}').needsLogin, true)
})

test("NetBird exit node shows as full tunnel via routes", () => {
  const t = NetBird.parseStatus('{"daemonStatus":"Connected","peers":{}}')
  const r = NetBird.withRoutes(t, '[{"dst":"default"}]')
  assert.equal(r.fullTunnel, true)
})

test("Mullvad status", () => {
  const d = Mullvad.parseStatus('{"state":"disconnected","details":{"location":{}}}')
  assert.equal(d.up, false)
  assert.equal(d.fullTunnel, false)
  const c = Mullvad.parseStatus(JSON.stringify({
    state: "connected",
    details: { location: { city: "Zurich", country: "Switzerland", ipv4: "1.2.3.4" } },
  }))
  assert.equal(c.up, true)
  assert.equal(c.fullTunnel, true)
  assert.equal(c.detail, "Zurich, Switzerland · 1.2.3.4")
})

test("WireGuard lists only unowned interfaces", () => {
  const names = WG.parseLinks('[{"ifname":"wt0"},{"ifname":"wg-office"},{"ifname":"home"},{"ifname":"x; rm -rf"}]')
  assert.deepEqual(names, ["wt0", "wg-office", "home"])
  const t = WG.fromLinks(names, ["wg-office"])
  assert.deepEqual(t.map((x) => x.id), ["wg:home"])
})

test("interface name validation rejects shell-ish input", () => {
  assert.equal(WG.validInterface("wg0"), true)
  assert.equal(WG.validInterface("a b"), false)
  assert.equal(WG.validInterface("../etc"), false)
  assert.equal(WG.validInterface("averyveryverylongname"), false)
})

test("several split tunnels at once: no conflict, nothing to warn", () => {
  const nm = NM.withRoutes(NM.parseProfiles(NMCLI)[0], '[{"dst":"10.20.0.0/16"}]')
  const nb = NetBird.withRoutes(NetBird.parseStatus('{"daemonStatus":"Connected","peers":{}}'), '[{"dst":"100.64.0.0/16"}]')
  assert.equal(Shared.conflictWarning([nm, nb]), "")
})

test("two full tunnels warn; Mullvad + others flagged as shadowing", () => {
  const mv = Mullvad.parseStatus('{"state":"connected","details":{"location":{}}}')
  const nb = NetBird.withRoutes(NetBird.parseStatus('{"daemonStatus":"Connected","peers":{}}'), '[{"dst":"default"}]')
  assert.equal(Shared.conflictWarning([mv, nb]), "Mullvad and NetBird both route all traffic")
  assert.equal(Shared.mullvadShadowsOthers([mv, nb]), true)
  assert.equal(Shared.mullvadShadowsOthers([mv]), false)
})

test("sortTunnels puts up first, then alphabetical", () => {
  const s = Shared.sortTunnels([
    { label: "b", up: false }, { label: "z", up: true }, { label: "a", up: false },
  ])
  assert.deepEqual(s.map((x) => x.label), ["z", "a", "b"])
})

const NETWORKS = `Available Networks:

  - ID: Exit Node (exit-amsterdam)
    Network: 0.0.0.0/0, ::/0
    Status: Selected

  - ID: Exit Node (exit-tokyo)
    Network: 0.0.0.0/0, ::/0
    Status: Not Selected

  - ID: office-lan
    Network: 10.50.0.0/24
    Status: Selected
`

test("NetBird parses networks and spots exit nodes", () => {
  const n = NetBird.parseNetworks(NETWORKS)
  assert.equal(n.length, 3)
  assert.equal(n[0].label, "exit-amsterdam")
  assert.equal(n[0].selected, true)
  assert.equal(n[0].exitNode, true)
  assert.equal(n[2].exitNode, false)
  assert.equal(NetBird.exitNodes(n).length, 2)
})

test("selecting an exit node deselects the other, never touches plain networks", () => {
  const n = NetBird.parseNetworks(NETWORKS)
  const cmds = NetBird.selectExitCommands(n, "Exit Node (exit-tokyo)")
  assert.deepEqual(cmds, [
    ["netbird", "networks", "deselect", "--", "Exit Node (exit-amsterdam)"],
    ["netbird", "networks", "select", "-a", "--", "Exit Node (exit-tokyo)"],
  ])
})

test("clearing exit nodes only deselects selected exit nodes", () => {
  const n = NetBird.parseNetworks(NETWORKS)
  assert.deepEqual(NetBird.clearExitCommands(n), [
    ["netbird", "networks", "deselect", "--", "Exit Node (exit-amsterdam)"],
  ])
})

test("selected exit node makes NetBird a full tunnel", () => {
  const base = NetBird.parseStatus('{"daemonStatus":"Connected","netbirdIp":"100.1.1.1/16","peers":{"total":2,"connected":1}}')
  const t = NetBird.withNetworks(base, NetBird.parseNetworks(NETWORKS))
  assert.equal(t.fullTunnel, true)
  assert.equal(t.currentExit, "Exit Node (exit-amsterdam)")
  assert.equal(t.exitNodes.length, 2)
  assert.equal(t.detail, "exit: exit-amsterdam · 100.1.1.1 · 1/2 peers")
})

test("no exit selected: NetBird stays split", () => {
  const base = NetBird.parseStatus('{"daemonStatus":"Connected","peers":{}}')
  const none = NETWORKS.replace("Status: Selected\n\n  - ID: Exit Node (exit-tokyo", "Status: Not Selected\n\n  - ID: Exit Node (exit-tokyo")
  const t = NetBird.withNetworks(base, NetBird.parseNetworks(none))
  assert.equal(t.fullTunnel, false)
  assert.equal(t.currentExit, "")
})

const Compose = load("Compose.js")

const POLL = `@@NM
${NMCLI}
@@NB
{"daemonStatus":"Connected","netbirdIp":"100.64.1.10/16","peers":{"total":7,"connected":3}}
@@NBN
${NETWORKS}
@@MV
{"state":"disconnected","details":{"location":{}}}
@@LINKS
[{"ifname":"wt0"},{"ifname":"wg-office"},{"ifname":"home"}]
@@R4
[{"dst":"default","dev":"enp5s0"},{"dst":"10.20.0.0/16","dev":"wg-office","protocol":"static"},
 {"dst":"100.64.0.0/16","dev":"wt0"},{"dst":"default","dev":"wt0","table":"7120"},
 {"dst":"127.0.0.1","dev":"lo","type":"local","table":"local"},{"dst":"10.9.0.0/24","dev":"home"}]
@@R6
[{"dst":"::/0","dev":"wt0","table":"7120"},{"dst":"fe80::/64","dev":"home"}]
`

test("routesByDevice skips local/link-local noise and normalises default", () => {
  const r = Shared.routesByDevice('[{"dst":"default","dev":"a"},{"dst":"1.1.1.1","dev":"lo","type":"local"}]', '[{"dst":"default","dev":"a"},{"dst":"fe80::/64","dev":"a"}]')
  assert.deepEqual(r, { a: ["0.0.0.0/0", "::/0"] })
})

test("compose: NM split tunnel, NetBird exit node, unowned WG, all at once", () => {
  const b = Compose.build(POLL)
  const by = Object.fromEntries(b.tunnels.map((t) => [t.id, t]))
  assert.equal(by["nm:aaaa1111"].up, true)
  assert.equal(by["nm:aaaa1111"].fullTunnel, false)
  assert.equal(by["nm:aaaa1111"].detail, "10.20.0.0/16")
  assert.equal(by["netbird"].fullTunnel, true)
  assert.equal(by["netbird"].currentExit, "Exit Node (exit-amsterdam)")
  assert.equal(by["wg:home"].up, true)
  assert.equal(by["wg:wg-office"], undefined) // owned by NM
  assert.equal(by["wg:wt0"], undefined) // owned by NetBird
  assert.equal(by["mullvad"].up, false)
  assert.equal(b.warning, "") // only NetBird is full
  assert.equal(b.note, "")
  assert.equal(b.tunnels[0].up, true) // sorted: connected first
})

test("compose: Mullvad up alongside others gets the note and a conflict", () => {
  const b = Compose.build(POLL.replace('"state":"disconnected"', '"state":"connected"'))
  assert.equal(b.warning, "NetBird and Mullvad both route all traffic")
  assert.equal(b.note.indexOf("Mullvad blocks"), 0)
})

test("compose: missing tools just yield no tunnels", () => {
  const b = Compose.build("@@NM\n@@NB\n@@MV\n")
  assert.equal(b.tunnels.length, 0)
})

test("compose: toggle commands per backend", () => {
  const b = Compose.build(POLL)
  const by = Object.fromEntries(b.tunnels.map((t) => [t.id, t]))
  assert.deepEqual(Compose.toggleCommands(by["nm:aaaa1111"]), [["nmcli", "connection", "down", "uuid", "aaaa1111"]])
  assert.deepEqual(Compose.toggleCommands(by["nm:bbbb2222"]), [["nmcli", "connection", "up", "uuid", "bbbb2222"]])
  assert.deepEqual(Compose.toggleCommands(by["netbird"]), [["netbird", "down"]])
  assert.deepEqual(Compose.toggleCommands(by["mullvad"]), [["mullvad", "connect"]])
  assert.deepEqual(Compose.toggleCommands(by["wg:home"]), [["pkexec", "wg-quick", "down", "home"]])
})

test("compose: clicking the selected exit node clears it, another switches", () => {
  const b = Compose.build(POLL)
  const nb = b.tunnels.find((t) => t.id === "netbird")
  assert.equal(Compose.exitCommands(b.networks, nb, "Exit Node (exit-amsterdam)").length, 1)
  assert.equal(Compose.exitCommands(b.networks, nb, "Exit Node (exit-amsterdam)")[0][2], "deselect")
  assert.equal(Compose.exitCommands(b.networks, nb, "Exit Node (exit-tokyo)").length, 2)
})

test("poll script: a tool without a trailing newline does not swallow the next marker", () => {
  const out = require("node:child_process").execFileSync("sh", ["-c", `
    ${Compose.POLL_SCRIPT.split("\n").slice(0, 3).join("\n")}
    m A; printf 'no-newline'
    m B; echo ok`]).toString()
  const s = Compose.parseSections(out)
  assert.equal(s.A.trim(), "no-newline")
  assert.equal(s.B.trim(), "ok")
})

const Network = load("Network.js")

const SHOW = `GENERAL.DEVICE:enp5s0
GENERAL.TYPE:ethernet
GENERAL.STATE:100 (connected)
GENERAL.CONNECTION:Wired connection 1
GENERAL.HWADDR:02\\:00\\:5E\\:10\\:00\\:01
GENERAL.MTU:1500
IP4.ADDRESS[1]:192.168.1.20/24
IP4.GATEWAY:192.168.1.1
IP4.DNS[1]:192.168.1.1
IP4.DNS[2]:1.1.1.1
IP6.ADDRESS[1]:fd1e::5a3/64
IP6.ADDRESS[2]:fe80::75cb/64

GENERAL.DEVICE:wlan0
GENERAL.TYPE:wifi
GENERAL.STATE:100 (connected)
GENERAL.CONNECTION:Home WiFi
GENERAL.HWADDR:AA:BB:CC:DD:EE:FF
GENERAL.MTU:1500
IP4.ADDRESS[1]:192.168.1.21/24
IP4.GATEWAY:192.168.1.1

GENERAL.DEVICE:wt0
GENERAL.TYPE:wireguard
GENERAL.STATE:100 (connected (externally))
GENERAL.CONNECTION:wt0

GENERAL.DEVICE:docker0
GENERAL.TYPE:bridge
GENERAL.STATE:100 (connected (externally))

GENERAL.DEVICE:veth7bd5e30
GENERAL.TYPE:ethernet
GENERAL.STATE:10 (unmanaged)
`

const NET_POLL = `@@SHOW
${SHOW}
@@WIFI
 :Neighbour 5G:90:WPA2 WPA3:1170 Mbit/s:36:5180 MHz
*:Home WiFi:55:WPA2 WPA3:540 Mbit/s:44:5220 MHz
@@ROUTES
[{"dst":"default","dev":"wlan0","metric":600},{"dst":"default","dev":"enp5s0","metric":100}]
@@SPEED
enp5s0 2500
wlan0 
lo 
`

test("network: only real links, split into wired and wireless", () => {
  const n = Network.build(NET_POLL)
  assert.deepEqual(n.wired.map((l) => l.device), ["enp5s0"])
  assert.deepEqual(n.wireless.map((l) => l.device), ["wlan0"])
  assert.equal(n.primary, "enp5s0")
})

test("network: wired details", () => {
  const w = Network.build(NET_POLL).wired[0]
  assert.equal(w.connected, true)
  assert.equal(w.primary, true)
  assert.deepEqual(w.ip4, ["192.168.1.20/24"])
  assert.deepEqual(w.ip6, ["fd1e::5a3/64"]) // link-local dropped
  assert.deepEqual(w.dns, ["192.168.1.1", "1.1.1.1"])
  assert.equal(w.gateway, "192.168.1.1")
  assert.equal(w.speed, 2500)
  assert.equal(w.hwaddr, "02:00:5E:10:00:01")
  assert.equal(Network.formatSpeed(w.speed), "2.5 Gbit/s")
})

test("network: wireless picks the associated AP, not the neighbours", () => {
  const w = Network.build(NET_POLL).wireless[0]
  assert.equal(w.primary, false)
  assert.equal(w.ap.ssid, "Home WiFi")
  assert.equal(w.ap.signal, 55)
  assert.equal(w.ap.band, "5 GHz")
  assert.equal(w.ap.channel, 44)
  assert.equal(Network.signalLabel(w.ap.signal), "Good")
})

test("network: no wifi hardware yields an empty wireless list", () => {
  const n = Network.build(NET_POLL.replace(/GENERAL.DEVICE:wlan0[\s\S]*?\n\n/, ""))
  assert.equal(n.wireless.length, 0)
})

test("network: disconnected wifi has no ap", () => {
  const n = Network.build(NET_POLL.replace("GENERAL.STATE:100 (connected)\nGENERAL.CONNECTION:Home", "GENERAL.STATE:30 (disconnected)\nGENERAL.CONNECTION:Home"))
  assert.equal(n.wireless[0].connected, false)
  assert.equal(n.wireless[0].ap, null)
})

test("network: bands", () => {
  assert.equal(Network.bandOf(2437), "2.4 GHz")
  assert.equal(Network.bandOf(5180), "5 GHz")
  assert.equal(Network.bandOf(6115), "6 GHz")
})

const PND = `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 221089649   63222    0    0    0     0          0         0 221089649   63222    0    0    0     0       0          0
enp5s0: 9384717743 6422726    0  844    0     0          0     15880 104646048  787596    1    2    0     0       0          0
`

test("traffic: /proc/net/dev parse", () => {
  const p = Network.parseProcNetDev(PND)
  assert.equal(p.enp5s0.rx, 9384717743)
  assert.equal(p.enp5s0.tx, 104646048)
  assert.equal(p.enp5s0.rxDrop, 844)
  assert.equal(p.enp5s0.txErrs, 1)
  assert.equal(p.lo.rx, 221089649)
})

test("traffic: rates, counter reset, zero interval", () => {
  const a = { eth: { rx: 1000, tx: 500 }, gone: { rx: 1, tx: 1 } }
  const b = { eth: { rx: 3000, tx: 500 }, new: { rx: 5, tx: 5 } }
  assert.deepEqual(Network.rates(a, b, 2), { eth: { rx: 1000, tx: 0 } })
  assert.deepEqual(Network.rates({ eth: { rx: 9, tx: 9 } }, { eth: { rx: 1, tx: 1 } }, 1), { eth: { rx: 0, tx: 0 } })
  assert.deepEqual(Network.rates(a, b, 0), {})
})

test("traffic: history window and formatting", () => {
  assert.deepEqual(Network.pushHistory([1, 2, 3], 4, 3), [2, 3, 4])
  assert.equal(Network.formatBytes(512), "512 B")
  assert.equal(Network.formatBytes(1536), "1.5 KB")
  assert.equal(Network.formatRate(5 * 1024 * 1024), "5.0 MB/s")
})

test("NetBird exposes peers, connected first, with names trimmed", () => {
  const t = NetBird.parseStatus(JSON.stringify({
    daemonStatus: "Connected", netbirdIp: "100.1.1.1/16", fqdn: "me.netbird.example",
    management: { url: "https://x", connected: true },
    peers: { total: 2, connected: 1, details: [
      { fqdn: "zzz.netbird.example", netbirdIp: "100.1.1.9", status: "Idle", connectionType: "-", latency: 0 },
      { fqdn: "srv.netbird.example", netbirdIp: "100.1.1.2", status: "Connected", connectionType: "P2P", latency: 12000000 },
    ] },
  }))
  assert.deepEqual(t.peers.map((p) => p.name), ["srv", "zzz"])
  assert.equal(t.peers[0].latencyMs, 12)
  assert.equal(t.peers[0].connectionType, "P2P")
  assert.equal(t.peers[1].connectionType, "")
  assert.equal(t.ip, "100.1.1.1")
  assert.equal(t.managementOk, true)
})

const IpConfig = load("IpConfig.js")
const Wifi = load("Wifi.js")

test("ip: IPv4 validation rejects junk and octal-looking octets", () => {
  assert.equal(IpConfig.isIPv4("192.168.1.10"), true)
  assert.equal(IpConfig.isIPv4("256.1.1.1"), false)
  assert.equal(IpConfig.isIPv4("192.168.01.10"), false)
  assert.equal(IpConfig.isIPv4("1.2.3"), false)
  assert.equal(IpConfig.isIPv4("1.2.3.4; reboot"), false)
})

test("ip: netmask accepts dotted, prefix and /prefix; rejects holes", () => {
  assert.equal(IpConfig.parseNetmask("255.255.255.0"), 24)
  assert.equal(IpConfig.parseNetmask("24"), 24)
  assert.equal(IpConfig.parseNetmask("/16"), 16)
  assert.equal(IpConfig.parseNetmask("255.255.255.252"), 30)
  assert.equal(IpConfig.parseNetmask("255.0.255.0"), -1)
  assert.equal(IpConfig.parseNetmask("0.0.0.0"), -1)
  assert.equal(IpConfig.parseNetmask("33"), -1)
  assert.equal(IpConfig.prefixToNetmask(24), "255.255.255.0")
  assert.equal(IpConfig.prefixToNetmask(20), "255.255.240.0")
})

const GOOD = { address: "192.168.1.50", netmask: "255.255.255.0", gateway: "192.168.1.1", dns: "1.1.1.1, 8.8.8.8" }

test("ip: valid static config", () => {
  const r = IpConfig.validateStatic(GOOD)
  assert.equal(r.ok, true)
  assert.deepEqual(r.value, { address: "192.168.1.50", prefix: 24, gateway: "192.168.1.1", dns: ["1.1.1.1", "8.8.8.8"] })
})

test("ip: each mistake reports on its own field", () => {
  assert.equal(IpConfig.validateStatic({ ...GOOD, address: "" }).errors.address, "Enter an IP address")
  assert.equal(IpConfig.validateStatic({ ...GOOD, netmask: "255.0.255.0" }).errors.netmask, "Not a valid netmask")
  assert.equal(IpConfig.validateStatic({ ...GOOD, gateway: "10.0.0.1" }).errors.gateway, "Gateway is outside 192.168.1.50/24")
  assert.equal(IpConfig.validateStatic({ ...GOOD, gateway: "192.168.1.50" }).errors.gateway, "Gateway cannot be this machine")
  assert.equal(IpConfig.validateStatic({ ...GOOD, address: "192.168.1.0" }).errors.address, "That is the network or broadcast address")
  assert.equal(IpConfig.validateStatic({ ...GOOD, address: "192.168.1.255" }).errors.address, "That is the network or broadcast address")
  assert.equal(IpConfig.validateStatic({ ...GOOD, address: "127.0.0.1" }).errors.address, "Not a usable host address")
  assert.equal(IpConfig.validateStatic({ ...GOOD, dns: "" }).errors.dns, "Add at least one DNS server")
  assert.equal(IpConfig.validateStatic({ ...GOOD, dns: "1.1.1.1 nope" }).errors.dns, "Every DNS server must be an IPv4 address")
  assert.equal(IpConfig.validateStatic({ ...GOOD, dns: "1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4" }).errors.dns, "At most three DNS servers")
})

test("ip: /31 point-to-point addresses are allowed", () => {
  const r = IpConfig.validateStatic({ address: "10.0.0.0", netmask: "31", gateway: "10.0.0.1", dns: "1.1.1.1" })
  assert.equal(r.ok, true)
})

test("ip: apply commands for static and DHCP", () => {
  const v = IpConfig.validateStatic(GOOD).value
  const m = IpConfig.applyCommands("u-1", "manual", v)
  assert.deepEqual(m[0], ["nmcli", "connection", "modify", "uuid", "u-1", "ipv4.method", "manual",
    "ipv4.addresses", "192.168.1.50/24", "ipv4.gateway", "192.168.1.1", "ipv4.dns", "1.1.1.1,8.8.8.8", "ipv4.ignore-auto-dns", "yes"])
  assert.deepEqual(m[1], ["nmcli", "connection", "up", "uuid", "u-1"])
  const a = IpConfig.applyCommands("u-1", "auto", null)
  assert.equal(a[0].includes("manual"), false)
  assert.equal(a[0][a[0].indexOf("ipv4.method") + 1], "auto")
})

test("ip: parse stored settings", () => {
  const s = IpConfig.parseSettings("ipv4.method:manual\nipv4.addresses:192.168.1.50/24\nipv4.gateway:192.168.1.1\nipv4.dns:1.1.1.1,8.8.8.8\n")
  assert.deepEqual(s, { method: "manual", address: "192.168.1.50", prefix: 24, gateway: "192.168.1.1", dns: ["1.1.1.1", "8.8.8.8"] })
  assert.equal(IpConfig.parseSettings("ipv4.method:auto\nipv4.addresses:\nipv4.gateway:\n").method, "auto")
})

test("wifi: generation from the iw bitrate line", () => {
  const he = Wifi.parseIwLink("Connected to aa (on wlp)\n\tfreq: 5220.0\n\tsignal: -77 dBm\n\ttx bitrate: 576.4 MBit/s 160MHz HE-MCS 3 HE-NSS 2 HE-GI 0 HE-DCM 0\n")
  assert.equal(he.gen, 6)
  assert.equal(he.label, "Wi-Fi 6")
  assert.equal(Wifi.parseIwLink("freq: 6115.0\ntx bitrate: 1200 MBit/s HE-MCS 9").label, "Wi-Fi 6E")
  assert.equal(Wifi.parseIwLink("freq: 5220.0\ntx bitrate: 2400 MBit/s EHT-MCS 11").short, "7")
  assert.equal(Wifi.parseIwLink("freq: 5180.0\ntx bitrate: 866.7 MBit/s VHT-MCS 9 80MHz").short, "5")
  assert.equal(Wifi.parseIwLink("freq: 2437.0\ntx bitrate: 144.4 MBit/s MCS 15 short GI").short, "4")
  assert.equal(Wifi.parseIwLink("freq: 2437.0\ntx bitrate: 54.0 MBit/s").gen, 0)
  assert.equal(Wifi.parseIwLink("Not connected."), null)
})

test("wifi: iw sections per device, and the link gets them", () => {
  const poll = NET_POLL.replace("@@ROUTES", "@@IW\n#DEV wlan0\nConnected to aa\n\tfreq: 5220.0\n\ttx bitrate: 100 MBit/s HE-MCS 3\n@@ROUTES")
  const n = Network.build(poll)
  assert.equal(n.wireless[0].wifi.label, "Wi-Fi 6")
  assert.equal(n.wired[0].wifi, null)
})

test("network: connection uuid is captured for later edits", () => {
  const poll = NET_POLL.replace("GENERAL.CONNECTION:Wired connection 1", "GENERAL.CONNECTION:Wired connection 1\nGENERAL.CON-UUID:cccc3333-21fd")
  assert.equal(Network.build(poll).wired[0].uuid, "cccc3333-21fd")
})

const RELAYS = `Albania (al)
\tTirana (tia) @ 41.32795°N, 19.81902°W
\t\tal-tia-wg-001 (45.142.26.2, 2a04::f001) - hosted by iRegister (rented)
\t\tal-tia-wg-002 (62.101.165.2, 2a04::f001) - hosted by iRegister (rented)

Australia (au)
\tAdelaide (adl) @ -34.9°N, 138.5°W
\t\tau-adl-wg-301 (103.214.20.50, 2404::c1f) - hosted by hostuniversal (rented)
\tSydney (syd) @ -33.8°N, 151.2°W
\t\tau-syd-wg-001 (146.70.200.2, 2001::f001) - hosted by M247 (rented)
\t\tau-syd-wg-002 (146.70.200.3, 2001::f002) - hosted by M247 (rented)

Austria (at)
\tVienna (vie) @ 48.2°N, 16.3°W
\t\tat-vie-wg-001 (1.2.3.4, 2001::1) - hosted by x (rented)
`

test("mullvad: relay list parses countries, cities and relay counts", () => {
  const r = Mullvad.parseRelays(RELAYS)
  assert.deepEqual(r.map((c) => c.code), ["al", "au", "at"]) // by name: Albania, Australia, Austria
  const au = r.find((c) => c.code === "au")
  assert.deepEqual(au.cities.map((c) => c.code), ["adl", "syd"])
  assert.equal(au.relays, 3)
  assert.equal(au.cities[1].relays, 2)
})

test("mullvad: stored location, as city, country or pinned server", () => {
  assert.deepEqual(Mullvad.parseRelayGet("Generic constraints\n    Location:               city osa, jp\n"), { country: "jp", city: "osa", hostname: "" })
  assert.deepEqual(Mullvad.parseRelayGet("    Location:   country se"), { country: "se", city: "", hostname: "" })
  assert.equal(Mullvad.parseRelayGet("    Location:   hostname se-got-wg-001").city, "got")
  assert.deepEqual(Mullvad.parseRelayGet("    Location:   any"), { country: "", city: "", hostname: "" })
})

test("mullvad: search by country, city or code", () => {
  const r = Mullvad.parseRelays(RELAYS)
  assert.deepEqual(Mullvad.filterCountries(r, "").length, 3)
  const aus = Mullvad.filterCountries(r, "austral")
  assert.deepEqual(aus.map((x) => x.country.code), ["au"])
  assert.equal(aus[0].cityOnly, false)
  assert.equal(aus[0].cities.length, 2)
  const syd = Mullvad.filterCountries(r, "sydney")
  assert.equal(syd[0].cityOnly, true)
  assert.deepEqual(syd[0].cities.map((c) => c.code), ["syd"])
  assert.deepEqual(Mullvad.filterCountries(r, "vie").map((x) => x.country.code), ["at"]) // city code
  assert.deepEqual(Mullvad.filterCountries(r, "zzz"), [])
})

test("mullvad: location commands set then connect, and refuse odd codes", () => {
  assert.deepEqual(Mullvad.connectToCommands("se", "got"), [["mullvad", "relay", "set", "location", "se", "got"], ["mullvad", "connect"]])
  assert.deepEqual(Mullvad.connectToCommands("se", ""), [["mullvad", "relay", "set", "location", "se"], ["mullvad", "connect"]])
  assert.deepEqual(Mullvad.connectToCommands("se; reboot", ""), [])
  assert.deepEqual(Mullvad.connectToCommands("--help", ""), [])
})

const Tailscale = load("Tailscale.js")

const TS_STATUS = JSON.stringify({
  Version: "1.74.1", BackendState: "Running", AuthURL: "",
  TailscaleIPs: ["100.101.102.103", "fd7a:115c:a1e0::1"],
  Self: { HostName: "laptop", DNSName: "laptop.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.101.102.103", "fd7a:115c:a1e0::1"] },
  CurrentTailnet: { Name: "me@example.com" },
  Peer: {
    "nodekey:aaa": { HostName: "nas", DNSName: "nas.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.1"], Online: true, CurAddr: "1.2.3.4:41641", ExitNodeOption: false },
    "nodekey:bbb": { HostName: "vps", DNSName: "vps.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.2"], Online: true, Relay: "fra", ExitNodeOption: true, ExitNode: true },
    "nodekey:ccc": { HostName: "phone", DNSName: "phone.tail1234.ts.net.", OS: "android", TailscaleIPs: ["100.100.1.3"], Online: false },
    "nodekey:ddd": { HostName: "old-exit", DNSName: "old-exit.tail1234.ts.net.", OS: "linux", TailscaleIPs: ["100.100.1.4"], Online: false, ExitNodeOption: true },
  },
})

test("tailscale: running state, peers, and the selected exit node", () => {
  const t = Tailscale.parseStatus(TS_STATUS)
  assert.equal(t.up, true)
  assert.equal(t.ip, "100.101.102.103")
  assert.equal(t.fqdn, "laptop.tail1234.ts.net")
  assert.equal(t.tailnet, "me@example.com")
  assert.equal(t.peersConnected, 2)
  assert.equal(t.peersTotal, 4)
  assert.deepEqual(t.peers.map((p) => p.name), ["nas", "vps", "old-exit", "phone"]) // online first
  assert.equal(t.peers[0].connectionType, "direct")
  assert.equal(t.peers[1].connectionType, "relay")
  assert.equal(t.fullTunnel, true)
  assert.equal(t.currentExit, "100.100.1.2")
  assert.equal(t.detail, "exit: vps · 100.101.102.103 · 2/4 peers")
})

test("tailscale: offline exit nodes are hidden unless selected", () => {
  const t = Tailscale.parseStatus(TS_STATUS)
  assert.deepEqual(t.exitNodes.map((e) => e.label), ["vps"])
  const noneOn = Tailscale.parseStatus(TS_STATUS.replace('"ExitNode":true', '"ExitNode":false'))
  assert.equal(noneOn.fullTunnel, false)
  assert.equal(noneOn.currentExit, "")
})

test("tailscale: stopped, needs login, and no daemon", () => {
  const stopped = Tailscale.parseStatus('{"BackendState":"Stopped","Peer":{}}')
  assert.equal(stopped.up, false)
  assert.equal(stopped.detail, "Stopped")
  const login = Tailscale.parseStatus('{"BackendState":"NeedsLogin","AuthURL":"https://login.tailscale.com/a/abc123"}')
  assert.equal(login.needsLogin, true)
  assert.equal(login.authUrl, "https://login.tailscale.com/a/abc123")
  assert.equal(Tailscale.parseStatus('{"BackendState":"NeedsLogin","AuthURL":"javascript:alert(1)"}').authUrl, "")
  assert.equal(Tailscale.parseStatus(""), null)
  assert.equal(Tailscale.parseStatus("not json"), null)
})

test("tailscale: exit node commands", () => {
  const t = Tailscale.parseStatus(TS_STATUS)
  assert.deepEqual(Tailscale.exitCommands(t, "100.100.1.2"), [["tailscale", "set", "--exit-node="]]) // selected: clears
  assert.deepEqual(Tailscale.exitCommands(t, "100.100.1.9"), [["tailscale", "set", "--exit-node=100.100.1.9"]])
  assert.deepEqual(Tailscale.exitCommands(t, "evil; reboot"), [])
})

test("tailscale: operator hint and command", () => {
  assert.equal(Tailscale.needsOperator("Access denied: prefs write access denied\nUse 'sudo tailscale up' or 'sudo tailscale set --operator=$USER'"), true)
  assert.equal(Tailscale.needsOperator("some other failure"), false)
  assert.deepEqual(Tailscale.operatorCommand("menno"), [["pkexec", "tailscale", "set", "--operator=menno"]])
  assert.deepEqual(Tailscale.operatorCommand("a b; rm"), [])
})

test("compose: tailscale joins the list, gets routes by device, toggles", () => {
  const poll = `@@TS\n${TS_STATUS}\n@@R4\n[{"dst":"100.64.0.0/10","dev":"tailscale0"},{"dst":"default","dev":"tailscale0","table":"52"}]\n@@R6\n[]\n`
  const b = Compose.build(poll)
  const t = b.tunnels.find((x) => x.id === "tailscale")
  assert.equal(t.device, "tailscale0")
  assert.equal(t.fullTunnel, true)
  assert.deepEqual(Compose.toggleCommands(t), [["tailscale", "down"]])
  assert.deepEqual(Compose.exitCommands([], t, "100.100.1.9"), [["tailscale", "set", "--exit-node=100.100.1.9"]])
  assert.equal(Shared.isForeignDevice("tailscale0"), true)
})

test("mullvad: settings parse from the three getters", () => {
  const s = Mullvad.parseSettings("Block traffic when the VPN is disconnected: on\nLocal network sharing setting: allow\nAutoconnect: off\n")
  assert.deepEqual(s, { lockdown: true, lan: true, autoconnect: false })
  assert.deepEqual(Mullvad.parseSettings("Block traffic when the VPN is disconnected: off\nLocal network sharing setting: block\nAutoconnect: on\n"), { lockdown: false, lan: false, autoconnect: true })
  assert.deepEqual(Mullvad.parseSettings(""), { lockdown: false, lan: false, autoconnect: false })
})

test("mullvad: setting commands, and nothing for unknown keys", () => {
  assert.deepEqual(Mullvad.settingCommands("lockdown", true), [["mullvad", "lockdown-mode", "set", "on"]])
  assert.deepEqual(Mullvad.settingCommands("lan", true), [["mullvad", "lan", "set", "allow"]])
  assert.deepEqual(Mullvad.settingCommands("lan", false), [["mullvad", "lan", "set", "block"]])
  assert.deepEqual(Mullvad.settingCommands("autoconnect", false), [["mullvad", "auto-connect", "set", "off"]])
  assert.deepEqual(Mullvad.settingCommands("rm -rf", true), [])
})

test("network: QR matrix parse, and rejection of anything not square", () => {
  const row = (n, i) => Array.from({ length: n }, (_, j) => (i + j) % 2).join("")
  const n = 25
  const good = "meta\twlan0\tWPA\tMy\tNet\n" + Array.from({ length: n }, (_, i) => row(n, i)).join("\n") + "\n"
  const q = Network.parseQr(good)
  assert.equal(q.iface, "wlan0")
  assert.equal(q.security, "WPA")
  assert.equal(q.ssid, "My\tNet")
  assert.equal(q.rows.length, 25)
  assert.equal(Network.parseQr(good.replace(row(n, 3), "0101")), null)
  assert.equal(Network.parseQr("No active Wi-Fi connection"), null)
  assert.equal(Network.parseQr(Array.from({ length: n }, (_, i) => row(n, i)).join("\n")), null) // no meta
})

test("network: device names are checked before they reach a command", () => {
  assert.equal(Network.validDevice("wlan0"), true)
  assert.equal(Network.validDevice("wlan0; reboot"), false)
  assert.equal(Network.validDevice(""), false)
})

test("band: status, choices, and a command only for known bands", () => {
  const b = Network.parseBand("band\t5\navailable\t2.4 5 6\nselected\tauto\n")
  assert.deepEqual(b, { band: "5", available: ["2.4", "5", "6"], selected: "auto" })
  assert.deepEqual(Network.parseBand(""), { band: "", available: [], selected: "auto" })
  const u = "11111111-1111-1111-1111-111111111111"
  assert.deepEqual(Network.bandCommand("5", u).slice(3), ["nmcli-band", "5 GHz", "a", u])
  assert.deepEqual(Network.bandCommand("auto", u).slice(3), ["nmcli-band", "Auto", "", u])
  assert.deepEqual(Network.bandCommand("6", u).slice(4), ["6 GHz", "6GHz", u])
  assert.equal(Network.bandCommand("7; reboot", u), null)
  assert.equal(Network.bandCommand("5", "x; reboot"), null)
  assert.equal(Network.validBand("2.4"), true)
  assert.equal(Network.bandLabel("2.4"), "2.4 GHz")
})

test("speed: ping summary, with and without replies", () => {
  const p = Network.parsePing("8 packets transmitted, 8 received, 0% packet loss, time 1403ms\nrtt min/avg/max/mdev = 10.100/12.300/15.200/1.800 ms\n")
  assert.deepEqual(p, { loss: 0, min: 10.1, avg: 12.3, max: 15.2, jitter: 1.8 })
  const dead = Network.parsePing("8 packets transmitted, 0 received, 100% packet loss, time 1400ms\n")
  assert.equal(dead.loss, 100)
  assert.equal(dead.avg, 0)
  assert.equal(Network.parsePing("ping: connect: Network is unreachable"), null)
})

test("speed: ramp-up is dropped and the rest averaged", () => {
  const r = Network.speedFromSamples("5\n50\n100\n100\n100\n100\n")
  assert.equal(r.mbps, 100)
  assert.equal(r.peak, 100)
  assert.equal(Network.speedFromSamples("20\n40\n").mbps, 30) // too short to trim
  assert.equal(Network.speedFromSamples(""), null)
  assert.deepEqual(Network.speedArgs("sideways"), [])
  assert.equal(Network.speedArgs("down")[2], "TERM")
  assert.equal(Network.formatMbps(412.4), "412 Mbit/s")
  assert.equal(Network.formatMbps(2400), "2.40 Gbit/s")
})

test("dns: servers accept IPv4 and IPv6, reject everything else", () => {
  assert.deepEqual(IpConfig.parseDnsServers("1.1.1.1, 8.8.8.8").servers, ["1.1.1.1", "8.8.8.8"])
  assert.equal(IpConfig.parseDnsServers("2606:4700:4700::1111 1.1.1.1").ok, true)
  assert.equal(IpConfig.parseDnsServers("").error, "Enter at least one DNS server")
  assert.equal(IpConfig.parseDnsServers("1.1.1.1 nope").error, "nope is not an IP address")
  assert.equal(IpConfig.parseDnsServers("1.1.1.1; reboot").ok, false)
  assert.equal(IpConfig.parseDnsServers("1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 9.9.9.9").error, "At most four DNS servers")
  assert.equal(IpConfig.isIPv6("::1"), true)
  assert.equal(IpConfig.isIPv6("1::2::3"), false)
  assert.equal(IpConfig.isIPv6("fe80:::1"), false)
})

test("wifi: ssid validity", () => {
  assert.equal(Wifi.validSsid("My Net"), true)
  assert.equal(Wifi.validSsid(""), false)
  assert.equal(Wifi.validSsid("x".repeat(33)), false)
  assert.equal(Wifi.validSsid("bad\nname"), false)
})

test("network: the DNS provider rides along in the poll", () => {
  assert.equal(Network.build(NET_POLL + "@@DNSP\nCloudflare\n").dns, "Cloudflare")
  assert.equal(Network.build(NET_POLL).dns, "")
})

const Tools = load("Tools.js")

test("tabs: auto shows with content, show always, hide never", () => {
  assert.equal(Tools.tabVisible("auto", true), true)
  assert.equal(Tools.tabVisible("auto", false), false)
  assert.equal(Tools.tabVisible("show", false), true)
  assert.equal(Tools.tabVisible("hide", true), false)
  assert.equal(Tools.tabMode({ vpn: "hide" }, "vpn"), "hide")
  assert.equal(Tools.tabMode({ vpn: "bogus" }, "vpn"), "auto")
  assert.equal(Tools.tabMode(undefined, "vpn"), "auto")
})

test("adapters: hidden ones drop out of the list", () => {
  const links = [{ device: "enp5s0" }, { device: "wlan0" }]
  assert.deepEqual(Tools.visibleLinks(links, ["wlan0"]).map((l) => l.device), ["enp5s0"])
  assert.equal(Tools.visibleLinks(links, undefined).length, 2)
})

test("guides: missing tools get the whole walkthrough, installed ones skip the install", () => {
  assert.equal(Tools.guideState("tailscale", {}), "missing")
  assert.equal(Tools.guideState("tailscale", { tailscale: true }), "idle")
  assert.equal(Tools.guideState("vpn", { nmcli: true }), "idle")
  assert.deepEqual(Tools.stepsFor("mullvad", "missing").map((s) => s.stage), ["install", "start", "login"])
  assert.deepEqual(Tools.stepsFor("mullvad", "idle").map((s) => s.stage), ["start", "login"])
  assert.deepEqual(Tools.stepsFor("vpn", "idle").map((s) => s.stage), ["import", "import"])
})

test("guides: only the NetBird web installer is never offered as one click", () => {
  const nb = Tools.GUIDES.netbird.steps.find((s) => s.stage === "install")
  assert.equal(nb.run, undefined)
  assert.equal(nb.command, undefined) // nothing to copy or run: read the guide
  Object.keys(Tools.GUIDES).forEach((id) => Tools.GUIDES[id].steps.filter((s) => s.run).forEach((s) => assert.equal(/curl|\|\s*sh/.test(s.command), false)))
  assert.equal(Tools.safeUrl("https://docs.netbird.io/get-started/install/linux"), true)
  assert.equal(Tools.safeUrl("javascript:alert(1)"), false)
  assert.equal(Tools.safeUrl("http://example.com"), false)
})

test("compose: installed tools are reported even when their daemon is down", () => {
  const b = Compose.build("@@INST\nnetbird\nnmcli\n@@NB\n@@TS\n")
  assert.deepEqual(b.installed, { netbird: true, nmcli: true })
  assert.equal(b.tunnels.length, 0)
})

test("dns: Quad9 and OpenDNS are recognised from the active servers", () => {
  assert.equal(Network.resolveDnsProvider("DHCP", []), "DHCP")
  assert.equal(Network.resolveDnsProvider("Google", ["8.8.8.8"]), "Google")
  assert.equal(Network.resolveDnsProvider("Custom", ["149.112.112.112", "9.9.9.9"]), "Quad9")
  assert.equal(Network.resolveDnsProvider("Custom", ["208.67.222.222", "208.67.220.220"]), "OpenDNS")
  assert.equal(Network.resolveDnsProvider("Custom", ["9.9.9.9"]), "Custom") // only half of Quad9
  assert.equal(Network.resolveDnsProvider("Custom", ["192.168.1.1"]), "Custom")
  assert.equal(Network.resolveDnsProvider("Cloudflare", ["1.1.1.1"]), "Cloudflare")
})

test("dns: preset servers all validate as DNS servers", () => {
  Object.keys(Network.DNS_PRESETS).forEach((n) => assert.equal(IpConfig.parseDnsServers(Network.DNS_PRESETS[n].servers.join(" ")).ok, true))
})

test("wifi: security names read the way people say them", () => {
  assert.equal(Wifi.securityLabel("Wpa2Psk"), "WPA2")
  assert.equal(Wifi.securityLabel("Sae"), "WPA3")
  assert.equal(Wifi.securityLabel("Wpa2Eap"), "WPA2 Enterprise")
  assert.equal(Wifi.securityLabel("SomethingNew"), "")
})

test("NetBird peers are named by their first label", () => {
  const t = NetBird.parseStatus(JSON.stringify({ daemonStatus: "Connected", peers: { total: 1, connected: 1, details: [
    { fqdn: "homeserver.netbird.example.com", netbirdIp: "100.1.1.5", status: "Connected" } ] } }))
  assert.equal(t.peers[0].name, "homeserver")
})

test("guides: no shipped text pipes a download into a shell", () => {
  Object.keys(Tools.GUIDES).forEach((id) => Tools.GUIDES[id].steps.forEach((s) => assert.equal(/curl|wget|\|\s*(ba)?sh/.test(s.command || ""), false)))
})

test("wifi: enterprise profiles must pin the server", () => {
  assert.equal(Wifi.validServerName("radius.example.edu"), true)
  assert.equal(Wifi.validServerName("example.edu"), true)
  assert.equal(Wifi.validServerName(""), false)
  assert.equal(Wifi.validServerName("localhost"), false)
  assert.equal(Wifi.validServerName("a b.example.com"), false)
  assert.equal(Wifi.validServerName("x.com; rm -rf"), false)
  assert.equal(Wifi.validServerName("-bad.example.com"), false)
})

test("wifi: CA certificate path is blank or a plain absolute certificate file", () => {
  assert.equal(Wifi.validCaPath(""), true)
  assert.equal(Wifi.validCaPath("/home/me/certs/ca.pem"), true)
  assert.equal(Wifi.validCaPath("ca.pem"), false)
  assert.equal(Wifi.validCaPath("/etc/../shadow.pem"), false)
  assert.equal(Wifi.validCaPath("/tmp/x y.pem"), false)
  assert.equal(Wifi.validCaPath("/tmp/ca.pem$(id)"), false)
  assert.equal(Wifi.validCaPath("/tmp/notacert.sh"), false)
})

test("wifi: saved PEAP profiles without a pinned server are flagged", () => {
  const rec = (uuid, fields) => ["connection.uuid:" + uuid, "connection.type:802-11-wireless", "connection.timestamp:" + uuid[0]].concat(fields, ["--"])
  const raw = [].concat(
    rec("11111111-1111-1111-1111-111111111111", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap", "802-1x.domain-suffix-match:", "802-1x.ca-cert:", "802-1x.system-ca-certs:no"]),
    rec("22222222-2222-2222-2222-222222222222", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap", "802-1x.domain-suffix-match:radius.example.edu", "802-1x.ca-cert:/etc/ca.pem"]),
    rec("33333333-3333-3333-3333-333333333333", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap", "802-1x.domain-match:radius.example.edu", "802-1x.system-ca-certs:yes"]),
    rec("44444444-4444-4444-4444-444444444444", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap", "802-1x.ca-cert:/etc/ca.pem"]),
    rec("55555555-5555-5555-5555-555555555555", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:tls"]),
    rec("66666666-6666-6666-6666-666666666666", ["802-11-wireless-security.key-mgmt:wpa-psk"]),
    // nmcli separates several methods with commas
    rec("77777777-7777-7777-7777-777777777777", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap,ttls"]),
    // subject-match is a substring test: not a pin
    rec("88888888-8888-8888-8888-888888888888", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:peap", "802-1x.subject-match:example.com", "802-1x.system-ca-certs:yes"]),
    // enterprise key management without readable 802.1X data
    rec("99999999-9999-9999-9999-999999999999", ["802-11-wireless-security.key-mgmt:wpa-eap"]),
    rec("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", ["802-11-wireless-security.key-mgmt:wpa-eap", "802-1x.eap:", "802-1x.system-ca-certs:yes", "802-1x.domain-suffix-match:x.example"]),
    ["done"]
  ).join("\n")
  const list = Wifi.parseProfiles(raw)
  assert.equal(list.length, 10)
  assert.deepEqual(list.map(p => Wifi.profileUnpinned(p)), [true, false, false, true, false, false, true, true, true, true])
  assert.equal(Wifi.pickProfile(list.slice(1, 3), "wlan0").uuid, "33333333-3333-3333-3333-333333333333")
  assert.equal(Wifi.validUuid("x; rm -rf /"), false)
  assert.equal(Wifi.autoconnecting(list[0]), true)
  assert.equal(Wifi.autoconnecting({ f: { "connection.autoconnect": "no" } }), false)
})

test("wifi: MD5, LEAP and unknown EAP methods are never trusted, even with a CA and server name", () => {
  const pinned = { "802-1x.system-ca-certs": "yes", "802-1x.domain-suffix-match": "radius.example.edu" }
  const prof = eap => ({ f: Object.assign({ "802-1x.eap": eap }, pinned) })
  assert.equal(Wifi.profileUnpinned(prof("md5")), true)
  assert.equal(Wifi.profileUnpinned(prof("peap,md5")), true)
  assert.equal(Wifi.profileUnpinned(prof("leap")), true)
  assert.equal(Wifi.profileUnpinned(prof("peap,sim")), true)
  assert.equal(Wifi.profileUnpinned(prof("peap,ttls")), false)
  assert.equal(Wifi.profileUnpinned(prof("tls,peap")), false)
  assert.equal(Wifi.profileUnpinned({ f: { "802-1x.eap": "tls" } }), false)
  assert.equal(Wifi.profileUnpinned({ f: { "802-1x.eap": "tls,md5" } }), true)
})

test("wifi: the profile to join is a client profile for this adapter", () => {
  const p = (uuid, ts, extra) => ({ uuid, type: "802-11-wireless", timestamp: ts, f: extra || {} })
  const list = [
    p("a", 10, { "802-11-wireless.mode": "infrastructure" }),
    p("b", 30, { "802-11-wireless.mode": "ap" }),
    p("c", 20, { "802-11-wireless.mode": "infrastructure", "connection.interface-name": "wlan1" }),
    p("d", 15, { "802-11-wireless.mode": "", "connection.interface-name": "wlan0" })
  ]
  assert.equal(Wifi.pickProfile(list, "wlan0").uuid, "d")
  assert.equal(Wifi.pickProfile(list, "wlan1").uuid, "c")
  assert.equal(Wifi.pickProfile([list[1]], "wlan0"), null)
})

test("wifi: profile check output that is incomplete or malformed is refused", () => {
  const ok = "connection.uuid:11111111-1111-1111-1111-111111111111\nconnection.type:802-11-wireless\n--\ndone\n"
  assert.equal(Wifi.parseProfiles(ok).length, 1)
  assert.deepEqual(Wifi.parseProfiles("done\n"), [])
  assert.equal(Wifi.parseProfiles(""), null)
  assert.equal(Wifi.parseProfiles(ok.replace("done\n", "")), null)
  assert.equal(Wifi.parseProfiles("--\ndone"), null)
  assert.equal(Wifi.parseProfiles("connection.uuid:nope\nconnection.type:x\n--\ndone"), null)
  assert.equal(Wifi.parseProfiles("connection.uuid:11111111-1111-1111-1111-111111111111\nconnection.type:802-11-wireless\ndone"), null)
  assert.equal(Wifi.parseProfiles("garbage\n--\ndone"), null)
})
