import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../model/Network.js" as Network

// Live traffic for one interface: current rates, a sparkline each way, and the
// counters since boot (with drops/errors only when there are any).
Item {
  id: root

  required property QtObject theme
  property real rx: 0
  property real tx: 0
  property var rxHistory: []
  property var txHistory: []
  property var counters: null

  implicitHeight: col.implicitHeight + Style.space(8)

  Column {
    id: col
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    Repeater {
      model: [
        { label: "Down", rate: root.rx, history: root.rxHistory, total: root.counters ? root.counters.rx : 0 },
        { label: "Up", rate: root.tx, history: root.txHistory, total: root.counters ? root.counters.tx : 0 }
      ]
      delegate: Column {
        required property var modelData
        width: col.width
        spacing: Style.space(2)

        RowLayout {
          width: parent.width
          Text {
            textFormat: Text.PlainText
            text: modelData.label
            color: root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.preferredWidth: Style.space(92)
          }
          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: Network.formatRate(modelData.rate)
            color: root.theme.foreground
            font.family: root.theme.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: Network.formatBytes(modelData.total) + " total"
            color: root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Sparkline {
          width: parent.width
          height: Style.space(22)
          values: modelData.history
          color: root.theme.foreground
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      color: root.theme.dim
      font.family: root.theme.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: {
        var c = root.counters
        if (!c) return ""
        var drops = c.rxDrop + c.txDrop
        var errs = c.rxErrs + c.txErrs
        var parts = []
        if (drops > 0) parts.push(drops + " dropped")
        if (errs > 0) parts.push(errs + " errors")
        return parts.join(" · ")
      }
    }
  }
}
