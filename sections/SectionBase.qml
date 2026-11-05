import QtQuick
import "../components"

// Contract every section follows. The panel only ever talks to these:
//
//   rowCount            how many rows the keyboard cursor can land on
//   activateCursor()    Enter on the current row
//   cursorGeometry()    { y, h } of the current row, for scrolling it into view
//   cursorRequested(n)  mouse hover moved the cursor to row n
//   closeRequested()    the section wants the panel closed
//   editing             a text field has focus: the panel must not eat keys
//   hasSubPage          Esc should call backRequested() instead of closing
//   textKey(t)          optional: a letter key the section wants
//   groupToggled(key)   a dropdown header was activated; the panel owns the state
//
// A section supplies `items` (see components/ItemList.qml) and reacts to
// `itemActivated`. It knows its own controller(s); the panel does not.
Item {
  id: root

  required property QtObject theme
  property var items: []
  property int cursor: 0
  property bool cursorActive: false
  // Sections that keep sub-pages fall back to their first page on close.
  property bool panelOpen: false
  // Which dropdowns are open (key -> true). Owned by the panel, so a section
  // that is rebuilt keeps its folds.
  property var expanded: ({})

  function isOpen(key) { return expanded[key] === true }

  property bool hasSubPage: false
  readonly property bool editing: list.editing

  signal backRequested()
  signal textKeyPressed(string key)
  signal fieldEdited(string key, string text)
  signal choiceSelected(string key, string optionId)
  signal groupToggled(string key)
  signal cursorRequested(int ordinal)
  signal closeRequested()
  signal itemActivated(var item)

  readonly property int rowCount: list.count
  implicitHeight: list.implicitHeight

  function activateCursor() { list.activateOrdinal(cursor) }
  function itemAtCursor() { return list.itemAtOrdinal(cursor) }
  function textKey(t) { textKeyPressed(t) }
  function cursorGeometry() { return list.geometryOf(cursor) }

  ItemList {
    id: list
    width: parent.width
    theme: root.theme
    items: root.items
    cursor: root.cursor
    cursorActive: root.cursorActive
    expanded: root.expanded
    onCursorRequested: function(ordinal) { root.cursorRequested(ordinal) }
    onFieldEdited: function(key, text) { root.fieldEdited(key, text) }
    onChoiceSelected: function(key, optionId) { root.choiceSelected(key, optionId) }
    onActivated: function(item) {
      if (item.type === "group") root.groupToggled(item.key)
      else root.itemActivated(item)
    }
  }
}
