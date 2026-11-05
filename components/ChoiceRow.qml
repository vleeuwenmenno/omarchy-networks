import QtQuick
import qs.Commons
import qs.Ui

// A short either/or: DHCP | Static. Click an option, or Enter to cycle.
Item {
  id: row

  required property QtObject theme
  property string label: ""
  property var options: []
  property string value: ""
  property bool cursorOn: false

  signal selected(string optionId)
  signal hovered()

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

    Row {
      spacing: Style.space(6)

      Repeater {
        model: row.options

        delegate: CursorSurface {
          id: chip
          required property var modelData
          readonly property bool chosen: modelData.id === row.value

          current: chosen
          hasCursor: row.cursorOn && chosen
          bordered: !chosen
          foreground: row.theme.foreground
          fill: row.theme.hoverFill
          currentFill: row.theme.selectedFill
          implicitWidth: chipText.implicitWidth + Style.space(24)
          implicitHeight: chipText.implicitHeight + Style.space(10)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.selected(chip.modelData.id)
          }

          Text {
            id: chipText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: chip.modelData.label
            color: chip.chosen ? row.theme.foreground : row.theme.dim
            font.family: row.theme.fontFamily
            font.pixelSize: Style.font.body
            font.bold: chip.chosen
          }
        }
      }
    }
  }
}
