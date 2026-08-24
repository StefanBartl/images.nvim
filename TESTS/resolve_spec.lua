-- TESTS/resolve_spec.lua — link detection and extension checking.
--
-- Chiefly the pure parts: `links_in_line` and `is_image` need neither a
-- filesystem nor a buffer. `to_path`'s local resolution is deliberately not
-- covered here (it needs a real filesystem); `under_cursor`'s remote branch at
-- the end is, because that is precisely what changed with `images.remote`.

---@param H table harness from TESTS/run.lua
return function(H)
  require("images.config").setup(nil) -- defaults, for `extensions`
  local resolve = require("images.resolve")

  -- ── is_image ───────────────────────────────────────────────────────────────
  H.ok(resolve.is_image("image.png"), "png is an image")
  H.ok(resolve.is_image("IMAGE.PNG"), "the extension is checked case-insensitively")
  H.ok(resolve.is_image("a/b/c.jpeg"), "a path does not disturb the extension check")
  H.falsy(resolve.is_image("note.md"), "md is not an image")
  H.falsy(resolve.is_image("no-extension"), "without an extension, not an image")
  H.falsy(resolve.is_image("archive.png.gz"), "only the last extension counts")

  -- ── links_in_line ──────────────────────────────────────────────────────────
  local links = resolve.links_in_line("no link here")
  H.eq(#links, 0, "a line without a link yields nothing")

  links = resolve.links_in_line("![alt](image.png)")
  H.eq(#links, 1, "an image link is recognised")
  H.eq(links[1].target, "image.png", "the target is extracted")
  H.eq(links[1].from, 1, "the range starts at the `!`")
  H.eq(links[1].to, 17, "the range ends at the closing parenthesis")

  links = resolve.links_in_line("text [doc](a.md) more ![i](b.png) end")
  H.eq(#links, 2, "several links on one line")
  H.eq(links[1].target, "a.md", "first target")
  H.eq(links[2].target, "b.png", "second target")
  H.ok(links[2].from > links[1].to, "the ranges do not overlap")

  -- The range has to span the whole link, not only the parenthesised part --
  -- otherwise the hover only fires with the cursor to the right of the `]`.
  links = resolve.links_in_line("![description](x.png)")
  local inside_alt = 5 -- somewhere inside the alt text
  H.ok(inside_alt >= links[1].from and inside_alt <= links[1].to, "the alt text counts as part of the link")

  -- Paths with spaces and subdirectories.
  links = resolve.links_in_line("![](assets/my image.png)")
  H.eq(links[1].target, "assets/my image.png", "spaces in the target survive")

  -- Nested brackets in the alt text must not break detection.
  links = resolve.links_in_line("![a [b] c](d.png)")
  H.eq(#links, 1, "brackets in the alt text do not break detection")
  H.eq(links[1].target, "d.png", "…and the target is still correct")

  -- ── under_cursor: a remote link yields the URL itself, without any network ─
  -- The only part of under_cursor covered here (see the header comment) --
  -- because it is the one place whose behaviour changed for images.remote: a
  -- remote target is passed through rather than discarded as "not found" like
  -- any other unresolvable path.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![remote](https://example.com/photo.jpg)" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  local target, err = resolve.under_cursor()
  H.ok(target ~= nil, "a remote link is recognised as a target: " .. tostring(err))
  H.eq(target and target.path, "https://example.com/photo.jpg", "path is the URL itself, not nil")
  pcall(vim.api.nvim_buf_delete, buf, { force = true })

  -- ── HTML targets via markdown.nvim ───────────────────────────────────────
  -- Only when markdown.nvim is reachable: `links_in_line` delegates to it,
  -- because its scanner also understands `<img src="…">` — the pattern that
  -- gives a caption in Markdown (`<figure>`/`<figcaption>`). Without
  -- markdown.nvim the built-in Markdown pattern stands and there is nothing to
  -- check here.
  if pcall(require, "markdown.core.link_scan") then
    local html = resolve.links_in_line('<img src="assets/start.png" alt="Start Screen">', 1)
    H.eq(#html, 1, "an HTML image is recognised via markdown.nvim")
    H.eq(html[1].target, "assets/start.png", "src is reported as the target")
    H.ok(html[1].from >= 1 and html[1].to >= html[1].from, "the range is 1-based and valid")

    local fig = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(fig, 0, -1, false, {
      "<figure>",
      '  <img src="https://example.com/photo.jpg" alt="Photo">',
      "  <figcaption>Figure 1: Photo</figcaption>",
      "</figure>",
    })
    vim.api.nvim_set_current_buf(fig)
    -- Cursor on the caption line: no target on the line itself, the image comes
    -- from the enclosing `<figure>` block.
    vim.api.nvim_win_set_cursor(0, { 3, 4 })
    local cap = resolve.under_cursor()
    H.ok(cap ~= nil, "the caption line resolves the block's image")
    H.eq(cap and cap.path, "https://example.com/photo.jpg", "…and the same one as the `<img>`")
    pcall(vim.api.nvim_buf_delete, fig, { force = true })
  end
end
