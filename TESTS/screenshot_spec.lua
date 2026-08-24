-- TESTS/screenshot_spec.lua — availability detection for `:Image screenshot`.
--
-- Only `available()`/`unavailable_reason()` are covered here: pure queries of
-- `vim.fn.has`/`executable`, without triggering a real capture. The capture
-- path itself launches an external, interactive tool (Snipping
-- Tool/screencapture/grim+slurp/maim) and therefore cannot be automated
-- meaningfully — neither headless nor without a human at the mouse. The same
-- boundary as the real download in images.remote, likewise only verified
-- manually rather than committed.

---@param H table harness from TESTS/run.lua
return function(H)
  local screenshot = require("images.screenshot")

  -- `available()` must run through cleanly whatever the actual result -- on
  -- every platform the suite runs on (here: the CI platform or the local
  -- machine), not only the one the concrete result applies to.
  local ok, available = pcall(screenshot.available)
  H.ok(ok, "available() does not throw: " .. tostring(available))
  H.ok(type(available) == "boolean", "available() returns a boolean")

  if not available then
    local ok2, reason = pcall(screenshot.unavailable_reason)
    H.ok(ok2, "unavailable_reason() does not throw: " .. tostring(reason))
    H.ok(type(reason) == "string" and #reason > 0, "…and returns a non-empty reason")
  end

  -- On Windows it is always available (ms-screenclip: ships with the system, no
  -- separate tool needed) -- the one case that can be checked unambiguously
  -- without mocking the platform.
  if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    H.ok(available, "always available on Windows (ms-screenclip: needs no external tool)")
  end
end
