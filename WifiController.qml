import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "model/Wifi.js" as Wifi
import "model/Demo.js" as Demo

// Wi-Fi through Quickshell's native NetworkManager bindings: radio switch,
// scan results, connect / disconnect / forget. The panel never touches the
// Networking objects directly; it reads `networks` and calls the verbs below.
Item {
  id: root
  visible: false

  // Scan only while someone is looking at the list.
  property bool scanning: false
  // Made-up networks instead of the real ones; see model/Demo.js.
  property bool demo: false

  readonly property bool available: Networking.backend === NetworkBackendType.NetworkManager
  readonly property bool radioOn: demo ? true : Networking.wifiEnabled
  readonly property var device: {
    var list = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < list.length; i++) if (list[i].type === DeviceType.Wifi) return list[i]
    return null
  }

  // Plain rows for the UI, strongest first, connected and saved on top.
  readonly property var networks: {
    if (demo) return Demo.WIFI_NETWORKS
    var objs = device && device.networks ? device.networks.values : []
    var seen = {}
    var out = []
    for (var i = 0; i < objs.length; i++) {
      var n = objs[i]
      var ssid = String(n.name || "")
      if (ssid === "" || seen[ssid]) continue
      seen[ssid] = true
      out.push({
        ssid: ssid,
        signal: Math.round((n.signalStrength || 0) * 100),
        security: securityName(n.security),
        secured: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
        enterprise: n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap,
        known: n.known === true,
        connected: n.connected === true,
        busy: n.stateChanging === true
      })
    }
    out.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return out
  }
  readonly property bool busy: networks.some(function(n) { return n.busy }) || enterpriseProcess.running || hiddenProcess.running

  // True for a few seconds after a scan starts, and while there is nothing to
  // show yet: the list fills in as access points answer.
  property bool refreshing: false

  // Last failure, in words. Cleared when a new attempt starts.
  property string failure: ""
  property var _watched: null

  // WifiSecurityType does not enumerate, so probe the names we know.
  function securityName(value) {
    var names = ["Open", "Owe", "StaticWep", "DynamicWep", "WpaPsk", "Wpa2Psk", "Sae", "WpaEap", "Wpa2Eap", "Wpa3SuiteB192"]
    for (var i = 0; i < names.length; i++)
      if (WifiSecurityType[names[i]] !== undefined && WifiSecurityType[names[i]] === value) return names[i]
    return ""
  }

  function _find(ssid) {
    var objs = device && device.networks ? device.networks.values : []
    for (var i = 0; i < objs.length; i++) if (String(objs[i].name) === ssid) return objs[i]
    return null
  }

  function setRadio(on) { if (demo) return; Networking.wifiEnabled = on }

  function _watch(net) { _watched = net; failure = "" }

  function connectKnown(ssid) { if (demo) return;
    var n = _find(ssid)
    if (!n) return
    _watch(n)
    n.connect()
  }

  function connectPsk(ssid, passphrase) { if (demo) return;
    var n = _find(ssid)
    if (!n) return
    _watch(n)
    n.connectWithPsk(passphrase)
  }

  // WPA-Enterprise (PEAP / MSCHAPv2). The password goes in on stdin and is fed
  // to nmcli's editor, never an argument: argv is world-readable in /proc.
  //
  // PEAP/MSCHAPv2 hands a password-equivalent to whoever answers as the
  // network, so the server must be pinned: `serverName` (required) must match
  // the RADIUS certificate, and that certificate must chain to `caPath` or, when
  // none is given, to the system CA bundle. Never a profile that trusts anyone.
  function connectEnterprise(ssid, identity, password, serverName, caPath) { if (demo) return;
    if (!Wifi.validServerName(serverName) || !Wifi.validCaPath(caPath || "")) {
      failure = "Check the server name and certificate path."
      return
    }
    failure = ""
    enterpriseProcess.command = ["bash", "-c", root._enterpriseScript, "nmcli-eap", ssid, identity, serverName, caPath || ""]
    enterpriseProcess.running = true
    enterpriseProcess.write(password + "\n")
  }

  readonly property string _enterpriseScript:
    "u=$(uuidgen); IFS= read -r pw; trust=(802-1x.system-ca-certs yes);" +
    " [ -n \"$4\" ] && trust=(802-1x.ca-cert \"$4\");" +
    " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
    " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
    " 802-1x.identity \"$2\" 802-1x.domain-suffix-match \"$3\" \"${trust[@]}\" 802-1x.auth-timeout 8 >/dev/null" +
    " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
    " && nmcli connection up uuid \"$u\"" +
    " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

  // A network that does not announce itself. Same care as enterprise: the
  // password arrives on stdin and goes to nmcli's editor, not into argv.
  // `security` is one of Wifi.HIDDEN_SECURITY.
  function connectHidden(ssid, security, password) { if (demo) return;
    if (!Wifi.validSsid(ssid) || Wifi.HIDDEN_SECURITY.indexOf(security) === -1) {
      failure = "Check the network name and security."
      return
    }
    failure = ""
    hiddenProcess.command = ["bash", "-c", root._hiddenScript, "nmcli-hidden", ssid, security]
    hiddenProcess.running = true
    hiddenProcess.write(password + "\n")
  }

  readonly property string _hiddenScript:
    "u=$(uuidgen); IFS= read -r pw; key=\"$2\";" +
    " if [ \"$key\" = open ]; then" +
    "   nmcli connection add type wifi con-name \"$1\" ssid \"$1\" wifi.hidden yes connection.uuid \"$u\" >/dev/null" +
    "   && nmcli connection up uuid \"$u\";" +
    " else" +
    "   nmcli connection add type wifi con-name \"$1\" ssid \"$1\" wifi.hidden yes wifi-sec.key-mgmt \"$key\" connection.uuid \"$u\" >/dev/null" +
    "   && printf 'set wifi-sec.psk %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
    "   && nmcli connection up uuid \"$u\";" +
    " fi || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

  Process {
    id: hiddenProcess
    running: false
    command: []
    stdinEnabled: true
    onExited: function(exitCode) {
      if (exitCode !== 0) root.failure = "Could not join. Check the name, security and password."
    }
  }

  function disconnect(ssid) { if (demo) return;
    var n = _find(ssid)
    if (n) n.disconnect()
  }

  function forget(ssid) { if (demo) return;
    var n = _find(ssid)
    if (n && n.known && !n.connected) n.forget()
  }

  function reasonText(reason) {
    if (reason === ConnectionFailReason.NoSecrets) return "Passphrase required"
    if (reason === ConnectionFailReason.WifiAuthTimeout) return "Wrong password"
    if (reason === ConnectionFailReason.WifiNetworkLost) return "Network went out of range"
    if (reason === ConnectionFailReason.WifiClientDisconnected) return "Disconnected by the access point"
    if (reason === ConnectionFailReason.WifiClientFailed) return "Could not associate"
    return "Connection failed"
  }

  Connections {
    target: root._watched
    ignoreUnknownSignals: true
    function onConnectionFailed(reason) { root.failure = root.reasonText(reason) }
  }

  Process {
    id: enterpriseProcess
    running: false
    command: []
    stdinEnabled: true
    onExited: function(exitCode) {
      if (exitCode !== 0) root.failure = "Could not connect. Check the username and password."
    }
  }

  // Ask NetworkManager for a fresh scan now. It may refuse a request that
  // follows another too closely; that is fine, the list is recent anyway.
  function rescan() { if (demo) return;
    if (refreshing || !device) return
    refreshing = true
    refreshTimer.restart()
    if (_scannerDevice) { _scannerDevice.scannerEnabled = false; _scannerDevice.scannerEnabled = true }
    rescanProcess.running = true
  }

  Process {
    id: rescanProcess
    running: false
    command: ["nmcli", "device", "wifi", "rescan"]
  }

  // Claim the scanner only while asked, and always give it back.
  property var _scannerDevice: null
  function _syncScanner() {
    var next = scanning ? device : null
    if (_scannerDevice && _scannerDevice !== next) _scannerDevice.scannerEnabled = false
    _scannerDevice = next
    if (_scannerDevice) _scannerDevice.scannerEnabled = true
  }
  onScanningChanged: {
    _syncScanner()
    refreshing = scanning
    if (scanning) refreshTimer.restart()
  }

  Timer {
    id: refreshTimer
    interval: 5000
    repeat: false
    onTriggered: root.refreshing = false
  }
  onDeviceChanged: _syncScanner()
  Component.onDestruction: if (_scannerDevice) _scannerDevice.scannerEnabled = false
}
