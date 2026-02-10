-- test_runner.lua — Minimal Lua test framework for vkQuake RmlUI
--
-- Loaded by the 'lua_test' console command via LuaBridge::RunTests().
-- Discovers and runs test files, prints a summary.

local pass_count = 0
local fail_count = 0
local current_suite = ""

function assert_true(expr, msg)
    if expr then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        engine.exec("echo [FAIL] " .. current_suite .. ": " .. (msg or "assertion failed"))
    end
end

function assert_false(expr, msg)
    assert_true(not expr, msg or "expected false")
end

function assert_equal(a, b, msg)
    if a == b then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        local detail = tostring(a) .. " ~= " .. tostring(b)
        engine.exec("echo [FAIL] " .. current_suite .. ": " .. (msg or detail))
    end
end

function assert_type(val, expected_type, msg)
    local actual = type(val)
    if actual == expected_type then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        local detail = "expected " .. expected_type .. ", got " .. actual
        engine.exec("echo [FAIL] " .. current_suite .. ": " .. (msg or detail))
    end
end

function assert_not_nil(val, msg)
    assert_true(val ~= nil, msg or "expected non-nil")
end

function assert_error(fn, msg)
    local ok, _ = pcall(fn)
    if not ok then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        engine.exec("echo [FAIL] " .. current_suite .. ": " .. (msg or "expected error"))
    end
end

function suite(name)
    current_suite = name
    engine.exec("echo [SUITE] " .. name)
end

-- Run test files
-- Note: we use dofile-style loading via the RmlUI Lua interpreter.
-- The test files are expected to define tests inline (no deferred execution).

local test_files = {
    "ui/lua/tests/test_game_table.lua",
    "ui/lua/tests/test_engine_api.lua",
    "ui/lua/tests/test_actions.lua",
}

engine.exec("echo ========================================")
engine.exec("echo   Lua Test Suite")
engine.exec("echo ========================================")

for _, path in ipairs(test_files) do
    local fn, err = loadfile(path)
    if fn then
        local ok, runtime_err = pcall(fn)
        if not ok then
            fail_count = fail_count + 1
            engine.exec("echo [ERROR] " .. path .. ": " .. tostring(runtime_err))
        end
    else
        fail_count = fail_count + 1
        engine.exec("echo [ERROR] Failed to load " .. path .. ": " .. tostring(err))
    end
end

engine.exec("echo ========================================")
local total = pass_count + fail_count
if fail_count == 0 then
    engine.exec("echo   PASSED: " .. total .. "/" .. total .. " assertions")
    engine.exec("echo   lua_test: ALL TESTS PASSED")
else
    engine.exec("echo   FAILED: " .. fail_count .. "/" .. total .. " assertions")
    engine.exec("echo   lua_test: TESTS FAILED")
end
engine.exec("echo ========================================")
