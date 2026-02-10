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
      └─ LuaBridge        ─── exposes game state + engine.exec to Lua
      │
      │ extern "C" boundary
      │
      ▼
 Quake Engine (C)
```

Key principle: **Lua is additive**. The existing C++ data models, action
dispatch, and binding system continue to work unchanged. Lua adds a
scripting layer on top — modders can use both in the same document.

### Design Philosophy

This project uses a **document-authored, declarative** approach to UI.
RML documents and RCSS stylesheets are the source of truth for layout,
styling, and behavior. Data bindings (`{{ health }}`, `{{ weapon_label }}`)
connect engine state to the document without code. RCSS transitions and
class toggles drive animation and visual state changes.

Lua's role is as a **reactive state mapper** — thin glue between engine
events and document state. Scripts should:

- **Read** from `game.*` (read-only — writes raise a Lua error)
- **Write** to data model variables (exposing computed/derived state)
- **Toggle classes** on documents (letting RCSS handle the visual response)
- **Call registered engine actions** via `engine.exec()`

Scripts should **not**:

- Build or create element trees from code
- Set inline styles (`element.style["prop"] = "val"` for layout/visual state)
- Manage animation timers or frame-by-frame visual updates
- Become the source of truth for anything visual

If markup + RCSS + data binding can express it, prefer that over Lua.
The reticle controller (`ui_lab/ui/lua/reticle_controller.lua`) is a
good reference — it maps engine state to class names and lets RCSS do
the rest. The base HUD uses pure `data-class` bindings instead.

See also: [Event ownership](RMLUI_INTEGRATION.md) — `on*` attributes
go through the Lua event instancer, which dispatches action strings
(like `navigate`, `close`, `cycle_cvar`) via registered Lua globals.
`data-event-*` attributes are for data model event callbacks inside
`data-for` loops (like `load_slot`, `select_mod`).

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

Mirrors all bindings from the C++ `GameDataModel`. Read-only — writes
raise a Lua error.

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
 game.ammo_type_label     -- string  ("SHELLS", "NAILS", "ROCKETS", "CELLS", "")
 game.is_axe              -- bool
 game.is_shells_weapon    -- bool    (SG or SSG)
 game.is_nails_weapon     -- bool    (NG or SNG)
 game.is_rockets_weapon   -- bool    (GL or RL)
 game.is_cells_weapon     -- bool    (LG)
 game.deathmatch          -- bool
 game.coop                -- bool
 game.intermission        -- bool
 game.intermission_type   -- int     (0=none, 1=text, 2=finale)
 game.game_title          -- string  (derived from active game directory)
 game.level_name          -- string
 game.map_name            -- string
 game.time_minutes        -- int
 game.time_seconds        -- int
 game.face_index          -- int     (0-4, health tier)
 game.face_pain           -- bool    (took damage this frame)
 game.weapon_show         -- bool    (weapon switch flash active)
 game.fire_flash          -- bool    (fire flash active)
 game.weapon_firing       -- bool    (weaponframe != 0, sustained fire)
 game.reticle_style       -- int     (resolved crosshair style)
 game.chat_active         -- bool    (chat input overlay visible)
 game.chat_prefix         -- string  ("say:" or "say_team:")
 game.chat_text           -- string  (current chat input buffer)
 game.num_players         -- int
```

### `engine` Table

