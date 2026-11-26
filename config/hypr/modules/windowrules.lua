--  __      __.__            .___
-- /  \    /  \__| ____    __| _/______  _  ________
-- \   \/\/   /  |/    \  / __ |/  _ \ \/ \/ /  ___/
--  \        /|  |   |  \/ /_/ (  <_> )     /\___ \
--   \__/\  / |__|___|  /\____ |\____/ \/\_//____  >
--        \/          \/      \/                 \/
--                              .___
--            _____    ____    __| _/
--            \__  \  /    \  / __ |
--             / __ \|   |  \/ /_/ |
--            (____  /___|  /\____ |
--                 \/     \/      \/
-- .____
-- |    |   _____  ___.__. ___________  ______
-- |    |   \__  \<   |  |/ __ \_  __ \/  ___/
-- |    |___ / __ \\___  \  ___/|  | \/\___ \
-- |_______ (____  / ____|\___  >__|  /____  >
--         \/    \/\/         \/           \/

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

--------------------
--- WINDOW RULES ---
--------------------

-- Ignore maximize requests from all apps
hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })

-- Fix some dragging issues with XWayland
hl.window_rule({
	name = "fix-xwayland-drags",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})

-------------------
--- LAYER RULES ---
-------------------

---- Presets
-- Video and games always fully opaque: the global active/inactive opacity
-- (decoration.lua) is for terminals and utilities, not for content.
hl.window_rule({
	name = "opaque-media",
	match = { class = "^(mpv|vlc|org\\.videolan\\.VLC|io\\.github\\.celluloid_player\\.Celluloid|org\\.kde\\.haruna|obs|com\\.obsproject\\.Studio)$" },
	opaque = true,
})
hl.window_rule({
	name = "opaque-games",
	match = { class = "^(steam|steam_app_\\d+|gamescope|Minecraft.*|minecraft-launcher|lutris|heroic)$" },
	opaque = true,
})
-- Sumi Discord glass (~/Projects/Sumi-Discord, README → Glass): Discord at 100 % so the global opacity doesn't
-- fade its text; its own alpha (the "Sumi · Glass" theme) still shows the blurred desktop. Not `opaque`/`force_rgbx`:
-- those discard the alpha channel. Backup: ~/.local/state/sumi-discord-20261124/windowrules.lua.before
hl.window_rule({
	name = "sumi-discord-glass",
	match = { class = "^([Dd]iscord|vesktop)$" },
	opacity = "1.0 override 1.0 override",
})

hl.layer_rule({ name = "blur quickshell", match = { namespace = "sumi-shell" }, blur = true, ignore_alpha = 0.4 })

hl.layer_rule({
	name = "blur quickshell uis",
	match = { namespace = "^sumi-(audio|calendar|login|monitor|wallhaven|keybinds|notifications|settings|tasks)$" },
	blur = true,
	ignore_alpha = 0.4,
})

hl.layer_rule({ name = "sumi-shell-motion", match = { namespace = "^sumi-.*$" }, no_anim = true })

--------------------------
---- WORKSPACE RULES -----
--------------------------

-- Workspace de una sola ventana tileada:
--hl.workspace_rule({ workspace = "w[tv1]", gaps_out  = 20, gaps_in   = 10, })
--hl.workspace_rule({ workspace = "f[1]", gaps_out  = 20, gaps_in   = 10, })
--hl.window_rule({ name  = "no-gaps-wtv1", match = { float     = false, workspace = "w[tv1]",}, border_size    = 2, rounding       = 20, rounding_power = 2.4, })
--hl.window_rule({ name  = "no-gaps-f1", match = { float     = false, workspace = "f[1]", }, border_size    = 2, rounding       = 20, rounding_power = 2.4, })

-- Special workspace (scratchpad)
hl.workspace_rule({ workspace = "special:magic", gaps_out = 20, gaps_in = 5, border_size = 0 })
