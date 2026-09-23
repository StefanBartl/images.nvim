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

  -- ── 4. The link lands via the window current when the paste started, not
  --      whatever window is current when the (async) capture callback fires
  --      (ERR-33) ────────────────────────────────────────────────────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local doc_win = vim.api.nvim_get_current_win()

    -- A second window on an unrelated buffer -- simulates ui.kit's alt-text
    -- input float becoming the current window before the capture callback
    -- runs, the way it does with `paste.ask_alt_text = true`.
    vim.cmd("botright split")
    local other_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(other_buf)
    local other_win = vim.api.nvim_get_current_win()
    H.ok(other_win ~= doc_win, "a second window exists to switch to")

    -- The fake capture switches away from the document window before
    -- invoking its callback -- what an async process callback (or an input
    -- float) does in practice.
    local function fake_capture_switching_window(out, cb)
      local fd = assert(io.open(out, "wb"))
      fd:write("x")
      fd:close()
      vim.api.nvim_set_current_win(other_win)
      cb(true)
    end

    vim.api.nvim_set_current_win(doc_win)
    paste.paste_with_name(buf, "shot.png", fake_capture_switching_window)

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.ok(
      lines[3] and lines[3]:find("assets/shot.png", 1, true) ~= nil,
      "the link lands on the line the cursor was on when the paste started: " .. vim.inspect(lines)
    )
    H.falsy(lines[1] and lines[1]:find("assets/shot.png", 1, true), "…not on the first line via the now-current other window")

    pcall(vim.api.nvim_win_close, other_win, true)
    pcall(vim.api.nvim_buf_delete, other_buf, { force = true })
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 5. resolve_link_path: the path-mode transform, in isolation ──────────
  -- (`:Images paste path=relative|absolute|repos|<prefix>`, Phase 3 point 8 --
  -- mirrors buffer-ctx.nvim's ops/filepath.lua mode="repos", see that
  -- module's own TESTS/ops_edge_spec.lua for the reference shape.)
  do
    local resolve_link_path = paste.resolve_link_path
    local abs = "/repos/images.nvim/docs/assets/shot.png"
    local doc_rel = "assets/shot.png"

    H.eq(resolve_link_path(abs, doc_rel, nil), doc_rel, "nil path_mode defaults to relative (doc-relative)")
    H.eq(resolve_link_path(abs, doc_rel, ""), doc_rel, "an empty path_mode also defaults to relative")
    H.eq(resolve_link_path(abs, doc_rel, "relative"), doc_rel, "mode=relative is the doc-relative path unchanged")
    H.eq(resolve_link_path(abs, doc_rel, "absolute"), abs, "mode=absolute is the full filesystem path")

    -- mode=repos: inside $REPOS_DIR strips the prefix; outside it falls back
    -- to the doc-relative path; unset errors -- same three cases buffer-ctx's
    -- mode="repos" covers, adapted to images.nvim's "transform only the link
    -- text, never the file location" contract.
    local saved_repos_dir = vim.env.REPOS_DIR

    vim.env.REPOS_DIR = "/repos"
    H.eq(
      resolve_link_path(abs, doc_rel, "repos"),
      "images.nvim/docs/assets/shot.png",
      "mode=repos inside $REPOS_DIR strips the repos-root prefix"
    )

    vim.env.REPOS_DIR = "/elsewhere"
    H.eq(resolve_link_path(abs, doc_rel, "repos"), doc_rel, "mode=repos outside $REPOS_DIR falls back to the doc-relative path")

    vim.env.REPOS_DIR = nil
    local link, repos_err = resolve_link_path(abs, doc_rel, "repos")
    H.eq(link, nil, "mode=repos with $REPOS_DIR unset returns no link path")
    H.contains(repos_err or "", "REPOS_DIR", "…and names the missing variable in the error")

    vim.env.REPOS_DIR = saved_repos_dir

    -- Anything else is a literal custom prefix, joined onto the doc-relative
    -- path -- a trailing slash on the prefix does not double up.
    H.eq(
      resolve_link_path(abs, doc_rel, "/static/img"),
      "/static/img/assets/shot.png",
      "an unrecognised mode is used as a literal custom prefix"
    )
    H.eq(
      resolve_link_path(abs, doc_rel, "/static/img/"),
      "/static/img/assets/shot.png",
      "…a trailing slash on the custom prefix is not doubled"
    )
  end

  -- ── 6. path_mode end-to-end via paste_with_name: only the LINK changes,
  --      the file always lands in the same place (paste.dir/existing
  --      resource folder) regardless of path_mode ─────────────────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true), "absolute")

    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "path_mode=absolute: file still lands in assets/")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local forward_root = (root:gsub("\\", "/"))
    H.ok(
      lines[1]:find(forward_root .. "/assets/shot.png", 1, true) ~= nil,
      "path_mode=absolute: the LINK is the full filesystem path: " .. lines[1]
    )
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local buf = make_buf(root)

    paste.paste_with_name(buf, "shot.png", fake_capture(true), "/cdn/assets")

    H.eq(vim.fn.filereadable(root .. "/assets/shot.png"), 1, "custom path_mode: file still lands in assets/")
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.ok(
      lines[1]:find("/cdn/assets/assets/shot.png", 1, true) ~= nil,
      "custom path_mode: the LINK is prefix + doc-relative path: " .. lines[1]
    )
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- ── 7. resolve_path_mode: explicit arg / configured default / interactive
  --      ask, without any real UI kit (unavailable in this test process, see
  --      TESTS/run.lua's own note on that) ─────────────────────────────────
  do
    local resolve_path_mode = paste.resolve_path_mode
    local config = require("images.config")

    -- An explicit mode wins outright, regardless of config.
    config.setup({ paste = { default_path_mode = "relative" } })
    local got
    resolve_path_mode("absolute", function(mode)
      got = mode
    end)
    H.eq(got, "absolute", "resolve_path_mode: an explicit path= argument wins outright")

    -- A configured default resolves silently -- vim.ui.select must NOT be
    -- called at all when one is set.
    local original_select = vim.ui.select
    vim.ui.select = function()
      error("vim.ui.select must not be called when paste.default_path_mode is set")
    end
    config.setup({ paste = { default_path_mode = "repos" } })
    got = nil
    resolve_path_mode(nil, function(mode)
      got = mode
    end)
    H.eq(got, "repos", "resolve_path_mode: a configured default is used without asking")
    vim.ui.select = original_select

    -- default_path_mode = false: no explicit arg, no default -> the
    -- interactive choice fires (ui.kit unavailable here, so vim.ui.select).
    config.setup({ paste = { default_path_mode = false } })

    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.value == "absolute" then
          on_choice(item)
          return
        end
      end
      on_choice(nil)
    end
    got = nil
    resolve_path_mode(nil, function(mode)
      got = mode
    end)
    H.eq(got, "absolute", "resolve_path_mode: default_path_mode=false asks via vim.ui.select, picking a built-in choice")

    -- Choosing "custom" asks a second time, for the literal prefix
    -- (vim.fn.input, since ui.kit is unavailable here too).
    vim.ui.select = function(items, _opts, on_choice)
      for _, item in ipairs(items) do
        if item.value == "custom" then
          on_choice(item)
          return
        end
      end
    end
    local original_input = vim.fn.input
    vim.fn.input = function()
      return "/cdn/assets"
    end
    got = nil
    resolve_path_mode(nil, function(mode)
      got = mode
    end)
    H.eq(got, "/cdn/assets", "resolve_path_mode: choosing 'custom' asks for the literal prefix next")

    -- Cancelling the select (nil choice) resolves to nil -- the caller (M.run)
    -- treats that as "cancelled", not as "relative".
    vim.ui.select = function(_items, _opts, on_choice)
      on_choice(nil)
    end
    got = "unset"
    resolve_path_mode(nil, function(mode)
      got = mode
    end)
    H.eq(got, nil, "resolve_path_mode: cancelling the select resolves to nil, not a default")

    vim.ui.select = original_select
    vim.fn.input = original_input
    config.setup({}) -- restore the plain default for any spec running after this one
  end
end
