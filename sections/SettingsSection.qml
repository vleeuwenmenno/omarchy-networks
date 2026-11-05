import QtQuick
import "../model/Tools.js" as Tools

// What the widget shows: which tabs, which adapters. Stored in the state file,
// so it follows you across restarts.
SectionBase {
  id: root

  required property var vpn
  required property var general
  required property var store
  // Which tabs currently have something to show, by id (the panel knows).
  required property var hasContent

  function adapters() {
    var out = []
    general.wired.forEach(function(l) { out.push({ link: l, wireless: false }) })
    general.wireless.forEach(function(l) { out.push({ link: l, wireless: true }) })
    return out
  }

  items: {
    var out = []
    var modes = store.get("tabs", {})

    out.push({ type: "header", text: "Tabs" })
    out.push({ type: "text", text: "Auto shows a tab once its tool is set up. Show keeps it, with install help while it is missing. Hide removes it." })
    Tools.TABS.forEach(function(tab) {
      var present = vpn.installed[tab.tool] === true
      out.push({
        type: "choice", key: "tab:" + tab.id,
        label: tab.label + (present ? "" : "  ·  not installed") + (hasContent[tab.id] ? "" : (present ? "  ·  nothing set up" : "")),
        options: [{ id: "auto", label: "Auto" }, { id: "show", label: "Show" }, { id: "hide", label: "Hide" }],
        value: Tools.tabMode(modes, tab.id)
      })
    })

    out.push({ type: "header", text: "Adapters" })
    var hidden = store.get("hiddenAdapters", [])
    var list = adapters()
    list.forEach(function(a) {
      out.push({
        type: "toggle", action: "adapter", device: a.link.device,
        glyph: a.wireless ? theme.glyphs.wifi : theme.glyphs.ethernet,
        title: (a.wireless ? "Wi-Fi" : "Wired") + " · " + a.link.device,
        detail: a.link.connected ? "Connected" : "Not connected",
        checked: hidden.indexOf(a.link.device) === -1
      })
    })
    if (list.length === 0) out.push({ type: "text", text: "No adapters found yet." })

    out.push({ type: "header", text: "Reset" })
    out.push({ type: "button", action: "reset", glyph: theme.glyphs.refresh, title: "Reset all settings",
               detail: "Tabs to Auto, adapters shown, links folded" })
    return out
  }

  onChoiceSelected: function(key, optionId) {
    if (key.indexOf("tab:") !== 0) return
    var next = {}
    var cur = store.get("tabs", {})
    for (var k in cur) next[k] = cur[k]
    next[key.slice(4)] = optionId
    store.set("tabs", next)
  }

  onItemActivated: function(item) {
    if (item.action === "adapter") {
      var hidden = store.get("hiddenAdapters", []).slice()
      var i = hidden.indexOf(item.device)
      if (i >= 0) hidden.splice(i, 1)
      else hidden.push(item.device)
      store.set("hiddenAdapters", hidden)
    } else if (item.action === "reset") {
      store.set("tabs", {})
      store.set("hiddenAdapters", [])
      store.set("linkOpen", {})
    }
  }
}
