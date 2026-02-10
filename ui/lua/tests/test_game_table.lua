-- test_game_table.lua — Verify Lua 'game' table field parity with GameDataModel

suite("game table existence")
assert_not_nil(game, "game global should exist")
assert_type(game, "table", "game should be a table")

suite("game table: core stats")
assert_type(game.health,        "number", "health")
assert_type(game.armor,         "number", "armor")
assert_type(game.ammo,          "number", "ammo")
assert_type(game.active_weapon, "number", "active_weapon")

suite("game table: ammo counts")
assert_type(game.shells,  "number", "shells")
assert_type(game.nails,   "number", "nails")
assert_type(game.rockets, "number", "rockets")
assert_type(game.cells,   "number", "cells")

suite("game table: level statistics")
assert_type(game.monsters,       "number", "monsters")
assert_type(game.total_monsters, "number", "total_monsters")
assert_type(game.secrets,        "number", "secrets")
assert_type(game.total_secrets,  "number", "total_secrets")

suite("game table: weapon ownership")
assert_type(game.has_shotgun,          "boolean", "has_shotgun")
assert_type(game.has_super_shotgun,    "boolean", "has_super_shotgun")
assert_type(game.has_nailgun,          "boolean", "has_nailgun")
assert_type(game.has_super_nailgun,    "boolean", "has_super_nailgun")
assert_type(game.has_grenade_launcher, "boolean", "has_grenade_launcher")
assert_type(game.has_rocket_launcher,  "boolean", "has_rocket_launcher")
assert_type(game.has_lightning_gun,    "boolean", "has_lightning_gun")

suite("game table: keys")
assert_type(game.has_key1, "boolean", "has_key1")
assert_type(game.has_key2, "boolean", "has_key2")

suite("game table: powerups")
assert_type(game.has_invisibility,    "boolean", "has_invisibility")
assert_type(game.has_invulnerability, "boolean", "has_invulnerability")
assert_type(game.has_suit,            "boolean", "has_suit")
assert_type(game.has_quad,            "boolean", "has_quad")

suite("game table: sigils")
assert_type(game.has_sigil1, "boolean", "has_sigil1")
assert_type(game.has_sigil2, "boolean", "has_sigil2")
assert_type(game.has_sigil3, "boolean", "has_sigil3")
assert_type(game.has_sigil4, "boolean", "has_sigil4")

suite("game table: armor type")
assert_type(game.armor_type, "number", "armor_type")

suite("game table: computed weapon fields")
assert_type(game.weapon_label,     "string",  "weapon_label")
assert_type(game.ammo_type_label,  "string",  "ammo_type_label")
assert_type(game.is_axe,           "boolean", "is_axe")
assert_type(game.is_shells_weapon, "boolean", "is_shells_weapon")
assert_type(game.is_nails_weapon,  "boolean", "is_nails_weapon")
assert_type(game.is_rockets_weapon,"boolean", "is_rockets_weapon")
assert_type(game.is_cells_weapon,  "boolean", "is_cells_weapon")

suite("game table: game state flags")
assert_type(game.deathmatch,       "boolean", "deathmatch")
assert_type(game.coop,             "boolean", "coop")
assert_type(game.intermission,     "boolean", "intermission")
assert_type(game.intermission_type,"number",  "intermission_type")

suite("game table: level info")
assert_type(game.level_name, "string", "level_name")
assert_type(game.map_name,   "string", "map_name")
assert_type(game.game_title, "string", "game_title")

suite("game table: time")
assert_type(game.time_minutes, "number", "time_minutes")
assert_type(game.time_seconds, "number", "time_seconds")

suite("game table: face animation")
assert_type(game.face_index, "number",  "face_index")
assert_type(game.face_pain,  "boolean", "face_pain")

suite("game table: reticle state")
assert_type(game.reticle_style,  "number",  "reticle_style")
assert_type(game.weapon_show,    "boolean", "weapon_show")
assert_type(game.fire_flash,     "boolean", "fire_flash")
assert_type(game.weapon_firing,  "boolean", "weapon_firing")

suite("game table: chat")
assert_type(game.chat_active, "boolean", "chat_active")
assert_type(game.chat_prefix, "string",  "chat_prefix")
assert_type(game.chat_text,   "string",  "chat_text")

suite("game table: player count")
assert_type(game.num_players, "number", "num_players")

suite("game table: read-only enforcement")
assert_error(function() game.health = 999 end, "write to game.health should error")
assert_error(function() game.new_field = true end, "write to new field should error")

suite("game table: proxy reads work through local")
local g = game
assert_type(g.health, "number", "local alias read should work")
