# Lua Scripting for RmlUI

Spec for adding Lua scripting support to the RmlUI integration layer,
enabling modders to create interactive UI behaviors without C++ changes.

---

## Motivation

Today, modders can override any RML document or RCSS stylesheet via the
mod directory system (see [MOD_UI_GUIDE.md](MOD_UI_GUIDE.md)). This gives
full control over layout, styling, and data-bound display. But all
**behavior** is locked in C++:

- HUD logic (health tier colors, weapon-reactive styling) = C++ lambdas
- Menu navigation dispatch = C++ `MenuEventHandler`
- Data model definitions = C++ `GameDataModel`, `CvarBinding`
- Custom computed bindings = C++ `BindFunc` closures

Lua scripting unlocks a new tier of modding: **behavioral UI** that's
fully mod-side, hot-reloadable, and requires zero engine recompilation.

---

## Architecture

### Current Stack (no Lua)

```
 RML Documents (mod-overridable)
      │
      │ {{ data bindings }}
      │ onclick="action_string"
      │
      ▼
 C++ Integration Layer (src/)
      │
      ├─ GameDataModel    ─── 50+ bindings from engine state
      ├─ CvarBinding      ─── two-way cvar sync
      ├─ MenuEventHandler ─── action string dispatch
      └─ NotificationModel─── centerprint + notify
      │
      │ extern "C" boundary
      │
      ▼
 Quake Engine (C)
```

### With Lua

```
 RML Documents (mod-overridable)
      │
      │ {{ data bindings }}            <script> tags
      │ onclick="action_string"        onclick="lua_function(event, element, document)"
      │                                │
      │                                ▼
      │                          Lua VM (single state)
      │                                │
      │                                ├─ DOM manipulation (full Element API)
      │                                ├─ Lua-created data models (OpenDataModel)
      │                                ├─ Event listeners (inline + programmatic)
      │                                └─ Engine bridge (game.*, engine.exec)
      │                                │
      ▼                                ▼
 C++ Integration Layer (src/)
      │
      ├─ GameDataModel    ─── still owns "game" model (C++ pushes each frame)
      ├─ CvarBinding      ─── still owns "cvars" model
      ├─ MenuEventHandler ─── still dispatches action strings
      ├─ NotificationModel─── still manages centerprint/notify
      └─ LuaBridge (NEW)  ─── exposes game state + engine.exec to Lua
      │
      │ extern "C" boundary
      │
      ▼
 Quake Engine (C)
```

Key principle: **Lua is additive**. The existing C++ data models, action
dispatch, and binding system continue to work unchanged. Lua adds a
scripting layer on top — modders can use both in the same document.

---

## Build Integration

### Dependencies

| Platform | Package | Notes |
|----------|---------|-------|
| Arch | `lua` or `luajit` | `sudo pacman -S lua` |
| Ubuntu 20.04+ | `liblua5.4-dev` | `sudo apt install liblua5.4-dev` |
| macOS | `lua` | `brew install lua` |
| MSYS2 (mingw64) | `mingw-w64-x86_64-lua` | `pacman -S mingw-w64-x86_64-lua` |
| MSYS2 (clangarm64) | `mingw-w64-clang-aarch64-lua` | |

RmlUI supports Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT. LuaJIT is
recommended for performance and correct C++ exception interop.

### meson_options.txt

```meson
option('use_lua', type: 'boolean', value: true,
       description: 'Enable Lua scripting for RmlUI documents')
```

### meson.build Changes

```
 Existing RmlUI CMake args:
   '-DRMLUI_LUA_BINDINGS=OFF'

 Changed to:
   '-DRMLUI_LUA_BINDINGS=ON'                          (when use_lua enabled)
   '-DRMLUI_LUA_BINDINGS_LIBRARY=lua'                 (or 'luajit')

 New dependency:
   lua_dep = dependency('lua', required: get_option('use_lua'))

 New link target:
   rmlui_lua_lib = meson.get_compiler('cpp').find_library('rmlui_lua',
       dirs: rmlui_build_dir / 'lib')

 New compile define:
   '-DUSE_LUA'                                        (when use_lua enabled)
```

CMake builds `librmlui_lua.a` alongside `librmlui.a` and
`librmlui_debugger.a`. All three are linked into the final executable.

### CI Impact

All CI workflows need the Lua dev package added to their install steps.
The `use_lua` option defaults to `true` but can be disabled for
minimal builds.

---

## C++ Bootstrap (One-Time)

### Initialization (~10 lines in ui_manager.cpp)

