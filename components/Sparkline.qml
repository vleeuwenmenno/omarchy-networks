import QtQuick

// Bars for the last N samples, scaled to the largest one on screen (with a
// floor, so an idle link does not blow idle noise up to full height).
Item {
  id: root

  property var values: []
  property int slots: 40
  property real floor: 8 * 1024
  property color color: "white"

  readonly property real peak: {
    var m = root.floor
    for (var i = 0; i < values.length; i++) if (values[i] > m) m = values[i]
    return m
  }

  implicitHeight: 26

  Row {
    anchors.fill: parent
    spacing: 1
    layoutDirection: Qt.LeftToRight

    Repeater {
      model: root.slots
      delegate: Item {
        required property int index
        readonly property int offset: root.slots - root.values.length
        readonly property real v: index >= offset ? root.values[index - offset] : 0
        width: (root.width - (root.slots - 1)) / root.slots
        height: root.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(v > 0 ? 1 : 0, Math.round(parent.height * (v / root.peak)))
          color: root.color
          opacity: 0.85
        }
      }
    }
  }
}
