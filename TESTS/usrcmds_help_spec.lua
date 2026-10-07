-- TESTS/usrcmds_help_spec.lua -- every flag and key=value pair of `:Image` has a line in lib.nvim's
-- option float.
--
-- The text comes from the `desc` of each FlagSpec/KvSpec in images.bindings.usrcmds (`paste path=`,
-- `optimise --quality`, `ocr --lang`). A new option without one shows up as a bare row in the
-- cheatsheet, so this fails until it is described.

---@param H table harness from TESTS/harness.lua
return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then return end

  -- `register` reads nothing but `cfg.command`, so no `setup()` (and no global config) is needed.
  require("images.bindings.usrcmds").register({ command = "Image" })
  H.ok(composer.registry().Image ~= nil, ":Image is registered through the composer")

  local missing = {}
  for _, m in ipairs(composer.help.undocumented("Image")) do
    missing[#missing + 1] = ("%s %s"):format(m.route, m.name)
  end
  H.eq(#missing, 0, ":Image options without a help text: " .. table.concat(missing, ", "))
end
