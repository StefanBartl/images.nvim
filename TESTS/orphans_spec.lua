-- TESTS/orphans_spec.lua — finding orphaned images in the target directory.
--
-- Needs a real filesystem and a named buffer (target_dir depends on
-- `nvim_buf_get_name`), so it is not a pure module like gallery/resolve/info —
-- but still testable without a terminal, which is what this shows.

---@param H table harness from TESTS/run.lua
return function(H)
  local orphans = require("images.orphans")
  require("images.config").setup(nil) -- default paste.dir = "assets"

  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(root .. "/assets", "p")

  ---@param path string
  local function touch(path)
    local fd = assert(io.open(path, "wb"))
    fd:write("x")
    fd:close()
  end

  touch(root .. "/assets/a.png")
  touch(root .. "/assets/b.png")
  touch(root .. "/assets/notes.txt") -- not an image file, must be ignored

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![a](assets/a.png)" })
  -- A buffer name is only anchored on disk after the first write/:write; but
  -- `resolve.to_path` merely runs `fs_stat` on the computed path, which already
  -- follows from the (as yet unsaved) name.

  -- ── a.png is referenced, b.png is not ────────────────────────────────────
  local found = orphans.find(buf)
  H.eq(#found, 1, "exactly one image is orphaned")
  H.eq(found[1].rel, "b.png", "…namely the unreferenced one")

  -- ── Once linked, nothing is orphaned any more ────────────────────────────
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "![b](assets/b.png)" })
  found = orphans.find(buf)
  H.eq(#found, 0, "both referenced -> no orphans left")

  -- ── No target directory: no error, an empty list ─────────────────────────
  local other_root = vim.fn.tempname()
  vim.fn.mkdir(other_root, "p")
  local other_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(other_buf, other_root .. "/doc.md")
  found = orphans.find(other_buf)
  H.eq(#found, 0, "a missing target directory yields an empty list, not an error")

  -- ── Non-image files are not counted ──────────────────────────────────────
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  found = orphans.find(buf)
  local rels = {}
  for _, o in ipairs(found) do
    rels[o.rel] = true
  end
  H.falsy(rels["notes.txt"], "notes.txt is not an image and does not appear")
  H.ok(rels["a.png"] and rels["b.png"], "both images are now unreferenced")

  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  pcall(vim.api.nvim_buf_delete, other_buf, { force = true })
end
