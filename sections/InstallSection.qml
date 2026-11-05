import QtQuick
import Quickshell
import "../model/Tools.js" as Tools

// Shown for a tab whose tool is missing or not set up yet: what it is, and
// the commands to get it going. Copy a command, or let Omarchy run the safe
// ones in a terminal. Nothing runs without a click.
SectionBase {
  id: root

  required property var vpn
  required property string tabId

  readonly property var guide: Tools.GUIDES[tabId]
  readonly property string state: Tools.guideState(tabId, vpn.installed)

  items: {
    var out = []
    var g = guide
    if (!g) return out

    out.push({ type: "header", text: state === "missing" ? g.name + " is not installed" : g.name + " is not set up yet" })
    out.push({ type: "text", text: g.note })

    var steps = Tools.stepsFor(tabId, state)
    for (var i = 0; i < steps.length; i++) {
      var st = steps[i]
      out.push({ type: "info", label: st.label, value: st.command, copy: st.command })
      if (st.run)
        out.push({ type: "button", action: "run", command: st.command, glyph: theme.glyphs.gear,
                   title: "Run it in a terminal" })
    }
    if (Tools.safeUrl(g.docs))
      out.push({ type: "button", action: "docs", url: g.docs, glyph: theme.glyphs.exit, title: "Open the install guide" })
    out.push({ type: "text", text: "This tab appears by itself once it is set up. Hide it in settings (the cog) if you do not use it." })
    return out
  }

  onItemActivated: function(item) {
    if (item.action === "run")
      Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", item.command])
    else if (item.action === "docs" && Tools.safeUrl(item.url))
      Quickshell.execDetached(["xdg-open", item.url])
  }
}