```lua
 engine.exec(cmd)              -- Queue console command (e.g. "map e1m1")
 engine.cvar_get(name)         -- Read cvar value (always returns string)
 engine.cvar_get_number(name)  -- Read cvar value as number (returns float)
 engine.cvar_set(name, value)  -- Write cvar value
 engine.time()                 -- Current realtime (seconds, float)
 engine.on_frame(name, fn)     -- Register a named per-frame callback
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

## ui_lab Examples (Planned)

These examples show what Lua scripting could enable in a `ui_lab`
Terminal Visor HUD mod. Each example builds on the current `hud.rml`
and requires zero C++ changes. These scripts do not ship in-tree —
they serve as reference patterns for modders.

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

## Lua-Driven Reticles

The custom reticle element system (`<reticle>`, `<reticle-dot>`,
`<reticle-line>`, `<reticle-ring>`, `<reticle-arc>`) uses 7 animatable
RCSS properties. Today, animation is driven by two C++ booleans
(`fire_flash`, `weapon_show`) that toggle `.firing`/`.equipping` classes.
Lua unlocks a much richer interaction model.

### How Reticles Work Today (No Lua)

```
 C++ GameDataModel                  RCSS                        Rendering
 ═══════════════                    ════                        ═════════

 fire_flash  (bool, 0.30s TTL)  ──► data-class-firing  ──────► .firing {
 weapon_show (bool, 0.15s TTL)  ──► data-class-equipping ───►   reticle-gap: 7dp;    ← expand
                                                                 reticle-radius: 14dp; ← expand
                                                               }
                                                               .equipping {
                                                                 reticle-gap: 1dp;     ← collapse
                                                                 reticle-length: 4dp;  ← collapse
                                                               }

 transition: reticle-radius reticle-gap reticle-length reticle-stroke 0.25s quadratic-out;
```

This gives exactly **2 binary states** with **fixed animation targets**.
Every weapon, every reticle style gets the same expansion/collapse behavior.

### What Lua Enables

With Lua, modders can:

1. **Per-weapon reticle parameters** — different spread, stroke, speed per weapon
2. **Continuous animation** — idle breathing, ammo-reactive pulsing
3. **Multi-state transitions** — not just firing/equipping but low-ammo, powerup, damage-taken
4. **Dynamic geometry** — add/remove arcs, lines, rings based on game state
5. **Parametric animation** — spread proportional to fire rate, not binary on/off

### Base Engine: Declarative Reticle (No Lua)

The base HUD uses pure `data-class` bindings — no Lua scripts. The
`weapon_firing` binding tracks live `weaponframe != 0` state from the
engine, and `weapon_show` tracks weapon raise animation.

**In `ui/rml/hud/hud.rml`:**

```xml
<div id="crosshair-container" class="crosshair" data-if="reticle_style > 0"
     data-class-firing="weapon_firing"
     data-class-equipping="weapon_show">
    <!-- reticle elements unchanged -->
</div>
```

**In `ui/rcss/hud.rcss`:**

```css
/* Fire animation: expand outward (data-class binding toggles .firing) */
.crosshair.firing reticle-line { reticle-gap: 7dp; }
.crosshair.firing reticle-ring { reticle-radius: 14dp; }

/* Equip animation: collapse then restore */
.crosshair.equipping reticle-line { reticle-gap: 1dp; reticle-length: 3dp; }
.crosshair.equipping reticle-ring { reticle-radius: 3dp; }
```

RCSS transitions handle the interpolation. A single generic `.firing`
rule gives uniform expand-on-fire for all weapons.

### Mod Example (ui_lab): Lua-Enhanced Per-Weapon Reticle

Mods can replace the declarative approach with a Lua controller for
per-weapon reticle profiles. The `ui_lab` mod demonstrates this —
see `ui_lab/ui/lua/reticle_controller.lua`.

The controller maps `game.weapon_firing` state to per-weapon CSS
classes (`.firing-sg`, `.firing-ssg`, etc.) via `engine.on_frame`,
letting each weapon have distinct spread/collapse values in RCSS.

```
 Lua sets target    RCSS transition    Procedural geometry
 ══════════════     ═══════════════    ═══════════════════
 style['reticle-gap'] = '7dp'
                    ──► interpolates 4dp → 7dp over 0.25s
                                       ──► OnPropertyChange() fires
                                           GenerateGeometry() rebuilds mesh
```

### ui_lab: Advanced Reticle Behaviors

The Terminal Visor mod pushes the system further with continuous
animation, multi-state awareness, and per-weapon reticle composition.

**`ui_lab/ui/lua/visor_reticle.lua`**

```lua
VisorReticle = VisorReticle or {}

