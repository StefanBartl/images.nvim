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

  -- ── shutdown(): closes stdin on a live worker, is a harmless no-op when
  --    none was ever started, and still answers a request that was in
  --    flight (or queued) at the moment Neovim quits -- the caller (e.g.
  --    images.paste's clipboard_to_file) is waiting on that callback to
  --    clean up a temp file/show a warning, and shutdown() used to drop the
  --    worker reference first, leaving it unanswered ─────────────────────
  do
    worker._reset()
    local shutdown_noop_ok = pcall(worker.shutdown)

    local fake = install_fake_powershell()
    local in_flight_done, in_flight_ok, in_flight_err
    worker.save_to_file(vim.fn.tempname() .. ".png", function(ok, err)
      in_flight_done, in_flight_ok, in_flight_err = true, ok, err
    end)
    worker.shutdown()
    local closed = fake.current().closed

    fake.restore()

    H.ok(shutdown_noop_ok, "shutdown() without a worker does not throw")
    H.ok(closed, "shutdown() closes the live worker's stdin")
    H.ok(in_flight_done, "shutdown() still answers a request that was in flight")
    H.falsy(in_flight_ok, "…as a failure, not left hanging forever")
    H.contains(in_flight_err or "", "shutting down", "…with a message naming why")
  end

  -- ── fail_all: a callback that throws must not stop the rest of the
  --    requests it is holding from being notified, or stop `shutdown()`
  --    from reaching its own stdin close right after -- a caller's callback
  --    is arbitrary code this module does not control (an ultracode review
  --    flagged the un-pcall'd call as a real, if narrow, exposure) ─────────
  do
    worker._reset()
    local fake = install_fake_powershell()

    worker.save_to_file(vim.fn.tempname() .. ".png", function()
      error("boom -- a caller's callback throwing")
    end)
    local queued_done, queued_ok
    worker.save_to_file(vim.fn.tempname() .. ".png", function(ok)
      queued_done, queued_ok = true, ok
    end)

    local shutdown_ok = pcall(worker.shutdown)
    local closed = fake.current().closed

    fake.restore()

    H.ok(shutdown_ok, "shutdown() itself does not throw even though the in-flight callback does")
    H.ok(closed, "…and still closes stdin afterwards")
    H.ok(queued_done, "the queued request behind the throwing one is still notified")
    H.falsy(queued_ok, "…as a failure, same as every other request failed by this shutdown")
  end

  -- ── handle_response: the same throw-safety matters here even more than in
  --    fail_all -- this is the ORDINARY response path, taken on every
  --    normal paste, not just on timeout/crash/shutdown. A throwing
  --    callback must not stop `send_next(w)` from running, or whatever is
  --    queued behind the answered request would never be sent at all ──────
  do
    worker._reset()
    local fake = install_fake_powershell()

    local first_ok = pcall(worker.save_to_file, vim.fn.tempname() .. ".png", function()
      error("boom -- a caller's callback throwing on an ordinary response")
    end)
    local second_done, second_ok
    worker.save_to_file(vim.fn.tempname() .. ".png", function(ok)
      second_done, second_ok = true, ok
    end)

    local writes_before = #fake.current().writes
    -- Answering the first request runs handle_response -> the throwing
    -- callback -> (must still reach) send_next(w) for the second one.
    -- handle_response itself runs inside vim.schedule (on_stdout defers it,
    -- same as every response), so it hasn't happened yet just because
    -- stdout_cb returned -- wait for it the same way the file's other
    -- cases do.
    local respond_ok = pcall(fake.current().stdout_cb, nil, "IMAGESNVIM:0:\n")
    vim.wait(200, function()
      return #fake.current().writes >= 2
    end, 5)
    local writes_after = #fake.current().writes

    fake.current().stdout_cb(nil, "IMAGESNVIM:3:\n")
    vim.wait(200, function()
      return second_done
    end, 5)

    fake.restore()

    H.ok(first_ok, "queueing the throwing-callback request does not itself throw")
    H.ok(respond_ok, "answering it does not propagate the callback's throw out of on_stdout")
    H.eq(writes_before, 1, "sanity: only the first request's line had been sent so far")
    H.eq(writes_after, 2, "handle_response still reaches send_next -- the second request's line goes out")
    H.ok(second_done, "…and it resolves normally")
    H.falsy(second_ok, "…this run's answer for it (code 3), unaffected by the first one's throw")
  end

  worker._reset()
end
