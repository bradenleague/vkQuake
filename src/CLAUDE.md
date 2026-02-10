# src/ — RmlUI Integration Layer

C++ bridge between the vkQuake engine (pure C) and RmlUI (C++17).

## C/C++ Boundary

- `ui_manager.h` — `extern "C"` public API (50+ functions). Zero C++ types cross the boundary.
- All engine-side calls gated with `#ifdef USE_RMLUI` (15 files in `Quake/`)
- Shared types in `types/` are C-compatible headers
- C++ code lives in `namespace QRmlUI`

**Critical**: Return types in `extern "C"` wrappers must EXACTLY match original function signatures (e.g., `float` vs `double` for `Cvar_VariableValue`). Type mismatches cause silent data corruption.

## File Map

```
ui_manager.h/.cpp         Public C API — what the engine calls
types/                    Header-only C-compatible types
  input_mode.h              UI_INPUT_INACTIVE / MENU_ACTIVE / OVERLAY
  game_state.h              Synced game state struct
  notification_state.h      Centerprint + notify line state
  cvar_schema.h             Console variable metadata
  cvar_provider.h           ICvarProvider interface
  command_executor.h        ICommandExecutor interface
  video_mode.h              Video mode list
internal/                 C++ implementation (namespace QRmlUI)
  render_interface_vk       Custom Vulkan renderer (pipelines, buffers, textures)
  vk_allocator              Vulkan memory management
  system_interface          Time/logging/clipboard bridge
  quake_file_interface      File I/O through Quake's pak/filesystem
  game_data_model           Sync game state → RmlUI data bindings (50+ bindings)
  notification_model        Centerprint + 4 notify lines with expiry
  cvar_binding              Two-way sync between cvars and UI elements
  menu_event_handler        Menu click dispatch (navigate, command, close, etc.)
  quake_cvar_provider       ICvarProvider implementation
  quake_command_executor    ICommandExecutor implementation
```

## Input Modes (`ui_input_mode_t`)

1. `UI_INPUT_INACTIVE` — Game controls active, RmlUI doesn't capture input
2. `UI_INPUT_MENU_ACTIVE` — Menu captures all input
3. `UI_INPUT_OVERLAY` — HUD visible, input passes through to game

## Engine Integration Points

All hooks behind `#ifdef USE_RMLUI`:

| Point | Engine File | UI Call |
|-------|-------------|---------|
| Init | `host.c` | `UI_Init()` |
| Vulkan setup | `gl_vidsdl.c` | `UI_InitializeVulkan()` |
| Frame | `gl_screen.c` | `UI_BeginFrame()`, `UI_Update()`, `UI_Render()`, `UI_EndFrame()` |
| Input (SDL2) | `in_sdl2.c` | `UI_*Event()` functions |
| Input (SDL3) | `in_sdl3.c` | `UI_*Event()` functions |
| Escape | `keys.c` | `UI_WantsMenuInput()`, `UI_HandleEscape()` |
| Game state | `sbar.c` | `UI_SyncGameState()`, `UI_ShowHUD()`, `UI_HideHUD()` |
| Disconnect | `cl_main.c`, `cl_demo.c` | Cleanup on disconnect |
| Shutdown | `host.c` | `UI_Shutdown()` |

## Code Conventions

- Classes: PascalCase with underscore suffix for implementations (`RenderInterface_VK`)
- Private members: `m_` prefix
- Namespace: `QRmlUI` (distinct from RmlUI's `Rml::`)
- C API functions: `UI_` prefix, snake_case
- C structs: `_t` suffix

## Key Documentation

- `docs/RMLUI_INTEGRATION.md` — Full API reference, input handling, menu stack
- `docs/DATA_CONTRACT.md` — Engine-to-UI data flow, complete binding reference
