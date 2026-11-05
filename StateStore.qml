import QtQuick
import Quickshell
import Quickshell.Io

// Small persistent state (favourites, ...) in one JSON file under
// ~/.local/state/omarchy. Not the widget's shell.json entry: writing that
// reloads the bar, and a star click must not close the panel.
Item {
  id: root
  visible: false

  property string name: "menno-networks.json"
  // Off for demo data: kept in memory, never written, never read from disk.
  property bool persist: true
  property var data: ({})
  readonly property string path: Quickshell.env("HOME") + "/.local/state/omarchy/" + name

  function get(key, fallback) {
    var v = data[key]
    return v === undefined ? fallback : v
  }

  function set(key, value) {
    var next = {}
    for (var k in data) next[k] = data[k]
    next[key] = value
    data = next
    if (persist) file.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: file
    path: root.persist ? root.path : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.data = parsed && typeof parsed === "object" && !(parsed instanceof Array) ? parsed : ({})
      } catch (e) { root.data = ({}) }
    }
    onLoadFailed: root.data = ({})
  }
}
