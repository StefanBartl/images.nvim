-- TESTS/paste_create_dir_spec.lua — `:Image paste` into a target directory that
-- does not exist yet asks first, through lib.nvim's `kit.create_on_missing`
-- (ui.nvim's `ui.kit.create_on_missing`): Create goes on with the paste,
-- anything else leaves everything as it was (no directory, no file, no link).
--
-- The dialog is answered with the kit's dialog hook, so no window opens. A
-- hooked answer arrives on the next loop turn, hence the `vim.wait`s.

---@param H table harness from TESTS/run.lua
return function(H)
  local paste = require("images.paste")
  local config = require("images.config")
  local hook = require("lib.nvim.ui.kit.hook")

  ---@param root string
  ---@return integer buf
  local function make_buf(root)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, root .. "/doc.md")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  --- A capture that writes one byte and remembers where.
  ---@return fun(out: string, cb: fun(ok: boolean, err: string|nil)) capture
  ---@return fun(): string|nil written the temp file the capture wrote
  local function fake_capture()
    local written
    return function(out, cb)
      written = out
      local fd = assert(io.open(out, "wb"))
      fd:write("x")
      fd:close()
      cb(true)
    end, function()
      return written
    end
  end

  --- Answer every dialog with `answer` and record what was asked.
  ---@param answer any
  ---@return table[] asked { kind, opts } per dialog
  local function answer_with(answer)
    local asked = {}
    hook.set(function(kind, opts)
      asked[#asked + 1] = { kind = kind, opts = opts }
      return true, answer
    end)
    return asked
  end

  local function fresh_root()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    return root
  end

  config.setup({ paste = { link_cursor = { startinsert = false } } })

  -- ── 1. Create: the directory is made and the paste goes on ───────────────
  do
    local root = fresh_root()
    local buf = make_buf(root)
    local asked = answer_with("Create")
    local capture = fake_capture()

    paste.paste_with_name(buf, "shot.png", capture)
    vim.wait(2000, function()
      return vim.fn.filereadable(root .. "/assets/shot.png") == 1
    end)
    hook.set(nil)

    H.eq(#asked, 1, "a missing target directory asks once")
    H.eq(asked[1] and asked[1].kind, "confirm", "…through the kit's confirm (create_on_missing)")
    local question = asked[1] and asked[1].opts.question or ""
    H.ok(question:find("assets/", 1, true) ~= nil, "the question names the directory: " .. question)
    H.eq(asked[1] and asked[1].opts.title, "Create directory?", "…and asks for a directory")
    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "Create: the image lands in the new directory")
    local line = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
    H.ok(line:find("assets/shot.png", 1, true) ~= nil, "Create: the link is inserted: " .. line)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 2. Cancel / a dismissed dialog: everything stays as it was ───────────
  for _, answer in ipairs({ "Cancel", false }) do
    local label = answer and answer or "dismissed"
    local root = fresh_root()
    local buf = make_buf(root)
    local asked = answer_with(answer or nil)
    local capture, written = fake_capture()

    paste.paste_with_name(buf, "shot.png", capture)
    vim.wait(2000, function()
      local tmp = written()
      return tmp ~= nil and vim.fn.filereadable(tmp) == 0
    end)
    hook.set(nil)

    H.eq(#asked, 1, label .. ": the question was asked")
    H.eq(vim.fn.isdirectory(root .. "/assets"), 0, label .. ": no directory is created")
    H.eq(#vim.fn.readdir(root), 0, label .. ": nothing at all is written next to the document")
    H.eq(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "|"), "", label .. ": no link is inserted")
    H.eq(vim.fn.filereadable(written() or ""), 0, label .. ": the captured temp file is removed")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 3. An existing directory asks nothing ────────────────────────────────
  do
    local root = fresh_root()
    vim.fn.mkdir(root .. "/assets", "p")
    local buf = make_buf(root)
    local asked = answer_with("Cancel")

    paste.paste_with_name(buf, "shot.png", (fake_capture()))
    hook.set(nil)

    H.eq(#asked, 0, "an existing target directory asks nothing")
    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "…and the image is written right away")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 4. confirm_create_dir = false: created silently, as before ───────────
  do
    config.setup({ paste = { confirm_create_dir = false, link_cursor = { startinsert = false } } })
    local root = fresh_root()
    local buf = make_buf(root)
    local asked = answer_with("Cancel")

    paste.paste_with_name(buf, "shot.png", (fake_capture()))
    hook.set(nil)

    H.eq(#asked, 0, "confirm_create_dir = false asks nothing")
    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "…and creates the directory itself")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  config.setup({}) -- restore the plain default for any spec running after this one
end
