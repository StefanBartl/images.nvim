---@module 'images.ps_path'
---@brief A file path as a PowerShell expression that cannot break out of its string.
---@description
--- PowerShell treats the typographic quotes U+2018..U+201B like `'`, so
--- doubling only the ASCII quote (`gsub("'", "''")`) still lets a path such as
--- `C:\Users\D’Angelo\Temp` close the string early. Instead the UTF-8 bytes of
--- the path travel as Base64 -- an alphabet with no quote, `;` or `$` in it --
--- and PowerShell turns them back into the string at run time.

local M = {}

--- PowerShell expression evaluating to `path`.
---@param path string
---@return string
function M.expr(path)
  local b64 = require("lib.lua.strings.encoding").base64_encode(path)
  return ("[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('%s'))"):format(b64)
end

return M
