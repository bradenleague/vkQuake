---
name: qlua
description: Lua scripting for RmlUI documents in vkQuake. Use when editing .lua files in ui/lua/, writing <script> blocks in .rml files, or working with the game/engine Lua API.
---

# Lua Scripting for vkQuake RmlUI

## Design Philosophy

Lua is a **reactive state mapper**, not an imperative UI layer. It bridges
engine events to document state — the document stays declarative.

**Lua should:**
- Read from `game.*` (read-only — writes raise an error)
- Write to data model variables
- Toggle classes on documents (let RCSS handle the visual response)
- Call engine actions via `engine.exec()`

**Lua should NOT:**
- Build or create element trees from code
- Set inline styles for visual state (`element.style["prop"] = "val"`)
- Manage animation timers or frame-by-frame visual updates
- Become the source of truth for anything visual

If markup + RCSS + data binding can express it, prefer that over Lua.

## Gotchas

1. **`document` is nil in `<script>` tags** — only available in inline
   event handlers (`onclick="fn(event, element, document)"`). Access
   documents via `rmlui.contexts["main"].documents["id"]` (requires `id`
   attribute on `<body>`).

2. **`element.style` is a proxy** — set with `element.style["prop"] = "val"`,
   clear with `= nil`. But per the philosophy above, prefer class toggles.

3. **Inline `SetProperty` does NOT trigger RCSS transitions** — use class
   toggles for animation. This is both a technical limitation and a design
   guideline.

4. **No `lua` console command** — use `engine.exec("echo ...")` for
   diagnostics from Lua scripts.

5. **`game.*` table is read-only** — enforced via `__newindex` metamethod.
   50+ fields updated each frame from C++ `GameDataModel`.

## Reference Pattern: Reticle Controller

`ui_lab/ui/lua/reticle_controller.lua` is the canonical example of
the reactive state mapper pattern:

```
engine state (game.weapon_firing) → on_frame callback → SetClass toggle → RCSS responds
```

It never manipulates geometry, sets inline styles, or manages timers.
The base HUD uses no Lua — just `data-class-firing="weapon_firing"`
bindings with a generic `.firing` RCSS rule.

## API Quick Reference

```lua
-- Engine table
engine.exec(cmd)              -- Queue console command
engine.cvar_get(name)         -- Read cvar (returns string)
engine.cvar_get_number(name)  -- Read cvar (returns float)
engine.cvar_set(name, value)  -- Write cvar
engine.time()                 -- Realtime in seconds (float)
engine.on_frame(name, fn)     -- Register named per-frame callback
engine.hud_visible()          -- true when key_dest == key_game (HUD showing)
```

For the full `game.*` field list and detailed API docs:
See [LUA_SCRIPTING.md](../../docs/LUA_SCRIPTING.md)

## Event Ownership

`onclick`/`onchange` attributes go through the Lua `EventListenerInstancer`,
which dispatches action strings (like `navigate`, `close`, `cycle_cvar`)
via registered Lua globals. This is the path for both menu actions and
scripted behavior.

`data-event-*` attributes are only for data model event callbacks inside
`data-for` loops (like `load_slot`, `select_mod`, `capture_key`).

## Testing

```bash
make lua-test    # Runs engine with test harness (~20 frames)
```

Tests live in `ui/lua/tests/`. Requires GPU + display + game assets (local only, not CI).
