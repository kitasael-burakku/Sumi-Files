-- ____   ____
-- \   \ /   /____ _______  ______
--  \   Y   /\__  \\_  __ \/  ___/
--   \     /  / __ \|  | \/\___ \
--    \___/  (____  /__|  /____  >
--                \/           \/

-- Variables compartidas entre módulos. Solo entra lo que usan DOS o más
-- archivos (o lo que se le pasa a private.lua): un valor que vive en un solo
-- módulo se queda ahí, al lado de lo que configura.
--
-- Uso:  local V = require("modules.vars")

local home = os.getenv("HOME") or "/home/user"

return {
    mainMod = "SUPER",

    -- Raíz de esta config: scripts, infinite_desktop, colors.lua.
    hyprDir = home .. "/.config/hypr",
}
