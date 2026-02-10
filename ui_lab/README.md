# UI Lab Example Mod

This mod is a deliberately custom RmlUI override used to validate that mod-owned UI files are loaded correctly.

## Run

```bash
make run MOD_NAME=ui_lab
```

or

```bash
./build/vkquake -game ui_lab
```

## What It Overrides

- `ui/rml/menus/main_menu.rml`
- `ui/rml/menus/pause_menu.rml`
- `ui/rml/hud.rml`
- `ui/rml/hud/hud_classic.rml`
- `ui/rml/hud/hud_modern.rml`
- `ui/rcss/lab_menu.rcss`
- `ui/rcss/lab_hud.rcss`

## Mods Menu Discovery

The Mods menu discovers directories containing at least one of:
`pak0.pak`, `progs.dat`, `csprogs.dat`, `maps/`, or `ui/`.
`ui_lab` is discovered via its `ui/` directory.

## Quick Validation Checklist

1. On startup, you should see the custom **UI LAB** main menu.
2. `ESC` in-game should open the custom pause menu.
3. HUD should use the custom panel style (not the base HUD visuals).
4. In the custom menu, quick-connect and host inputs should accept text and execute actions.
5. `ui_reload` and `ui_reload_css` should update mod files live.
