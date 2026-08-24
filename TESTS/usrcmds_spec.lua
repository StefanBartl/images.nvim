-- TESTS/usrcmds_spec.lua — `:Image` dispatch, especially passing the range on.
--
-- A regression test for a real bug: the `list` route originally read
-- `ctx.range.first`/`ctx.range.last`, fields that do not exist on
-- `Lib.UserCmd.Composer.RangeInfo` at all (the real ones are `line1`/`line2`),
-- and no route set `range = true` — so Neovim would never have handed the
-- command a range. `:'<,'>Image list` looked like it worked (no error, no
-- warning) but never actually filtered.
--
-- `images` itself is replaced by a recorder: the routes only have to dispatch
-- correctly, not really draw — that would need a terminal. `package.loaded`
-- must be restored afterwards, or every spec after this one runs against the
-- recorder instead of the real module.

---@param H table harness from TESTS/run.lua
return function(H)
  local cfg = require("images.config").setup({ command = "ImageTest" })
  require("images.bindings.usrcmds").register(cfg)

  local calls = {}
  ---@param name string
  local function record(name)
    return function(...)
      calls[#calls + 1] = { name, ... }
    end
  end

  local real_images = package.loaded["images"]
  package.loaded["images"] = {
    hover = record("hover"),
    show = record("show"),
    list = record("list"),
    gallery = record("gallery"),
    gallery_range = record("gallery_range"),
    step = record("step"),
    info = record("info"),
    paste = record("paste"),
    replace = record("replace"),
    orphans = record("orphans"),
    pin = record("pin"),
    recheck = record("recheck"),
    clear = record("clear"),
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "1", "2", "3", "4", "5" })
  vim.api.nvim_set_current_buf(buf)

  local function run(cmd)
    calls = {}
    vim.cmd(cmd)
    return calls[1]
  end

  -- ── Bare :Image without a range -> hover ─────────────────────────────────
  H.eq(run("ImageTest")[1], "hover", "the bare command without a range shows the image under the cursor")

  -- ── Bare :Image WITH a range -> the range's gallery, not hover ───────────
  local call = run("2,4ImageTest")
  H.eq(call[1], "gallery_range", "the bare command with a range becomes the ranged gallery")
  H.eq(call[2], 2, "…with line1 from the range")
  H.eq(call[3], 4, "…and line2 from the range")

  -- ── :Image list without a range -> nil, nil (the whole buffer) ───────────
  call = run("ImageTest list")
  H.eq(call[1], "list", "list without a range")
  H.eq(call[2], nil, "…no first")
  H.eq(call[3], nil, "…no last")

  -- ── :Image list WITH a range -> the actual lines, not nil ────────────────
  -- This is the regression proper: before the fix `nil, nil` came out here,
  -- because the wrong field names were being read.
  call = run("2,4ImageTest list")
  H.eq(call[1], "list", "list with a range")
  H.eq(call[2], 2, "…line1 arrives")
  H.eq(call[3], 4, "…line2 arrives")

  -- ── :Image gallery [cols] without a range ────────────────────────────────
  call = run("ImageTest gallery")
  H.eq(call[1], "gallery", "gallery without a range calls the buffer-wide variant")
  H.eq(call[2], nil, "…with no path list supplied")

  -- ── :Image gallery [cols] WITH a range, column count included ────────────
  call = run("2,4ImageTest gallery 3")
  H.eq(call[1], "gallery_range", "gallery with a range becomes the ranged gallery")
  H.eq(call[2], 2, "…line1")
  H.eq(call[3], 4, "…line2")
  H.eq(call[4], 3, "…and the column count arrives with it")

  -- ── The remaining subcommands, sampled ───────────────────────────────────
  H.eq(run("ImageTest next")[1], "step", "next dispatches to step")
  H.eq(run("ImageTest next")[2], 1, "…with delta 1")
  H.eq(run("ImageTest prev")[2], -1, "prev with delta -1")
  H.eq(run("ImageTest paste")[1], "paste", "paste dispatches correctly")
  H.eq(run("ImageTest paste")[2], nil, "…without a name: no argument")
  call = run("ImageTest paste shot")
  H.eq(call[1], "paste", "paste with a name dispatches correctly")
  H.eq(call[2], "shot", "…and the name arrives")
  H.eq(run("ImageTest replace")[1], "replace", "replace dispatches correctly")
  H.eq(run("ImageTest orphans")[1], "orphans", "orphans dispatches correctly")
  H.eq(run("ImageTest pin")[1], "pin", "pin dispatches correctly")
  H.eq(run("ImageTest check")[1], "recheck", "check dispatches to recheck")
  H.eq(run("ImageTest clear")[1], "clear", "clear dispatches correctly")

  package.loaded["images"] = real_images
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end
