import QtQuick
import Quickshell.Io
import "model/Network.js" as Network

// Latency and packet loss first (a few pings), then download and upload with
// Omarchy's own helper, each over a fixed window. Never runs by itself: a
// speed test is a lot of traffic, so it starts when asked and not before.
Item {
  id: root
  visible: false

  // idle | latency | down | up | done | error
  property string phase: "idle"
  property var ping: null
  property var down: null
  property var up: null
  property string error: ""
  property bool demo: false

  readonly property bool running: phase === "latency" || phase === "down" || phase === "up"

  function start() {
    if (running) return
    if (demo) {
      ping = { loss: 0, min: 9.8, avg: 11.2, max: 14.1, jitter: 1.1 }
      down = { mbps: 468, peak: 512 }
      up = { mbps: 94, peak: 101 }
      phase = "done"
      return
    }
    ping = null
    down = null
    up = null
    error = ""
    phase = "latency"
    pingProcess.running = true
  }

  function stop() {
    if (!running) return
    phase = "idle"
    pingProcess.running = false
    downProcess.running = false
    upProcess.running = false
  }

  Process {
    id: pingProcess
    running: false
    command: Network.PING_ARGS
    stdout: StdioCollector { id: pingOut; waitForEnd: true }
    onExited: function() {
      if (root.phase !== "latency") return
      root.ping = Network.parsePing(String(pingOut.text || ""))
      if (!root.ping || root.ping.loss >= 100) {
        root.error = "No reply from the internet. Check your connection."
        root.phase = "error"
        return
      }
      root.phase = "down"
      downProcess.command = Network.speedArgs("down")
      downProcess.running = true
    }
  }

  // `timeout` ends the helper on purpose, so its exit status says nothing; the
  // numbers it printed do.
  Process {
    id: downProcess
    running: false
    command: []
    stdout: StdioCollector { id: downOut; waitForEnd: true }
    onExited: function() {
      if (root.phase !== "down") return
      root.down = Network.speedFromSamples(String(downOut.text || ""))
      if (!root.down) {
        root.error = "The download test could not start."
        root.phase = "error"
        return
      }
      root.phase = "up"
      upProcess.command = Network.speedArgs("up")
      upProcess.running = true
    }
  }

  Process {
    id: upProcess
    running: false
    command: []
    stdout: StdioCollector { id: upOut; waitForEnd: true }
    onExited: function() {
      if (root.phase !== "up") return
      root.up = Network.speedFromSamples(String(upOut.text || ""))
      if (!root.up) {
        root.error = "The upload test could not start."
        root.phase = "error"
        return
      }
      root.phase = "done"
    }
  }
}
