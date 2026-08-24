-- TESTS/paste_target_spec.lua — `:Image paste`'s target directory logic.
--
-- Covers three real fixes, all without a real clipboard: `paste_with_name` and
-- `capture_with_optional_name` take `capture` as a parameter, so a fake
-- suffices (the same trick orphans_spec.lua uses for filesystem tests without a
-- terminal).
--
--   1. When `capture` fails (no image in the clipboard), NO target directory is
--      created — `target_paths` used to create it before it was even settled
--      whether there was anything to write into it.
--   2. When the document's directory already holds "Resources" or "Ressourcen",
--      that one is used instead of `paste.dir` ("assets"), and no second
--      directory appears.
--   3. `:Image paste {name}` (direct_name) skips every name prompt and uses the
--      given name directly.

---@param H table harness from TESTS/run.lua
return function(H)
  local paste = require("images.paste")
  require("images.config").setup(nil) -- default paste.dir = "assets"

  ---@param root string
  ---@return integer buf
  local function make_buf(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    return buf
  end

  ---@param ok boolean
  ---@return fun(out: string, cb: fun(ok: boolean, err: string|nil))
  local function fake_capture(ok)
    return function(out, cb)
      if ok then
        local fd = assert(io.open(out, "wb"))
        fd:write("x")
        fd:close()
        cb(true)
      else
        cb(false, "no image in the clipboard")
      end
    end
  end

  -- ── 1. A failed capture creates no target directory ──────────────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, nil, fake_capture(false))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "no image in the clipboard -> no assets folder")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 1b. A successful capture creates the directory and writes into it ────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 1, "a successful capture creates assets")
    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "…and the file lands inside it")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.ok(lines[1]:find("assets/shot.png", 1, true) ~= nil, "the link is inserted: " .. lines[1])
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 2. An existing "Resources" folder is used instead of "assets" ────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.mkdir(root .. "/Resources", "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "no additional assets folder")
    H.eq(vim.fn.filereadable(root .. "/Resources/shot.png"), 1, "the file lands in the existing Resources folder")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 2b. "Ressourcen" (German) is recognised too, case-insensitively ──────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.mkdir(root .. "/ressourcen", "p") -- lower case
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true))

    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "no additional assets folder")
    H.eq(
      vim.fn.filereadable(root .. "/ressourcen/shot.png"),
      1,
      "the file lands in the existing ressourcen folder (matched case-insensitively)"
    )
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 3. direct_name skips every prompt and is used directly ───────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)
    vim.api.nvim_set_current_buf(buf)

    paste.capture_with_optional_name(fake_capture(true), "my image")

    H.eq(vim.fn.filereadable(root .. "/assets/my image.png"), 1, "direct_name is sanitised and used directly, with no prompt")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 3b. A direct_name left empty by sanitising aborts ────────────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)
    vim.api.nvim_set_current_buf(buf)

    local ok = pcall(paste.capture_with_optional_name, fake_capture(true), "..")
    H.ok(ok, "an invalid direct_name does not throw, it only reports an error")
    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, "…and creates no directory")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end
