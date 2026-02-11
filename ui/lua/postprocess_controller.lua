--
-- postprocess_controller.lua
--
-- Helmet display echo: subtle depth ghost during gameplay,
-- stronger in menus for that full visor-projection look.
--

PostProcess = {}

-- Echo intensity per context
PostProcess.ECHO_HUD  = 0.1
PostProcess.ECHO_MENU = 0.2
PostProcess.SCALE     = 1.01

PostProcess.last_echo = nil
PostProcess.initialized = false

local function format_val (v)
	return string.format ("%.6f", v)
end

function PostProcess.Think ()
	-- Set scale once
	if not PostProcess.initialized then
		engine.cvar_set ("r_ui_echo_scale", format_val (PostProcess.SCALE))
		PostProcess.initialized = true
	end

	local hud_up = engine.hud_visible ()
	local target = hud_up and PostProcess.ECHO_HUD or PostProcess.ECHO_MENU

	if PostProcess.last_echo ~= target then
		engine.cvar_set ("r_ui_echo", format_val (target))
		PostProcess.last_echo = target
	end
end

engine.on_frame ("postprocess", PostProcess.Think)
