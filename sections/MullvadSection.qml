import QtQuick
import "../model/Mullvad.js" as Mullvad

// Mullvad on its own: the switch, then every location it serves. Countries are
// dropdowns that open onto their cities; a search box narrows the lot. Picking
// a city sets the location and connects; picking the connected one disconnects.
SectionBase {
  id: root

  required property var vpn
  required property var store

  property string query: ""
  // Without a search, only this many countries show up front; the rest sit in
  // one dropdown. With a search, results are capped the same way.
  readonly property int shownCountries: 10
  readonly property int searchLimit: 12

  // The one setting that cuts your own connection takes two clicks.
  property string armed: ""
  Timer { id: armTimer; interval: 5000; onTriggered: root.armed = "" }

  readonly property var favorites: store.get("mullvadFavorites", [])

  function toggleFavorite(code) {
    var cur = favorites.slice()
    var i = cur.indexOf(code)
    if (i >= 0) cur.splice(i, 1)
    else cur.push(code)
    store.set("mullvadFavorites", cur)
  }

  readonly property var tunnel: {
    var list = vpn.view.filter(function(t) { return t.backend === "mullvad" })
    return list.length > 0 ? list[0] : null
  }
  readonly property var location: tunnel && tunnel.location ? tunnel.location : { country: "", city: "", hostname: "" }

  Component.onCompleted: vpn.loadRelays()
  onPanelOpenChanged: if (panelOpen) vpn.loadRelays()

  function isHere(code, city) {
    return tunnel !== null && tunnel.up && location.country === code && (location.city || "") === city
  }

  function isTarget(code, city) {
    return vpn.mullvadSwitching && vpn.mullvadTarget === code + "/" + city
  }

  function countryItems(entry, forceOpen) {
    var c = entry.country
    var out = []
    var key = "mv." + c.code
    var active = tunnel !== null && tunnel.up && location.country === c.code
    var open = isOpen(key) || forceOpen
    var fav = favorites.indexOf(c.code) !== -1
    out.push({
      type: "group", key: key, open: forceOpen, text: c.name,
      summary: active ? "connected" : entry.cities.length + (entry.cities.length === 1 ? " city" : " cities"),
      secondary: fav ? "\uf005" : "\uf006", secondaryOn: fav, secondaryAction: "favorite", country: c.code
    })
    if (!open) return out

    // Any server in the country, unless the search already narrowed to cities.
    if (!entry.cityOnly)
      out.push({
        type: "toggle", action: "location", country: c.code, city: "", indent: true,
        glyph: theme.glyphs.exit, title: "Any city", detail: c.relays + " servers",
        checked: isHere(c.code, ""), busy: isTarget(c.code, "")
      })
    for (var i = 0; i < entry.cities.length; i++) {
      var ci = entry.cities[i]
      out.push({
        type: "toggle", action: "location", country: c.code, city: ci.code, indent: true,
        glyph: theme.glyphs.exit, title: ci.name, detail: ci.relays + (ci.relays === 1 ? " server" : " servers"),
        checked: isHere(c.code, ci.code), busy: isTarget(c.code, ci.code)
      })
    }
    return out
  }

  function settingItem(t, key, title, detail) {
    var on = t.settings[key]
    var pending = (t.settingsPending || []).indexOf(key) !== -1
    var arming = armed === key
    return {
      type: "toggle", action: "setting", key: key, tunnel: t, glyph: theme.glyphs.gear,
      title: title, checked: on, busy: pending,
      detail: arming ? "Click again to confirm. This blocks your internet until Mullvad connects." : detail
    }
  }

  function settingsItems(t) {
    if (!t.settings) return []
    var on = []
    if (t.settings.lockdown) on.push("lockdown")
    if (t.settings.lan) on.push("local network")
    if (t.settings.autoconnect) on.push("auto-connect")
    var out = [{ type: "group", key: "mv.settings", text: "Settings", summary: on.length > 0 ? on.join(" · ") : "defaults" }]
    if (!isOpen("mv.settings")) return out
    out.push(settingItem(t, "lockdown", "Lockdown mode", "Block all traffic while Mullvad is off"))
    out.push(settingItem(t, "lan", "Local network access", "Reach printers and local devices while connected"))
    out.push(settingItem(t, "autoconnect", "Connect on startup", "Bring the tunnel up when the daemon starts"))
    return out
  }

  items: {
    var t = tunnel
    var out = []
    if (!t) return out

    out.push({
      type: "toggle", action: "toggle", tunnel: t, glyph: theme.glyphs.mullvad,
      title: "Mullvad", detail: t.detail,
      checked: t.up || t.connecting,
      // The row being switched to carries the spinner; one is enough.
      busy: t.connecting && !vpn.mullvadSwitching
    })
    if (vpn.lastError !== "") out.push({ type: "text", tone: "urgent", text: vpn.lastError })
    if (t.lockedDown && !t.up)
      out.push({ type: "text", tone: "urgent", text: "Lockdown mode is on: all traffic is blocked until Mullvad connects." })
    if (vpn.note !== "") out.push({ type: "text", text: vpn.note })

    out = out.concat(settingsItems(t))

    out.push({ type: "field", key: "search", label: "", initial: query, placeholder: "Search countries and cities" })

    if (!vpn.relaysLoaded) {
      out.push({ type: "status", text: "Loading locations…" })
      return out
    }

    var results = Mullvad.filterCountries(vpn.relays, query)
    if (query.trim() !== "") {
      if (results.length === 0) {
        out.push({ type: "text", text: "No location matches “" + query.trim() + "”." })
        return out
      }
      // Few matches: open them, so a city search lands on the city.
      var auto = results.length <= 2
      for (var i = 0; i < results.length && i < searchLimit; i++)
        out = out.concat(countryItems(results[i], auto || results[i].cityOnly))
      if (results.length > searchLimit)
        out.push({ type: "text", text: (results.length - searchLimit) + " more matches. Narrow the search." })
      return out
    }

    // No search: favourites on top, then the connected country, then the rest
    // alphabetically.
    var favs = results.filter(function(r) { return favorites.indexOf(r.country.code) !== -1 })
    var rest = results.filter(function(r) { return favorites.indexOf(r.country.code) === -1 })
    rest.sort(function(a, b) {
      var ah = a.country.code === location.country ? 0 : 1
      var bh = b.country.code === location.country ? 0 : 1
      return ah !== bh ? ah - bh : a.country.name.localeCompare(b.country.name)
    })
    if (favs.length > 0) {
      out.push({ type: "header", text: "Favourites" })
      for (var f = 0; f < favs.length; f++) out = out.concat(countryItems(favs[f], false))
      out.push({ type: "header", text: "All countries" })
    }
    for (var j = 0; j < rest.length && j < shownCountries; j++)
      out = out.concat(countryItems(rest[j], false))
    if (rest.length > shownCountries) {
      out.push({ type: "group", key: "mv.more", text: "More countries", summary: (rest.length - shownCountries) + " more" })
      if (isOpen("mv.more"))
        for (var k = shownCountries; k < rest.length; k++) out = out.concat(countryItems(rest[k], false))
    }
    return out
  }

  onFieldEdited: function(key, text) {
    if (key === "search") query = text
  }

  onItemActivated: function(item) {
    if (item.action === "toggle") vpn.toggle(item.tunnel)
    else if (item.action === "location") vpn.connectMullvad(tunnel, item.country, item.city)
    else if (item.action === "favorite") toggleFavorite(item.country)
    else if (item.action === "setting") {
      var turningOn = !item.tunnel.settings[item.key]
      if (item.key === "lockdown" && turningOn && !item.tunnel.up && armed !== "lockdown") {
        armed = "lockdown"
        armTimer.restart()
        return
      }
      armed = ""
      vpn.setMullvadSetting(item.key, turningOn)
    }
  }
}
