import QtQuick

// A QR code from a matrix of "0101" rows. Always black on white with a quiet
// zone (the matrix already carries one): scanners need the contrast, so the
// theme does not get a say.
Item {
  id: root

  property var rows: []
  property int maxSize: 260

  readonly property int modules: rows ? rows.length : 0
  readonly property int cell: modules > 0 ? Math.max(2, Math.floor(maxSize / modules)) : 0
  readonly property int side: cell * modules

  implicitHeight: side + 8

  onRowsChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    width: root.side
    height: root.side
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.fillStyle = "#ffffff"
      ctx.fillRect(0, 0, width, height)
      ctx.fillStyle = "#000000"
      var rows = root.rows || []
      for (var y = 0; y < rows.length; y++) {
        var row = rows[y]
        for (var x = 0; x < row.length; x++)
          if (row.charAt(x) === "1") ctx.fillRect(x * root.cell, y * root.cell, root.cell, root.cell)
      }
    }
  }
}
