-- TESTS/ps_path_spec.lua — a path in a PowerShell script cannot break out of
-- its string. The Windows clipboard code (`images.paste`, `images.win_clipboard_worker`)
-- builds its script through `images.ps_path.expr`.
--
-- The text checks run everywhere; the round trip through a real `powershell.exe`
-- only where one exists.

---@param H table harness from TESTS/run.lua
return function(H)
  local ps_path = require("images.ps_path")

  -- Hostile on purpose: U+2018..U+201B, an ASCII quote, a command separator.
  local hostile = "x\u{2018}a\u{2019}b\u{201A}c\u{201B}d'e; Write-Output X $(Get-Date)"

  local expr = ps_path.expr(hostile)
  H.falsy(expr:find(hostile, 1, true), "the path is not in the script text")
  H.falsy(expr:find("\u{2019}", 1, true), "…no typographic quote survives into it")
  H.falsy(expr:find("; Write-Output", 1, true), "…nor an injected statement")
  H.contains(expr, "FromBase64String('", "…it travels as Base64")

  if vim.fn.executable("powershell.exe") == 0 then return end

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local target = dir .. "/" .. hostile .. ".txt"
  -- The ASCII quote, `;`, `$` and parentheses are legal in Windows file names.
  local script = ("Set-Content -LiteralPath (%s) -Value ok"):format(ps_path.expr(target))
  local result = vim
    .system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script }, { text = true })
    :wait(30000)
  H.eq(result.code, 0, "PowerShell accepts the hostile path: " .. tostring(result.stderr))
  H.eq(result.stdout or "", "", "…and runs no injected statement")
  H.ok(vim.uv.fs_stat(target) ~= nil, "…and the file lands exactly at the requested path")

  -- The shape the clipboard code really uses: the expression as a method
  -- argument, not inside parentheses of a cmdlet call.
  local png = dir .. "/" .. hostile .. ".png"
  local save = table.concat({
    "Add-Type -AssemblyName System.Drawing;",
    "$img = New-Object System.Drawing.Bitmap 2,2;",
    ("$img.Save(%s, [System.Drawing.Imaging.ImageFormat]::Png);"):format(ps_path.expr(png)),
  }, " ")
  local saved = vim
    .system({ "powershell.exe", "-NoProfile", "-NonInteractive", "-STA", "-Command", save }, { text = true })
    :wait(30000)
  H.eq(saved.code, 0, "$img.Save(<expr>, Png) accepts it: " .. tostring(saved.stderr))
  H.ok(vim.uv.fs_stat(png) ~= nil, "…and the PNG lands exactly at the requested path")
  vim.fn.delete(dir, "rf")
end
