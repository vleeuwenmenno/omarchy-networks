import QtQuick
import qs.Commons
import qs.Ui

// The panel's tabs, as an even grid: every chip the same size. Up to four tabs
// share one row; five wrap into rows of three, so nothing ever overflows the
// panel or sits ragged. `sections` is [{ id, label, badge, badgeUrgent }].
Grid {
  id: tabs

  required property QtObject theme
  property var sections: []
  property string currentId: ""

  signal selected(string sectionId)

  readonly property int count: Math.max(1, sections.length)
  columns: count <= 4 ? count : 3
  spacing: Style.space(6)
  width: parent ? parent.width : implicitWidth

  readonly property real chipWidth: Math.floor((width - (columns - 1) * spacing) / columns)

  Repeater {
    model: tabs.sections

    delegate: CursorSurface {
      id: chip
      required property var modelData
      readonly property bool isCurrent: modelData.id === tabs.currentId

      current: isCurrent
      bordered: !isCurrent
      foreground: tabs.theme.foreground
      currentFill: tabs.theme.selectedFill
      fill: tabs.theme.hoverFill
      width: tabs.chipWidth
      height: Style.space(30)

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tabs.selected(chip.modelData.id)
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: chip.modelData.label
          color: chip.isCurrent ? tabs.theme.foreground : tabs.theme.dim
          font.family: tabs.theme.fontFamily
          font.pixelSize: Style.font.body
          font.bold: chip.isCurrent
        }

        Rectangle {
          visible: (chip.modelData.badge || "") !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(badgeText.implicitWidth + Style.space(8), height)
          height: badgeText.implicitHeight + Style.space(2)
          radius: height / 2
          color: chip.modelData.badgeUrgent ? tabs.theme.urgent : tabs.theme.selectedFill
          border.width: 1
          border.color: chip.modelData.badgeUrgent ? tabs.theme.urgent : tabs.theme.dim

          Text {
            id: badgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: chip.modelData.badge || ""
            color: chip.modelData.badgeUrgent ? tabs.theme.background : tabs.theme.foreground
            font.family: tabs.theme.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }
}
