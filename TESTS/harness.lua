-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert a falsy value.
---@param v any
---@param msg string|nil
function H.falsy(v, msg)
  if v then error(("FAIL %s: expected falsy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert `haystack` contains `needle` as a literal substring.
---@param haystack string
---@param needle string
---@param msg string|nil
function H.contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(("FAIL %s: %q does not contain %q"):format(msg or "", tostring(haystack), needle), 2)
  end
end

--- Fresh scratch buffer, made current, with optional lines and filetype.
---@param lines string[]|nil
---@param ft string|nil
---@return integer bufnr
function H.scratch(lines, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  if lines then vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
  if ft then vim.bo[buf].filetype = ft end
  return buf
end

--- Create a temporary directory, run `fn(dir)`, then remove it.
---@generic T
---@param fn fun(dir: string): T
---@return T
function H.tmpdir(fn)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local ok, ret = pcall(fn, vim.fs.normalize(dir))
  vim.fn.delete(dir, "rf")
  if not ok then error(ret, 0) end
  return ret
end

--- Write `content` to `path`, creating parent directories.
---@param path string
---@param content string
function H.write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "wb"))
  f:write(content)
  f:close()
end

return H
