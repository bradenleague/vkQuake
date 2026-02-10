-- test_actions.lua — Verify all 15 action globals exist as functions

suite("action globals")

local action_names = {
    "navigate", "command", "cvar_changed", "cycle_cvar",
    "close", "close_all", "quit", "new_game",
    "load_game", "save_game", "bind_key", "main_menu",
    "connect_to", "host_game", "load_mod",
}

for _, name in ipairs(action_names) do
    local fn = _G[name]
    assert_not_nil(fn, name .. " should exist as a global")
    assert_type(fn, "function", name .. " should be a function")
end

assert_equal(#action_names, 15, "should have exactly 15 action globals")