-- Weapon-specific reticle compositions: define which primitives to use per weapon.
-- This goes beyond the base 4 styles — each weapon gets a tailored reticle.
VisorReticle.WEAPON_RETICLES = {
    -- SG: cross + ring, medium spread
    [1]  = { type = "cross_ring",  idle_gap = 4, idle_radius = 10,
             fire_gap = 6, fire_radius = 13, fire_stroke = 2.0,
             breath_amount = 0.5 },
    -- SSG: wide arcs + dot, big kick
    [2]  = { type = "arcs_dot",    idle_radius = 12, idle_arc_span = 80,
             fire_radius = 20, fire_arc_span = 120,
             breath_amount = 0.8 },
    -- NG: tight dot + thin ring, fast pulse
    [4]  = { type = "dot_ring",    idle_radius = 6,
             fire_radius = 9, fire_dot_radius = 3,
             breath_amount = 0.3, breath_speed = 3.0 },
    -- SNG: dual ring, tight
    [8]  = { type = "dual_ring",   idle_inner = 4, idle_outer = 8,
             fire_inner = 6, fire_outer = 11,
             breath_amount = 0.2, breath_speed = 4.0 },
    -- GL: wide chevron, slow
    [16] = { type = "arcs_dot",    idle_radius = 14, idle_arc_span = 60,
             fire_radius = 22, fire_arc_span = 90,
             breath_amount = 1.0, breath_speed = 1.0 },
    -- RL: ring + cross, big punch
    [32] = { type = "cross_ring",  idle_gap = 5, idle_radius = 12,
             fire_gap = 14, fire_radius = 20, fire_stroke = 2.5,
             breath_amount = 0.6 },
    -- LG: tight dot, beam-focus
    [64] = { type = "dot_ring",    idle_radius = 4,
             fire_radius = 3, fire_dot_radius = 2,
             breath_amount = 0.1, breath_speed = 6.0 },
}

VisorReticle.state = "idle"       -- "idle", "firing", "equipping", "cooldown"
VisorReticle.state_start = 0
VisorReticle.prev_fire = false
VisorReticle.prev_equip = false
VisorReticle.prev_weapon = 0

-- Idle breathing: subtle pulsation so the reticle feels alive.
function VisorReticle.BreathOffset()
    local cfg = VisorReticle.GetWeaponConfig()
    local amount = cfg.breath_amount or 0.5
    local speed = cfg.breath_speed or 2.0
    return math.sin(engine.time() * speed) * amount
end

function VisorReticle.GetWeaponConfig()
    return VisorReticle.WEAPON_RETICLES[game.active_weapon]
        or VisorReticle.WEAPON_RETICLES[1]  -- fallback to SG
end

function VisorReticle.Think(event, element, document)
    local container = document:GetElementById('crosshair-container')
    if not container then return end

    -- State machine: detect transitions
    local now = engine.time()
    local firing = game.fire_flash
    local equipping = game.weapon_show

    -- Rising edge: entered firing
    if firing and not VisorReticle.prev_fire then
        VisorReticle.state = "firing"
        VisorReticle.state_start = now
    -- Rising edge: entered equipping
    elseif equipping and not VisorReticle.prev_equip then
        VisorReticle.state = "equipping"
        VisorReticle.state_start = now
    -- Falling edge: fire ended → brief cooldown before idle
    elseif not firing and VisorReticle.prev_fire then
        VisorReticle.state = "cooldown"
        VisorReticle.state_start = now
    -- Cooldown → idle after 0.15s
    elseif VisorReticle.state == "cooldown" and (now - VisorReticle.state_start > 0.15) then
        VisorReticle.state = "idle"
    -- Equip ended
    elseif not equipping and VisorReticle.state == "equipping" then
        VisorReticle.state = "idle"
    end

    VisorReticle.prev_fire = firing
    VisorReticle.prev_equip = equipping

    -- Apply state to reticle primitives
    local cfg = VisorReticle.GetWeaponConfig()

    if VisorReticle.state == "firing" then
        VisorReticle.ApplyFiring(container, cfg)
    elseif VisorReticle.state == "equipping" then
        VisorReticle.ApplyEquipping(container, cfg)
    else
        VisorReticle.ApplyIdle(container, cfg)
    end

    -- Low ammo warning: tighten reticle + change color
    if game.ammo <= 5 and not game.is_axe then
        VisorReticle.ApplyLowAmmo(container)
    end

    -- Weapon switch: rebuild reticle composition if weapon changed
    if game.active_weapon ~= VisorReticle.prev_weapon then
        VisorReticle.RebuildForWeapon(container, document, cfg)
        VisorReticle.prev_weapon = game.active_weapon
    end
