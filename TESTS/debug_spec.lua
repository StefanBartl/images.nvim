-- TESTS/debug_spec.lua — `:Image debug report`'s instrumentation and its
-- `disarm` counterpart.
--
-- `columns`/`float` open real windows and draw generated cards into them —
-- interactive diagnostics, not covered here. What is testable, and pins the
-- actual regression (PRIN-10): `report` used to rewire `images.terminal.draw`
-- for the rest of the session with no restore path anywhere in the plugin,
-- despite `arm()`'s own comment promising one.

---@param H table harness from TESTS/run.lua
return function(H)
  local debug = require("images.debug")
  local term = require("images.terminal")

  local original = term.draw
  H.ok(term.__debug_draw == nil, "starts unarmed: no wrapper left behind by an earlier spec")

  -- ── report arms: draw is wrapped, the untouched original is kept ─────────
  debug.report()
  H.ok(term.draw ~= original, "report() replaces images.terminal.draw with a logging wrapper")
  H.eq(term.__debug_draw, original, "…and keeps the untouched original on the module")

  -- ── disarm puts it back ───────────────────────────────────────────────────
  debug.disarm()
  H.eq(term.draw, original, "disarm() restores the original images.terminal.draw")
  H.ok(term.__debug_draw == nil, "…and forgets the wrapped copy")

  -- ── disarm again is a harmless no-op, not an error ────────────────────────
  local ok = pcall(debug.disarm)
  H.ok(ok, "disarm() when not armed does not throw")
  H.eq(term.draw, original, "…and draw is still the original")

  -- ── re-arming after a disarm wraps the real function again, not the old
  --    wrapper (arm()'s own idempotency guarantee) ─────────────────────────
  debug.report()
  H.eq(term.__debug_draw, original, "a fresh arm keeps the real original, not a stale wrapper")
  debug.disarm()
  H.eq(term.draw, original, "cleaned up: draw is back to the original for the specs that follow")
end
