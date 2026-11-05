import QtQuick

// Every tunnel except NetBird (which has its own section). Each switch is
// independent: split-tunnel VPNs are meant to run side by side.
SectionBase {
  id: root

  required property var vpn

  readonly property var tunnels: vpn.view.filter(function(t) { return t.kind !== "mesh" && t.backend !== "mullvad" })

  items: {
    var out = []
    if (vpn.warning !== "") out.push({ type: "text", tone: "urgent", text: vpn.warning })
    if (vpn.note !== "") out.push({ type: "text", text: vpn.note })
    if (vpn.lastError !== "") out.push({ type: "text", tone: "urgent", text: vpn.lastError })

    for (var i = 0; i < tunnels.length; i++) {
      var t = tunnels[i]
      out.push({
        type: "toggle", action: "toggle", tunnel: t,
        glyph: theme.glyphs[t.kind] || theme.glyphs.vpn,
        title: t.label, detail: t.detail,
        checked: t.up || t.connecting, busy: t.connecting
      })
    }
    if (tunnels.length === 0)
      out.push(vpn.loaded
        ? { type: "text", text: "No tunnels yet. Install Mullvad, or import a WireGuard / OpenVPN profile into NetworkManager." }
        : { type: "status", text: "Checking…" })
    return out
  }

  onItemActivated: function(item) {
    if (item.action === "toggle") vpn.toggle(item.tunnel)
  }
}
