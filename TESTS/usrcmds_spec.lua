-- TESTS/usrcmds_spec.lua — `:Image`-Dispatch, insbesondere Range-Weitergabe.
--
-- Regressionstest für einen echten Bug: die `list`-Route las ursprünglich
-- `ctx.range.first`/`ctx.range.last`, Felder, die auf
-- `Lib.UserCmd.Composer.RangeInfo` gar nicht existieren (die echten heißen
-- `line1`/`line2`), und keine Route setzte `range = true` — Neovim hätte dem
-- Command also nie einen Range übergeben. `:'<,'>Image list` sah aus wie es
-- funktioniert (kein Fehler, keine Warnung), filterte aber nie wirklich.
--
-- `images` selbst wird durch einen Aufzeichner ersetzt: die Routen sollen nur
-- korrekt dispatchen, nicht wirklich zeichnen — das würde ein Terminal
-- brauchen. `package.loaded` wird danach zwingend zurückgesetzt, sonst
-- arbeiten alle Specs nach diesem mit dem Aufzeichner statt dem echten Modul.

---@param H table Harness aus TESTS/run.lua
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

  -- ── Bare :Image ohne Range → hover ─────────────────────────────────────────
  H.eq(run("ImageTest")[1], "hover", "bare Command ohne Range zeigt das Bild unter dem Cursor")

  -- ── Bare :Image MIT Range → Galerie des Bereichs, nicht hover ──────────────
  local call = run("2,4ImageTest")
  H.eq(call[1], "gallery_range", "bare Command mit Range wird zur Bereichs-Galerie")
  H.eq(call[2], 2, "…mit line1 aus dem Range")
  H.eq(call[3], 4, "…und line2 aus dem Range")

  -- ── :Image list ohne Range → nil, nil (ganzer Buffer) ──────────────────────
  call = run("ImageTest list")
  H.eq(call[1], "list", "list ohne Range")
  H.eq(call[2], nil, "…kein first")
  H.eq(call[3], nil, "…kein last")

  -- ── :Image list MIT Range → tatsächliche Zeilen, nicht nil ─────────────────
  -- Das ist die eigentliche Regression: vor dem Fix wären hier `nil, nil`
  -- herausgekommen, weil die falschen Feldnamen gelesen wurden.
  call = run("2,4ImageTest list")
  H.eq(call[1], "list", "list mit Range")
  H.eq(call[2], 2, "…line1 kommt an")
  H.eq(call[3], 4, "…line2 kommt an")

  -- ── :Image gallery [cols] ohne Range ────────────────────────────────────────
  call = run("ImageTest gallery")
  H.eq(call[1], "gallery", "gallery ohne Range ruft die Buffer-weite Variante")
  H.eq(call[2], nil, "…keine Pfadliste vorgegeben")

  -- ── :Image gallery [cols] MIT Range, inklusive Spaltenzahl ─────────────────
  call = run("2,4ImageTest gallery 3")
  H.eq(call[1], "gallery_range", "gallery mit Range wird zur Bereichs-Galerie")
  H.eq(call[2], 2, "…line1")
  H.eq(call[3], 4, "…line2")
  H.eq(call[4], 3, "…und die Spaltenzahl kommt mit an")

  -- ── Übrige Subcommands, stichprobenartig ───────────────────────────────────
  H.eq(run("ImageTest next")[1], "step", "next dispatcht auf step")
  H.eq(run("ImageTest next")[2], 1, "…mit delta 1")
  H.eq(run("ImageTest prev")[2], -1, "prev mit delta -1")
  H.eq(run("ImageTest paste")[1], "paste", "paste dispatcht korrekt")
  H.eq(run("ImageTest paste")[2], nil, "…ohne Namen: kein Argument")
  call = run("ImageTest paste shot")
  H.eq(call[1], "paste", "paste mit Namen dispatcht korrekt")
  H.eq(call[2], "shot", "…und der Name kommt an")
  H.eq(run("ImageTest replace")[1], "replace", "replace dispatcht korrekt")
  H.eq(run("ImageTest orphans")[1], "orphans", "orphans dispatcht korrekt")
  H.eq(run("ImageTest pin")[1], "pin", "pin dispatcht korrekt")
  H.eq(run("ImageTest check")[1], "recheck", "check dispatcht auf recheck")
  H.eq(run("ImageTest clear")[1], "clear", "clear dispatcht korrekt")

  package.loaded["images"] = real_images
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end
