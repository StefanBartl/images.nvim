-- TESTS/redact_spec.lua — `:Image redact`, only the safely testable part.
--
-- `M.open()` opens a real window and draws (`images.terminal.draw`) — that
-- stays unchecked, like `images.zen.open()` in zen_spec.lua. The actual
-- geometry (`images.scale.fit_cells`/`cell_box_to_pixels`) and the burn-in
-- (`images.convert.redact`) are covered in scale_spec.lua/convert_spec.lua.

---@param H table harness from TESTS/run.lua
return function(H)
  local redact = require("images.redact")

  -- ── No window open: is_open/close are safe no-ops ────────────────────────
  H.falsy(redact.is_open(), "no redaction window is open")
  redact.close() -- must not fail
  H.falsy(redact.is_open(), "close() stays a no-op without an open window")
end