```cpp
#ifdef USE_LUA
#include <RmlUi/Lua/Lua.h>
#endif

// In UI_Init(), after Rml::Initialise() and context creation:
#ifdef USE_LUA
    Rml::Lua::Initialise();
    // Registers:
    //   - LuaDocumentElementInstancer (handles <script> tags)
    //   - LuaEventListenerInstancer (handles onclick="lua_code")
    //   - All Lua type bindings (Element, Document, Context, Event, etc.)
    //   - Global `rmlui` table
#endif
```

### Shutdown

```cpp
// In UI_Shutdown(), before Rml::Shutdown():
#ifdef USE_LUA
    Rml::Lua::Shutdown();
#endif
```

### Engine Bridge (game state + console access)

A small C++ shim that pushes engine state into the Lua global namespace
each frame, plus an `engine.exec()` function for console commands:

```cpp
// lua_bridge.h / lua_bridge.cpp  (new file, ~80 lines)

namespace QRmlUI {
namespace LuaBridge {

void Initialize(lua_State* L);  // Register globals
void Update();                  // Push game state each frame

} // namespace LuaBridge
} // namespace QRmlUI
```

This registers:

1. **`game` table** — read-only mirror of GameDataModel bindings
2. **`engine.exec(cmd)`** — queues a console command via `Cbuf_AddText`
3. **`engine.cvar_get(name)`** — reads a cvar value
4. **`engine.cvar_set(name, value)`** — writes a cvar value

