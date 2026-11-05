.pragma library

// Which tabs exist, whether they show, and what to tell someone whose tool is
// missing. Pure data and small decisions; the UI only draws it.

var TABS = [
  { id: "vpn", label: "VPN", tool: "nmcli" },
  { id: "mullvad", label: "Mullvad", tool: "mullvad" },
  { id: "netbird", label: "NetBird", tool: "netbird" },
  { id: "tailscale", label: "Tailscale", tool: "tailscale" }
]

var MODES = ["auto", "show", "hide"]

function tabMode(map, id) {
  var m = map ? map[id] : undefined
  return MODES.indexOf(m) !== -1 ? m : "auto"
}

// auto: when there is something to show. show: always, with install help when
// there is nothing. hide: never.
function tabVisible(mode, hasContent) {
  return mode === "show" || (mode === "auto" && hasContent)
}

function visibleLinks(links, hidden) {
  var h = Array.isArray(hidden) ? hidden : []
  return (links || []).filter(function(l) { return h.indexOf(l.device) === -1 })
}

// ---- Install guides -------------------------------------------------------
//
// stage: install | start | login | import. `run` marks a step that is safe to
// offer as one click (it only installs from the distribution or Omarchy);
// NetBird's official installer is a script from the web, so that one is shown
// for you to read and copy, never run for you.

var GUIDES = {
  vpn: {
    name: "NetworkManager VPNs",
    note: "WireGuard and OpenVPN profiles live in NetworkManager. WireGuard works out of the box.",
    docs: "https://wiki.archlinux.org/title/NetworkManager#Network_services_with_NetworkManager_dispatcher",
    steps: [
      { stage: "install", label: "OpenVPN support", command: "omarchy pkg add networkmanager-openvpn", run: true },
      { stage: "import", label: "Import WireGuard", command: "nmcli connection import type wireguard file ~/vpn.conf" },
      { stage: "import", label: "Import OpenVPN", command: "nmcli connection import type openvpn file ~/vpn.ovpn" }
    ]
  },
  mullvad: {
    name: "Mullvad",
    note: "Mullvad is a privacy VPN with servers in dozens of countries. You need an account number.",
    docs: "https://mullvad.net/en/download/vpn/linux",
    steps: [
      { stage: "install", label: "Install", command: "omarchy pkg add mullvad-vpn", run: true },
      { stage: "start", label: "Start the daemon", command: "sudo systemctl enable --now mullvad-daemon", run: true },
      { stage: "login", label: "Log in", command: "mullvad account login <account-number>" }
    ]
  },
  netbird: {
    name: "NetBird",
    note: "NetBird is a mesh VPN you can self-host. It is not in the Arch repositories; the project's own installer is the supported route.",
    docs: "https://docs.netbird.io/get-started/install/linux",
    steps: [
      { stage: "install", label: "Install", command: "curl -fsSL https://pkgs.netbird.io/install.sh | sh" },
      { stage: "start", label: "Start the service", command: "sudo systemctl enable --now netbird", run: true },
      { stage: "login", label: "Connect", command: "netbird up" }
    ]
  },
  tailscale: {
    name: "Tailscale",
    note: "Tailscale is a mesh VPN. Omarchy has its own installer, which also starts the service and lets your user control it.",
    docs: "https://tailscale.com/kb/1031/install-linux",
    steps: [
      { stage: "install", label: "Install", command: "omarchy install service tailscale", run: true },
      { stage: "login", label: "Log in", command: "tailscale up" }
    ]
  }
}

// "missing": the tool is not on this machine. "idle": it is, but nothing
// answers (daemon stopped, or no profiles yet).
function guideState(tabId, installed) {
  var tab = TABS.filter(function(t) { return t.id === tabId })[0]
  if (!tab) return "missing"
  return installed && installed[tab.tool] ? "idle" : "missing"
}

// What to show. Missing: everything from the start. Idle: skip the install.
function stepsFor(tabId, state) {
  var g = GUIDES[tabId]
  if (!g) return []
  return g.steps.filter(function(s) { return state === "missing" ? s.stage !== "import" || tabId === "vpn" : s.stage !== "install" })
}

function safeUrl(u) { return /^https:\/\/[A-Za-z0-9._~:\/?#\[\]@!$&'()*+,;=%-]+$/.test(String(u || "")) }
