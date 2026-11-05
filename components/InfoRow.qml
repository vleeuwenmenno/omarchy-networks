import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Label on the left, value on the right. Every row is a cursor target: Enter or
// a click copies it (the list does the copying), and the value is replaced by
// "Copied" for a moment so you know it worked.
CursorSurface {
  id: row

  required property QtObject theme
  property string label: ""
  property string value: ""
  property string copy: ""
  // Owned by the list, which outlives this row: a poll rebuilds the rows, and
  // the "Copied" mark must not vanish with them.
  property bool copied: false
  property bool cursorOn: false
  property bool good: false
  property bool bad: false

  signal activated()
  signal hovered()


  hasCursor: cursorOn
  foreground: theme.foreground
  fill: theme.hoverFill
  implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight) + Style.spacing.rowPaddingX * 0.6

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.hovered()
    onClicked: row.activated()
  }

  RowLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(12)

    Text {
      id: labelText
      textFormat: Text.PlainText
      text: row.label
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      Layout.preferredWidth: Style.space(92)
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: row.copied ? "\uf00c  Copied" : row.value
      color: row.bad && !row.copied ? row.theme.urgent : row.theme.foreground
      font.bold: row.copied
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
    }
  }
}
