import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One switchable thing: a tunnel, an exit node. The row owns the click, mouse
// and keyboard alike, so the switch itself is display only.
CursorSurface {
  id: row

  required property QtObject theme
  property string glyph: ""
  property string title: ""
  property string detail: ""
  property bool checked: false
  property bool busy: false
  property bool indent: false
  property bool dimmed: false
  property bool switchVisible: true
  property string secondaryGlyph: ""
  // When true the switch is its own click target and the rest of the row does
  // something else (a link's header folds; its switch powers it).
  property bool switchClickable: false
  // Rows that are headers rather than choices keep the plain background when
  // on; the switch already says so.
  property bool highlightOn: true
  property bool cursorOn: false

  signal activated()
  signal secondaryActivated()
  signal switchActivated()
  signal hovered()

  hasCursor: cursorOn
  current: highlightOn && checked && !indent
  foreground: theme.foreground
  fill: theme.hoverFill
  currentFill: theme.selectedFill
  implicitHeight: layout.implicitHeight + Style.spacing.rowPaddingX

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
    anchors.leftMargin: Style.space(10) + (row.indent ? Style.space(22) : 0)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)

    Text {
      text: row.glyph
      color: row.checked ? row.theme.foreground : row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.body
      Layout.preferredWidth: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: row.title
        color: row.checked ? row.theme.foreground : row.theme.dim
        font.family: row.theme.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        Layout.fillWidth: true
        text: row.detail
        color: row.theme.dim
        font.family: row.theme.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }

    Text {
      visible: row.secondaryGlyph !== ""
      text: row.secondaryGlyph
      color: row.theme.dim
      font.family: row.theme.fontFamily
      font.pixelSize: Style.font.body
      Layout.alignment: Qt.AlignVCenter
      leftPadding: Style.space(6)
      rightPadding: Style.space(6)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.secondaryActivated()
      }
    }

    Item {
      id: control
      visible: row.switchVisible || row.busy
      implicitWidth: sw.implicitWidth
      implicitHeight: sw.implicitHeight
      Layout.alignment: Qt.AlignVCenter

      ToggleSwitch {
        id: sw
        visible: row.switchVisible
        checked: row.checked
        busy: row.busy
        interactive: row.switchClickable
        // The row draws the cursor; the switch only reacts to being pointed at,
        // and only when it is its own target. Two frames made it look doubled.
        hasCursor: false
        cursorRing: row.switchClickable
        onToggled: row.switchActivated()
        foreground: row.theme.foreground
        // Muted while busy, so the spinner is the only thing that reads.
        opacity: row.busy ? 0.25 : 1.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }

      // Busy: a disc over the knob's track with the spinner in it, so the
      // switch visibly waits instead of just ignoring clicks.
      Rectangle {
        visible: row.busy && row.switchVisible
        anchors.centerIn: parent
        width: sw.knobSize + Style.space(6)
        height: width
        radius: width / 2
        color: row.theme.background
        border.width: 1
        border.color: row.theme.dim
      }

      Spinner {
        anchors.centerIn: parent
        running: row.busy
        size: row.switchVisible ? sw.knobSize : Style.space(14)
        color: row.theme.foreground
      }
    }
  }
}
