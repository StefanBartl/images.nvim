---@module 'images.convert'
---@brief Formatkonvertierung über ImageMagick: SVG→PNG, Bild→PDF, Bild→geschwärzte Kopie.
---@description
--- Drei unabhängige Konvertierungen, ein Modul, weil alle drei dieselbe
--- `magick`-Abhängigkeit und dieselbe Fehlerbehandlung teilen:
---
--- `M.to_png` — WezTerm dekodiert PNG/JPEG/GIF/WebP selbst, aber kein SVG.
--- Hier ist eine Konvertierung wirklich nötig, nicht nur eine Verbesserung —
--- bewusst der einzige *Anzeige*-Fall, in dem `magick` Voraussetzung statt
--- Zugabe ist (siehe die Leitplanke in docs/ROADMAP/README.md). Ergebnisse
--- landen gecacht in `stdpath("cache")/images.nvim/svg`, benannt nach
--- Quellpfad + Änderungszeit — ein geändertes SVG bekommt automatisch eine
--- neue PNG-Datei statt eine veraltete zu zeigen.
---
--- `M.to_pdf` — die Gegenrichtung von `pdfport.nvim`s "PDF-Seite als Bild"
--- (siehe docs/ROADMAP/CROSS-PLUGIN.md): ein vorhandenes Bild als PDF neben
--- der Quelldatei ablegen, z.B. um einen Screenshot an ein Ticket
--- anzuhängen, das eine PDF erwartet. Kein Cache — anders als SVG-Anzeige
--- ist das ein einmaliger, expliziter Export, kein wiederholter Zeichenpfad.
---
--- Ist `pdfport.nvim` installiert und meldet `can_create("image")` einen
--- verfügbaren Producer, läuft der Export darüber (asynchron, verlustfrei
--- über `img2pdf`, sonst `magick` — welcher Producer greift, entscheidet
--- pdfports eigene `create_chain`, nicht dieses Plugin). Ohne pdfport bleibt
--- der bisherige synchrone `magick`-Pfad unverändert die einzige Option.
--- Soft-Dependency über `pcall`, wie überall in diesem Repo (siehe
--- CROSS-PLUGIN.md).
---
--- `M.redact` — Rechtecke (Pixelkoordinaten, siehe `images.scale`) schwarz
--- übermalen und als neue Datei ablegen, siehe docs/ROADMAP/REDACT.md für
--- das volle Konzept (Motivation: casedesk-Anhänge mit Kundendaten, die vor
--- einer künftigen KI-Übergabe unkenntlich gemacht werden müssen). Kein
--- Cache, wie `M.to_pdf` — ein einmaliger Export, kein Zeichenpfad.

local M = {}

---@param path string
---@return boolean
function M.is_svg(path)
  return (path:match("%.([%w]+)$") or ""):lower() == "svg"
end

---@return string
local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/images.nvim/svg"
  require("lib.nvim.fs.mkdirp")(dir)
  return dir
end

--- SVG nach PNG konvertieren, mit Cache über Quellpfad + Änderungszeit.
---@param path string absoluter Pfad zu einer .svg-Datei
---@return string|nil png_path
---@return string|nil err
function M.to_png(path)
  if not require("lib.nvim.cross.executable").exists("magick") then
    return nil, "SVG braucht ImageMagick (`magick` nicht gefunden)"
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "Datei nicht gefunden: " .. path end

  -- sha256 aus Pfad+mtime als Dateiname: kollisionsfrei genug für einen
  -- Cache, und ein geändertes SVG bekommt automatisch einen neuen Schlüssel.
  local key = vim.fn.sha256(path .. ":" .. tostring(stat.mtime and stat.mtime.sec or 0))
  local out = cache_dir() .. "/" .. key .. ".png"

  if vim.uv.fs_stat(out) then return out end

  -- -background none: transparenter Hintergrund statt eines erratenen
  -- Weiß/Schwarz, das auf einem farbigen Terminalhintergrund falsch aussähe.
  local result = vim.system({ "magick", path, "-background", "none", out }, { text = true }):wait()
  if result.code ~= 0 then
    pcall(vim.uv.fs_unlink, out)
    return nil, "Konvertierung fehlgeschlagen: " .. vim.trim(result.stderr or "")
  end
  if not vim.uv.fs_stat(out) then return nil, "Konvertierung lieferte keine Datei" end
  return out
end

