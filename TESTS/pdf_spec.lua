-- TESTS/pdf_spec.lua — a PDF page as a PNG (images.pdf).
--
-- Same restraint as the rest of the suite: everything up to the process is
-- checked, the process itself is not. pdftoppm is not a build dependency of
-- this plugin and pdfport.nvim is not on the test runtimepath, so what holds
-- headlessly is the part that decides WHETHER to shell out and WHERE the
-- result goes — the extension judgement, the availability answer, and the
-- cache key. The last of those is the one that would go wrong silently: a key
-- that drops an input serves the wrong picture for as long as the cache lives.

---@param H table harness from TESTS/run.lua
return function(H)
  local pdf = require("images.pdf")

  -- ── is_pdf: the extension, and nothing else ──────────────────────────────
  H.ok(pdf.is_pdf("/tmp/report.pdf"), "a .pdf is a PDF")
  H.ok(pdf.is_pdf("C:/docs/Rechnung.PDF"), "the extension check is case-insensitive")
  H.falsy(pdf.is_pdf("/tmp/shot.png"), "a png is not a PDF")
  H.falsy(pdf.is_pdf("/tmp/report.pdf.bak"), "a renamed PDF is not one")
  H.falsy(pdf.is_pdf(nil), "nil is not a PDF")
  H.falsy(pdf.is_pdf(""), "the empty string is not a PDF")

  -- ── available(): a strict boolean, and the opt-out outranks everything ───
  H.eq(type(pdf.available()), "boolean", "available() answers with a boolean")

  local config = require("images.config")
  local restore = config.get()
  config.setup({ pdf = { enabled = false } })
  H.falsy(pdf.available(), "pdf.enabled = false is honoured even where the tools exist")
  config.setup({})
  H.eq(pdf.page(), 1, "the default page is the first")
  H.eq(pdf.dpi(), 120, "the default resolution is 120 dpi")

  config.setup({ pdf = { page = 3, dpi = 300 } })
  H.eq(pdf.page(), 3, "a configured page is used")
  H.eq(pdf.dpi(), 300, "a configured resolution is used")

  config.setup({ pdf = { page = 0, dpi = -1 } })
  H.eq(pdf.page(), 1, "a page below 1 falls back to the first")
  H.eq(pdf.dpi(), 120, "a resolution below 1 falls back to the default")
  config.setup({})

  -- ── cache_key: all four inputs reach it ─────────────────────────────────
  local base = pdf.cache_key("/tmp/a.pdf", 100, 1, 120)
  H.eq(pdf.cache_key("/tmp/a.pdf", 100, 1, 120), base, "the same inputs give the same key")
  H.ok(pdf.cache_key("/tmp/b.pdf", 100, 1, 120) ~= base, "a different file gives a different key")
  H.ok(pdf.cache_key("/tmp/a.pdf", 101, 1, 120) ~= base, "an edited file gives a different key")
  H.ok(pdf.cache_key("/tmp/a.pdf", 100, 2, 120) ~= base, "another page gives a different key")
  H.ok(pdf.cache_key("/tmp/a.pdf", 100, 1, 216) ~= base, "another dpi gives a different key")

  -- ── cache_file: a missing source is a named error, not a crash ──────────
  local out, err = pdf.cache_file("/nonexistent/nowhere.pdf", 1, 120)
  H.falsy(out, "a file that is not there has no cache entry")
  H.contains(err or "", "not found", "the error names the reason")

  H.tmpdir(function(dir)
    local path = dir .. "/doc.pdf"
    H.write(path, "%PDF-1.4\n") -- not a readable PDF; nothing here reads it
    local file = pdf.cache_file(path, 1, 120)
    H.ok(type(file) == "string", "an existing file has a cache path")
    H.contains(file or "", "images.nvim/pdf", "the cache lives under the plugin's own directory")
    H.contains(file or "", ".png", "the cached page is a PNG")
  end)

  -- ── page_png: the callback runs exactly once, with an error, on refusal ──
  local calls = {}
  pdf.page_png("/tmp/notes.md", nil, function(png, e)
    calls[#calls + 1] = { png = png, err = e }
  end)
  H.eq(#calls, 1, "a non-PDF settles the callback once")
  H.falsy(calls[1].png, "and hands back no PNG")
  H.contains(calls[1].err or "", "not a PDF", "the error names the reason")

  config.setup({ pdf = { enabled = false } })
  calls = {}
  pdf.page_png("/tmp/report.pdf", nil, function(png, e)
    calls[#calls + 1] = { png = png, err = e }
  end)
  H.eq(#calls, 1, "an unavailable rasterizer settles the callback once")
  H.contains(calls[1].err or "", "pdfport", "the error names what is missing")

  config.setup(restore)
end
