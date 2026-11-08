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
  readonly property bool busy: connecting || networks.some(function(n) { return n.busy }) || enterpriseProcess.running || hiddenProcess.running || checkProcess.running

  // One join attempt, from the click until it works or fails. The panel shows
  // it on the form, and the bar icon spins while it runs, so closing the
  // panel does not hide that something is happening.
  property string attemptSsid: ""
  // "" (nothing), "connecting", "connected" or "failed".
  property string attemptPhase: ""
  readonly property bool connecting: attemptPhase === "connecting"
  property bool _sawConnecting: false
  property bool _wasKnown: false

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

  function _begin(ssid, net) {
    failure = ""
    attemptSsid = ssid
    attemptPhase = "connecting"
    _sawConnecting = false
    _wasKnown = net ? net.known === true : false
    _watched = net
    attemptTimer.restart()
  }

  function _succeed() {
    if (attemptPhase !== "connecting") return
    attemptTimer.stop()
    attemptPhase = "connected"
    failure = ""
    doneTimer.restart()
  }

  // A specific reason (from NetworkManager) replaces a generic one, never the
  // other way round.
  function _fail(text, specific) {
    if (attemptPhase === "failed" && !specific) return
    if (attemptPhase !== "connecting" && attemptPhase !== "failed") return
    attemptTimer.stop()
    attemptPhase = "failed"
    failure = text
    // A password that did not work leaves a saved profile behind that would be
    // tried again without asking. Drop the one this attempt created.
    if (_watched && !_wasKnown && _watched.known && !_watched.connected) _watched.forget()
  }

  // Saved profiles that would send a password to an unverified server (made
  // before the form pinned one, or by other tools). Never activated as is.
  property var staleUuids: []
  property string _checkSsid: ""
  // The saved profile for `ssid` must be re-entered with a server name.
  signal needsPinning(string ssid)

  function _isEnterprise(n) {
    return n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap || n.security === WifiSecurityType.Wpa3SuiteB192
  }

  function connectKnown(ssid) { if (demo) return;
    var n = _find(ssid)
    if (!n) return
    if (_isEnterprise(n) && !checkProcess.running) {
      // Look at the saved profile first; connect only if it pins the server.
      _checkSsid = ssid
      checkProcess.command = ["bash", "-c", root._checkScript, "nmcli-check", ssid]
      checkProcess.running = true
      return
    }
    _begin(ssid, n)
    n.connect()
  }

  function _checked(text) {
    var ssid = _checkSsid
    var n = _find(ssid)
    if (!n) return
    var bad = Wifi.parseProfiles(text).filter(function(p) { return Wifi.profileUnpinned(p) && Wifi.validUuid(p.uuid) })
    if (bad.length === 0) {
      staleUuids = []
      _begin(ssid, n)
      n.connect()
      return
    }
    staleUuids = bad.map(function(p) { return p.uuid })
    needsPinning(ssid)
  }

  readonly property string _checkScript:
    "nmcli -t -f uuid,type connection show | while IFS=: read -r u t; do" +
    " [ \"$t\" = 802-11-wireless ] || continue;" +
    " [ \"$(nmcli -g 802-11-wireless.ssid connection show uuid \"$u\")\" = \"$1\" ] || continue;" +
    " echo \"uuid=$u\";" +
    " nmcli -t -f 802-1x.eap,802-1x.domain-suffix-match,802-1x.domain-match,802-1x.altsubject-matches,802-1x.subject-match,802-1x.ca-cert,802-1x.system-ca-certs connection show uuid \"$u\";" +
    " echo --; done"

  Process {
    id: checkProcess
    running: false
    command: []
    stdout: StdioCollector { id: checkOut; waitForEnd: true }
    onExited: function(exitCode) {
      // If the profile cannot be read, do not connect blind.
      if (exitCode === 0) root._checked(String(checkOut.text || ""))
      else root._fail("Could not read the saved profile.", true)
    }
  }

  function connectPsk(ssid, passphrase) { if (demo) return;
    var n = _find(ssid)
    if (!n) {
      attemptSsid = ssid
      attemptPhase = "failed"
      failure = "That network is out of range. Scan again."
      return
    }
    _begin(ssid, n)
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
    _begin(ssid, null)
    // The unpinned profiles this one replaces go away once it connects.
    var stale = staleUuids.filter(Wifi.validUuid)
    enterpriseProcess.command = ["bash", "-c", root._enterpriseScript, "nmcli-eap", ssid, identity, serverName, caPath || ""].concat(stale)
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
    " && { shift 4; for o; do nmcli connection delete uuid \"$o\" >/dev/null 2>&1; done; true; }" +
    " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

  // A network that does not announce itself. Same care as enterprise: the
  // password arrives on stdin and goes to nmcli's editor, not into argv.
  // `security` is one of Wifi.HIDDEN_SECURITY.
  function connectHidden(ssid, security, password) { if (demo) return;
    if (!Wifi.validSsid(ssid) || Wifi.HIDDEN_SECURITY.indexOf(security) === -1) {
      failure = "Check the network name and security."
      return
    }
    _begin(ssid, null)
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
      if (exitCode === 0) root._succeed()
      else root._fail("Could not join. Check the name, security and password.", true)
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
    function onConnectionFailed(reason) { root._fail(root.reasonText(reason), true) }
    function onConnectedChanged() { if (root._watched && root._watched.connected) root._succeed() }
    function onStateChanged() {
      var st = root._watched ? root._watched.state : -1
      if (st === ConnectionState.Connecting) root._sawConnecting = true
      else if (st === ConnectionState.Disconnected && root._sawConnecting) root._fail("Could not connect. Check the password.", false)
    }
  }

  // The radio can hang for a long time on a bad password; do not spin forever.
  Timer {
    id: attemptTimer
    interval: 30000
    repeat: false
    onTriggered: root._fail("Timed out. Check the password and the signal.", false)
  }

  // "Connected" stays readable for a moment, then the state goes quiet.
  Timer {
    id: doneTimer
    interval: 4000
    repeat: false
    onTriggered: if (root.attemptPhase === "connected") root.attemptPhase = ""
  }

  Process {
    id: enterpriseProcess
    running: false
    command: []
    stdinEnabled: true
    onExited: function(exitCode) {
      if (exitCode === 0) { root.staleUuids = []; root._succeed() }
      else root._fail("Could not connect. Check the username, password and server name.", true)
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