--- Bild als PDF exportieren, neben der Quelldatei mit derselben Basis
--- ("bild.png" → "bild.pdf"). Existiert die Zieldatei bereits, wird sie
--- überschrieben — dieselbe Haltung wie `:Image paste`/`replace`, die
--- Zieldateien ebenfalls ohne Rückfrage schreiben; images.nvim fragt bei
--- Dateioperationen grundsätzlich nicht nach, sondern meldet das Ergebnis.
---
--- `on_done` ist der einzige Weg, das Ergebnis zu erfahren: beide Pfade —
--- pdfport wie magick — rufen es asynchron auf, sobald die Konvertierung
--- fertig ist. Die Rückgabewerte sind entsprechend immer nil und nur noch
--- für die Fälle gesetzt, die schon vor dem Start scheitern (kein magick,
--- Datei nicht gefunden).
---@param path string absoluter Pfad zu einer Bilddatei
---@param on_done fun(ok: boolean, out_path_or_err: string)|nil
---@return string|nil pdf_path  nur im synchronen (magick) Erfolgsfall gesetzt
---@return string|nil err       nur im synchronen (magick) Fehlerfall gesetzt
function M.to_pdf(path, on_done)
  local ok_pp, pdfport = pcall(require, "pdfport")
  if ok_pp and type(pdfport.can_create) == "function" and pdfport.can_create("image") then
    pdfport.create({
      inputs = { path },
      from = "image",
      __callback = function(result)
        if not on_done then return end
        if result.status == "ok" then
          on_done(true, result.path)
        else
          on_done(false, result.error or "Export fehlgeschlagen (pdfport)")
        end
      end,
    })
    return nil, nil
  end

  if not require("lib.nvim.cross.executable").exists("magick") then
    local err = "PDF-Export braucht ImageMagick (`magick` nicht gefunden)"
    if on_done then on_done(false, err) end
    return nil, err
  end

  local stat = vim.uv.fs_stat(path)
  if not stat then
    local err = "Datei nicht gefunden: " .. path
    if on_done then on_done(false, err) end
    return nil, err
  end

  local out = vim.fn.fnamemodify(path, ":r") .. ".pdf"

  -- `magick` lief hier bis eben über `vim.system(...):wait()` und blockierte
  -- damit den UI-Thread für die gesamte Konvertierung — bei einem großen Bild
  -- sind das Sekunden. Jetzt asynchron, genau wie der pdfport-Zweig darüber:
  -- damit ist `on_done` in *beiden* Pfaden der Weg zum Ergebnis, so wie die
  -- Doku dieser Funktion es ohnehin schon beschreibt.
  vim.system({ "magick", path, out }, { text = true }, function(result)
    -- vim.system-Callbacks laufen außerhalb der Main-Loop; `on_done` landet
    -- bei jedem Aufrufer in notify und vim.fn.
    vim.schedule(function()
      if not on_done then return end
      if result.code ~= 0 then
        on_done(false, "Export fehlgeschlagen: " .. vim.trim(result.stderr or ""))
        return
      end
      if not vim.uv.fs_stat(out) then
        on_done(false, "Export lieferte keine Datei")
        return
      end
      on_done(true, out)
    end)
  end)

  return nil, nil
end

--- Rechtecke schwarz übermalen und als neue Datei neben der Quelldatei
--- ablegen ("bild.png" → "bild.redacted.png"), das Original bleibt
--- unverändert. Existiert die Zieldatei bereits, wird sie überschrieben —
--- dieselbe Haltung wie `M.to_pdf`.
---@param path string absoluter Pfad zu einer Bilddatei
---@param boxes { x1: integer, y1: integer, x2: integer, y2: integer }[] Pixelrechtecke, siehe `images.scale.cell_box_to_pixels`
---@return string|nil out_path
---@return string|nil err
function M.redact(path, boxes)
  if not require("lib.nvim.cross.executable").exists("magick") then
    return nil, "Schwärzen braucht ImageMagick (`magick` nicht gefunden)"
  end
  if not boxes or #boxes == 0 then return nil, "Keine Box zum Schwärzen angegeben" end

  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "Datei nicht gefunden: " .. path end

  local ext = vim.fn.fnamemodify(path, ":e")
  local out = vim.fn.fnamemodify(path, ":r") .. ".redacted." .. (ext ~= "" and ext or "png")

  local args = { "magick", path, "-fill", "black" }
  for _, box in ipairs(boxes) do
    table.insert(args, "-draw")
    table.insert(args, ("rectangle %d,%d %d,%d"):format(box.x1, box.y1, box.x2, box.y2))
  end
  table.insert(args, out)

  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 then return nil, "Schwärzen fehlgeschlagen: " .. vim.trim(result.stderr or "") end
  if not vim.uv.fs_stat(out) then return nil, "Schwärzen lieferte keine Datei" end
  return out
end

return M
