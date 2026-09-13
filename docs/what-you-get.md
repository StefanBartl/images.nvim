# What you get with the defaults

```
:Image                     show the image under the cursor
:'<,'>Image                gallery of just the selected lines
:Image gallery             every image in the buffer, side by side
:Image paste               clipboard screenshot → file next to the document + link
:Image screenshot          take a screenshot interactively, skipping the clipboard step
:Image next / prev         walk through the images of the buffer
:Image orphans             images in paste.dir that nothing links to anymore
:Image calibrate           measure this terminal's image placement, once, interactively
:Image pickers cwd         browse every image under cwd, live preview with snacks.picker
:Image zen                 the image under the cursor, full-screen, in a real window
:Image compare cwd         pick two images, view side by side at their true relative size
:Image ocr                 read the text out of the image under the cursor, into a buffer
:Image redact              black out boxes before sharing a screenshot
:Image scale 800x          resized copy next to the source, aspect preserved
:Image optimise            smaller copy: metadata stripped, best compression
:Image convert png         copy in another format, same stem
```

In markdown buffers, `<leader>im` shows the image under the cursor,
`<leader>ig` opens the gallery, `<leader>in`/`<leader>ip` walk through them,
`<leader>iv` pastes from the clipboard, `<leader>is` takes a screenshot, and a
double-click on a link shows the image.

Every route with its arguments is in [commands.md](commands.md); every key is
in [BINDINGS.md](BINDINGS.md); how the commands combine day to day is in
[WORKFLOW.md](WORKFLOW.md).
