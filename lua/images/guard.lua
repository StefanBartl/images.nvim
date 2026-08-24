---@module 'images.guard'
---@brief Terminal capability guard, shared by every draw path.
---@description
--- Warns once per session and draws anyway. A hard refusal would be wrong —
--- detection is a heuristic over environment variables, because OSC 1337 has
--- no capability query, and a false negative would break a working setup. The
--- message therefore names the test that settles the question, and the option
--- that silences it.
---
--- Originally private to `images.init`; moved here as soon as a second and
--- third caller (`images.browse`, `images.zen`) needed the same guard in front
--- of the same draw path — otherwise every caller would carry its own `warned`
--- flag and the warning would appear several times per session.

local M = {}

---@return Lib.Notify.Notifier
local function notify()
  return require("lib.nvim.notify").create("[images]")
end

--- Whether the capability warning has already appeared this session.
---@type boolean
local warned = false

--- Guard before the first draw: can this terminal show images at all?
---@return nil
function M.check()
  local cap = require("images.terminal").capability(require("images.config").get().display.assume_supported)

  if cap.ok then
    -- Even when ok there may be a hint pending, e.g. tmux without passthrough.
    if cap.hint and not warned then
      warned = true
      notify().warn(cap.hint)
    end
    return
  end

  if warned then return end
  warned = true
  notify().warn(table.concat({ cap.reason or "this terminal probably cannot show images", cap.hint }, "\n"))
end

--- Reset the `warned` flag. For `images.recheck()` (after a configuration
--- change) and for tests.
---@return nil
function M.reset()
  warned = false
end

return M