end

function VisorReticle.ApplyFiring(container, cfg)
    local lines = container:GetElementsByTagName('reticle-line')
    for _, line in ipairs(lines) do
        line.style['reticle-gap'] = (cfg.fire_gap or 7) .. 'dp'
    end

    local rings = container:GetElementsByTagName('reticle-ring')
    for _, ring in ipairs(rings) do
        ring.style['reticle-radius'] = (cfg.fire_radius or 14) .. 'dp'
        if cfg.fire_stroke then
            ring.style['reticle-stroke'] = cfg.fire_stroke .. 'dp'
        end
    end

    local arcs = container:GetElementsByTagName('reticle-arc')
    for _, arc in ipairs(arcs) do
        arc.style['reticle-radius'] = (cfg.fire_radius or 14) .. 'dp'
    end
end

function VisorReticle.ApplyEquipping(container, cfg)
    local lines = container:GetElementsByTagName('reticle-line')
    for _, line in ipairs(lines) do
        line.style['reticle-gap'] = '1dp'
        line.style['reticle-length'] = '3dp'
    end

    local rings = container:GetElementsByTagName('reticle-ring')
    for _, ring in ipairs(rings) do
        ring.style['reticle-radius'] = '3dp'
    end
end

function VisorReticle.ApplyIdle(container, cfg)
    local breath = VisorReticle.BreathOffset()

    local lines = container:GetElementsByTagName('reticle-line')
    for _, line in ipairs(lines) do
        line.style['reticle-gap'] = (cfg.idle_gap or 4) + breath .. 'dp'
        line.style['reticle-length'] = '8dp'
    end

    local rings = container:GetElementsByTagName('reticle-ring')
    for _, ring in ipairs(rings) do
        ring.style['reticle-radius'] = (cfg.idle_radius or 10) + breath .. 'dp'
        ring.style['reticle-stroke'] = '1.5dp'
    end

    local arcs = container:GetElementsByTagName('reticle-arc')
    for _, arc in ipairs(arcs) do
        arc.style['reticle-radius'] = (cfg.idle_radius or 10) + breath .. 'dp'
    end
end

function VisorReticle.ApplyLowAmmo(container)
    -- Tighten everything by 30% and shift to amber
    local primitives = container:QuerySelectorAll('reticle-dot, reticle-line, reticle-ring, reticle-arc')
    for _, el in ipairs(primitives) do
        el.style['image-color'] = '#e6a030cc'
    end
end

-- Dynamic reticle composition: swap out child elements based on weapon.
-- This is the advanced feature — the reticle shape itself changes per weapon.
function VisorReticle.RebuildForWeapon(container, document, cfg)
    -- Find the active <reticle> element
    local reticles = container:GetElementsByTagName('reticle')
    if #reticles == 0 then return end
    local reticle = reticles[1]

    -- Reset color on weapon switch
    local primitives = container:QuerySelectorAll('reticle-dot, reticle-line, reticle-ring, reticle-arc')
    for _, el in ipairs(primitives) do
        el.style['image-color'] = ''  -- clear inline, fall back to RCSS
    end
end
```

**RCSS additions in `ui_lab/ui/rcss/lab_hud.rcss`:**

```css
/* Faster transitions for Lua-driven reticles (Lua sets targets, RCSS interpolates) */
reticle-dot, reticle-line, reticle-ring, reticle-arc {
    transition: reticle-radius reticle-gap reticle-length reticle-stroke
                reticle-start-angle reticle-end-angle
                image-color
                0.15s quadratic-out;
}

