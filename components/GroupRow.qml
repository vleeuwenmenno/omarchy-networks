import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A dropdown header: click or Enter folds its rows open and shut. The summary
// shows what is inside while it is closed, so closed is rarely a loss.
CursorSurface {
  id: row

  required property QtObject theme
  property string text: ""
  property string summary: ""
  property bool expanded: false
  property bool cursorOn: false
  property string secondaryGlyph: ""
  property bool secondaryOn: false

  signal activated()
  signal secondaryActivated()
  signal hovered()

  hasCursor: cursorOn
  foreground: theme.foreground
  fill: theme.hoverFill
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX * 0.6

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.hovered()
    onClicked: row.activated()
  }

  RowLayout {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)

    Text {
      text: row.expanded ? "" : ""
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.caption
      Layout.preferredWidth: Style.space(12)
    }

    Text {
      textFormat: Text.PlainText
      text: row.text
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      visible: !row.expanded
      text: row.summary
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight
    }

    Item { Layout.fillWidth: true; visible: row.expanded }

    Text {
      visible: row.secondaryGlyph !== ""
      text: row.secondaryGlyph
      color: row.secondaryOn ? row.theme.foreground : row.theme.dim
      opacity: row.secondaryOn ? 1.0 : 0.6
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.body
      leftPadding: Style.space(6)
      rightPadding: Style.space(2)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.secondaryActivated()
      }
    }
  }
}
