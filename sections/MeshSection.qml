import QtQuick
import Quickshell
import "../model/Tailscale.js" as Tailscale

// A mesh VPN with peers and exit nodes: NetBird and Tailscale. One section,
// two instances, told apart by `backend`. What differs between them (a login
// page, the operator permission, a management server) shows up only when the
// tunnel carries it.
SectionBase {
  id: root

  required property var vpn
  required property string backend

  // Exit nodes shown before the rest fold into a dropdown, and peers shown
  // when the peer list is open.
  readonly property int shownExitNodes: 4
  readonly property int shownPeers: 12

  readonly property var tunnel: {
    var list = vpn.view.filter(function(t) { return t.backend === root.backend })
    return list.length > 0 ? list[0] : null
  }

  function peerValue(p) {
    var parts = [p.ip]
    if (p.connected) {
      if (p.connectionType !== "") parts.push(p.relayed ? "relay" : p.connectionType)
      if (p.latencyMs > 0) parts.push(p.latencyMs + " ms")
    } else {
      parts.push(p.status.toLowerCase())
    }
    return parts.join(" · ")
  }

  function exitItem(t, e) {
    return {
      type: "toggle", action: "exit", tunnel: t, exitId: e.id,
      glyph: theme.glyphs.exit, title: e.label,
      detail: e.selected ? "Sending all traffic through this peer" : "",
      checked: e.selected, busy: e.pending === true
    }
  }

  items: {
    var out = []
    var t = tunnel
    if (!t) return out
    var prefix = "mesh." + backend

    out.push({
      type: "toggle", action: "toggle", tunnel: t, glyph: theme.glyphs.mesh,
      title: t.label, detail: t.detail,
      checked: t.up || t.connecting, busy: t.connecting
    })
    if (vpn.lastError !== "") out.push({ type: "text", tone: "urgent", text: vpn.lastError })

    if (t.needsLogin) {
      if (t.authUrl) out.push({ type: "button", action: "login", glyph: theme.glyphs.exit, title: "Open the login page" })
      else out.push({ type: "text", tone: "urgent", text: "Login required. Run `" + backend + " up` in a terminal." })
    }
    // Tailscale refuses ordinary users until they are made its operator.
    if (backend === "tailscale" && Tailscale.needsOperator(vpn.lastError))
      out.push({ type: "button", action: "operator", glyph: theme.glyphs.gear, title: "Let this user control Tailscale",
                 detail: "Asks for your password once" })
    if (!t.up) return out

    if (t.ip !== "") out.push({ type: "info", label: "Address", value: t.ip, copy: t.ip })

    var exits = t.exitNodes || []
    if (exits.length > 0) {
      out.push({ type: "header", text: "Exit node" })
      for (var i = 0; i < exits.length && i < shownExitNodes; i++) out.push(exitItem(t, exits[i]))
      if (exits.length > shownExitNodes) {
        out.push({ type: "group", key: prefix + ".exits", text: "More exit nodes", summary: (exits.length - shownExitNodes) + " more" })
        if (isOpen(prefix + ".exits"))
          for (var j = shownExitNodes; j < exits.length; j++) out.push(exitItem(t, exits[j]))
      }
    }

    // Folded: reference material.
    out.push({
      type: "group", key: prefix + ".details", text: "Details",
      summary: t.managementUrl !== "" ? (t.managementOk ? "management connected" : "management unreachable") : t.tailnet
    })
    if (isOpen(prefix + ".details")) {
      if (t.fqdn !== "") out.push({ type: "info", label: "Name", value: t.fqdn, copy: t.fqdn })
      if (t.tailnet) out.push({ type: "info", label: "Tailnet", value: t.tailnet })
      if (t.managementUrl !== "")
        out.push({ type: "info", label: "Management", value: t.managementUrl.replace(/^https?:\/\//, "").replace(/:443$/, ""), bad: !t.managementOk })
    }

    var peers = t.peers || []
    if (peers.length > 0) {
      out.push({ type: "group", key: prefix + ".peers", text: "Peers", summary: t.peersConnected + " of " + t.peersTotal + " connected" })
      if (isOpen(prefix + ".peers")) {
        for (var k = 0; k < peers.length && k < shownPeers; k++)
          out.push({ type: "info", label: peers[k].name, value: peerValue(peers[k]), copy: peers[k].ip })
        if (peers.length > shownPeers)
          out.push({ type: "text", text: (peers.length - shownPeers) + " more peers. Use `" + backend + " status` to list them all." })
      }
    }
    return out
  }

  onItemActivated: function(item) {
    var t = tunnel
    if (item.action === "toggle") {
      // Logged out: the switch cannot work, so send the user to log in.
      if (t && t.needsLogin && t.authUrl) Quickshell.execDetached(["xdg-open", t.authUrl])
      else vpn.toggle(item.tunnel)
    }
    else if (item.action === "exit") vpn.toggleExit(item.tunnel, item.exitId)
    else if (item.action === "login" && t && t.authUrl) Quickshell.execDetached(["xdg-open", t.authUrl])
    else if (item.action === "operator") vpn.runAction(Tailscale.operatorCommand(Quickshell.env("USER")))
  }
}
