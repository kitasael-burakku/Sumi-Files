--    _____                .__  __
--   /     \   ____   ____ |__|/  |_  ___________  ______
--  /  \ /  \ /  _ \ /    \|  \   __\/  _ \_  __ \/  ___/
-- /    Y    (  <_> )   |  \  ||  | (  <_> )  | \/\___ \
-- \____|__  /\____/|___|  /__||__|  \____/|__|  /____  >
--         \/            \/                           \/

-- See https://wiki.hypr.land/configuring/core/monitors/
hl.monitor({
	output = "",
	mode = "highrr", -- highest refresh rate (here 1920x1080@200); pin "WxH@Hz" if you need one
	position = "0x0",
	scale = 1,
})

hl.config({ render = { cm_auto_hdr = 0, direct_scanout = 2 }}) -- 2 = auto: only for content marked as a game