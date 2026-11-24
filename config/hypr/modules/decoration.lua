-- ________                                    __  .__
-- \______ \   ____   ____  ________________ _/  |_|__| ____   ____
--  |    |  \_/ __ \_/ ___\/  _ \_  __ \__  \\   __\  |/  _ \ /    \
--  |    `   \  ___/\  \__(  <_> )  | \// __ \|  | |  (  <_> )   |  \
-- /_______  /\___  >\___  >____/|__|  (____  /__| |__|\____/|___|  /
--         \/     \/     \/                 \/                    \/

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
	general = {
		gaps_in = 8,
		gaps_out = { top = 10, right = 10, bottom = 15, left = 10 },

		border_size = 1,

		-- El color lo escribe matugen (o la copia estática / un preset de la shell) en hypr/colors.lua: así
		-- sobrevive a una recarga de Hyprland (paletas estáticas F-d, 2026-11-04). Si falta o no se puede
		-- leer, el teal Minimaru de siempre — misma identidad de reposo que
		-- hypr/scripts/dynamic-colors.static.sh, para que un arranque en frío y un "apagar el toggle" luzcan igual.
		col = (function()
			local ok, c = pcall(dofile, require("modules.vars").hyprDir .. "/colors.lua")
			if ok and type(c) == "table" and c.active_border and c.inactive_border then
				return c
			end
			return { active_border = "rgba(90cececc)", inactive_border = "rgba(90cece0f)" }
		end)(),

		resize_on_border = true,
		extend_border_grab_area = 18,
		hover_icon_on_border = true,

		allow_tearing = false,
	},

	decoration = {
		rounding = 0,

		active_opacity = 0.95,
		inactive_opacity = 0.90,
		fullscreen_opacity = 1,

		shadow = {
			enabled = true,
			range = 8,
			render_power = 1,
			sharp = false,
			color = "rgba(0,0,0,0.55)",
			offset = { 0, 5 },
			scale = 1.0,
		},

		blur = {
			enabled = true,

			brightness = 1,
			contrast = 1,
			noise = 0,

			size = 10,
			passes = 3,

			special = true,
		},
	},

	animations = {
		enabled = true,
	},
})
