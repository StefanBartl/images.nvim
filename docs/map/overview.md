# images.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**2 modules** · 1 namespaces · 17 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua_images["images.nvim"]
  nlua_images_bindings["bindings"]
  nlua_images_config["configbr/smallKonfigurations-Einstieg: Defaults mit…/small"]
  nlua_images --> nlua_images_bindings
  nlua_images --> nlua_images_config
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_images_bindings_keymaps_lua["images.bindings.keymaps"]
  nlua_images_bindings_which_key_lua["images.bindings.which_key"]
  nlua_images_bindings_keymaps_lua --> nlua_images_bindings_which_key_lua
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `bindings` |  |  |  |
| `images.config` | Konfigurations-Einstieg: Defaults mit User-Optionen zusammenführen. | 2 | [src](../../lua/images/config/init.lua) |

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
