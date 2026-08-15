# images.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**2 modules** · 2 namespaces · 25 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["images.nvim"]
  nlua_images["imagesbr/smallBilder im Terminal anzeigen, ohne dass…/small"]
  nlua_images_bindings["bindings"]
  nlua_images_config["configbr/smallKonfigurations-Einstieg: Defaults mit…/small"]
  nlua --> nlua_images
  nlua_images --> nlua_images_bindings
  nlua_images --> nlua_images_config
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_images_anchor_lua["images.anchor"]
  nlua_images_ascii_lua["images.ascii"]
  nlua_images_bindings["bindings"]
  nlua_images_browse_lua["images.browse"]
  nlua_images_compare_lua["images.compare"]
  nlua_images_config["images.config"]
  nlua_images_convert_lua["images.convert"]
  nlua_images_guard_lua["images.guard"]
  nlua_images_health_lua["images.health"]
  nlua_images_hover_float_lua["images.hover_float"]
  nlua_images_info_lua["images.info"]
  nlua_images_orphans_lua["images.orphans"]
  nlua_images_paste_lua["images.paste"]
  nlua_images_redact_lua["images.redact"]
  nlua_images_remote_lua["images.remote"]
  nlua_images_resolve_lua["images.resolve"]
  nlua_images_scale_lua["images.scale"]
  nlua_images_scan_lua["images.scan"]
  nlua_images_screenshot_lua["images.screenshot"]
  nlua_images_terminal_lua["images.terminal"]
  nlua_images_zen_lua["images.zen"]
  nlua_images_anchor_lua --> nlua_images_scale_lua
  nlua_images_anchor_lua --> nlua_images_terminal_lua
  nlua_images_ascii_lua --> nlua_images_info_lua
  nlua_images_ascii_lua --> nlua_images_scale_lua
  nlua_images_bindings --> nlua_images_remote_lua
  nlua_images_bindings --> nlua_images_scale_lua
  nlua_images_bindings --> nlua_images_terminal_lua
  nlua_images_browse_lua --> nlua_images_anchor_lua
  nlua_images_browse_lua --> nlua_images_config
  nlua_images_browse_lua --> nlua_images_guard_lua
  nlua_images_browse_lua --> nlua_images_resolve_lua
  nlua_images_browse_lua --> nlua_images_terminal_lua
  nlua_images_compare_lua --> nlua_images_browse_lua
  nlua_images_compare_lua --> nlua_images_guard_lua
  nlua_images_compare_lua --> nlua_images_info_lua
  nlua_images_compare_lua --> nlua_images_scale_lua
  nlua_images_compare_lua --> nlua_images_terminal_lua
  nlua_images_guard_lua --> nlua_images_terminal_lua
  nlua_images_health_lua --> nlua_images_screenshot_lua
  nlua_images_health_lua --> nlua_images_terminal_lua
  nlua_images_hover_float_lua --> nlua_images_anchor_lua
  nlua_images_hover_float_lua --> nlua_images_config
  nlua_images_hover_float_lua --> nlua_images_terminal_lua
  nlua_images_orphans_lua --> nlua_images_config
  nlua_images_orphans_lua --> nlua_images_resolve_lua
  nlua_images_orphans_lua --> nlua_images_scan_lua
  nlua_images_paste_lua --> nlua_images_config
  nlua_images_paste_lua --> nlua_images_resolve_lua
  nlua_images_paste_lua --> nlua_images_screenshot_lua
  nlua_images_redact_lua --> nlua_images_anchor_lua
  nlua_images_redact_lua --> nlua_images_config
  nlua_images_redact_lua --> nlua_images_convert_lua
  nlua_images_redact_lua --> nlua_images_guard_lua
  nlua_images_redact_lua --> nlua_images_info_lua
  nlua_images_redact_lua --> nlua_images_resolve_lua
  nlua_images_redact_lua --> nlua_images_scale_lua
  nlua_images_redact_lua --> nlua_images_terminal_lua
  nlua_images_redact_lua --> nlua_images_zen_lua
  nlua_images_remote_lua --> nlua_images_config
  nlua_images_resolve_lua --> nlua_images_config
  nlua_images_resolve_lua --> nlua_images_remote_lua
  nlua_images_scan_lua --> nlua_images_resolve_lua
  nlua_images_screenshot_lua --> nlua_images_config
  nlua_images_terminal_lua --> nlua_images_convert_lua
  nlua_images_zen_lua --> nlua_images_anchor_lua
  nlua_images_zen_lua --> nlua_images_config
  nlua_images_zen_lua --> nlua_images_guard_lua
  nlua_images_zen_lua --> nlua_images_resolve_lua
  nlua_images_zen_lua --> nlua_images_terminal_lua
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `images` | Bilder im Terminal anzeigen, ohne dass Neovim das Terminal verlässt. | 28 | [src](../../lua/images/init.lua) |
| &nbsp;&nbsp;`bindings` |  |  |  |
| &nbsp;&nbsp;`images.config` | Konfigurations-Einstieg: Defaults mit User-Optionen zusammenführen. | 2 | [src](../../lua/images/config/init.lua) |

## Drift

0 errors · 0 warnings · 3 info

No errors or warnings.


<details>
<summary>3 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/images has no README.md |
| `missing-readme` | lua/images/config has no README.md |
| `unreferenced-module` | images.health is required by no other file in the tree |

</details>