/* Powerup reticle color overrides (Lua could also set these) */
.has-quad reticle-dot,  .has-quad reticle-line,
.has-quad reticle-ring, .has-quad reticle-arc  { image-color: #4488ffcc; }

.has-pent reticle-dot,  .has-pent reticle-line,
.has-pent reticle-ring, .has-pent reticle-arc  { image-color: #ff4444cc; }
```

### Key Design Principle: Lua Sets Targets, RCSS Animates

```
 PER FRAME:
 ══════════
 Lua reads game.fire_flash, game.active_weapon
     │
     ├── Looks up per-weapon profile
     ├── Computes idle breath offset (sin wave)
     └── Sets inline style values on reticle elements
              │
              ▼
         element.style['reticle-gap'] = '7dp'
              │
              ▼
 RCSS transition engine interpolates from current → target
     (defined once in stylesheet, never touched by Lua)
              │
              ▼
 OnPropertyChange() fires on each interpolation step
     → GenerateGeometry() rebuilds procedural mesh
              │
              ▼
 OnRender() draws the mesh at parent center
```

Lua never does per-frame geometry math. It just says "the gap should be
7dp now" and the RCSS transition + procedural geometry pipeline handles
the rest. This is the same pattern as the current `.firing` class
approach, but with continuous values instead of binary states.

### What Modders Can Customize (Without C++ Changes)

| Aspect | Today (RCSS-only) | With Lua |
|--------|-------------------|----------|
| Fire animation targets | Fixed (same for all weapons) | Per-weapon profiles |
| Equip animation targets | Fixed | Per-weapon profiles |
| Animation states | 2 (firing, equipping) | N (idle, firing, cooldown, equipping, low-ammo, powerup, ...) |
| Idle behavior | Static | Breathing/pulsing via `sin()` |
| Reticle color | Fixed per theme | Reactive (low ammo = amber, powerup = blue, etc.) |
| Reticle composition | 4 preset styles | Dynamic — change shape per weapon |
| Transition timing | Fixed 0.25s | Per-state timing via different RCSS classes |
| Spread amount | Fixed dp values | Proportional to weapon characteristics |

### Idle Breathing Detail

The `VisorReticle.BreathOffset()` function deserves explanation. This
sets inline styles every frame, which normally bypasses RCSS transitions.
For breathing, this is intentional — we want continuous sinusoidal motion,
not a transition to a fixed target.

However, when switching **from** idle **to** firing, the RCSS transition
kicks in because we're setting a new fixed target (`fire_gap`). The
transition interpolates from the current breath-offset position to the
fire target, giving a natural feel.

```
 Time ─────────────────────────────────────►

 Idle:     ~~~sin wave~~~  (Lua sets every frame, no transition)
                          │
                          ▼ fire_flash = true
 Firing:                  ╲ (transition from ~4.3dp to 7dp over 0.15s)
                            ─────── 7dp target ───────
                                                      │
                                                      ▼ fire_flash = false
 Cooldown:                                            ╱ (transition 7dp → ~4dp)
                                                     ~~~sin wave resumes~~~
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
work. The Lua action globals bridge them through `MenuEventHandler`.
Lua handlers can call the same actions:

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

### Phase 1: Enable Lua (Build + Bootstrap) — Complete

**Shipped.** Lua dependency, build integration, `Rml::Lua::Initialise()`,
`<script>` tags, inline event handlers, full DOM API, `OpenDataModel`,
and `rmlui.*` globals are all in place.

### Phase 2: Engine Bridge — Complete

**Shipped.** The `game` table (read-only, 50+ fields) and `engine`
table (`exec`, `cvar_get`, `cvar_get_number`, `cvar_set`, `time`,
`on_frame`) are registered. Action globals bridge menu action strings
through `MenuEventHandler`. The `ui_lab` mod's reticle controller
(`ui_lab/ui/lua/reticle_controller.lua`) demonstrates Lua-driven
per-weapon reticle profiles. The base HUD uses declarative
`data-class` bindings instead (no Lua dependency).

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
| No shader access | Rendering is C++ `RenderInterface_VK` | Use RCSS animations + custom RmlUI elements |
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

### Lua Bridge

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

### ui_lab Example Files

The `ui_lab` mod demonstrates Lua scripting in the Terminal Visor HUD.

```
 ui_lab/ui/lua/                          Lua scripts directory
 ui_lab/ui/lua/reticle_controller.lua    Per-weapon reticle profiles (shipped)
 ui_lab/ui/lua/damage_flash.lua          Example: damage overlay (planned)
 ui_lab/ui/lua/kill_feed.lua             Example: rolling kill feed (planned)
 ui_lab/ui/lua/stats_tracker.lua         Example: session stats overlay (planned)
 ui_lab/ui/lua/visor_effects.lua         Example: scanline animation (planned)
 ui_lab/ui/lua/weapon_wheel.lua          Example: dynamic weapon selector (planned)
```
