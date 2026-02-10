-- test_engine_api.lua — Verify engine.* API surface

suite("engine table existence")
assert_not_nil(engine, "engine global should exist")
assert_type(engine, "table", "engine should be a table")

suite("engine.exec")
assert_type(engine.exec, "function", "engine.exec should be a function")

suite("engine.cvar_get")
assert_type(engine.cvar_get, "function", "engine.cvar_get should be a function")
-- cvar_get returns a string
local vol = engine.cvar_get("volume")
assert_type(vol, "string", "cvar_get should return string")

suite("engine.cvar_get_number")
assert_type(engine.cvar_get_number, "function", "engine.cvar_get_number should be a function")
-- cvar_get_number returns a number
local vol_num = engine.cvar_get_number("volume")
assert_type(vol_num, "number", "cvar_get_number should return number")

suite("engine.cvar_set")
assert_type(engine.cvar_set, "function", "engine.cvar_set should be a function")

suite("engine.time")
assert_type(engine.time, "function", "engine.time should be a function")
local t = engine.time()
assert_type(t, "number", "engine.time() should return number")
assert_true(t > 0, "engine.time() should be positive")

suite("engine.on_frame")
assert_type(engine.on_frame, "function", "engine.on_frame should be a function")