See [Engine Bridge API](#engine-bridge-api) for the full reference.

---

## How Scripts Load

### Inline Scripts

```xml
<rml>
<head>
    <script>
    -- This Lua code executes when the document is parsed.
    -- Functions defined here are available to event handlers.
    MyHud = MyHud or {}

    function MyHud.OnHealthChange(event, element, document)
        local hp_el = document:GetElementById('hp')
        if hp_el then
            local val = tonumber(hp_el.inner_rml) or 100
            if val < 25 then
                hp_el:SetClass('critical', true)
            end
        end
    end
    </script>
</head>
```

### External Scripts

```xml
<head>
    <script src="../../lua/my_hud_logic.lua"/>
</head>
```

External scripts load through `QuakeFileInterface`, so they respect
mod directory precedence:

```
 1. <mod_directory>/ui/lua/my_hud_logic.lua   ← highest priority
 2. <basedir>/ui/lua/my_hud_logic.lua         ← fallback
```

### Event Handlers

Inline event attributes compile to Lua closures with three automatic
parameters:

```xml
<button onclick="MyMenu.OnClick(event, element, document)">
```

The handler receives:
- `event` — the Event object (type, target, parameters)
- `element` — the element the handler is attached to
- `document` — the owner document

### Execution Model

- **Single Lua state**: All documents share one `lua_State`. Functions
  defined in one document are visible to all others.
- **Namespace pattern**: Use `MyMod = MyMod or {}` to avoid collisions.
- **No async**: No built-in timers or coroutine scheduling. Use
  frame-driven polling via event handlers or the engine bridge's
  per-frame update.

---

## Lua API Reference

### Global: `rmlui`

| Member | Type | Description |
|--------|------|-------------|
| `rmlui.contexts` | Proxy | Access all contexts by name or index |
| `rmlui.key_identifier` | table | Enum of all `KI_*` key codes |
| `rmlui.key_modifier` | table | `CTRL`, `SHIFT`, `ALT`, `META`, etc. |
| `rmlui:CreateContext(name, dims)` | method | Create a new context |
| `rmlui:LoadFontFace(path, [fallback])` | method | Load a font |
| `rmlui:RegisterTag(tag, instancer)` | method | Register custom element |

### Context

| Method | Returns | Description |
|--------|---------|-------------|
| `LoadDocument(path)` | Document | Load an RML file |
| `CreateDocument([tag])` | Document | Create empty document |
| `UnloadDocument(doc)` | | Unload a document |
| `UnloadAllDocuments()` | | Unload all documents |
| `OpenDataModel(name, table)` | DataModel | Create Lua-backed data model |
| `ProcessKeyDown(ki, mod)` | | Inject key event |
| `ProcessTextInput(text)` | | Inject text input |
| `IsMouseInteracting()` | bool | Check mouse interaction |

| Property | Type | Writable |
|----------|------|----------|
| `name` | string | No |
| `dimensions` | Vector2i | Yes |
| `documents` | Proxy | No |
| `focus_element` | Element | No |
| `hover_element` | Element | No |
| `root_element` | Element | No |
| `dp_ratio` | number | Yes |

### Document (extends Element)

| Method | Returns | Description |
|--------|---------|-------------|
| `Show([modal], [focus])` | | Show document |
| `Hide()` | | Hide document |
| `Close()` | | Close and unload |
| `PullToFront()` | | Bring to front |
| `PushToBack()` | | Send to back |
| `CreateElement(tag)` | ElementPtr | Create a new element |
| `CreateTextNode(text)` | ElementPtr | Create a text node |

| Property | Type | Writable |
|----------|------|----------|
| `title` | string | Yes |
| `context` | Context | No |

### Element

**Properties:**

| Property | Type | Writable |
|----------|------|----------|
| `id` | string | Yes |
| `class_name` | string | Yes |
| `inner_rml` | string | Yes |
| `tag_name` | string | No |
| `style` | StyleProxy | No |
| `attributes` | Proxy | No |
| `child_nodes` | Proxy | No |
| `first_child` | Element/nil | No |
| `last_child` | Element/nil | No |
| `next_sibling` | Element/nil | No |
| `previous_sibling` | Element/nil | No |
| `parent_node` | Element/nil | No |
| `owner_document` | Document | No |
| `offset_left/top/width/height` | number | No |
| `client_left/top/width/height` | number | No |
| `scroll_left/top` | number | Yes |
| `scroll_width/height` | number | No |

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `AppendChild(ptr)` | Element | Append element (moves ownership) |
| `RemoveChild(el)` | bool | Remove a child |
| `InsertBefore(ptr, adj)` | Element | Insert before adjacent |
| `ReplaceChild(new, old)` | bool | Replace a child |
| `GetElementById(id)` | Element/nil | Find by ID |
| `GetElementsByTagName(tag)` | table | Find by tag |
| `QuerySelector(sel)` | Element/nil | CSS selector (first match) |
| `QuerySelectorAll(sel)` | table | CSS selector (all matches) |
| `Matches(sel)` | bool | Test CSS selector |
| `GetAttribute(name)` | variant | Get attribute value |
| `SetAttribute(name, val)` | | Set attribute |
| `HasAttribute(name)` | bool | Check attribute |
| `RemoveAttribute(name)` | | Remove attribute |
| `SetClass(name, add)` | | Add or remove CSS class |
| `IsClassSet(name)` | bool | Check CSS class |
| `SetProperty(name, val)` | | Set inline style |
| `AddEventListener(ev, fn)` | | Attach event listener |
| `DispatchEvent(name, params)` | | Fire custom event |
| `Focus()` | | Focus element |
| `Blur()` | | Remove focus |
| `Click()` | | Simulate click |
| `ScrollIntoView(top)` | | Scroll into view |

### Event

| Property | Type | Description |
|----------|------|-------------|
| `type` | string | Event name ("click", "keydown", etc.) |
| `target_element` | Element | Element that originated the event |
| `current_element` | Element | Element currently handling the event |
| `parameters` | Proxy | Event-specific parameters |

| Method | Description |
|--------|-------------|
| `StopPropagation()` | Stop event propagation |
| `StopImmediatePropagation()` | Stop all further listeners |

### Style Proxy

Read/write CSS properties as strings:

```lua
element.style.color = "red"
element.style.width = "200dp"
local bg = element.style["background-color"]
```

### Data Models from Lua

`Context:OpenDataModel(name, table)` creates a two-way data model backed
by a Lua table:

```lua
local model = context:OpenDataModel("my_data", {
    score = 0,
    player_name = "Ranger",
    show_bonus = false,
    items = { "key_gold", "key_silver" },
    on_submit = function(event, ...)
        -- event callback binding
    end,
})

-- Read/write triggers automatic UI dirty tracking:
model.score = model.score + 100
```

RML documents can then bind to this model:

```xml
<body data-model="my_data">
    <span>{{ player_name }}: {{ score }}</span>
    <div data-if="show_bonus">BONUS!</div>
    <div data-for="item : items">{{ item }}</div>
</body>
```

**Supported value types:**
- Numbers, strings, booleans → scalar bindings
- Tables (array or map) → nested/iterable bindings
- Functions → event callback bindings (`data-event-*`)

---

## Engine Bridge API

These globals are registered by the C++ `LuaBridge` shim and provide
modders with access to engine state without C++ changes.

### `game` Table (read-only, updated each frame)

Mirrors all bindings from the C++ `GameDataModel`:

```lua
 game.health              -- int     (0-250)
 game.armor               -- int     (0-200)
 game.ammo                -- int     (current weapon ammo)
 game.active_weapon       -- int     (IT_* bitflag)
 game.shells              -- int
 game.nails               -- int
 game.rockets             -- int
 game.cells               -- int
 game.monsters            -- int
 game.total_monsters      -- int
 game.secrets             -- int
 game.total_secrets       -- int
 game.has_shotgun         -- bool
 game.has_super_shotgun   -- bool
 game.has_nailgun         -- bool
 game.has_super_nailgun   -- bool
 game.has_grenade_launcher-- bool
 game.has_rocket_launcher -- bool
 game.has_lightning_gun   -- bool
 game.has_key1            -- bool    (silver)
 game.has_key2            -- bool    (gold)
 game.has_invisibility    -- bool
 game.has_invulnerability -- bool
 game.has_suit            -- bool
 game.has_quad            -- bool
 game.has_sigil1..4       -- bool
 game.armor_type          -- int     (0=none, 1=green, 2=yellow, 3=red)
 game.weapon_label        -- string  ("SHOTGUN", "ROCKET L.", etc.)
 game.is_axe              -- bool
 game.deathmatch          -- bool
 game.coop                -- bool
 game.intermission        -- bool
 game.level_name          -- string
 game.map_name            -- string
 game.time_minutes        -- int
 game.time_seconds        -- int
 game.face_index          -- int     (0-4, health tier)
 game.face_pain           -- bool    (took damage this frame)
 game.weapon_show         -- bool    (weapon switch flash active)
 game.fire_flash          -- bool    (fire flash active)
 game.reticle_style       -- int     (resolved crosshair style)
 game.num_players         -- int
```

### `engine` Table

```lua
 engine.exec(cmd)              -- Queue console command (e.g. "map e1m1")
 engine.cvar_get(name)         -- Read cvar value (returns number or string)
 engine.cvar_set(name, value)  -- Write cvar value
 engine.time()                 -- Current realtime (seconds, float)
```

### Example: React to Engine State

```lua
function MyHud.Think(event, element, document)
    if game.has_quad and game.health > 0 then
        document:GetElementById('hud-frame'):SetClass('quad-active', true)
    end

    if game.health < 25 then
        engine.exec("play items/damage3.wav")
    end
end
```

---

## Mod File Structure with Lua

```
 mymod/
 ├── quake.rc
 └── ui/
     ├── lua/                          ← Lua scripts (loaded via <script src>)
     │   ├── hud_logic.lua             ← HUD behavior
     │   ├── menu_helpers.lua          ← Menu utilities
     │   └── damage_overlay.lua        ← Damage flash system
     ├── rml/
     │   ├── hud/
     │   │   └── hud.rml               ← HUD with <script> tags
     │   └── menus/
     │       ├── main_menu.rml         ← Menu with Lua interactivity
     │       └── stats.rml             ← Custom stats overlay
     └── rcss/
         └── lab_hud.rcss              ← Styles
```

Scripts load through `QuakeFileInterface`, so mod scripts override base
scripts at the same path. A mod can also add entirely new scripts.

---

## ui_lab Examples

These examples show what Lua scripting enables in the existing `ui_lab`
Terminal Visor HUD. Each example builds on the current `hud.rml` and
requires zero C++ changes once the bootstrap is in place.

### Example 1: Damage Flash Overlay

A screen-edge flash effect when the player takes damage, driven by
reading the health binding from the DOM:

**`ui_lab/ui/lua/damage_flash.lua`**

```lua
DamageFlash = DamageFlash or {}
DamageFlash.prev_health = 100

function DamageFlash.Think(event, element, document)
    local cur = game.health
    local prev = DamageFlash.prev_health

    if cur < prev and cur > 0 then
        local overlay = document:GetElementById('damage-overlay')
        if overlay then
            -- Trigger CSS animation by toggling class
            overlay:SetClass('flash', false)
            overlay:SetClass('flash', true)
        end
    end

    DamageFlash.prev_health = cur
end
```

**In `hud.rml` `<head>`:**

```xml
<script src="../../lua/damage_flash.lua"/>
<style>
    #damage-overlay {
        position: absolute;
        top: 0; left: 0; right: 0; bottom: 0;
        opacity: 0;
        pointer-events: none;
    }
    #damage-overlay.flash {
        animation: damage-flash 0.3s ease-out;
    }
    @keyframes damage-flash {
        0%   { opacity: 0.4; background-color: rgba(255, 0, 0, 80); }
        100% { opacity: 0; }
    }
</style>
```

**In `hud.rml` `<body>`:**

```xml
<body data-model="game" onupdate="DamageFlash.Think(event, element, document)">
    <div id="damage-overlay"></div>
    <!-- ... rest of visor HUD ... -->
</body>
```

### Example 2: Dynamic Kill Feed

A rolling message feed that Lua manages by creating and removing DOM
elements. Uses a custom data model so the feed is independent of the
C++ `NotificationModel`.

**`ui_lab/ui/lua/kill_feed.lua`**

```lua
KillFeed = KillFeed or {}
KillFeed.entries = {}
KillFeed.MAX_ENTRIES = 5
KillFeed.ENTRY_LIFETIME = 4.0  -- seconds

function KillFeed.Add(message, document)
    local feed = document:GetElementById('kill-feed')
    if not feed then return end

    -- Create entry element
    local entry = document:CreateElement('div')
    entry:SetClass('kf-entry', true)
    entry.inner_rml = message
    feed:AppendChild(entry)

    table.insert(KillFeed.entries, 1, {
        element = entry,
        time = engine.time(),
    })

    -- Trim excess
    while #KillFeed.entries > KillFeed.MAX_ENTRIES do
        local old = table.remove(KillFeed.entries)
        if old.element then
            feed:RemoveChild(old.element)
        end
    end
end

function KillFeed.Think(event, element, document)
    local feed = document:GetElementById('kill-feed')
    if not feed then return end
    local now = engine.time()

    -- Expire old entries
    local i = #KillFeed.entries
    while i >= 1 do
        local e = KillFeed.entries[i]
        local age = now - e.time
        if age > KillFeed.ENTRY_LIFETIME then
            feed:RemoveChild(e.element)
            table.remove(KillFeed.entries, i)
        elseif age > KillFeed.ENTRY_LIFETIME - 1.0 then
            -- Fade out in the last second
            e.element:SetClass('fading', true)
        end
        i = i - 1
    end
end
```

**In `hud.rml`:**

```xml
<script src="../../lua/kill_feed.lua"/>

<!-- In the visor-left-col, below notify messages -->
<div id="kill-feed" class="visor-kill-feed"></div>
```

### Example 3: Lua-Driven Stats Tracker

A custom data model created entirely in Lua, providing a real-time
performance overlay. No C++ data model changes needed.

**`ui_lab/ui/lua/stats_tracker.lua`**

```lua
Stats = Stats or {}

function Stats.Init(document)
    if Stats.model then return end

    local ctx = document.context
    Stats.model = ctx:OpenDataModel("stats", {
        session_kills = 0,
        session_deaths = 0,
        kd_ratio = "0.00",
        damage_taken = 0,
        streak = 0,
        best_streak = 0,
        show_stats = false,
    })

    Stats.prev_health = game.health
    Stats.prev_monsters = game.monsters
end

function Stats.Think(event, element, document)
    Stats.Init(document)
    if not Stats.model then return end

    -- Track kills (monster count increased)
    local cur_monsters = game.monsters
    if cur_monsters > (Stats.prev_monsters or 0) then
        local new_kills = cur_monsters - Stats.prev_monsters
        Stats.model.session_kills = Stats.model.session_kills + new_kills
        Stats.model.streak = Stats.model.streak + new_kills
        if Stats.model.streak > Stats.model.best_streak then
            Stats.model.best_streak = Stats.model.streak
        end
    end
    Stats.prev_monsters = cur_monsters

    -- Track deaths (health dropped to 0 or below from positive)
    local cur_health = game.health
    if cur_health <= 0 and (Stats.prev_health or 100) > 0 then
        Stats.model.session_deaths = Stats.model.session_deaths + 1
        Stats.model.streak = 0  -- reset kill streak
    end
    Stats.prev_health = cur_health

    -- Track damage taken
    if cur_health < (Stats.prev_health or 100) and cur_health > 0 then
        Stats.model.damage_taken = Stats.model.damage_taken
            + (Stats.prev_health - cur_health)
    end

    -- Update K/D ratio display
    local deaths = Stats.model.session_deaths
    if deaths > 0 then
        Stats.model.kd_ratio = string.format("%.2f",
            Stats.model.session_kills / deaths)
    else
        Stats.model.kd_ratio = string.format("%d",
            Stats.model.session_kills)
    end
end

function Stats.Toggle(event, element, document)
    Stats.Init(document)
    if Stats.model then
        Stats.model.show_stats = not Stats.model.show_stats
    end
end
```

**In `hud.rml`:**

```xml
<script src="../../lua/stats_tracker.lua"/>

<!-- Toggle with a keybind or button -->
<body data-model="game"
      onupdate="Stats.Think(event, element, document)"
      onkeydown="if event.parameters.key_identifier == rmlui.key_identifier.TAB then Stats.Toggle(event, element, document) end">

    <!-- Stats overlay (uses its own data model) -->
    <div data-model="stats">
        <div class="visor-stats-overlay" data-if="show_stats">
            <div class="visor-panel">
                <span class="sys-label">SESSION STATS</span>
                <div>KILLS: {{ session_kills }}</div>
                <div>DEATHS: {{ session_deaths }}</div>
                <div>K/D: {{ kd_ratio }}</div>
                <div>DMG TAKEN: {{ damage_taken }}</div>
                <div>STREAK: {{ streak }} (BEST: {{ best_streak }})</div>
            </div>
        </div>
    </div>

    <!-- ... rest of visor HUD ... -->
</body>
```

### Example 4: Visor Scanline Effect

Animated visor chrome driven by Lua, updating a CSS property each frame:

**`ui_lab/ui/lua/visor_effects.lua`**

```lua
VisorFX = VisorFX or {}
VisorFX.scanline_offset = 0
VisorFX.SPEED = 60  -- pixels per second

function VisorFX.Think(event, element, document)
    -- Advance scanline offset
    local dt = 1.0 / 72.0  -- approximate frame time
    VisorFX.scanline_offset = (VisorFX.scanline_offset + VisorFX.SPEED * dt) % 720

    local scanline = document:GetElementById('scanline-overlay')
    if scanline then
        scanline.style['top'] = math.floor(VisorFX.scanline_offset) .. 'dp'
    end

    -- Visor static on damage
    if game.face_pain then
        local frame = document:GetElementById('visor-frame')
        if frame then
            frame:SetClass('static-burst', true)
        end
    end
end
```

### Example 5: Custom Menu with Lua-Driven Options

A mod settings menu with form controls backed by a Lua data model:

**`ui_lab/ui/rml/menus/mod_settings.rml`**

```xml
<rml>
<head>
    <title>Mod Settings</title>
    <link type="text/rcss" href="../../rcss/base.rcss"/>
    <link type="text/rcss" href="../../rcss/menu.rcss"/>
    <script>
    ModSettings = ModSettings or {}

    function ModSettings.Init(document)
        if ModSettings.model then return end

        ModSettings.model = document.context:OpenDataModel("mod_settings", {
            hud_style = "visor",
            hud_opacity = 0.9,
            enable_scanlines = true,
            enable_damage_flash = true,
            reticle_color = "green",
            changed = false,
        })
    end

    function ModSettings.Apply(event, element, document)
        if not ModSettings.model then return end
        local m = ModSettings.model

        -- Push values to engine cvars
        engine.cvar_set("ui_lab_hud_style", m.hud_style)
        engine.cvar_set("ui_lab_opacity", tostring(m.hud_opacity))
        engine.cvar_set("ui_lab_scanlines", m.enable_scanlines and "1" or "0")
        engine.cvar_set("ui_lab_damage_flash", m.enable_damage_flash and "1" or "0")

        m.changed = false
    end

    function ModSettings.Cancel(event, element, document)
        document:Close()
    end
    </script>
</head>
<body data-model="mod_settings"
      onload="ModSettings.Init(document)">

    <div class="menu-panel">
        <h2>MOD SETTINGS</h2>

        <form data-event-change="changed = true">
            <label>HUD Style:
                <select name="hud_style" data-value="hud_style">
                    <option value="visor">Terminal Visor</option>
                    <option value="minimal">Minimal</option>
                    <option value="classic">Classic</option>
                </select>
            </label>

            <label>HUD Opacity:
                <input type="range" min="0.3" max="1.0" step="0.05"
                       data-value="hud_opacity"/>
            </label>

            <label>
                <input type="checkbox" data-checked="enable_scanlines"/>
                Scanline Effect
            </label>

            <label>
                <input type="checkbox" data-checked="enable_damage_flash"/>
                Damage Flash
            </label>

            <div class="btn-row">
                <button onclick="ModSettings.Apply(event, element, document)"
                        data-attrif-disabled="!changed">APPLY</button>
                <button onclick="ModSettings.Cancel(event, element, document)">
                    CANCEL</button>
            </div>
        </form>
    </div>
</body>
</rml>
```

### Example 6: Dynamic Element Creation — Weapon Wheel

A popup weapon selector built entirely in Lua by creating elements
dynamically based on which weapons the player owns:

**`ui_lab/ui/lua/weapon_wheel.lua`**

```lua
WeaponWheel = WeaponWheel or {}
WeaponWheel.visible = false

WeaponWheel.WEAPONS = {
    { flag = 1,     label = "SG",  cmd = "impulse 2" },
    { flag = 2,     label = "SSG", cmd = "impulse 3" },
    { flag = 4,     label = "NG",  cmd = "impulse 4" },
    { flag = 8,     label = "SNG", cmd = "impulse 5" },
    { flag = 16,    label = "GL",  cmd = "impulse 6" },
    { flag = 32,    label = "RL",  cmd = "impulse 7" },
    { flag = 64,    label = "LG",  cmd = "impulse 8" },
}

function WeaponWheel.Toggle(event, element, document)
    WeaponWheel.visible = not WeaponWheel.visible
    local container = document:GetElementById('weapon-wheel')
    if not container then return end

    if WeaponWheel.visible then
        WeaponWheel.Build(container, document)
        container.style.display = 'block'
    else
        container.style.display = 'none'
    end
end

function WeaponWheel.Build(container, document)
    -- Clear previous entries
    container.inner_rml = ''

    for _, wpn in ipairs(WeaponWheel.WEAPONS) do
        -- Check if player has this weapon via game state
        local has_key = "has_" .. string.lower(wpn.label)
        -- Simplified: check via the active_weapon flags in game table
        -- In practice, use the has_* booleans from game table

        local entry = document:CreateElement('div')
        entry:SetClass('ww-entry', true)
        entry.inner_rml = wpn.label

        if game.active_weapon == wpn.flag then
            entry:SetClass('active', true)
        end

        -- Event listener for selection
        entry:AddEventListener('click', function(ev, el, doc)
            engine.exec(wpn.cmd)
            WeaponWheel.Toggle(ev, el, doc)
        end)

        container:AppendChild(entry)
    end
end
```

---

## Interaction with Existing Systems

### Data Bindings

Lua scripts coexist with C++ data models:

```
 "game" model    ← Owned by C++ GameDataModel (read-only from Lua via game.*)
 "cvars" model   ← Owned by C++ CvarBinding (read/write via engine.cvar_*)
 "my_model"      ← Owned by Lua OpenDataModel (full read/write)
```

A single RML document can reference multiple models:

```xml
<body data-model="game">
    {{ health }}                           <!-- C++ binding -->

    <div data-model="stats">
        {{ session_kills }}                <!-- Lua binding -->
    </div>
</body>
```

### Action Strings

Existing `onclick="navigate('options')"` action strings continue to
work. MenuEventHandler still dispatches them. Lua handlers can call
the same actions:

```lua
-- These are equivalent:
-- RML:  onclick="navigate('options')"
-- Lua:
function GoToOptions(event, element, document)
    -- Load and show the options menu via the normal document flow
    local doc = document.context:LoadDocument('ui/rml/menus/options.rml')
    if doc then doc:Show() end
end
```

### Hot Reload

`ui_reload` clears the document cache and re-parses all RML. Since Lua
globals use the `MyMod = MyMod or {}` pattern, persistent state survives
reload. `<script>` blocks re-execute, re-defining functions with updated
code.

State stored in `OpenDataModel` tables is lost on reload (the model
is recreated). Use the `or {}` guard on the model creation to detect
this:

```lua
if MyMod.model == nil then
    MyMod.model = context:OpenDataModel("my_data", { ... })
end
```

---

## Security Considerations

### Trusted Mods (Default)

Quake mods are traditionally trusted (they run QuakeC progs.dat). Lua
scripts from mods are treated the same — full access to standard
libraries, file I/O, and engine commands.

### Sandboxing (Optional, Future)

If untrusted content support is added later, sandbox Lua by removing
dangerous globals before loading mod scripts:

```lua
-- In the C++ bootstrap, after luaL_openlibs():
local sandbox_removals = {
    'io', 'os', 'loadfile', 'dofile',
    'debug', 'package',
}
```

This is explicitly **not** part of the initial implementation. Quake
mods have always been fully trusted.

---

## Implementation Phases

### Phase 1: Enable Lua (Build + Bootstrap)

**Scope:** Flip the build flag, add Lua dependency, initialize the
plugin. No engine bridge yet.

**What modders get:**
- `<script>` tags (inline and external)
- Inline event handlers with Lua code
- Full DOM manipulation API (Element, Document, Context)
- `Context:OpenDataModel()` for Lua-driven data models
- Custom element instancers from Lua
- `rmlui.*` globals (contexts, key identifiers)

**What's missing:**
- No `game.*` table (must read from DOM text nodes)
- No `engine.exec()` (must use action strings)

**Files changed:**
- `meson_options.txt` — add `use_lua` option
- `meson.build` — Lua dep, CMake flag, link `librmlui_lua.a`
- `src/ui_manager.cpp` — `Rml::Lua::Initialise()` / `Shutdown()`
- CI workflows — add Lua packages

### Phase 2: Engine Bridge

**Scope:** Add the `game` and `engine` globals so Lua scripts can
access engine state and execute commands directly.

**What modders get:**
- `game.health`, `game.weapon_label`, etc. (read-only)
- `engine.exec("map e1m1")`
- `engine.cvar_get("sensitivity")`
- `engine.cvar_set("crosshair", "2")`
- `engine.time()` for timing/animation

**Files changed:**
- `src/internal/lua_bridge.h/.cpp` — new (~80 lines)
- `src/ui_manager.cpp` — call `LuaBridge::Initialize()` / `Update()`
- `meson.build` — add `lua_bridge.cpp` to sources

### Phase 3: Lifecycle Hooks (Future)

**Scope:** Register Lua callbacks for engine events, enabling reactive
patterns without polling.

```lua
hooks.on_level_start(function(map_name)
    Stats.Reset()
end)

hooks.on_damage_taken(function(amount, attacker)
    DamageFlash.Trigger(amount)
end)

hooks.on_weapon_switch(function(old_weapon, new_weapon)
    WeaponWheel.Highlight(new_weapon)
end)

hooks.on_item_pickup(function(item_name)
    KillFeed.Add("Picked up " .. item_name, document)
end)
```

This requires adding hook dispatch points in the engine (C), which is a
larger change than Phases 1-2.

---

## Limitations

| Limitation | Reason | Workaround |
|------------|--------|------------|
| Single Lua state | RmlUI plugin design | Use `MyMod = MyMod or {}` namespacing |
| No custom decorators | Decorator API is C++ only | Use `element.style` for per-element effects |
| No shader access | Rendering is C++ `RenderInterface_VK` | Use CSS animations + Lottie |
| Style values are strings | RmlUI proxy design | Parse with `tonumber()` when needed |
| `ElementPtr` ownership moves | Memory safety | Don't use ptr after AppendChild/InsertBefore |
| No async/timers | No Lua scheduler | Poll in `onupdate` handler, use `engine.time()` |
| `io`/`os` available | Not sandboxed by default | Acceptable for trusted mods |
| Data models lost on reload | Document re-parse recreates | Guard with `if model == nil then` |

### Gotchas

1. **Lua built as C**: Distro Lua packages are typically C, which means
   `longjmp` on errors skips C++ destructors. Use LuaJIT or build Lua
   as C++ (`-DRMLUI_LUA_BINDINGS_LIBRARY=lua_as_cxx`) to avoid this.

2. **Global namespace collisions**: All documents share one Lua state.
   Always namespace: `MyMod.func()`, never bare `func()`.

3. **`CloseLuaDataModel` lifecycle**: Data model definitions must
   outlive the RmlUI context. The C++ bootstrap handles this, but
   modders should not hold references to closed models.

4. **1-based indexing**: Lua `child_nodes[1]` is the first child. RmlUI
   data model arrays adjust internally (Lua index - 1).

5. **`inner_rml` is RML, not text**: Setting `inner_rml` parses the
   string as RML markup. Use `CreateTextNode()` for plain text.

---

## Files Reference

### New Files (Phases 1-2)

```
 src/internal/lua_bridge.h          LuaBridge API declaration
 src/internal/lua_bridge.cpp        game/engine table registration + per-frame update
```

### Modified Files

```
 meson_options.txt                  + use_lua option
 meson.build                        + Lua dependency, CMake flag, link, new source
 src/ui_manager.cpp                 + Rml::Lua::Initialise/Shutdown, LuaBridge init/update
 .github/workflows/*.yml            + Lua packages in CI
```

### RmlUI Fork (Already Exists, Unchanged)

```
 lib/rmlui/Source/Lua/              60+ files — full Lua binding implementation
 lib/rmlui/Include/RmlUi/Lua/      Public headers
 lib/rmlui/Source/Lua/CMakeLists.txt  Build config for librmlui_lua.a
 lib/rmlui/Samples/lua_invaders/   Working example (reference)
```

### ui_lab Example Files (New)

```
 ui_lab/ui/lua/                     Lua scripts directory
 ui_lab/ui/lua/damage_flash.lua     Example 1: damage overlay
 ui_lab/ui/lua/kill_feed.lua        Example 2: rolling kill feed
 ui_lab/ui/lua/stats_tracker.lua    Example 3: session stats overlay
 ui_lab/ui/lua/visor_effects.lua    Example 4: scanline animation
 ui_lab/ui/lua/weapon_wheel.lua     Example 6: dynamic weapon selector
```
