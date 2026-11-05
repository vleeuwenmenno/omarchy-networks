import QtQuick
import qs.Commons
import qs.Ui

// A labelled text input. The field owns its text: the section is told about
// each edit but never pushes the text back, so rebuilding the list around it
// cannot eat a keystroke. `initial` is read once, when the row is created.
Item {
  id: row

  required property QtObject theme
  property string label: ""
  property string initial: ""
  property string placeholder: ""
  property string error: ""
  property bool password: false
  property bool cursorOn: false
  // Set by the list when this field is the replacement for one that had focus
  // a moment ago: typing in a search box rebuilds the list around it.
  property bool restoreFocus: false
  property int restoreCursor: -1

  readonly property bool editing: input.activeFocus

  signal edited(string text)
  signal accepted()
  signal hovered()
  signal destroyedWhileEditing(int cursorPosition)

  Component.onCompleted: {
    if (!restoreFocus) return
    input.forceActiveFocus()
    input.cursorPosition = restoreCursor >= 0 ? Math.min(restoreCursor, input.length) : input.length
  }
  Component.onDestruction: if (input.activeFocus) destroyedWhileEditing(input.cursorPosition)

  function focusField() { input.forceActiveFocus() }
  function blurField() { input.focus = false }

  implicitHeight: col.implicitHeight + Style.space(6)

  HoverHandler { onHoveredChanged: if (hovered) row.hovered() }

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      textFormat: Text.PlainText
      visible: row.label !== ""
      text: row.label
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    TextField {
      id: input
      width: parent.width
      text: row.initial
      placeholderText: row.placeholder
      password: row.password
      foreground: row.theme.foreground
      hasCursor: row.cursorOn
      selectByMouse: true
      onTextEdited: row.edited(text)
      onAccepted: row.accepted()
      Keys.onTabPressed: row.accepted()
      Keys.onEscapePressed: function(event) { input.focus = false; event.accepted = true }
    }

    Text {
      textFormat: Text.PlainText
      visible: row.error !== ""
      width: parent.width
      text: row.error
      wrapMode: Text.WordWrap
      color: row.theme.urgent
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
