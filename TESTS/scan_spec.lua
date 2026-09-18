-- TESTS/scan_spec.lua — images.scan: every image link in a buffer, split
-- into what resolves and what does not, optionally restricted to a line
-- range (`:'<,'>Image list`'s own restriction).

---@param H table harness from TESTS/run.lua
return function(H)
  require("images.config").setup(nil) -- defaults, for `extensions`
  local scan = require("images.scan")

  -- ── an invalid buffer is a clean empty result, not an error ───────────────
  local found, missing = scan.buffer(999999)
  H.eq(#found, 0, "an invalid buffer yields no targets")
  H.eq(#missing, 0, "…and no unresolvable ones either")

  H.tmpdir(function(dir)
    H.write(dir .. "/a.png", "not a real png, existence is all that matters here")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, dir .. "/notes.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "line 1: no link here",
      "line 2: ![a](a.png)",
      "line 3: ![missing](nope.png)",
      "line 4: [not an image](a.md)",
      "line 5: ![a](a.png) again",
    })
    vim.api.nvim_set_current_buf(buf)

    -- ── whole buffer: resolved hits and unresolvable ones split correctly ──
    found, missing = scan.buffer(buf)
    H.eq(#found, 2, "both existing image links resolve (line 4's non-image link is not among them)")
    H.eq(#missing, 1, "the one image link that does not resolve is reported separately")
    H.eq(missing[1], "nope.png", "…named by its raw target")
    H.eq(found[1].lnum, 2, "found entries carry their real line number")
    H.eq(found[2].lnum, 5, "…for every hit, not just the first")
    H.ok(found[1].path:sub(-5) == "a.png", "found entries carry the resolved absolute path: " .. found[1].path)
    H.eq(found[1].raw, "a.png", "…alongside the raw (unresolved) link text")

    -- ── line-range restriction: real line numbers survive, not range-relative ones ─
    found, missing = scan.buffer(buf, 1, 2)
    H.eq(#found, 1, "restricting to lines 1-2 finds only the first hit")
    H.eq(found[1].lnum, 2, "…still numbered from the top of the buffer")

    found, missing = scan.buffer(buf, 4, 5)
    H.eq(#found, 1, "restricting to lines 4-5 finds only the last hit")
    H.eq(found[1].lnum, 5, "…correctly numbered despite the range not starting at 1")
    H.eq(#missing, 0, "…and the unresolvable link on line 3 is outside the range")

    found, missing = scan.buffer(buf, 3, 3)
    H.eq(#found, 0, "a range with no resolvable image finds nothing")
    H.eq(#missing, 1, "…but the unresolvable one inside the range is still reported")

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)
end
