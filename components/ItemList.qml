import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Renders a section from plain data. A section builds `items`; this draws them
// and walks the keyboard cursor over the actionable ones.
//
//   { type: "header", text }
//   { type: "text",   text, tone: "normal" | "dim" | "urgent" }
//   { type: "status", text, busy }                    "Scanning…" with a spinner
//   { type: "info",   label, value, copy }          actionable when `copy` is set
//   { type: "toggle", glyph, title, detail, checked, busy, indent, action,
//                      secondary (glyph), secondaryAction, ... }
//   { type: "button", glyph, title, detail, action, ... }
//   { type: "group", key, text, summary }              dropdown header, actionable
//   { type: "field", key, label, initial, placeholder, error, password }
//   { type: "choice", key, label, options: [{ id, label }], value }
//   { type: "qr", rows }                              a scannable matrix
//   { type: "stats",  rx, tx, rxHistory, txHistory, counters }
//
// Anything else on the item (tunnel, exit id, ...) is passed straight back in
// `activated`, so the section decides what an action means.
Column {
  id: list

  required property QtObject theme
  property var items: []
  property int cursor: 0
  property bool cursorActive: false
  // key -> true for dropdowns that are open.
  property var expanded: ({})

  signal activated(var item)
  signal cursorRequested(int ordinal)
  signal fieldEdited(string key, string text)
  signal choiceSelected(string key, string optionId)

  // Which info row was just copied. Held here, not on the row.
  property string copiedId: ""
  function markCopied(id) { copiedId = id; copiedTimer.restart() }
  Timer { id: copiedTimer; interval: 1400; onTriggered: list.copiedId = "" }

  // True while any text field has keyboard focus: the panel must then leave
  // keys alone, or typing "j" would move the cursor.
  // A field that had focus when the list rebuilt: its replacement takes over.
  property var refocus: ({ key: "", cursor: -1 })
  onItemsChanged: Qt.callLater(function() { list.refocus = { key: "", cursor: -1 } })

  property var editingKeys: ({})
  readonly property bool editing: {
    for (var k in editingKeys) if (editingKeys[k]) return true
    return false
  }
  function _setEditing(key, on) {
    var next = {}
    for (var k in editingKeys) next[k] = editingKeys[k]
    next[key] = on
    editingKeys = next
  }

  spacing: Style.space(2)

  function actionable(item) {
    if (!item) return false
    if (item.type === "toggle" || item.type === "button" || item.type === "group"
        || item.type === "field" || item.type === "choice") return true
    return item.type === "info" && (!!item.copy || !!item.value)
  }

  // Item index -> cursor ordinal, or -1 for rows the cursor skips.
  readonly property var ordinals: {
    var out = []
    var n = 0
    for (var i = 0; i < items.length; i++) out.push(actionable(items[i]) ? n++ : -1)
    return out
  }
  readonly property int count: {
    var n = 0
    for (var i = 0; i < ordinals.length; i++) if (ordinals[i] >= 0) n++
    return n
  }

  function indexOfOrdinal(ordinal) {
    for (var i = 0; i < ordinals.length; i++) if (ordinals[i] === ordinal) return i
    return -1
  }

  function activateOrdinal(ordinal) {
    var i = indexOfOrdinal(ordinal)
    if (i < 0) return
    var item = items[i]
    if (item.type === "info") {
      copyInfo(item)
      markCopied(item.label + "|" + i)
    } else if (item.type === "field") {
      var cell = repeater.itemAt(i)
      if (cell && cell.fieldItem) cell.fieldItem.focusField()
    } else if (item.type === "choice") {
      var idx = 0
      for (var o = 0; o < item.options.length; o++) if (item.options[o].id === item.value) idx = o
      choiceSelected(item.key, item.options[(idx + 1) % item.options.length].id)
    } else {
      activated(item)
    }
  }

  // Enter in a field: on to the next row, editing it if it is a field too.
  function advanceFrom(ordinal) {
    var cur = indexOfOrdinal(ordinal)
    if (cur >= 0) { var c = repeater.itemAt(cur); if (c && c.fieldItem) c.fieldItem.blurField() }
    var nextIndex = indexOfOrdinal(ordinal + 1)
    if (nextIndex < 0) return
    cursorRequested(ordinal + 1)
    var cell = repeater.itemAt(nextIndex)
    if (cell && cell.fieldItem) cell.fieldItem.focusField()
  }

  // Rows with a `copy` text copy that; the rest copy what they show.
  function copyInfo(item) {
    var text = item.copy || item.value
    if (text) Quickshell.execDetached(["wl-copy", String(text)])
  }

  function itemAtOrdinal(ordinal) {
    var i = indexOfOrdinal(ordinal)
    return i >= 0 ? items[i] : null
  }

  // Where the cursor row sits, so the panel can scroll it into view.
  function geometryOf(ordinal) {
    var i = indexOfOrdinal(ordinal)
    var cell = i >= 0 ? repeater.itemAt(i) : null
    return cell ? { y: cell.y, h: cell.height } : null
  }

  Repeater {
    id: repeater
    model: list.items

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      readonly property int ordinal: list.ordinals[index] === undefined ? -1 : list.ordinals[index]
      readonly property bool onCursor: list.cursorActive && ordinal >= 0 && list.cursor === ordinal

      width: list.width
      height: body.implicitHeight
      readonly property var fieldItem: fieldLoader.item

      Column {
        id: body
        width: parent.width

        Loader {
          width: parent.width
          active: cell.modelData.type === "header"
          visible: active
          sourceComponent: Component {
            PanelSectionHeader {
              text: cell.modelData.text.toUpperCase()
              foreground: list.theme.foreground
              fontFamily: list.theme.fontFamily
              topPadding: Style.space(8)
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "text"
          visible: active
          sourceComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: cell.modelData.text
              wrapMode: Text.WordWrap
              color: cell.modelData.tone === "urgent" ? list.theme.urgent : list.theme.dim
              font.family: list.theme.fontFamily
              font.pixelSize: Style.font.bodySmall
              leftPadding: Style.space(10)
              rightPadding: Style.space(10)
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "status"
          visible: active
          sourceComponent: Component {
            Row {
              spacing: Style.space(8)
              leftPadding: Style.space(10)
              Spinner {
                anchors.verticalCenter: parent.verticalCenter
                running: cell.modelData.busy !== false
                size: Style.space(12)
                color: list.theme.dim
              }
              Text {
                textFormat: Text.PlainText
                text: cell.modelData.text
                color: list.theme.dim
                font.family: list.theme.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "info"
          visible: active
          sourceComponent: Component {
            InfoRow {
              theme: list.theme
              label: cell.modelData.label
              value: cell.modelData.value
              copy: cell.modelData.copy || ""
              bad: cell.modelData.bad === true
              cursorOn: cell.onCursor
              onHovered: list.cursorRequested(cell.ordinal)
              copied: list.copiedId === cell.modelData.label + "|" + cell.index
              onActivated: { list.copyInfo(cell.modelData); list.markCopied(cell.modelData.label + "|" + cell.index) }
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "toggle" || cell.modelData.type === "button"
          visible: active
          sourceComponent: Component {
            ToggleRow {
              theme: list.theme
              glyph: cell.modelData.glyph || ""
              title: cell.modelData.title
              detail: cell.modelData.detail || ""
              checked: cell.modelData.type === "toggle" && cell.modelData.checked === true
              busy: cell.modelData.busy === true
              indent: cell.modelData.indent === true
              switchVisible: cell.modelData.type === "toggle"
              secondaryGlyph: cell.modelData.secondary || ""
              switchClickable: cell.modelData.switchClickable === true
              highlightOn: cell.modelData.neutral !== true
              onSwitchActivated: {
                var power = {}
                for (var p in cell.modelData) power[p] = cell.modelData[p]
                power.action = cell.modelData.switchAction
                list.activated(power)
              }
              onSecondaryActivated: {
                var copy = {}
                for (var k in cell.modelData) copy[k] = cell.modelData[k]
                copy.action = cell.modelData.secondaryAction
                list.activated(copy)
              }
              cursorOn: cell.onCursor
              onHovered: list.cursorRequested(cell.ordinal)
              onActivated: list.activated(cell.modelData)
            }
          }
        }

        Loader {
          id: fieldLoader
          width: parent.width
          active: cell.modelData.type === "field"
          visible: active
          sourceComponent: Component {
            FieldRow {
              id: field
              theme: list.theme
              label: cell.modelData.label
              initial: cell.modelData.initial || ""
              placeholder: cell.modelData.placeholder || ""
              error: cell.modelData.error || ""
              password: cell.modelData.password === true
              restoreFocus: list.refocus.key === cell.modelData.key
              restoreCursor: list.refocus.cursor
              onDestroyedWhileEditing: function(pos) { list.refocus = { key: cell.modelData.key, cursor: pos } }
              cursorOn: cell.onCursor
              onEditingChanged: list._setEditing(cell.modelData.key, editing)
              Component.onDestruction: list._setEditing(cell.modelData.key, false)
              onHovered: list.cursorRequested(cell.ordinal)
              onEdited: function(text) { list.fieldEdited(cell.modelData.key, text) }
              onAccepted: list.advanceFrom(cell.ordinal)
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "choice"
          visible: active
          sourceComponent: Component {
            ChoiceRow {
              theme: list.theme
              label: cell.modelData.label || ""
              options: cell.modelData.options
              value: cell.modelData.value
              cursorOn: cell.onCursor
              onHovered: list.cursorRequested(cell.ordinal)
              onSelected: function(optionId) { list.choiceSelected(cell.modelData.key, optionId) }
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "group"
          visible: active
          sourceComponent: Component {
            GroupRow {
              theme: list.theme
              text: cell.modelData.text
              summary: cell.modelData.summary || ""
              expanded: list.expanded[cell.modelData.key] === true || cell.modelData.open === true
              secondaryGlyph: cell.modelData.secondary || ""
              secondaryOn: cell.modelData.secondaryOn === true
              onSecondaryActivated: {
                var copy = {}
                for (var k in cell.modelData) copy[k] = cell.modelData[k]
                copy.type = "secondary"
                copy.action = cell.modelData.secondaryAction
                list.activated(copy)
              }
              cursorOn: cell.onCursor
              onHovered: list.cursorRequested(cell.ordinal)
              onActivated: list.activated(cell.modelData)
            }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "qr"
          visible: active
          sourceComponent: Component {
            QrView { rows: cell.modelData ? cell.modelData.rows : [] }
          }
        }

        Loader {
          width: parent.width
          active: cell.modelData.type === "stats"
          visible: active
          sourceComponent: Component {
            StatsBlock {
              theme: list.theme
              rx: cell.modelData.rx
              tx: cell.modelData.tx
              rxHistory: cell.modelData.rxHistory
              txHistory: cell.modelData.txHistory
              counters: cell.modelData.counters
            }
          }
        }
      }
    }
  }
}
