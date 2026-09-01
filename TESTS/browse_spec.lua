-- TESTS/browse_spec.lua — filesystem image scanning and scope resolution.
--
-- `M.walk` is a pure function (a real filesystem, but no terminal), just like
-- `orphans.find` — so this tests without drawing. `open()` itself (which opens
-- snacks.picker or falls back to a plain selection) stays unchecked, like every
-- draw path in this suite.

---@param H table harness from TESTS/run.lua
return function(H)
  local browse = require("images.browse")
  require("images.config").setup(nil)

  -- ── walk: finds images, skips configured and fixed exclusions ────────────
  H.tmpdir(function(root)
    H.write(root .. "/a.png", "x")
    H.write(root .. "/notes.txt", "x") -- not an image file
    H.write(root .. "/sub/b.jpg", "x")
    H.write(root .. "/.git/c.png", "x") -- always excluded
    H.write(root .. "/node_modules/d.png", "x") -- excluded by default

    local found = browse.walk(root, { "node_modules" }, { "png", "jpg" })
    table.sort(found)
    H.eq(#found, 2, "exactly two images found")
    H.contains(found[1], "a.png", "a.png is among them")
    H.contains(found[2], "b.jpg", "b.jpg in the subdirectory is among them")

    for _, p in ipairs(found) do
      H.falsy(p:find(".git", 1, true), ".git stays excluded always")
      H.falsy(p:find("node_modules", 1, true), "node_modules stays excluded")
    end
  end)

  -- ── walk: the extension filter is case-insensitive ───────────────────────
  H.tmpdir(function(root)
    H.write(root .. "/upper.PNG", "x")
    local found = browse.walk(root, {}, { "png" })
    H.eq(#found, 1, "the extension is compared case-insensitively")
  end)

  -- ── roots: cwd ──────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local chdir = require("lib.nvim.fs.chdir")
    local normkey = require("lib.nvim.fs.normkey")
    local before = assert(vim.uv.cwd(), "no cwd")
    chdir(root)
    local resolved = browse.roots("cwd", nil)
    chdir(before)
    -- Both sides go through normkey, which expands a Windows 8.3 short name
    -- to its long form. `roots("cwd")` reads `uv.cwd()`, and Windows reports
    -- the long name for a directory entered by its short one, while `root` is
    -- still the raw `tempname()` string -- so a plain compare read
    -- "C:/Users/STEFAN~1/..." vs "C:/Users/StefanBartl/...". Canonicalising
    -- the expectation keeps the assertion about *which directory* was
    -- resolved rather than about how the OS chose to spell it.
    H.eq(normkey(resolved), normkey(root), "cwd resolves to the current working directory")
  end)

  -- ── roots: a nil scope falls back to cwd ─────────────────────────────────
  H.eq(browse.roots(nil, nil), browse.roots("cwd", nil), "no scope means cwd")

  -- ── roots: path ─────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local resolved, err = browse.roots("path", root)
    H.eq(err, nil, "no error for an existing directory")
    H.eq(resolved, require("images.resolve").normalize_path(root), "path resolves to the given folder")
  end)

  local _, err = browse.roots("path", nil)
  H.contains(err or "", "path", "path without a directory yields a comprehensible error")

  _, err = browse.roots("path", "/definitely/no/directory/here")
  H.ok(err ~= nil, "a non-existent directory yields an error")

  -- ── roots: cfile ────────────────────────────────────────────────────────────
  H.tmpdir(function(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_set_current_buf(buf)
    local resolved = browse.roots("cfile", nil)
    H.eq(resolved, require("images.resolve").normalize_path(root), "cfile resolves to the file's directory")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  -- ── roots: an unknown scope ──────────────────────────────────────────────
  local _, unknown_err = browse.roots("nonsense", nil)
  H.ok(unknown_err ~= nil, "an unknown scope yields an error")

  -- ── snacks_available: returns a boolean without drawing ──────────────────
  H.ok(type(browse.snacks_available()) == "boolean", "snacks_available is a boolean")
end
