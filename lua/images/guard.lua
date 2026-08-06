---@module 'images.guard'
---@brief Terminal-Fähigkeits-Guard, gemeinsam für jeden Zeichenpfad.
---@description
--- Warnt einmal pro Sitzung und lässt trotzdem zeichnen. Ein harter Abbruch
--- wäre falsch — die Erkennung ist eine Heuristik über Umgebungsvariablen,
--- weil OSC 1337 keine Fähigkeitsabfrage kennt, und ein Fehlalarm würde ein
--- funktionierendes Setup abwürgen. Die Meldung nennt deshalb den Test, mit
--- dem sich das klären lässt, und die Option, die sie abstellt.
---
--- Ursprünglich privat in `images.init`; hierher gezogen, sobald ein zweiter
--- und dritter Aufrufer (`images.browse`, `images.zen`) denselben Guard vor
--- demselben Zeichenpfad brauchten — sonst würde jeder Aufrufer sein eigenes
--- `warned`-Flag mitschleppen und die Warnung mehrfach pro Sitzung zeigen.

local M = {}

---@return table notify-Handle aus lib.nvim
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Ob die Fähigkeitswarnung in dieser Sitzung schon erschienen ist.
---@type boolean
local warned = false

--- Guard vor dem ersten Zeichnen: kann dieses Terminal überhaupt Bilder?
---@return nil
function M.check()
  local cap = require("images.terminal").capability(require("images.config").get().display.assume_supported)

  if cap.ok then
    -- Auch bei ok kann ein Hinweis anstehen, etwa tmux ohne passthrough.
    if cap.hint and not warned then
      warned = true
      notify().warn(cap.hint)
    end
    return
  end

  if warned then return end
  warned = true
  notify().warn(table.concat({ cap.reason or "Terminal kann vermutlich keine Bilder", cap.hint }, "\n"))
end

--- `warned`-Flag zurücksetzen. Für `images.recheck()` (nach einer
--- Konfigurationsänderung) und für Tests.
---@return nil
function M.reset()
  warned = false
end

return M
