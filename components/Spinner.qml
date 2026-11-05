import QtQuick

// A ring with a gap, turning. Drawn once; the rotation is animated, so a busy
// spinner costs no repaints.
Item {
  id: root

  property color color: "white"
  property real size: 14
  property real thickness: 2
  property bool running: true

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size
  visible: running

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true

    onWidthChanged: requestPaint()
    Connections {
      target: root
      function onColorChanged() { canvas.requestPaint() }
      function onThicknessChanged() { canvas.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var r = (Math.min(width, height) - root.thickness) / 2
      ctx.strokeStyle = root.color
      ctx.lineWidth = root.thickness
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.arc(width / 2, height / 2, r, 0, Math.PI * 1.5, false)
      ctx.stroke()
    }

    RotationAnimator on rotation {
      from: 0
      to: 360
      duration: 850
      loops: Animation.Infinite
      running: root.running
    }
  }
}
