// Loads QML `.pragma library` scripts under node: strips `.pragma`, resolves
// `.import "X.js" as Y` to the loaded module, evaluates in a sandbox.
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const MODEL = path.join(__dirname, "..", "model")
const cache = {}

function load(name) {
  if (cache[name]) return cache[name]
  const sandbox = {}
  cache[name] = sandbox
  const src = fs.readFileSync(path.join(MODEL, name), "utf8")
    .split("\n")
    .filter((line) => {
      const m = line.match(/^\.import "([^"]+)" as (\w+)/)
      if (m) { sandbox[m[2]] = load(m[1]); return false }
      return !line.startsWith(".pragma")
    })
    .join("\n")
  vm.createContext(sandbox)
  vm.runInContext(src, sandbox, { filename: name })
  return sandbox
}

module.exports = { load }
