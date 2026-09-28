-- TESTS/win_clipboard_worker_spec.lua — images.win_clipboard_worker's request
-- protocol and lifecycle, the seam the real `:Image paste` on Windows now
-- goes through instead of spawning a fresh `powershell.exe` every time (see
-- that module's own header for why).
--
-- `vim.system` is stubbed, per this suite's own convention (see
-- TESTS/README.md, "Real external processes") — a real PowerShell process
-- would need Windows to run at all, and the point here is the plumbing
-- (queueing, response parsing, timeout/respawn), which has no OS in it.
-- The fake spawned "process" is a plain table recording every stdin write
-- and exposing the `stdout` callback the module gave it, so a spec can
-- answer a request exactly the way a real PowerShell response would arrive.
--
-- `fake.restore()` always runs before the first assertion that could fail,
-- never after (screenshot_spec.lua's own convention, for the same reason):
-- an assertion failure throws, and this file has no spec-local pcall around
-- it, so anything placed after the last assertion would never run on a
-- failing case -- leaving `vim.system` stubbed for every spec that runs
-- after this one in the same process, exactly the kind of cross-spec
-- pollution `blocks_spec.lua`/`convert_spec.lua`/`ocr_spec.lua` (all real
-- `vim.system` users) would then fail with, for a reason that has nothing to
-- do with them.

---@param H table harness from TESTS/run.lua
return function(H)
  local worker = require("images.win_clipboard_worker")

  ---@return table fake { spawn_count, current, restore }
  local function install_fake_powershell()
    local spawn_count = 0
    local current = nil
    local original_system = vim.system

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
      H.eq(cmd[1], "powershell.exe", "spawns the PowerShell helper")
      spawn_count = spawn_count + 1
      local proc = { writes = {}, killed = nil, closed = false, stdout_cb = opts.stdout, on_exit = on_exit }
      function proc:write(data)
        if data == nil then
          self.closed = true
        else
          table.insert(self.writes, data)
        end
      end
      function proc:kill(sig)
        self.killed = sig
      end
      current = proc
      return proc
    end

    return {
      spawn_count = function()
        return spawn_count
      end,
      current = function()
        return current
      end,
      restore = function()
        vim.system = original_system
      end,
    }
  end

  local original_opts = vim.deepcopy(require("images.config").user_opts())

  -- ── A "no image" response resolves with the documented message, and the
  --    worker is reused (no second spawn) for the request after it ─────────
  do
    worker._reset()
    local fake = install_fake_powershell()

    local out1 = vim.fn.tempname() .. ".png"
    local done1, ok1, err1
    worker.save_to_file(out1, function(ok, err)
      done1, ok1, err1 = true, ok, err
    end)
    local spawn_count_1 = fake.spawn_count()
    local writes_1 = #fake.current().writes

    fake.current().stdout_cb(nil, "IMAGESNVIM:3:\n")
    vim.wait(200, function()
      return done1
    end, 5)

    local out2 = vim.fn.tempname() .. ".png"
    local done2, ok2
    worker.save_to_file(out2, function(ok)
      done2, ok2 = true, ok
    end)
    local spawn_count_2 = fake.spawn_count()

    -- The real PowerShell writes the PNG bytes itself ($img.Save(...))
    -- before reporting success; the fake stands in for that here.
    H.write(out2, "fake png bytes")
    fake.current().stdout_cb(nil, "IMAGESNVIM:0:\n")
    vim.wait(200, function()
      return done2
    end, 5)

    fake.restore()

    H.eq(spawn_count_1, 1, "the first request spawns exactly one process")
    H.eq(writes_1, 1, "…and sends exactly one line for it")
    H.ok(done1, "the request resolves")
    H.falsy(ok1, "code 3 -> failure")
    H.eq(err1, "no image in the clipboard", "…with the documented message")
    H.eq(spawn_count_2, 1, "a second request reuses the worker -- no second spawn")
    H.ok(ok2, "code 0 plus a non-empty file -> success")
  end

  -- ── Two requests issued back to back: the second is not sent until the
  --    first has answered (queued, not raced over the shared stdin) ───────
  do
    worker._reset()
    local fake = install_fake_powershell()

    local done1, done2
    worker.save_to_file(vim.fn.tempname() .. ".png", function()
      done1 = true
    end)
    local out2 = vim.fn.tempname() .. ".png"
    worker.save_to_file(out2, function()
      done2 = true
    end)
    local writes_before_first_answer = #fake.current().writes

    fake.current().stdout_cb(nil, "IMAGESNVIM:3:\n")
    vim.wait(200, function()
      return done1
    end, 5)
    local writes_after_first_answer = #fake.current().writes

    H.write(out2, "fake png bytes")
    fake.current().stdout_cb(nil, "IMAGESNVIM:0:\n")
    vim.wait(200, function()
      return done2
    end, 5)

    fake.restore()

    H.eq(writes_before_first_answer, 1, "the second request's line is not sent while the first is still in flight")
    H.ok(done1, "the first request resolves")
    H.eq(writes_after_first_answer, 2, "…only then is the second request's line sent")
    H.ok(done2, "the second request resolves too")
  end

  -- ── A request that never answers times out instead of wedging every
  --    paste after it for the rest of the session ─────────────────────────
  do
    worker._reset()
    require("images.config").setup({ paste = { windows_clipboard_timeout_ms = 20 } })
    local fake = install_fake_powershell()

    local done, ok, err
    worker.save_to_file(vim.fn.tempname() .. ".png", function(o, e)
      done, ok, err = true, o, e
    end)

    -- Comfortably above the 20ms timeout configured above.
    vim.wait(1000, function()
      return done
    end, 10)
    local killed = fake.current().killed

    -- The next request must not stay bound to the now-dead process: a fresh
    -- one is spawned.
    worker.save_to_file(vim.fn.tempname() .. ".png", function() end)
    local spawn_count_after_timeout = fake.spawn_count()

    fake.restore()
    require("images.config").setup(original_opts)

    H.ok(done, "the timeout fires instead of hanging forever")
    H.falsy(ok, "…reporting failure")
    H.contains(err or "", "timed out", "…specifically the timeout")
    H.eq(killed, "sigkill", "…and the hung process is killed")
    H.eq(spawn_count_after_timeout, 2, "the request after a timeout starts a fresh process")
  end

  -- ── shutdown(): closes stdin on a live worker, and is a harmless no-op
  --    when none was ever started ──────────────────────────────────────────
  do
    worker._reset()
    local shutdown_noop_ok = pcall(worker.shutdown)

    local fake = install_fake_powershell()
    worker.save_to_file(vim.fn.tempname() .. ".png", function() end)
    worker.shutdown()
    local closed = fake.current().closed

    fake.restore()

    H.ok(shutdown_noop_ok, "shutdown() without a worker does not throw")
    H.ok(closed, "shutdown() closes the live worker's stdin")
  end

  worker._reset()
end
